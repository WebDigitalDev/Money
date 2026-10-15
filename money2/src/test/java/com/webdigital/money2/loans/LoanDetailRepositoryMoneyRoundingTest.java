package com.webdigital.money2.loans;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import java.util.Map;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class LoanDetailRepositoryMoneyRoundingTest {

    @Test
    void installmentSynchronizationComparesAmountsAtCentPrecision() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        LoanDetailRepository repository = new LoanDetailRepository(jdbc);

        repository.synchronizeInstallment(1200384L);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(), eq(Map.of("id", 1200384L)));
        String statement = sql.getValue().replaceAll("\\s+", " ");
        assertThat(statement).contains("ROUND(COALESCE((SELECT SUM(pg.valor)");
        assertThat(statement).contains("),0)::numeric,2) < ROUND(");
    }
}
