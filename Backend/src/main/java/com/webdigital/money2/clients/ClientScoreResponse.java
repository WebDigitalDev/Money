package com.webdigital.money2.clients;

import java.math.BigDecimal;

public record ClientScoreResponse(
        int points,
        long overdueDays,
        BigDecimal totalDebt) {
}
