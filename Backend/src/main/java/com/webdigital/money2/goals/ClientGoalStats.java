package com.webdigital.money2.goals;

import java.math.BigDecimal;
import java.math.RoundingMode;

public record ClientGoalStats(long active, long onTime, long overdue, long newClients) {
    public static final ClientGoalStats EMPTY = new ClientGoalStats(0, 0, 0, 0);
    public BigDecimal onTimePercentage() { return percent(onTime); }
    public BigDecimal overduePercentage() { return percent(overdue); }
    private BigDecimal percent(long count) {
        return active == 0 ? BigDecimal.ZERO : BigDecimal.valueOf(count * 100)
                .divide(BigDecimal.valueOf(active), 2, RoundingMode.HALF_UP);
    }
    public BigDecimal achieved(FinancialGoalType type) {
        return switch (type) {
            case CLIENTES_ATIVOS -> BigDecimal.valueOf(newClients);
            case CLIENTES_EM_DIA -> onTimePercentage();
            case CLIENTES_ATRASO -> overduePercentage();
            default -> throw new IllegalArgumentException("Indicador não é de clientes");
        };
    }
    public boolean reached(FinancialGoalType type, BigDecimal target) {
        if (type.isPercentage() && active == 0) return false;
        return type == FinancialGoalType.CLIENTES_ATRASO
                ? achieved(type).compareTo(target) <= 0 : achieved(type).compareTo(target) >= 0;
    }
    public BigDecimal progress(FinancialGoalType type, BigDecimal target) {
        if (type.isPercentage() && active == 0) return BigDecimal.ZERO;
        if (type == FinancialGoalType.CLIENTES_ATRASO) {
            if (reached(type, target)) return BigDecimal.valueOf(100);
            return BigDecimal.valueOf(100).subtract(overduePercentage()).multiply(BigDecimal.valueOf(100))
                    .divide(BigDecimal.valueOf(100).subtract(target), 2, RoundingMode.HALF_UP);
        }
        return target.signum() == 0 ? BigDecimal.ZERO : achieved(type).multiply(BigDecimal.valueOf(100))
                .divide(target, 2, RoundingMode.HALF_UP);
    }
}
