package com.webdigital.money2.integrations;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.webdigital.money2.integrations.PixRepository.BankConfig;
import com.webdigital.money2.integrations.PixRepository.ChargeState;
import com.webdigital.money2.integrations.PixRepository.PaymentProcessingResult;
import com.webdigital.money2.integrations.SicrediPixClient.PixResult;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.loans.LoanDetailRepository;
import com.webdigital.money2.loans.LoanDetailRepository.LoanSnapshot;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

class PixServiceTest {

    private final PixRepository repository = mock(PixRepository.class);
    private final LoanDetailRepository loans = mock(LoanDetailRepository.class);
    private final PixWorkflowRepository workflow = mock(PixWorkflowRepository.class);
    private final SicrediPixClient sicredi = mock(SicrediPixClient.class);
    private final WebDigitalWhatsappClient whatsapp = mock(WebDigitalWhatsappClient.class);
    private final TransactionTemplate transactions = mock(TransactionTemplate.class);
    private final PixService service = new PixService(
            repository, loans, sicredi, whatsapp, transactions, workflow);

    @AfterEach
    void shutdown() { service.shutdown(); }

    @BeforeEach
    void executeTransactionCallbacks() {
        when(transactions.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(mock(TransactionStatus.class));
        });
    }

    @Test
    void reconciliationMarksCancelledWhenSicrediReturnsCancelled() {
        LocalDateTime now = LocalDateTime.now();
        PixChargeResponse waiting = charge(91L, "AGUARDANDO", false);
        ChargeState state = new ChargeState(waiting, "CLIENTE", 7L, "65999999999", false, false);
        BankConfig bank = new BankConfig(3L, "client", "secret", "key", "token", "api",
                "certificate", "private-key", null, now);
        PixResult remote = new PixResult("CANCELADO", "copy", null, null,
                null, null, "{}");

        when(workflow.reconciliationIds()).thenReturn(List.of(91L));
        when(repository.requireChargeForUpdate(91L)).thenReturn(state);
        when(repository.bank(3L)).thenReturn(bank);
        when(sicredi.consult(bank, waiting.transactionId())).thenReturn(remote);
        when(repository.charge(91L)).thenReturn(charge(91L, "CANCELADO", false));

        service.reconcileMoney2Charges();

        verify(repository).rawStatus(91L, "CANCELADO", "{}", null, null);
        verify(repository, never()).processPayment(anyLong(), any(), any());
    }

    @Test
    void cancellationEndpointKeepsExistingBankConfirmationFlow() {
        UserAccount user = mock(UserAccount.class);
        when(user.getId()).thenReturn(7L);
        when(user.getUsername()).thenReturn("USUARIO");
        var waiting = charge(91, "AGUARDANDO", false);
        when(repository.waitingForLoan(7, 700)).thenReturn(List.of(waiting), List.of());
        when(repository.requireChargeForUpdate(91))
                .thenReturn(new ChargeState(waiting, "CLIENTE", 7, "65999999999", false, false));
        when(repository.charge(91)).thenReturn(waiting);
        when(sicredi.consult(any(), any())).thenReturn(new PixResult("AGUARDANDO", null, null, null, null, null, "{}"));
        when(sicredi.cancel(any(), any())).thenReturn(new PixResult("CANCELADO", null, null, null, null, null, "{}"));

        var result = service.cancelPending(user, 700);

        org.junit.jupiter.api.Assertions.assertEquals(new PixCancellationResult(1, 0, 0), result);
        verify(repository).rawStatus(91, "CANCELADO", "{}", null, null);
    }

    @Test
    void reconciliationMarksCancelledWhenActiveChargeCalendarExpired() {
        LocalDateTime now = LocalDateTime.now();
        PixChargeResponse waiting = new PixChargeResponse(
                93L, 700L, null, null, 3L, "M2700TXID93", new BigDecimal("100.00"),
                "AGUARDANDO", "copy", null, null, null, false, null,
                now.minusDays(2), now.minusDays(2));
        ChargeState state = new ChargeState(waiting, "CLIENTE", 7L, "65999999999", false, false);
        BankConfig bank = new BankConfig(3L, "client", "secret", "key", "token", "api",
                "certificate", "private-key", null, now);
        PixResult activeButExpired = new PixResult(
                "AGUARDANDO", "copy", null, null, null, now.minusMinutes(1), "{}");

        when(workflow.reconciliationIds()).thenReturn(List.of(93L));
        when(repository.requireChargeForUpdate(93L)).thenReturn(state);
        when(repository.bank(3L)).thenReturn(bank);
        when(sicredi.consult(bank, waiting.transactionId())).thenReturn(activeButExpired);
        when(repository.charge(93L)).thenReturn(charge(93L, "CANCELADO", false));

        service.reconcileMoney2Charges();

        verify(repository).rawStatus(93L, "CANCELADO", "{}", null, null);
    }

    @Test
    void reconciliationKeepsActiveChargeWaitingBeforeCalendarExpires() {
        LocalDateTime now = LocalDateTime.now();
        PixChargeResponse waiting = charge(94L, "AGUARDANDO", false);
        ChargeState state = new ChargeState(waiting, "CLIENTE", 7L, "65999999999", false, false);
        BankConfig bank = new BankConfig(3L, "client", "secret", "key", "token", "api",
                "certificate", "private-key", null, now);
        PixResult active = new PixResult(
                "AGUARDANDO", "copy", null, null, null, now.plusMinutes(1), "{}");

        when(workflow.reconciliationIds()).thenReturn(List.of(94L));
        when(repository.requireChargeForUpdate(94L)).thenReturn(state);
        when(repository.bank(3L)).thenReturn(bank);
        when(sicredi.consult(bank, waiting.transactionId())).thenReturn(active);
        when(repository.charge(94L)).thenReturn(charge(94L, "AGUARDANDO", false));

        service.reconcileMoney2Charges();

        verify(repository).rawStatus(94L, "AGUARDANDO", "{}", null, null);
    }

    @Test
    void paidPixRefreshesLoanTotalsAndDoesNotDuplicateWhatsappWithoutClaim() {
        PixChargeResponse paid = charge(92L, "PAGO", false);
        ChargeState state = new ChargeState(paid, "CLIENTE", 7L, "65999999999", false, false);

        when(workflow.reconciliationIds()).thenReturn(List.of(92L));
        when(repository.requireChargeForUpdate(92L)).thenReturn(state);
        when(repository.charge(92L)).thenReturn(paid);
        when(repository.processPayment(eq(92L), eq(paid.transactionId()), any()))
                .thenReturn(new PaymentProcessingResult(501L, true, paid.loanId()));
        when(repository.claimWhatsappConfirmation(92L)).thenReturn(false);

        service.reconcileMoney2Charges();

        verify(loans).refreshLoanFinancialTotals(paid.loanId());
        verify(whatsapp, never()).sendText(any(), any(), any(), any(), any(), any(), any());
    }

    @ParameterizedTest
    @ValueSource(strings = {"100.00", "600.00"})
    void readOnlyCollectorCanGeneratePixIncludingAmountAboveContractBalance(String requestedAmount) {
        BigDecimal amount = new BigDecimal(requestedAmount);
        UserAccount collector = new UserAccount();
        ReflectionTestUtils.setField(collector, "id", 17L);
        collector.setUsername("COBRADOR");
        collector.setCollector(true);
        collector.setReadOnly(true);
        LoanSnapshot loan = new LoanSnapshot(
                700L, 9L, "CLIENTE TESTE", 3L, "REGIÃO TESTE",
                LocalDate.of(2026, 9, 1).atStartOfDay(),
                LocalDate.of(2026, 9, 2).atStartOfDay(),
                10, null, "D", new BigDecimal("300.00"), BigDecimal.ZERO,
                BigDecimal.ZERO, new BigDecimal("200.00"), BigDecimal.TEN,
                BigDecimal.ZERO, new BigDecimal("500.00"), new BigDecimal("200.00"),
                null, null, false, true, false, false, 2, "Em dia", "APROVADO", false);
        BankConfig bank = new BankConfig(
                3L, "client", "secret", "key", "token", "api",
                "certificate", "private-key", null, LocalDateTime.now());
        PixResult generated = new PixResult(
                "AGUARDANDO", "copy", null, null, null, null, "{}");
        PixChargeResponse response = charge(95L, "AGUARDANDO", false);

        when(loans.requireSnapshot(17L, 700L)).thenReturn(loan);
        when(repository.available(700L, null)).thenReturn(new BigDecimal("500.00"));
        when(repository.waiting(700L, null)).thenReturn(List.of());
        when(repository.bankForRegion(3L)).thenReturn(bank);
        when(repository.insert(eq(700L), eq(null), eq(3L), any(), eq(amount)))
                .thenReturn(95L);
        when(sicredi.create(eq(bank), eq(700L), eq(null), any(), eq(amount)))
                .thenReturn(generated);
        when(repository.charge(95L)).thenReturn(response);

        service.generate(collector, 700L, new PixGenerateRequest(null, amount));

        verify(repository).insert(eq(700L), eq(null), eq(3L), any(), eq(amount));
    }

    private PixChargeResponse charge(long id, String status, boolean processed) {
        LocalDateTime now = LocalDateTime.now();
        return new PixChargeResponse(id, 700L, null, null, 3L, "M2700TXID",
                new BigDecimal("100.00"), status, "copy", null, null, null,
                processed, null, now.minusHours(1), now);
    }

    @Test
    void paymentQueuesBothMessagesWithoutWaitingForWhatsapp() {
        var paid = charge(92L, "PAGO", false);
        var state = new ChargeState(paid, "CLIENTE", 7L, "65999999999", false, false);
        when(workflow.reconciliationIds()).thenReturn(List.of(92L));
        when(repository.requireChargeForUpdate(92L)).thenReturn(state);
        when(repository.charge(92L)).thenReturn(paid);
        when(repository.processPayment(eq(92L), eq(paid.transactionId()), any()))
                .thenReturn(new PaymentProcessingResult(501L, true, paid.loanId()));

        service.reconcileMoney2Charges();

        verify(workflow).enqueue(92L);
        verify(loans).refreshLoanFinancialTotals(700L);
        verify(whatsapp, never()).sendText(any(), any(), any(), any(), any(), any(), any());
    }

    @Test
    void alreadyProcessedPaymentDoesNotReplayHistoricalMessages() {
        var paid = charge(92L, "PAGO", true);
        when(workflow.reconciliationIds()).thenReturn(List.of(92L));
        when(repository.requireChargeForUpdate(92L))
                .thenReturn(new ChargeState(paid, "CLIENTE", 7L, "65999999999", true, true));
        when(repository.charge(92L)).thenReturn(paid);
        when(repository.processPayment(eq(92L), any(), any()))
                .thenReturn(new PaymentProcessingResult(501L, false, 700L));

        service.reconcileMoney2Charges();

        verify(workflow, never()).enqueue(anyLong());
    }

    @Test
    void collectionIsSuspendedWhenBankCannotConfirmOutstandingPix() {
        var waiting = charge(91L, "AGUARDANDO", false);
        when(workflow.collectionChargeIds(700L)).thenReturn(List.of(91L));
        when(repository.requireChargeForUpdate(91L))
                .thenReturn(new ChargeState(waiting, "CLIENTE", 7L, "65999999999", false, false));
        when(sicredi.consult(any(), any())).thenThrow(new IllegalStateException("Banco indisponível"));

        org.junit.jupiter.api.Assertions.assertFalse(service.prepareCollection(700L));
    }

    @Test
    void collectionReconcilesPaymentBeforeCheckingDebt() {
        var waiting = charge(91L, "AGUARDANDO", false);
        var paid = charge(91L, "PAGO", true);
        when(workflow.collectionChargeIds(700L)).thenReturn(List.of(91L));
        when(repository.requireChargeForUpdate(91L))
                .thenReturn(new ChargeState(waiting, "CLIENTE", 7L, "65999999999", false, false));
        when(sicredi.consult(any(), any())).thenReturn(new PixResult("PAGO", null, null, null,
                LocalDateTime.now(), null, "{}"));
        when(repository.charge(91L)).thenReturn(paid);
        when(repository.processPayment(eq(91L), any(), any()))
                .thenReturn(new PaymentProcessingResult(501L, true, 700L));

        org.junit.jupiter.api.Assertions.assertTrue(service.prepareCollection(700L));
        verify(workflow).enqueue(91L);
        verify(loans).refreshLoanFinancialTotals(700L);
    }
}
