package com.webdigital.money2.goals;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import java.lang.reflect.Method;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class FinancialGoalProgressRepositoryTest {

    @Test
    void profitIsRecognizedInFullOnlyWhenContractClosesInsideGoalPeriod()
            throws Exception {
        FinancialGoalProgressRepository repository =
                new FinancialGoalProgressRepository(
                        mock(NamedParameterJdbcTemplate.class));
        Method method = FinancialGoalProgressRepository.class
                .getDeclaredMethod("profitSql");
        method.setAccessible(true);

        String query = (String) method.invoke(repository);

        assertThat(query)
                .contains("SUM(public.calcular_lucro_fluxo(loan.id))")
                .contains("closed_loans AS MATERIALIZED")
                .contains("last_settlement_payment AS MATERIALIZED")
                .contains("loan.renewed = true")
                .contains("COALESCE(summary.pending_count, 0) = 0")
                .contains("COALESCE(payment.last_payment_date, loan.last_due_date)")
                .contains("loan.recognition_date >= :startDate")
                .contains("< CAST(:endDate AS date) + INTERVAL '1 day'")
                .doesNotContain("vw_emprestimos_resumo")
                .doesNotContain("paid_before")
                .doesNotContain("paid_during")
                .doesNotContain("pg.data >= :startDate");
    }

    @Test
    void activeGoalProgressCalculatesSharedProfitEventsOnlyOnce()
            throws Exception {
        FinancialGoalProgressRepository repository =
                new FinancialGoalProgressRepository(
                        mock(NamedParameterJdbcTemplate.class));
        Method method = FinancialGoalProgressRepository.class
                .getDeclaredMethod("activeGoalsSql");
        method.setAccessible(true);

        String query = (String) method.invoke(repository);

        assertThat(query)
                .contains("target_goals AS MATERIALIZED")
                .contains("profit_events AS MATERIALIZED")
                .contains("public.calcular_lucro_fluxo(loan.id)")
                .contains("profit.regiao_id = region.regiao_id")
                .contains("goal.id IN (:goalIds)")
                .doesNotContain("vw_emprestimos_resumo");
    }

    @Test
    void clientGoalProgressCountsContractsWithTheSameRegionClassification()
            throws Exception {
        FinancialGoalProgressRepository repository =
                new FinancialGoalProgressRepository(
                        mock(NamedParameterJdbcTemplate.class));
        Method method = FinancialGoalProgressRepository.class
                .getDeclaredMethod("clientStatsSql");
        method.setAccessible(true);

        String query = (String) method.invoke(repository);

        assertThat(query)
                .contains("e.id contract_id")
                .contains("GROUP BY gc.cutoff,gc.contract_id")
                .contains("historical_contracts AS MATERIALIZED")
                .contains("FROM historical_contracts hc")
                .contains("gc.cutoff=CURRENT_DATE AND p.pendente IS DISTINCT FROM false")
                .contains("gc.cutoff=CURRENT_DATE AND p.pendente=true")
                .contains("WHEN gc.status=1 THEN 'Lançamento'")
                .contains("WHEN gc.missing THEN 'Desaparecido'")
                .contains("('Lançamento','Em atraso','Em dia')) active")
                .contains("'Em atraso','Desaparecido')) on_time")
                .contains("contract_state='Em atraso'")
                .contains("contract_date BETWEEN data_inicio AND cutoff")
                .doesNotContain("GROUP BY gc.cutoff,gc.client_id")
                .doesNotContain("MIN(e.data::date) first_date")
                .doesNotContain("FROM (SELECT DISTINCT cutoff FROM goals) dates");
    }
}
