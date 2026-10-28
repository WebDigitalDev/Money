package com.webdigital.money2.chat;

import static java.math.BigDecimal.ZERO;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.loans.LoanDetailService;
import java.util.ArrayList;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ChatServiceClientSearchTest {

    private ChatRepository repository;
    private QdrantService qdrant;
    private QdrantFinancialService financialQdrant;
    private ChatConversationStore conversations;
    private ChatService service;
    private UserAccount user;

    @BeforeEach
    void setUp() {
        repository = mock(ChatRepository.class);
        qdrant = mock(QdrantService.class);
        financialQdrant = mock(QdrantFinancialService.class);
        conversations = new ChatConversationStore();
        service = new ChatService(
                repository,
                qdrant,
                financialQdrant,
                new TextVectorizer(),
                conversations,
                mock(LoanDetailService.class));
        user = mock(UserAccount.class);
        when(user.getId()).thenReturn(7L);
        when(repository.accessibleRegionIds(7L)).thenReturn(List.of(1L));
        when(financialQdrant.context(org.mockito.ArgumentMatchers.anyString(),
                org.mockito.ArgumentMatchers.anyList(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(FinancialSemanticContext.empty());
    }

    @Test
    void normalizesCaseAndReturnsTheSingleExactMatch() {
        ChatClientResponse client = client(10L, "WEBDIGITAL");
        ChatLoanResponse activeLoan = new ChatLoanResponse(
                46409L, "WEBDIGITAL", "REGIÃO", "Mensal",
                LocalDate.of(2026, 9, 10), 2, ZERO, "EM_DIA");
        when(repository.searchClients(7L, "webdigital", 51)).thenReturn(List.of(client));
        when(qdrant.search("webdigital", List.of(1L), 50)).thenReturn(List.of(10L));
        when(repository.activeLoanResults(7L, 10L, 100)).thenReturn(List.of(activeLoan));

        ChatResponse response = service.answer(
                user,
                new ChatRequest("WebDigital", "CLIENT_SEARCH", null, null, "case-search"));

        assertThat(response.mode()).isEqualTo("CLIENT_CONTEXT");
        assertThat(response.clients()).containsExactly(client);
        assertThat(response.loans()).containsExactly(activeLoan);
        verify(repository).searchClients(7L, "webdigital", 51);
    }

    @Test
    void returnsEveryExactMatchWhenThereAreAtMostFifty() {
        List<ChatClientResponse> matches = clients(50, "JHONY");
        when(repository.searchClients(7L, "jhony", 51)).thenReturn(matches);
        when(qdrant.search("jhony", List.of(1L), 50)).thenReturn(List.of(5L, 2L));

        ChatResponse response = service.answer(
                user,
                new ChatRequest("jhony", "CLIENT_SEARCH", null, null, "all-matches"));

        assertThat(response.mode()).isEqualTo("CLIENT_SEARCH");
        assertThat(response.clients()).hasSize(50).containsExactlyInAnyOrderElementsOf(matches);
        assertThat(response.suggestions()).hasSize(50);
        assertThat(response.clients().get(0).id()).isEqualTo(5L);
        assertThat(response.clients().get(1).id()).isEqualTo(2L);
    }

    @Test
    void asksForFirstAndLastNameWhenMoreThanFiftyMatch() {
        when(repository.searchClients(7L, "jhony", 51)).thenReturn(clients(51, "JHONY"));

        ChatResponse response = service.answer(
                user,
                new ChatRequest("JHONY", "CLIENT_SEARCH", null, null, "too-many"));

        assertThat(response.mode()).isEqualTo("CLIENT_SEARCH");
        assertThat(response.message()).containsIgnoringCase("nome e o sobrenome");
        assertThat(response.clients()).isEmpty();
        assertThat(response.suggestions()).isEmpty();
        verify(qdrant, never()).search("jhony", List.of(1L), 50);
    }

    @Test
    void offersAnotherSubjectWhenAskingForAnotherClient() {
        conversations.selectClient(7L, "change-client", 10L);

        ChatResponse response = service.answer(
                user,
                new ChatRequest("Outro cliente", "CLIENT_CONTEXT", null, null, "change-client"));

        assertThat(response.mode()).isEqualTo("CLIENT_SEARCH");
        assertThat(response.message()).containsIgnoringCase("qual cliente");
        assertThat(response.suggestions()).singleElement().satisfies(suggestion -> {
            assertThat(suggestion.label()).isEqualTo("Outro assunto");
            assertThat(suggestion.message()).isEqualTo("Outro assunto");
            assertThat(suggestion.clientId()).isNull();
            assertThat(suggestion.regionId()).isNull();
        });
        assertThat(conversations.get(7L, "change-client").clientId()).isNull();
    }

    @Test
    void clientFollowUpKeepsActionsWithoutRepeatingTheClientCard() {
        ChatClientResponse client = client(10L, "WEBDIGITAL");
        conversations.selectClient(7L, "client-follow-up", 10L);
        when(repository.clientsByIds(7L, List.of(10L), 1)).thenReturn(List.of(client));
        when(repository.latestPayment(7L, 10L)).thenReturn(new ChatPaymentSnapshot(
                46409L, "10", LocalDateTime.of(2026, 8, 14, 10, 0),
                new java.math.BigDecimal("132.00"), "NORMAL"));

        ChatResponse response = service.answer(
                user,
                new ChatRequest(
                        "Qual foi o último pagamento?",
                        "CLIENT_CONTEXT", null, null, "client-follow-up"));

        assertThat(response.mode()).isEqualTo("CLIENT_CONTEXT");
        assertThat(response.clients()).isEmpty();
        assertThat(response.message()).contains("14/08/2026").contains("132,00");
        assertThat(response.suggestions())
                .extracting(ChatSuggestionResponse::label)
                .containsExactly(
                        "Último pagamento", "Próximo vencimento",
                        "Saldo atual", "Outro cliente");
    }

    @Test
    void anotherSubjectReturnsToTheBeginningAndClearsConversationContext() {
        conversations.selectClient(7L, "another-subject", 10L);
        conversations.selectRegion(7L, "another-subject", 20L, "SUMMARY_REGION");

        ChatResponse response = service.answer(
                user,
                new ChatRequest("Outro assunto", "CLIENT_SEARCH", null, null, "another-subject"));

        assertThat(response.mode()).isEqualTo("READY");
        assertThat(response.suggestions())
                .extracting(ChatSuggestionResponse::label)
                .containsExactly(
                        "Consultar cliente",
                        "Vencimentos de hoje",
                        "Empréstimos Atrasados",
                        "Resumo financeiro");
        assertThat(conversations.get(7L, "another-subject"))
                .isEqualTo(ChatConversationContext.empty());
    }

    private static List<ChatClientResponse> clients(int amount, String name) {
        List<ChatClientResponse> result = new ArrayList<>();
        for (long id = 1; id <= amount; id++) {
            result.add(client(id, name + " " + id));
        }
        return result;
    }

    private static ChatClientResponse client(long id, String name) {
        return new ChatClientResponse(
                id,
                name,
                null,
                null,
                1L,
                "REGIÃO",
                0,
                ZERO,
                ZERO,
                ZERO,
                ZERO,
                ZERO);
    }
}
