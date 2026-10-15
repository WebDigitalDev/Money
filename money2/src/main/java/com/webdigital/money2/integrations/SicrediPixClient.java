package com.webdigital.money2.integrations;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.webdigital.money2.shared.ApiException;
import java.math.BigDecimal;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.Base64;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class SicrediPixClient {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");
    private static final long EXPIRATION_SECONDS = 86400L;
    private final ObjectMapper mapper;
    private final SicrediMtlsClientFactory clients;
    private final Map<String, Token> tokens = new ConcurrentHashMap<>();

    public SicrediPixClient(ObjectMapper mapper, SicrediMtlsClientFactory clients) {
        this.mapper = mapper;
        this.clients = clients;
    }

    public PixResult create(PixRepository.BankConfig config, long loanId, Long installmentId,
                            String transactionId, BigDecimal amount) {
        validate(config);
        ObjectNode body = mapper.createObjectNode();
        body.putObject("calendario").put("expiracao", EXPIRATION_SECONDS);
        body.putObject("valor").put("original", amount.setScale(2).toPlainString());
        body.put("chave", config.pixKey());
        body.put("solicitacaoPagador", "Contrato " + loanId
                + (installmentId == null ? "" : " parcela " + installmentId));
        JsonNode response = request(config, "PUT", "/cob/" + transactionId, body);
        return result(response);
    }

    public PixResult consult(PixRepository.BankConfig config, String transactionId) {
        validate(config);
        return result(request(config, "GET", "/cob/" + transactionId, null));
    }

    public PixResult cancel(PixRepository.BankConfig config, String transactionId) {
        validate(config);
        ObjectNode body = mapper.createObjectNode();
        body.put("status", "REMOVIDA_PELO_USUARIO_RECEBEDOR");
        return result(request(config, "PATCH", "/cob/" + transactionId, body));
    }

    private PixResult result(JsonNode response) {
        String rawStatus = find(response, "status");
        String status = normalizeStatus(rawStatus);
        String copy = first(find(response, "pixCopiaECola"), find(response, "pixCopiaCola"),
                find(response, "brcode"), find(response, "copiaCola"), find(response, "emv"));
        String qrCode = first(find(response, "qrcode"), find(response, "qrCode"), find(response, "imagemQrcode"));
        String location = first(find(response, "location"), find(response, "url"), find(response, "loc"));
        LocalDateTime paidAt = parseDate(first(find(response, "horario"), find(response, "dataPagamento")));
        LocalDateTime createdAt = parseDate(find(response, "criacao"));
        long expirationSeconds = parseLong(find(response, "expiracao"), EXPIRATION_SECONDS);
        LocalDateTime expiresAt = createdAt == null ? null : createdAt.plusSeconds(expirationSeconds);
        return new PixResult(status, copy, qrCode, location, paidAt, expiresAt, response.toString());
    }

    private JsonNode request(PixRepository.BankConfig config, String method, String path, JsonNode body) {
        try {
            HttpClient client = clients.create(config);
            String token = token(config, client);
            String baseUrl = trimSlash(config.apiBaseUrl());
            HttpRequest.Builder builder = HttpRequest.newBuilder()
                    .uri(URI.create(baseUrl + "/v3" + path))
                    .timeout(Duration.ofSeconds(30))
                    .header("Accept", "application/json")
                    .header("Authorization", "Bearer " + token)
                    .header("Content-Type", "application/json");
            if ("GET".equals(method)) builder.GET();
            else builder.method(method, HttpRequest.BodyPublishers.ofString(
                    body == null ? "{}" : mapper.writeValueAsString(body), StandardCharsets.UTF_8));
            HttpResponse<String> response = client.send(
                    builder.build(), HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            JsonNode json = response.body() == null || response.body().isBlank()
                    ? mapper.createObjectNode() : mapper.readTree(response.body());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new SicrediException(response.statusCode(), safeMessage(json, response.statusCode()));
            }
            return json;
        } catch (SicrediException exception) {
            throw exception;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new ApiException(HttpStatus.BAD_GATEWAY, "Comunicação com o Sicredi interrompida.");
        } catch (IllegalArgumentException exception) {
            throw new ApiException(HttpStatus.BAD_REQUEST, summarize(exception.getMessage()));
        } catch (Exception exception) {
            throw new ApiException(HttpStatus.BAD_GATEWAY,
                    "Falha ao comunicar com o Sicredi: " + summarize(exception.getMessage()));
        }
    }

    private synchronized String token(PixRepository.BankConfig config, HttpClient client) throws Exception {
        long now = System.currentTimeMillis();
        String cacheKey = config.id() + "|" + config.clientId() + "|" + config.updatedAt();
        Token cached = tokens.get(cacheKey);
        if (cached != null && cached.expiresAt() > now) return cached.value();
        String form = "grant_type=client_credentials&scope="
                + URLEncoder.encode("cob.write cob.read pix.read", StandardCharsets.UTF_8);
        String basic = Base64.getEncoder().encodeToString(
                (config.clientId() + ":" + config.clientSecret()).getBytes(StandardCharsets.UTF_8));
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(config.tokenUrl())).timeout(Duration.ofSeconds(30))
                .header("Accept", "application/json")
                .header("Content-Type", "application/x-www-form-urlencoded")
                .header("Authorization", "Basic " + basic)
                .POST(HttpRequest.BodyPublishers.ofString(form, StandardCharsets.UTF_8)).build();
        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        JsonNode json = response.body() == null || response.body().isBlank()
                ? mapper.createObjectNode() : mapper.readTree(response.body());
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            throw new SicrediException(response.statusCode(), safeMessage(json, response.statusCode()));
        }
        String value = find(json, "access_token");
        if (value == null) throw new ApiException(HttpStatus.BAD_GATEWAY, "O Sicredi não retornou o token de acesso.");
        long expires = json.path("expires_in").asLong(3600L);
        long duration = expires > 86400L ? expires : expires * 1000L;
        tokens.put(cacheKey, new Token(value, now + Math.max(30000L, duration - 60000L)));
        return value;
    }

    private void validate(PixRepository.BankConfig config) {
        if (config == null || blank(config.clientId()) || blank(config.clientSecret()) || blank(config.pixKey())
                || blank(config.tokenUrl()) || blank(config.apiBaseUrl()) || blank(config.certificatePath())
                || blank(config.privateKeyPath())) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "Complete as credenciais e certificados Sicredi da conta bancária.");
        }
    }

    private String normalizeStatus(String value) {
        String status = value == null ? "" : value.toUpperCase();
        if (status.contains("CONCLUID") || status.contains("PAGO") || status.contains("LIQUID")) return "PAGO";
        if (status.contains("REMOVID") || status.contains("CANCEL")) return "CANCELADO";
        return "AGUARDANDO";
    }

    private String find(JsonNode node, String field) {
        if (node == null || node.isNull()) return null;
        if (node.isObject()) {
            JsonNode direct = node.get(field);
            if (direct != null && direct.isValueNode()) {
                String value = direct.asText("").trim();
                if (!value.isEmpty()) return value;
            }
            var fields = node.fields();
            while (fields.hasNext()) {
                String found = find(fields.next().getValue(), field);
                if (found != null) return found;
            }
        } else if (node.isArray()) {
            for (JsonNode child : node) {
                String found = find(child, field);
                if (found != null) return found;
            }
        }
        return null;
    }

    private LocalDateTime parseDate(String value) {
        if (value == null) return null;
        try {
            return OffsetDateTime.parse(value).atZoneSameInstant(BUSINESS_ZONE).toLocalDateTime();
        } catch (Exception ignored) {
            try {
                return LocalDateTime.parse(value);
            } catch (Exception ignoredAgain) {
                return null;
            }
        }
    }

    private long parseLong(String value, long fallback) {
        try {
            long parsed = Long.parseLong(value);
            return parsed > 0 ? parsed : fallback;
        } catch (Exception ignored) {
            return fallback;
        }
    }

    private String safeMessage(JsonNode json, int status) {
        String value = first(find(json, "message"), find(json, "error"), find(json, "detail"));
        return value == null ? "Sicredi retornou HTTP " + status + "." : summarize(value);
    }

    private String first(String... values) {
        for (String value : values) if (!blank(value)) return value.trim();
        return null;
    }

    private String trimSlash(String value) {
        String result = value == null ? "" : value.trim();
        while (result.endsWith("/")) result = result.substring(0, result.length() - 1);
        return result;
    }

    private static boolean blank(String value) { return value == null || value.isBlank(); }
    private static String summarize(String value) {
        String result = value == null || value.isBlank() ? "erro de comunicação" : value.trim();
        return result.length() > 500 ? result.substring(0, 497) + "..." : result;
    }

    record PixResult(String status, String copyAndPaste, String qrCode, String location,
                     LocalDateTime paidAt, LocalDateTime expiresAt, String rawResponse) { }
    private record Token(String value, long expiresAt) { }

    static final class SicrediException extends ApiException {
        private final int remoteStatus;
        SicrediException(int remoteStatus, String message) {
            super(remoteStatus == 404 ? HttpStatus.NOT_FOUND : HttpStatus.BAD_GATEWAY, message);
            this.remoteStatus = remoteStatus;
        }
        int remoteStatus() { return remoteStatus; }
    }
}
