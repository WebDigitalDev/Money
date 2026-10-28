package com.webdigital.money2.codex;

import java.math.BigDecimal;
import java.math.RoundingMode;

public record CodexRegionSummary(
        long regionId,
        String regionName,
        long clients,
        long openLoans,
        long overdueLoans,
        long onTimeLoans,
        long settledLoans,
        BigDecimal loaned,
        BigDecimal received,
        BigDecimal receivable,
        BigDecimal overdue,
        BigDecimal dueToday,
        BigDecimal profit,
        BigDecimal delinquencyPercentage) {

    public CodexRegionSummary(
            long regionId,
            String regionName,
            long clients,
            long openLoans,
            long overdueLoans,
            long onTimeLoans,
            long settledLoans,
            BigDecimal loaned,
            BigDecimal received,
            BigDecimal receivable,
            BigDecimal overdue,
            BigDecimal dueToday,
            BigDecimal profit) {
        this(
                regionId,
                regionName,
                clients,
                openLoans,
                overdueLoans,
                onTimeLoans,
                settledLoans,
                money(loaned),
                money(received),
                money(receivable),
                money(overdue),
                money(dueToday),
                money(profit),
                percentage(overdue, receivable));
    }

    private static BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value)
                .setScale(2, RoundingMode.HALF_UP);
    }

    private static BigDecimal percentage(BigDecimal value, BigDecimal total) {
        BigDecimal safeTotal = total == null ? BigDecimal.ZERO : total;
        if (safeTotal.signum() <= 0) return BigDecimal.ZERO.setScale(2);
        return (value == null ? BigDecimal.ZERO : value)
                .multiply(BigDecimal.valueOf(100))
                .divide(safeTotal, 2, RoundingMode.HALF_UP);
    }
}
