package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDate;

public record LoanNegotiationRequest(
        BigDecimal debtAmount,
        BigDecimal additionalAmount,
        BigDecimal interestAmount,
        BigDecimal interestPercent,
        Integer installmentCount,
        LocalDate firstDueDate,
        String paymentType,
        String notes) {
}
