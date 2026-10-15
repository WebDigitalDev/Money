package com.webdigital.money2.routes;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Set;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.springframework.jdbc.core.ResultSetExtractor;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class CollectionRouteRepositoryTest {

    @Test
    void routeUsesApprovedBalancesAndRegionalAccess() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        CollectionRouteRepository repository = new CollectionRouteRepository(jdbc);
        when(jdbc.query(
                anyString(), anyMap(),
                ArgumentMatchers.<ResultSetExtractor<CollectionRoutePageResponse>>any()))
                .thenReturn(new CollectionRoutePageResponse(
                        java.util.List.of(), 0, 50, 0, 0, false,
                        java.math.BigDecimal.ZERO, java.math.BigDecimal.ZERO));

        repository.search(
                7L, null, Set.of(11L), 3142L, "goiânia", CollectionRouteSort.OVERDUE_AMOUNT,
                "cliente", false, 0, 50);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(
                sql.capture(), anyMap(),
                ArgumentMatchers.<ResultSetExtractor<CollectionRoutePageResponse>>any());
        assertThat(sql.getValue())
                .contains("COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'")
                .contains("COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'")
                .contains("ROUND((COALESCE(p.valor,0)+COALESCE(p.valor_juros,0))::numeric,2)")
                .contains("balance.due_date<CURRENT_DATE")
                .contains("ru.usuario_id=:userId")
                .contains(":filterRegions=false OR c.regiao_id IN (:regionIds)")
                .contains(":filterCity=false OR c.cidade_id=:cityId")
                .contains(":city='' OR lower(COALESCE(debt.city_name,'')) LIKE :citySearch")
                .contains(":assignedOnly=true AND debt.route_id IS NOT NULL")
                .contains(":assignedOnly=false AND debt.route_id IS NULL")
                .contains(":filterCollector=false OR debt.collector_id=:collectorId")
                .contains("GROUP BY c.id")
                .contains("ORDER BY overdue_debt DESC,overdue_days DESC")
                .doesNotContain("vw_emprestimos_resumo");
    }

    @Test
    void availableCitiesComeOnlyFromClientsInTheCurrentRouteList() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        CollectionRouteRepository repository = new CollectionRouteRepository(jdbc);
        when(jdbc.query(
                anyString(), anyMap(),
                ArgumentMatchers.<RowMapper<com.webdigital.money2.clients.CityOptionResponse>>any()))
                .thenReturn(java.util.List.of());

        repository.cities(7L, 7L, Set.of(11L), "cliente", true);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(
                sql.capture(), anyMap(),
                ArgumentMatchers.<RowMapper<com.webdigital.money2.clients.CityOptionResponse>>any());
        assertThat(sql.getValue())
                .contains("ru.usuario_id=:userId")
                .contains(":filterRegions=false OR c.regiao_id IN (:regionIds)")
                .contains(":assignedOnly=true AND debt.route_id IS NOT NULL")
                .contains(":assignedOnly=false AND debt.route_id IS NULL")
                .contains(":filterCollector=false OR debt.collector_id=:collectorId")
                .contains("debt.city_id IS NOT NULL")
                .contains("lower(COALESCE(debt.client_name,'')) LIKE :search")
                .contains("SELECT DISTINCT debt.city_id");
    }

    @Test
    void availableCollectorsComeOnlyFromAssignedRoutesInTheCurrentList() {
        NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
        CollectionRouteRepository repository = new CollectionRouteRepository(jdbc);
        when(jdbc.query(
                anyString(), anyMap(),
                ArgumentMatchers.<RowMapper<CollectionRouteCollectorResponse>>any()))
                .thenReturn(java.util.List.of());

        repository.assignedCollectors(7L, null, Set.of(11L), 3142L, "cliente");

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).query(
                sql.capture(), anyMap(),
                ArgumentMatchers.<RowMapper<CollectionRouteCollectorResponse>>any());
        assertThat(sql.getValue())
                .contains("debt.route_id IS NOT NULL")
                .contains("debt.collector_id IS NOT NULL")
                .contains(":filterRegions=false OR c.regiao_id IN (:regionIds)")
                .contains(":filterCity=false OR c.cidade_id=:cityId")
                .contains("SELECT DISTINCT debt.collector_id");
    }
}
