package com.webdigital.money2.chat;

import java.math.BigDecimal;

public record ChatLoanStatusResponse(
        long overdueCount,
        BigDecimal overdueAmount,
        long onTimeCount,
        BigDecimal onTimeAmount,
        long settledCount,
        BigDecimal settledAmount) {
}
