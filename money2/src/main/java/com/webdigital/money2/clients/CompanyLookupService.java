package com.webdigital.money2.clients;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.webdigital.money2.shared.ApiException;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class CompanyLookupService {

    private static final Duration CACHE_DURATION = Duration.ofHours(12);
    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(12);

    private final ObjectMapper mapper;
    private final HttpClient client;
    private final String baseUrl;
    private final Map<String, CachedCompany> cache = new ConcurrentHashMap<>();

    public CompanyLookupService(
            ObjectMapper mapper,
            @Value("${money.company-lookup.base-url:https://brasilapi.com.br/api/cnpj/v1}")
            String baseUrl) {
        this.mapper = mapper;
        this.baseUrl = baseUrl.replaceAll("/+$", "");
        this.client = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(5))
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();
    }

    public CompanyLookupResponse lookup(String rawDocument) {
        String document = digits(rawDocument);
        if (!validCnpj(document)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe um CNPJ válido.");
        }
        CachedCompany cached = cache.get(document);
        if (cached != null && cached.expiresAt().isAfter(Instant.now())) {
            return cached.company();
        }

        HttpRequest request = HttpRequest.newBuilder(URI.create(baseUrl + "/" + document))
                .timeout(REQUEST_TIMEOUT)
                .header("Accept", "application/json")
                .header("User-Agent", "Money/2.0 (WebDigital)")
                .GET()
                .build();
        try {
            HttpResponse<String> response = client.send(
                    request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 404) {
                throw new ApiException(HttpStatus.NOT_FOUND, "CNPJ não encontrado.");
            }
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw unavailable();
            }
            CompanyLookupResponse company = map(document, mapper.readTree(response.body()));
            cache.put(document, new CachedCompany(
                    company, Instant.now().plus(CACHE_DURATION)));
            return company;
        } catch (ApiException exception) {
            throw exception;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw unavailable();
        } catch (IOException | IllegalArgumentException exception) {
            throw unavailable();
        }
    }

    private CompanyLookupResponse map(String document, JsonNode root) {
        String legalName = text(root, "razao_social");
        if (legalName == null) {
            throw unavailable();
        }
        String streetType = text(root, "descricao_tipo_de_logradouro");
        String street = text(root, "logradouro");
        String address = street;
        if (street != null && streetType != null
                && !street.toUpperCase().startsWith(streetType.toUpperCase())) {
            address = streetType + " " + street;
        }
        return new CompanyLookupResponse(
                document,
                legalName,
                text(root, "nome_fantasia"),
                stateRegistration(root),
                text(root, "email"),
                digitsOrNull(text(root, "ddd_telefone_1")),
                digitsOrNull(text(root, "ddd_telefone_2")),
                number(root, "cep"),
                number(root, "codigo_municipio_ibge"),
                text(root, "municipio"),
                text(root, "uf"),
                address,
                text(root, "numero"),
                text(root, "complemento"),
                text(root, "bairro"));
    }

    private String stateRegistration(JsonNode root) {
        JsonNode registrations = root.path("inscricoes_estaduais");
        if (!registrations.isArray()) return null;
        for (JsonNode item : registrations) {
            String value = text(item, "inscricao_estadual");
            if (value == null) value = text(item, "numero");
            if (value != null) return value;
        }
        return null;
    }

    private String text(JsonNode node, String field) {
        JsonNode value = node.path(field);
        if (value.isMissingNode() || value.isNull()) return null;
        String result = value.asText().trim();
        return result.isEmpty() ? null : result;
    }

    private Long number(JsonNode node, String field) {
        String value = digits(text(node, field));
        if (value.isEmpty()) return null;
        try {
            return Long.valueOf(value);
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private String digitsOrNull(String value) {
        String result = digits(value);
        return result.isEmpty() ? null : result;
    }

    private String digits(String value) {
        return value == null ? "" : value.replaceAll("\\D", "");
    }

    private boolean validCnpj(String value) {
        if (value.length() != 14 || value.chars().distinct().count() == 1) return false;
        int[] firstWeights = {5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2};
        int[] secondWeights = {6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2};
        return digit(value, 12, firstWeights) == Character.digit(value.charAt(12), 10)
                && digit(value, 13, secondWeights) == Character.digit(value.charAt(13), 10);
    }

    private int digit(String value, int length, int[] weights) {
        int sum = 0;
        for (int index = 0; index < length; index++) {
            sum += Character.digit(value.charAt(index), 10) * weights[index];
        }
        int remainder = sum % 11;
        return remainder < 2 ? 0 : 11 - remainder;
    }

    private ApiException unavailable() {
        return new ApiException(
                HttpStatus.BAD_GATEWAY,
                "A consulta de CNPJ está temporariamente indisponível. Tente novamente.");
    }

    private record CachedCompany(CompanyLookupResponse company, Instant expiresAt) { }
}
