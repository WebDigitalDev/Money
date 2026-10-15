package com.webdigital.money2.chat;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

/**
 * Índice semântico usado em todas as mensagens do chat financeiro. O Qdrant
 * identifica intenções e contratos candidatos; PostgreSQL continua sendo a
 * fonte oficial e sempre revalida acesso, valores e histórico.
 */
@Service
public class QdrantFinancialService {

    private static final Logger LOGGER = LoggerFactory.getLogger(QdrantFinancialService.class);

    private static final Map<String, List<String>> INTENT_EXAMPLES = Map.ofEntries(
            Map.entry("CONTRACT_DETAIL", List.of(
                    "dados do contrato", "detalhes do emprestimo", "consultar numero do contrato")),
            Map.entry("CONTRACT_HISTORY", List.of(
                    "historico de alteracoes do contrato", "o que mudou no emprestimo", "movimentacoes do contrato")),
            Map.entry("CONTRACT_CREATED_BY", List.of(
                    "quem criou o emprestimo", "quem cadastrou o contrato", "autor da criacao do contrato")),
            Map.entry("CONTRACT_APPROVAL", List.of(
                    "quem aprovou o contrato", "aprovacao do emprestimo", "status da conferencia")),
            Map.entry("CONTRACT_LAST_PAYMENT", List.of(
                    "quando foi o ultimo pagamento do contrato", "ultimo valor pago", "pagamento mais recente")),
            Map.entry("CONTRACT_NEXT_DUE", List.of(
                    "proximo vencimento do contrato", "quando vence a proxima parcela", "parcela seguinte")),
            Map.entry("CONTRACT_BALANCE", List.of(
                    "saldo devedor do contrato", "quanto falta pagar", "valor em aberto do emprestimo")),
            Map.entry("REGION_PROFIT", List.of(
                    "quanto lucrou a regiao", "lucro financeiro regional", "qual foi o lucro")),
            Map.entry("REGION_GOAL_RECOMMENDATION", List.of(
                    "quanto de meta recomenda para a regiao", "sugestao de meta financeira", "recomendar meta regional")),
            Map.entry("REGION_SUMMARY", List.of(
                    "resumo financeiro da regiao", "quanto emprestou e recebeu", "desempenho financeiro regional")),
            Map.entry("REGION_RANKING", List.of(
                    "qual regiao lucrou mais", "ranking financeiro das regioes", "compare o desempenho das regioes")),
            Map.entry("REGION_DELINQUENCY", List.of(
                    "taxa de inadimplencia da regiao", "percentual em atraso", "risco da carteira regional")),
            Map.entry("REGION_MARGIN", List.of(
                    "margem de lucro da regiao", "rentabilidade regional", "percentual de lucro")),
            Map.entry("REGION_AVERAGE_TICKET", List.of(
                    "ticket medio dos emprestimos", "valor medio por contrato", "media emprestada por contrato")),
            Map.entry("CLIENT_SEARCH", List.of(
                    "consultar cliente", "buscar cliente pelo nome", "pesquisar cpf do cliente")));

    private final RestClient client;
    private final TextVectorizer vectorizer;
    private final String collection;
    private final boolean enabled;

    public QdrantFinancialService(
            RestClient.Builder builder,
            TextVectorizer vectorizer,
            @Value("${money.qdrant.url:http://127.0.0.1:6333}") String url,
            @Value("${money.qdrant.api-key:}") String apiKey,
            @Value("${money.qdrant.financial-collection:money2_financial_context}") String collection,
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

    public boolean synchronizeIntents() {
        if (!enabled || !ensureCollection()) return false;
        List<Map<String, Object>> points = new ArrayList<>();
        for (Map.Entry<String, List<String>> entry : INTENT_EXAMPLES.entrySet()) {
            for (int index = 0; index < entry.getValue().size(); index++) {
                String key = entry.getKey() + ":" + index;
                points.add(Map.of(
                        "id", stableId("intent:" + key),
                        "vector", vectorizer.vectorize(entry.getValue().get(index)),
                        "payload", Map.of(
                                "kind", "INTENT",
                                "intent", entry.getKey())));
            }
        }
        return upsertPoints(points, "intenções financeiras");
    }

    public boolean upsertContracts(List<IndexedFinancialContract> contracts) {
        if (!enabled || contracts == null || contracts.isEmpty() || !ensureCollection()) return false;
        List<Map<String, Object>> points = new ArrayList<>(contracts.size());
        for (IndexedFinancialContract contract : contracts) {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("kind", "CONTRACT");
            payload.put("loanId", contract.id());
            payload.put("regionId", contract.regionId());
            points.add(Map.of(
                    "id", stableId("contract:" + contract.id()),
                    "vector", vectorizer.vectorize(contract.searchableText()),
                    "payload", payload));
        }
        return upsertPoints(points, "contratos");
    }

    @SuppressWarnings("unchecked")
    public FinancialSemanticContext context(String query, List<Long> regionIds, int limit) {
        if (!enabled || query == null || query.isBlank()) return FinancialSemanticContext.empty();
        if (!ensureCollection()) return FinancialSemanticContext.empty();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("query", vectorizer.vectorize(query));
        body.put("limit", Math.max(4, Math.min(limit, 20)));
        body.put("with_payload", true);
        body.put("score_threshold", 0.08);
        List<Map<String, Object>> access = new ArrayList<>();
        access.add(Map.of("key", "kind", "match", Map.of("value", "INTENT")));
        if (regionIds != null && !regionIds.isEmpty()) {
            access.add(Map.of("key", "regionId", "match", Map.of("any", regionIds)));
        }
        body.put("filter", Map.of("should", access));
        try {
            Map<String, Object> response = client.post()
                    .uri("/collections/{collection}/points/query", collection)
                    .body(body)
                    .retrieve()
                    .body(Map.class);
            if (response == null || !(response.get("result") instanceof Map<?, ?> result)
                    || !(result.get("points") instanceof List<?> points)) {
                return new FinancialSemanticContext(List.of(), List.of(), true);
            }
            LinkedHashSet<Long> contracts = new LinkedHashSet<>();
            LinkedHashSet<String> intents = new LinkedHashSet<>();
            for (Object rawPoint : points) {
                if (!(rawPoint instanceof Map<?, ?> point)
                        || !(point.get("payload") instanceof Map<?, ?> payload)) continue;
                String kind = String.valueOf(payload.get("kind"));
                if ("INTENT".equals(kind) && payload.get("intent") != null) {
                    intents.add(String.valueOf(payload.get("intent")));
                } else if ("CONTRACT".equals(kind) && payload.get("loanId") instanceof Number loanId) {
                    contracts.add(loanId.longValue());
                }
            }
            return new FinancialSemanticContext(
                    List.copyOf(contracts), List.copyOf(intents), true);
        } catch (RuntimeException exception) {
            LOGGER.warn("Contextualização financeira no Qdrant indisponível: {}", exception.getMessage());
            return FinancialSemanticContext.empty();
        }
    }

    private boolean ensureCollection() {
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
                                    "Qdrant recusou a coleção financeira: " + response.getStatusCode());
                        })
                        .toBodilessEntity();
                createPayloadIndex("kind", "keyword");
                createPayloadIndex("regionId", "integer");
                LOGGER.info("Coleção Qdrant financeira {} criada.", collection);
                return true;
            } catch (RuntimeException exception) {
                LOGGER.warn("Qdrant indisponível ao preparar o contexto financeiro: {}", exception.getMessage());
                return false;
            }
        }
    }

    private boolean upsertPoints(List<Map<String, Object>> points, String label) {
        try {
            client.put()
                    .uri("/collections/{collection}/points?wait=true", collection)
                    .body(Map.of("points", points))
                    .retrieve()
                    .toBodilessEntity();
            return true;
        } catch (RuntimeException exception) {
            LOGGER.warn("Não foi possível indexar {} no Qdrant: {}", label, exception.getMessage());
            return false;
        }
    }

    private void createPayloadIndex(String field, String schema) {
        try {
            client.put()
                    .uri("/collections/{collection}/index?wait=true", collection)
                    .body(Map.of("field_name", field, "field_schema", schema))
                    .retrieve()
                    .toBodilessEntity();
        } catch (RuntimeException exception) {
            LOGGER.debug("Índice {} do contexto financeiro já existe: {}", field, exception.getMessage());
        }
    }

    private static String stableId(String value) {
        return UUID.nameUUIDFromBytes(value.getBytes(StandardCharsets.UTF_8)).toString();
    }
}
