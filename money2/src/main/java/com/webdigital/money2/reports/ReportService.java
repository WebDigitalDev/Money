package com.webdigital.money2.reports;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ReportService {

    private static final int EXPORT_PAGE_SIZE = 500_000;

    private final AuditHistoryRepository historyRepository;

    public ReportService(AuditHistoryRepository historyRepository) {
        this.historyRepository = historyRepository;
    }

    @Transactional(readOnly = true)
    public AuditHistoryPageResponse history(
            UserAccount user,
            LocalDate startDate,
            LocalDate endDate,
            String rawUsernames,
            String rawRegionIds,
            int page,
            int size) {
        validatePeriod(startDate, endDate);
        return historyRepository.search(
                user.getId(),
                startDate == null ? null : startDate.atStartOfDay(),
                endExclusive(endDate),
                parseUsernames(rawUsernames),
                parseRegionIds(rawRegionIds),
                Math.max(0, page),
                Math.max(25, Math.min(size, 500)));
    }

    @Transactional(readOnly = true)
    public AuditHistoryPageResponse exportHistory(
            UserAccount user,
            LocalDate startDate,
            LocalDate endDate,
            String rawUsernames,
            String rawRegionIds) {
        validatePeriod(startDate, endDate);
        return historyRepository.search(
                user.getId(),
                startDate == null ? null : startDate.atStartOfDay(),
                endExclusive(endDate),
                parseUsernames(rawUsernames),
                parseRegionIds(rawRegionIds),
                0,
                EXPORT_PAGE_SIZE);
    }

    @Transactional(readOnly = true)
    public List<String> users() {
        return historyRepository.users();
    }

    private LocalDateTime endExclusive(LocalDate endDate) {
        return endDate == null ? null : endDate.plusDays(1).atStartOfDay();
    }

    private void validatePeriod(LocalDate startDate, LocalDate endDate) {
        if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "A data inicial deve ser anterior à data final.");
        }
    }

    private Set<Long> parseRegionIds(String value) {
        Set<Long> result = new HashSet<>();
        if (value == null || value.isBlank()) return result;
        for (String part : value.split(",")) {
            try {
                long id = Long.parseLong(part.trim());
                if (id >= 0) result.add(id);
            } catch (NumberFormatException exception) {
                throw new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "Uma ou mais regiões informadas no filtro são inválidas.");
            }
        }
        return result;
    }

    private Set<String> parseUsernames(String value) {
        Set<String> result = new HashSet<>();
        if (value == null || value.isBlank()) return result;
        for (String part : value.split(",")) {
            String username = part.trim();
            if (!username.isEmpty()) result.add(username);
        }
        return result;
    }
}
