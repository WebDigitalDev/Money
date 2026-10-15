package com.webdigital.money2.chat;

import java.math.BigDecimal;
import java.time.LocalDateTime;

record ChatInstallmentSnapshot(
        long loanId,
        String installment,
        LocalDateTime dueAt,
        BigDecimal balance) {
}
