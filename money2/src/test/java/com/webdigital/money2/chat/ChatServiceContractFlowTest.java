package com.webdigital.money2.chat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.loans.LoanApprovalResponse;
import com.webdigital.money2.loans.LoanDetailResponse;
import com.webdigital.money2.loans.LoanDetailService;
import com.webdigital.money2.loans.LoanHistoryResponse;
import com.webdigital.money2.loans.LoanInstallmentResponse;
import com.webdigital.money2.loans.LoanPaymentResponse;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ChatServiceContractFlowTest {

    private ChatRepository repository;
    private QdrantFinancialService financialQdrant;
    private LoanDetailService loans;
    private ChatConversationStore conversations;
    private ChatService service;
    private UserAccount user;

    @BeforeEach
    void setUp() {
        repository = mock(ChatRepository.class);
        financialQdrant = mock(QdrantFinancialService.class);
        loans = mock(LoanDetailService.class);
        conversations = new ChatConversationStore();
        service = new ChatService(
                repository,
                mock(QdrantService.class),
                financialQdrant,
                new TextVectorizer(),
                conversations,
                loans);
        user = mock(UserAccount.class);
        when(user.getId()).thenReturn(7L);
        when(repository.accessibleRegionIds(7L)).thenReturn(List.of(12L));
        when(repository.accessibleRegions(7L)).thenReturn(
                List.of(new ChatRegionOption(12L, "Capitalize")));
        when(financialQdrant.context(anyString(), anyList(), anyInt()))
                .thenReturn(new FinancialSemanticContext(
                        List.of(46409L), List.of("CONTRACT_DETAIL"), true));
        when(repository.latestPaymentForLoan(7L, 46409L)).thenReturn(
                new ChatPaymentSnapshot(
                        46409L, "1", LocalDateTime.of(2026, 8, 15, 9, 30),
                        new BigDecimal("150.00"), "NORMAL"));
    }

    @Test
    void genericTextNeverFallsBackToClientSearch() {
        ChatResponse response = service.answer(
                user,
                new ChatRequest("JHONY", "READY", null, null, "generic"));

        assertThat(response.mode()).isEqualTo("READY");
        assertThat(response.message()).containsIgnoringCase("contrato");
        verify(repository, never()).searchClients(7L, "jhony", 51);
        verify(financialQdrant).context("jhony", List.of(12L), 12);
    }

    @Test
    void numberAloneReturnsDetailedContractAndKeepsItsContext() {
        LoanDetailResponse loan = contract();
        when(loans.get(user, 46409L)).thenReturn(loan);

        ChatResponse response = service.answer(
                user,
                new ChatRequest("46409", "READY", null, null, "contract"));

        assertThat(response.mode()).isEqualTo("CONTRACT_CONTEXT");
        assertThat(response.contract()).isNotNull();
        assertThat(response.contract().loanId()).isEqualTo(46409L);
        assertThat(response.contract().clientName()).isEqualTo("Cliente Teste");
        assertThat(response.contract().createdBy()).isEqualTo("operador");
        assertThat(response.contract().approvedBy()).isEqualTo("administrador");
        assertThat(response.contract().lastPaymentAmount()).isEqualByComparingTo("150.00");
        assertThat(response.suggestions())
                .extracting(ChatSuggestionResponse::label)
                .containsExactly("Histórico", "Outro assunto");
        assertThat(conversations.get(7L, "contract").loanId()).isEqualTo(46409L);
    }

    @Test
    void followUpUsesTheSelectedContractInsteadOfSearchingAClient() {
        LoanDetailResponse loan = contract();
        when(loans.get(user, 46409L)).thenReturn(loan);
        service.answer(user, new ChatRequest("46409", "READY", null, null, "follow-up"));

        ChatResponse response = service.answer(
                user,
                new ChatRequest(
                        "Quando foi o último pagamento?",
                        "CONTRACT_CONTEXT", null, null, "follow-up"));

        assertThat(response.message())
                .contains("15/08/2026")
                .contains("150,00")
                .contains("#46409");
        assertThat(response.contract()).isNull();
        assertThat(response.suggestions())
                .extracting(ChatSuggestionResponse::label)
                .containsExactly("Histórico", "Outro assunto");
        verify(repository, never()).searchClients(
                org.mockito.ArgumentMatchers.anyLong(), anyString(), anyInt());
    }

    @Test
    void historyReturnsASeparateScrollablePayloadWithoutRepeatingTheDetailCard() {
        LoanDetailResponse loan = contract();
        when(loans.get(user, 46409L)).thenReturn(loan);
        service.answer(user, new ChatRequest("46409", "READY", null, null, "history"));

        ChatResponse response = service.answer(
                user,
                new ChatRequest(
                        "Mostre o histórico de alterações",
                        "CONTRACT_CONTEXT", null, null, "history"));

        assertThat(response.mode()).isEqualTo("CONTRACT_HISTORY");
        assertThat(response.contract()).isNotNull();
        assertThat(response.contract().history())
                .extracting(ChatContractEventResponse::category)
                .contains("EMPRESTIMO", "APROVACAO");
        assertThat(response.suggestions())
                .extracting(ChatSuggestionResponse::label)
                .containsExactly("Histórico", "Outro assunto");
    }

    @Test
    void answersProfitAndGoalRecommendationDirectlyFromTheRegionName() {
        ChatFinancialSummaryResponse summary = new ChatFinancialSummaryResponse(
                8, 10,
                new BigDecimal("10000.00"),
                new BigDecimal("8000.00"),
                new BigDecimal("5000.00"),
                new BigDecimal("500.00"),
                new BigDecimal("2000.00"));
        when(repository.summary(
                org.mockito.ArgumentMatchers.eq(7L),
                org.mockito.ArgumentMatchers.eq(12L),
                org.mockito.ArgumentMatchers.any(),
                org.mockito.ArgumentMatchers.any())).thenReturn(summary);
        conversations.selectContract(7L, "profit", 46409L, 12L);

        ChatResponse profit = service.answer(
                user,
                new ChatRequest(
                        "Quanto lucrou a região Capitalize?",
                        "READY", null, null, "profit"));
        ChatResponse goal = service.answer(
                user,
                new ChatRequest(
                        "Quanto de meta recomenda para região Capitalize?",
                        "READY", null, null, "goal"));

        assertThat(profit.summary()).isSameAs(summary);
        assertThat(profit.message()).contains("Capitalize").contains("2.000,00");
        assertThat(goal.message())
                .contains("média dos três meses")
                .contains("11.000,00")
                .contains("8.800,00")
                .contains("2.200,00");
    }

    private static LoanDetailResponse contract() {
        LoanDetailResponse loan = mock(LoanDetailResponse.class);
        when(loan.id()).thenReturn(46409L);
        when(loan.clientId()).thenReturn(91L);
        when(loan.clientName()).thenReturn("Cliente Teste");
        when(loan.regionId()).thenReturn(12L);
        when(loan.regionName()).thenReturn("Capitalize");
        when(loan.contractDate()).thenReturn(LocalDateTime.of(2026, 7, 1, 10, 0));
        when(loan.paymentType()).thenReturn("Mensal");
        when(loan.installmentCount()).thenReturn(3);
        when(loan.loanedAmount()).thenReturn(new BigDecimal("900.00"));
        when(loan.totalAmount()).thenReturn(new BigDecimal("1050.00"));
        when(loan.receivedAmount()).thenReturn(new BigDecimal("150.00"));
        when(loan.receivableAmount()).thenReturn(new BigDecimal("900.00"));
        when(loan.profitAmount()).thenReturn(BigDecimal.ZERO.setScale(2));
        when(loan.status()).thenReturn("Em dia");
        when(loan.approvalStatus()).thenReturn("APROVADO");

        LoanPaymentResponse payment = new LoanPaymentResponse(
                1L, LocalDateTime.of(2026, 8, 15, 9, 30),
                new BigDecimal("150.00"), null, false, "APROVADO", "NORMAL");
        LoanInstallmentResponse installment = new LoanInstallmentResponse(
                10L, "1", LocalDateTime.of(2026, 9, 1, 0, 0), null,
                new BigDecimal("350.00"), BigDecimal.ZERO,
                new BigDecimal("350.00"), new BigDecimal("150.00"),
                new BigDecimal("200.00"), BigDecimal.ZERO, BigDecimal.ZERO,
                0, "Parcial", null, true, false, List.of(payment));
        when(loan.installments()).thenReturn(List.of(installment));
        when(loan.history()).thenReturn(List.of(new LoanHistoryResponse(
                1L, "EMPRESTIMO", "criarEmprestimo", "Novo contrato criado.",
                "operador", LocalDateTime.of(2026, 7, 1, 10, 0))));
        when(loan.approvals()).thenReturn(List.of(new LoanApprovalResponse(
                2L, "EMPRESTIMO", null, "APROVADO", "Aprovado", BigDecimal.ZERO,
                "operador", "administrador", null,
                LocalDateTime.of(2026, 7, 1, 10, 1),
                LocalDateTime.of(2026, 7, 1, 10, 5))));
        return loan;
    }
}
