package com.webdigital.money2.dashboard;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.dashboard.DashboardModels.FinancialSummary;
import com.webdigital.money2.dashboard.DashboardModels.Metrics;
import com.webdigital.money2.dashboard.DashboardModels.Response;
import com.webdigital.money2.goals.FinancialGoalService;
import com.webdigital.money2.users.Region;
import com.webdigital.money2.users.RegionRepository;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class DashboardServiceTest {

    @Test
    void tutorialDashboardForcesOnlyTutorialWithoutUserMembership() {
        RegionRepository regionRepository = mock(RegionRepository.class);
        DashboardRepository dashboardRepository = mock(DashboardRepository.class);
        FinancialGoalService financialGoalService = mock(FinancialGoalService.class);
        DashboardService service = new DashboardService(
                regionRepository, dashboardRepository, financialGoalService);
        UserAccount user = new UserAccount();
        ReflectionTestUtils.setField(user, "id", 44L);
        user.setUsername("BIANCA");
        Region tutorial = new Region();
        ReflectionTestUtils.setField(tutorial, "id", 1000000001L);
        tutorial.setDescription("TUTORIAL");
        tutorial.setResponsiblePeople("WEBDIGITAL");
        List<Long> tutorialIds = List.of(1000000001L);
        Metrics metrics = new Metrics(
                0, 0, BigDecimal.ZERO, BigDecimal.ZERO, 0, BigDecimal.ZERO,
                0, 0, 0, 0, 0, 0, BigDecimal.ZERO);
        FinancialSummary financial = new FinancialSummary(
                BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO,
                BigDecimal.ZERO, List.of());
        when(regionRepository.findTutorialRegions()).thenReturn(List.of(tutorial));
        when(dashboardRepository.metrics(44L, tutorialIds, true)).thenReturn(metrics);
        when(dashboardRepository.financial(44L, tutorialIds, true)).thenReturn(financial);
        when(dashboardRepository.dueToday(44L, tutorialIds, true)).thenReturn(List.of());

        Response result = service.load(user, 7L, "7,8", true);

        assertThat(result.selectedRegionIds()).containsExactly(1000000001L);
        assertThat(result.selectedRegionName()).isEqualTo("TUTORIAL");
        assertThat(result.regions()).singleElement().satisfies(region -> {
            assertThat(region.id()).isEqualTo(1000000001L);
            assertThat(region.name()).isEqualTo("TUTORIAL");
        });
        verify(dashboardRepository).metrics(44L, tutorialIds, true);
        verify(dashboardRepository).financial(44L, tutorialIds, true);
        verify(dashboardRepository).dueToday(44L, tutorialIds, true);
    }
}
