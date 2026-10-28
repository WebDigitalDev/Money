package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record LoanSummaryResponse(
        long id,
        String clientName,
        long regionId,
        String regionName,
        String cityName,
        LocalDateTime nextDueDate,
        LocalDateTime createdAt,
        String status,
        String statusColor,
        BigDecimal receivableAmount,
        BigDecimal receivedAmount,
        BigDecimal loanedAmount,
        BigDecimal profitAmount,
        String paymentType,
        boolean negotiated,
        String installmentProgress,
        boolean hasPendingPix,
        String collateral) {
}
