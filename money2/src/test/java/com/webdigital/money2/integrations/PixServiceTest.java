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
import com.webdigital.money2.loans.LoanDetailService;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

class PixServiceTest {

    private final PixRepository repository = mock(PixRepository.class);
    private final LoanDetailRepository loans = mock(LoanDetailRepository.class);
    private final LoanDetailService loanDetails = mock(LoanDetailService.class);
    private final SicrediPixClient sicredi = mock(SicrediPixClient.class);
    private final WebDigitalWhatsappClient whatsapp = mock(WebDigitalWhatsappClient.class);
    private final TransactionTemplate transactions = mock(TransactionTemplate.class);
    private final PixService service = new PixService(
            repository, loans, loanDetails, sicredi, whatsapp, transactions);

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

        when(repository.pendingMoney2Ids()).thenReturn(List.of(91L));
        when(repository.requireChargeForUpdate(91L)).thenReturn(state);
        when(repository.bank(3L)).thenReturn(bank);
        when(sicredi.consult(bank, waiting.transactionId())).thenReturn(remote);
        when(repository.charge(91L)).thenReturn(charge(91L, "CANCELADO", false));

        service.reconcileMoney2Charges();

        verify(repository).rawStatus(91L, "CANCELADO", "{}", null, null);
        verify(repository, never()).processPayment(anyLong(), any(), any());
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

        when(repository.pendingMoney2Ids()).thenReturn(List.of(93L));
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

        when(repository.pendingMoney2Ids()).thenReturn(List.of(94L));
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

        when(repository.pendingMoney2Ids()).thenReturn(List.of(92L));
        when(repository.requireChargeForUpdate(92L)).thenReturn(state);
        when(repository.charge(92L)).thenReturn(paid);
        when(repository.processPayment(eq(92L), eq(paid.transactionId()), any()))
                .thenReturn(new PaymentProcessingResult(501L, true, paid.loanId()));
        when(repository.claimWhatsappConfirmation(92L)).thenReturn(false);

        service.reconcileMoney2Charges();

        verify(loans).refreshLoanFinancialTotals(paid.loanId());
        verify(whatsapp, never()).sendText(any(), any(), any(), any(), any(), any(), any());
    }

    @Test
    void readOnlyCollectorCanGeneratePixForAccessibleContract() {
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
        when(repository.insert(eq(700L), eq(null), eq(3L), any(), eq(new BigDecimal("100.00"))))
                .thenReturn(95L);
        when(sicredi.create(eq(bank), eq(700L), eq(null), any(), eq(new BigDecimal("100.00"))))
                .thenReturn(generated);
        when(repository.charge(95L)).thenReturn(response);

        service.generate(collector, 700L, new PixGenerateRequest(null, new BigDecimal("100.00")));

        verify(repository).insert(eq(700L), eq(null), eq(3L), any(), eq(new BigDecimal("100.00")));
    }

    private PixChargeResponse charge(long id, String status, boolean processed) {
        LocalDateTime now = LocalDateTime.now();
        return new PixChargeResponse(id, 700L, null, null, 3L, "M2700TXID",
                new BigDecimal("100.00"), status, "copy", null, null, null,
                processed, null, now.minusHours(1), now);
    }

    @Test
    void delayedPixDeliveryDoesNotPreventUpdatedContractMessage() throws Exception {
        var paid = charge(92L, "PAGO", false);
        var state = new ChargeState(paid, "CLIENTE", 7L, "65999999999", false, false);
        var config = new IntegrationModels.WhatsappSecret(true, "token",
                "https://webdigital.dev/api/v1", null, null, null, null, null, null);
        var device = new PixRepository.WhatsappTarget(1L, "device", "Teste", true);
        var pending = new com.fasterxml.jackson.databind.ObjectMapper().readTree("""
                {"status":"processing","dispatch_id":"pending-92","provider_message_id":"EVO-92"}
                """);
        when(repository.pendingMoney2Ids()).thenReturn(List.of(92L));
        when(repository.requireChargeForUpdate(92L)).thenReturn(state);
        when(repository.charge(92L)).thenReturn(paid);
        when(repository.processPayment(eq(92L), eq(paid.transactionId()), any()))
                .thenReturn(new PaymentProcessingResult(501L, true, paid.loanId()));
        when(repository.claimWhatsappConfirmation(92L)).thenReturn(true);
        when(repository.whatsappSecret()).thenReturn(config);
        when(repository.whatsappTarget(7L)).thenReturn(device);
        when(whatsapp.sendText(any(), any(), any(), any(), any(), any(), any())).thenReturn(pending);
        when(loanDetails.contractMessageForSystem(700L)).thenReturn("Contrato atualizado");

        service.reconcileMoney2Charges();

        verify(whatsapp).sendText(eq(config), eq("device"), eq(state.phone()),
                eq("Contrato atualizado"), eq("money.loan.updated"),
                eq("loan-updated-after-pix:92"), eq("CLIENTE"));
        verify(repository).whatsappLog(eq(state), eq(device), eq("PIX_RECEBIDO"),
                eq("AVISO"), any(), eq(WebDigitalWhatsappClient.pendingNotice(pending)));
        verify(repository, never()).markWhatsappConfirmation(eq(92L), eq(false), any());
    }
}
