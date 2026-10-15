package com.webdigital.money2.integrations;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;

class WebDigitalWhatsappClientTest {

    @Test
    void acceptedSendWithDelayedDeliveryIsPendingInsteadOfFailed() throws Exception {
        var result = new ObjectMapper().readTree("""
                {"status":"processing","dispatch_id":"test-dispatch","provider_message_id":"EVO-123"}
                """);
        assertThat(WebDigitalWhatsappClient.validateDispatch(result)).isSameAs(result);
        assertThat(WebDigitalWhatsappClient.logStatus(result)).isEqualTo("AVISO");
        assertThat(WebDigitalWhatsappClient.pendingNotice(result)).contains("test-dispatch");
    }

    @Test
    void missingProviderAcceptanceAndRealFailuresAreNotSuccessful() throws Exception {
        var mapper = new ObjectMapper();
        for (String json : new String[]{
                "{\"status\":\"processing\",\"dispatch_id\":\"test-dispatch\"}",
                "{\"status\":\"failed\",\"error\":\"Dispositivo desconectado\"}",
                "{}"}) {
            var result = mapper.readTree(json);
            assertThatThrownBy(() -> WebDigitalWhatsappClient.validateDispatch(result))
                    .isInstanceOf(com.webdigital.money2.shared.ApiException.class);
        }
        var sent = mapper.readTree("{\"status\":\"sent\"}");
        assertThat(WebDigitalWhatsappClient.validateDispatch(sent)).isSameAs(sent);
        assertThat(WebDigitalWhatsappClient.logStatus(sent)).isEqualTo("SUCESSO");
        assertThat(WebDigitalWhatsappClient.pendingNotice(sent)).isNull();
    }

    @Test
    void pixMessageUsesNativeCopyButtonPayload() {
        WebDigitalWhatsappClient client = new WebDigitalWhatsappClient(new ObjectMapper());

        ObjectNode body = client.pixMessageBody(
                "(65) 99999-9999",
                "Segue o PIX para pagamento.",
                "00020101021226890014br.gov.bcb.pix",
                "pix:123",
                "CLIENTE TESTE");

        assertThat(body.path("to").asText()).isEqualTo("+5565999999999");
        assertThat(body.path("type").asText()).isEqualTo("pix");
        assertThat(body.path("pix_code").asText()).startsWith("000201");
        assertThat(body.path("button_text").asText()).isEqualTo("Copiar PIX Copia e Cola");
        assertThat(body.path("event").asText()).isEqualTo("money.pix.charge");
        assertThat(body.path("external_reference").asText()).isEqualTo("pix:123");
    }

    @Test
    void pixMessageNormalizesBrazilianPhoneWithLocalPrefixZero() {
        WebDigitalWhatsappClient client = new WebDigitalWhatsappClient(new ObjectMapper());

        ObjectNode body = client.pixMessageBody(
                "(065) 99999-9999", "PIX", "000201", "pix:456", "CLIENTE");

        assertThat(body.path("to").asText()).isEqualTo("+5565999999999");
    }
}
