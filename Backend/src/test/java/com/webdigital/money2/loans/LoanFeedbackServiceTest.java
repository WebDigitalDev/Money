package com.webdigital.money2.loans;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.loans.LoanDetailRepository.LoanSnapshot;
import com.webdigital.money2.shared.ApiException;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class LoanFeedbackServiceTest {

    private final LoanDetailRepository loanRepository = mock(LoanDetailRepository.class);
    private final LoanFeedbackRepository feedbackRepository = mock(LoanFeedbackRepository.class);
    private final LoanFeedbackService service = new LoanFeedbackService(
            loanRepository, feedbackRepository);

    @Test
    void everyAccessibleUserCanAddFeedback() {
        UserAccount user = user(7L, false);
        when(feedbackRepository.insert(55L, 7L, "MATHEUS", "Cliente solicitou retorno."))
                .thenReturn(91L);
        LoanFeedbackResponse created = new LoanFeedbackResponse(
                91L, 55L, "Cliente solicitou retorno.", 7L,
                "Matheus", LocalDateTime.now(), null);
        when(feedbackRepository.list(55L)).thenReturn(List.of(created));

        LoanFeedbackResponse response = service.add(
                user, 55L, new LoanFeedbackRequest(" Cliente solicitou retorno. "));

        assertEquals(91L, response.id());
        verify(loanRepository).requireSnapshot(7L, 55L);
    }

    @Test
    void onlyAdministratorCanDeleteFeedback() {
        UserAccount user = user(8L, false);

        ApiException error = assertThrows(ApiException.class,
                () -> service.delete(user, 55L, 91L));

        assertEquals(HttpStatus.FORBIDDEN, error.getStatus());
        verify(feedbackRepository, never()).delete(91L);
    }

    @Test
    void administratorCanDeleteFeedback() {
        UserAccount administrator = user(1L, true);
        when(feedbackRepository.belongsToLoan(91L, 55L)).thenReturn(true);

        service.delete(administrator, 55L, 91L);

        verify(feedbackRepository).delete(91L);
    }

    private UserAccount user(long id, boolean administrator) {
        UserAccount user = mock(UserAccount.class);
        when(user.getId()).thenReturn(id);
        when(user.getUsername()).thenReturn("MATHEUS");
        when(user.isAdministrator()).thenReturn(administrator);
        when(loanRepository.requireSnapshot(id, 55L)).thenReturn(mock(LoanSnapshot.class));
        return user;
    }
}
