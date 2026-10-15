package com.webdigital.money2.goals;

import org.junit.jupiter.api.Test;
import java.math.BigDecimal;
import static org.assertj.core.api.Assertions.assertThat;

class ClientGoalStatsTest {
    @Test void onTimeTargetIsAMinimum() {
        ClientGoalStats stats=new ClientGoalStats(10,8,2,3);
        assertThat(stats.onTimePercentage()).isEqualByComparingTo("80");
        assertThat(stats.reached(FinancialGoalType.CLIENTES_EM_DIA,new BigDecimal("70"))).isTrue();
        assertThat(stats.reached(FinancialGoalType.CLIENTES_EM_DIA,new BigDecimal("90"))).isFalse();
    }
    @Test void overdueTargetIsAMaximumAndProgressIncreasesWhenDebtDecreases() {
        BigDecimal target=new BigDecimal("20");
        ClientGoalStats bad=new ClientGoalStats(10,5,5,3);
        ClientGoalStats good=new ClientGoalStats(10,8,2,3);
        assertThat(bad.reached(FinancialGoalType.CLIENTES_ATRASO,target)).isFalse();
        assertThat(good.reached(FinancialGoalType.CLIENTES_ATRASO,target)).isTrue();
        assertThat(bad.progress(FinancialGoalType.CLIENTES_ATRASO,target)).isEqualByComparingTo("62.5");
        assertThat(good.progress(FinancialGoalType.CLIENTES_ATRASO,target)).isEqualByComparingTo("100");
    }
    @Test void noClientsDoesNotSatisfyAnyPercentageGoal() {
        assertThat(ClientGoalStats.EMPTY.reached(FinancialGoalType.CLIENTES_ATRASO,BigDecimal.ZERO)).isFalse();
        assertThat(ClientGoalStats.EMPTY.progress(FinancialGoalType.CLIENTES_ATRASO,BigDecimal.ZERO)).isZero();
    }
    @Test void zeroOverdueIsSupportedAndNewClientsIsAnIndependentCount() {
        ClientGoalStats stats=new ClientGoalStats(10,10,0,2);
        assertThat(stats.reached(FinancialGoalType.CLIENTES_ATRASO,BigDecimal.ZERO)).isTrue();
        assertThat(stats.achieved(FinancialGoalType.CLIENTES_ATIVOS)).isEqualByComparingTo("2");
        assertThat(stats.reached(FinancialGoalType.CLIENTES_ATIVOS,new BigDecimal("3"))).isFalse();
    }
}
