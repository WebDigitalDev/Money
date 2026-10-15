package com.webdigital.money2.integrations;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappSecret;
import com.webdigital.money2.shared.ApiException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.HexFormat;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class WebDigitalWhatsappClient {

    public static final String BASE_URL = "https://webdigital.dev/api/v1";
    private static final String PIX_BUTTON_TEXT = "Copiar PIX Copia e Cola";

    private final ObjectMapper mapper;
    private final HttpClient client;

    public WebDigitalWhatsappClient(ObjectMapper mapper) {
        this.mapper = mapper;
        this.client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(12)).build();
    }

    public JsonNode devices(WhatsappSecret configuration) {
        return execute(configuration, "GET", "/whatsapp/devices", null, null);
    }

    public JsonNode deviceStatus(WhatsappSecret configuration, String remoteId) {
        return execute(configuration, "GET", "/whatsapp/devices/" + path(remoteId) + "/status", null, null);
    }

    public JsonNode sendText(
            WhatsappSecret configuration,
            String remoteId,
            String phone,
            String message,
            String event,
            String reference,
            String contactName) {
        ObjectNode body = mapper.createObjectNode();
        body.put("to", normalizePhone(phone));
        body.put("type", "text");
        body.put("body", require(message, "Informe a mensagem do WhatsApp."));
        if (event != null && !event.isBlank()) body.put("event", event.trim());
        if (reference != null && !reference.isBlank()) body.put("external_reference", reference.trim());
        if (contactName != null && !contactName.isBlank()) body.put("contact_name", contactName.trim());
        String key = "money2:" + sha256(remoteId + "|" + clean(reference) + "|" + message);
        JsonNode result = execute(configuration, "POST",
                "/whatsapp/devices/" + path(remoteId) + "/messages", body, key);
        return validateDispatch(result);
    }

    public JsonNode sendPix(
            WhatsappSecret configuration,
            String remoteId,
            String phone,
            String message,
            String pixCode,
            String reference,
            String contactName) {
        ObjectNode body = pixMessageBody(phone, message, pixCode, reference, contactName);
        String key = "money2:" + sha256(remoteId + "|" + clean(reference) + "|" + pixCode);
        JsonNode result = execute(configuration, "POST",
                "/whatsapp/devices/" + path(remoteId) + "/messages", body, key);
        return validateDispatch(result);
    }

    static JsonNode validateDispatch(JsonNode result) {
        if ("sent".equalsIgnoreCase(result.path("status").asText()) || pending(result)) return result;
        throw new ApiException(HttpStatus.BAD_GATEWAY,
                text(result, "error", "A API WhatsApp não aceitou o envio da mensagem."));
    }

    static boolean pending(JsonNode result) {
        return result != null && "processing".equalsIgnoreCase(result.path("status").asText())
                && !result.path("dispatch_id").asText("").isBlank()
                && !result.path("provider_message_id").asText("").isBlank();
    }

    static String logStatus(JsonNode result) {
        return pending(result) ? "AVISO" : "SUCESSO";
    }

    static String pendingNotice(JsonNode result) {
        return pending(result)
                ? "Envio aceito pela API; aguardando confirmação de entrega. Protocolo: "
                    + result.path("dispatch_id").asText()
                : null;
    }

    public JsonNode dispatchStatus(WhatsappSecret configuration, String remoteId, String dispatchId) {
        return execute(configuration, "GET", "/whatsapp/devices/" + path(remoteId)
                + "/messages/" + path(dispatchId), null, null);
    }

    ObjectNode pixMessageBody(
            String phone,
            String message,
            String pixCode,
            String reference,
            String contactName) {
        ObjectNode body = mapper.createObjectNode();
        body.put("to", normalizePhone(phone));
        body.put("type", "pix");
        body.put("body", require(message, "Informe a mensagem do PIX."));
        body.put("pix_code", require(pixCode, "Código PIX não informado."));
        body.put("button_text", PIX_BUTTON_TEXT);
        body.put("event", "money.pix.charge");
        if (reference != null && !reference.isBlank()) body.put("external_reference", reference.trim());
        if (contactName != null && !contactName.isBlank()) body.put("contact_name", contactName.trim());
        return body;
    }

    private JsonNode execute(
            WhatsappSecret configuration,
            String method,
            String path,
            JsonNode body,
            String idempotencyKey) {
        String token = require(configuration == null ? null : configuration.token(),
                "Configure o token da API WebDigital.");
        String baseUrl = configuration == null ? BASE_URL : clean(configuration.baseUrl());
        if (baseUrl.isBlank()) baseUrl = BASE_URL;
        while (baseUrl.endsWith("/")) baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        if (!baseUrl.startsWith("https://")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "A URL da API WebDigital deve usar HTTPS.");
        }
        try {
            HttpRequest.Builder builder = HttpRequest.newBuilder()
                    .uri(URI.create(baseUrl + path))
                    .timeout(Duration.ofSeconds("GET".equals(method) && path.contains("/messages/") ? 8 : 75))
                    .header("Accept", "application/json")
                    .header("Authorization", "Bearer " + token);
            if (idempotencyKey != null) builder.header("Idempotency-Key", idempotencyKey);
            if ("POST".equals(method)) {
                builder.header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(body), StandardCharsets.UTF_8));
            } else {
                builder.GET();
            }
            HttpResponse<String> response = client.send(
                    builder.build(), HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            JsonNode json = response.body() == null || response.body().isBlank()
                    ? mapper.createObjectNode() : mapper.readTree(response.body());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                HttpStatus status = switch (response.statusCode()) {
                    case 401, 403 -> HttpStatus.UNAUTHORIZED;
                    case 404 -> HttpStatus.NOT_FOUND;
                    case 409 -> HttpStatus.CONFLICT;
                    case 422, 429 -> HttpStatus.BAD_REQUEST;
                    default -> HttpStatus.BAD_GATEWAY;
                };
                throw new ApiException(status, text(json, "message",
                        text(json, "error", "Falha na API WebDigital (HTTP " + response.statusCode() + ").")));
            }
            return json;
        } catch (ApiException exception) {
            throw exception;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new ApiException(HttpStatus.BAD_GATEWAY, "Comunicação com a API WebDigital interrompida.");
        } catch (Exception exception) {
            throw new ApiException(HttpStatus.BAD_GATEWAY,
                    "Falha ao comunicar com a API WebDigital: " + summarize(exception.getMessage()));
        }
    }

    private String normalizePhone(String value) {
        String digits = clean(value).replaceAll("\\D", "");
        while (digits.startsWith("0")) digits = digits.substring(1);
        if (digits.length() == 10 || digits.length() == 11) digits = "55" + digits;
        if (digits.length() < 12 || digits.length() > 15) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Telefone inválido para envio pelo WhatsApp.");
        }
        return "+" + digits;
    }

    private String path(String value) {
        String result = require(value, "Identificador do dispositivo não informado.");
        if (!result.matches("[A-Za-z0-9._-]+")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Identificador do dispositivo inválido.");
        }
        return result;
    }

    private String sha256(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception exception) {
            throw new IllegalStateException("Não foi possível gerar a chave de idempotência.", exception);
        }
    }

    private static String require(String value, String message) {
        String result = clean(value);
        if (result.isBlank()) throw new ApiException(HttpStatus.BAD_REQUEST, message);
        return result;
    }

    private static String text(JsonNode node, String field, String fallback) {
        if (node != null && node.hasNonNull(field) && !node.path(field).asText().isBlank()) {
            return summarize(node.path(field).asText());
        }
        return fallback;
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static String summarize(String value) {
        String result = clean(value);
        if (result.isBlank()) return "erro de comunicação";
        return result.length() > 300 ? result.substring(0, 297) + "..." : result;
    }
}
