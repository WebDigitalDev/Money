package com.webdigital.money2.integrations;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Set;
import org.mockito.ArgumentCaptor;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class IntegrationRepositoryTest {

    @Test
    void emptyRemoteDeviceListReleasesRegionMappingsForReplacementNumber() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        IntegrationRepository repository = new IntegrationRepository(jdbc);

        repository.markMissingRemoteDevicesDisconnected(Set.of());

        verify(jdbc).update("DELETE FROM whatsapp_dispositivo_regioes", java.util.Map.of());
        verify(jdbc).update(
                "UPDATE whatsapp_dispositivos SET connected=false, status='DESCONECTADO', disparando=false",
                java.util.Map.of());
    }

    @Test
    void nonEmptyRemoteListMigratesMatchingLegacyNumberAndReleasesOtherLegacyMappings() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        IntegrationRepository repository = new IntegrationRepository(jdbc);

        repository.markMissingRemoteDevicesDisconnected(Set.of("current-device"));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc, times(4)).update(sql.capture(), org.mockito.ArgumentMatchers.eq(
                Map.of("ids", Set.of("current-device"))));
        String statements = String.join("\n", sql.getAllValues());
        assertTrue(statements.contains("SET dispositivo_id=match.current_id"));
        assertTrue(statements.contains(
                "d.webdigital_device_id IS NULL OR d.webdigital_device_id NOT IN (:ids)"));
        assertTrue(statements.contains(
                "webdigital_device_id IS NULL OR webdigital_device_id NOT IN (:ids)"));
    }

    @Test
    void dispatchEligibilityKeepsWhitespaceBeforeDynamicCondition() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        when(jdbc.queryForObject(anyString(), anyMap(), eq(Integer.class))).thenReturn(1);
        IntegrationRepository repository = new IntegrationRepository(jdbc);

        boolean eligible = repository.isDispatchTargetEligible("ATRASADAS",
                new IntegrationRepository.DispatchTarget(10, "Cliente", "65993453927", 20,
                        30L, "1", LocalDateTime.now().minusDays(2), BigDecimal.TEN));

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).queryForObject(sql.capture(), anyMap(), eq(Integer.class));
        assertTrue(eligible);
        assertTrue(sql.getValue().contains("AND p.vencimento::date<CURRENT_DATE"));
    }
}
