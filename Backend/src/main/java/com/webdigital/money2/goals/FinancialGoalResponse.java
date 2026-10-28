package com.webdigital.money2.goals;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

public record FinancialGoalResponse(
        Long id,
        Long regionId,
        String regionName,
        FinancialGoalType type,
        BigDecimal targetAmount,
        BigDecimal achievedAmount,
        BigDecimal remainingAmount,
        BigDecimal percentage,
        LocalDate startDate,
        LocalDate endDate,
        FinancialGoalStatus status,
        LocalDateTime createdAt,
        LocalDateTime updatedAt,
        boolean canManage,
        List<Long> regionIds,
        List<String> regionNames,
        ClientGoalStats clients,
        boolean repeatFrequency) {
    public FinancialGoalResponse(Long id, Long regionId, String regionName, FinancialGoalType type,
            BigDecimal targetAmount, BigDecimal achievedAmount, BigDecimal remainingAmount, BigDecimal percentage,
            LocalDate startDate, LocalDate endDate, FinancialGoalStatus status, LocalDateTime createdAt,
            LocalDateTime updatedAt, boolean canManage, List<Long> regionIds, List<String> regionNames) {
        this(id, regionId, regionName, type, targetAmount, achievedAmount, remainingAmount, percentage,
                startDate, endDate, status, createdAt, updatedAt, canManage, regionIds, regionNames, null, false);
    }
}
