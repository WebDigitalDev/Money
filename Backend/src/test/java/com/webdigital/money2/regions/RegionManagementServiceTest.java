package com.webdigital.money2.regions;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiException;
import com.webdigital.money2.users.RegionRepository;
import com.webdigital.money2.users.UserRegionRepository;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.test.util.ReflectionTestUtils;

class RegionManagementServiceTest {

    @Test
    void commonEditorCannotCreateRegions() {
        RegionRepository regionRepository = mock(RegionRepository.class);
        UserRegionRepository userRegionRepository = mock(UserRegionRepository.class);
        RegionManagementService service = new RegionManagementService(
                regionRepository, userRegionRepository);
        UserAccount user = mock(UserAccount.class);
        when(user.isAdministrator()).thenReturn(false);
        when(user.isReadOnly()).thenReturn(false);

        RegionRequest request = new RegionRequest(
                "REGIÃO TESTE", null, null, null, null, null, null, null, false);

        assertThatThrownBy(() -> service.create(user, request))
                .isInstanceOfSatisfying(ApiException.class, error -> {
                    org.assertj.core.api.Assertions.assertThat(error.getStatus())
                            .isEqualTo(HttpStatus.FORBIDDEN);
                    org.assertj.core.api.Assertions.assertThat(error.getMessage())
                            .isEqualTo("Somente administradores podem alterar regiões.");
                });
        verifyNoInteractions(regionRepository, userRegionRepository);
    }

    @Test
    void tutorialOptionsIgnoreMembershipAndUseCanonicalName() {
        RegionRepository regionRepository = mock(RegionRepository.class);
        UserRegionRepository userRegionRepository = mock(UserRegionRepository.class);
        RegionManagementService service = new RegionManagementService(
                regionRepository, userRegionRepository);
        UserAccount user = mock(UserAccount.class);
        com.webdigital.money2.users.Region region =
                new com.webdigital.money2.users.Region();
        ReflectionTestUtils.setField(region, "id", 1000000001L);
        region.setDescription("TUTORIAL");
        region.setResponsiblePeople("WEBDIGITAL");
        when(regionRepository.findTutorialRegions()).thenReturn(List.of(region));

        List<RegionOptionResponse> result = service.options(user, true);

        assertThat(result).containsExactly(
                new RegionOptionResponse(1000000001L, "TUTORIAL"));
        verifyNoInteractions(userRegionRepository);
    }
}
