package com.webdigital.money2.goals;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiException;
import com.webdigital.money2.users.Region;
import com.webdigital.money2.users.RegionRepository;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.test.util.ReflectionTestUtils;

class FinancialGoalServiceTest {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");

    private final FinancialGoalRepository goalRepository =
            mock(FinancialGoalRepository.class);
    private final FinancialGoalProgressRepository progressRepository =
            mock(FinancialGoalProgressRepository.class);
    private final RegionRepository regionRepository = mock(RegionRepository.class);
    private final FinancialGoalService service = new FinancialGoalService(
            goalRepository, progressRepository, regionRepository);

    @Test
    void listsAccessibleGoalWithCalculatedProgress() {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        LocalDate start = today.minusDays(10);
        LocalDate end = today.plusDays(10);
        UserAccount administrator = user(1L, true);
        Region region = region(7L, "ATLAS CRED", "DANIEL");
        FinancialGoalEntity goal = goal(
                30L, 7L, FinancialGoalType.RECEBIDO,
                "1000.00", start, end);

        when(regionRepository.findAccessibleByUserId(1L)).thenReturn(List.of(region));
        when(goalRepository.findAccessibleVisibleSince(1L, today.minusDays(2)))
                .thenReturn(List.of(goal));
        when(progressRepository.achieved(
                FinancialGoalType.RECEBIDO, 7L, start, today))
                .thenReturn(money("625.50"));

        FinancialGoalResponse response = service.list(administrator).get(0);

        assertThat(response.regionName()).isEqualTo("ATLAS CRED - DANIEL");
        assertThat(response.achievedAmount()).isEqualByComparingTo("625.50");
        assertThat(response.remainingAmount()).isEqualByComparingTo("374.50");
        assertThat(response.percentage()).isEqualByComparingTo("62.55");
        assertThat(response.status()).isEqualTo(FinancialGoalStatus.ATIVA);
        assertThat(response.canManage()).isTrue();
    }

    @Test
    void futureGoalStartsAtZeroWithoutQueryingFinancialTables() {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        UserAccount user = user(2L, true);
        Region region = region(8L, "APEX FINANCE", "BEATRIZ");
        FinancialGoalEntity goal = goal(
                31L, 8L, FinancialGoalType.EMPRESTADO,
                "5000.00", today.plusDays(2), today.plusDays(32));

        when(regionRepository.findAccessibleByUserId(2L)).thenReturn(List.of(region));
        when(goalRepository.findAccessibleVisibleSince(2L, today.minusDays(2)))
                .thenReturn(List.of(goal));

        FinancialGoalResponse response = service.list(user).get(0);

        assertThat(response.achievedAmount()).isEqualByComparingTo("0.00");
        assertThat(response.percentage()).isEqualByComparingTo("0");
        assertThat(response.status()).isEqualTo(FinancialGoalStatus.FUTURA);
        assertThat(response.canManage()).isTrue();
        verify(progressRepository, never()).achieved(
                FinancialGoalType.EMPRESTADO, 8L,
                goal.getStartDate(), goal.getEndDate());
    }

    @Test
    void listsGroupGoalWithAggregatedProgressAndRegionNames() {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        LocalDate start = today.minusDays(3);
        LocalDate end = today.plusDays(20);
        UserAccount administrator = user(1L, true);
        Region atlas = region(7L, "ATLAS CRED", "DANIEL");
        Region cash = region(8L, "CASH", "CHINAYDER");
        FinancialGoalEntity goal = goal(
                35L, 7L, FinancialGoalType.EMPRESTADO,
                "5000.00", start, end);
        goal.setRegionIds(Set.of(7L, 8L));

        when(regionRepository.findAccessibleByUserId(1L))
                .thenReturn(List.of(atlas, cash));
        when(goalRepository.findAccessibleVisibleSince(1L, today.minusDays(2)))
                .thenReturn(List.of(goal));
        when(progressRepository.achieved(
                FinancialGoalType.EMPRESTADO, List.of(7L, 8L), start, today))
                .thenReturn(money("2200.00"));

        FinancialGoalResponse response = service.list(administrator).get(0);

        assertThat(response.regionName()).isEqualTo("GRUPO DE REGIÕES");
        assertThat(response.regionIds()).containsExactly(7L, 8L);
        assertThat(response.regionNames())
                .containsExactly("ATLAS CRED - DANIEL", "CASH - CHINAYDER");
        assertThat(response.achievedAmount()).isEqualByComparingTo("2200.00");
    }

    @Test
    void commonUserCanListAccessibleGoalsAsReadOnly() {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        UserAccount user = user(2L, false);
        Region region = region(8L, "APEX FINANCE", "BEATRIZ");
        FinancialGoalEntity goal = goal(
                40L, 8L, FinancialGoalType.LUCRO,
                "2000.00", today.plusDays(1), today.plusMonths(1));
        when(regionRepository.findAccessibleByUserId(2L)).thenReturn(List.of(region));
        when(goalRepository.findAccessibleVisibleSince(2L, today.minusDays(2)))
                .thenReturn(List.of(goal));

        FinancialGoalResponse response = service.list(user).get(0);

        assertThat(response.regionName()).isEqualTo("APEX FINANCE - BEATRIZ");
        assertThat(response.canManage()).isFalse();
    }

    @Test
    void activeGoalsCalculateProgressInOneBatch() {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        UserAccount administrator = user(1L, true);
        Region atlas = region(7L, "ATLAS CRED", "DANIEL");
        Region cash = region(8L, "CASH", "CHINAYDER");
        FinancialGoalEntity atlasGoal = goal(
                50L, 7L, FinancialGoalType.LUCRO,
                "1000.00", today.minusDays(9), today.plusDays(20));
        FinancialGoalEntity cashGoal = goal(
                51L, 8L, FinancialGoalType.LUCRO,
                "2000.00", today.minusDays(9), today.plusDays(20));

        when(regionRepository.findAccessibleByUserId(1L))
                .thenReturn(List.of(atlas, cash));
        when(goalRepository.findAccessibleActiveOn(1L, today))
                .thenReturn(List.of(atlasGoal, cashGoal));
        when(progressRepository.achievedActive(List.of(50L, 51L)))
                .thenReturn(Map.of(50L, money("250.00"), 51L, money("900.00")));

        List<FinancialGoalResponse> result = service.listActive(
                administrator, List.of(7L, 8L));

        assertThat(result).extracting(FinancialGoalResponse::achievedAmount)
                .containsExactly(money("250.00"), money("900.00"));
        verify(progressRepository).achievedActive(List.of(50L, 51L));
        verify(progressRepository, never()).achieved(
                FinancialGoalType.LUCRO, 7L,
                atlasGoal.getStartDate(), today);
    }

    @Test
    void commonUserCannotCreateGoal() {
        UserAccount user = user(2L, false);
        FinancialGoalRequest request = new FinancialGoalRequest(
                8L, FinancialGoalType.LUCRO, money("2000"),
                LocalDate.now(BUSINESS_ZONE),
                LocalDate.now(BUSINESS_ZONE).plusMonths(1));

        assertThatThrownBy(() -> service.create(user, request))
                .isInstanceOf(ApiException.class)
                .extracting(error -> ((ApiException) error).getStatus())
                .isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void dashboardIncludesClientGoalsWithinSelectedAccessibleRegions() {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        UserAccount user = user(1L, false);
        FinancialGoalEntity clientGoal = goal(60L, 7L, FinancialGoalType.CLIENTES_EM_DIA,
                "70", today, today.plusDays(10));
        FinancialGoalEntity other = goal(61L, 8L, FinancialGoalType.CLIENTES_ATRASO,
                "20", today, today.plusDays(10));
        when(regionRepository.findAccessibleByUserId(1L)).thenReturn(List.of(
                region(7L, "ATLAS", ""), region(8L, "CASH", "")));
        when(goalRepository.findAccessibleActiveOn(1L, today))
                .thenReturn(List.of(clientGoal, other));
        when(progressRepository.clientStats(List.of(60L))).thenReturn(
                Map.of(60L, new ClientGoalStats(10, 8, 2, 3)));
        List<FinancialGoalResponse> result = service.listActive(user, List.of(7L));
        assertThat(result).hasSize(1);
        assertThat(result.get(0).clients().onTime()).isEqualTo(8);
        assertThat(result.get(0).achievedAmount()).isEqualByComparingTo("80");
        verify(progressRepository).achievedActive(List.of());
        verify(progressRepository).clientStats(List.of(60L));
    }

    @Test
    void allowsMoreThanOneUnfinishedGoalOfSameTypeAndRegion() {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        UserAccount administrator = user(1L, true);
        Region region = region(7L, "ATLAS CRED", "DANIEL");
        FinancialGoalRequest request = new FinancialGoalRequest(
                7L, FinancialGoalType.LUCRO, money("2000"),
                today, today.plusMonths(1));

        when(regionRepository.isAccessible(7L, 1L)).thenReturn(true);
        when(regionRepository.findById(7L)).thenReturn(Optional.of(region));
        when(goalRepository.saveAndFlush(any(FinancialGoalEntity.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(progressRepository.achieved(
                FinancialGoalType.LUCRO, 7L, today, today))
                .thenReturn(money("0"));

        FinancialGoalResponse response = service.create(administrator, request);

        assertThat(response.targetAmount()).isEqualByComparingTo("2000.00");
        verify(goalRepository).saveAndFlush(any(FinancialGoalEntity.class));
    }

    @Test
    void endedFinancialGoalRemainsVisibleUsingItsFinalAmount() {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        UserAccount administrator = user(1L, true);
        Region region = region(7L, "ATLAS CRED", "DANIEL");
        FinancialGoalEntity goal = goal(
                42L, 7L, FinancialGoalType.RECEBIDO,
                "1000.00", today.minusMonths(1), today.minusDays(1));
        goal.setFinalAchievedAmount(money("875.00"));
        goal.setFinalizedAt(LocalDateTime.now(BUSINESS_ZONE).minusDays(1));
        when(regionRepository.findAccessibleByUserId(1L)).thenReturn(List.of(region));
        when(goalRepository.findAccessibleVisibleSince(1L, today.minusDays(2)))
                .thenReturn(List.of(goal));

        FinancialGoalResponse response = service.list(administrator).get(0);

        assertThat(response.status()).isEqualTo(FinancialGoalStatus.ENCERRADA);
        assertThat(response.achievedAmount()).isEqualByComparingTo("875.00");
        verify(progressRepository, never()).achieved(
                FinancialGoalType.RECEBIDO, 7L,
                goal.getStartDate(), goal.getEndDate());
    }

    @Test
    void endedClientGoalRemainsVisibleWithItsFinalCounts() {
        LocalDate today=LocalDate.now(BUSINESS_ZONE);
        FinancialGoalEntity goal=goal(91L,7L,FinancialGoalType.CLIENTES_ATRASO,"20",today.minusDays(10),today.minusDays(1));
        when(regionRepository.findAccessibleByUserId(1L)).thenReturn(List.of(region(7L,"TEST","")));
        when(goalRepository.findAccessibleVisibleSince(1L, today.minusDays(2)))
                .thenReturn(List.of(goal));
        when(progressRepository.clientStats(List.of(91L))).thenReturn(
                Map.of(91L, new ClientGoalStats(10, 8, 2, 1)));

        FinancialGoalResponse response = service.list(user(1L,true)).get(0);

        assertThat(response.status()).isEqualTo(FinancialGoalStatus.ENCERRADA);
        assertThat(response.clients().active()).isEqualTo(10);
        assertThat(response.clients().onTime()).isEqualTo(8);
        assertThat(response.clients().overdue()).isEqualTo(2);
        assertThat(response.clients().newClients()).isEqualTo(1);
        assertThat(goal.getFinalClientStats()).isEqualTo(new ClientGoalStats(10, 8, 2, 1));
        verify(progressRepository).clientStats(List.of(91L));
    }

    @Test
    void recurringClientGoalCreatesNextPeriodWithSameConfiguration() {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        FinancialGoalEntity ended = goal(93L, 7L, FinancialGoalType.CLIENTES_EM_DIA,
                "70", today.minusDays(1), today.minusDays(1));
        ended.setRegionIds(Set.of(7L, 8L));
        ended.setRepeatFrequency(true);
        when(goalRepository.findRecurringDue(today))
                .thenReturn(List.of(ended), List.of());
        when(goalRepository.saveAndFlush(any(FinancialGoalEntity.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.createDueRecurringGoals();

        org.mockito.ArgumentCaptor<FinancialGoalEntity> saved =
                org.mockito.ArgumentCaptor.forClass(FinancialGoalEntity.class);
        verify(goalRepository).saveAndFlush(saved.capture());
        assertThat(saved.getValue().getStartDate()).isEqualTo(today);
        assertThat(saved.getValue().getEndDate()).isEqualTo(today);
        assertThat(saved.getValue().getRegionIds()).containsExactlyInAnyOrder(7L, 8L);
        assertThat(saved.getValue().getType()).isEqualTo(FinancialGoalType.CLIENTES_EM_DIA);
        assertThat(saved.getValue().getTargetAmount()).isEqualByComparingTo("70.00");
        assertThat(saved.getValue().isRepeatFrequency()).isTrue();
        assertThat(saved.getValue().getPreviousGoalId()).isEqualTo(93L);
    }

    @Test
    void batchQueryReplacesIndividualQueriesForActiveFinancialGoals() {
        LocalDate today=LocalDate.now(BUSINESS_ZONE);
        FinancialGoalEntity goal=goal(92L,7L,FinancialGoalType.RECEBIDO,"1000",today.minusDays(10),today.plusDays(1));
        when(regionRepository.findAccessibleByUserId(1L)).thenReturn(List.of(region(7L,"TEST","")));
        when(goalRepository.findAccessibleVisibleSince(1L, today.minusDays(2)))
                .thenReturn(List.of(goal));
        when(progressRepository.achievedActive(List.of(92L))).thenReturn(Map.of(92L,money("500")));
        assertThat(service.list(user(1L,true)).get(0).achievedAmount()).isEqualByComparingTo("500");
        verify(progressRepository,never()).achieved(any(),anyLong(),any(),any());
    }

    private static UserAccount user(long id, boolean administrator) {
        UserAccount user = new UserAccount();
        ReflectionTestUtils.setField(user, "id", id);
        user.setUsername(administrator ? "ADMINISTRADOR" : "USUARIO");
        user.setAdministrator(administrator);
        return user;
    }

    private static Region region(long id, String description, String responsible) {
        Region region = new Region();
        ReflectionTestUtils.setField(region, "id", id);
        region.setDescription(description);
        region.setResponsiblePeople(responsible);
        return region;
    }

    private static FinancialGoalEntity goal(
            long id,
            long regionId,
            FinancialGoalType type,
            String target,
            LocalDate start,
            LocalDate end) {
        FinancialGoalEntity goal = new FinancialGoalEntity();
        ReflectionTestUtils.setField(goal, "id", id);
        goal.setRegionId(regionId);
        goal.setType(type);
        goal.setTargetAmount(money(target));
        goal.setStartDate(start);
        goal.setEndDate(end);
        goal.setCreatedBy(1L);
        goal.setCreatedAt(LocalDateTime.now(BUSINESS_ZONE));
        goal.setUpdatedAt(LocalDateTime.now(BUSINESS_ZONE));
        return goal;
    }

    private static BigDecimal money(String value) {
        return new BigDecimal(value).setScale(2);
    }
}
