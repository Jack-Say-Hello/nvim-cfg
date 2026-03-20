# Credential Query Service 性能优化报告

> 生成时间：2026-03-20
> 目标：1000 并发查询，响应延迟 ≤ 200ms

---

## 目录

- [一、工程完整分析](#一工程完整分析)
  - [1.1 项目定位](#11-项目定位)
  - [1.2 技术栈](#12-技术栈)
  - [1.3 架构分析](#13-架构分析)
  - [1.4 API 端点](#14-api-端点)
  - [1.5 缓存设计](#15-缓存设计)
  - [1.6 凭证状态计算逻辑](#16-凭证状态计算逻辑)
  - [1.7 数据模型](#17-数据模型)
  - [1.8 配置分析](#18-配置分析)
  - [1.9 测试情况](#19-测试情况)
  - [1.10 代码质量观察](#110-代码质量观察)
- [二、首轮性能优化建议（全景）](#二首轮性能优化建议全景)
  - [2.1 P0：消除明确的性能杀手](#21-p0消除明确的性能杀手)
  - [2.2 P1：缓存层优化](#22-p1缓存层优化)
  - [2.3 P2：Tomcat 与线程模型](#23-p2tomcat-与线程模型)
  - [2.4 P3：数据库层](#24-p3数据库层)
  - [2.5 P4：JVM 调优](#25-p4jvm-调优)
  - [2.6 优化收益汇总表](#26-优化收益汇总表)
- [三、P0 三项修复实施](#三p0-三项修复实施)
  - [3.1 关闭 SQL 日志输出](#31-关闭-sql-日志输出)
  - [3.2 替换 System.out.println 为 Logger](#32-替换-systemoutprintln-为-logger)
  - [3.3 调大 HikariCP 连接池](#33-调大-hikaricp-连接池)
- [四、深度代码 Review（并发视角）](#四深度代码-review并发视角)
  - [4.1 致命级：open-in-view 问题](#41-致命级open-in-view-问题)
  - [4.2 高影响：同步日志 Appender](#42-高影响同步日志-appender)
  - [4.3 高影响：缓存穿透](#43-高影响缓存穿透)
  - [4.4 中等影响：Redis 序列化开销](#44-中等影响redis-序列化开销)
  - [4.5 中等影响：逐请求计时日志](#45-中等影响逐请求计时日志)
- [五、二轮修复实施](#五二轮修复实施)
  - [5.1 关闭 open-in-view](#51-关闭-open-in-view)
  - [5.2 异步日志配置](#52-异步日志配置)
  - [5.3 缓存穿透防护](#53-缓存穿透防护)
- [六、全部变更清单](#六全部变更清单)

---

## 一、工程完整分析

### 1.1 项目定位

Credential Query Service 是一个基于 Spring Boot 的**凭证查询微服务**，核心功能是根据序列号（sn）查询凭证信息（证书内容、有效期、状态），并通过 Redis 缓存加速查询，MySQL 作为持久化存储。典型的**读多写少**场景。

### 1.2 技术栈

| 组件 | 版本/实现 |
|------|----------|
| Java | 1.8 |
| Spring Boot | 2.5.14 |
| ORM | Spring Data JPA / Hibernate |
| 数据库 | MySQL 8+ (mysql-connector-java) |
| 缓存 | Redis (Lettuce 连接池) |
| 序列化 | Jackson |
| 构建工具 | Maven 3.9.11 (Wrapper) |

> Spring Boot 2.5.14 是 2.5.x 的最后一个维护版本，已于 2022 年停止维护。Java 8 虽然仍广泛使用，但也已进入长期维护期。

### 1.3 架构分析

#### 分层结构

```
Controller → Service → Repository → MySQL
                ↕
              Redis (缓存层)
```

标准三层架构，职责划分清晰：

- **CredentialController** (`controller/`) — 接收 HTTP 请求，调用 Service，返回响应。只有 3 个端点，逻辑很薄。
- **CredentialService** (`service/`) — 核心业务层，负责查询逻辑和缓存策略。
- **CredentialRepository** (`repository/`) — 继承 `JpaRepository`，只定义了一个自定义方法 `findBySn(String sn)`。

#### 源码目录结构

```
src/main/java/com/query_credential/credential_query/
├── CredentialQueryApplication.java   # Spring Boot 主入口
├── controller/
│   └── CredentialController.java     # REST API 端点
├── service/
│   └── CredentialService.java        # 业务逻辑 + 缓存策略
├── repository/
│   └── CredentialRepository.java     # Spring Data JPA 数据访问
├── entity/
│   └── Credential.java               # JPA 实体
├── dto/
│   └── CredentialResponse.java       # API 响应 DTO
├── model/
│   └── ResponseData.java             # 扩展响应模型（未使用）
└── config/
    └── RedisConfig.java              # Redis/Cache 配置
```

### 1.4 API 端点

所有端点在 `/api` 路径下：

| Method | Path | 功能 | 状态 |
|--------|------|------|------|
| GET | `/api/query_credential/{sn}` | 根据序列号查询凭证 | 已实现 |
| DELETE | `/api/cache/{sn}` | 清除指定凭证缓存 | 已实现 |
| GET | `/api/cache/stats` | 缓存统计 | **未实现**（返回占位文本） |

### 1.5 缓存设计

项目中存在**两套缓存实现并存**：

**方案一：声明式缓存（当前主用）**
- 通过 `@Cacheable(value = "credentialCache", key = "#sn")` 注解实现
- 由 `RedisConfig` 中配置的 `RedisCacheManager` 管理
- TTL：1 小时（`Duration.ofHours(1)`）
- 不缓存空值

**方案二：手动缓存（备用，未被调用）**
- `queryCredentialBySnWithManualCache()` 方法，直接使用 `RedisTemplate` 操作
- key 前缀：`credential:`
- TTL：24 小时
- 只缓存 statusCode == 200 的结果

两套方案独立存在，Controller 当前只调用了方案一。方案二是开发过程中的备选实现，保留在代码中但未被调用。

#### Redis 序列化配置

`RedisConfig` 中启用了 Jackson 默认类型信息写入：

```java
mapper.activateDefaultTyping(
    LaissezFaireSubTypeValidator.instance,
    ObjectMapper.DefaultTyping.NON_FINAL
);
```

`LaissezFaireSubTypeValidator` 不做任何类型校验，这在安全敏感场景下存在反序列化攻击风险，但在内部服务中通常问题不大。

### 1.6 凭证状态计算逻辑

`CredentialService.calculateCredentialStatus()` 根据当前时间和有效期动态计算状态：

```
当前时间 < validity_start  → "NotStarted"
当前时间 > validity_end    → "Expired"
数据库 status == "revoked" → "Revoked"
其他情况                   → "Valid"
```

**逻辑隐患**：判断顺序导致**已吊销但未到期的凭证**会先检查时间，如果时间在有效期内才会检查 revoked。而**已吊销但已过期的凭证**会返回 "Expired" 而不是 "Revoked"。通常吊销状态的优先级应该高于过期。

### 1.7 数据模型

**Credential 实体** — 对应 `credential` 表：

| 字段 | 类型 | 说明 |
|------|------|------|
| id | Integer | 自增主键 |
| sn | String (UNIQUE) | 序列号，查询核心标识 |
| cert | TEXT | 证书内容 |
| validity_start | LocalDateTime | 有效期起始 |
| validity_end | LocalDateTime | 有效期截止 |
| status | String | 状态，默认 "Valid" |

**CredentialResponse** — API 响应对象，实现了 `Serializable`（用于 Redis 存储），`toString()` 对 cert 做了脱敏处理。

**ResponseData** — 扩展版响应对象，比 CredentialResponse 多了 `issuerName` 和 `organizationId`。**未被任何代码引用**，是死代码。

### 1.8 配置分析

`application.properties` 要点：

| 配置项 | 值 | 备注 |
|--------|---|------|
| ddl-auto | validate | 不自动建表，表需手动维护 |
| show-sql | true | ⚠️ 生产环境严重性能问题 |
| format_sql | true | ⚠️ 额外格式化开销 |
| Redis max-active | 200 | 连接池上限 |
| HikariCP pool size | **未配置（默认10）** | ⚠️ 严重瓶颈 |
| server.port | 8080 | 服务端口 |
| 数据库密码 | 硬编码 | ⚠️ 安全隐患 |

### 1.9 测试情况

只有一个自动生成的上下文加载测试 `CredentialQueryApplicationTests`，没有任何业务逻辑测试。**测试覆盖率基本为零**。

### 1.10 代码质量观察

**做得好的地方：**
- 分层清晰，职责单一
- CredentialResponse 的 `toString()` 对证书内容脱敏
- 异常处理在 Service 层做了兜底
- Redis 连接池参数配置合理

**存在问题：**

| 问题 | 位置 | 影响 |
|------|------|------|
| Controller 使用 `System.out.println` | CredentialController.java:28 | 高并发同步锁竞争 |
| ResponseData 类未被使用 | model/ResponseData.java | 死代码 |
| 两套缓存实现并存 | CredentialService.java | 增加维护和理解成本 |
| 缺少输入校验 | Controller 层 | `{sn}` 无格式校验 |
| 没有统一异常处理 | 全局 | 缺少 `@ControllerAdvice` |
| cache/stats 未实现 | CredentialController.java:40 | 占位代码 |
| 无数据库迁移工具 | 全局 | 表结构变更需手动 SQL |
| Jackson 反序列化安全 | RedisConfig.java | `LaissezFaireSubTypeValidator` 不做类型限制 |

---

## 二、首轮性能优化建议（全景）

> 设计指标：1000 并发查询，响应延迟 ≤ 200ms

### 2.1 P0：消除明确的性能杀手

#### 2.1.1 关闭 SQL 日志输出

**文件**：`application.properties:33-34`

**问题代码**：
```properties
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.format_sql=true
```

**分析**：`show-sql=true` 会让每次 SQL 查询都通过 `System.out` 输出到控制台，`format_sql=true` 还要额外做格式化字符串拼接。`System.out` 内部持有全局锁（`synchronized`），在 1000 并发下所有线程竞争同一把锁，这一项就可以让延迟翻几倍。

#### 2.1.2 去掉 Controller 中的 System.out.println

**文件**：`CredentialController.java:28`

**问题代码**：
```java
System.out.println("查询耗时: " + (endTime - startTime) + "ms");
```

**分析**：和上面同理，`System.out.println` 是同步 I/O，内部持有 `PrintStream` 的全局锁。1000 并发下所有请求在这里串行化。字符串拼接（`+` 操作符）还会在每次调用时创建临时对象，增加 GC 压力。

**建议**：改用 SLF4J Logger，使用 `{}` 占位符避免字符串拼接。

#### 2.1.3 调大 HikariCP 连接池

**问题**：当前没有配置 HikariCP 参数，使用默认值 `maximumPoolSize=10`。

**分析**：这意味着缓存未命中时，最多只有 10 个请求能同时查数据库，其余全部排队等待。在 1000 并发下如果缓存命中率不是接近 100%，数据库连接池就是最大的瓶颈。

**建议配置**：
```properties
spring.datasource.hikari.maximum-pool-size=50
spring.datasource.hikari.minimum-idle=20
spring.datasource.hikari.connection-timeout=3000
```

### 2.2 P1：缓存层优化

#### 2.2.1 优化 Redis 序列化

**文件**：`RedisConfig.java:36`

**问题**：`activateDefaultTyping` 使用 `NON_FINAL`，给每个非 final 类型的字段都写入 `@class` 元数据。一个简单的 `CredentialResponse` 序列化后每个 String 字段都被包了一层类型数组，体积膨胀显著，增加 CPU 时间和网络传输量。

**建议**：使用 `Jackson2JsonRedisSerializer<CredentialResponse>` 指定具体类型，去掉 `activateDefaultTyping`。

#### 2.2.2 增加本地缓存（二级缓存）

**分析**：当前架构每次请求都要访问 Redis（即使缓存命中），在 1000 并发下意味着每秒 1000 次 Redis 网络往返。

**建议**：引入 Caffeine 作为一级本地缓存：

```
请求 → Caffeine (本地内存, μs级) → Redis (网络, ms级) → MySQL
```

对于凭证这种更新频率低的数据，本地缓存 TTL 设置短一些（如 5 分钟），就能大幅减少 Redis 访问。

#### 2.2.3 缓存预热

如果凭证数据量可控（比如几万条），启动时将热点数据预加载到缓存，避免冷启动时大量请求穿透到数据库。

### 2.3 P2：Tomcat 与线程模型

**问题**：Spring Boot 内嵌 Tomcat 默认 `maxThreads=200`。1000 并发下如果每个请求耗时稍长，200 个线程会被占满，后续请求排队。

**建议**：
```properties
server.tomcat.threads.max=500
server.tomcat.threads.min-spare=50
server.tomcat.accept-count=200
```

但线程数不是越大越好，过多线程会导致上下文切换开销增大，需要配合连接池大小综合调整。

### 2.4 P3：数据库层

#### 2.4.1 确认 sn 字段有索引

JPA 中 `@Column(unique = true)` 在 `ddl-auto=validate` 模式下不会自动建索引，只做校验。需要在数据库中确认：

```sql
SHOW INDEX FROM credential WHERE Column_name = 'sn';
```

如果没有索引，每次查询都是全表扫描，高并发下致命。

#### 2.4.2 按需查询字段

当前 `findBySn` 会加载整行数据，包括可能很大的 `cert` (TEXT) 字段。如果部分场景不需要 cert，可以用投影查询减少传输量。但当前接口 cert 是必须返回的，优先级较低。

### 2.5 P4：JVM 调优

`启动命令.txt` 中的 G1GC 配置基本合理，可优化点：

```bash
java -jar -Xmx4g -Xms4g \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=100 \          # 降到100ms，给200ms目标留余量
  -XX:InitiatingHeapOccupancyPercent=30 \
  -XX:+AlwaysPreTouch \               # 启动时预分配内存，避免运行时缺页
  -XX:+ParallelRefProcEnabled \       # 并行引用处理
  -Xloggc:/path/to/gc.log \          # GC日志写文件，不要写stdout
  target/credential-query-1.0.0.jar
```

注意 `-XX:+PrintGC` 在 Java 8 中默认写到 stdout，高并发下同样有锁竞争问题，应改用 `-Xloggc` 输出到文件。

### 2.6 优化收益汇总表

| 优先级 | 优化项 | 预期收益 |
|--------|--------|----------|
| **P0** | 关闭 show-sql 和 format_sql | 消除最大的同步阻塞点 |
| **P0** | 去掉 System.out.println | 消除 Controller 层的锁竞争 |
| **P0** | 调大 HikariCP 连接池 | 消除数据库访问的排队瓶颈 |
| **P1** | 简化 Redis 序列化 | 减少缓存读写的 CPU 和网络开销 |
| **P1** | 增加 Caffeine 本地缓存 | 大幅减少 Redis 网络往返 |
| **P2** | 调整 Tomcat 线程池 | 提升并发承载能力 |
| **P3** | 确认 sn 字段索引 | 避免缓存穿透时的全表扫描 |
| **P4** | GC 日志写文件 + 参数微调 | 消除 GC 日志锁竞争，降低尾延迟 |

---

## 三、P0 三项修复实施

### 3.1 关闭 SQL 日志输出

**修改文件**：`src/main/resources/application.properties`

**变更内容**：

```diff
- spring.jpa.show-sql=true
+ spring.jpa.show-sql=false
  spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQLDialect
  spring.jpa.properties.hibernate.jdbc.time_zone=Asia/Shanghai
- spring.jpa.properties.hibernate.format_sql=true
+ spring.jpa.properties.hibernate.format_sql=false
```

**效果**：消除每次 SQL 查询时的 stdout 同步锁竞争和格式化字符串开销。

### 3.2 替换 System.out.println 为 Logger

**修改文件**：`src/main/java/.../controller/CredentialController.java`

**变更内容**：

```diff
  package com.query_credential.credential_query.controller;

+ import org.slf4j.Logger;
+ import org.slf4j.LoggerFactory;
  import org.springframework.beans.factory.annotation.Autowired;
  // ... 其余 import 不变

  @RestController
  @RequestMapping("/api")
  public class CredentialController {

+     private static final Logger logger = LoggerFactory.getLogger(CredentialController.class);
+
      @Autowired
      private CredentialService credentialService;

      @GetMapping("/query_credential/{sn}")
      public ResponseEntity<CredentialResponse> queryCredential(@PathVariable String sn) {
          long startTime = System.currentTimeMillis();

          CredentialResponse response = credentialService.queryCredentialBySn(sn);

          long endTime = System.currentTimeMillis();
-         System.out.println("查询耗时: " + (endTime - startTime) + "ms");
+         logger.info("查询耗时: {}ms, sn: {}", endTime - startTime, sn);

          return ResponseEntity.status(response.getStatusCode()).body(response);
      }
```

**效果**：
- 消除 `System.out.println` 的全局锁竞争
- 使用 `{}` 占位符替代字符串拼接，避免临时对象创建
- 日志中同时输出 sn，便于排查慢查询

### 3.3 调大 HikariCP 连接池

**修改文件**：`src/main/resources/application.properties`

**新增配置**：

```properties
# HikariCP 连接池配置
spring.datasource.hikari.maximum-pool-size=50
spring.datasource.hikari.minimum-idle=20
spring.datasource.hikari.connection-timeout=3000
spring.datasource.hikari.idle-timeout=60000
spring.datasource.hikari.max-lifetime=1800000
```

**参数说明**：

| 参数 | 值 | 含义 |
|------|---|------|
| maximum-pool-size | 50 | 从默认 10 提升到 50，允许更多并发数据库访问 |
| minimum-idle | 20 | 保持 20 个空闲连接，减少突发流量时的建连延迟 |
| connection-timeout | 3000ms | 获取连接超时 3 秒 |
| idle-timeout | 60000ms | 空闲连接 60 秒后回收 |
| max-lifetime | 1800000ms | 连接最大存活 30 分钟，避免 MySQL `wait_timeout` 导致连接被服务端断开 |

---

## 四、深度代码 Review（并发视角）

> P0 修复后，对 `credential_query` 包下所有代码逐文件、逐行重新审查，专注于 1000 并发场景下的延迟瓶颈。

### 4.1 致命级：open-in-view 问题

**问题本质**：Spring Boot 2.5 默认 `spring.jpa.open-in-view=true`，会注册 `OpenEntityManagerInViewInterceptor`，在**每个 HTTP 请求进入时就从 HikariCP 获取一个数据库连接，直到请求结束才归还**。

**影响分析**：

当前的请求流程实际上是：

```
请求进入
  → 获取 DB 连接（open-in-view）     ← 即使缓存命中也会拿
  → @Cacheable 检查 Redis
  → 命中 → 直接返回                   ← DB 连接白白持有
  → 请求结束 → 归还 DB 连接
```

在 1000 并发下，即使 Redis 缓存命中率 99%，1000 个请求**全部**都在竞争 50 个数据库连接。990 个本不需要数据库的请求也在排队等连接，这直接导致延迟飙升。

**这是当前代码中隐藏最深、影响最大的问题**。单独这一项修复就可能让 P99 延迟降低一个数量级。

### 4.2 高影响：同步日志 Appender

**问题本质**：项目中没有 `logback.xml` 或 `logback-spring.xml`，使用 Spring Boot 默认的 logback 配置——**同步 ConsoleAppender**。

**影响分析**：

每次 `logger.info()` 调用都直接写 stdout，内部持有锁。虽然 `@Cacheable` 缓存命中时不会进入方法体（直接返回），但缓存未命中时一次请求最多触发：

| 位置 | 日志调用 |
|------|---------|
| CredentialService.java:39 | `logger.info("缓存未命中，查询数据库: {}", sn)` |
| CredentialService.java:55 | `logger.info("数据库查询成功，序列号: {}", sn)` |
| CredentialController.java:32 | `logger.info("查询耗时: {}ms, sn: {}", ...)` |

共 **3 次同步日志写入**。在缓存冷启动或穿透场景下，这仍然是严重瓶颈。

### 4.3 高影响：缓存穿透

**问题本质**：`RedisConfig.java:63` 配置了 `.disableCachingNullValues()`。

**影响分析**：

当前 `@Cacheable` 机制下：
- 查询存在的 sn → 返回 `CredentialResponse(200, ...)` → **会被缓存**（非 null）
- 查询不存在的 sn → 返回 `CredentialResponse(404, ...)` → **也会被缓存**（非 null，TTL 与正常数据相同 = 1 小时）
- 查询异常 → 返回 `CredentialResponse(500, ...)` → **也会被缓存**（这是个问题：错误结果缓存 1 小时）

真正的穿透风险在于：如果有人用大量**不同的**随机无效 sn 发起请求，每个新 sn 第一次都必须穿透到数据库。虽然同一个 sn 的后续请求会命中缓存，但海量不同 sn 意味着持续的数据库压力。

此外，500 错误也会被缓存 1 小时，意味着临时的数据库故障恢复后，错误响应仍然会持续返回。

### 4.4 中等影响：Redis 序列化开销

**问题本质**：`RedisConfig.java:36` 和 `55` 两处使用了 `activateDefaultTyping(NON_FINAL)`。

**影响分析**：

一个 `CredentialResponse` 序列化后的实际 JSON 结构：

```json
["com.query_credential.credential_query.dto.CredentialResponse", {
  "statusCode": 200,
  "message": ["java.lang.String", "Credential found"],
  "sn": ["java.lang.String", "ABC123"],
  "cert": ["java.lang.String", "...大量证书内容..."],
  "status": ["java.lang.String", "Valid"]
}]
```

每个 String 字段都被包了一层类型数组，数据体积膨胀。如果 cert 字段内容较大（证书通常几 KB），序列化后体积增长显著，增加了：
- Jackson 序列化/反序列化的 CPU 时间
- Redis 网络传输量
- Redis 内存占用

### 4.5 中等影响：逐请求计时日志

**文件**：`CredentialController.java:27-32`

```java
long startTime = System.currentTimeMillis();
// ...
long endTime = System.currentTimeMillis();
logger.info("查询耗时: {}ms, sn: {}", endTime - startTime, sn);
```

`System.currentTimeMillis()` 本身开销极小，但配合同步日志输出，每个请求都产生一条日志。在 1000 并发下这是不必要的负担。建议生产环境改用 `logger.debug` 级别，只在需要排查时通过动态调整日志级别开启。

### 4.6 发现汇总

| 序号 | 问题 | 位置 | 影响级别 |
|------|------|------|---------|
| 1 | open-in-view=true，缓存命中也占 DB 连接 | 默认配置（未显式关闭） | **致命** |
| 2 | 同步 ConsoleAppender，日志写入持锁 | 无 logback-spring.xml | **高** |
| 3 | 缓存穿透 + 500 错误被长期缓存 | Service + RedisConfig | **高** |
| 4 | Jackson NON_FINAL 序列化膨胀 | RedisConfig.java:36,55 | **中** |
| 5 | 每请求计时日志 | CredentialController.java:27-32 | **中** |

---

## 五、二轮修复实施

> 针对深度 Review 发现的前三项（致命 + 高影响）进行修复。

### 5.1 关闭 open-in-view

**修改文件**：`src/main/resources/application.properties`

**变更内容**：

```diff
  # JPA 配置
+ spring.jpa.open-in-view=false
  spring.jpa.hibernate.ddl-auto=validate
```

**效果**：

| 场景 | 修复前 | 修复后 |
|------|--------|--------|
| 缓存命中 | 获取 DB 连接 → 查 Redis → 命中 → 返回 → 归还连接 | 查 Redis → 命中 → 返回（不碰 DB 连接） |
| 缓存未命中 | 获取 DB 连接 → 查 Redis → 未命中 → 查 DB → 返回 → 归还连接 | 查 Redis → 未命中 → 获取 DB 连接 → 查 DB → 归还连接 → 返回 |

关闭后，只有真正需要查数据库的请求才会获取连接。假设缓存命中率 90%，1000 并发下只有 100 个请求竞争 DB 连接（而不是 1000 个），连接池压力下降 10 倍。

### 5.2 异步日志配置

**新增文件**：`src/main/resources/logback-spring.xml`

**完整内容**：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>

    <!-- 实际的控制台输出 appender -->
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss} - %msg%n</pattern>
        </encoder>
    </appender>

    <!-- 异步包裹，日志写入不阻塞业务线程 -->
    <appender name="ASYNC_CONSOLE" class="ch.qos.logback.classic.AsyncAppender">
        <!-- 队列容量，默认256，高并发下需要加大 -->
        <queueSize>1024</queueSize>
        <!-- 队列剩余容量低于此值时丢弃 TRACE/DEBUG/INFO 日志，0 表示永不丢弃 -->
        <discardingThreshold>0</discardingThreshold>
        <!-- 不提取调用者信息，避免每次日志都生成堆栈（性能关键） -->
        <includeCallerData>false</includeCallerData>
        <!-- 队列满时不阻塞业务线程，直接丢弃 -->
        <neverBlock>true</neverBlock>
        <appender-ref ref="CONSOLE"/>
    </appender>

    <!-- 文件输出 appender（生产环境建议使用） -->
    <appender name="FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>logs/credential-query.log</file>
        <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
            <fileNamePattern>logs/credential-query.%d{yyyy-MM-dd}.%i.log</fileNamePattern>
            <maxFileSize>100MB</maxFileSize>
            <maxHistory>7</maxHistory>
            <totalSizeCap>1GB</totalSizeCap>
        </rollingPolicy>
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>

    <appender name="ASYNC_FILE" class="ch.qos.logback.classic.AsyncAppender">
        <queueSize>1024</queueSize>
        <discardingThreshold>0</discardingThreshold>
        <includeCallerData>false</includeCallerData>
        <neverBlock>true</neverBlock>
        <appender-ref ref="FILE"/>
    </appender>

    <logger name="com.query_credential" level="INFO"/>
    <logger name="org.springframework" level="WARN"/>
    <logger name="org.hibernate" level="ERROR"/>

    <root level="INFO">
        <appender-ref ref="ASYNC_CONSOLE"/>
        <appender-ref ref="ASYNC_FILE"/>
    </root>

</configuration>
```

**关键参数说明**：

| 参数 | 值 | 作用 |
|------|---|------|
| queueSize | 1024 | 异步队列容量，容纳突发日志量 |
| neverBlock | true | 队列满时丢弃日志而不阻塞业务线程（**性能优先**） |
| includeCallerData | false | 不生成调用者堆栈信息，避免反射开销 |
| discardingThreshold | 0 | 不提前丢弃任何级别的日志 |

**效果**：业务线程调用 `logger.info()` 时只需将日志事件放入内存队列即返回（纳秒级），实际的 I/O 写入由独立的后台线程异步完成。1000 并发下消除了日志输出的锁竞争。

### 5.3 缓存穿透防护

**修改文件**：`src/main/java/.../service/CredentialService.java`

**核心改动思路**：去掉 `@Cacheable` 注解，改用 `RedisTemplate` 手动控制缓存逻辑，实现分层 TTL 策略。

**改动前后对比**：

| 改动点 | 之前 | 之后 |
|--------|------|------|
| 缓存方式 | `@Cacheable` 注解（Spring 托管） | `RedisTemplate` 手动控制 |
| 200 结果 TTL | 1 小时（CacheManager 统一配置） | 1 小时 |
| 404 结果 TTL | 1 小时（和正常数据相同） | **5 分钟**（短 TTL 防穿透） |
| 500 错误 | 缓存 1 小时（严重问题） | **不缓存**（下次可重试） |
| Redis 异常 | 直接抛出，影响主流程 | **静默降级**，回退查数据库 |
| 备用方法 | `queryCredentialBySnWithManualCache` 残留 | 已删除，统一为一套实现 |

**修改后完整代码**：

```java
@Service
public class CredentialService {

    private static final Logger logger = LoggerFactory.getLogger(CredentialService.class);

    @Autowired
    private CredentialRepository credentialRepository;

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    private static final String CACHE_KEY_PREFIX = "credential:";
    private static final long CACHE_EXPIRE_HOURS = 1;          // 正常结果缓存1小时
    private static final long CACHE_NULL_EXPIRE_MINUTES = 5;   // 空结果缓存5分钟，防穿透

    /**
     * 查询凭证信息，带缓存穿透防护
     * - 200 结果：缓存1小时
     * - 404 结果：缓存5分钟短TTL，防止同一个无效sn反复打到数据库
     * - 500 错误：不缓存
     */
    public CredentialResponse queryCredentialBySn(String sn) {
        String cacheKey = CACHE_KEY_PREFIX + sn;

        // 1. 查缓存
        try {
            CredentialResponse cachedResponse =
                (CredentialResponse) redisTemplate.opsForValue().get(cacheKey);
            if (cachedResponse != null) {
                return cachedResponse;
            }
        } catch (Exception e) {
            logger.warn("Redis读取失败，降级查库: {}", e.getMessage());
        }

        logger.info("缓存未命中，查询数据库: {}", sn);

        // 2. 查数据库
        try {
            Optional<Credential> credentialOpt = credentialRepository.findBySn(sn);

            if (credentialOpt.isPresent()) {
                Credential credential = credentialOpt.get();
                String status = calculateCredentialStatus(credential);

                CredentialResponse response = new CredentialResponse(
                    200, "Credential found",
                    credential.getSn(), credential.getCert(), status
                );

                // 正常结果缓存1小时
                setCacheQuietly(cacheKey, response, CACHE_EXPIRE_HOURS, TimeUnit.HOURS);
                return response;
            } else {
                CredentialResponse response =
                    new CredentialResponse(404, "Credential not found");
                logger.warn("凭证未找到，序列号: {}", sn);

                // 空结果缓存5分钟，防止穿透
                setCacheQuietly(cacheKey, response, CACHE_NULL_EXPIRE_MINUTES, TimeUnit.MINUTES);
                return response;
            }

        } catch (Exception e) {
            logger.error("查询凭证失败，序列号: {}, 错误: {}", sn, e.getMessage());
            // 500 错误不缓存，下次请求可以重试
            return new CredentialResponse(500, "Query error: " + e.getMessage());
        }
    }

    /**
     * 写缓存，Redis异常时静默降级，不影响主流程
     */
    private void setCacheQuietly(String key, CredentialResponse response,
                                  long timeout, TimeUnit unit) {
        try {
            redisTemplate.opsForValue().set(key, response, timeout, unit);
        } catch (Exception e) {
            logger.warn("Redis写入失败: {}", e.getMessage());
        }
    }

    /**
     * 清除缓存
     */
    public void evictCredentialCache(String sn) {
        String cacheKey = CACHE_KEY_PREFIX + sn;
        try {
            redisTemplate.delete(cacheKey);
            logger.info("清除缓存，序列号: {}", sn);
        } catch (Exception e) {
            logger.warn("清除缓存失败，序列号: {}, 错误: {}", sn, e.getMessage());
        }
    }

    // calculateCredentialStatus 方法不变...
}
```

**效果**：
- 同一个无效 sn 在 5 分钟内只查一次数据库，大幅降低穿透流量
- 数据库临时故障恢复后，错误不会被缓存，下次请求立即可用
- Redis 故障时自动降级查数据库，服务不中断

---

## 六、全部变更清单

### 修改的文件

| 文件 | 轮次 | 变更内容 |
|------|------|---------|
| `src/main/resources/application.properties` | P0 | `show-sql=false`, `format_sql=false` |
| `src/main/resources/application.properties` | P0 | 新增 HikariCP 连接池 5 项参数 |
| `src/main/resources/application.properties` | 二轮 | 新增 `spring.jpa.open-in-view=false` |
| `src/main/java/.../controller/CredentialController.java` | P0 | `System.out.println` → SLF4J Logger |
| `src/main/java/.../service/CredentialService.java` | 二轮 | 重写缓存逻辑：手动 RedisTemplate + 分层 TTL + 降级 |

### 新增的文件

| 文件 | 轮次 | 说明 |
|------|------|------|
| `src/main/resources/logback-spring.xml` | 二轮 | 异步日志配置（AsyncAppender + 文件滚动） |

### 删除/清理的代码

| 内容 | 文件 | 说明 |
|------|------|------|
| `queryCredentialBySnWithManualCache()` 方法 | CredentialService.java | 未被调用的备用手动缓存实现 |
| `updateCredentialCache()` 方法 | CredentialService.java | 依赖 `@CachePut` 注解，已不再适用 |
| `@Cacheable` / `@CacheEvict` / `@CachePut` 注解 | CredentialService.java | 改为手动 RedisTemplate 控制 |

### 仍待优化（未实施）

| 优化项 | 优先级 | 说明 |
|--------|--------|------|
| 简化 Redis 序列化（去掉 NON_FINAL） | P1 | 减少序列化体积和 CPU 开销 |
| 增加 Caffeine 本地二级缓存 | P1 | 消除 Redis 网络往返 |
| 调整 Tomcat 线程池 | P2 | 提升并发承载能力 |
| 确认 sn 字段数据库索引 | P3 | 避免全表扫描 |
| GC 日志写文件 + JVM 参数微调 | P4 | 降低尾延迟 |
| Controller 计时日志改为 debug 级别 | 低 | 减少生产环境日志量 |
