package com.webdigital.money2.chat;

import java.math.BigDecimal;

public record ChatFinancialSummaryResponse(
        long clients,
        long openLoans,
        BigDecimal loaned,
        BigDecimal received,
        BigDecimal receivable,
        BigDecimal overdue,
        BigDecimal profit) {
}
