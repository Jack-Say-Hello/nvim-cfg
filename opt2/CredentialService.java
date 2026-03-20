package com.query_credential.credential_query.service;

import java.time.LocalDateTime;
import java.util.Optional;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import com.query_credential.credential_query.dto.CredentialResponse;
import com.query_credential.credential_query.entity.Credential;
import com.query_credential.credential_query.repository.CredentialRepository;

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
            CredentialResponse cachedResponse = (CredentialResponse) redisTemplate.opsForValue().get(cacheKey);
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
                    credential.getSn(),
                    credential.getCert(),
                    status
                );

                // 正常结果缓存1小时
                setCacheQuietly(cacheKey, response, CACHE_EXPIRE_HOURS, TimeUnit.HOURS);
                return response;
            } else {
                CredentialResponse response = new CredentialResponse(404, "Credential not found");
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
    private void setCacheQuietly(String key, CredentialResponse response, long timeout, TimeUnit unit) {
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

    /**
     * 计算凭证状态
     */
    private String calculateCredentialStatus(Credential credential) {
        LocalDateTime currentTime = LocalDateTime.now();
        String status = "Valid";

        if (currentTime.isBefore(credential.getValidityStart())) {
            status = "NotStarted";
        } else if (currentTime.isAfter(credential.getValidityEnd())) {
            status = "Expired";
        } else if ("revoked".equalsIgnoreCase(credential.getStatus())) {
            status = "Revoked";
        }

        return status;
    }
}
