package com.webdigital.money2.chat;

import java.math.BigDecimal;
import java.time.LocalDate;

public record ChatLoanResponse(
        long loanId,
        String clientName,
        String regionName,
        String paymentType,
        LocalDate dueDate,
        long installmentCount,
        BigDecimal amount,
        String status) {
}
