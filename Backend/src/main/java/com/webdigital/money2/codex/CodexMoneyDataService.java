package com.webdigital.money2.codex;

import com.fasterxml.jackson.databind.JsonNode;
import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.chat.ChatClientResponse;
import com.webdigital.money2.chat.ChatContractResponse;
import com.webdigital.money2.chat.ChatFinancialSummaryResponse;
import com.webdigital.money2.chat.ChatLoanStatusResponse;
import com.webdigital.money2.chat.ChatRepository;
import com.webdigital.money2.chat.ChatResponse;
import com.webdigital.money2.chat.ChatService;
import com.webdigital.money2.chat.FinancialSemanticContext;
import com.webdigital.money2.chat.QdrantFinancialService;
import com.webdigital.money2.chat.QdrantService;
import com.webdigital.money2.goals.FinancialGoalResponse;
import com.webdigital.money2.loans.LoanDetailResponse;
import com.webdigital.money2.loans.LoanDetailService;
import com.webdigital.money2.regions.RegionListResponse;
import com.webdigital.money2.regions.RegionManagementService;
import com.webdigital.money2.regions.RegionSummaryResponse;
import com.webdigital.money2.routes.CollectionRoutePageResponse;
import com.webdigital.money2.routes.CollectionRouteService;
import com.webdigital.money2.shared.ApiException;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

/**
 * Camada de leitura usada exclusivamente pelo Codex. O modelo escolhe a fonte
 * e pode executar várias consultas no mesmo turno; nenhuma operação de escrita
 * ou SQL arbitrário é exposta. Qdrant localiza entidades e intenções, enquanto
 * PostgreSQL revalida permissão e devolve os valores atuais.
 */
@Service
public class CodexMoneyDataService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");

    private final ChatRepository chatRepository;
    private final CodexMoneyRepository codexRepository;
    private final QdrantService clientQdrant;
    private final QdrantFinancialService financialQdrant;
    private final LoanDetailService loanDetailService;
    private final ChatService chatService;
    private final CollectionRouteService routeService;
    private final RegionManagementService regionService;

    public CodexMoneyDataService(
            ChatRepository chatRepository,
            CodexMoneyRepository codexRepository,
            QdrantService clientQdrant,
            QdrantFinancialService financialQdrant,
            LoanDetailService loanDetailService,
            ChatService chatService,
            CollectionRouteService routeService,
            RegionManagementService regionService) {
        this.chatRepository = chatRepository;
        this.codexRepository = codexRepository;
        this.clientQdrant = clientQdrant;
        this.financialQdrant = financialQdrant;
        this.loanDetailService = loanDetailService;
        this.chatService = chatService;
        this.routeService = routeService;
        this.regionService = regionService;
    }

    public CodexMoneyToolResult query(UserAccount user, JsonNode arguments) {
        String source = requiredText(arguments, "fonte").toUpperCase(Locale.ROOT);
        String question = text(arguments, "pergunta");
        String search = firstText(arguments, "termo", "pergunta");
        List<Long> regionScope = accessibleRegionScope(user, longList(arguments, "regiaoIds"));
        LocalDate startDate = date(arguments, "dataInicio");
        LocalDate endDate = date(arguments, "dataFim");
        if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "A data inicial da consulta não pode ser posterior à data final.");
        }
        int limit = integer(arguments, "limite", 20, 1, 100);

        return switch (source) {
            case "CONTEXTO" -> context(user, question == null ? search : question, limit);
            case "REGIOES" -> regionList(user, regionScope);
            case "RESUMO_REGIOES" -> regionSummaries(
                    user, regionScope, startDate, endDate);
            case "CLIENTES" -> clients(
                    user, nullableLong(arguments, "clienteId"), search, limit);
            case "CONTRATO" -> contract(user, requiredLong(arguments, "contratoId"));
            case "CARTEIRA" -> portfolio(
                    user, regionScope, text(arguments, "status"), limit);
            case "PAGAMENTOS" -> payments(
                    user, regionScope, startDate, endDate, search, limit);
            case "METAS" -> goals(user, regionScope);
            case "ROTAS" -> routes(
                    user, regionScope, search, text(arguments, "ordenacao"), limit);
            default -> throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "Fonte de dados não reconhecida pelo assistente.");
        };
    }

    private CodexMoneyToolResult context(UserAccount user, String question, int limit) {
        String query = clean(question);
        if (query.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe a pergunta para contextualizar.");
        }
        List<Long> regionIds = chatRepository.accessibleRegionIds(user.getId());
        FinancialSemanticContext financial = financialQdrant.context(query, regionIds, limit);
        List<Long> clientIds = clientQdrant.search(query, regionIds, limit);
        List<ChatClientResponse> clients = clientIds.isEmpty()
                ? chatRepository.searchClients(user.getId(), query, limit)
                : chatRepository.clientsByIds(user.getId(), clientIds, limit);
        boolean qdrantUsed = financial.qdrantUsed() || !clientIds.isEmpty();

        Map<String, Object> data = base("CONTEXTO");
        data.put("qdrantUsado", qdrantUsed);
        data.put("intencoesProvaveis", financial.intents());
        data.put("contratosCandidatos", financial.contractIds());
        data.put("clientesCandidatos", clients);
        data.put("regioesDisponiveis", chatRepository.accessibleRegions(user.getId()));
        data.put("orientacao",
                "Use os identificadores encontrados para consultar outras fontes nesta mesma resposta."
                        + " regioesDisponiveis já é a lista completa de regiões permitidas e pode"
                        + " responder diretamente perguntas de nomes, quantidade ou existência."
                        + " Não peça ao usuário para escolher se a pergunta já define o escopo.");

        // CONTEXTO serve apenas para descoberta interna. Os candidatos não
        // devem virar cards antes de o modelo confirmar a fonte CLIENTES.
        return new CodexMoneyToolResult(data, null);
    }

    private CodexMoneyToolResult regionList(
            UserAccount user,
            List<Long> regionIds) {
        Set<Long> filter = new LinkedHashSet<>(regionIds);
        List<?> regions = chatRepository.accessibleRegions(user.getId()).stream()
                .filter(region -> filter.isEmpty() || filter.contains(region.id()))
                .toList();
        Map<String, Object> data = base("REGIOES");
        data.put("quantidade", regions.size());
        data.put("regioes", regions);
        data.put("orientacao", "Esta fonte lista regiões sem calcular indicadores financeiros.");
        return new CodexMoneyToolResult(data, null);
    }

    private CodexMoneyToolResult regionSummaries(
            UserAccount user,
            List<Long> regionIds,
            LocalDate startDate,
            LocalDate endDate) {
        String rawRegionIds = regionIds.isEmpty()
                ? null
                : String.join(",", regionIds.stream().map(String::valueOf).toList());
        RegionListResponse regionResponse = regionService.searchForAssistant(
                user, null, startDate, endDate, rawRegionIds);
        List<CodexRegionSummary> summaries = regionResponse.items().stream()
                .map(this::toCodexSummary)
                .toList();
        Map<String, Object> data = base("RESUMO_REGIOES");
        data.put("dataInicio", startDate);
        data.put("dataFim", endDate);
        data.put("regioes", summaries);
        data.put("totais", regionResponse.totals());

        ChatResponse presentation = null;
        if (summaries.size() == 1) {
            CodexRegionSummary item = summaries.get(0);
            ChatFinancialSummaryResponse summary = new ChatFinancialSummaryResponse(
                    item.clients(), item.openLoans(), item.loaned(), item.received(),
                    item.receivable(), item.overdue(), item.profit());
            ChatLoanStatusResponse status = new ChatLoanStatusResponse(
                    item.overdueLoans(), item.overdue(),
                    item.onTimeLoans(), item.receivable().subtract(item.overdue()).max(java.math.BigDecimal.ZERO),
                    item.settledLoans(), java.math.BigDecimal.ZERO.setScale(2));
            List<FinancialGoalResponse> goals = chatRepository.activeFinancialGoals(
                    user.getId(), item.regionId());
            presentation = new ChatResponse(
                    "", "READY", List.of(), List.of(), summary, false,
                    List.of(), status, null, null, goals, null);
        }
        return new CodexMoneyToolResult(data, presentation);
    }

    private CodexRegionSummary toCodexSummary(RegionSummaryResponse item) {
        return new CodexRegionSummary(
                item.id(),
                item.description(),
                item.activeClients(),
                item.activeClients(),
                item.overdueClients(),
                item.currentClients(),
                0,
                item.loanedAmount(),
                item.receivedAmount(),
                item.receivableAmount(),
                item.overdueAmount(),
                item.dueTodayAmount(),
                item.profitAmount());
    }

    private CodexMoneyToolResult clients(
            UserAccount user,
            Long clientId,
            String search,
            int limit) {
        List<ChatClientResponse> clients;
        boolean qdrantUsed = false;
        if (clientId != null && clientId > 0) {
            clients = chatRepository.clientsByIds(user.getId(), List.of(clientId), 1);
        } else {
            String query = clean(search);
            if (query.isEmpty()) {
                throw new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "Informe nome, documento, telefone ou código do cliente.");
            }
            List<Long> ids = clientQdrant.search(
                    query, chatRepository.accessibleRegionIds(user.getId()), limit);
            qdrantUsed = !ids.isEmpty();
            clients = ids.isEmpty()
                    ? chatRepository.searchClients(user.getId(), query, limit)
                    : chatRepository.clientsByIds(user.getId(), ids, limit);
        }
        Map<String, Object> data = base("CLIENTES");
        data.put("qdrantUsado", qdrantUsed);
        data.put("clientes", clients);
        return new CodexMoneyToolResult(
                data,
                new ChatResponse("", "READY", List.of(), clients, null, qdrantUsed));
    }

    private CodexMoneyToolResult contract(UserAccount user, long contractId) {
        LoanDetailResponse detail = loanDetailService.get(user, contractId);
        ChatContractResponse card = chatService.contractData(user, contractId);
        Map<String, Object> data = base("CONTRATO");
        data.put("contrato", detail);
        ChatResponse presentation = new ChatResponse(
                "", "CONTRACT_CONTEXT", List.of(), List.of(), null, false,
                List.of(), null, null, null, List.of(), null, card);
        return new CodexMoneyToolResult(data, presentation);
    }

    private CodexMoneyToolResult portfolio(
            UserAccount user,
            List<Long> regionIds,
            String rawStatus,
            int limit) {
        String status = clean(rawStatus).toUpperCase(Locale.ROOT);
        Long regionId = regionIds.size() == 1 ? regionIds.get(0) : null;
        List<ChatClientResponse> clients = switch (status) {
            case "ATRASADO", "ATRASADOS" -> chatRepository.overdue(user.getId(), regionId, limit);
            case "VENCE_HOJE", "HOJE" -> chatRepository.dueToday(user.getId(), regionId, limit);
            default -> throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "Use ATRASADO ou VENCE_HOJE para consultar a carteira.");
        };
        Map<String, Object> data = base("CARTEIRA");
        data.put("status", status);
        data.put("clientes", clients);
        return new CodexMoneyToolResult(
                data,
                new ChatResponse("", "READY", List.of(), clients, null, false));
    }

    private CodexMoneyToolResult payments(
            UserAccount user,
            List<Long> regionIds,
            LocalDate startDate,
            LocalDate endDate,
            String search,
            int limit) {
        List<CodexPaymentData> payments = codexRepository.recentPayments(
                user.getId(), regionIds, startDate, endDate, search, limit);
        Map<String, Object> data = base("PAGAMENTOS");
        data.put("dataInicio", startDate);
        data.put("dataFim", endDate);
        data.put("pagamentos", payments);
        return new CodexMoneyToolResult(data, null);
    }

    private CodexMoneyToolResult goals(UserAccount user, List<Long> regionIds) {
        List<Long> scope = regionIds.isEmpty()
                ? chatRepository.accessibleRegionIds(user.getId()) : regionIds;
        Map<Long, FinancialGoalResponse> unique = new LinkedHashMap<>();
        for (Long regionId : scope) {
            for (FinancialGoalResponse goal : chatRepository.activeFinancialGoals(
                    user.getId(), regionId)) {
                unique.putIfAbsent(goal.id(), goal);
            }
        }
        List<FinancialGoalResponse> goals = List.copyOf(unique.values());
        Map<String, Object> data = base("METAS");
        data.put("metasAtivas", goals);
        ChatResponse presentation = new ChatResponse(
                "", "READY", List.of(), List.of(), null, false,
                List.of(), null, null, null, goals, null);
        return new CodexMoneyToolResult(data, presentation);
    }

    private CodexMoneyToolResult routes(
            UserAccount user,
            List<Long> regionIds,
            String search,
            String ordering,
            int limit) {
        String rawRegions = regionIds.isEmpty()
                ? null : String.join(",", regionIds.stream().map(String::valueOf).toList());
        CollectionRoutePageResponse routes = routeService.search(
                user,
                rawRegions,
                null,
                null,
                null,
                clean(ordering).isEmpty() ? "OVERDUE_DAYS" : ordering,
                clean(search),
                0,
                limit);
        Map<String, Object> data = base("ROTAS");
        data.put("rotas", routes);
        return new CodexMoneyToolResult(data, null);
    }

    private List<Long> accessibleRegionScope(UserAccount user, List<Long> requested) {
        if (requested.isEmpty()) return List.of();
        Set<Long> accessible = new LinkedHashSet<>(
                chatRepository.accessibleRegionIds(user.getId()));
        if (!accessible.containsAll(requested)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Uma ou mais regiões não estão disponíveis.");
        }
        return requested.stream().distinct().toList();
    }

    private Map<String, Object> base(String source) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("fonte", source);
        data.put("somenteLeitura", true);
        data.put("dataAtual", LocalDate.now(BUSINESS_ZONE));
        return data;
    }

    private static String requiredText(JsonNode node, String field) {
        String value = text(node, field);
        if (value == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o campo " + field + ".");
        }
        return value;
    }

    private static String firstText(JsonNode node, String... fields) {
        for (String field : fields) {
            String value = text(node, field);
            if (value != null) return value;
        }
        return null;
    }

    private static String text(JsonNode node, String field) {
        if (node == null || !node.isObject()) return null;
        JsonNode value = node.get(field);
        if (value == null || value.isNull()) return null;
        String clean = value.asText().trim();
        return clean.isEmpty() ? null : clean;
    }

    private static Long nullableLong(JsonNode node, String field) {
        if (node == null || !node.isObject()) return null;
        JsonNode value = node.get(field);
        return value == null || value.isNull() || !value.canConvertToLong()
                ? null : value.longValue();
    }

    private static long requiredLong(JsonNode node, String field) {
        Long value = nullableLong(node, field);
        if (value == null || value <= 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Informe o campo " + field + ".");
        }
        return value;
    }

    private static List<Long> longList(JsonNode node, String field) {
        if (node == null || !node.isObject() || !node.path(field).isArray()) return List.of();
        List<Long> values = new ArrayList<>();
        for (JsonNode item : node.path(field)) {
            if (item.canConvertToLong() && item.longValue() > 0) values.add(item.longValue());
        }
        return values.stream().distinct().toList();
    }

    private static LocalDate date(JsonNode node, String field) {
        String value = text(node, field);
        if (value == null) return null;
        try {
            return LocalDate.parse(value);
        } catch (RuntimeException exception) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "A data " + field + " deve usar o formato AAAA-MM-DD.");
        }
    }

    private static int integer(
            JsonNode node,
            String field,
            int fallback,
            int minimum,
            int maximum) {
        JsonNode value = node == null ? null : node.get(field);
        int parsed = value != null && value.canConvertToInt() ? value.intValue() : fallback;
        return Math.max(minimum, Math.min(parsed, maximum));
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
