package com.webdigital.money2.routes;

import java.math.BigDecimal;
import java.util.List;

public record CollectionRoutePageResponse(
        List<CollectionRouteItemResponse> items,
        int page,
        int size,
        long totalItems,
        int totalPages,
        boolean hasNext,
        BigDecimal totalDebt,
        BigDecimal totalOverdueDebt) {
}
