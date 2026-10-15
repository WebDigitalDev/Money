package com.webdigital.money2.loans;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class LoanLaunchTransitionServiceTest {

    @Mock
    private LoanDetailRepository repository;

    @InjectMocks
    private LoanLaunchTransitionService service;

    @Test
    void transitionsApprovedLaunchesFromPreviousDays() {
        when(repository.transitionPreviousDayLaunches()).thenReturn(2);

        service.transitionPreviousDayLaunches();

        verify(repository).transitionPreviousDayLaunches();
    }
}
