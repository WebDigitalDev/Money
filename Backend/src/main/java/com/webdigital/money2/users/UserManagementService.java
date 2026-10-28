package com.webdigital.money2.users;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.auth.UserAccountRepository;
import com.webdigital.money2.auth.UserTutorialStatus;
import com.webdigital.money2.auth.UserTutorialStatusRepository;
import com.webdigital.money2.auth.TutorialRegionAccessService;
import com.webdigital.money2.shared.ApiException;
import com.webdigital.money2.shared.PageResponse;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UserManagementService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");

    private final UserAccountRepository userRepository;
    private final UserTutorialStatusRepository tutorialStatusRepository;
    private final RegionRepository regionRepository;
    private final UserRegionRepository userRegionRepository;
    private final TutorialRegionAccessService tutorialRegionAccessService;
    private final BCryptPasswordEncoder passwordEncoder = new BCryptPasswordEncoder();

    public UserManagementService(
            UserAccountRepository userRepository,
            UserTutorialStatusRepository tutorialStatusRepository,
            RegionRepository regionRepository,
            UserRegionRepository userRegionRepository,
            TutorialRegionAccessService tutorialRegionAccessService) {
        this.userRepository = userRepository;
        this.tutorialStatusRepository = tutorialStatusRepository;
        this.regionRepository = regionRepository;
        this.userRegionRepository = userRegionRepository;
        this.tutorialRegionAccessService = tutorialRegionAccessService;
    }

    @Transactional(readOnly = true)
    public PageResponse<UserSummaryResponse> search(String rawQuery, int page, int size) {
        String query = normalizeSearch(rawQuery);
        int pageSize = Math.max(10, Math.min(size, 100));
        Page<UserAccount> result = userRepository.search(
                query,
                PageRequest.of(Math.max(page, 0), pageSize));
        List<UserSummaryResponse> items = result.getContent().stream()
                .map(this::toSummary)
                .toList();
        return PageResponse.from(result, items);
    }

    @Transactional(readOnly = true)
    public UserDetailResponse getById(Long id) {
        return toDetail(requireUser(id));
    }

    @Transactional(readOnly = true)
    public UserDetailResponse getProfile(Long id) {
        UserAccount user = requireUser(id);
        List<Long> assignedIds = userRegionRepository.findRegionIdsByUserId(id);
        List<RegionOptionResponse> regions = regionRepository.findAllById(assignedIds)
                .stream()
                .sorted(java.util.Comparator
                        .comparing(
                                (Region region) -> clean(region.getDescription()),
                                String.CASE_INSENSITIVE_ORDER)
                        .thenComparing(Region::getId))
                .map(region -> new RegionOptionResponse(
                        region.getId(), clean(region.getDescription()), true))
                .toList();
        return toDetailResponse(user, regions);
    }

    @Transactional(readOnly = true)
    public List<RegionOptionResponse> getRegionOptions() {
        return regionRepository.findAllByOrderByDescriptionAsc().stream()
                .map(region -> new RegionOptionResponse(
                        region.getId(), clean(region.getDescription()), false))
                .toList();
    }

    @Transactional
    public UserDetailResponse create(UserCreateRequest request) {
        String username = normalizeUsername(request.username());
        String email = nullableClean(request.email());
        validateUnique(username, email, null);

        UserAccount user = new UserAccount();
        applyIdentity(user, request.firstName(), request.lastName(), username, email);
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setEnabled(request.enabled());
        user.setLocked(false);
        user.setExpired(false);
        user.setCredentialsExpired(false);
        user.setForcePasswordChange(request.forcePasswordChange());
        user.setAdministrator(request.administrator());
        user.setReadOnly(!request.canEdit());
        user.setCollector(Boolean.TRUE.equals(request.collector()));

        UserAccount saved = userRepository.saveAndFlush(user);
        replaceRegions(saved, request.regionIds());
        tutorialRegionAccessService.synchronize(saved);
        return toDetail(saved);
    }

    @Transactional
    public UserDetailResponse update(Long id, UserUpdateRequest request) {
        UserAccount user = requireUser(id);
        String username = normalizeUsername(request.username());
        String email = nullableClean(request.email());
        validateUnique(username, email, id);

        applyIdentity(user, request.firstName(), request.lastName(), username, email);
        user.setEnabled(request.enabled());
        user.setLocked(request.locked());
        user.setExpired(request.expired());
        user.setCredentialsExpired(request.credentialsExpired());
        user.setForcePasswordChange(request.forcePasswordChange());
        user.setAdministrator(request.administrator());
        user.setReadOnly(!request.canEdit());
        if (request.collector() != null) {
            user.setCollector(request.collector());
        }

        UserAccount saved = userRepository.saveAndFlush(user);
        replaceRegions(saved, request.regionIds());
        updateTutorialVisibility(saved.getId(), request.showTutorial());
        tutorialRegionAccessService.synchronize(saved);
        return toDetail(saved);
    }

    @Transactional
    public void changePassword(Long id, ChangePasswordRequest request) {
        UserAccount user = requireUser(id);
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setCredentialsExpired(false);
        user.setForcePasswordChange(false);
        userRepository.saveAndFlush(user);
    }

    private UserAccount requireUser(Long id) {
        return userRepository.findById(id)
                .orElseThrow(() -> new ApiException(
                        HttpStatus.NOT_FOUND,
                        "Usuário não encontrado."));
    }

    private void validateUnique(String username, String email, Long currentId) {
        boolean usernameExists = currentId == null
                ? userRepository.existsByUsernameIgnoreCase(username)
                : userRepository.existsByUsernameIgnoreCaseAndIdNot(username, currentId);
        if (usernameExists) {
            throw new ApiException(HttpStatus.CONFLICT, "Usuário já cadastrado.");
        }

        if (email == null) {
            return;
        }
        boolean emailExists = currentId == null
                ? userRepository.existsByEmailIgnoreCase(email)
                : userRepository.existsByEmailIgnoreCaseAndIdNot(email, currentId);
        if (emailExists) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "Já existe um usuário cadastrado com o e-mail informado.");
        }
    }

    private void applyIdentity(
            UserAccount user,
            String firstName,
            String lastName,
            String username,
            String email) {
        user.setFirstName(clean(firstName));
        user.setLastName(nullableClean(lastName));
        user.setUsername(username);
        user.setEmail(email);
    }

    private void replaceRegions(UserAccount user, Set<Long> requestedRegionIds) {
        Long userId = user.getId();
        Set<Long> regionIds = requestedRegionIds == null
                ? new HashSet<>()
                : new HashSet<>(requestedRegionIds);

        Long tutorialRegionId = tutorialRegionAccessService.tutorialRegionId();
        if (!tutorialRegionAccessService.isPermanentUser(user)
                && tutorialRegionId != null) {
            regionIds.remove(tutorialRegionId);
        }

        if (!regionIds.isEmpty()) {
            Set<Long> existingIds = regionRepository.findAllById(regionIds).stream()
                    .map(Region::getId)
                    .collect(java.util.stream.Collectors.toSet());
            if (!existingIds.equals(regionIds)) {
                throw new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "Uma ou mais regiões informadas não existem.");
            }
        }

        userRegionRepository.deleteByUserId(userId);
        if (regionIds.isEmpty()) {
            return;
        }

        LocalDateTime timestamp = LocalDateTime.now(BUSINESS_ZONE);
        List<UserRegion> assignments = regionIds.stream()
                .sorted()
                .map(regionId -> new UserRegion(userId, regionId, timestamp))
                .toList();
        userRegionRepository.saveAll(assignments);
    }

    private void updateTutorialVisibility(Long userId, Boolean showTutorial) {
        if (showTutorial == null) return;
        if (showTutorial) {
            tutorialStatusRepository.deleteById(userId);
            return;
        }
        if (!tutorialStatusRepository.existsById(userId)) {
            tutorialStatusRepository.save(new UserTutorialStatus(
                    userId,
                    LocalDateTime.now(BUSINESS_ZONE)));
        }
    }

    private UserSummaryResponse toSummary(UserAccount user) {
        return new UserSummaryResponse(
                user.getId(),
                displayName(user),
                user.getUsername(),
                nullableClean(user.getEmail()),
                user.isEnabled(),
                user.isAdministrator(),
                !user.isReadOnly(),
                user.isCollector(),
                user.getLastAccess());
    }

    private UserDetailResponse toDetail(UserAccount user) {
        Set<Long> assignedIds = new HashSet<>(
                userRegionRepository.findRegionIdsByUserId(user.getId()));
        List<RegionOptionResponse> regions = regionRepository
                .findAllByOrderByDescriptionAsc()
                .stream()
                .map(region -> new RegionOptionResponse(
                        region.getId(),
                        clean(region.getDescription()),
                        assignedIds.contains(region.getId())))
                .toList();

        return toDetailResponse(user, regions);
    }

    private UserDetailResponse toDetailResponse(
            UserAccount user,
            List<RegionOptionResponse> regions) {
        return new UserDetailResponse(
                user.getId(),
                clean(user.getFirstName()),
                nullableClean(user.getLastName()),
                displayName(user),
                user.getUsername(),
                nullableClean(user.getEmail()),
                user.isEnabled(),
                user.isLocked(),
                user.isExpired(),
                user.isCredentialsExpired(),
                user.isForcePasswordChange(),
                user.isAdministrator(),
                !user.isReadOnly(),
                user.isCollector(),
                tutorialStatusRepository.existsById(user.getId()),
                user.getLastAccess(),
                regions);
    }

    private String displayName(UserAccount user) {
        String name = String.join(
                " ",
                clean(user.getFirstName()),
                clean(user.getLastName())).trim();
        return name.isBlank() ? user.getUsername() : name;
    }

    private String normalizeUsername(String value) {
        return clean(value).toUpperCase(Locale.ROOT);
    }

    private String normalizeSearch(String value) {
        String normalized = clean(value);
        return normalized.length() > 80 ? normalized.substring(0, 80) : normalized;
    }

    private String nullableClean(String value) {
        String cleaned = clean(value);
        return cleaned.isEmpty() ? null : cleaned;
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
