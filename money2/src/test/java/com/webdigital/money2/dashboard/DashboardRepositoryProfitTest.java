package com.webdigital.money2.dashboard;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.dashboard.DashboardModels.DueTodayLoan;
import com.webdigital.money2.dashboard.DashboardModels.FinancialPoint;
import com.webdigital.money2.dashboard.DashboardModels.Metrics;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class DashboardRepositoryProfitTest {

    @Test
    void dailyProfitUsesTheSameLoanProfitFunctionAsLoanCards() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        DashboardRepository repository = new DashboardRepository(jdbc);
        Metrics emptyMetrics = new Metrics(
                0, 0, BigDecimal.ZERO, BigDecimal.ZERO, 0, BigDecimal.ZERO,
                0, 0, 0, 0, 0, 0, BigDecimal.ZERO);
        when(jdbc.queryForObject(
                anyString(), anyMap(), ArgumentMatchers.<RowMapper<Metrics>>any()))
                .thenReturn(emptyMetrics);

        repository.metrics(7L, List.of(11L));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).queryForObject(
                sql.capture(), anyMap(), ArgumentMatchers.<RowMapper<Metrics>>any());
        assertThat(sql.getValue())
                .contains("SUM(public.calcular_lucro_fluxo(event.id))")
                .contains("profit_events AS MATERIALIZED")
                .contains("closed_loans AS MATERIALIZED")
                .contains("last_settlement_payment AS MATERIALIZED")
                .contains("MAX(payment.data) last_payment_date")
                .contains("event.recognition_date>=CURRENT_DATE")
                .contains("JOIN pending_installments p ON p.id=pg.parcela_id")
                .doesNotContain("vw_emprestimos_resumo")
                .doesNotContain("paid_before+pg.paid_today");
    }

    @Test
    void financialHistoryUsesLoanProfitOnTheClosingDate() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        DashboardRepository repository = new DashboardRepository(jdbc);
        when(jdbc.query(
                anyString(), anyMap(), ArgumentMatchers.<RowMapper<FinancialPoint>>any()))
                .thenReturn(List.of());

        repository.financial(7L, List.of(11L));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(
                sql.capture(), anyMap(), ArgumentMatchers.<RowMapper<FinancialPoint>>any());
        assertThat(sql.getValue())
                .contains("public.calcular_lucro_fluxo(event.id)")
                .contains("profit_events AS MATERIALIZED")
                .contains("GROUP BY event.recognition_date::date")
                .contains("pending_installments AS MATERIALIZED")
                .contains("JOIN pending_installments p ON p.id=pg.parcela_id")
                .doesNotContain("vw_emprestimos_resumo")
                .doesNotContain("profit_running");
    }

    @Test
    void financialHistoryUsesTheSameInclusivePeriodAsRegions() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        DashboardRepository repository = new DashboardRepository(jdbc);
        when(jdbc.query(
                anyString(), anyMap(), ArgumentMatchers.<RowMapper<FinancialPoint>>any()))
                .thenReturn(List.of());

        repository.financial(7L, List.of(11L));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(
                sql.capture(), anyMap(), ArgumentMatchers.<RowMapper<FinancialPoint>>any());
        assertThat(sql.getValue())
                .contains("(CURRENT_DATE-INTERVAL '30 days')::date first_day")
                .contains("CURRENT_DATE last_day")
                .contains("generate_series(l.first_day,l.last_day,INTERVAL '1 day')")
                .doesNotContain("INTERVAL '29 days'");
    }

    @Test
    void dueTodayOnlyAggregatesPaymentsForTodaysPendingInstallments() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        DashboardRepository repository = new DashboardRepository(jdbc);
        when(jdbc.query(
                anyString(), anyMap(), ArgumentMatchers.<RowMapper<DueTodayLoan>>any()))
                .thenReturn(List.of());

        repository.dueToday(7L, List.of(11L));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(
                sql.capture(), anyMap(), ArgumentMatchers.<RowMapper<DueTodayLoan>>any());
        assertThat(sql.getValue())
                .contains("due_installments AS MATERIALIZED")
                .contains("JOIN due_installments p ON p.id=pg.parcela_id")
                .contains("p.vencimento>=CURRENT_DATE")
                .contains("p.vencimento<CURRENT_DATE+INTERVAL '1 day'")
                .doesNotContain("p.vencimento::date=CURRENT_DATE");
    }
}
