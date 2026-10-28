package com.webdigital.money2.clients;

import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class ClientQueryRepository {

    private static final String BASE_CTE = """
            WITH accessible_clients AS MATERIALIZED (
                SELECT
                    c.id,
                    c.nome,
                    c.razao,
                    c.cgc_cpf,
                    c.telefone,
                    c.telefone2,
                    c.regiao_id,
                    r.descricao AS regiao_descricao
                FROM cliente c
                JOIN regioes r ON r.id = c.regiao_id
                WHERE (
                      (:tutorialMode = true AND c.regiao_id = :tutorialRegionId)
                      OR
                      (:tutorialMode = false AND EXISTS (
                          SELECT 1
                          FROM regiao_usuario ur
                          WHERE ur.usuario_id = :userId
                            AND ur.regiao_id = c.regiao_id
                      ))
                  )
                  AND (:filterRegions = false OR c.regiao_id IN (:regionIds))
            ),
            loan_flags AS MATERIALIZED (
                SELECT
                    e.cliente_id,
                    bool_or(
                        COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                        AND e.status <> 3
                        AND COALESCE(e.refinanciado, false) = false
                        AND COALESCE(e.renovacao, false) = false
                        AND (
                            e.status = 1
                            OR COALESCE(e.desaparecido, false) = true
                            OR EXISTS (
                                SELECT 1 FROM parcelas p
                                WHERE p.emprestimo_id = e.id
                                  AND p.pendente = true
                            )
                        )
                    ) AS has_open_loan,
                    bool_or(
                        COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                        AND e.status <> 3
                        AND e.status <> 1
                        AND COALESCE(e.refinanciado, false) = false
                        AND COALESCE(e.renovacao, false) = false
                        AND COALESCE(e.desaparecido, false) = true
                    ) AS is_missing
                FROM emprestimo e
                JOIN accessible_clients c ON c.id = e.cliente_id
                GROUP BY e.cliente_id
            ),
            classified AS MATERIALIZED (
                SELECT
                    c.*,
                    CASE
                        WHEN COALESCE(lf.is_missing, false) THEN 'MISSING'
                        WHEN COALESCE(lf.has_open_loan, false) THEN 'ACTIVE'
                        ELSE 'INACTIVE'
                    END AS client_status
                FROM accessible_clients c
                LEFT JOIN loan_flags lf ON lf.cliente_id = c.id
            ),
            filtered AS MATERIALIZED (
                SELECT *
                FROM classified c
                WHERE :query = ''
                   OR lower(COALESCE(c.nome, '')) LIKE :search
                   OR lower(COALESCE(c.razao, '')) LIKE :search
                   OR lower(COALESCE(c.cgc_cpf, '')) LIKE :search
                   OR lower(COALESCE(c.telefone, '')) LIKE :search
                   OR lower(COALESCE(c.telefone2, '')) LIKE :search
                   OR CAST(c.id AS text) LIKE :search
                   OR (:digits <> '' AND (
                       regexp_replace(COALESCE(c.cgc_cpf, ''), '[^0-9]', '', 'g') LIKE :digitSearch
                       OR regexp_replace(COALESCE(c.telefone, ''), '[^0-9]', '', 'g') LIKE :digitSearch
                       OR regexp_replace(COALESCE(c.telefone2, ''), '[^0-9]', '', 'g') LIKE :digitSearch
                   ))
            )
            """;

    private final NamedParameterJdbcTemplate jdbc;

    public ClientQueryRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public ClientListResponse search(
            long userId,
            ClientStatus status,
            String rawQuery,
            Set<Long> regionIds,
            boolean tutorialMode,
            Long tutorialRegionId,
            int page,
            int size) {
        Map<String, Object> parameters = parameters(
                userId, rawQuery, regionIds, tutorialMode, tutorialRegionId);
        parameters.put("allStatuses", status == null);
        parameters.put("status", status == null ? "" : status.name());
        parameters.put("limit", size);
        parameters.put("offset", page * size);

        String listSql = BASE_CTE + """
                SELECT
                    id,
                    nome,
                    cgc_cpf,
                    COALESCE(NULLIF(telefone, ''), NULLIF(telefone2, '')) AS primary_phone,
                    regiao_id,
                    regiao_descricao,
                    client_status
                FROM filtered
                WHERE :allStatuses = true OR client_status = :status
                ORDER BY lower(COALESCE(nome, '')), id
                LIMIT :limit OFFSET :offset
                """;
        List<ClientSummaryResponse> items = jdbc.query(listSql, parameters, (result, row) ->
                new ClientSummaryResponse(
                        result.getLong("id"),
                        clean(result.getString("nome")),
                        nullable(result.getString("cgc_cpf")),
                        nullable(result.getString("primary_phone")),
                        result.getLong("regiao_id"),
                        clean(result.getString("regiao_descricao")),
                        ClientStatus.valueOf(result.getString("client_status"))));

        String countsSql = BASE_CTE + """
                SELECT
                    COUNT(*) FILTER (WHERE client_status = 'ACTIVE') AS active_count,
                    COUNT(*) FILTER (WHERE client_status = 'INACTIVE') AS inactive_count,
                    COUNT(*) FILTER (WHERE client_status = 'MISSING') AS missing_count
                FROM filtered
                """;
        ClientStatusCountsResponse counts = jdbc.queryForObject(
                countsSql,
                parameters,
                (result, row) -> new ClientStatusCountsResponse(
                        result.getLong("active_count"),
                        result.getLong("inactive_count"),
                        result.getLong("missing_count")));
        if (counts == null) counts = new ClientStatusCountsResponse(0, 0, 0);
        long total = status == null
                ? counts.active() + counts.withoutLoans() + counts.missing()
                : switch (status) {
                    case ACTIVE -> counts.active();
                    case INACTIVE -> counts.withoutLoans();
                    case MISSING -> counts.missing();
                };
        int totalPages = total == 0 ? 0 : (int) Math.ceil((double) total / size);
        return new ClientListResponse(
                items,
                page,
                size,
                total,
                totalPages,
                page + 1 < totalPages,
                counts);
    }

    public ClientStatus status(long clientId, long userId) {
        String sql = """
                SELECT CASE
                    WHEN EXISTS (
                        SELECT 1
                        FROM emprestimo e
                        WHERE e.cliente_id = c.id
                          AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                          AND e.status <> 3
                          AND e.status <> 1
                          AND COALESCE(e.refinanciado, false) = false
                          AND COALESCE(e.renovacao, false) = false
                          AND COALESCE(e.desaparecido, false) = true
                    ) THEN 'MISSING'
                    WHEN EXISTS (
                        SELECT 1
                        FROM emprestimo e
                        WHERE e.cliente_id = c.id
                          AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                          AND e.status <> 3
                          AND COALESCE(e.refinanciado, false) = false
                          AND COALESCE(e.renovacao, false) = false
                          AND (
                              e.status = 1
                              OR COALESCE(e.desaparecido, false) = true
                              OR EXISTS (
                                  SELECT 1
                                  FROM parcelas p
                                  WHERE p.emprestimo_id = e.id
                                    AND p.pendente = true
                              )
                          )
                    ) THEN 'ACTIVE'
                    ELSE 'INACTIVE'
                END AS client_status
                FROM cliente c
                WHERE c.id = :clientId
                  AND EXISTS (
                      SELECT 1
                      FROM regiao_usuario access
                      WHERE access.usuario_id = :userId
                        AND access.regiao_id = c.regiao_id
                  )
                """;
        List<String> result = jdbc.query(
                sql,
                Map.of("clientId", clientId, "userId", userId),
                (row, index) -> row.getString("client_status"));
        return result.isEmpty() ? ClientStatus.INACTIVE : ClientStatus.valueOf(result.get(0));
    }

    private Map<String, Object> parameters(
            long userId,
            String rawQuery,
            Set<Long> regionIds,
            boolean tutorialMode,
            Long tutorialRegionId) {
        String query = clean(rawQuery).toLowerCase(Locale.ROOT);
        String digits = query.replaceAll("[^0-9]", "");
        Map<String, Object> values = new HashMap<>();
        values.put("userId", userId);
        values.put("tutorialMode", tutorialMode);
        values.put("tutorialRegionId", tutorialRegionId == null ? -1L : tutorialRegionId);
        values.put("filterRegions", regionIds != null && !regionIds.isEmpty());
        values.put("regionIds", regionIds == null || regionIds.isEmpty() ? List.of(-1L) : regionIds);
        values.put("query", query);
        values.put("search", "%" + query + "%");
        values.put("digits", digits);
        values.put("digitSearch", "%" + digits + "%");
        return values;
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static String nullable(String value) {
        String result = clean(value);
        return result.isEmpty() ? null : result;
    }
}
