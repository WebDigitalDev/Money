package com.webdigital.money2.chat;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.loans.LoanApprovalResponse;
import com.webdigital.money2.loans.LoanDetailResponse;
import com.webdigital.money2.loans.LoanDetailService;
import com.webdigital.money2.loans.LoanHistoryResponse;
import com.webdigital.money2.loans.LoanInstallmentResponse;
import com.webdigital.money2.shared.ApiException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.NumberFormat;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.stereotype.Service;

@Service
public class ChatService {

    private static final String MODE_READY = "READY";
    private static final String MODE_CLIENT_SEARCH = "CLIENT_SEARCH";
    private static final String MODE_CLIENT_CONTEXT = "CLIENT_CONTEXT";
    private static final String MODE_CONTRACT_CONTEXT = "CONTRACT_CONTEXT";
    private static final String MODE_CONTRACT_HISTORY = "CONTRACT_HISTORY";
    private static final String MODE_SUMMARY_REGION = "SUMMARY_REGION";
    private static final String MODE_SUMMARY_PERIOD = "SUMMARY_PERIOD";
    private static final String MODE_SUMMARY_MONTH = "SUMMARY_MONTH";
    private static final String MODE_DUE_TODAY_REGION = "DUE_TODAY_REGION";
    private static final String MODE_OVERDUE_REGION = "OVERDUE_REGION";
    private static final String ACTION_EXPORT_EXCEL = "EXPORT_EXCEL";
    private static final String ACTION_EXPORT_PDF = "EXPORT_PDF";
    private static final String ACTION_SELECT_MONTH = "SELECT_MONTH";
    private static final int CLIENT_RESULT_LIMIT = 50;
    private static final int CLIENT_OVERFLOW_FETCH_LIMIT = CLIENT_RESULT_LIMIT + 1;
    private static final Locale BRAZIL = Locale.forLanguageTag("pt-BR");
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");
    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("dd/MM/yyyy");
    private static final DateTimeFormatter DATE_TIME = DateTimeFormatter.ofPattern("dd/MM/yyyy 'às' HH:mm");
    private static final Pattern CONTRACT_WITH_LABEL = Pattern.compile(
            "(?:contrato|emprestimo|emprestimo numero|contrato numero|numero do contrato|numero do emprestimo)\\s*(?:n|numero)?\\s*(\\d{1,19})");
    private static final Pattern ONLY_NUMBER = Pattern.compile("^\\d{1,19}$");

    private final ChatRepository repository;
    private final QdrantService qdrant;
    private final QdrantFinancialService financialQdrant;
    private final TextVectorizer vectorizer;
    private final ChatConversationStore conversations;
    private final LoanDetailService loanDetailService;

    public ChatService(
            ChatRepository repository,
            QdrantService qdrant,
            QdrantFinancialService financialQdrant,
            TextVectorizer vectorizer,
            ChatConversationStore conversations,
            LoanDetailService loanDetailService) {
        this.repository = repository;
        this.qdrant = qdrant;
        this.financialQdrant = financialQdrant;
        this.vectorizer = vectorizer;
        this.conversations = conversations;
        this.loanDetailService = loanDetailService;
    }

    public ChatResponse answer(UserAccount user, ChatRequest request) {
        String conversationId = request.conversationId();
        String normalized = vectorizer.normalize(request.message());
        ChatConversationContext context = conversations.get(user.getId(), conversationId);
        FinancialSemanticContext semantic = financialQdrant.context(
                normalized, repository.accessibleRegionIds(user.getId()), 12);

        if (request.clientId() != null) {
            conversations.selectClient(user.getId(), conversationId, request.clientId());
            return clientDetail(user, request.clientId(), normalized);
        }
        if (request.regionId() != null) {
            conversations.selectRegion(user.getId(), conversationId, request.regionId(), request.mode());
            return regionalQuery(user, request.mode(), request.regionId(), normalized);
        }
        if (normalized.isBlank()) return help(context);

        if (isOtherSubject(normalized)) {
            conversations.clear(user.getId(), conversationId);
            return readyResponse(
                    "Certo. Sobre o que você quer falar agora?",
                    mainSuggestions(),
                    MODE_READY);
        }
        if (MODE_SUMMARY_PERIOD.equalsIgnoreCase(request.mode())) {
            return summaryPeriod(user, context, normalized);
        }
        if (MODE_SUMMARY_MONTH.equalsIgnoreCase(request.mode())) {
            return summaryMonth(user, context, normalized);
        }
        if (isRegionSelectionMode(request.mode())) {
            return regionalQueryByName(user, request.mode(), normalized, conversationId);
        }
        if (isGreeting(normalized)) return greeting(user, context, normalized);
        if (isThanks(normalized)) {
            boolean hasContract = context.loanId() != null;
            return readyResponse(
                    choose(normalized,
                            "Por nada! Se quiser, continuo daqui.",
                            "Disponha! Pode mandar a próxima dúvida.",
                            "Imagina! Estou por aqui para conferir o que precisar."),
                    hasContract ? contractSuggestions()
                            : context.clientId() == null ? mainSuggestions() : clientSuggestions(),
                    hasContract ? MODE_CONTRACT_CONTEXT
                            : context.clientId() == null ? MODE_READY : MODE_CLIENT_CONTEXT);
        }
        if (isClientSearchCommand(normalized)) {
            conversations.clearClient(user.getId(), conversationId);
            conversations.clearContract(user.getId(), conversationId);
            return new ChatResponse(
                    choose(normalized,
                            "Claro. Qual cliente você quer consultar?",
                            "Vamos lá — qual é o cliente?",
                            "Certo! Digite o nome, CPF/CNPJ, telefone ou código do cliente."),
                    MODE_CLIENT_SEARCH,
                    otherSubjectSuggestion(),
                    List.of(),
                    null,
                    false);
        }

        // A busca por cliente só existe dentro do fluxo aberto explicitamente
        // pelo botão "Consultar cliente". Nenhuma mensagem geral cai aqui.
        if (MODE_CLIENT_SEARCH.equalsIgnoreCase(request.mode())) {
            return searchClients(user, cleanedClientQuery(normalized, request.mode()), conversationId);
        }

        Long requestedLoanId = extractContractId(normalized);
        if (requestedLoanId != null) {
            return contractQuery(
                    user, requestedLoanId, normalized, conversationId, semantic);
        }

        boolean namesAccessibleRegion = isRegionalFinancialQuestion(normalized)
                && findRegion(user, normalized) != null;
        if (context.loanId() != null && isContractScopedIntent(normalized)
                && !namesAccessibleRegion && !isRegionalRanking(normalized)) {
            return contractQuery(
                    user, context.loanId(), normalized, conversationId, semantic);
        }

        ChatResponse directRegional = directRegionalFinancialQuery(user, normalized, semantic);
        if (directRegional != null) return directRegional;

        // Uma solicitação explicitamente coletiva troca o foco do cliente
        // atual por uma consulta regional.
        if (isCollectiveIntent(normalized)) return regionalIntent(user, normalized);
        if (context.loanId() != null) {
            return contractQuery(
                    user, context.loanId(), normalized, conversationId, semantic);
        }
        if (MODE_CONTRACT_CONTEXT.equalsIgnoreCase(request.mode())) {
            return readyResponse(
                    "Perdi apenas a referência do contrato. Digite novamente o número para eu continuar.",
                    mainSuggestions(), MODE_READY);
        }
        if (context.clientId() != null) {
            return clientFollowUp(user, context, normalized, conversationId);
        }
        if (MODE_CLIENT_CONTEXT.equalsIgnoreCase(request.mode())) {
            return new ChatResponse(
                    "Perdi apenas a referência do cliente desta conversa. Pesquise e selecione o cliente novamente para eu continuar.",
                    MODE_CLIENT_SEARCH,
                    List.of(),
                    List.of(),
                    null,
                    false);
        }
        if (isDueToday(normalized) || isOverdue(normalized) || isSummary(normalized)) {
            return regionalIntent(user, normalized);
        }
        return broadFinancialHelp(normalized, semantic);
    }

    private ChatResponse greeting(
            UserAccount user,
            ChatConversationContext context,
            String source) {
        String firstName = clean(user.getFirstName());
        String name = firstName.isBlank() ? "" : ", " + firstName;
        if (context.loanId() != null) {
            return readyResponse(
                    "Olá" + name + "! Continuo com o contrato #" + context.loanId()
                            + " em foco. O que você quer conferir?",
                    contractSuggestions(), MODE_CONTRACT_CONTEXT);
        }
        if (context.clientId() != null) {
            ChatClientResponse client = findClient(user, context.clientId());
            if (client != null) {
                return readyResponse(
                        choose(source,
                                "Oi" + name + "! Continuo com os dados de " + client.name() + " por aqui. O que você quer saber?",
                                "Olá" + name + "! Ainda estou acompanhando " + client.name() + ". Pode perguntar.",
                                "Tudo certo" + name + "? O cliente em foco é " + client.name() + "."),
                        clientSuggestions(),
                        MODE_CLIENT_CONTEXT);
            }
        }
        return readyResponse(
                choose(source,
                        "Oi" + name + "! O que vamos conferir nas finanças hoje?",
                        "Olá" + name + "! Digite um contrato ou faça uma pergunta financeira do seu jeito.",
                        "Tudo certo" + name + "? Posso conferir contratos, histórico, pagamentos, vencimentos, lucros e metas."),
                mainSuggestions(),
                MODE_READY);
    }

    private ChatResponse regionalIntent(UserAccount user, String normalized) {
        if (isDueToday(normalized)) {
            return regionPrompt(user, MODE_DUE_TODAY_REGION,
                    "Certo. De qual região você quer ver os vencimentos de hoje?");
        }
        if (isOverdue(normalized)) {
            return regionPrompt(user, MODE_OVERDUE_REGION,
                    "Vamos conferir. De qual região você quer ver os empréstimos atrasados?");
        }
        return regionPrompt(user, MODE_SUMMARY_REGION,
                "Claro. Qual região você quer analisar no resumo financeiro?");
    }

    private ChatResponse contractQuery(
            UserAccount user,
            long loanId,
            String normalized,
            String conversationId,
            FinancialSemanticContext semantic) {
        LoanDetailResponse loan;
        try {
            loan = loanDetailService.get(user, loanId);
        } catch (ApiException exception) {
            conversations.clearContract(user.getId(), conversationId);
            return new ChatResponse(
                    "Não encontrei o contrato #" + loanId
                            + " nas regiões permitidas para você. O número está correto?",
                    MODE_READY,
                    List.of(
                            new ChatSuggestionResponse(
                                    "Tentar outro contrato", "Digite o número do contrato", null),
                            new ChatSuggestionResponse(
                                    "Consultar cliente", "Consultar cliente", null),
                            otherSubject()),
                    List.of(), null, semantic.qdrantUsed());
        }

        conversations.selectContract(user.getId(), conversationId, loan.id(), loan.regionId());
        ChatContractResponse contract = contractResponse(user, loan);

        if (isContractCreatedBy(normalized)
                || semantic.suggests("CONTRACT_CREATED_BY") && containsAny(normalized, "quem", "criou", "cadastrou")) {
            conversations.rememberIntent(user.getId(), conversationId, "CONTRACT_CREATED_BY");
            String message = contract.createdBy() == null
                    ? "O histórico do contrato #" + loan.id()
                            + " não informa com segurança quem realizou a criação."
                    : "O contrato #" + loan.id() + " foi criado por " + contract.createdBy()
                            + formatOccurredAt(contract.createdAt()) + ".";
            if (isContractHistory(normalized) && !contract.history().isEmpty()) {
                message += " Também organizei o histórico completo abaixo.";
            }
            return isContractHistory(normalized)
                    ? contractHistoryAnswer(message, contract, semantic.qdrantUsed())
                    : contractAnswer(message, contract, semantic.qdrantUsed());
        }
        if (isContractApproval(normalized)
                || semantic.suggests("CONTRACT_APPROVAL") && containsAny(normalized, "aprov", "conferencia")) {
            conversations.rememberIntent(user.getId(), conversationId, "CONTRACT_APPROVAL");
            String message;
            if (contract.approvedBy() != null) {
                message = "A aprovação mais recente do contrato #" + loan.id() + " foi feita por "
                        + contract.approvedBy() + formatOccurredAt(contract.approvedAt()) + ".";
            } else if ("PENDENTE".equalsIgnoreCase(contract.approvalStatus())) {
                message = "O contrato #" + loan.id() + " ainda está aguardando aprovação.";
            } else {
                message = "O contrato #" + loan.id() + " está " + contract.approvalStatus().toLowerCase(BRAZIL)
                        + ", mas o histórico disponível não identifica um aprovador.";
            }
            return contractAnswer(message, contract, semantic.qdrantUsed());
        }
        if (isContractHistory(normalized)
                || semantic.suggests("CONTRACT_HISTORY") && containsAny(normalized, "historico", "alter", "mudou")) {
            conversations.rememberIntent(user.getId(), conversationId, "CONTRACT_HISTORY");
            String message = contract.history().isEmpty()
                    ? "Não há alterações registradas no histórico do contrato #" + loan.id() + "."
                    : "Encontrei " + contract.history().size() + " evento(s) no histórico do contrato #"
                            + loan.id() + ". Role a lista abaixo para consultar.";
            return contractHistoryAnswer(message, contract, semantic.qdrantUsed());
        }
        if (isLatestPayment(normalized)
                || semantic.suggests("CONTRACT_LAST_PAYMENT") && containsAny(normalized, "pagamento", "pagou", "pago")) {
            conversations.rememberIntent(user.getId(), conversationId, "CONTRACT_LAST_PAYMENT");
            String message = contract.lastPaymentDate() == null
                    ? "Ainda não há pagamento aprovado registrado no contrato #" + loan.id() + "."
                    : "O último pagamento do contrato #" + loan.id() + " foi em "
                            + DATE.format(contract.lastPaymentDate()) + ", no valor de "
                            + currency(contract.lastPaymentAmount())
                            + installmentSuffix(contract.lastPaymentInstallment()) + ".";
            return contractAnswer(message, contract, semantic.qdrantUsed());
        }
        if (isNextDue(normalized)
                || semantic.suggests("CONTRACT_NEXT_DUE") && containsAny(normalized, "vence", "vencimento", "parcela")) {
            conversations.rememberIntent(user.getId(), conversationId, "CONTRACT_NEXT_DUE");
            String message = contract.nextDueDate() == null
                    ? "O contrato #" + loan.id() + " não possui próxima parcela pendente."
                    : "O próximo vencimento do contrato #" + loan.id() + " é em "
                            + DATE.format(contract.nextDueDate()) + ", com saldo de "
                            + currency(contract.nextDueAmount())
                            + installmentSuffix(contract.nextDueInstallment()) + ".";
            return contractAnswer(message, contract, semantic.qdrantUsed());
        }
        if (isOpenInstallments(normalized) || isDebt(normalized)
                || semantic.suggests("CONTRACT_BALANCE") && containsAny(normalized, "saldo", "deve", "aberto", "falta")) {
            conversations.rememberIntent(user.getId(), conversationId, "CONTRACT_BALANCE");
            String message = contract.receivableAmount().signum() == 0
                    ? "O contrato #" + loan.id() + " não possui saldo em aberto."
                    : "O saldo atual do contrato #" + loan.id() + " é "
                            + currency(contract.receivableAmount()) + ", distribuído em "
                            + contract.openInstallments() + " parcela(s) pendente(s); "
                            + contract.overdueInstallments() + " está(ão) em atraso.";
            return contractAnswer(message, contract, semantic.qdrantUsed());
        }
        if (isRegionQuestion(normalized)) {
            return contractAnswer(
                    "O contrato #" + loan.id() + " pertence à região " + loan.regionName() + ".",
                    contract, semantic.qdrantUsed());
        }
        if (isReceived(normalized)) {
            return contractAnswer(
                    "O contrato #" + loan.id() + " já recebeu "
                            + currency(contract.receivedAmount()) + ".",
                    contract, semantic.qdrantUsed());
        }
        if (isLoaned(normalized)) {
            return contractAnswer(
                    "O valor emprestado no contrato #" + loan.id() + " foi "
                            + currency(contract.loanedAmount()) + ".",
                    contract, semantic.qdrantUsed());
        }
        if (containsAny(normalized, "lucro", "lucrou", "rentabilidade")) {
            return contractAnswer(
                    "O lucro reconhecido até agora no contrato #" + loan.id() + " é "
                            + currency(contract.profitAmount()) + ".",
                    contract, semantic.qdrantUsed());
        }

        conversations.rememberIntent(user.getId(), conversationId, "CONTRACT_DETAIL");
        return contractDetailAnswer(
                "Encontrei o contrato #" + loan.id() + " de " + loan.clientName()
                        + ". Organizei os dados atuais abaixo.",
                contract, semantic.qdrantUsed());
    }

    private ChatResponse contractAnswer(
            String message,
            ChatContractResponse contract,
            boolean semanticSearch) {
        return new ChatResponse(
                message, MODE_CONTRACT_CONTEXT, contractSuggestions(), List.of(), null,
                semanticSearch);
    }

    private ChatResponse contractDetailAnswer(
            String message,
            ChatContractResponse contract,
            boolean semanticSearch) {
        return new ChatResponse(
                message, MODE_CONTRACT_CONTEXT, contractSuggestions(), List.of(), null,
                semanticSearch, List.of(), null, null, null, List.of(), null, contract);
    }

    private ChatResponse contractHistoryAnswer(
            String message,
            ChatContractResponse contract,
            boolean semanticSearch) {
        return new ChatResponse(
                message, MODE_CONTRACT_HISTORY, contractSuggestions(), List.of(), null,
                semanticSearch, List.of(), null, null, null, List.of(), null, contract);
    }

    /**
     * Monta os dados estruturados do contrato sem acionar o fluxo guiado do
     * chat legado. Usado pelas ferramentas de leitura do Codex.
     */
    public ChatContractResponse contractData(UserAccount user, long loanId) {
        return contractResponse(user, loanDetailService.get(user, loanId));
    }

    private ChatContractResponse contractResponse(UserAccount user, LoanDetailResponse loan) {
        List<LoanInstallmentResponse> installments = loan.installments();
        long paidCount = installments.stream().filter(item -> !item.pending()).count();
        long openCount = installments.stream().filter(LoanInstallmentResponse::pending).count();
        long overdueCount = installments.stream()
                .filter(item -> item.pending() && item.overdueDays() > 0).count();

        ChatPaymentSnapshot latestPayment = repository.latestPaymentForLoan(
                user.getId(), loan.id());
        LoanInstallmentResponse nextDue = installments.stream()
                .filter(LoanInstallmentResponse::pending)
                .filter(item -> item.balanceAmount().signum() > 0 && item.dueDate() != null)
                .min(Comparator.comparing(LoanInstallmentResponse::dueDate))
                .orElse(null);

        LoanHistoryResponse creation = loan.history().stream()
                .filter(this::isCreationEvent)
                .min(Comparator.comparing(
                        LoanHistoryResponse::occurredAt,
                        Comparator.nullsLast(Comparator.naturalOrder())))
                .orElse(null);
        LoanApprovalResponse approval = loan.approvals().stream()
                .filter(item -> item.approver() != null && !item.approver().isBlank())
                .filter(item -> "APROVADO".equalsIgnoreCase(item.status()))
                .max(Comparator.comparing(
                        LoanApprovalResponse::decidedAt,
                        Comparator.nullsFirst(Comparator.naturalOrder())))
                .orElse(null);
        LoanHistoryResponse lastChange = loan.history().stream()
                .filter(item -> item.occurredAt() != null)
                .max(Comparator.comparing(LoanHistoryResponse::occurredAt))
                .orElse(null);

        String createdBy = creation == null ? null : nullable(creation.username());
        LocalDateTime createdAt = creation == null ? loan.contractDate() : creation.occurredAt();
        if (createdBy == null) {
            LoanApprovalResponse request = loan.approvals().stream()
                    .filter(item -> item.requester() != null && !item.requester().isBlank())
                    .min(Comparator.comparing(
                            LoanApprovalResponse::createdAt,
                            Comparator.nullsLast(Comparator.naturalOrder())))
                    .orElse(null);
            if (request != null) {
                createdBy = request.requester();
                if (createdAt == null) createdAt = request.createdAt();
            }
        }

        List<ChatContractEventResponse> history = new ArrayList<>();
        history.addAll(loan.history().stream()
                .map(item -> new ChatContractEventResponse(
                        item.category(), item.operation(), item.description(),
                        item.username(), item.occurredAt()))
                .toList());
        history.addAll(loan.approvals().stream()
                .map(item -> new ChatContractEventResponse(
                        "APROVACAO",
                        nullable(item.action()) == null ? item.status() : item.action(),
                        approvalHistoryDescription(item),
                        nullable(item.approver()) == null ? item.requester() : item.approver(),
                        item.decidedAt() == null ? item.createdAt() : item.decidedAt()))
                .toList());
        history.sort(Comparator.comparing(
                ChatContractEventResponse::occurredAt,
                Comparator.nullsLast(Comparator.reverseOrder())));
        return new ChatContractResponse(
                loan.id(), loan.clientId(), loan.clientName(), loan.regionId(), loan.regionName(),
                toDate(loan.contractDate()), loan.paymentType(), loan.installmentCount(),
                paidCount, openCount, overdueCount,
                loan.loanedAmount(), loan.totalAmount(), loan.receivedAmount(),
                loan.receivableAmount(), loan.profitAmount(), loan.status(), loan.approvalStatus(),
                latestPayment == null ? null : toDate(latestPayment.paidAt()),
                latestPayment == null ? null : latestPayment.amount(),
                latestPayment == null ? null : latestPayment.installment(),
                nextDue == null ? null : toDate(nextDue.dueDate()),
                nextDue == null ? null : nextDue.balanceAmount(),
                nextDue == null ? null : nextDue.number(),
                createdBy, createdAt,
                approval == null ? null : approval.approver(),
                approval == null ? null : approval.decidedAt(),
                lastChange == null ? null : nullable(lastChange.username()),
                lastChange == null ? null : lastChange.occurredAt(),
                history);
    }

    private ChatResponse directRegionalFinancialQuery(
            UserAccount user,
            String normalized,
            FinancialSemanticContext semantic) {
        if (!isRegionalFinancialQuestion(normalized)) return null;
        ChatRegionOption region = findRegion(user, normalized);
        if (region == null) {
            if (isRegionalRanking(normalized)) {
                return regionalRanking(user, normalized, semantic.qdrantUsed());
            }
            if (containsAny(normalized, "regiao", "regional", "lucro", "meta")) {
                return regionPrompt(user, MODE_SUMMARY_REGION,
                        "Qual região você quer analisar? Pode escolher uma abaixo.");
            }
            return null;
        }
        if (isGoalRecommendation(normalized)) {
            return regionalGoalRecommendation(user, region, semantic.qdrantUsed());
        }
        return regionalMetric(user, region, normalized, semantic.qdrantUsed());
    }

    private ChatResponse regionalMetric(
            UserAccount user,
            ChatRegionOption region,
            String normalized,
            boolean semanticSearch) {
        DateRange period = containsAny(normalized, "a receber", "recebivel", "saldo", "em atraso", "inadimplencia")
                ? new DateRange(null, null, "no período geral")
                : requestedPeriod(normalized);
        ChatFinancialSummaryResponse summary = repository.summary(
                user.getId(), region.id(), period.start(), period.end());
        String message;
        if (containsAny(normalized, "taxa de inadimplencia", "percentual em atraso")) {
            BigDecimal rate = percentage(summary.overdue(), summary.receivable());
            message = "A taxa de inadimplência de " + region.name() + " é "
                    + percent(rate) + ", com " + currency(summary.overdue())
                    + " vencidos sobre " + currency(summary.receivable()) + " a receber.";
        } else if (containsAny(normalized, "margem de lucro", "margem financeira", "rentabilidade")) {
            BigDecimal margin = percentage(summary.profit(), summary.received());
            message = "A margem sobre os recebimentos de " + region.name() + " "
                    + period.label() + " é " + percent(margin) + ": "
                    + currency(summary.profit()) + " de lucro sobre "
                    + currency(summary.received()) + " recebidos.";
        } else if (containsAny(normalized, "ticket medio", "valor medio por contrato", "media por contrato")) {
            BigDecimal ticket = summary.openLoans() == 0
                    ? BigDecimal.ZERO.setScale(2)
                    : summary.loaned().divide(
                            BigDecimal.valueOf(summary.openLoans()), 2, RoundingMode.HALF_UP);
            message = "O ticket médio de " + region.name() + " " + period.label()
                    + " é " + currency(ticket) + " por contrato em aberto.";
        } else if (containsAny(normalized, "lucro", "lucrou", "lucrado")) {
            message = "O lucro de " + region.name() + " " + period.label() + " foi de "
                    + currency(summary.profit()) + ".";
        } else if (containsAny(normalized, "quanto recebeu", "total recebido", "recebimento")) {
            message = region.name() + " recebeu " + currency(summary.received()) + " " + period.label() + ".";
        } else if (containsAny(normalized, "quanto emprestou", "total emprestado", "emprestado")) {
            message = region.name() + " emprestou " + currency(summary.loaned()) + " " + period.label() + ".";
        } else if (containsAny(normalized, "em atraso", "atrasado", "inadimplencia")) {
            message = region.name() + " possui " + currency(summary.overdue()) + " em atraso no recorte analisado.";
        } else if (containsAny(normalized, "a receber", "recebivel", "saldo")) {
            message = "O valor atual a receber de " + region.name() + " é "
                    + currency(summary.receivable()) + ".";
        } else {
            message = "Aqui está o panorama financeiro de " + region.name() + " " + period.label() + ".";
        }
        return new ChatResponse(
                message, MODE_READY,
                List.of(
                        new ChatSuggestionResponse(
                                "Recomendar meta", "Quanto de meta recomenda para região " + region.name(), null),
                        new ChatSuggestionResponse(
                                "Resumo completo", "Resumo financeiro", null),
                        otherSubject()),
                List.of(), summary, semanticSearch, List.of(), null, null, null, List.of(),
                new ChatSummaryContextResponse(region.id(), region.name(), period.start(), period.end()));
    }

    private ChatResponse regionalRanking(
            UserAccount user,
            String normalized,
            boolean semanticSearch) {
        DateRange period = requestedPeriod(normalized);
        List<ChatRegionProfitSnapshot> performances = repository.profitRanking(
                user.getId(), period.start(), period.end());
        if (performances.isEmpty()) {
            return readyResponse(
                    "Você não possui regiões disponíveis para comparar.", mainSuggestions(), MODE_READY);
        }
        StringBuilder message = new StringBuilder("Ranking de lucro ")
                .append(period.label()).append(":");
        for (int index = 0; index < Math.min(performances.size(), 5); index++) {
            ChatRegionProfitSnapshot item = performances.get(index);
            message.append("\n").append(index + 1).append(". ")
                    .append(item.regionName()).append(" — ")
                    .append(currency(item.profit()));
        }
        return new ChatResponse(
                message.toString(), MODE_READY, mainSuggestions(), List.of(), null, semanticSearch);
    }

    private ChatResponse regionalGoalRecommendation(
            UserAccount user,
            ChatRegionOption region,
            boolean semanticSearch) {
        LocalDate firstCurrentMonth = LocalDate.now(BUSINESS_ZONE).withDayOfMonth(1);
        BigDecimal loaned = BigDecimal.ZERO;
        BigDecimal received = BigDecimal.ZERO;
        BigDecimal profit = BigDecimal.ZERO;
        for (int monthsBack = 1; monthsBack <= 3; monthsBack++) {
            YearMonth month = YearMonth.from(firstCurrentMonth.minusMonths(monthsBack));
            ChatFinancialSummaryResponse summary = repository.summary(
                    user.getId(), region.id(), month.atDay(1), month.atEndOfMonth());
            loaned = loaned.add(summary.loaned());
            received = received.add(summary.received());
            profit = profit.add(summary.profit());
        }
        BigDecimal recommendedLoaned = recommendation(loaned);
        BigDecimal recommendedReceived = recommendation(received);
        BigDecimal recommendedProfit = recommendation(profit);
        String message;
        if (recommendedLoaned.signum() == 0 && recommendedReceived.signum() == 0
                && recommendedProfit.signum() == 0) {
            message = "Ainda não há três meses de movimento suficiente para recomendar uma meta segura para "
                    + region.name() + ".";
        } else {
            message = "Para " + region.name()
                    + ", recomendo metas mensais de " + currency(recommendedLoaned) + " emprestados, "
                    + currency(recommendedReceived) + " recebidos e "
                    + currency(recommendedProfit) + " de lucro. A projeção usa a média dos três meses completos mais recentes com 10% de crescimento.";
        }
        return new ChatResponse(
                message, MODE_READY,
                List.of(
                        new ChatSuggestionResponse(
                                "Lucro da região", "Quanto lucrou a região " + region.name(), null),
                        new ChatSuggestionResponse(
                                "Resumo financeiro", "Resumo financeiro", null),
                        otherSubject()),
                List.of(), null, semanticSearch);
    }

    private ChatResponse broadFinancialHelp(String normalized, FinancialSemanticContext semantic) {
        String message;
        if (semantic.suggests("CONTRACT_DETAIL") || containsAny(normalized, "contrato", "emprestimo")) {
            message = "Consigo consultar esse contrato, mas preciso do número. Digite, por exemplo: “46409” ou “quem criou o contrato 46409?”.";
        } else {
            message = "Não identifiquei um contrato ou indicador financeiro específico. Você pode digitar o número de um contrato, perguntar pelo histórico dele ou consultar lucro, recebimentos e metas de uma região.";
        }
        return readyResponse(message, mainSuggestions(), MODE_READY);
    }

    private ChatResponse searchClients(UserAccount user, String query, String conversationId) {
        if (query.length() < 2) {
            return new ChatResponse(
                    "Me passe pelo menos duas letras do nome para eu localizar o cliente certo.",
                    MODE_CLIENT_SEARCH,
                    List.of(),
                    List.of(),
                    null,
                    false);
        }

        List<ChatClientResponse> exactClients = repository.searchClients(
                user.getId(), query, CLIENT_OVERFLOW_FETCH_LIMIT);

        if (exactClients.size() > CLIENT_RESULT_LIMIT) {
            return new ChatResponse(
                    "Encontrei mais de 50 clientes com “" + query
                            + "”. Informe o nome e o sobrenome para eu retornar o resultado exato.",
                    MODE_CLIENT_SEARCH, List.of(), List.of(), null, false);
        }

        // O PostgreSQL define quais nomes correspondem exatamente ao texto
        // informado. O Qdrant pode ordenar esses mesmos clientes por relevância,
        // mas nunca acrescenta resultados aproximados à lista.
        List<Long> semanticIds = qdrant.search(
                query, repository.accessibleRegionIds(user.getId()), CLIENT_RESULT_LIMIT);
        Map<Long, ChatClientResponse> remaining = new LinkedHashMap<>();
        for (ChatClientResponse client : exactClients) remaining.put(client.id(), client);
        List<ChatClientResponse> clients = new ArrayList<>(exactClients.size());
        for (Long id : semanticIds) {
            ChatClientResponse client = remaining.remove(id);
            if (client != null) clients.add(client);
        }
        boolean usedQdrant = !clients.isEmpty();
        clients.addAll(remaining.values());

        if (clients.isEmpty()) {
            return new ChatResponse(
                    choose(query,
                            "Não achei ninguém com “" + query + "”. Tente mais uma parte do nome, CPF/CNPJ ou telefone.",
                            "Não encontrei esse cliente ainda. Você consegue me passar outro trecho do nome ou o telefone?",
                            "Essa busca não retornou clientes. Confira o nome ou tente pelo CPF/CNPJ."),
                    MODE_CLIENT_SEARCH, List.of(), List.of(), null, usedQdrant);
        }
        if (clients.size() == 1) {
            ChatClientResponse client = clients.get(0);
            conversations.selectClient(user.getId(), conversationId, client.id());
            return detailResponse(user, client, usedQdrant, query);
        }

        List<ChatSuggestionResponse> suggestions = new ArrayList<>();
        for (ChatClientResponse client : clients) {
            suggestions.add(new ChatSuggestionResponse(
                    client.name() + " • " + client.regionName(), client.name(), client.id()));
        }
        return new ChatResponse(
                choose(query,
                        "Encontrei algumas possibilidades. Qual destes clientes é o que você procura?",
                        "Achei mais de um resultado parecido. Selecione o cliente certo para continuarmos.",
                        "Temos alguns nomes correspondentes. Toque em um deles e eu trago os dados atuais."),
                MODE_CLIENT_SEARCH, suggestions, clients, null, usedQdrant);
    }

    private ChatResponse clientDetail(UserAccount user, Long clientId, String source) {
        ChatClientResponse client = findClient(user, clientId);
        if (client == null) {
            return new ChatResponse(
                    "Não consegui abrir esse cliente. Ele pode não existir ou estar fora das suas regiões permitidas.",
                    MODE_READY, mainSuggestions(), List.of(), null, false);
        }
        return detailResponse(user, client, false, source);
    }

    private ChatResponse clientFollowUp(
            UserAccount user,
            ChatConversationContext context,
            String normalized,
            String conversationId) {
        ChatClientResponse client = findClient(user, context.clientId());
        if (client == null) {
            return new ChatResponse(
                    "Não tenho mais acesso ao cliente que estava em foco. Escolha outro cliente para continuarmos.",
                    MODE_CLIENT_SEARCH, List.of(), List.of(), null, false);
        }

        if (isLatestPayment(normalized)
                || isContinuationOf(normalized, context.lastIntent(), "LAST_PAYMENT")) {
            conversations.rememberIntent(user.getId(), conversationId, "LAST_PAYMENT");
            return latestPayment(user, client, normalized);
        }
        if (isNextDue(normalized)
                || isContinuationOf(normalized, context.lastIntent(), "NEXT_DUE")) {
            conversations.rememberIntent(user.getId(), conversationId, "NEXT_DUE");
            return nextDue(user, client, normalized);
        }
        if (isOpenInstallments(normalized)) {
            conversations.rememberIntent(user.getId(), conversationId, "OPEN_INSTALLMENTS");
            return openInstallments(user, client, normalized);
        }
        if (isLoanList(normalized)) {
            conversations.rememberIntent(user.getId(), conversationId, "ACTIVE_LOANS");
            return activeLoans(user, client, normalized);
        }
        if (isContact(normalized)) return contact(client, normalized);
        if (isDocument(normalized)) return document(client, normalized);
        if (isRegionQuestion(normalized)) {
            return clientAnswer(choose(normalized,
                    client.name() + " pertence à região " + client.regionName() + ".",
                    "A região de " + client.name() + " é " + client.regionName() + "."), client);
        }
        if (isDueToday(normalized)) {
            return clientAnswer(client.dueToday().signum() > 0
                    ? client.name() + " tem " + currency(client.dueToday()) + " vencendo hoje."
                    : "Nada vence hoje para " + client.name() + ".", client);
        }
        if (isOverdue(normalized)) {
            return clientAnswer(client.overdue().signum() > 0
                    ? client.name() + " está com " + currency(client.overdue()) + " em atraso."
                    : "Boa notícia: " + client.name() + " não possui valor em atraso agora.", client);
        }
        if (isDebt(normalized)) {
            return clientAnswer(client.receivable().signum() > 0
                    ? choose(normalized,
                            "O saldo atual a receber de " + client.name() + " é " + currency(client.receivable()) + ".",
                            client.name() + " ainda tem " + currency(client.receivable()) + " em aberto.")
                    : client.name() + " não possui saldo em aberto neste momento.", client);
        }
        if (isReceived(normalized)) {
            return clientAnswer(choose(normalized,
                    "Até agora, recebemos " + currency(client.received()) + " de " + client.name() + ".",
                    "O total recebido de " + client.name() + " é " + currency(client.received()) + "."), client);
        }
        if (isLoaned(normalized)) {
            return clientAnswer(choose(normalized,
                    "O total emprestado para " + client.name() + " é " + currency(client.loaned()) + ".",
                    client.name() + " soma " + currency(client.loaned()) + " em valores emprestados."), client);
        }
        if (isSummary(normalized) || isClientSummary(normalized)) {
            return detailResponse(user, client, false, normalized);
        }

        return clientAnswer(choose(normalized,
                "Estou com " + client.name() + " em foco. Posso conferir o último pagamento, saldo, atraso, próximo vencimento ou contratos em aberto.",
                "Entendi que ainda estamos falando de " + client.name() + ". Pergunte, por exemplo: “qual foi o último pagamento?” ou “quando vence a próxima parcela?”.",
                "Continuo acompanhando " + client.name() + ". Me diga se você quer ver pagamentos, dívida, parcelas ou vencimentos."), client);
    }

    private ChatResponse latestPayment(UserAccount user, ChatClientResponse client, String source) {
        ChatPaymentSnapshot payment = repository.latestPayment(user.getId(), client.id());
        if (payment == null || payment.paidAt() == null) {
            return clientAnswer(choose(source,
                    "Ainda não há pagamento aprovado registrado para " + client.name() + ".",
                    "Não encontrei pagamentos confirmados para " + client.name() + " até agora."), client);
        }
        String installment = "-".equals(payment.installment())
                ? "" : ", na " + ordinal(payment.installment()) + " parcela";
        String roll = "JUROS_ROLAGEM".equalsIgnoreCase(payment.type())
                ? " Esse lançamento foi de pagamento somente dos juros." : "";
        return clientAnswer(choose(source,
                "O último pagamento de " + client.name() + " foi em " + DATE.format(payment.paidAt())
                        + ", no valor de " + currency(payment.amount()) + installment
                        + " do contrato #" + payment.loanId() + "." + roll,
                "Encontrei: " + client.name() + " pagou " + currency(payment.amount())
                        + " em " + DATE.format(payment.paidAt()) + installment
                        + " do contrato #" + payment.loanId() + "." + roll), client);
    }

    private ChatResponse nextDue(UserAccount user, ChatClientResponse client, String source) {
        ChatInstallmentSnapshot installment = repository.nextDue(user.getId(), client.id());
        if (installment == null || installment.dueAt() == null) {
            return clientAnswer(choose(source,
                    client.name() + " não possui parcela pendente com próximo vencimento.",
                    "Não encontrei vencimentos pendentes para " + client.name() + "."), client);
        }
        return clientAnswer(choose(source,
                "O próximo vencimento de " + client.name() + " é em " + DATE.format(installment.dueAt())
                        + ": " + ordinal(installment.installment()) + " parcela do contrato #"
                        + installment.loanId() + ", com saldo de " + currency(installment.balance()) + ".",
                "A próxima parcela vence em " + DATE.format(installment.dueAt()) + " e tem "
                        + currency(installment.balance()) + " em aberto no contrato #"
                        + installment.loanId() + "."), client);
    }

    private ChatResponse openInstallments(UserAccount user, ChatClientResponse client, String source) {
        long count = repository.openInstallmentCount(user.getId(), client.id());
        String answer = count == 0
                ? client.name() + " não possui parcelas pendentes."
                : choose(source,
                        client.name() + " possui " + count + " parcela(s) pendente(s), somando "
                                + currency(client.receivable()) + " a receber.",
                        "Há " + count + " parcela(s) em aberto para " + client.name()
                                + ". O saldo total é " + currency(client.receivable()) + ".");
        return clientAnswer(answer, client);
    }

    private ChatResponse activeLoans(UserAccount user, ChatClientResponse client, String source) {
        List<ChatLoanResponse> loans = repository.activeLoanResults(user.getId(), client.id(), 100);
        if (loans.isEmpty()) return clientAnswer(client.name() + " não possui contratos ativos no momento.", client);
        String message = choose(source,
                "Estes são os contratos ativos de " + client.name() + ":",
                client.name() + " tem " + loans.size() + " contrato(s) em aberto. Toque em um para ver os detalhes.");
        return clientLoansAnswer(message, loans);
    }

    private ChatResponse contact(ChatClientResponse client, String source) {
        String answer = client.phone() == null
                ? "Não há telefone cadastrado para " + client.name() + "."
                : choose(source,
                        "O telefone/WhatsApp de " + client.name() + " é " + client.phone() + ".",
                        "Você pode falar com " + client.name() + " pelo número " + client.phone() + ".");
        return clientAnswer(answer, client);
    }

    private ChatResponse document(ChatClientResponse client, String source) {
        String answer = client.document() == null
                ? "Não há CPF/CNPJ informado para " + client.name() + "."
                : choose(source,
                        "O CPF/CNPJ de " + client.name() + " é " + client.document() + ".",
                        "Documento cadastrado para " + client.name() + ": " + client.document() + ".");
        return clientAnswer(answer, client);
    }

    private ChatResponse clientAnswer(String message, ChatClientResponse client) {
        return new ChatResponse(message, MODE_CLIENT_CONTEXT, clientSuggestions(),
                List.of(), null, false);
    }

    private ChatResponse clientLoansAnswer(String message, List<ChatLoanResponse> loans) {
        return new ChatResponse(
                message, MODE_CLIENT_CONTEXT, clientSuggestions(), List.of(), null,
                false, loans, null, null, null, List.of(), null);
    }

    private ChatResponse clientAnswerWithLoans(
            String message,
            ChatClientResponse client,
            List<ChatLoanResponse> loans,
            boolean semanticSearch) {
        return new ChatResponse(
                message, MODE_CLIENT_CONTEXT, clientSuggestions(), List.of(client), null,
                semanticSearch, loans, null, null, null, List.of(), null);
    }

    private ChatResponse regionPrompt(UserAccount user, String mode, String question) {
        List<ChatRegionOption> regions = repository.accessibleRegions(user.getId());
        if (regions.isEmpty()) return readyResponse(
                "Você não possui nenhuma região disponível para consultar.", mainSuggestions(), MODE_READY);
        List<ChatSuggestionResponse> suggestions = regions.stream()
                .map(region -> new ChatSuggestionResponse(region.name(), region.name(), null, region.id()))
                .toList();
        return new ChatResponse(question, mode, suggestions, List.of(), null, false);
    }

    private ChatResponse regionalQueryByName(
            UserAccount user, String mode, String normalizedName, String conversationId) {
        List<ChatRegionOption> matches = repository.accessibleRegions(user.getId()).stream()
                .filter(region -> {
                    String name = vectorizer.normalize(region.name());
                    return name.equals(normalizedName) || name.contains(normalizedName) || normalizedName.contains(name);
                }).toList();
        if (matches.size() == 1) {
            conversations.selectRegion(user.getId(), conversationId, matches.get(0).id(), mode);
            return regionalQuery(user, mode, matches.get(0).id(), normalizedName);
        }
        return regionPrompt(user, mode, regionQuestion(mode));
    }

    private ChatResponse regionalQuery(UserAccount user, String mode, Long regionId, String source) {
        ChatRegionOption region = repository.accessibleRegions(user.getId()).stream()
                .filter(option -> option.id().equals(regionId)).findFirst().orElse(null);
        if (region == null) return readyResponse(
                "Essa região não está disponível para o seu usuário.", mainSuggestions(), MODE_READY);
        if (MODE_DUE_TODAY_REGION.equalsIgnoreCase(mode)) return regionalDueToday(user, region, source);
        if (MODE_OVERDUE_REGION.equalsIgnoreCase(mode)) return regionalOverdue(user, region, source);
        return summaryPeriodPrompt(region);
    }

    private ChatResponse summaryPeriodPrompt(ChatRegionOption region) {
        return new ChatResponse(
                "Qual período você quer analisar em " + region.name() + "?",
                MODE_SUMMARY_PERIOD,
                List.of(
                        new ChatSuggestionResponse(
                                "Últimos 30 dias", "Últimos 30 dias", null, null, null),
                        new ChatSuggestionResponse(
                                "Escolher mês", "Escolher mês", null, null, null),
                        new ChatSuggestionResponse("Geral", "Geral", null, null, null),
                        otherSubject()),
                List.of(), null, false);
    }

    private ChatResponse summaryPeriod(
            UserAccount user,
            ChatConversationContext context,
            String normalized) {
        ChatRegionOption region = selectedRegion(user, context.regionId());
        if (region == null) {
            return regionPrompt(user, MODE_SUMMARY_REGION,
                    "Qual região você quer analisar no resumo financeiro?");
        }
        if (normalized.equals("ultimos 30 dias")) {
            LocalDate endDate = LocalDate.now(BUSINESS_ZONE);
            return regionalSummary(user, region, endDate.minusDays(29), endDate);
        }
        if (normalized.equals("geral")) {
            return regionalSummary(user, region, null, null);
        }
        if (normalized.equals("escolher mes")) {
            List<ChatSuggestionResponse> months = new ArrayList<>();
            for (ChatMonthOption month : repository.availableSummaryMonths(
                    user.getId(), region.id())) {
                months.add(new ChatSuggestionResponse(
                        month.label(),
                        "Resumo financeiro " + month.year() + " " + month.month(),
                        null,
                        null,
                        ACTION_SELECT_MONTH));
            }
            months.add(otherSubject());
            return new ChatResponse(
                    "Escolha o mês do resumo financeiro de " + region.name() + ".",
                    MODE_SUMMARY_MONTH, months, List.of(), null, false);
        }
        return summaryPeriodPrompt(region);
    }

    private ChatResponse summaryMonth(
            UserAccount user,
            ChatConversationContext context,
            String normalized) {
        ChatRegionOption region = selectedRegion(user, context.regionId());
        if (region == null) {
            return regionPrompt(user, MODE_SUMMARY_REGION,
                    "Qual região você quer analisar no resumo financeiro?");
        }
        java.util.regex.Matcher matcher = java.util.regex.Pattern
                .compile("(?:resumo financeiro )?(\\d{4}) (\\d{1,2})$")
                .matcher(normalized);
        if (!matcher.find()) return summaryPeriod(user, context, "escolher mes");
        int year = Integer.parseInt(matcher.group(1));
        int month = Integer.parseInt(matcher.group(2));
        if (month < 1 || month > 12) return summaryPeriod(user, context, "escolher mes");
        YearMonth selected = YearMonth.of(year, month);
        return regionalSummary(user, region, selected.atDay(1), selected.atEndOfMonth());
    }

    private ChatResponse regionalSummary(
            UserAccount user,
            ChatRegionOption region,
            LocalDate startDate,
            LocalDate endDate) {
        ChatFinancialSummaryResponse summary = repository.summary(
                user.getId(), region.id(), startDate, endDate);
        ChatLoanStatusResponse loanStatus = repository.loanStatus(
                user.getId(), region.id(), startDate, endDate);
        ChatClientStatusResponse clientStatus = repository.clientStatus(
                user.getId(), region.id());
        List<com.webdigital.money2.goals.FinancialGoalResponse> financialGoals =
                repository.activeFinancialGoals(user.getId(), region.id());
        return new ChatResponse(
                "Aqui está o resumo financeiro de " + region.name() + ".",
                MODE_READY,
                List.of(
                        new ChatSuggestionResponse(
                                "Exportar PDF", "Exportar PDF", null, null, ACTION_EXPORT_PDF),
                        otherSubject()),
                List.of(), summary, false, List.of(), loanStatus, clientStatus,
                null, financialGoals,
                new ChatSummaryContextResponse(
                        region.id(), region.name(), startDate, endDate));
    }

    private ChatResponse regionalDueToday(UserAccount user, ChatRegionOption region, String source) {
        List<ChatLoanResponse> loans = repository.dueTodayLoans(user.getId(), region.id());
        String message = loans.isEmpty()
                ? choose(source, "Tudo tranquilo: não há valores vencendo hoje em " + region.name() + ".",
                        "Nenhum vencimento para hoje em " + region.name() + ".")
                : choose(source, "Encontrei " + loans.size()
                                + " empréstimo(s) com vencimento hoje em " + region.name() + ".",
                        "Estes são os vencimentos de hoje em " + region.name() + ".");
        return loanListResponse(message, loans);
    }

    private ChatResponse regionalOverdue(UserAccount user, ChatRegionOption region, String source) {
        List<ChatLoanResponse> loans = repository.overdueLoans(user.getId(), region.id());
        String message = loans.isEmpty()
                ? choose(source, "Boa notícia: não há empréstimos atrasados em " + region.name() + ".",
                        "Nenhuma pendência vencida encontrada em " + region.name() + ".")
                : choose(source, "Separei todos os empréstimos atrasados em " + region.name() + ".",
                        "Encontrei " + loans.size()
                                + " empréstimo(s) atrasado(s) em " + region.name() + ".");
        return loanListResponse(message, loans);
    }

    private ChatResponse loanListResponse(String message, List<ChatLoanResponse> loans) {
        return new ChatResponse(
                message,
                MODE_READY,
                List.of(
                        new ChatSuggestionResponse(
                                "Exportar", "Exportar", null, null, ACTION_EXPORT_EXCEL),
                        otherSubject()),
                List.of(), null, false, loans, null, null, null, List.of(), null);
    }

    private ChatRegionOption selectedRegion(UserAccount user, Long regionId) {
        if (regionId == null) return null;
        return repository.accessibleRegions(user.getId()).stream()
                .filter(option -> option.id().equals(regionId))
                .findFirst()
                .orElse(null);
    }

    private ChatResponse detailResponse(
            UserAccount user,
            ChatClientResponse client,
            boolean semanticSearch,
            String source) {
        String opening = choose(source,
                "Encontrei " + client.name() + ". Separei o resumo financeiro e os contratos ativos abaixo.",
                "Certo, estes são os dados atuais de " + client.name() + ".",
                "Aqui está a posição financeira de " + client.name() + ", com os contratos que você pode abrir.");
        List<ChatLoanResponse> loans = repository.activeLoanResults(user.getId(), client.id(), 100);
        if (loans.isEmpty()) {
            opening += " O cliente não possui empréstimos ativos no momento.";
        }
        return clientAnswerWithLoans(opening, client, loans, semanticSearch);
    }

    private ChatResponse help(ChatConversationContext context) {
        if (context.loanId() != null) {
            return readyResponse(
                    "Pode continuar a pergunta sobre o contrato #" + context.loanId()
                            + " ou digitar outro número.",
                    contractSuggestions(), MODE_CONTRACT_CONTEXT);
        }
        return readyResponse(context.clientId() == null
                        ? "Pode perguntar do seu jeito. Digite um contrato ou consulte pagamentos, histórico, indicadores e regiões."
                        : "Pode continuar a pergunta sobre esse cliente ou escolher outra consulta.",
                context.clientId() == null ? mainSuggestions() : clientSuggestions(),
                context.clientId() == null ? MODE_READY : MODE_CLIENT_CONTEXT);
    }

    private ChatResponse readyResponse(
            String message, List<ChatSuggestionResponse> suggestions, String mode) {
        return new ChatResponse(message, mode, suggestions, List.of(), null, false);
    }

    private List<ChatSuggestionResponse> mainSuggestions() {
        return List.of(
                new ChatSuggestionResponse("Consultar cliente", "Consultar cliente", null),
                new ChatSuggestionResponse("Vencimentos de hoje", "Clientes com vencimento hoje", null),
                new ChatSuggestionResponse("Empréstimos Atrasados", "Empréstimos Atrasados", null),
                new ChatSuggestionResponse("Resumo financeiro", "Resumo financeiro", null));
    }

    private List<ChatSuggestionResponse> clientSuggestions() {
        return List.of(
                new ChatSuggestionResponse("Último pagamento", "Qual foi o último pagamento?", null),
                new ChatSuggestionResponse("Próximo vencimento", "Quando vence a próxima parcela?", null),
                new ChatSuggestionResponse("Saldo atual", "Quanto ainda está devendo?", null),
                new ChatSuggestionResponse("Outro cliente", "Consultar cliente", null));
    }

    private List<ChatSuggestionResponse> contractSuggestions() {
        return List.of(
                new ChatSuggestionResponse("Histórico", "Mostre o histórico de alterações", null),
                otherSubject());
    }

    private List<ChatSuggestionResponse> otherSubjectSuggestion() {
        return List.of(otherSubject());
    }

    private ChatSuggestionResponse otherSubject() {
        return new ChatSuggestionResponse("Outro assunto", "Outro assunto", null);
    }

    private ChatClientResponse findClient(UserAccount user, long clientId) {
        List<ChatClientResponse> clients = repository.clientsByIds(user.getId(), List.of(clientId), 1);
        return clients.isEmpty() ? null : clients.get(0);
    }

    private static boolean isRegionSelectionMode(String mode) {
        return MODE_SUMMARY_REGION.equalsIgnoreCase(mode)
                || MODE_DUE_TODAY_REGION.equalsIgnoreCase(mode)
                || MODE_OVERDUE_REGION.equalsIgnoreCase(mode);
    }

    private ChatRegionOption findRegion(UserAccount user, String normalized) {
        return repository.accessibleRegions(user.getId()).stream()
                .filter(region -> {
                    String regionName = vectorizer.normalize(region.name());
                    return !regionName.isBlank() && normalized.contains(regionName);
                })
                .max(Comparator.comparingInt(region -> region.name().length()))
                .orElse(null);
    }

    private DateRange requestedPeriod(String normalized) {
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        if (containsAny(normalized, "geral", "todo periodo", "desde o inicio", "total historico")) {
            return new DateRange(null, null, "no período geral");
        }
        if (containsAny(normalized, "hoje", "neste dia")) {
            return new DateRange(today, today, "hoje");
        }
        if (containsAny(normalized, "ultimos 30 dias", "30 dias")) {
            return new DateRange(today.minusDays(29), today, "nos últimos 30 dias");
        }
        if (containsAny(normalized, "mes passado", "ultimo mes")) {
            YearMonth month = YearMonth.from(today).minusMonths(1);
            return new DateRange(month.atDay(1), month.atEndOfMonth(), "no mês passado");
        }
        if (containsAny(normalized, "ano passado", "ultimo ano")) {
            int year = today.getYear() - 1;
            return new DateRange(
                    LocalDate.of(year, 1, 1), LocalDate.of(year, 12, 31),
                    "em " + year);
        }
        if (containsAny(normalized, "este ano", "ano atual")) {
            return new DateRange(
                    LocalDate.of(today.getYear(), 1, 1), today,
                    "em " + today.getYear());
        }
        Matcher days = Pattern.compile("ultimos (\\d{1,3}) dias").matcher(normalized);
        if (days.find()) {
            int amount = Math.max(1, Math.min(Integer.parseInt(days.group(1)), 365));
            return new DateRange(today.minusDays(amount - 1L), today,
                    "nos últimos " + amount + " dias");
        }
        Matcher year = Pattern.compile("(?:^| )(20\\d{2})(?: |$)").matcher(normalized);
        if (year.find()) {
            int selected = Integer.parseInt(year.group(1));
            return new DateRange(
                    LocalDate.of(selected, 1, 1), LocalDate.of(selected, 12, 31),
                    "em " + selected);
        }
        YearMonth month = YearMonth.from(today);
        return new DateRange(month.atDay(1), month.atEndOfMonth(), "neste mês");
    }

    private static BigDecimal recommendation(BigDecimal threeMonthTotal) {
        return threeMonthTotal
                .divide(BigDecimal.valueOf(3), 2, RoundingMode.HALF_UP)
                .multiply(new BigDecimal("1.10"))
                .setScale(2, RoundingMode.HALF_UP);
    }

    private static BigDecimal percentage(BigDecimal numerator, BigDecimal denominator) {
        if (numerator == null || denominator == null || denominator.signum() == 0) {
            return BigDecimal.ZERO.setScale(2);
        }
        return numerator.multiply(BigDecimal.valueOf(100))
                .divide(denominator, 2, RoundingMode.HALF_UP);
    }

    private static String regionQuestion(String mode) {
        if (MODE_DUE_TODAY_REGION.equalsIgnoreCase(mode)) return "De qual região você quer ver os vencimentos de hoje?";
        if (MODE_OVERDUE_REGION.equalsIgnoreCase(mode)) return "De qual região você quer ver os empréstimos atrasados?";
        return "Qual região você quer analisar no resumo financeiro?";
    }

    private static String cleanedClientQuery(String normalized, String mode) {
        String result = normalized.replaceFirst("^(consultar|buscar|pesquisar|cliente|clientes)\\s+", "")
                .replaceFirst("^(o|a|os|as)\\s+", "").trim();
        if (MODE_CLIENT_SEARCH.equalsIgnoreCase(mode) && result.startsWith("cliente ")) {
            result = result.substring("cliente ".length()).trim();
        }
        return result;
    }

    private static boolean isGreeting(String value) {
        return value.matches("^(oi|ola|ola tudo bem|bom dia|boa tarde|boa noite|ajuda|tudo bem)$");
    }

    private static boolean isThanks(String value) {
        return value.matches("^(obrigado|obrigada|valeu|show|perfeito|ok obrigado|ok obrigada)$");
    }

    private static boolean isClientSearchCommand(String value) {
        return value.equals("consultar cliente") || value.equals("buscar cliente")
                || value.equals("outro cliente") || value.equals("trocar cliente")
                || value.equals("pesquisar cliente");
    }

    private static boolean isOtherSubject(String value) {
        return value.equals("outro assunto");
    }

    private static boolean isCollectiveIntent(String value) {
        return value.startsWith("clientes ") || value.startsWith("emprestimos ")
                || value.startsWith("resumo financeiro")
                || value.contains(" da regiao") || value.contains(" na regiao");
    }

    private static Long extractContractId(String value) {
        if (value == null || value.isBlank()) return null;
        Matcher matcher = CONTRACT_WITH_LABEL.matcher(value);
        String number = matcher.find() ? matcher.group(1)
                : ONLY_NUMBER.matcher(value).matches() ? value : null;
        if (number == null) return null;
        try {
            long result = Long.parseLong(number);
            return result > 0 ? result : null;
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static boolean isContractCreatedBy(String value) {
        return containsAny(value,
                "quem criou", "quem cadastrou", "criado por", "autor da criacao",
                "responsavel pela criacao", "quem fez o contrato");
    }

    private static boolean isContractApproval(String value) {
        return containsAny(value,
                "quem aprovou", "aprovado por", "historico de aprovacao",
                "status da aprovacao", "conferencia do contrato", "aprovacao do contrato");
    }

    private static boolean isContractHistory(String value) {
        return containsAny(value,
                "historico", "alteracoes", "alteracao", "o que mudou",
                "movimentacoes", "auditoria", "ultima mudanca", "quem alterou");
    }

    private static boolean isContractScopedIntent(String value) {
        return containsAny(value,
                "contrato", "emprestimo", "pagamento", "pagou", "parcela",
                "vencimento", "saldo", "divida", "historico", "alteracao",
                "aprovacao", "aprovou", "criou", "cadastrou", "lucro",
                "valor emprestado", "valor recebido", "qual regiao");
    }

    private static boolean isRegionalFinancialQuestion(String value) {
        return containsAny(value,
                "regiao", "regional", "lucro", "lucrou", "meta", "desempenho",
                "quanto emprestou", "quanto recebeu", "a receber", "inadimplencia");
    }

    private static boolean isGoalRecommendation(String value) {
        return containsAny(value,
                "recomenda", "recomendacao", "sugere", "sugestao de meta",
                "qual meta", "quanto de meta", "projecao de meta");
    }

    private static boolean isRegionalRanking(String value) {
        return containsAny(value, "ranking", "compare as regioes", "comparar regioes")
                || (containsAny(value, "qual regiao", "quais regioes")
                    && containsAny(value, "mais", "melhor", "maior", "menor"));
    }

    private boolean isCreationEvent(LoanHistoryResponse event) {
        String operation = vectorizer.normalize(event.operation());
        String description = vectorizer.normalize(event.description());
        return containsAny(operation, "criar", "cadastrar", "novo emprestimo", "novo contrato")
                || containsAny(description, "novo contrato criado", "emprestimo criado", "contrato criado");
    }

    private static boolean isLatestPayment(String value) {
        return containsAny(value, "ultimo pagamento", "ultima parcela paga", "ultima vez que pagou",
                "quando pagou", "data do pagamento", "data desse pagamento", "pagamento mais recente",
                "quanto foi o pagamento", "valor do ultimo pagamento", "ultimo valor recebido")
                || (containsAny(value, "pagamento", "pagou", "parcela paga", "recebido")
                    && containsAny(value, "ultimo", "ultima", "recente", "quando", "que dia", "data"));
    }

    private static boolean isNextDue(String value) {
        return containsAny(value, "proximo vencimento", "proxima parcela", "quando vence",
                "data do vencimento", "qual vencimento", "vencimento seguinte")
                || (containsAny(value, "vence", "vencimento", "parcela")
                    && containsAny(value, "proximo", "proxima", "seguinte", "quando", "que dia"));
    }

    private static boolean isOpenInstallments(String value) {
        return containsAny(value, "quantas parcelas", "parcelas abertas", "parcelas em aberto",
                "parcelas pendentes", "quantas prestacoes");
    }

    private static boolean isLoanList(String value) {
        return containsAny(value, "quais contratos", "listar contratos", "contratos ativos",
                "quais emprestimos", "listar emprestimos", "emprestimos ativos");
    }

    private static boolean isContact(String value) {
        return containsAny(value, "telefone", "whatsapp", "numero do cliente", "contato");
    }

    private static boolean isDocument(String value) {
        return containsAny(value, "cpf", "cnpj", "documento");
    }

    private static boolean isRegionQuestion(String value) {
        return containsAny(value, "qual regiao", "regiao dele", "regiao dela", "onde pertence");
    }

    private static boolean isDebt(String value) {
        return containsAny(value, "quanto deve", "quanto ainda deve", "esta devendo", "saldo atual",
                "saldo devedor", "valor a receber", "divida atual", "em aberto")
                || (containsAny(value, "saldo", "divida", "deve", "devendo", "receber")
                    && containsAny(value, "quanto", "qual", "total", "valor", "ainda"));
    }

    private static boolean isReceived(String value) {
        return containsAny(value, "quanto recebeu", "quanto ja recebeu", "total recebido", "valor recebido");
    }

    private static boolean isLoaned(String value) {
        return containsAny(value, "quanto emprestou", "quanto foi emprestado", "total emprestado", "valor emprestado");
    }

    private static boolean isClientSummary(String value) {
        return containsAny(value, "situacao do cliente", "dados do cliente", "financeiro dele",
                "financeiro dela", "como ele esta", "como ela esta", "visao geral");
    }

    private static boolean isDueToday(String value) {
        return containsAny(value, "vence hoje", "vencem hoje", "vencimento hoje",
                "vencimentos de hoje", "divida hoje");
    }

    private static boolean isOverdue(String value) {
        return containsAny(value, "em atraso", "atrasados", "atrasado", "inadimplentes", "inadimplente");
    }

    private static boolean isSummary(String value) {
        return value.contains("resumo financeiro") || value.contains("resumo da operacao") || value.equals("resumo");
    }

    private static boolean containsAny(String value, String... terms) {
        for (String term : terms) if (value.contains(term)) return true;
        return false;
    }

    private static boolean isContinuationOf(String value, String lastIntent, String expectedIntent) {
        if (!expectedIntent.equals(lastIntent) || value.length() > 45) return false;
        return containsAny(value,
                "e o valor", "qual valor", "e a data", "qual data", "que dia",
                "qual parcela", "qual contrato", "e quando", "e o proximo", "e a proxima");
    }

    private static String choose(String source, String... alternatives) {
        if (alternatives.length == 0) return "";
        return alternatives[Math.floorMod(source == null ? 0 : source.hashCode(), alternatives.length)];
    }

    private static String ordinal(String installment) {
        String clean = clean(installment);
        return clean.matches(".*[ºª°].*") ? clean : clean + "ª";
    }

    private static String installmentSuffix(String installment) {
        String clean = clean(installment);
        return clean.isBlank() || "-".equals(clean)
                ? ""
                : ", na " + ordinal(clean) + " parcela";
    }

    private static String approvalHistoryDescription(LoanApprovalResponse approval) {
        String description = nullable(approval.description());
        if (description != null) return description;
        String rejectionReason = nullable(approval.rejectionReason());
        if (rejectionReason != null) return "Solicitação recusada: " + rejectionReason;
        String status = clean(approval.status());
        if ("APROVADO".equalsIgnoreCase(status)) return "Contrato aprovado.";
        if ("REJEITADO".equalsIgnoreCase(status)) return "Solicitação de aprovação recusada.";
        if ("PENDENTE".equalsIgnoreCase(status)) return "Contrato enviado para aprovação.";
        return status.isBlank() ? "Movimentação de aprovação." : status;
    }

    private static String formatOccurredAt(LocalDateTime value) {
        return value == null ? "" : " em " + DATE_TIME.format(value);
    }

    private static LocalDate toDate(LocalDateTime value) {
        return value == null ? null : value.toLocalDate();
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static String nullable(String value) {
        String clean = clean(value);
        return clean.isBlank() ? null : clean;
    }

    private static String currency(BigDecimal value) {
        return NumberFormat.getCurrencyInstance(BRAZIL).format(
                value == null ? BigDecimal.ZERO : value);
    }

    private static String percent(BigDecimal value) {
        BigDecimal clean = value == null ? BigDecimal.ZERO.setScale(2)
                : value.setScale(2, RoundingMode.HALF_UP);
        return clean.toPlainString().replace('.', ',') + "%";
    }

    private record DateRange(LocalDate start, LocalDate end, String label) {}

}
