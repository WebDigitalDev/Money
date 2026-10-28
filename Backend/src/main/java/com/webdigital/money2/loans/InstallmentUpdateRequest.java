package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDate;

public record InstallmentUpdateRequest(
        LocalDate dueDate,
        BigDecimal amount,
        BigDecimal interestAmount,
        String dueDateNote) {
}
