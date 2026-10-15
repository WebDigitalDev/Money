package com.webdigital.money2.auth;

import com.webdigital.money2.users.Region;
import com.webdigital.money2.users.RegionRepository;
import com.webdigital.money2.users.UserRegion;
import com.webdigital.money2.users.UserRegionRepository;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Locale;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TutorialRegionAccessService {

    public static final String TUTORIAL_REGION_NAME = "TUTORIAL";
    public static final String PERMANENT_USERNAME = "NAKASAWA";
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");

    private final UserTutorialStatusRepository tutorialStatusRepository;
    private final RegionRepository regionRepository;
    private final UserRegionRepository userRegionRepository;

    public TutorialRegionAccessService(
            UserTutorialStatusRepository tutorialStatusRepository,
            RegionRepository regionRepository,
            UserRegionRepository userRegionRepository) {
        this.tutorialStatusRepository = tutorialStatusRepository;
        this.regionRepository = regionRepository;
        this.userRegionRepository = userRegionRepository;
    }

    @Transactional
    public void synchronize(UserAccount user) {
        Region tutorial = tutorialRegion();
        if (tutorial == null) return;
        boolean shouldHaveAccess = isPermanentUser(user)
                || !tutorialStatusRepository.existsById(user.getId());
        boolean hasAccess = userRegionRepository.existsByUserIdAndRegionId(
                user.getId(), tutorial.getId());
        if (shouldHaveAccess && !hasAccess) {
            userRegionRepository.save(new UserRegion(
                    user.getId(), tutorial.getId(), LocalDateTime.now(BUSINESS_ZONE)));
        } else if (!shouldHaveAccess && hasAccess) {
            userRegionRepository.deleteByUserIdAndRegionId(
                    user.getId(), tutorial.getId());
        }
    }

    @Transactional
    public void grantTemporaryAccess(UserAccount user) {
        Region tutorial = tutorialRegion();
        if (tutorial == null) return;
        boolean hasAccess = userRegionRepository.existsByUserIdAndRegionId(
                user.getId(), tutorial.getId());
        if (!hasAccess) {
            userRegionRepository.save(new UserRegion(
                    user.getId(), tutorial.getId(), LocalDateTime.now(BUSINESS_ZONE)));
        }
    }

    public boolean isTutorialRegion(Long regionId) {
        if (regionId == null) return false;
        Region tutorial = tutorialRegion();
        return tutorial != null && tutorial.getId().equals(regionId);
    }

    public Long tutorialRegionId() {
        Region tutorial = tutorialRegion();
        return tutorial == null ? null : tutorial.getId();
    }

    public boolean isPermanentUser(UserAccount user) {
        return normalize(user.getUsername()).equals(PERMANENT_USERNAME);
    }

    private Region tutorialRegion() {
        List<Region> matches = regionRepository.findTutorialRegions();
        return matches.isEmpty() ? null : matches.get(0);
    }

    private String normalize(String value) {
        return value == null ? "" : value.trim().toUpperCase(Locale.ROOT);
    }
}
