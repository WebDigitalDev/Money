package com.webdigital.money2.reports;

import java.util.List;

public record AuditHistoryPageResponse(
        List<AuditHistoryItemResponse> items,
        int page,
        int size,
        boolean hasNext) {
}
