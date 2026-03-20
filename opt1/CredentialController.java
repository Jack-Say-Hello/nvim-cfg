package com.query_credential.credential_query.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.query_credential.credential_query.dto.CredentialResponse;
import com.query_credential.credential_query.service.CredentialService;

@RestController
@RequestMapping("/api")
public class CredentialController {

    private static final Logger logger = LoggerFactory.getLogger(CredentialController.class);

    @Autowired
    private CredentialService credentialService;

    @GetMapping("/query_credential/{sn}")
    public ResponseEntity<CredentialResponse> queryCredential(@PathVariable String sn) {
        long startTime = System.currentTimeMillis();

        CredentialResponse response = credentialService.queryCredentialBySn(sn);

        long endTime = System.currentTimeMillis();
        logger.info("查询耗时: {}ms, sn: {}", endTime - startTime, sn);

        return ResponseEntity.status(response.getStatusCode()).body(response);
    }
    
    @DeleteMapping("/cache/{sn}")
    public ResponseEntity<String> clearCache(@PathVariable String sn) {
        credentialService.evictCredentialCache(sn);
        return ResponseEntity.ok("缓存已清除: " + sn);
    }
    
    @GetMapping("/cache/stats")
    public ResponseEntity<String> getCacheStats() {
        return ResponseEntity.ok("缓存统计信息（需要实现）");
    }
}