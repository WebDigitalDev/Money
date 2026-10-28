package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDate;

public record InterestOnlyPaymentRequest(
        Long installmentId,
        BigDecimal amount,
        LocalDate date,
        LocalDate newDueDate,
        String note) {
}
