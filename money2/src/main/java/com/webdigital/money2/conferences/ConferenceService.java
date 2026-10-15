package com.webdigital.money2.conferences;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.conferences.ConferenceRepository.DecisionTarget;
import com.webdigital.money2.loans.LoanDecisionRequest;
import com.webdigital.money2.loans.LoanDetailService;
import com.webdigital.money2.shared.ApiException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ConferenceService {

    private final ConferenceRepository repository;
    private final LoanDetailService loanDetailService;

    public ConferenceService(ConferenceRepository repository, LoanDetailService loanDetailService) {
        this.repository = repository;
        this.loanDetailService = loanDetailService;
    }

    @Transactional(readOnly = true)
    public ConferenceListResponse search(UserAccount user, String query, String category,
                                         String regionIds, int page, int size,
                                         boolean includeDetails) {
        requireAdministrator(user);
        int safePage = Math.max(0, page);
        int safeSize = Math.min(Math.max(size, 1), 200);
        return repository.search(user.getId(), query, types(category), ids(regionIds),
                safePage, safeSize, includeDetails);
    }

    @Transactional(readOnly = true)
    public List<ConferenceDetailResponse> details(UserAccount user, long conferenceId) {
        requireAdministrator(user);
        return repository.details(user.getId(), conferenceId);
    }

    @Transactional
    public ConferenceDecisionResponse decide(UserAccount user, long conferenceId,
                                               boolean approve, ConferenceDecisionRequest request) {
        requireAdministrator(user);
        String observation = normalize(request == null ? null : request.observation());
        if (!approve && observation == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o motivo do indeferimento.");
        }
        List<DecisionTarget> targets = repository.decisionTargets(user.getId(), conferenceId);
        if (targets.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Conferência não encontrada ou já processada.");
        }
        int processed = 0;
        for (DecisionTarget target : targets) {
            if (target.loanId() == null || target.loanId() <= 0) {
                throw new ApiException(HttpStatus.CONFLICT, "O contrato desta conferência não foi encontrado.");
            }
            loanDetailService.decideApproval(
                    user, target.loanId(), target.id(), approve, new LoanDecisionRequest(observation));
            processed++;
        }
        String message = approve
                ? ("PAGAMENTO".equals(targets.get(0).type())
                    ? "Pagamento conferido com sucesso."
                    : "Operação aprovada com sucesso.")
                : ("PAGAMENTO".equals(targets.get(0).type())
                    ? "Pagamento indeferido."
                    : "Operação reprovada.");
        return new ConferenceDecisionResponse(message, processed);
    }

    private void requireAdministrator(UserAccount user) {
        if (user == null || !user.isAdministrator()) {
            throw new ApiException(HttpStatus.FORBIDDEN,
                    "Somente administradores podem acessar as conferências.");
        }
    }

    private List<String> types(String category) {
        String value = category == null ? "" : category.trim().toUpperCase(Locale.ROOT);
        return switch (value) {
            case "PAYMENT" -> List.of("PAGAMENTO");
            case "LOAN" -> List.of("EMPRESTIMO");
            case "NEGOTIATION" -> List.of("REFINANCIAMENTO", "RENOVACAO");
            case "CLOSURE" -> List.of("FINALIZACAO");
            default -> List.of();
        };
    }

    private List<Long> ids(String values) {
        if (values == null || values.isBlank()) return List.of();
        List<Long> result = new ArrayList<>();
        for (String value : values.split(",")) {
            try {
                long id = Long.parseLong(value.trim());
                if (id > 0) result.add(id);
            } catch (NumberFormatException ignored) {
            }
        }
        return result.stream().distinct().toList();
    }

    private String normalize(String value) {
        if (value == null) return null;
        String result = value.trim();
        return result.isEmpty() ? null : result;
    }
}
