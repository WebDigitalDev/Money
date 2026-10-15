package com.webdigital.money2.auth;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.users.Region;
import com.webdigital.money2.users.RegionRepository;
import com.webdigital.money2.users.UserRegion;
import com.webdigital.money2.users.UserRegionRepository;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class TutorialRegionAccessServiceTest {

    private final UserTutorialStatusRepository tutorialStatusRepository =
            mock(UserTutorialStatusRepository.class);
    private final RegionRepository regionRepository = mock(RegionRepository.class);
    private final UserRegionRepository userRegionRepository =
            mock(UserRegionRepository.class);
    private final TutorialRegionAccessService service =
            new TutorialRegionAccessService(
                    tutorialStatusRepository,
                    regionRepository,
                    userRegionRepository);

    @BeforeEach
    void tutorialRegionExists() {
        Region tutorial = new Region();
        ReflectionTestUtils.setField(tutorial, "id", 1000000001L);
        tutorial.setDescription("TUTORIAL");
        when(regionRepository.findTutorialRegions()).thenReturn(List.of(tutorial));
    }

    @Test
    void grantsTemporaryAccessWhileFirstTutorialIsPending() {
        UserAccount user = user(7L, "BIANCA");
        when(tutorialStatusRepository.existsById(7L)).thenReturn(false);
        when(userRegionRepository.existsByUserIdAndRegionId(7L, 1000000001L))
                .thenReturn(false);

        service.synchronize(user);

        verify(userRegionRepository).save(any(UserRegion.class));
    }

    @Test
    void removesTemporaryAccessAfterTutorialCompletion() {
        UserAccount user = user(8L, "HELAIZA");
        when(tutorialStatusRepository.existsById(8L)).thenReturn(true);
        when(userRegionRepository.existsByUserIdAndRegionId(8L, 1000000001L))
                .thenReturn(true);

        service.synchronize(user);

        verify(userRegionRepository)
                .deleteByUserIdAndRegionId(8L, 1000000001L);
    }

    @Test
    void keepsPermanentAccessForNakasawa() {
        UserAccount user = user(9L, " NAKASAWA ");
        when(tutorialStatusRepository.existsById(9L)).thenReturn(true);
        when(userRegionRepository.existsByUserIdAndRegionId(9L, 1000000001L))
                .thenReturn(false);

        service.synchronize(user);

        verify(userRegionRepository).save(any(UserRegion.class));
        verify(userRegionRepository, never())
                .deleteByUserIdAndRegionId(9L, 1000000001L);
    }

    @Test
    void explicitlyStartingTutorialGrantsAccessEvenAfterPreviousCompletion() {
        UserAccount user = user(10L, "BIANCA");
        when(tutorialStatusRepository.existsById(10L)).thenReturn(true);
        when(userRegionRepository.existsByUserIdAndRegionId(10L, 1000000001L))
                .thenReturn(false);

        service.grantTemporaryAccess(user);

        verify(userRegionRepository).save(any(UserRegion.class));
        verify(userRegionRepository, never())
                .deleteByUserIdAndRegionId(10L, 1000000001L);
    }

    private UserAccount user(long id, String username) {
        UserAccount user = new UserAccount();
        ReflectionTestUtils.setField(user, "id", id);
        user.setUsername(username);
        return user;
    }
}
