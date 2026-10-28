package com.webdigital.money2.routes;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record CollectionRouteItemResponse(
        long clientId,
        String clientName,
        long regionId,
        String regionName,
        BigDecimal totalDebt,
        BigDecimal overdueDebt,
        int overdueDays,
        int overdueLoans,
        String address,
        CollectionRouteStatus status,
        int collectionCount,
        LocalDateTime lastCollectionAt,
        Long routeId,
        Long collectorId,
        String collectorName,
        LocalDateTime assignedAt) {
}
