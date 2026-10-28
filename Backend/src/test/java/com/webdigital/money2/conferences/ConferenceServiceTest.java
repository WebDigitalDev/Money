package com.webdigital.money2.conferences;

import static org.junit.jupiter.api.Assertions.assertSame;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.loans.LoanDetailService;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ConferenceServiceTest {

    private ConferenceRepository repository;
    private ConferenceService service;
    private UserAccount administrator;

    @BeforeEach
    void setUp() {
        repository = mock(ConferenceRepository.class);
        service = new ConferenceService(repository, mock(LoanDetailService.class));
        administrator = mock(UserAccount.class);
        when(administrator.isAdministrator()).thenReturn(true);
        when(administrator.getId()).thenReturn(7L);
    }

    @Test
    void forwardsLightweightListOptionToRepository() {
        ConferenceListResponse expected = new ConferenceListResponse(
                List.of(), 0, 0, 200, Map.of());
        when(repository.search(7L, "ana", List.of("PAGAMENTO"), List.of(3L, 5L),
                0, 200, false)).thenReturn(expected);

        ConferenceListResponse result = service.search(
                administrator, "ana", "PAYMENT", "3,5", 0, 500, false);

        assertSame(expected, result);
        verify(repository).search(7L, "ana", List.of("PAGAMENTO"), List.of(3L, 5L),
                0, 200, false);
    }

    @Test
    void loadsConferenceDetailsOnlyForCurrentAdministrator() {
        List<ConferenceDetailResponse> expected = List.of(mock(ConferenceDetailResponse.class));
        when(repository.details(7L, 91L)).thenReturn(expected);

        List<ConferenceDetailResponse> result = service.details(administrator, 91L);

        assertSame(expected, result);
        verify(repository).details(7L, 91L);
    }
}
