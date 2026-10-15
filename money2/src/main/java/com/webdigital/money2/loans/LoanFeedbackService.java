package com.webdigital.money2.loans;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.shared.ApiException;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class LoanFeedbackService {

    private final LoanDetailRepository loanRepository;
    private final LoanFeedbackRepository feedbackRepository;

    public LoanFeedbackService(
            LoanDetailRepository loanRepository,
            LoanFeedbackRepository feedbackRepository) {
        this.loanRepository = loanRepository;
        this.feedbackRepository = feedbackRepository;
    }

    @Transactional(readOnly = true)
    public List<LoanFeedbackResponse> list(UserAccount user, long loanId) {
        loanRepository.requireSnapshot(requireUserId(user), loanId);
        return feedbackRepository.list(loanId);
    }

    @Transactional
    public LoanFeedbackResponse add(UserAccount user, long loanId, LoanFeedbackRequest request) {
        long userId = requireUserId(user);
        loanRepository.requireSnapshot(userId, loanId);
        String text = request == null || request.text() == null ? "" : request.text().trim();
        if (text.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Digite o feedback.");
        }
        if (text.length() > 2000) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "O feedback deve ter no máximo 2.000 caracteres.");
        }
        long id = feedbackRepository.insert(
                loanId, userId, safeUsername(user), text);
        loanRepository.log("EMPRESTIMO", loanId, "adicionarFeedback",
                "Feedback #" + id + " adicionado ao contrato.", safeUsername(user));
        return feedbackRepository.list(loanId).stream()
                .filter(item -> item.id() == id)
                .findFirst()
                .orElseThrow(() -> new ApiException(
                        HttpStatus.INTERNAL_SERVER_ERROR, "O feedback não foi localizado."));
    }

    @Transactional
    public void delete(UserAccount user, long loanId, long feedbackId) {
        long userId = requireUserId(user);
        loanRepository.requireSnapshot(userId, loanId);
        if (!user.isAdministrator()) {
            throw new ApiException(HttpStatus.FORBIDDEN,
                    "Somente administradores podem remover feedbacks.");
        }
        if (!feedbackRepository.belongsToLoan(feedbackId, loanId)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Feedback não encontrado.");
        }
        feedbackRepository.delete(feedbackId);
        loanRepository.log("EMPRESTIMO", loanId, "removerFeedback",
                "Feedback #" + feedbackId + " removido do contrato.", safeUsername(user));
    }

    private long requireUserId(UserAccount user) {
        if (user == null || user.getId() == null) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Sessão inválida.");
        }
        return user.getId();
    }

    private String safeUsername(UserAccount user) {
        String value = user == null ? null : user.getUsername();
        return value == null || value.isBlank() ? "USUÁRIO" : value.trim();
    }
}
