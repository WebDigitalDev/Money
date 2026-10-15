package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record LoanPaymentResponse(
        long id,
        LocalDateTime date,
        BigDecimal amount,
        String note,
        boolean automatic,
        String approvalStatus,
        String type) {
}
