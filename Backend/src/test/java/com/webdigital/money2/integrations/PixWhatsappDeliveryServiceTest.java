package com.webdigital.money2.integrations;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.webdigital.money2.integrations.PixWorkflowRepository.Delivery;
import com.webdigital.money2.loans.LoanDetailService;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class PixWhatsappDeliveryServiceTest {
    private final PixWorkflowRepository workflow = mock(PixWorkflowRepository.class);
    private final PixRepository pix = mock(PixRepository.class);
    private final LoanDetailService loans = mock(LoanDetailService.class);
    private final WebDigitalWhatsappClient whatsapp = mock(WebDigitalWhatsappClient.class);
    private final PixWhatsappDeliveryService service = new PixWhatsappDeliveryService(workflow, pix, loans, whatsapp);
    private final IntegrationModels.WhatsappSecret config = new IntegrationModels.WhatsappSecret(
            true, "token", "https://webdigital.dev/api/v1", null, null, null, null, null, null);
    private final PixRepository.WhatsappTarget device = new PixRepository.WhatsappTarget(1, "device", "Teste", true);
    private final PixRepository.ChargeState state = new PixRepository.ChargeState(
            new PixChargeResponse(92, 700, null, 501L, 3, "M2700TXID", new BigDecimal("100.00"),
                    "PAGO", "copy", null, null, null, true, LocalDateTime.now(), LocalDateTime.now(), LocalDateTime.now()),
            "CLIENTE", 7, "65999999999", true, true);

    @BeforeEach
    void setUp() {
        when(pix.whatsappSecret()).thenReturn(config);
        when(pix.requireChargeForUpdate(92)).thenReturn(state);
        when(pix.whatsappTarget(7)).thenReturn(device);
        when(loans.contractMessageForSystem(700)).thenReturn("Contrato atualizado");
    }

    @Test
    void delayedContractDeliveryIsAcceptedAndNeverRetried() throws Exception {
        var delivery = task("EMPRESTIMO_ATUALIZADO");
        when(workflow.claim()).thenReturn(delivery).thenReturn(null);
        var pending = new ObjectMapper().readTree("""
                {"status":"processing","dispatch_id":"pending-92","provider_message_id":"EVO-92"}
                """);
        when(whatsapp.sendText(any(), any(), any(), any(), any(), any(), any())).thenReturn(pending);

        service.deliverNext();
        service.deliverNext();

        verify(whatsapp, times(1)).sendText(eq(config), eq("device"), eq(state.phone()),
                eq("Contrato atualizado"), eq("money.loan.updated"), eq("loan-updated-after-pix:92"), eq("CLIENTE"));
        verify(workflow).accepted(any(), eq("pending-92"), eq(WebDigitalWhatsappClient.pendingNotice(pending)));
        verify(workflow, never()).failed(any(), any());
    }

    @Test
    void contractFailureRemainsRetryableIndependentlyOfAcceptedReceipt() {
        when(workflow.claim()).thenReturn(task("EMPRESTIMO_ATUALIZADO"));
        when(whatsapp.sendText(any(), any(), any(), any(), any(), any(), any()))
                .thenThrow(new IllegalStateException("Tempo esgotado"));

        service.deliverNext();

        verify(workflow).failed(any(), eq("Tempo esgotado"));
        verify(workflow, never()).accepted(any(), any(), any());
        verify(pix, never()).markWhatsappConfirmation(anyLong(), anyBoolean(), any());
    }

    @Test
    void retryReusesPersistedContractAndDestinationForIdempotency() throws Exception {
        Delivery persisted = new Delivery(92, "EMPRESTIMO_ATUALIZADO", 2, "lease", 1L,
                "original-device", "65988888888", "Nome original", "Contrato da primeira tentativa");
        when(workflow.claim()).thenReturn(persisted);
        when(whatsapp.sendText(any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(new ObjectMapper().readTree("{\"status\":\"sent\"}"));

        service.deliverNext();

        verify(loans, never()).contractMessageForSystem(anyLong());
        verify(pix, never()).whatsappTarget(anyLong());
        verify(whatsapp).sendText(config, "original-device", "65988888888",
                "Contrato da primeira tentativa", "money.loan.updated", "loan-updated-after-pix:92", "Nome original");
    }

    @Test
    void disconnectedRegionKeepsBothMessagesAvailableForRetry() {
        when(workflow.claim()).thenReturn(task("PIX_RECEBIDO"));
        when(pix.whatsappTarget(7)).thenThrow(new IllegalStateException("Nenhum dispositivo conectado"));

        service.deliverNext();

        verify(workflow).failed(any(), eq("Nenhum dispositivo conectado"));
        verifyNoInteractions(whatsapp);
    }

    @Test
    void payloadIsPersistedBeforeNetworkRequest() throws Exception {
        when(workflow.claim()).thenReturn(task("PIX_RECEBIDO"));
        when(whatsapp.sendText(any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(new ObjectMapper().readTree("{\"status\":\"sent\"}"));

        service.deliverNext();

        var order = inOrder(workflow, whatsapp);
        var saved = ArgumentCaptor.forClass(Delivery.class);
        order.verify(workflow).savePayload(saved.capture());
        order.verify(whatsapp).sendText(any(), any(), any(), any(), any(), any(), any());
        assertEquals("pix-received:92", saved.getValue().reference());
        org.junit.jupiter.api.Assertions.assertTrue(saved.getValue().message().contains("R$ 100,00"));
    }

    private Delivery task(String type) {
        return new Delivery(92, type, 1, "lease", null, null, null, null, null);
    }
}
