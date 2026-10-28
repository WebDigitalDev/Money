package com.webdigital.money2.goals;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiException;
import com.webdigital.money2.users.Region;
import com.webdigital.money2.users.RegionRepository;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.LinkedHashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FinancialGoalService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");
    private static final long COMPLETED_GOAL_VISIBILITY_DAYS = 2;

    private final FinancialGoalRepository goalRepository;
    private final FinancialGoalProgressRepository progressRepository;
    private final RegionRepository regionRepository;

    public FinancialGoalService(
            FinancialGoalRepository goalRepository,
            FinancialGoalProgressRepository progressRepository,
            RegionRepository regionRepository) {
        this.goalRepository = goalRepository;
        this.progressRepository = progressRepository;
        this.regionRepository = regionRepository;
    }

    @Transactional
    public List<FinancialGoalResponse> list(UserAccount user) {
        Map<Long, Region> regions = accessibleRegions(user);
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        ensureRecurringGoals(today);
        LocalDate oldestVisibleEndDate = today.minusDays(COMPLETED_GOAL_VISIBILITY_DAYS);
        List<FinancialGoalEntity> goals = goalRepository
                .findAccessibleVisibleSince(user.getId(), oldestVisibleEndDate).stream()
                .filter(goal -> regions.keySet().containsAll(goal.getRegionIds()))
                .toList();
        Map<Long, BigDecimal> amounts = progressRepository.achievedActive(goals.stream()
                .filter(g -> !g.getType().isClient() && !today.isBefore(g.getStartDate())
                        && g.getFinalAchievedAmount() == null)
                .map(FinancialGoalEntity::getId).toList());
        Map<Long, ClientGoalStats> clients = progressRepository.clientStats(goals.stream()
                .filter(g -> g.getType().isClient() && g.getFinalClientStats() == null)
                .map(FinancialGoalEntity::getId).toList());
        return goals.stream().map(goal -> goal.getType().isClient()
                ? clientResponse(goal, regions, today, user, clients.getOrDefault(goal.getId(), ClientGoalStats.EMPTY))
                : response(goal, regions, today, user, amounts.get(goal.getId()))).toList();
    }

    @Transactional
    public FinancialGoalResponse create(UserAccount user, FinancialGoalRequest request) {
        requireAdministrator(user);
        validate(request);
        List<Long> regionIds = effectiveRegionIds(request);
        Map<Long, Region> regions = requireAccessibleRegions(user, regionIds);
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        LocalDateTime now = LocalDateTime.now(BUSINESS_ZONE);
        FinancialGoalEntity goal = new FinancialGoalEntity();
        apply(goal, request, regionIds);
        goal.setCreatedBy(user.getId());
        goal.setCreatedAt(now);
        goal.setUpdatedAt(now);
        FinancialGoalEntity saved = goalRepository.saveAndFlush(goal);
        return response(saved, regions, today, user);
    }

    @Transactional
    public FinancialGoalResponse update(
            UserAccount user,
            long id,
            FinancialGoalRequest request) {
        requireAdministrator(user);
        validate(request);
        FinancialGoalEntity goal = requireAccessibleGoal(user, id);
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        if (today.isAfter(goal.getEndDate())) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "Metas encerradas não podem mais ser editadas.");
        }
        List<Long> regionIds = effectiveRegionIds(request);
        Map<Long, Region> regions = requireAccessibleRegions(user, regionIds);
        apply(goal, request, regionIds);
        goal.setUpdatedAt(LocalDateTime.now(BUSINESS_ZONE));
        return response(
                goalRepository.saveAndFlush(goal),
                regions,
                today,
                user);
    }

    @Transactional
    public List<FinancialGoalResponse> listActive(
            UserAccount user,
            List<Long> selectedRegionIds) {
        Map<Long, Region> regions = accessibleRegions(user);
        Set<Long> selected = selectedRegionIds == null
                ? Set.of()
                : selectedRegionIds.stream()
                        .filter(java.util.Objects::nonNull)
                        .filter(id -> id > 0)
                        .collect(Collectors.toSet());
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        ensureRecurringGoals(today);
        List<FinancialGoalEntity> activeGoals = goalRepository
                .findAccessibleActiveOn(user.getId(), today).stream()
                .filter(goal -> regions.keySet().containsAll(goal.getRegionIds()))
                .filter(goal -> status(goal, today) == FinancialGoalStatus.ATIVA)
                .filter(goal -> selected.isEmpty()
                        || goal.getRegionIds().stream().anyMatch(selected::contains))
                .toList();
        Map<Long, BigDecimal> progressByGoal = progressRepository.achievedActive(
                activeGoals.stream().filter(goal -> !goal.getType().isClient())
                        .map(FinancialGoalEntity::getId).toList());
        Map<Long, ClientGoalStats> clients = progressRepository.clientStats(activeGoals.stream()
                .filter(goal -> goal.getType().isClient()).map(FinancialGoalEntity::getId).toList());
        return activeGoals.stream()
                .map(goal -> goal.getType().isClient()
                        ? clientResponse(goal, regions, today, user, clients.getOrDefault(goal.getId(), ClientGoalStats.EMPTY))
                        : response(
                        goal,
                        regions,
                        today,
                        user,
                        progressByGoal.getOrDefault(goal.getId(), BigDecimal.ZERO)))
                .toList();
    }

    @Transactional
    public void delete(UserAccount user, long id) {
        requireAdministrator(user);
        FinancialGoalEntity goal = requireAccessibleGoal(user, id);
        if (goal.getPreviousGoalId() != null) {
            goalRepository.findById(goal.getPreviousGoalId()).ifPresent(previous -> {
                previous.setRepeatFrequency(false);
                previous.setUpdatedAt(LocalDateTime.now(BUSINESS_ZONE));
            });
        }
        goalRepository.delete(goal);
        goalRepository.flush();
    }

    @Scheduled(
            initialDelayString = "${money.goals.recurrence-initial-delay-ms:15000}",
            fixedDelayString = "${money.goals.recurrence-delay-ms:300000}")
    @Transactional
    public void createDueRecurringGoals() {
        ensureRecurringGoals(LocalDate.now(BUSINESS_ZONE));
    }

    private FinancialGoalResponse response(
            FinancialGoalEntity goal,
            Map<Long, Region> regions,
            LocalDate today,
            UserAccount user) {
        return response(goal, regions, today, user, null);
    }

    private FinancialGoalResponse response(
            FinancialGoalEntity goal,
            Map<Long, Region> regions,
            LocalDate today,
            UserAccount user,
            BigDecimal activeProgress) {
        if (goal.getType().isClient()) {
            ClientGoalStats stats = progressRepository.clientStats(List.of(goal.getId()))
                    .getOrDefault(goal.getId(), ClientGoalStats.EMPTY);
            return clientResponse(goal, regions, today, user, stats);
        }
        List<Long> regionIds = goal.getRegionIds().stream().sorted().toList();
        List<String> regionNames = regionIds.stream()
                .map(regions::get)
                .map(this::displayName)
                .toList();
        FinancialGoalStatus goalStatus = status(goal, today);
        BigDecimal achieved;
        if (goalStatus == FinancialGoalStatus.ENCERRADA
                && goal.getFinalAchievedAmount() != null) {
            achieved = money(goal.getFinalAchievedAmount());
        } else if (activeProgress != null) {
            achieved = money(activeProgress);
            if (goalStatus == FinancialGoalStatus.ENCERRADA) {
                goal.setFinalAchievedAmount(achieved);
                goal.setFinalizedAt(LocalDateTime.now(BUSINESS_ZONE));
            }
        } else {
            LocalDate progressEnd = today.isBefore(goal.getEndDate())
                    ? today : goal.getEndDate();
            achieved = progressEnd.isBefore(goal.getStartDate())
                    ? BigDecimal.ZERO.setScale(2)
                    : achieved(goal.getType(), regionIds,
                            goal.getStartDate(), progressEnd);
            if (goalStatus == FinancialGoalStatus.ENCERRADA) {
                goal.setFinalAchievedAmount(achieved);
                goal.setFinalizedAt(LocalDateTime.now(BUSINESS_ZONE));
            }
        }
        BigDecimal target = money(goal.getTargetAmount());
        BigDecimal remaining = target.subtract(achieved)
                .max(BigDecimal.ZERO).setScale(2, RoundingMode.HALF_UP);
        BigDecimal percentage = target.signum() == 0
                ? BigDecimal.ZERO
                : achieved.multiply(BigDecimal.valueOf(100))
                        .divide(target, 2, RoundingMode.HALF_UP);
        return new FinancialGoalResponse(
                goal.getId(),
                goal.getRegionId(),
                regionNames.size() > 1 ? "GRUPO DE REGIÕES" : regionNames.get(0),
                goal.getType(),
                target,
                achieved,
                remaining,
                percentage,
                goal.getStartDate(),
                goal.getEndDate(),
                goalStatus,
                goal.getCreatedAt(),
                goal.getUpdatedAt(),
                user.isAdministrator(),
                regionIds,
                regionNames,
                null,
                goal.isRepeatFrequency());
    }

    private FinancialGoalStatus status(FinancialGoalEntity goal, LocalDate today) {
        if (today.isBefore(goal.getStartDate())) return FinancialGoalStatus.FUTURA;
        if (today.isAfter(goal.getEndDate())) return FinancialGoalStatus.ENCERRADA;
        return FinancialGoalStatus.ATIVA;
    }

    private void apply(
            FinancialGoalEntity goal,
            FinancialGoalRequest request,
            List<Long> regionIds) {
        goal.setRegionIds(new LinkedHashSet<>(regionIds));
        goal.setType(request.type());
        goal.setTargetAmount(money(request.targetAmount()));
        goal.setStartDate(request.startDate());
        goal.setEndDate(request.endDate());
        goal.setRepeatFrequency(Boolean.TRUE.equals(request.repeatFrequency()));
    }

    private void validate(FinancialGoalRequest request) {
        BigDecimal target = request.targetAmount();
        if (target == null || target.signum() < 0
                || (request.type() != FinancialGoalType.CLIENTES_ATRASO && target.signum() == 0)
                || (request.type().isPercentage() && target.compareTo(BigDecimal.valueOf(100)) > 0)
                || (request.type() == FinancialGoalType.CLIENTES_ATIVOS && target.stripTrailingZeros().scale() > 0)) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "Informe uma quantidade inteira positiva ou um percentual entre 0 e 100 (zero somente para atraso).");
        }
        if (effectiveRegionIds(request).isEmpty()) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "Selecione ao menos uma região para a meta financeira.");
        }
        if (request.startDate().isAfter(request.endDate())) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "A data inicial deve ser anterior ou igual à data final.");
        }
        if (Boolean.TRUE.equals(request.repeatFrequency()) && !request.type().isClient()) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "A repetição de frequência está disponível somente para metas de clientes.");
        }
    }

    private FinancialGoalEntity requireAccessibleGoal(UserAccount user, long id) {
        FinancialGoalEntity goal = goalRepository.findById(id)
                .orElseThrow(() -> new ApiException(
                        HttpStatus.NOT_FOUND, "Meta financeira não encontrada."));
        if (!goal.getRegionIds().stream()
                .allMatch(regionId -> regionRepository.isAccessible(regionId, user.getId()))) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Meta financeira não encontrada.");
        }
        return goal;
    }

    private Map<Long, Region> requireAccessibleRegions(
            UserAccount user,
            List<Long> regionIds) {
        Map<Long, Region> accessible = new LinkedHashMap<>();
        for (long regionId : regionIds) {
            if (!regionRepository.isAccessible(regionId, user.getId())) {
                throw new ApiException(HttpStatus.NOT_FOUND, "Região não encontrada.");
            }
            Region region = regionRepository.findById(regionId)
                    .orElseThrow(() -> new ApiException(
                            HttpStatus.NOT_FOUND, "Região não encontrada."));
            accessible.put(regionId, region);
        }
        return accessible;
    }

    private BigDecimal achieved(
            FinancialGoalType type,
            List<Long> regionIds,
            LocalDate startDate,
            LocalDate endDate) {
        BigDecimal value = regionIds.size() == 1
                ? progressRepository.achieved(
                        type, regionIds.get(0), startDate, endDate)
                : progressRepository.achieved(type, regionIds, startDate, endDate);
        return money(value);
    }

    private List<Long> effectiveRegionIds(FinancialGoalRequest request) {
        LinkedHashSet<Long> ids = new LinkedHashSet<>();
        if (request.regionIds() != null) {
            request.regionIds().stream()
                    .filter(java.util.Objects::nonNull)
                    .filter(id -> id > 0)
                    .forEach(ids::add);
        }
        if (ids.isEmpty() && request.regionId() != null && request.regionId() > 0) {
            ids.add(request.regionId());
        }
        return List.copyOf(ids);
    }

    private Map<Long, Region> accessibleRegions(UserAccount user) {
        return regionRepository.findAccessibleByUserId(user.getId()).stream()
                .collect(Collectors.toMap(Region::getId, Function.identity()));
    }

    private void requireAdministrator(UserAccount user) {
        if (!user.isAdministrator()) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Apenas administradores podem gerenciar metas financeiras.");
        }
    }

    private BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value)
                .setScale(2, RoundingMode.HALF_UP);
    }

    private String displayName(Region region) {
        if (region == null) return "Região";
        String description = clean(region.getDescription());
        String responsible = clean(region.getResponsiblePeople());
        String base = description.isEmpty() ? "Região #" + region.getId() : description;
        return responsible.isEmpty() ? base : base + " - " + responsible;
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private FinancialGoalResponse clientResponse(FinancialGoalEntity goal, Map<Long, Region> regions,
            LocalDate today, UserAccount user, ClientGoalStats current) {
        ClientGoalStats stats = goal.getFinalClientStats() == null ? current : goal.getFinalClientStats();
        FinancialGoalStatus state = status(goal, today);
        BigDecimal achieved = money(stats.achieved(goal.getType()));
        if (state == FinancialGoalStatus.ENCERRADA && goal.getFinalClientStats() == null) {
            goal.setFinalClientStats(stats);
            goal.setFinalAchievedAmount(achieved);
            goal.setFinalizedAt(LocalDateTime.now(BUSINESS_ZONE));
        }
        BigDecimal target = money(goal.getTargetAmount());
        BigDecimal remaining = (goal.getType() == FinancialGoalType.CLIENTES_ATRASO
                ? achieved.subtract(target) : target.subtract(achieved)).max(BigDecimal.ZERO);
        List<Long> ids = goal.getRegionIds().stream().sorted().toList();
        List<String> names = ids.stream().map(regions::get).map(this::displayName).toList();
        return new FinancialGoalResponse(goal.getId(), goal.getRegionId(),
                names.size() > 1 ? "GRUPO DE REGIÕES" : names.get(0), goal.getType(), target, achieved,
                remaining, state == FinancialGoalStatus.FUTURA ? BigDecimal.ZERO : stats.progress(goal.getType(), target),
                goal.getStartDate(), goal.getEndDate(), state, goal.getCreatedAt(), goal.getUpdatedAt(),
                user.isAdministrator(), ids, names, stats, goal.isRepeatFrequency());
    }

    private synchronized void ensureRecurringGoals(LocalDate today) {
        for (int pass = 0; pass < 32; pass++) {
            List<FinancialGoalEntity> due = goalRepository.findRecurringDue(today);
            if (due.isEmpty()) return;
            LocalDateTime now = LocalDateTime.now(BUSINESS_ZONE);
            for (FinancialGoalEntity previous : due) {
                long periodDays = Math.max(1,
                        ChronoUnit.DAYS.between(previous.getStartDate(), previous.getEndDate()) + 1);
                LocalDate nextStart = previous.getEndDate().plusDays(1);
                LocalDate nextEnd = nextStart.plusDays(periodDays - 1);
                if (nextEnd.isBefore(today)) {
                    long elapsed = Math.max(0, ChronoUnit.DAYS.between(nextStart, today));
                    long skippedPeriods = elapsed / periodDays;
                    nextStart = nextStart.plusDays(skippedPeriods * periodDays);
                    nextEnd = nextStart.plusDays(periodDays - 1);
                }
                FinancialGoalEntity next = new FinancialGoalEntity();
                next.setRegionIds(new LinkedHashSet<>(previous.getRegionIds()));
                next.setType(previous.getType());
                next.setTargetAmount(previous.getTargetAmount());
                next.setStartDate(nextStart);
                next.setEndDate(nextEnd);
                next.setCreatedBy(previous.getCreatedBy());
                next.setCreatedAt(now);
                next.setUpdatedAt(now);
                next.setRepeatFrequency(true);
                next.setPreviousGoalId(previous.getId());
                goalRepository.saveAndFlush(next);
            }
        }
    }
}
