package com.webdigital.money2.integrations;

import com.fasterxml.jackson.databind.JsonNode;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappSecret;
import com.webdigital.money2.integrations.PixRepository.ChargeState;
import com.webdigital.money2.integrations.PixRepository.PaymentProcessingResult;
import com.webdigital.money2.integrations.PixRepository.WhatsappTarget;
import com.webdigital.money2.integrations.SicrediPixClient.PixResult;
import com.webdigital.money2.loans.LoanDetailRepository;
import com.webdigital.money2.loans.LoanDetailRepository.LoanSnapshot;
import com.webdigital.money2.loans.LoanDetailService;
import com.webdigital.money2.shared.ApiException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.http.HttpStatus;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class PixService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");
    private static final String PIX_MESSAGE = "Olá, {nome_cliente}. Segue o PIX do contrato {contrato}, no valor de {valor_pix}.";
    private static final String PIX_RECEIVED = "Olá, {nome_cliente}. Recebemos seu pagamento via PIX no valor de {valor_pix}, referente ao contrato {contrato}. Obrigado!";
    private final PixRepository repository;
    private final LoanDetailRepository loans;
    private final LoanDetailService loanDetails;
    private final SicrediPixClient sicredi;
    private final WebDigitalWhatsappClient whatsapp;
    private final TransactionTemplate transactions;
    private final ConcurrentHashMap<Long, Object> loanLocks = new ConcurrentHashMap<>();

    public PixService(PixRepository repository, LoanDetailRepository loans, LoanDetailService loanDetails,
                      SicrediPixClient sicredi, WebDigitalWhatsappClient whatsapp,
                      TransactionTemplate transactions) {
        this.repository = repository;
        this.loans = loans;
        this.loanDetails = loanDetails;
        this.sicredi = sicredi;
        this.whatsapp = whatsapp;
        this.transactions = transactions;
    }

    public PixChargeResponse current(UserAccount user, long loanId, Long installmentId) {
        loans.requireSnapshot(user.getId(), loanId);
        if (installmentId != null) loans.requireInstallment(loanId, installmentId);
        return repository.current(user.getId(), loanId, installmentId);
    }

    public PixCancellationResult cancelPending(UserAccount user, long loanId) {
        loans.requireSnapshot(user.getId(), loanId);
        Object lock = loanLocks.computeIfAbsent(loanId, ignored -> new Object());
        synchronized (lock) {
            try {
                int cancelled = 0;
                int paid = 0;
                for (PixChargeResponse pending : repository.waitingForLoan(user.getId(), loanId)) {
                    PixChargeResponse refreshed = refreshSystem(pending.id());
                    if ("PAGO".equals(refreshed.status())) {
                        paid++;
                        continue;
                    }
                    if (!"AGUARDANDO".equals(refreshed.status())) continue;

                    PixRepository.BankConfig bank = repository.bank(refreshed.bankAccountId());
                    PixResult result = sicredi.cancel(bank, refreshed.transactionId());
                    String status = effectiveStatus(result);
                    if ("AGUARDANDO".equals(status)) {
                        // If PATCH returned no decisive status, consult the bank before
                        // deciding whether the loan can safely be released.
                        result = sicredi.consult(bank, refreshed.transactionId());
                        status = effectiveStatus(result);
                    }
                    repository.rawStatus(refreshed.id(), status, result.rawResponse(), null, result.paidAt());
                    if ("PAGO".equals(status)) {
                        processPaid(refreshed.id(), result.paidAt());
                        paid++;
                    } else if ("CANCELADO".equals(status)) {
                        cancelled++;
                    } else {
                        throw new ApiException(HttpStatus.BAD_GATEWAY,
                                "O Sicredi não confirmou o cancelamento de todos os PIX. "
                                        + "O contrato continuará bloqueado até a confirmação.");
                    }
                }
                if (cancelled > 0) {
                    try {
                        loans.log("EMPRESTIMO", loanId, "cancelarPix",
                                cancelled + " cobrança(s) PIX cancelada(s) no Sicredi.", user.getUsername());
                    } catch (RuntimeException ignored) {
                        // A falha de auditoria não desfaz o cancelamento confirmado pelo banco.
                    }
                }
                int remaining = repository.waitingForLoan(user.getId(), loanId).size();
                return new PixCancellationResult(cancelled, paid, remaining);
            } finally {
                loanLocks.remove(loanId, lock);
            }
        }
    }

    public PixChargeResponse generate(UserAccount user, long loanId, PixGenerateRequest request) {
        LoanSnapshot loan = loans.requireSnapshot(user.getId(), loanId);
        if (loan.numericStatus() == 3 || loan.refinanced() || loan.operationLocked()) {
            throw new ApiException(HttpStatus.CONFLICT, "Este contrato não aceita uma nova cobrança PIX.");
        }
        Long installmentId = request == null ? null : request.installmentId();
        if (installmentId != null) loans.requireInstallment(loanId, installmentId);
        BigDecimal amount = money(request == null ? null : request.amount());
        if (amount.signum() <= 0) throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o valor do PIX.");
        validateAvailable(loanId, installmentId, amount);
        Object lock = loanLocks.computeIfAbsent(loanId, ignored -> new Object());
        synchronized (lock) {
            try {
                cancelWaiting(loanId, installmentId);
                // O PIX anterior pode ter sido pago enquanto era cancelado.
                validateAvailable(loanId, installmentId, amount);
                PixRepository.BankConfig bank = repository.bankForRegion(loan.regionId());
                String transactionId = transactionId(loanId);
                long pixId = repository.insert(loanId, installmentId, bank.id(), transactionId, amount);
                PixResult result;
                try {
                    result = sicredi.create(bank, loanId, installmentId, transactionId, amount);
                } catch (RuntimeException exception) {
                    repository.failed(pixId, "ERRO", message(exception));
                    throw exception;
                }
                String status = result.status();
                repository.generated(pixId, result.copyAndPaste(), result.qrCode(), result.location(),
                        result.rawResponse(), status, result.paidAt());
                if ("PAGO".equals(status)) {
                    try {
                        processPaid(pixId, result.paidAt());
                    } catch (RuntimeException ignored) {
                        // O recebimento permanece como PAGO e será reprocessado pelo conciliador.
                    }
                }
                try {
                    loans.log("EMPRESTIMO", loanId, "gerarPix",
                            "PIX gerado no valor de " + amount + ".", user.getUsername());
                } catch (RuntimeException ignored) {
                    // A auditoria não pode invalidar uma cobrança já criada no banco.
                }
                return repository.charge(pixId);
            } finally {
                loanLocks.remove(loanId, lock);
            }
        }
    }

    public PixChargeResponse refresh(UserAccount user, long pixId) {
        ChargeState state = repository.requireCharge(user.getId(), pixId);
        return refresh(state, false, false);
    }

    public PixChargeResponse sendWhatsapp(UserAccount user, long pixId) {
        ChargeState state = repository.requireCharge(user.getId(), pixId);
        PixChargeResponse pix = state.charge();
        if (!"AGUARDANDO".equals(pix.status()) || blank(pix.copyAndPaste())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Este PIX não está disponível para envio.");
        }
        sendWhatsapp(state, false);
        return repository.charge(pixId);
    }

    @Scheduled(fixedDelay = 15000L, initialDelay = 30000L)
    public void reconcileMoney2Charges() {
        for (Long pixId : repository.pendingMoney2Ids()) {
            try {
                ChargeState state = repository.requireChargeForUpdate(pixId);
                refresh(state, true, true);
            } catch (RuntimeException ignored) {
                // A falha fica registrada na própria cobrança e será tentada novamente.
            }
        }
    }

    private PixChargeResponse refresh(
            ChargeState state, boolean suppressRemoteFailure, boolean reconcileCancelled) {
        PixChargeResponse pix = state.charge();
        if ("ERRO".equals(pix.status()) || ("CANCELADO".equals(pix.status()) && !reconcileCancelled)) {
            return pix;
        }
        if ("PAGO".equals(pix.status())) {
            try {
                processPaid(pix.id(), pix.paidAt());
            } catch (RuntimeException exception) {
                if (!suppressRemoteFailure) throw exception;
            }
            return repository.charge(pix.id());
        }
        PixResult result;
        try {
            result = sicredi.consult(repository.bank(pix.bankAccountId()), pix.transactionId());
        } catch (RuntimeException exception) {
            repository.rawStatus(pix.id(), pix.status(), null, message(exception), null);
            if (!suppressRemoteFailure) {
                throw new ApiException(HttpStatus.BAD_GATEWAY,
                        "Não foi possível consultar o PIX no Sicredi. Tente novamente.");
            }
            return repository.charge(pix.id());
        }
        String status = effectiveStatus(result);
        repository.rawStatus(pix.id(), status, result.rawResponse(), null, result.paidAt());
        if ("PAGO".equals(status)) {
            try {
                processPaid(pix.id(), result.paidAt());
            } catch (RuntimeException exception) {
                if (!suppressRemoteFailure) throw exception;
            }
        }
        return repository.charge(pix.id());
    }

    private String effectiveStatus(PixResult result) {
        if (!"AGUARDANDO".equals(result.status())) return result.status();
        LocalDateTime expiresAt = result.expiresAt();
        return expiresAt != null && !expiresAt.isAfter(LocalDateTime.now(BUSINESS_ZONE))
                ? "CANCELADO"
                : "AGUARDANDO";
    }

    private void cancelWaiting(long loanId, Long installmentId) {
        for (PixChargeResponse current : repository.waiting(loanId, installmentId)) {
            PixChargeResponse refreshed = refreshSystem(current.id());
            if (!"AGUARDANDO".equals(refreshed.status())) continue;
            try {
                PixResult result = sicredi.cancel(repository.bank(refreshed.bankAccountId()), refreshed.transactionId());
                String status = result.status();
                repository.rawStatus(refreshed.id(), status, result.rawResponse(), null, result.paidAt());
                if ("PAGO".equals(status)) processPaid(refreshed.id(), result.paidAt());
                if ("AGUARDANDO".equals(status)) {
                    throw new ApiException(HttpStatus.BAD_GATEWAY,
                            "O Sicredi não confirmou o cancelamento do PIX anterior.");
                }
            } catch (RuntimeException exception) {
                throw new ApiException(HttpStatus.BAD_GATEWAY,
                        "Não foi possível confirmar o cancelamento do PIX anterior no Sicredi; "
                                + "um novo código não foi gerado para evitar duplicidade.");
            }
        }
    }

    private PixChargeResponse refreshSystem(long pixId) {
        ChargeState state = repository.requireChargeForUpdate(pixId);
        return refresh(state, false, false);
    }

    private void processPaid(long pixId, LocalDateTime paidAt) {
        PaymentProcessingResult processing;
        try {
            processing = transactions.execute(status -> {
                PixChargeResponse pix = repository.charge(pixId);
                PaymentProcessingResult result = repository.processPayment(
                        pixId, pix.transactionId(),
                        paidAt == null ? LocalDateTime.now(BUSINESS_ZONE) : paidAt);
                if (result.processedNow()) loans.refreshLoanFinancialTotals(result.loanId());
                return result;
            });
        } catch (RuntimeException exception) {
            repository.paymentProcessingFailed(pixId, message(exception));
            throw exception;
        }
        if (processing == null || !repository.claimWhatsappConfirmation(pixId)) return;
        ChargeState paid = repository.requireChargeForUpdate(pixId);
        try {
            sendWhatsapp(paid, true);
            sendUpdatedLoanMessage(paid);
        } catch (RuntimeException exception) {
            repository.markWhatsappConfirmation(pixId, false, message(exception));
        }
    }

    private void sendWhatsapp(ChargeState state, boolean confirmation) {
        WhatsappSecret config = repository.whatsappSecret();
        if (!config.active() || blank(config.token())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "A API WhatsApp não está ativa e configurada.");
        }
        if (blank(state.phone())) throw new ApiException(HttpStatus.BAD_REQUEST, "O cliente não possui telefone válido.");
        WhatsappTarget device = repository.whatsappTarget(state.regionId());
        PixChargeResponse pix = state.charge();
        String source = confirmation
                ? first(config.pixReceivedMessage(), PIX_RECEIVED)
                : first(config.pixMessage(), PIX_MESSAGE);
        String message = source.replace("{nome_cliente}", state.clientName())
                .replace("{cliente}", state.clientName())
                .replace("{contrato}", Long.toString(pix.loanId()))
                .replace("{valor_pix}", currency(pix.amount()));
        String logMessage = confirmation ? message : message + "\n\n" + pix.copyAndPaste();
        try {
            JsonNode dispatch;
            if (confirmation) {
                dispatch = whatsapp.sendText(config, device.remoteId(), state.phone(), message,
                        "money.pix.received", "pix-received:" + pix.id(), state.clientName());
            } else {
                if (!device.pixCopySupported()) {
                    throw new ApiException(HttpStatus.BAD_REQUEST,
                            "O dispositivo selecionado não oferece o botão de copiar código PIX.");
                }
                dispatch = whatsapp.sendPix(config, device.remoteId(), state.phone(), message, pix.copyAndPaste(),
                        "pix:" + pix.id(), state.clientName());
            }
            repository.whatsappLog(state, device, confirmation ? "PIX_RECEBIDO" : "PIX",
                    WebDigitalWhatsappClient.logStatus(dispatch), logMessage,
                    WebDigitalWhatsappClient.pendingNotice(dispatch));
            // Accepted sends must not be repeated while the recipient is offline.
            if (confirmation) repository.markWhatsappConfirmation(pix.id(), true,
                    WebDigitalWhatsappClient.pendingNotice(dispatch));
        } catch (RuntimeException exception) {
            repository.whatsappLog(state, device, confirmation ? "PIX_RECEBIDO" : "PIX",
                    "ERRO", logMessage, message(exception));
            if (confirmation) repository.markWhatsappConfirmation(pix.id(), false, message(exception));
            throw exception;
        }
    }

    private void sendUpdatedLoanMessage(ChargeState state) {
        PixChargeResponse pix = state.charge();
        WhatsappTarget device = null;
        try {
            WhatsappSecret config = repository.whatsappSecret();
            device = repository.whatsappTarget(state.regionId());
            String updatedMessage = loanDetails.contractMessageForSystem(pix.loanId());
            JsonNode dispatch = whatsapp.sendText(config, device.remoteId(), state.phone(), updatedMessage,
                    "money.loan.updated", "loan-updated-after-pix:" + pix.id(), state.clientName());
            repository.whatsappLog(state, device, "EMPRESTIMO_ATUALIZADO",
                    WebDigitalWhatsappClient.logStatus(dispatch), updatedMessage,
                    WebDigitalWhatsappClient.pendingNotice(dispatch));
        } catch (RuntimeException exception) {
            String error = "Confirmação PIX enviada, mas falhou a mensagem atualizada: " + message(exception);
            if (device != null) {
                repository.whatsappLog(state, device, "EMPRESTIMO_ATUALIZADO",
                        "ERRO", null, error);
            }
            repository.markWhatsappConfirmation(pix.id(), true, error);
        }
    }

    private void validateAvailable(long loanId, Long installmentId, BigDecimal amount) {
        BigDecimal available = repository.available(loanId, installmentId);
        if (available.signum() <= 0) {
            throw new ApiException(HttpStatus.CONFLICT, "Não existe saldo pendente para cobrança.");
        }
        if (amount.compareTo(available) > 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "O PIX não pode ser maior que o saldo de " + available.toPlainString() + ".");
        }
    }

    private String transactionId(long loanId) {
        String raw = "M2" + loanId + UUID.randomUUID().toString().replace("-", "");
        return raw.length() > 35 ? raw.substring(0, 35) : raw;
    }

    private String currency(BigDecimal amount) {
        return "R$ " + amount.setScale(2, RoundingMode.HALF_UP).toPlainString().replace('.', ',');
    }

    private BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value).setScale(2, RoundingMode.HALF_UP);
    }

    private String first(String value, String fallback) { return blank(value) ? fallback : value.trim(); }
    private boolean blank(String value) { return value == null || value.isBlank(); }
    private String message(Throwable error) {
        String value = error == null || error.getMessage() == null ? "Falha de integração." : error.getMessage().trim();
        return value.length() > 1000 ? value.substring(0, 1000) : value;
    }
}
