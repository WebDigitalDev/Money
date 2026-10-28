package com.webdigital.money2.routes;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record CollectionHistoryResponse(
        long id,
        long clientId,
        long regionId,
        String regionName,
        long userId,
        String collectorName,
        String observation,
        BigDecimal debtAmount,
        int overdueDays,
        String attachmentName,
        String attachmentContentType,
        Long attachmentSize,
        boolean attachmentAvailable,
        LocalDateTime createdAt) {
}
