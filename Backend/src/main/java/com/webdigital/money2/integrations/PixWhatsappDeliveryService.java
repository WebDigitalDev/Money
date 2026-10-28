package com.webdigital.money2.integrations;

import com.fasterxml.jackson.databind.JsonNode;
import com.webdigital.money2.integrations.PixWorkflowRepository.Delivery;
import com.webdigital.money2.loans.LoanDetailService;
import java.math.RoundingMode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Service
public class PixWhatsappDeliveryService {
    private static final Logger log = LoggerFactory.getLogger(PixWhatsappDeliveryService.class);
    private static final String RECEIVED = "Olá, {nome_cliente}. Recebemos seu pagamento via PIX no valor de {valor_pix}, referente ao contrato {contrato}. Obrigado!";
    private final PixWorkflowRepository workflow;
    private final PixRepository pix;
    private final LoanDetailService loans;
    private final WebDigitalWhatsappClient whatsapp;

    public PixWhatsappDeliveryService(PixWorkflowRepository workflow, PixRepository pix,
                                      LoanDetailService loans, WebDigitalWhatsappClient whatsapp) {
        this.workflow = workflow;
        this.pix = pix;
        this.loans = loans;
        this.whatsapp = whatsapp;
    }

    @Scheduled(scheduler = "pixWhatsappScheduler", initialDelay = 2000, fixedDelay = 1000)
    @Scheduled(scheduler = "pixWhatsappScheduler", initialDelay = 2250, fixedDelay = 1000)
    @Scheduled(scheduler = "pixWhatsappScheduler", initialDelay = 2500, fixedDelay = 1000)
    @Scheduled(scheduler = "pixWhatsappScheduler", initialDelay = 2750, fixedDelay = 1000)
    public void deliverNext() {
        Delivery delivery = workflow.claim();
        if (delivery == null) return;
        PixRepository.ChargeState state = null;
        PixRepository.WhatsappTarget device = null;
        try {
            var configuration = pix.whatsappSecret();
            if (!configuration.active() || configuration.token() == null || configuration.token().isBlank()) {
                throw new IllegalStateException("A API WhatsApp não está ativa e configurada.");
            }
            state = pix.requireChargeForUpdate(delivery.pixId());
            if (delivery.message() == null) {
                device = pix.whatsappTarget(state.regionId());
                String message = delivery.receipt() ? receiptMessage(configuration.pixReceivedMessage(), state)
                        : loans.contractMessageForSystem(state.charge().loanId());
                delivery = delivery.withPayload(state, device, message);
                // Persist the exact request before network I/O: retries keep the same idempotency key.
                workflow.savePayload(delivery);
            } else {
                device = new PixRepository.WhatsappTarget(delivery.deviceId(), delivery.remoteId(), "", false);
            }
            JsonNode dispatch = whatsapp.sendText(configuration, delivery.remoteId(), delivery.phone(),
                    delivery.message(), delivery.event(), delivery.reference(), delivery.clientName());
            pix.whatsappLog(state, device, delivery.type(), WebDigitalWhatsappClient.logStatus(dispatch),
                    delivery.message(), WebDigitalWhatsappClient.pendingNotice(dispatch));
            workflow.accepted(delivery, dispatch.path("dispatch_id").asText(null),
                    WebDigitalWhatsappClient.pendingNotice(dispatch));
        } catch (RuntimeException exception) {
            String error = exception.getMessage() == null ? "Falha na entrega WhatsApp." : exception.getMessage();
            if (error.length() > 1000) error = error.substring(0, 1000);
            workflow.failed(delivery, error);
            if (state != null && device != null) {
                pix.whatsappLog(state, device, delivery.type(), "ERRO", delivery.message(), error);
            }
            log.warn("WhatsApp PIX {} tipo {} tentativa {}: {}", delivery.pixId(), delivery.type(),
                    delivery.attempts(), error);
        }
    }

    private String receiptMessage(String template, PixRepository.ChargeState state) {
        String source = template == null || template.isBlank() ? RECEIVED : template;
        return source.replace("{nome_cliente}", state.clientName()).replace("{cliente}", state.clientName())
                .replace("{contrato}", Long.toString(state.charge().loanId()))
                .replace("{valor_pix}", "R$ " + state.charge().amount().setScale(2, RoundingMode.HALF_UP)
                        .toPlainString().replace('.', ','));
    }
}
