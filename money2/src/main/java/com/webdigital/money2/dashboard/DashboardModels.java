package com.webdigital.money2.dashboard;

import com.webdigital.money2.goals.FinancialGoalResponse;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public final class DashboardModels {

    private DashboardModels() {
    }

    public record RegionOption(long id, String name) {
    }

    public record Metrics(
            long overdueClients,
            long overdueLoans,
            BigDecimal overdueAmount,
            BigDecimal receivedTodayAmount,
            long receivedTodayPayments,
            BigDecimal profitTodayAmount,
            long settledTodayLoans,
            long renewedTodayLoans,
            long overdueInstallments,
            long oldestOverdueDays,
            long dueTodayLoans,
            long dueTodayInstallments,
            BigDecimal dueTodayAmount) {
    }

    public record FinancialPoint(
            LocalDate date,
            BigDecimal loanedAmount,
            BigDecimal receivedAmount,
            BigDecimal overdueAmount,
            BigDecimal profitAmount) {
    }

    public record FinancialSummary(
            BigDecimal loanedAmount,
            BigDecimal receivedAmount,
            BigDecimal overdueAmount,
            BigDecimal profitAmount,
            List<FinancialPoint> points) {
    }

    public record DueTodayLoan(
            long loanId,
            String clientName,
            String regionName,
            String paymentType,
            BigDecimal amount) {
    }

    public record Response(
            String userName,
            LocalDate date,
            long selectedRegionId,
            String selectedRegionName,
            List<Long> selectedRegionIds,
            List<RegionOption> regions,
            Metrics metrics,
            FinancialSummary financial,
            List<FinancialGoalResponse> activeGoals,
            List<DueTodayLoan> dueToday) {
    }
}
