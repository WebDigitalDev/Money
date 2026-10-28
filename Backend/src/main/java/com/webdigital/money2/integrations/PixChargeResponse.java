package com.webdigital.money2.integrations;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record PixChargeResponse(
        long id,
        long loanId,
        Long installmentId,
        Long paymentId,
        long bankAccountId,
        String transactionId,
        BigDecimal amount,
        String status,
        String copyAndPaste,
        String qrCode,
        String location,
        String error,
        boolean paymentProcessed,
        LocalDateTime paidAt,
        LocalDateTime createdAt,
        LocalDateTime updatedAt) {
}
