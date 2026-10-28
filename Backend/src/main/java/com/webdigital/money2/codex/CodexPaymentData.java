package com.webdigital.money2.codex;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record CodexPaymentData(
        long paymentId,
        LocalDateTime paidAt,
        BigDecimal amount,
        String type,
        long contractId,
        String installment,
        long clientId,
        String clientName,
        long regionId,
        String regionName) {
}
