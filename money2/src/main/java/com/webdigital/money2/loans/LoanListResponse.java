package com.webdigital.money2.loans;

import java.util.List;

public record LoanListResponse(
        List<LoanSummaryResponse> items,
        int page,
        int size,
        long totalItems,
        int totalPages,
        boolean hasNext,
        LoanTotalsResponse totals) {
}
