package com.webdigital.money2.dashboard;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.dashboard.DashboardModels.RegionOption;
import com.webdigital.money2.dashboard.DashboardModels.Response;
import com.webdigital.money2.goals.FinancialGoalService;
import com.webdigital.money2.shared.ApiException;
import com.webdigital.money2.users.Region;
import com.webdigital.money2.users.RegionRepository;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DashboardService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");

    private final RegionRepository regionRepository;
    private final DashboardRepository dashboardRepository;
    private final FinancialGoalService financialGoalService;

    public DashboardService(
            RegionRepository regionRepository,
            DashboardRepository dashboardRepository,
            FinancialGoalService financialGoalService) {
        this.regionRepository = regionRepository;
        this.dashboardRepository = dashboardRepository;
        this.financialGoalService = financialGoalService;
    }

    @Transactional(readOnly = true)
    public Response load(
            UserAccount user,
            Long requestedRegionId,
            String rawRequestedRegionIds) {
        return load(user, requestedRegionId, rawRequestedRegionIds, false);
    }

    @Transactional(readOnly = true)
    public Response load(
            UserAccount user,
            Long requestedRegionId,
            String rawRequestedRegionIds,
            boolean tutorial) {
        if (tutorial) {
            Region tutorialRegion = regionRepository.findTutorialRegions().stream()
                    .findFirst()
                    .orElseThrow(() -> new ApiException(
                            HttpStatus.NOT_FOUND,
                            "A região TUTORIAL não foi encontrada."));
            List<Long> tutorialIds = List.of(tutorialRegion.getId());
            return new Response(
                    displayUserName(user),
                    LocalDate.now(BUSINESS_ZONE),
                    tutorialRegion.getId(),
                    "TUTORIAL",
                    tutorialIds,
                    List.of(new RegionOption(tutorialRegion.getId(), "TUTORIAL")),
                    dashboardRepository.metrics(user.getId(), tutorialIds, true),
                    dashboardRepository.financial(user.getId(), tutorialIds, true),
                    List.of(),
                    dashboardRepository.dueToday(user.getId(), tutorialIds, true));
        }
        List<Region> accessible = regionRepository.findAccessibleByUserId(user.getId());
        if (accessible.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Seu usuário não possui regiões vinculadas.");
        }
        List<Long> requestedIds = parseRegionIds(rawRequestedRegionIds);
        if (requestedIds.isEmpty() && requestedRegionId != null) {
            requestedIds = List.of(requestedRegionId);
        }
        if (requestedIds.isEmpty()) {
            requestedIds = List.of(accessible.get(0).getId());
        }
        Set<Long> accessibleIds = accessible.stream()
                .map(Region::getId)
                .collect(java.util.stream.Collectors.toSet());
        if (!accessibleIds.containsAll(requestedIds)) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Uma ou mais regiões selecionadas não estão disponíveis para seu usuário.");
        }
        List<Long> selectedIds = List.copyOf(requestedIds);
        Region selected = accessible.stream()
                .filter(region -> region.getId().equals(selectedIds.get(0)))
                .findFirst()
                .orElseThrow();
        List<RegionOption> options = accessible.stream()
                .map(region -> new RegionOption(region.getId(), displayName(region)))
                .toList();
        String selectedName = selectedIds.size() == 1
                ? displayName(selected)
                : selectedIds.size() + " regiões selecionadas";
        return new Response(
                displayUserName(user),
                LocalDate.now(BUSINESS_ZONE),
                selected.getId(),
                selectedName,
                selectedIds,
                options,
                dashboardRepository.metrics(user.getId(), selectedIds),
                dashboardRepository.financial(user.getId(), selectedIds),
                financialGoalService.listActive(user, selectedIds),
                dashboardRepository.dueToday(user.getId(), selectedIds));
    }

    private List<Long> parseRegionIds(String rawValue) {
        String value = clean(rawValue);
        if (value.isEmpty()) return List.of();
        LinkedHashSet<Long> ids = new LinkedHashSet<>();
        for (String part : value.split(",")) {
            try {
                long id = Long.parseLong(part.trim());
                if (id > 0) ids.add(id);
            } catch (NumberFormatException exception) {
                throw new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "A seleção de regiões é inválida.");
            }
        }
        return List.copyOf(ids);
    }

    private String displayName(Region region) {
        String description = clean(region.getDescription());
        String responsible = clean(region.getResponsiblePeople());
        String base = description.isEmpty() ? "Região #" + region.getId() : description;
        return responsible.isEmpty() ? base : base + " - " + responsible;
    }

    private String displayUserName(UserAccount user) {
        String firstName = clean(user.getFirstName());
        if (!firstName.isEmpty()) return firstName;
        String username = clean(user.getUsername());
        if (username.isEmpty()) return "Usuário";
        return username.substring(0, 1).toUpperCase() + username.substring(1).toLowerCase();
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
