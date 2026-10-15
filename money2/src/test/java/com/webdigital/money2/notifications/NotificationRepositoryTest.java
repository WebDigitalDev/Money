package com.webdigital.money2.notifications;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import java.util.*;
import static org.mockito.Mockito.*;
import static org.assertj.core.api.Assertions.assertThat;

class NotificationRepositoryTest {
    private final NamedParameterJdbcTemplate jdbc=mock(NamedParameterJdbcTemplate.class);
    private final NotificationRepository repository=new NotificationRepository(jdbc);
    @Test void defaultsAreOff() {
        assertThat(repository.preferences(1)).isEqualTo(new NotificationRepository.Preferences(false,false));
    }
    @Test void historyIsLimitedByTimeAndAllRegionsAreRequired() {
        repository.list(7);
        ArgumentCaptor<String> sql=ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(sql.capture(),eq(Map.of("userId",7L)),any(RowMapper.class));
        assertThat(sql.getValue()).contains("INTERVAL '24 hours'", "NOT EXISTS", "unnest(e.region_ids)", "ur.usuario_id=:userId");
    }
    @Test void pixIsOnlyCollectedOnceAfterConfirmedProcessing() {
        repository.collectPayments();
        ArgumentCaptor<String> sql=ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture(),eq(Map.of()));
        assertThat(sql.getValue()).contains("p.pagamento_processado=true", "p.status='PAGO'", "ON CONFLICT(event_key) DO NOTHING");
    }
    @Test void goalsDeduplicateAcrossSchedulerRuns() {
        repository.goal(9,"Meta","Teste",Set.of(3L,2L));
        verify(jdbc).update(contains("ON CONFLICT(event_key) DO NOTHING"),
                eq(Map.of("key","GOAL:9","title","Meta","body","Teste","regions","{2,3}")));
    }
}
