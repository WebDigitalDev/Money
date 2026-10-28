package com.webdigital.money2.conferences;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.conferences.ConferenceRepository.AutomaticPaymentTarget;
import com.webdigital.money2.loans.LoanDetailService;
import java.util.List;
import org.junit.jupiter.api.Test;

class ConferenceAutoApprovalServiceTest {

    @Test
    void processesEveryExpiredPaymentUntilQueueIsEmpty() {
        ConferenceRepository repository = mock(ConferenceRepository.class);
        LoanDetailService loanDetailService = mock(LoanDetailService.class);
        AutomaticPaymentTarget first = new AutomaticPaymentTarget(10L, 100L);
        AutomaticPaymentTarget second = new AutomaticPaymentTarget(11L, 101L);
        when(repository.expiredPaymentTargets(200))
                .thenReturn(List.of(first, second))
                .thenReturn(List.of());
        when(loanDetailService.approveExpiredPaymentBySystem(100L, 10L)).thenReturn(true);
        when(loanDetailService.approveExpiredPaymentBySystem(101L, 11L)).thenReturn(true);

        new ConferenceAutoApprovalService(repository, loanDetailService).approveExpiredPayments();

        verify(loanDetailService).approveExpiredPaymentBySystem(100L, 10L);
        verify(loanDetailService).approveExpiredPaymentBySystem(101L, 11L);
    }
}
