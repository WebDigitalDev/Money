package com.webdigital.money2.loans;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.auth.TutorialRegionAccessService;
import com.webdigital.money2.shared.ApiException;
import java.time.LocalDate;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class LoanManagementService {

    private static final int EXPORT_PAGE_SIZE = 500_000;

    private static final Map<String, String> STATUSES = Map.ofEntries(
            Map.entry("pendente aprovação", "Pendente Aprovação"),
            Map.entry("lançamento", "Lançamento"),
            Map.entry("em dia", "Em dia"),
            Map.entry("vence hoje", "Vence hoje"),
            Map.entry("desaparecido", "Desaparecido"),
            Map.entry("em atraso", "Em atraso"),
            Map.entry("cancelado", "Cancelado"),
            Map.entry("quitado", "Quitado"),
            Map.entry("renov/abat", "Renov/Abat"),
            Map.entry("refinanciado", "Refinanciado"));

    private final LoanQueryRepository loanRepository;
    private final TutorialRegionAccessService tutorialRegionAccessService;

    public LoanManagementService(
            LoanQueryRepository loanRepository,
            TutorialRegionAccessService tutorialRegionAccessService) {
        this.loanRepository = loanRepository;
        this.tutorialRegionAccessService = tutorialRegionAccessService;
    }

    @Transactional(readOnly = true)
    public LoanListResponse search(
            UserAccount user,
            String query,
            String rawStatuses,
            String rawRegionIds,
            boolean tutorial,
            LocalDate startDate,
            LocalDate endDate,
            int page,
            int size) {
        validatePeriod(startDate, endDate);
        int safePage = Math.max(0, page);
        int safeSize = Math.max(10, Math.min(size, 100));
        Long tutorialRegionId = tutorial
                ? requireTutorialRegionId()
                : null;
        return loanRepository.search(
                user.getId(),
                query,
                parseStatuses(rawStatuses),
                tutorial ? Set.of(tutorialRegionId) : parseRegionIds(rawRegionIds),
                tutorial,
                tutorialRegionId,
                startDate,
                endDate,
                safePage,
                safeSize);
    }

    @Transactional(readOnly = true)
    public LoanListResponse export(
            UserAccount user,
            String query,
            String rawStatuses,
            String rawRegionIds,
            boolean tutorial,
            LocalDate startDate,
            LocalDate endDate) {
        validatePeriod(startDate, endDate);
        Long tutorialRegionId = tutorial
                ? requireTutorialRegionId()
                : null;
        return loanRepository.search(
                user.getId(),
                query,
                parseStatuses(rawStatuses),
                tutorial ? Set.of(tutorialRegionId) : parseRegionIds(rawRegionIds),
                tutorial,
                tutorialRegionId,
                startDate,
                endDate,
                0,
                EXPORT_PAGE_SIZE);
    }

    private Long requireTutorialRegionId() {
        Long id = tutorialRegionAccessService.tutorialRegionId();
        if (id == null) {
            throw new ApiException(
                    HttpStatus.NOT_FOUND,
                    "A região TUTORIAL não foi encontrada.");
        }
        return id;
    }

    private void validatePeriod(LocalDate startDate, LocalDate endDate) {
        if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "A data inicial deve ser anterior à data final.");
        }
    }

    private Set<String> parseStatuses(String value) {
        if (value == null || value.isBlank()) return Set.of();
        Set<String> result = new LinkedHashSet<>();
        for (String part : value.split(",")) {
            String raw = part.trim();
            if (raw.isEmpty()) continue;
            String status = STATUSES.get(raw.toLowerCase(Locale.ROOT));
            if (status == null) {
                throw new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "Um ou mais status informados são inválidos.");
            }
            result.add(status);
        }
        return result;
    }

    private Set<Long> parseRegionIds(String value) {
        if (value == null || value.isBlank()) return Set.of();
        try {
            return Arrays.stream(value.split(","))
                    .map(String::trim)
                    .filter(part -> !part.isEmpty())
                    .map(Long::valueOf)
                    .filter(id -> id >= 0)
                    .collect(Collectors.toCollection(LinkedHashSet::new));
        } catch (NumberFormatException exception) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "Uma ou mais regiões informadas são inválidas.");
        }
    }
}
