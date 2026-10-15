package com.webdigital.money2.reports;

import java.time.LocalDateTime;

public record AuditHistoryItemResponse(
        Long id,
        String entityName,
        String username,
        Long entityId,
        String operation,
        String description,
        LocalDateTime timestamp,
        Long regionId,
        String regionDescription,
        String value) {
}
