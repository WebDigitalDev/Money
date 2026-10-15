package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDate;

public record PaymentRequest(
        BigDecimal amount,
        LocalDate date,
        String note) {
}
