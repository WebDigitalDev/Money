package com.webdigital.money2.goals;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public record FinancialGoalRequest(
        @Positive Long regionId,
        List<@Positive Long> regionIds,
        @NotNull FinancialGoalType type,
        @NotNull @DecimalMin("0") BigDecimal targetAmount,
        @NotNull LocalDate startDate,
        @NotNull LocalDate endDate,
        Boolean repeatFrequency) {

    public FinancialGoalRequest(
            Long regionId,
            FinancialGoalType type,
            BigDecimal targetAmount,
            LocalDate startDate,
            LocalDate endDate) {
        this(regionId, null, type, targetAmount, startDate, endDate, false);
    }
}
