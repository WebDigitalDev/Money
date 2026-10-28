package com.webdigital.money2.integrations;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class PixRepositoryTest {

    @Test
    void reconciliationDoesNotIncludeCancelledPix() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        PixRepository repository = new PixRepository(jdbc);

        repository.pendingMoney2Ids();

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).queryForList(sql.capture(), eq(Map.of()), eq(Long.class));
        assertTrue(sql.getValue().contains("status='AGUARDANDO'"));
        assertFalse(sql.getValue().contains("status='CANCELADO'"));
    }

    @Test
    void installmentSynchronizationComparesAmountsAtCentPrecision() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        PixRepository repository = new PixRepository(jdbc);

        repository.synchronizeInstallments(List.of(1200384L));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(), eq(Map.of("ids", List.of(1200384L))));
        String statement = sql.getValue().replaceAll("\\s+", " ");
        assertTrue(statement.contains("ROUND(COALESCE((SELECT SUM(pg.valor)"));
        assertTrue(statement.contains("),0)::numeric,2) < ROUND("));
    }
}
