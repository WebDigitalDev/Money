package com.webdigital.money2.regions;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiException;
import com.webdigital.money2.users.Region;
import com.webdigital.money2.users.RegionRepository;
import com.webdigital.money2.users.UserRegion;
import com.webdigital.money2.users.UserRegionRepository;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RegionManagementService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");

    private final RegionRepository regionRepository;
    private final UserRegionRepository userRegionRepository;

    public RegionManagementService(
            RegionRepository regionRepository,
            UserRegionRepository userRegionRepository) {
        this.regionRepository = regionRepository;
        this.userRegionRepository = userRegionRepository;
    }

    @Transactional(readOnly = true)
    public RegionListResponse search(
            UserAccount user,
            String rawQuery,
            LocalDate startDate,
            LocalDate endDate,
            String rawRegionIds) {
        return searchInternal(user, rawQuery, startDate, endDate, rawRegionIds);
    }

    @Transactional(readOnly = true, timeout = 25)
    public RegionListResponse searchForAssistant(
            UserAccount user,
            String rawQuery,
            LocalDate startDate,
            LocalDate endDate,
            String rawRegionIds) {
        return searchInternal(user, rawQuery, startDate, endDate, rawRegionIds);
    }

    private RegionListResponse searchInternal(
            UserAccount user,
            String rawQuery,
            LocalDate startDate,
            LocalDate endDate,
            String rawRegionIds) {
        validatePeriod(startDate, endDate);
        String query = clean(rawQuery).toLowerCase(Locale.ROOT);
        Set<Long> requestedIds = parseRegionIds(rawRegionIds);

        List<RegionSummaryResponse> items = regionRepository
                .findSummaries(user.getId(), startDate, endDate)
                .stream()
                .map(this::toSummary)
                .filter(item -> requestedIds.isEmpty() || requestedIds.contains(item.id()))
                .filter(item -> query.isEmpty() || matches(item, query))
                .toList();

        return new RegionListResponse(items, total(items), startDate, endDate);
    }

    @Transactional(readOnly = true)
    public List<RegionOptionResponse> options(UserAccount user) {
        return options(user, false);
    }

    @Transactional(readOnly = true)
    public List<RegionOptionResponse> options(UserAccount user, boolean tutorial) {
        if (tutorial) {
            return regionRepository.findTutorialRegions().stream()
                    .limit(1)
                    .map(region -> new RegionOptionResponse(
                            region.getId(), "TUTORIAL"))
                    .toList();
        }
        return regionRepository.findAccessibleByUserId(user.getId()).stream()
                .map(region -> new RegionOptionResponse(
                        region.getId(), displayName(region)))
                .toList();
    }

    @Transactional(readOnly = true)
    public RegionDetailResponse getById(UserAccount user, Long id) {
        return toDetail(requireAccessible(user, id));
    }

    @Transactional
    public RegionDetailResponse create(UserAccount user, RegionRequest request) {
        requireEditable(user);
        LocalDateTime now = LocalDateTime.now(BUSINESS_ZONE);
        Region region = new Region();
        apply(region, request);
        region.setCreatedAt(now);
        region.setUpdatedAt(now);
        Region saved = regionRepository.saveAndFlush(region);
        userRegionRepository.save(new UserRegion(user.getId(), saved.getId(), now));
        return toDetail(saved);
    }

    @Transactional
    public RegionDetailResponse update(
            UserAccount user,
            Long id,
            RegionRequest request) {
        requireEditable(user);
        Region region = requireAccessible(user, id);
        apply(region, request);
        region.setUpdatedAt(LocalDateTime.now(BUSINESS_ZONE));
        return toDetail(regionRepository.saveAndFlush(region));
    }

    @Transactional
    public void delete(UserAccount user, Long id) {
        requireEditable(user);
        Region region = requireAccessible(user, id);
        if (regionRepository.countBusinessReferences(id) > 0) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "A região não pode ser excluída porque já possui dados vinculados.");
        }

        try {
            userRegionRepository.deleteByRegionId(id);
            userRegionRepository.flush();
            regionRepository.delete(region);
            regionRepository.flush();
        } catch (DataIntegrityViolationException exception) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "A região não pode ser excluída porque já está em uso.");
        }
    }

    private Region requireAccessible(UserAccount user, Long id) {
        if (!regionRepository.isAccessible(id, user.getId())) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Região não encontrada.");
        }
        return regionRepository.findById(id)
                .orElseThrow(() -> new ApiException(
                        HttpStatus.NOT_FOUND, "Região não encontrada."));
    }

    private void requireEditable(UserAccount user) {
        if (!user.isAdministrator()) {
            throw new ApiException(
                    HttpStatus.FORBIDDEN,
                    "Somente administradores podem alterar regiões.");
        }
    }

    private void apply(Region region, RegionRequest request) {
        region.setDescription(clean(request.description()));
        region.setResponsiblePeople(nullableClean(request.responsiblePeople()));
        region.setParentDescription(nullableClean(request.parentDescription()));
        region.setLoanMessage(nullableClean(request.loanMessage()));
        region.setRefinancedLoanMessage(nullableClean(request.refinancedLoanMessage()));
        region.setCollectionMessage(nullableClean(request.collectionMessage()));
        region.setCollectionLinkMessage(nullableClean(request.collectionLinkMessage()));
        region.setOverdueMessage(nullableClean(request.overdueMessage()));
        region.setClientOwnerRequired(request.clientOwnerRequired());
    }

    private RegionDetailResponse toDetail(Region region) {
        return new RegionDetailResponse(
                region.getId(),
                clean(region.getDescription()),
                nullableClean(region.getResponsiblePeople()),
                nullableClean(region.getParentDescription()),
                region.getCreatedAt(),
                region.getUpdatedAt(),
                nullableClean(region.getLoanMessage()),
                nullableClean(region.getRefinancedLoanMessage()),
                nullableClean(region.getCollectionMessage()),
                nullableClean(region.getCollectionLinkMessage()),
                nullableClean(region.getOverdueMessage()),
                region.isClientOwnerRequired());
    }

    private RegionSummaryResponse toSummary(Object[] row) {
        return new RegionSummaryResponse(
                number(row[0]).longValue(),
                clean((String) row[1]),
                nullableClean((String) row[2]),
                number(row[3]).intValue(),
                number(row[4]).intValue(),
                number(row[5]).intValue(),
                number(row[6]).intValue(),
                decimal(row[7]),
                decimal(row[8]),
                decimal(row[9]),
                decimal(row[10]),
                decimal(row[11]),
                decimal(row[12]),
                decimal(row[13]));
    }

    private RegionTotalsResponse total(List<RegionSummaryResponse> items) {
        int active = 0;
        int missing = 0;
        int current = 0;
        int overdue = 0;
        BigDecimal overdueAmount = BigDecimal.ZERO;
        BigDecimal received = BigDecimal.ZERO;
        BigDecimal dueToday = BigDecimal.ZERO;
        BigDecimal receivable = BigDecimal.ZERO;
        BigDecimal missingAmount = BigDecimal.ZERO;
        BigDecimal profit = BigDecimal.ZERO;
        BigDecimal loaned = BigDecimal.ZERO;

        for (RegionSummaryResponse item : items) {
            active += item.activeClients();
            missing += item.missingClients();
            current += item.currentClients();
            overdue += item.overdueClients();
            overdueAmount = overdueAmount.add(item.overdueAmount());
            received = received.add(item.receivedAmount());
            dueToday = dueToday.add(item.dueTodayAmount());
            receivable = receivable.add(item.receivableAmount());
            missingAmount = missingAmount.add(item.missingAmount());
            profit = profit.add(item.profitAmount());
            loaned = loaned.add(item.loanedAmount());
        }

        return new RegionTotalsResponse(
                items.size(), active, missing, current, overdue,
                overdueAmount, received, dueToday, receivable,
                missingAmount, profit, loaned);
    }

    private boolean matches(RegionSummaryResponse item, String query) {
        return item.description().toLowerCase(Locale.ROOT).contains(query)
                || clean(item.responsiblePeople()).toLowerCase(Locale.ROOT).contains(query)
                || item.id().toString().contains(query);
    }

    private Set<Long> parseRegionIds(String value) {
        Set<Long> result = new HashSet<>();
        if (value == null || value.isBlank()) {
            return result;
        }
        for (String part : value.split(",")) {
            try {
                long id = Long.parseLong(part.trim());
                if (id >= 0) {
                    result.add(id);
                }
            } catch (NumberFormatException exception) {
                throw new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "Uma ou mais regiões informadas no filtro são inválidas.");
            }
        }
        return result;
    }

    private void validatePeriod(LocalDate startDate, LocalDate endDate) {
        if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "A data inicial deve ser anterior à data final.");
        }
    }

    private String displayName(Region region) {
        String description = clean(region.getDescription());
        String responsible = clean(region.getResponsiblePeople());
        if (description.isEmpty()) {
            description = "Região #" + region.getId();
        }
        return responsible.isEmpty() ? description : description + " - " + responsible;
    }

    private Number number(Object value) {
        return value instanceof Number number ? number : 0;
    }

    private BigDecimal decimal(Object value) {
        if (value == null) {
            return BigDecimal.ZERO.setScale(2);
        }
        if (value instanceof BigDecimal decimal) {
            return decimal.setScale(2, RoundingMode.HALF_UP);
        }
        return new BigDecimal(value.toString()).setScale(2, RoundingMode.HALF_UP);
    }

    private String nullableClean(String value) {
        String cleaned = clean(value);
        return cleaned.isEmpty() ? null : cleaned;
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
