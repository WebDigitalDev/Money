package com.webdigital.money2.reports;

import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class AuditHistoryRepository {

    private static final Pattern VALUE_PATTERN = Pattern.compile(
            "R\\$\\s*\\d{1,3}(?:\\.\\d{3})*,\\d{2}|R\\$\\s*\\d+,\\d{2}");

    private static final String HISTORY_SQL = """
            WITH filtered_logs AS MATERIALIZED (
                SELECT
                    l.id,
                    l.entity_name,
                    l.username,
                    l.entity_id,
                    l.operation,
                    l.description,
                    l.timestamp AS log_timestamp
                FROM entity_log_detalhado l
                WHERE (CAST(:startDate AS timestamp) IS NULL
                       OR l.timestamp >= CAST(:startDate AS timestamp))
                  AND (CAST(:endDateExclusive AS timestamp) IS NULL
                       OR l.timestamp < CAST(:endDateExclusive AS timestamp))
                  AND (:filterUsers = false OR l.username IN (:usernames))
            ),
            enriched AS MATERIALIZED (
                SELECT
                    l.*,
                    CASE
                        WHEN l.entity_name = 'REGIAO' THEN l.entity_id
                        ELSE COALESCE(client.regiao_id, approval.regiao_id)
                    END AS region_id,
                    client.nome AS client_name
                FROM filtered_logs l
                LEFT JOIN cliente client_log
                       ON l.entity_name = 'CLIENTE' AND client_log.id = l.entity_id
                LEFT JOIN emprestimo loan_log
                       ON l.entity_name = 'EMPRESTIMO' AND loan_log.id = l.entity_id
                LEFT JOIN parcelas installment_log
                       ON l.entity_name = 'PARCELA' AND installment_log.id = l.entity_id
                LEFT JOIN emprestimo installment_loan
                       ON installment_loan.id = installment_log.emprestimo_id
                LEFT JOIN pagamentos payment_log
                       ON l.entity_name = 'PAGAMENTO'
                      AND (l.operation IS NULL OR l.operation NOT IN (
                          'adicionaPagamento',
                          'deletaPagamentoEmprestimo',
                          'lancarPagamentoContrato',
                          'aprovarPagamentoContrato',
                          'reprovarPagamentoContrato'))
                      AND payment_log.id_pagamento = l.entity_id
                LEFT JOIN parcelas payment_installment
                       ON payment_installment.id = payment_log.parcela_id
                LEFT JOIN emprestimo payment_loan
                       ON payment_loan.id = payment_installment.emprestimo_id
                LEFT JOIN aprovacoes approval
                       ON l.entity_name = 'APROVACAO' AND approval.id = l.entity_id
                LEFT JOIN emprestimo approval_loan
                       ON approval_loan.id = COALESCE(
                           approval.emprestimo_id,
                           approval.entidade_id,
                           approval.emprestimo_origem_id)
                LEFT JOIN emprestimo contract_payment_loan
                       ON l.entity_name = 'PAGAMENTO'
                      AND l.operation IN (
                          'adicionaPagamento',
                          'deletaPagamentoEmprestimo',
                          'lancarPagamentoContrato',
                          'aprovarPagamentoContrato',
                          'reprovarPagamentoContrato')
                      AND contract_payment_loan.id = l.entity_id
                LEFT JOIN cliente client
                       ON client.id = COALESCE(
                           client_log.id,
                           loan_log.cliente_id,
                           installment_loan.cliente_id,
                           payment_loan.cliente_id,
                           approval_loan.cliente_id,
                           contract_payment_loan.cliente_id)
            )
            SELECT
                e.id,
                e.entity_name,
                e.username,
                e.entity_id,
                e.operation,
                e.description,
                e.log_timestamp,
                e.region_id,
                region.descricao AS region_description,
                e.client_name
            FROM enriched e
            LEFT JOIN regioes region ON region.id = e.region_id
            WHERE (
                e.region_id IS NULL
                OR EXISTS (
                    SELECT 1
                    FROM regiao_usuario ur
                    WHERE ur.usuario_id = :userId
                      AND ur.regiao_id = e.region_id
                )
            )
              AND (:filterRegions = false OR e.region_id IN (:regionIds))
            ORDER BY e.log_timestamp DESC NULLS LAST, e.id DESC
            LIMIT :limit OFFSET :offset
            """;

    private final NamedParameterJdbcTemplate jdbc;

    public AuditHistoryRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public AuditHistoryPageResponse search(
            long userId,
            LocalDateTime startDate,
            LocalDateTime endDateExclusive,
            Set<String> usernames,
            Set<Long> regionIds,
            int page,
            int size) {
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("userId", userId);
        parameters.put("startDate", startDate);
        parameters.put("endDateExclusive", endDateExclusive);
        parameters.put("filterUsers", usernames != null && !usernames.isEmpty());
        parameters.put(
                "usernames",
                usernames == null || usernames.isEmpty() ? List.of("") : usernames);
        parameters.put("filterRegions", regionIds != null && !regionIds.isEmpty());
        parameters.put(
                "regionIds",
                regionIds == null || regionIds.isEmpty() ? List.of(-1L) : regionIds);
        parameters.put("limit", size + 1);
        parameters.put("offset", page * size);

        List<AuditHistoryItemResponse> result = jdbc.query(
                HISTORY_SQL,
                parameters,
                (row, index) -> {
                    String description = enrichDescription(
                            row.getString("description"),
                            row.getString("client_name"));
                    Timestamp timestamp = row.getTimestamp("log_timestamp");
                    return new AuditHistoryItemResponse(
                            row.getLong("id"),
                            clean(row.getString("entity_name")),
                            clean(row.getString("username")),
                            row.getObject("entity_id", Long.class),
                            clean(row.getString("operation")),
                            clean(description),
                            timestamp == null ? null : timestamp.toLocalDateTime(),
                            row.getObject("region_id", Long.class),
                            nullable(row.getString("region_description")),
                            extractValue(description));
                });

        boolean hasNext = result.size() > size;
        List<AuditHistoryItemResponse> items = hasNext
                ? new ArrayList<>(result.subList(0, size))
                : result;
        return new AuditHistoryPageResponse(List.copyOf(items), page, size, hasNext);
    }

    public List<String> users() {
        return jdbc.query(
                """
                SELECT DISTINCT trim(username) AS username
                FROM users
                WHERE enable = true
                  AND username IS NOT NULL
                  AND trim(username) <> ''
                ORDER BY username
                """,
                (row, index) -> row.getString("username"));
    }

    private static String enrichDescription(String original, String clientName) {
        if (original == null) return "";
        String description = original.trim();
        if (!description.startsWith("Adicionado pagamento no valor")
                || description.toLowerCase(Locale.ROOT).contains(" cliente ")
                || clientName == null
                || clientName.isBlank()) {
            return original;
        }
        return description + " do cliente " + clientName.trim() + ".";
    }

    private static String extractValue(String description) {
        if (description == null) return "";
        Matcher matcher = VALUE_PATTERN.matcher(description);
        return matcher.find() ? matcher.group() : "";
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static String nullable(String value) {
        String result = clean(value);
        return result.isEmpty() ? null : result;
    }
}
