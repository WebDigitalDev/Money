package com.webdigital.money2.routes;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiException;
import java.math.BigDecimal;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

class CollectionRouteServiceTest {

    @TempDir
    Path storage;

    @Test
    void regularUserCanSearchRoutes() {
        CollectionRouteRepository routes = mock(CollectionRouteRepository.class);
        CollectionRouteService service = service(routes);
        UserAccount user = user(false);
        CollectionRoutePageResponse expected = new CollectionRoutePageResponse(
                List.of(), 0, 50, 0, 0, false,
                BigDecimal.ZERO, BigDecimal.ZERO);
        when(routes.search(
                17L, 23L, Set.of(3L), 3142L, "goiânia", CollectionRouteSort.OVERDUE_AMOUNT,
                "ana", true, 0, 50)).thenReturn(expected);

        assertThat(service.search(
                user, "3", 23L, 3142L, "goiânia", "OVERDUE_AMOUNT", "ana", 0, 50))
                .isSameAs(expected);
    }

    @Test
    void collectorSeesOnlyRoutesAssignedToOwnUser() {
        CollectionRouteRepository routes = mock(CollectionRouteRepository.class);
        CollectionRouteService service = service(routes);
        UserAccount collector = user(true);
        CollectionRoutePageResponse expected = new CollectionRoutePageResponse(
                List.of(), 0, 50, 0, 0, false,
                BigDecimal.ZERO, BigDecimal.ZERO);
        when(routes.search(
                17L, 17L, Set.of(), null, "", CollectionRouteSort.OVERDUE_DAYS,
                "", true, 0, 50)).thenReturn(expected);

        assertThat(service.search(
                collector, "", 23L, null, "", "OVERDUE_DAYS", "", 0, 50))
                .isSameAs(expected);
    }

    @Test
    void onlySelectedCollectorCanRegisterCollection() {
        CollectionRouteRepository routes = mock(CollectionRouteRepository.class);
        CollectionEntityRepository collections = mock(CollectionEntityRepository.class);
        CollectionRouteService service = new CollectionRouteService(
                routes, collections, storage.toString());
        when(routes.requireAssignedDebt(17L, 99L)).thenReturn(debt());

        assertThatThrownBy(() -> service.register(
                user(false), 99L, "Visita realizada", null))
                .isInstanceOf(ApiException.class)
                .hasMessage("Somente o cobrador responsável por esta rota pode registrar cobranças.");
        verify(routes).requireAssignedDebt(17L, 99L);
        verify(collections, never()).saveAndFlush(any());
    }

    @Test
    void detailTellsAppWhetherUserCanRegister() {
        CollectionRouteRepository routes = mock(CollectionRouteRepository.class);
        CollectionRouteService service = service(routes);
        CollectionRouteItemResponse debt = debt();
        when(routes.requireAssignedDebt(eq(17L), eq(99L))).thenReturn(debt);
        when(routes.contracts(eq(17L), eq(99L))).thenReturn(List.of());
        when(routes.history(eq(99L))).thenReturn(List.of());

        assertThat(service.detail(user(false), 99L).canRegisterCollection()).isFalse();
        assertThat(service.detail(user(true), 99L).canRegisterCollection()).isTrue();
    }

    @Test
    void regularUserCanListCandidatesAndAssignRoutes() {
        CollectionRouteRepository routes = mock(CollectionRouteRepository.class);
        CollectionRouteService service = service(routes);
        UserAccount regular = user(false);
        CollectionRoutePageResponse expected = new CollectionRoutePageResponse(
                List.of(), 0, 50, 0, 0, false,
                BigDecimal.ZERO, BigDecimal.ZERO);
        when(routes.search(
                17L, null, Set.of(), null, "", CollectionRouteSort.OVERDUE_DAYS,
                "", false, 0, 50)).thenReturn(expected);
        when(routes.collectorAvailable(23L)).thenReturn(true);
        when(routes.assign(17L, 23L, Set.of(99L))).thenReturn(1);

        assertThat(service.candidates(
                regular, "", null, "", "OVERDUE_DAYS", "", 0, 50))
                .isSameAs(expected);
        assertThat(service.assign(
                regular, new CollectionRouteAssignmentRequest(23L, List.of(99L)))
                .assignedClients()).isEqualTo(1);
        verify(routes).assign(17L, 23L, Set.of(99L));
    }

    @Test
    void userAssignsEverySelectedClientToCollector() {
        CollectionRouteRepository routes = mock(CollectionRouteRepository.class);
        CollectionRouteService service = service(routes);
        UserAccount regular = user(false);
        when(routes.collectorAvailable(23L)).thenReturn(true);
        when(routes.assign(17L, 23L, Set.of(99L, 100L))).thenReturn(2);

        CollectionRouteAssignmentResponse result = service.assign(
                regular,
                new CollectionRouteAssignmentRequest(23L, List.of(99L, 100L)));

        assertThat(result.assignedClients()).isEqualTo(2);
        verify(routes).assign(17L, 23L, Set.of(99L, 100L));
    }

    @Test
    void regularUserCanRemoveAssignmentWithoutDeletingDebtOrHistory() {
        CollectionRouteRepository routes = mock(CollectionRouteRepository.class);
        CollectionRouteService service = service(routes);
        UserAccount regular = user(false);
        when(routes.requireAssignedDebt(17L, 99L)).thenReturn(debt());
        when(routes.removeAssignment(17L, 99L)).thenReturn(true);

        service.removeAssignment(regular, 99L);

        verify(routes).removeAssignment(17L, 99L);
        verify(routes, never()).history(anyLong());
    }

    @Test
    void collectorWithoutRoutineEditingPermissionCannotAssignRoutes() {
        CollectionRouteRepository routes = mock(CollectionRouteRepository.class);
        CollectionRouteService service = service(routes);
        UserAccount collector = user(true);
        collector.setReadOnly(true);

        assertThatThrownBy(() -> service.assign(
                collector, new CollectionRouteAssignmentRequest(23L, List.of(99L))))
                .isInstanceOf(ApiException.class)
                .hasMessage("Ative a permissão 'Permitir edições nas rotinas' para criar rotas.");

        verify(routes, never()).assign(anyLong(), anyLong(), any());
    }

    @Test
    void collectorWithoutRoutineEditingPermissionCannotRemoveAssignment() {
        CollectionRouteRepository routes = mock(CollectionRouteRepository.class);
        CollectionRouteService service = service(routes);
        UserAccount collector = user(true);
        collector.setReadOnly(true);

        assertThatThrownBy(() -> service.removeAssignment(collector, 99L))
                .isInstanceOf(ApiException.class)
                .hasMessage("Ative a permissão 'Permitir edições nas rotinas' para remover rotas.");

        verify(routes, never()).removeAssignment(anyLong(), anyLong());
    }

    @Test
    void regularReadOnlyUserCanRemoveAssignment() {
        CollectionRouteRepository routes = mock(CollectionRouteRepository.class);
        CollectionRouteService service = service(routes);
        UserAccount regular = user(false);
        regular.setReadOnly(true);
        when(routes.requireAssignedDebt(17L, 99L)).thenReturn(debt());
        when(routes.removeAssignment(17L, 99L)).thenReturn(true);

        service.removeAssignment(regular, 99L);

        verify(routes).removeAssignment(17L, 99L);
    }

    private CollectionRouteService service(CollectionRouteRepository routes) {
        return new CollectionRouteService(
                routes, mock(CollectionEntityRepository.class), storage.toString());
    }

    private static UserAccount user(boolean collector) {
        UserAccount user = new UserAccount();
        ReflectionTestUtils.setField(user, "id", 17L);
        user.setCollector(collector);
        return user;
    }

    private static CollectionRouteItemResponse debt() {
        return new CollectionRouteItemResponse(
                99L, "Cliente", 3L, "Região", BigDecimal.TEN,
                BigDecimal.ONE, 5, 1, "Endereço", CollectionRouteStatus.IN_PROGRESS,
                0, null, 71L, 17L, "Cobrador", null);
    }
}
