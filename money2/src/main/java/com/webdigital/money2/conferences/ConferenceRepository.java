package com.webdigital.money2.conferences;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class ConferenceRepository {

    private static final String FILTERED = """
            WITH source AS (
              SELECT a.id, a.tipo, a.acao, a.status, a.emprestimo_id,
                     a.emprestimo_origem_id, a.parcela_id, a.regiao_id,
                     COALESCE(r.descricao, '') AS region_name,
                     COALESCE(c.nome, '') AS client_name,
                     COALESCE(a.descricao, '') AS description,
                     COALESCE(a.valor, 0) AS amount,
                     COALESCE(a.solicitante_nome, a.solicitante_username, '') AS requester,
                     a.dtcad,
                     CASE
                       WHEN a.tipo='PAGAMENTO' AND COALESCE(a.emprestimo_id, 0) > 0
                         THEN 'P:' || a.emprestimo_id
                       ELSE 'A:' || a.id
                     END AS card_key
              FROM aprovacoes a
              LEFT JOIN emprestimo e ON e.id = a.emprestimo_id
              LEFT JOIN cliente c ON c.id = e.cliente_id
              LEFT JOIN regioes r ON r.id = a.regiao_id
              WHERE a.status = 'PENDENTE'
            ), filtered AS (
              SELECT source.* FROM source
              WHERE 1=1
              AND EXISTS (
                SELECT 1 FROM regiao_usuario ru
                WHERE ru.usuario_id = :userId AND ru.regiao_id = source.regiao_id
              )
              AND (:allTypes OR source.tipo IN (:types))
              AND (:allRegions OR source.regiao_id IN (:regionIds))
              AND (
                :query = ''
                OR LOWER(source.client_name) LIKE :queryLike
                OR LOWER(source.region_name) LIKE :queryLike
                OR LOWER(source.description) LIKE :queryLike
                OR LOWER(source.requester) LIKE :queryLike
                OR CAST(COALESCE(source.emprestimo_id, 0) AS TEXT) LIKE :queryLike
              )
            ), ranked AS (
              SELECT filtered.*,
                     SUM(amount) OVER (PARTITION BY card_key) AS card_amount,
                     COUNT(*) OVER (PARTITION BY card_key) AS card_count,
                     ROW_NUMBER() OVER (
                       PARTITION BY card_key ORDER BY dtcad DESC NULLS LAST, id DESC
                     ) AS card_position
              FROM filtered
            )
            """;

    private final NamedParameterJdbcTemplate jdbc;

    public ConferenceRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public ConferenceListResponse search(
            long userId, String query, List<String> types, List<Long> regionIds, int page, int size,
            boolean includeDetails) {
        MapSqlParameterSource parameters = parameters(userId, query, types, regionIds)
                .addValue("limit", size)
                .addValue("offset", page * size);
        List<ConferenceItemResponse> items = jdbc.query(
                FILTERED + """
                SELECT id,tipo,acao,status,emprestimo_id,emprestimo_origem_id,parcela_id,regiao_id,
                       region_name,client_name,description,card_amount,requester,dtcad,card_count
                FROM ranked WHERE card_position=1
                ORDER BY dtcad DESC NULLS LAST,id DESC LIMIT :limit OFFSET :offset
                """,
                parameters,
                (rs, row) -> new ConferenceItemResponse(
                        rs.getLong(1), clean(rs.getString(2)), nullable(rs.getString(3)),
                        clean(rs.getString(4)), rs.getObject(5, Long.class),
                        rs.getObject(6, Long.class), rs.getObject(7, Long.class),
                        rs.getObject(8, Long.class), clean(rs.getString(9)), clean(rs.getString(10)),
                        clean(rs.getString(11)), decimal(rs.getBigDecimal(12)), clean(rs.getString(13)),
                        dateTime(rs.getTimestamp(14)), rs.getInt(15), List.of()));

        Map<Long, List<ConferenceDetailResponse>> details = includeDetails
                ? detailsByCardIds(items.stream().map(ConferenceItemResponse::id).toList())
                : Map.of();
        items = items.stream().map(item -> {
            List<ConferenceDetailResponse> cardDetails = details.getOrDefault(item.id(), List.of());
            int itemCount = cardDetails.isEmpty() ? item.itemCount() : cardDetails.size();
            String description = groupedDescription(item, itemCount);
            return new ConferenceItemResponse(
                    item.id(), item.type(), item.action(), item.status(), item.loanId(), item.originLoanId(),
                    item.installmentId(), item.regionId(), item.regionName(), item.clientName(), description,
                    item.amount(), item.requester(), item.createdAt(), itemCount, List.copyOf(cardDetails));
        }).toList();

        Long total = jdbc.queryForObject(
                FILTERED + " SELECT COUNT(*) FROM ranked WHERE card_position=1",
                parameters, Long.class);
        Map<String, Long> counts = counts(userId, query, regionIds);
        return new ConferenceListResponse(
                List.copyOf(items), total == null ? 0 : total, page, size, Map.copyOf(counts));
    }

    public List<ConferenceDetailResponse> details(long userId, long cardId) {
        Boolean allowed = jdbc.queryForObject("""
                SELECT EXISTS (
                  SELECT 1 FROM aprovacoes a
                  WHERE a.id=:cardId AND a.status='PENDENTE'
                    AND EXISTS (
                      SELECT 1 FROM regiao_usuario ru
                      WHERE ru.usuario_id=:userId AND ru.regiao_id=a.regiao_id
                    )
                )
                """, Map.of("cardId", cardId, "userId", userId), Boolean.class);
        if (!Boolean.TRUE.equals(allowed)) return List.of();
        return List.copyOf(detailsByCardIds(List.of(cardId)).getOrDefault(cardId, List.of()));
    }

    private Map<Long, List<ConferenceDetailResponse>> detailsByCardIds(List<Long> cardIds) {
        if (cardIds == null || cardIds.isEmpty()) return Map.of();
        Map<Long, List<ConferenceDetailResponse>> result = new LinkedHashMap<>();
        jdbc.query("""
                SELECT detail.card_id, detail.approval_id, detail.payment_id, detail.installment_id,
                       detail.installment, detail.due_date, detail.amount, detail.installment_amount,
                       detail.interest_amount, detail.total_amount, detail.description,
                       detail.due_date_observation
                FROM (
                  SELECT rep.id AS card_id, a.id AS approval_id,
                         COALESCE(pg.id_pagamento, a.entidade_id) AS payment_id,
                         COALESCE(p.id, a.parcela_id) AS installment_id,
                         COALESCE(p.parcela, '') AS installment, p.vencimento::date AS due_date,
                         COALESCE(pg.valor, a.valor, 0) AS amount,
                         COALESCE(p.valor, 0) AS installment_amount,
                         COALESCE(p.valor_juros, 0) AS interest_amount,
                         COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0) AS total_amount,
                         CASE
                           WHEN p.id IS NULL THEN 'Pagamento'
                           WHEN COALESCE(pg.tipo, 'NORMAL') = 'JUROS_ROLAGEM'
                             THEN 'Baixa só juros na parcela ' || COALESCE(p.parcela, '')
                           ELSE 'Parcela ' || COALESCE(p.parcela, '')
                         END AS description,
                         COALESCE(p.observacao_vencimento, '') AS due_date_observation
                  FROM aprovacoes rep
                  JOIN aprovacoes a ON a.status='PENDENTE' AND a.tipo='PAGAMENTO'
                       AND a.emprestimo_id=rep.emprestimo_id
                  LEFT JOIN pagamentos pg ON pg.id_pagamento=a.entidade_id
                  LEFT JOIN parcelas p ON p.id=COALESCE(a.parcela_id, pg.parcela_id)
                  WHERE rep.id IN (:cardIds) AND rep.tipo='PAGAMENTO'

                  UNION ALL

                  SELECT rep.id AS card_id, rep.id AS approval_id, NULL::bigint AS payment_id,
                         p.id AS installment_id, COALESCE(p.parcela, '') AS installment,
                         p.vencimento::date AS due_date,
                         COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0) AS amount,
                         COALESCE(p.valor, 0) AS installment_amount,
                         COALESCE(p.valor_juros, 0) AS interest_amount,
                         COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0) AS total_amount,
                         'Parcela ' || COALESCE(p.parcela, '') AS description,
                         COALESCE(p.observacao_vencimento, '') AS due_date_observation
                  FROM aprovacoes rep
                  JOIN parcelas p ON p.emprestimo_id=COALESCE(rep.entidade_id, rep.emprestimo_id)
                  WHERE rep.id IN (:cardIds) AND rep.tipo IN
                        ('EMPRESTIMO','REFINANCIAMENTO','RENOVACAO','FINALIZACAO')
                ) detail
                ORDER BY detail.card_id, detail.due_date NULLS LAST,
                         NULLIF(regexp_replace(detail.installment, '[^0-9]', '', 'g'), '')::integer NULLS LAST,
                         detail.installment_id
                """, Map.of("cardIds", cardIds), rs -> {
            long cardId = rs.getLong("card_id");
            ConferenceDetailResponse detail = new ConferenceDetailResponse(
                    rs.getObject("approval_id", Long.class), rs.getObject("payment_id", Long.class),
                    rs.getObject("installment_id", Long.class), clean(rs.getString("installment")),
                    localDate(rs.getDate("due_date")), decimal(rs.getBigDecimal("amount")),
                    decimal(rs.getBigDecimal("installment_amount")),
                    decimal(rs.getBigDecimal("interest_amount")),
                    decimal(rs.getBigDecimal("total_amount")), clean(rs.getString("description")),
                    clean(rs.getString("due_date_observation")));
            result.computeIfAbsent(cardId, ignored -> new ArrayList<>()).add(detail);
        });
        return result;
    }

    private String groupedDescription(ConferenceItemResponse item, int itemCount) {
        if (!"PAGAMENTO".equals(item.type()) || itemCount <= 1) return item.description();
        String description = clean(item.description());
        int groupedIndex = description.indexOf(". ");
        if (groupedIndex > 0 && description.substring(groupedIndex).contains("parcela(s) neste pagamento")) {
            description = description.substring(0, groupedIndex);
        }
        int valueIndex = description.indexOf(" no valor de ");
        if (valueIndex > 0) description = description.substring(0, valueIndex);
        if (description.isBlank()) {
            description = "Baixa manual no contrato " + (item.loanId() == null ? "" : item.loanId());
        }
        return description + ". " + itemCount + " parcela(s) neste pagamento aguardando conferência.";
    }

    public List<DecisionTarget> decisionTargets(long userId, long conferenceId) {
        List<DecisionTarget> selected = jdbc.query("""
                SELECT id, emprestimo_id, tipo, grupo_aprovacao
                FROM aprovacoes
                WHERE id=:id AND status='PENDENTE'
                  AND EXISTS (SELECT 1 FROM regiao_usuario ru
                              WHERE ru.usuario_id=:userId AND ru.regiao_id=aprovacoes.regiao_id)
                """, Map.of("id", conferenceId, "userId", userId), (rs, row) ->
                new DecisionTarget(rs.getLong(1), rs.getObject(2, Long.class),
                        clean(rs.getString(3)), nullable(rs.getString(4))));
        if (selected.isEmpty()) return List.of();
        DecisionTarget first = selected.get(0);
        if (!"PAGAMENTO".equals(first.type())) return selected;
        if (first.loanId() != null && first.loanId() > 0) {
            return jdbc.query("""
                    SELECT id, emprestimo_id, tipo, grupo_aprovacao
                    FROM aprovacoes
                    WHERE status='PENDENTE' AND tipo='PAGAMENTO' AND emprestimo_id=:loanId
                      AND EXISTS (SELECT 1 FROM regiao_usuario ru
                                  WHERE ru.usuario_id=:userId AND ru.regiao_id=aprovacoes.regiao_id)
                    ORDER BY parcela_id NULLS LAST, id
                    """, Map.of("loanId", first.loanId(), "userId", userId), (rs, row) ->
                    new DecisionTarget(rs.getLong(1), rs.getObject(2, Long.class),
                            clean(rs.getString(3)), nullable(rs.getString(4))));
        }
        if (first.group() == null) return selected;
        return jdbc.query("""
                SELECT id, emprestimo_id, tipo, grupo_aprovacao
                FROM aprovacoes
                WHERE status='PENDENTE' AND grupo_aprovacao=:group
                  AND EXISTS (SELECT 1 FROM regiao_usuario ru
                              WHERE ru.usuario_id=:userId AND ru.regiao_id=aprovacoes.regiao_id)
                ORDER BY id
                """, Map.of("group", first.group(), "userId", userId), (rs, row) ->
                new DecisionTarget(rs.getLong(1), rs.getObject(2, Long.class),
                        clean(rs.getString(3)), nullable(rs.getString(4))));
    }

    public List<AutomaticPaymentTarget> expiredPaymentTargets(int limit) {
        return jdbc.query("""
                SELECT a.id, a.emprestimo_id
                FROM aprovacoes a
                WHERE a.status='PENDENTE' AND a.tipo='PAGAMENTO'
                  AND a.emprestimo_id IS NOT NULL AND a.entidade_id IS NOT NULL
                  AND a.dtcad < NOW() - INTERVAL '30 days'
                ORDER BY a.dtcad, a.id
                LIMIT :limit
                """, Map.of("limit", Math.min(Math.max(limit, 1), 500)), (rs, row) ->
                new AutomaticPaymentTarget(rs.getLong(1), rs.getLong(2)));
    }

    private Map<String, Long> counts(long userId, String query, List<Long> regionIds) {
        MapSqlParameterSource parameters = parameters(userId, query, List.of(), regionIds);
        Map<String, Long> result = new LinkedHashMap<>();
        result.put("ALL", 0L);
        result.put("PAYMENT", 0L);
        result.put("LOAN", 0L);
        result.put("NEGOTIATION", 0L);
        result.put("CLOSURE", 0L);
        jdbc.query(FILTERED + """
                SELECT CASE
                         WHEN tipo='PAGAMENTO' THEN 'PAYMENT'
                         WHEN tipo='EMPRESTIMO' THEN 'LOAN'
                         WHEN tipo IN ('REFINANCIAMENTO','RENOVACAO') THEN 'NEGOTIATION'
                         WHEN tipo='FINALIZACAO' THEN 'CLOSURE'
                         ELSE 'OTHER'
                       END category, COUNT(*)
                FROM ranked WHERE card_position=1 GROUP BY 1
                """, parameters, rs -> {
            long value = rs.getLong(2);
            result.put(rs.getString(1), value);
            result.put("ALL", result.get("ALL") + value);
        });
        return result;
    }

    private MapSqlParameterSource parameters(
            long userId, String query, List<String> types, List<Long> regionIds) {
        String normalized = query == null ? "" : query.trim().toLowerCase();
        List<String> safeTypes = types == null || types.isEmpty() ? List.of("__ALL__") : types;
        List<Long> safeRegions = regionIds == null || regionIds.isEmpty() ? List.of(-1L) : regionIds;
        return new MapSqlParameterSource()
                .addValue("userId", userId)
                .addValue("query", normalized)
                .addValue("queryLike", "%" + normalized + "%")
                .addValue("allTypes", types == null || types.isEmpty())
                .addValue("types", safeTypes)
                .addValue("allRegions", regionIds == null || regionIds.isEmpty())
                .addValue("regionIds", safeRegions);
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static String nullable(String value) {
        String result = clean(value);
        return result.isEmpty() ? null : result;
    }

    private static BigDecimal decimal(BigDecimal value) {
        return value == null ? BigDecimal.ZERO : value;
    }

    private static LocalDateTime dateTime(Timestamp value) {
        return value == null ? null : value.toLocalDateTime();
    }

    private static LocalDate localDate(java.sql.Date value) {
        return value == null ? null : value.toLocalDate();
    }

    public record DecisionTarget(long id, Long loanId, String type, String group) {
    }

    public record AutomaticPaymentTarget(long approvalId, long loanId) {
    }
}
