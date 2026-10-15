package com.webdigital.money2.chat;

import static java.math.BigDecimal.ZERO;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.goals.FinancialGoalResponse;
import com.webdigital.money2.loans.LoanDetailService;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ChatServiceRegionalFlowTest {

    private ChatRepository repository;
    private ChatConversationStore conversations;
    private ChatService service;
    private UserAccount user;

    @BeforeEach
    void setUp() {
        repository = mock(ChatRepository.class);
        conversations = new ChatConversationStore();
        QdrantFinancialService financialQdrant = mock(QdrantFinancialService.class);
        when(financialQdrant.context(org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.anyList(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(FinancialSemanticContext.empty());
        service = new ChatService(
                repository,
                mock(QdrantService.class),
                financialQdrant,
                new TextVectorizer(),
                conversations,
                mock(LoanDetailService.class));
        user = mock(UserAccount.class);
        when(user.getId()).thenReturn(7L);
        when(repository.accessibleRegions(7L))
                .thenReturn(List.of(new ChatRegionOption(12L, "Centro")));
    }

    @Test
    void returnsEveryDueLoanAndOnlyTheTwoResultActions() {
        List<ChatLoanResponse> loans = loans(18, "VENCE_HOJE");
        when(repository.dueTodayLoans(7L, 12L)).thenReturn(loans);

        ChatResponse response = service.answer(
                user,
                new ChatRequest(
                        "Centro", "DUE_TODAY_REGION", null, 12L, "due-list"));

        assertThat(response.loans()).containsExactlyElementsOf(loans);
        assertThat(response.clients()).isEmpty();
        assertThat(response.suggestions())
                .extracting(ChatSuggestionResponse::label)
                .containsExactly("Exportar", "Outro assunto");
        assertThat(response.suggestions().get(0).action()).isEqualTo("EXPORT_EXCEL");
        verify(repository).dueTodayLoans(7L, 12L);
    }

    @Test
    void asksForSummaryPeriodThenBuildsTheLastThirtyDaysSummary() {
        ChatFinancialSummaryResponse summary =
                new ChatFinancialSummaryResponse(
                        4, 6, ZERO, ZERO, ZERO, ZERO, ZERO);
        ChatLoanStatusResponse status =
                new ChatLoanStatusResponse(2, ZERO, 3, ZERO, 4, ZERO);
        ChatClientStatusResponse clientStatus =
                new ChatClientStatusResponse(8, 5, 2);
        FinancialGoalResponse goal = mock(FinancialGoalResponse.class);

        ChatResponse period = service.answer(
                user,
                new ChatRequest(
                        "Centro", "SUMMARY_REGION", null, 12L, "summary-flow"));

        assertThat(period.mode()).isEqualTo("SUMMARY_PERIOD");
        assertThat(period.suggestions())
                .extracting(ChatSuggestionResponse::label)
                .containsExactly(
                        "Últimos 30 dias", "Escolher mês", "Geral", "Outro assunto");

        LocalDate today = LocalDate.now(java.time.ZoneId.of("America/Cuiaba"));
        when(repository.summary(7L, 12L, today.minusDays(29), today))
                .thenReturn(summary);
        when(repository.loanStatus(7L, 12L, today.minusDays(29), today))
                .thenReturn(status);
        when(repository.clientStatus(7L, 12L)).thenReturn(clientStatus);
        when(repository.activeFinancialGoals(7L, 12L)).thenReturn(List.of(goal));

        ChatResponse response = service.answer(
                user,
                new ChatRequest(
                        "Últimos 30 dias", "SUMMARY_PERIOD", null, null, "summary-flow"));

        assertThat(response.message())
                .isEqualTo("Aqui está o resumo financeiro de Centro.");
        assertThat(response.summary()).isSameAs(summary);
        assertThat(response.loanStatus()).isSameAs(status);
        assertThat(response.clientStatus()).isSameAs(clientStatus);
        assertThat(response.financialGoals()).containsExactly(goal);
        assertThat(response.financialGoal()).isSameAs(goal);
        assertThat(response.summaryContext()).isEqualTo(
                new ChatSummaryContextResponse(
                        12L, "Centro", today.minusDays(29), today));
        assertThat(response.suggestions())
                .extracting(ChatSuggestionResponse::label)
                .containsExactly("Exportar PDF", "Outro assunto");
    }

    @Test
    void anotherSubjectClearsTheSelectedSummaryRegion() {
        conversations.selectRegion(7L, "reset-flow", 12L, "SUMMARY_REGION");

        ChatResponse response = service.answer(
                user,
                new ChatRequest(
                        "Outro assunto", "SUMMARY_PERIOD", null, null, "reset-flow"));

        assertThat(response.mode()).isEqualTo("READY");
        assertThat(response.suggestions())
                .extracting(ChatSuggestionResponse::label)
                .containsExactly(
                        "Consultar cliente",
                        "Vencimentos de hoje",
                        "Empréstimos Atrasados",
                        "Resumo financeiro");
        assertThat(conversations.get(7L, "reset-flow"))
                .isEqualTo(ChatConversationContext.empty());
    }

    private static List<ChatLoanResponse> loans(int amount, String status) {
        List<ChatLoanResponse> result = new ArrayList<>();
        for (long id = 1; id <= amount; id++) {
            result.add(new ChatLoanResponse(
                    id,
                    "Cliente " + id,
                    "Centro",
                    "Mensal",
                    LocalDate.now(),
                    1,
                    ZERO,
                    status));
        }
        return result;
    }
}
