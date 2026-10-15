package com.webdigital.money2.chat;

import java.math.BigDecimal;
import java.time.LocalDateTime;

record ChatPaymentSnapshot(
        long loanId,
        String installment,
        LocalDateTime paidAt,
        BigDecimal amount,
        String type) {
}
