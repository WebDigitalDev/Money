package com.webdigital.money2.conferences;

import com.webdigital.money2.conferences.ConferenceRepository.AutomaticPaymentTarget;
import com.webdigital.money2.loans.LoanDetailService;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Service
public class ConferenceAutoApprovalService {

    private static final Logger LOGGER = LoggerFactory.getLogger(ConferenceAutoApprovalService.class);
    private static final int BATCH_SIZE = 200;
    private static final int MAX_BATCHES_PER_RUN = 20;

    private final ConferenceRepository repository;
    private final LoanDetailService loanDetailService;

    public ConferenceAutoApprovalService(
            ConferenceRepository repository,
            LoanDetailService loanDetailService) {
        this.repository = repository;
        this.loanDetailService = loanDetailService;
    }

    @Scheduled(
            fixedDelayString = "${money.conferences.auto-approval-delay-ms:3600000}",
            initialDelayString = "${money.conferences.auto-approval-initial-delay-ms:45000}")
    public void approveExpiredPayments() {
        int processed = 0;
        int failures = 0;
        for (int batch = 0; batch < MAX_BATCHES_PER_RUN; batch++) {
            List<AutomaticPaymentTarget> targets = repository.expiredPaymentTargets(BATCH_SIZE);
            if (targets.isEmpty()) break;
            int processedInBatch = 0;
            for (AutomaticPaymentTarget target : targets) {
                try {
                    if (loanDetailService.approveExpiredPaymentBySystem(
                            target.loanId(), target.approvalId())) {
                        processed++;
                        processedInBatch++;
                    }
                } catch (RuntimeException exception) {
                    failures++;
                    LOGGER.warn(
                            "Falha ao aprovar automaticamente a conferência de pagamento {} do contrato {}.",
                            target.approvalId(), target.loanId(), exception);
                }
            }
            if (processedInBatch == 0) break;
        }
        if (processed > 0 || failures > 0) {
            LOGGER.info(
                    "Conferências antigas processadas automaticamente: {} aprovada(s), {} falha(s).",
                    processed, failures);
        }
    }
}
