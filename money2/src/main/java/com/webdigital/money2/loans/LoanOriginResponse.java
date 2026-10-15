package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record LoanOriginResponse(
        long id,
        String clientName,
        String regionName,
        String cityName,
        LocalDateTime nextDueDate,
        String status,
        String statusColor,
        BigDecimal loanedAmount,
        BigDecimal receivedAmount,
        BigDecimal receivableAmount,
        BigDecimal profitAmount,
        String paymentType,
        boolean negotiated) {
}
