package com.webdigital.money2.clients;

import java.util.List;

public record ClientListResponse(
        List<ClientSummaryResponse> items,
        int page,
        int size,
        long totalItems,
        int totalPages,
        boolean hasNext,
        ClientStatusCountsResponse counts) {
}
