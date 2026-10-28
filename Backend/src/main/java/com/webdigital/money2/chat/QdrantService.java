package com.webdigital.money2.chat;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

@Service
public class QdrantService {

    private static final Logger LOGGER = LoggerFactory.getLogger(QdrantService.class);

    private final RestClient client;
    private final TextVectorizer vectorizer;
    private final String collection;
    private final boolean enabled;

    public QdrantService(
            RestClient.Builder builder,
            TextVectorizer vectorizer,
            @Value("${money.qdrant.url:http://127.0.0.1:6333}") String url,
            @Value("${money.qdrant.api-key:}") String apiKey,
            @Value("${money.qdrant.collection:money2_clients}") String collection,
            @Value("${money.qdrant.enabled:false}") boolean enabled) {
        RestClient.Builder configured = builder.baseUrl(url);
        if (apiKey != null && !apiKey.isBlank()) {
            configured = configured.defaultHeader("api-key", apiKey.trim());
        }
        this.client = configured.build();
        this.vectorizer = vectorizer;
        this.collection = collection;
        this.enabled = enabled;
    }

    public boolean isEnabled() {
        return enabled;
    }

    public boolean ensureCollection() {
        if (!enabled) return false;
        try {
            client.get().uri("/collections/{collection}", collection)
                    .retrieve().toBodilessEntity();
            return true;
        } catch (RuntimeException notFound) {
            try {
                client.put().uri("/collections/{collection}", collection)
                        .body(Map.of(
                                "vectors", Map.of(
                                        "size", TextVectorizer.DIMENSIONS,
                                        "distance", "Cosine"),
                                "on_disk_payload", true))
                        .retrieve()
                        .onStatus(HttpStatusCode::isError, (request, response) -> {
                            throw new IllegalStateException(
                                    "Qdrant recusou a criação da coleção: " + response.getStatusCode());
                        })
                        .toBodilessEntity();
                createRegionPayloadIndex();
                LOGGER.info("Coleção Qdrant {} criada.", collection);
                return true;
            } catch (RuntimeException exception) {
                LOGGER.warn("Qdrant indisponível ao preparar a coleção: {}", exception.getMessage());
                return false;
            }
        }
    }

    public boolean upsert(List<IndexedClient> clients) {
        if (!enabled || clients == null || clients.isEmpty()) return false;
        if (!ensureCollection()) return false;
        List<Map<String, Object>> points = new ArrayList<>(clients.size());
        for (IndexedClient item : clients) {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("name", item.name());
            payload.put("legalName", item.legalName());
            payload.put("document", item.document());
            payload.put("phone", item.phone());
            payload.put("regionId", item.regionId());
            payload.put("regionName", item.regionName());
            points.add(Map.of(
                    "id", item.id(),
                    "vector", vectorizer.vectorize(item.searchableText()),
                    "payload", payload));
        }
        try {
            client.put()
                    .uri("/collections/{collection}/points?wait=true", collection)
                    .body(Map.of("points", points))
                    .retrieve()
                    .toBodilessEntity();
            return true;
        } catch (RuntimeException exception) {
            LOGGER.warn("Não foi possível atualizar o índice Qdrant: {}", exception.getMessage());
            return false;
        }
    }

    public void delete(Long clientId) {
        if (!enabled || clientId == null || !ensureCollection()) return;
        try {
            client.post()
                    .uri("/collections/{collection}/points/delete?wait=true", collection)
                    .body(Map.of("points", List.of(clientId)))
                    .retrieve()
                    .toBodilessEntity();
        } catch (RuntimeException exception) {
            LOGGER.warn("Não foi possível remover o cliente {} do Qdrant: {}",
                    clientId, exception.getMessage());
        }
    }

    @SuppressWarnings("unchecked")
    public List<Long> search(String query, List<Long> regionIds, int limit) {
        if (!enabled || query == null || query.isBlank() || regionIds.isEmpty()) return List.of();
        if (!ensureCollection()) return List.of();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("query", vectorizer.vectorize(query));
        body.put("limit", Math.max(1, Math.min(limit, 50)));
        body.put("with_payload", false);
        body.put("score_threshold", 0.08);
        body.put("filter", Map.of(
                "must", List.of(Map.of(
                        "key", "regionId",
                        "match", Map.of("any", regionIds)))));
        try {
            Map<String, Object> response = client.post()
                    .uri("/collections/{collection}/points/query", collection)
                    .body(body)
                    .retrieve()
                    .body(Map.class);
            if (response == null || !(response.get("result") instanceof Map<?, ?> result)) {
                return List.of();
            }
            Object rawPoints = result.get("points");
            if (!(rawPoints instanceof List<?> points)) return List.of();
            List<Long> ids = new ArrayList<>();
            for (Object rawPoint : points) {
                if (rawPoint instanceof Map<?, ?> point && point.get("id") instanceof Number id) {
                    ids.add(id.longValue());
                }
            }
            return List.copyOf(ids);
        } catch (RuntimeException exception) {
            LOGGER.warn("Busca Qdrant indisponível; usando PostgreSQL: {}", exception.getMessage());
            return List.of();
        }
    }

    private void createRegionPayloadIndex() {
        try {
            client.put()
                    .uri("/collections/{collection}/index?wait=true", collection)
                    .body(Map.of("field_name", "regionId", "field_schema", "integer"))
                    .retrieve()
                    .toBodilessEntity();
        } catch (RuntimeException exception) {
            LOGGER.debug("Índice de payload do Qdrant já existe ou não pôde ser criado: {}",
                    exception.getMessage());
        }
    }
}
