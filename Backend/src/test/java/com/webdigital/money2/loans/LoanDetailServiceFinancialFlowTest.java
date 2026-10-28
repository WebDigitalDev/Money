package com.webdigital.money2.loans;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.inOrder;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.loans.LoanDetailRepository.ApprovalSnapshot;
import com.webdigital.money2.loans.LoanDetailRepository.ContractMessageSnapshot;
import com.webdigital.money2.loans.LoanDetailRepository.InstallmentSeed;
import com.webdigital.money2.loans.LoanDetailRepository.LoanSnapshot;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.test.util.ReflectionTestUtils;

class LoanDetailServiceFinancialFlowTest {

    private final LoanDetailRepository repository = mock(LoanDetailRepository.class);
    private final LoanDetailService service = new LoanDetailService(
            repository, mock(LoanFeedbackRepository.class));
    private final UserAccount administrator = administrator();

    @Test
    void commonUserPaymentIsAppliedImmediatelyAndStillSentToConference() {
        UserAccount operator = operator();
        LoanSnapshot loan = snapshot(90L, money("500"), money("0"), money("100"));
        when(repository.requireSnapshot(2L, 90L)).thenReturn(loan);
        when(repository.requireInstallment(90L, 901L)).thenReturn(
                new LoanDetailRepository.InstallmentSnapshot(
                        901L, LocalDateTime.of(2026, 8, 25, 12, 0),
                        money("100"), money("0"), money("0")));
        when(repository.insertPayment(anyLong(), anyLong(), any(), any(), any(), anyString()))
                .thenReturn(9901L);
        emptyRelations(loan);

        service.addPayment(operator, 90L, 901L,
                new PaymentRequest(money("100"), LocalDate.of(2026, 8, 24), null));

        verify(repository).insertPayment(90L, 901L, money("100"),
                LocalDate.of(2026, 8, 24), null, "APROVADO");
        verify(repository).createApproval(eq(loan), eq("PAGAMENTO"), eq(null),
                eq(9901L), eq(901L), eq(money("100")), eq("OPERADOR"),
                anyString(), eq(null));
        verify(repository).synchronizeInstallment(901L);
        verify(repository).refreshLoanFinancialTotals(90L);
    }

    @Test
    void editingFullyPaidInstallmentSynchronizesItsPaidStatus() {
        LoanSnapshot loan = snapshot(90L, money("600"), money("0"), money("300"));
        LocalDateTime dueDate = LocalDateTime.of(2026, 8, 21, 12, 0);
        when(repository.requireSnapshot(1L, 90L)).thenReturn(loan);
        when(repository.requireInstallment(90L, 901L)).thenReturn(
                new LoanDetailRepository.InstallmentSnapshot(
                        901L, dueDate, money("36"), money("30"), money("36")));
        emptyRelations(loan);

        service.updateInstallment(administrator, 90L, 901L,
                new InstallmentUpdateRequest(
                        LocalDate.of(2026, 8, 21), money("36"), money("0"), null));

        verify(repository).updateInstallment(
                901L, LocalDate.of(2026, 8, 21), money("36"), money("0"), null);
        verify(repository).synchronizeInstallment(901L);
        verify(repository).refreshLoanFinancialTotals(90L);
        verify(repository, never()).renumberInstallmentsByDueDate(anyLong());
    }

    @Test
    void changingInstallmentDueDateRenumbersContractChronologically() {
        LoanSnapshot loan = snapshot(90L, money("600"), money("0"), money("300"));
        when(repository.requireSnapshot(1L, 90L)).thenReturn(loan);
        when(repository.requireInstallment(90L, 901L)).thenReturn(
                new LoanDetailRepository.InstallmentSnapshot(
                        901L, LocalDateTime.of(2026, 8, 21, 12, 0),
                        money("36"), money("0"), money("0")));
        emptyRelations(loan);

        service.updateInstallment(administrator, 90L, 901L,
                new InstallmentUpdateRequest(
                        LocalDate.of(2026, 9, 21), money("36"), money("0"),
                        "Vencimento prorrogado."));

        verify(repository).renumberInstallmentsByDueDate(90L);
    }

    @Test
    void distributedPaymentByCommonUserIsAppliedImmediately() {
        UserAccount operator = operator();
        LoanSnapshot loan = snapshot(90L, money("500"), money("0"), money("100"));
        LoanInstallmentResponse installment = new LoanInstallmentResponse(
                901L, "1", LocalDateTime.of(2026, 8, 25, 12, 0), null,
                money("100"), money("0"), money("100"), money("0"), money("100"),
                money("0"), money("0"), 0, "À Vencer", null, true, false, List.of());
        when(repository.requireSnapshot(2L, 90L)).thenReturn(loan);
        when(repository.installments(90L, loan.lateFee())).thenReturn(List.of(installment));
        when(repository.insertPayment(anyLong(), anyLong(), any(), any(), any(), anyString()))
                .thenReturn(9901L);
        when(repository.history(90L)).thenReturn(List.of());
        when(repository.approvals(90L)).thenReturn(List.of());
        when(repository.origins(90L)).thenReturn(List.of());

        service.distributePayment(operator, 90L,
                new PaymentRequest(money("100"), LocalDate.of(2026, 8, 24), null));

        verify(repository).insertPayment(90L, 901L, money("100"),
                LocalDate.of(2026, 8, 24), null, "APROVADO");
        verify(repository).createApproval(eq(loan), eq("PAGAMENTO"), eq(null),
                eq(9901L), eq(901L), eq(money("100")), eq("OPERADOR"),
                anyString(), anyString());
    }

    @Test
    void rejectingPaymentConferenceDoesNotReverseAppliedPayment() {
        LoanSnapshot loan = snapshot(90L, money("500"), money("0"), money("100"));
        ApprovalSnapshot approval = new ApprovalSnapshot(
                8801L, "PAGAMENTO", null, 9901L, 90L,
                null, 901L, "PENDENTE", money("100"), money("0"),
                money("0"), money("0"), money("0"), money("0"));
        when(repository.requireSnapshot(1L, 90L)).thenReturn(loan);
        when(repository.requirePendingApproval(1L, 90L, 8801L)).thenReturn(approval);
        emptyRelations(loan);

        service.decideApproval(administrator, 90L, 8801L, false,
                new LoanDecisionRequest("Valor conferido com divergência."));

        verify(repository).setPaymentApproval(9901L, "APROVADO");
        verify(repository).synchronizeInstallment(901L);
        verify(repository).refreshLoanFinancialTotals(90L);
        verify(repository).decideApproval(8801L, "REPROVADO", "ADMINISTRADOR",
                "Valor conferido com divergência.");
    }

    @Test
    void rejectingRefinancingKeepsReasonOnOriginAndDeletesOnlyPendingDestination() {
        LoanSnapshot destination = snapshot(47797L, money("801"), money("0"), money("0"));
        ApprovalSnapshot approval = new ApprovalSnapshot(
                61783L, "REFINANCIAMENTO", null, 47797L, 47797L,
                46966L, null, "PENDENTE", money("801"), money("0"),
                money("0"), money("0"), money("0"), money("801"));
        when(repository.requireSnapshot(1L, 47797L)).thenReturn(destination);
        when(repository.requirePendingApproval(1L, 47797L, 61783L)).thenReturn(approval);

        LoanDetailResponse response = service.decideApproval(
                administrator, 47797L, 61783L, false,
                new LoanDecisionRequest("Dados do refinanciamento incorretos."));

        assertThat(response).isNull();
        InOrder order = inOrder(repository);
        order.verify(repository).decideApproval(
                61783L, "REPROVADO", "ADMINISTRADOR",
                "Dados do refinanciamento incorretos.");
        order.verify(repository).linkRejectedNegotiationToOrigin(61783L, 46966L);
        order.verify(repository).deleteLoanPreservingApproval(47797L, 61783L);
        order.verify(repository).log(
                "APROVACAO", 61783L, "reprovar",
                "Operação reprovada: Dados do refinanciamento incorretos.",
                "ADMINISTRADOR");
        verify(repository, never()).deleteLoan(47797L);
        verify(repository).requireSnapshot(1L, 47797L);
    }

    @Test
    void expiredPaymentIsApprovedAndAuditedBySystem() {
        ApprovalSnapshot approval = new ApprovalSnapshot(
                8801L, "PAGAMENTO", "BAIXA_MANUAL", 9901L, 90L,
                null, 901L, "PENDENTE", money("200"), money("0"),
                money("0"), money("0"), money("0"), money("0"));
        when(repository.lockExpiredPaymentApproval(90L, 8801L)).thenReturn(approval);

        boolean processed = service.approveExpiredPaymentBySystem(90L, 8801L);

        assertThat(processed).isTrue();
        verify(repository).setPaymentApproval(9901L, "APROVADO");
        verify(repository).synchronizeInstallment(901L);
        verify(repository).refreshLoanFinancialTotals(90L);
        verify(repository).decideApproval(
                8801L, "APROVADO", "APROVADO PELO SISTEMA", "APROVADO PELO SISTEMA");
        verify(repository).log(
                "APROVACAO", 8801L, "aprovar", "APROVADO PELO SISTEMA", "APROVADO PELO SISTEMA");
        verify(repository, never()).applyDeferredInterestRollIfPresent(anyLong());
    }

    @Test
    void interestOnlyPaymentImmediatelyRollsDueDateWithoutAmortizingDebt() {
        LoanSnapshot loan = snapshot(90L, money("500"), money("0"), money("260"), "M");
        LocalDateTime previousDue = LocalDateTime.of(2026, 8, 15, 12, 0);
        LoanInstallmentResponse installment = new LoanInstallmentResponse(
                901L, "1", previousDue, null, money("760"), money("0"),
                money("760"), money("0"), money("760"), money("0"),
                money("0"), 0, "À Vencer", null, true, false, List.of());

        when(repository.requireSnapshot(1L, 90L)).thenReturn(loan);
        emptyRelations(loan);
        when(repository.installments(90L, loan.lateFee())).thenReturn(List.of(installment));
        when(repository.requireInstallment(90L, 901L)).thenReturn(
                new LoanDetailRepository.InstallmentSnapshot(
                        901L, previousDue, money("760"), money("0"), money("0")));
        when(repository.insertPayment(anyLong(), anyLong(), any(), any(), any(), anyString(), anyString()))
                .thenReturn(9901L);
        when(repository.createApproval(any(), anyString(), anyString(), anyLong(), anyLong(), any(),
                anyString(), anyString(), anyString())).thenReturn(8801L);
        service.interestOnlyPayment(administrator, 90L,
                new InterestOnlyPaymentRequest(901L, null,
                        LocalDate.of(2026, 8, 15), null, null));

        verify(repository).insertPayment(eq(90L), eq(901L), eq(money("260")),
                eq(LocalDate.of(2026, 8, 15)), eq(null), eq("APROVADO"), eq("JUROS_ROLAGEM"));
        verify(repository).updateInstallmentDueDate(eq(901L), eq(LocalDate.of(2026, 9, 15)), anyString());
        verify(repository).renumberInstallmentsByDueDate(90L);
        verify(repository).createApproval(eq(loan), eq("PAGAMENTO"), eq("JUROS_ROLAGEM"),
                eq(9901L), eq(901L), eq(money("260")), eq("ADMINISTRADOR"),
                anyString(), anyString());
        verify(repository).refreshLoanFinancialTotals(90L);
        verify(repository, never()).insertInterestRollRequest(anyLong(), anyLong(), anyLong(), any(), any());
    }

    @Test
    void commonLoanPersistsNegotiatedAmountAsLegacyInterest() {
        LoanSnapshot saved = snapshot(100L, money("500"), money("0"), money("1200"));
        when(repository.insertLoan(anyLong(), any(), any(), anyInt(), any(), anyString(),
                any(), any(), any(), any(), any(), any(), anyBoolean(), anyString())).thenReturn(100L);
        when(repository.requireSnapshot(1L, 100L)).thenReturn(saved);
        emptyRelations(saved);

        LoanDetailResponse response = service.create(administrator, new LoanCreateRequest(
                9L, LocalDate.of(2026, 8, 13), LocalDate.of(2026, 8, 14), 10,
                null, "D", money("500"), money("0"), money("1200"), null,
                money("10"), null, null, false));

        ArgumentCaptor<BigDecimal> principal = ArgumentCaptor.forClass(BigDecimal.class);
        ArgumentCaptor<BigDecimal> interest = ArgumentCaptor.forClass(BigDecimal.class);
        verify(repository).insertLoan(eq(9L), any(), any(), eq(10), any(), eq("D"),
                principal.capture(), eq(money("0")), interest.capture(), eq(money("10")),
                any(), any(), eq(false), eq("APROVADO"));
        ArgumentCaptor<List<InstallmentSeed>> installments = ArgumentCaptor.forClass(List.class);
        verify(repository).insertInstallments(eq(100L), installments.capture());

        assertThat(principal.getValue()).isEqualByComparingTo("500.00");
        assertThat(interest.getValue()).isEqualByComparingTo("1200.00");
        assertThat(response.negotiatedAmount()).isEqualByComparingTo("1200.00");
        assertThat(response.totalAmount()).isEqualByComparingTo("1700.00");
        assertThat(installments.getValue()).hasSize(10);
        assertThat(installments.getValue().stream().map(InstallmentSeed::amount)
                .reduce(money("0"), BigDecimal::add)).isEqualByComparingTo("1700.00");
    }

    @Test
    void negotiatedOriginExposesOriginalAndNegotiatedValuesLikeLegacyApp() {
        LoanSnapshot negotiated = snapshot(200L, money("1200"), money("500"), money("0"));
        when(repository.requireSnapshot(1L, 200L)).thenReturn(negotiated);
        emptyRelations(negotiated);

        LoanDetailResponse response = service.get(administrator, 200L);

        assertThat(response.negotiatedOrigin()).isTrue();
        assertThat(response.originalLoanAmount()).isEqualByComparingTo("500.00");
        assertThat(response.negotiatedAmount()).isEqualByComparingTo("1200.00");
        assertThat(response.totalAmount()).isEqualByComparingTo("1200.00");
    }

    @Test
    void refinancingPersistsTotalAsNegotiatedPrincipalAndZeroContractInterest() {
        LoanSnapshot origin = snapshot(300L, money("500"), money("0"), money("500"));
        LoanSnapshot destination = snapshot(301L, money("1200"), money("500"), money("0"));
        when(repository.requireSnapshot(1L, 300L)).thenReturn(origin);
        when(repository.pendingDebt(300L)).thenReturn(money("500"));
        when(repository.insertNegotiatedLoan(any(), any(), any(), any(), anyInt(), any(),
                anyString(), any(), anyString())).thenReturn(301L);
        when(repository.requireSnapshot(1L, 301L)).thenReturn(destination);
        emptyRelations(destination);

        LoanDetailResponse response = service.negotiate(administrator, 300L, "REFINANCIAMENTO",
                new LoanNegotiationRequest(money("500"), money("0"), money("700"), money("140"),
                        10, LocalDate.of(2026, 8, 14), "D", null));

        verify(repository).insertNegotiatedLoan(eq(origin), eq(money("1200")), eq(money("0")),
                eq(money("0")), eq(10), any(), eq("D"), any(), eq("APROVADO"));
        verify(repository).insertRefinancing(eq(300L), eq(301L), eq(money("500")),
                eq(money("500")), eq(money("700")), eq(money("140")), eq(money("1200")));
        assertThat(response.negotiatedAmount()).isEqualByComparingTo("1200.00");
    }

    @Test
    void renewalUsesAmountToLendAsPrincipalWithoutAddingDebtAgain() {
        LoanSnapshot origin = snapshot(400L, money("500"), money("0"), money("500"));
        LoanSnapshot destination = snapshot(401L, money("1200"), money("500"), money("300"));
        when(repository.requireSnapshot(1L, 400L)).thenReturn(origin);
        when(repository.pendingDebt(400L)).thenReturn(money("500"));
        when(repository.insertNegotiatedLoan(any(), any(), any(), any(), anyInt(), any(),
                anyString(), any(), anyString())).thenReturn(401L);
        when(repository.requireSnapshot(1L, 401L)).thenReturn(destination);
        emptyRelations(destination);

        service.negotiate(administrator, 400L, "RENOVACAO",
                new LoanNegotiationRequest(money("500"), money("1200"), money("300"), money("0"),
                        10, LocalDate.of(2026, 8, 14), "D", null));

        verify(repository).insertNegotiatedLoan(eq(origin), eq(money("1200")), eq(money("300")),
                eq(money("0")), eq(10), any(), eq("D"), any(), eq("APROVADO"));
        verify(repository).insertInstallments(eq(401L), any());
        verify(repository).insertRefinancing(eq(400L), eq(401L), eq(money("500")),
                eq(money("500")), eq(money("300")), eq(money("0")), eq(money("1200")));
    }

    @Test
    void refinancingUsesAuthoritativePendingDebtInsteadOfClientValue() {
        LoanSnapshot origin = snapshot(500L, money("800"), money("0"), money("0"));
        LoanSnapshot destination = snapshot(501L, money("1100"), money("800"), money("0"));
        when(repository.requireSnapshot(1L, 500L)).thenReturn(origin);
        when(repository.pendingDebt(500L)).thenReturn(money("1000"));
        when(repository.insertNegotiatedLoan(any(), any(), any(), any(), anyInt(), any(),
                anyString(), any(), anyString())).thenReturn(501L);
        when(repository.requireSnapshot(1L, 501L)).thenReturn(destination);
        emptyRelations(destination);

        service.negotiate(administrator, 500L, "REFINANCIAMENTO",
                new LoanNegotiationRequest(money("1"), money("0"), money("100"), money("10"),
                        10, LocalDate.of(2026, 8, 14), "D", null));

        verify(repository).insertNegotiatedLoan(eq(origin), eq(money("1100")), eq(money("0")),
                eq(money("0")), eq(10), any(), eq("D"), any(), eq("APROVADO"));
        verify(repository).insertRefinancing(eq(500L), eq(501L), eq(money("800")),
                eq(money("1000")), eq(money("100")), eq(money("10")), eq(money("1100")));
    }

    @Test
    void contractMessageUsesTemplateSavedInRegion() {
        LoanSnapshot loan = snapshot(600L, money("500"), money("0"), money("100"));
        LoanInstallmentResponse installment = new LoanInstallmentResponse(
                601L, "1", LocalDateTime.of(2026, 8, 17, 12, 0), null,
                money("60"), money("0"), money("60"), money("10"), money("50"),
                money("0"), money("0"), 0, "Parcial", null, true, false, List.of());
        ContractMessageSnapshot source = new ContractMessageSnapshot(
                "CLIENTE TESTE", "RUA A", "CENTRO", "123", "78000000", null,
                "CUIABÁ", "MT",
                "Oi {cliente}! {endereco}, {numero}, {bairro}, {cidade}. Área {area}. "
                        + "Comércio: {comercio}. Contrato de {valor}, {parcelas} parcelas de "
                        + "{valorparcela}, em {data}, cobrança {tipo}.\n{gerarparcelas}",
                "Refinanciado de {valor} para {refinanciamento}.\n{gerarparcelas}");
        when(repository.requireSnapshot(1L, 600L)).thenReturn(loan);
        when(repository.installments(600L, loan.lateFee())).thenReturn(List.of(installment));
        when(repository.requireContractMessage(600L)).thenReturn(source);

        String message = service.message(administrator, 600L, "CONTRATO").message()
                .replace('\u00a0', ' ');

        assertThat(message)
                .contains("Oi CLIENTE TESTE! RUA A, 123, CENTRO, CUIABÁ - MT")
                .contains("Área REGIÃO TESTE")
                .contains("Comércio: Sem comércio")
                .contains("Contrato de R$ 500,00, 10 parcelas de R$ 60,00")
                .contains("cobrança Diário")
                .contains("*SEMANA 01*")
                .contains("🟨 Vlr. Pendente: R$ 50,00")
                .doesNotContain("{cliente}", "{valor}", "{gerarparcelas}");
    }

    @Test
    void refinancedContractUsesRefinancedTemplateSavedInRegion() {
        LoanSnapshot loan = snapshot(700L, money("1200"), money("500"), money("0"));
        ContractMessageSnapshot source = new ContractMessageSnapshot(
                "CLIENTE TESTE", null, null, null, null, null, null, null,
                "Empréstimo comum {valor}",
                "Refinanciamento de {valor} para {refinanciamento}");
        when(repository.requireSnapshot(1L, 700L)).thenReturn(loan);
        when(repository.installments(700L, loan.lateFee())).thenReturn(List.of());
        when(repository.requireContractMessage(700L)).thenReturn(source);

        String message = service.message(administrator, 700L, "CONTRATO").message()
                .replace('\u00a0', ' ');

        assertThat(message).isEqualTo("Refinanciamento de R$ 500,00 para R$ 1.200,00");
    }

    private void emptyRelations(LoanSnapshot loan) {
        when(repository.installments(loan.id(), loan.lateFee())).thenReturn(List.of());
        when(repository.history(loan.id())).thenReturn(List.of());
        when(repository.approvals(loan.id())).thenReturn(List.of());
        when(repository.origins(loan.id())).thenReturn(List.of());
    }

    private static LoanSnapshot snapshot(long id, BigDecimal loaned, BigDecimal original,
                                         BigDecimal interest) {
        return snapshot(id, loaned, original, interest, "D");
    }

    private static LoanSnapshot snapshot(long id, BigDecimal loaned, BigDecimal original,
                                         BigDecimal interest, String paymentType) {
        return new LoanSnapshot(id, 9L, "CLIENTE TESTE", 3L, "REGIÃO TESTE",
                LocalDateTime.of(2026, 8, 13, 12, 0), LocalDateTime.of(2026, 8, 14, 12, 0),
                10, null, paymentType, loaned, original, money("0"), interest, money("10"),
                money("0"), loaned.add(interest), interest, null, null, false, true,
                false, false, 2, "Em dia", "APROVADO", false);
    }

    private static UserAccount administrator() {
        UserAccount user = new UserAccount();
        ReflectionTestUtils.setField(user, "id", 1L);
        user.setUsername("ADMINISTRADOR");
        user.setAdministrator(true);
        return user;
    }

    private static UserAccount operator() {
        UserAccount user = new UserAccount();
        ReflectionTestUtils.setField(user, "id", 2L);
        user.setUsername("OPERADOR");
        user.setAdministrator(false);
        user.setReadOnly(false);
        return user;
    }

    private static BigDecimal money(String value) {
        return new BigDecimal(value).setScale(2);
    }
}
