package com.webdigital.money2.loans;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class LoanLaunchTransitionService {

    private static final Logger LOGGER = LoggerFactory.getLogger(LoanLaunchTransitionService.class);

    private final LoanDetailRepository repository;

    public LoanLaunchTransitionService(LoanDetailRepository repository) {
        this.repository = repository;
    }

    @Scheduled(
            fixedDelayString = "${money.loans.launch-transition-delay-ms:60000}",
            initialDelayString = "${money.loans.launch-transition-initial-delay-ms:30000}")
    @Transactional
    public void transitionPreviousDayLaunches() {
        int transitioned = repository.transitionPreviousDayLaunches();
        if (transitioned > 0) {
            LOGGER.info(
                    "Empréstimos que saíram automaticamente de Lançamento na virada do dia: {}.",
                    transitioned);
        }
    }
}
