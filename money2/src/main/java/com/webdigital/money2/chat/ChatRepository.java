package com.webdigital.money2.chat;

import com.webdigital.money2.goals.FinancialGoalProgressRepository;
import com.webdigital.money2.goals.FinancialGoalResponse;
import com.webdigital.money2.goals.FinancialGoalStatus;
import com.webdigital.money2.goals.FinancialGoalType;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.Month;
import java.time.ZoneId;
import java.time.format.TextStyle;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class ChatRepository {

    private static final Locale BRAZIL = Locale.forLanguageTag("pt-BR");
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Cuiaba");

    private static final String FINANCIAL_CTE = """
            WITH accessible_clients AS MATERIALIZED (
                SELECT
                    c.id,
                    c.nome,
                    c.cgc_cpf,
                    COALESCE(NULLIF(c.telefone, ''), NULLIF(c.telefone2, '')) AS telefone,
                    c.regiao_id,
                    r.descricao AS regiao_descricao
                FROM cliente c
                JOIN regioes r ON r.id = c.regiao_id
                WHERE EXISTS (
                      SELECT 1 FROM regiao_usuario ur
                      WHERE ur.usuario_id = :userId
                        AND ur.regiao_id = c.regiao_id
                  )
            ),
            eligible_loans AS MATERIALIZED (
                SELECT e.id, e.cliente_id, COALESCE(e.valor_emprestado, 0) AS emprestado
                FROM emprestimo e
                JOIN accessible_clients c ON c.id = e.cliente_id
                WHERE COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                  AND e.status <> 3
                  AND COALESCE(e.refinanciado, false) = false
                  AND COALESCE(e.renovacao, false) = false
            ),
            payments AS MATERIALIZED (
                SELECT
                    pg.parcela_id,
                    COALESCE(SUM(pg.valor), 0) AS recebido,
                    COALESCE(SUM(pg.valor) FILTER (
                        WHERE COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'), 0) AS amortizado
                FROM pagamentos pg
                JOIN parcelas p ON p.id = pg.parcela_id
                JOIN eligible_loans e ON e.id = p.emprestimo_id
                WHERE COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                GROUP BY pg.parcela_id
            ),
            installment_values AS MATERIALIZED (
                SELECT
                    e.cliente_id,
                    e.id AS loan_id,
                    p.vencimento,
                    p.pendente,
                    GREATEST(
                        COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                        - COALESCE(pg.amortizado, 0), 0) AS saldo,
                    COALESCE(pg.recebido, 0) AS recebido
                FROM eligible_loans e
                JOIN parcelas p ON p.emprestimo_id = e.id
                LEFT JOIN payments pg ON pg.parcela_id = p.id
            ),
            installment_summary AS MATERIALIZED (
                SELECT
                    cliente_id,
                    COUNT(DISTINCT loan_id) FILTER (WHERE pendente = true AND saldo > 0) AS contratos,
                    COALESCE(SUM(saldo) FILTER (WHERE pendente = true), 0) AS receber,
                    COALESCE(SUM(saldo) FILTER (
                        WHERE pendente = true AND vencimento < CURRENT_DATE), 0) AS atrasado,
                    COALESCE(SUM(saldo) FILTER (
                        WHERE pendente = true
                          AND vencimento >= CURRENT_DATE
                          AND vencimento < CURRENT_DATE + INTERVAL '1 day'), 0) AS vence_hoje,
                    COALESCE(SUM(recebido), 0) AS recebido
                FROM installment_values
                GROUP BY cliente_id
            ),
            loan_summary AS MATERIALIZED (
                SELECT cliente_id, COALESCE(SUM(emprestado), 0) AS emprestado
                FROM eligible_loans
                GROUP BY cliente_id
            ),
            client_financial AS MATERIALIZED (
                SELECT
                    c.*,
                    COALESCE(i.contratos, 0) AS contratos,
                    COALESCE(l.emprestado, 0) AS emprestado,
                    COALESCE(i.recebido, 0) AS recebido,
                    COALESCE(i.receber, 0) AS receber,
                    COALESCE(i.atrasado, 0) AS atrasado,
                    COALESCE(i.vence_hoje, 0) AS vence_hoje
                FROM accessible_clients c
                LEFT JOIN installment_summary i ON i.cliente_id = c.id
                LEFT JOIN loan_summary l ON l.cliente_id = c.id
            )
            """;

    private final NamedParameterJdbcTemplate jdbc;
    private final FinancialGoalProgressRepository goalProgress;

    public ChatRepository(
            NamedParameterJdbcTemplate jdbc,
            FinancialGoalProgressRepository goalProgress) {
        this.jdbc = jdbc;
        this.goalProgress = goalProgress;
    }

    public List<Long> accessibleRegionIds(long userId) {
        return jdbc.query("""
                SELECT DISTINCT regiao_id
                FROM regiao_usuario
                WHERE usuario_id = :userId AND regiao_id IS NOT NULL
                ORDER BY regiao_id
                """, Map.of("userId", userId),
                (result, row) -> result.getLong("regiao_id"));
    }

    public List<ChatRegionOption> accessibleRegions(long userId) {
        return jdbc.query("""
                SELECT DISTINCT
                    r.id,
                    COALESCE(NULLIF(TRIM(r.descricao), ''), 'Região #' || r.id) AS descricao
                FROM regiao_usuario ur
                JOIN regioes r ON r.id = ur.regiao_id
                WHERE ur.usuario_id = :userId
                ORDER BY descricao, r.id
                """, Map.of("userId", userId),
                (result, row) -> new ChatRegionOption(
                        result.getLong("id"),
                        result.getString("descricao")));
    }

    public List<IndexedClient> indexableClients() {
        return jdbc.query("""
                SELECT
                    c.id, c.nome, c.razao, c.cgc_cpf, c.telefone, c.telefone2,
                    c.regiao_id, r.descricao AS regiao_descricao
                FROM cliente c
                JOIN regioes r ON r.id = c.regiao_id
                WHERE c.ativo = true
                ORDER BY c.id
                """, Map.of(), (result, row) -> indexed(result));
    }

    public IndexedClient indexableClient(Long clientId) {
        List<IndexedClient> result = jdbc.query("""
                SELECT
                    c.id, c.nome, c.razao, c.cgc_cpf, c.telefone, c.telefone2,
                    c.regiao_id, r.descricao AS regiao_descricao
                FROM cliente c
                JOIN regioes r ON r.id = c.regiao_id
                WHERE c.ativo = true AND c.id = :clientId
                """, Map.of("clientId", clientId), (row, index) -> indexed(row));
        return result.isEmpty() ? null : result.get(0);
    }

    public List<IndexedFinancialContract> indexableFinancialContracts() {
        return jdbc.query("""
                WITH installment_status AS (
                    SELECT
                        p.emprestimo_id,
                        COUNT(*) FILTER (WHERE p.pendente = true) AS pending_count,
                        COUNT(*) FILTER (
                            WHERE p.pendente = true AND p.vencimento::date < CURRENT_DATE
                        ) AS overdue_count
                    FROM parcelas p
                    GROUP BY p.emprestimo_id
                )
                SELECT
                    e.id,
                    c.regiao_id,
                    COALESCE(NULLIF(TRIM(r.descricao), ''), 'Região #' || r.id) AS regiao,
                    COALESCE(NULLIF(TRIM(c.nome), ''), 'Cliente #' || c.id) AS cliente,
                    CASE e.tipo
                        WHEN 'D' THEN 'Diário'
                        WHEN 'S' THEN 'Semanal'
                        WHEN 'Q' THEN 'Quinzenal'
                        WHEN 'M' THEN 'Mensal'
                        WHEN 'Z' THEN 'Diário Seg-Sab'
                        WHEN 'A' THEN 'Dia sim e dia não'
                        WHEN 'B' THEN 'Todo sábado'
                        WHEN 'C' THEN 'Todo domingo'
                        ELSE 'Empréstimo'
                    END AS tipo,
                    CASE
                        WHEN COALESCE(e.aprovacao_status, 'APROVADO') = 'PENDENTE' THEN 'Pendente aprovação'
                        WHEN e.status = 3 THEN 'Cancelado'
                        WHEN COALESCE(e.refinanciado, false) THEN 'Refinanciado'
                        WHEN COALESCE(e.renovacao, false) THEN 'Renovado'
                        WHEN COALESCE(s.overdue_count, 0) > 0 THEN 'Em atraso'
                        WHEN COALESCE(s.pending_count, 0) = 0 THEN 'Quitado'
                        ELSE 'Em dia'
                    END AS situacao
                FROM emprestimo e
                JOIN cliente c ON c.id = e.cliente_id
                JOIN regioes r ON r.id = c.regiao_id
                LEFT JOIN installment_status s ON s.emprestimo_id = e.id
                ORDER BY e.id
                """, Map.of(), (row, index) -> new IndexedFinancialContract(
                row.getLong("id"),
                row.getLong("regiao_id"),
                clean(row.getString("regiao")),
                clean(row.getString("cliente")),
                clean(row.getString("tipo")),
                clean(row.getString("situacao"))));
    }

    public List<ChatClientResponse> clientsByIds(long userId, List<Long> ids, int limit) {
        if (ids == null || ids.isEmpty()) return List.of();
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("userId", userId);
        parameters.put("ids", ids);
        parameters.put("limit", Math.max(1, Math.min(limit, 25)));
        List<ChatClientResponse> rows = jdbc.query(FINANCIAL_CTE + """
                SELECT * FROM client_financial
                WHERE id IN (:ids)
                LIMIT :limit
                """, parameters, (result, row) -> client(result));
        Map<Long, ChatClientResponse> byId = new HashMap<>();
        for (ChatClientResponse item : rows) byId.put(item.id(), item);
        return ids.stream().map(byId::get).filter(item -> item != null).limit(limit).toList();
    }

    public List<ChatClientResponse> searchClients(long userId, String query, int limit) {
        String clean = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
        String digits = clean.replaceAll("[^0-9]", "");
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("userId", userId);
        parameters.put("search", "%" + clean + "%");
        parameters.put("digits", digits);
        parameters.put("digitSearch", "%" + digits + "%");
        parameters.put("limit", Math.max(1, Math.min(limit, 51)));
        return jdbc.query(FINANCIAL_CTE + """
                SELECT * FROM client_financial
                WHERE translate(
                          lower(COALESCE(nome, '')),
                          'áàâãäåéèêëíìîïóòôõöúùûüçñ',
                          'aaaaaaeeeeiiiiooooouuuucn') LIKE :search
                   OR lower(COALESCE(cgc_cpf, '')) LIKE :search
                   OR lower(COALESCE(telefone, '')) LIKE :search
                   OR CAST(id AS text) LIKE :search
                   OR (:digits <> '' AND (
                       regexp_replace(COALESCE(cgc_cpf, ''), '[^0-9]', '', 'g') LIKE :digitSearch
                       OR regexp_replace(COALESCE(telefone, ''), '[^0-9]', '', 'g') LIKE :digitSearch))
                ORDER BY lower(COALESCE(nome, '')), id
                LIMIT :limit
                """, parameters, (result, row) -> client(result));
    }

    public List<ChatClientResponse> dueToday(long userId, int limit) {
        return dueToday(userId, null, limit);
    }

    public List<ChatClientResponse> dueToday(long userId, Long regionId, int limit) {
        return listByFinancialCondition(userId, regionId, "vence_hoje > 0", limit);
    }

    public List<ChatClientResponse> overdue(long userId, int limit) {
        return overdue(userId, null, limit);
    }

    public List<ChatClientResponse> overdue(long userId, Long regionId, int limit) {
        return listByFinancialCondition(userId, regionId, "atrasado > 0", limit);
    }

    public List<ChatLoanResponse> dueTodayLoans(long userId, long regionId) {
        return regionalLoans(userId, regionId, true);
    }

    public List<ChatLoanResponse> overdueLoans(long userId, long regionId) {
        return regionalLoans(userId, regionId, false);
    }

    public ChatFinancialSummaryResponse summary(long userId) {
        return summary(userId, null);
    }

    public ChatFinancialSummaryResponse summary(long userId, Long regionId) {
        return summary(userId, regionId, null, null);
    }

    public ChatFinancialSummaryResponse summary(
            long userId,
            Long regionId,
            LocalDate startDate,
            LocalDate endDate) {
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("userId", userId);
        parameters.put("regionId", regionId);
        parameters.put("startDate", startDate);
        parameters.put("endDate", endDate);
        ChatFinancialSummaryResponse result = jdbc.queryForObject("""
                WITH accessible_loans AS MATERIALIZED (
                    SELECT
                        e.id,
                        e.cliente_id,
                        e.status,
                        e.data,
                        COALESCE(e.valor_emprestado, 0) AS emprestado
                    FROM emprestimo e
                    JOIN cliente c ON c.id = e.cliente_id
                    WHERE (CAST(:regionId AS bigint) IS NULL OR c.regiao_id = :regionId)
                      AND EXISTS (
                          SELECT 1 FROM regiao_usuario ur
                          WHERE ur.usuario_id = :userId
                            AND ur.regiao_id = c.regiao_id
                      )
                      AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND e.status <> 3
                      AND COALESCE(e.refinanciado, false) = false
                      AND COALESCE(e.renovacao, false) = false
                ),
                profit_loans AS MATERIALIZED (
                    SELECT
                        e.id,
                        COALESCE(e.valor_emprestado, 0) AS capital
                    FROM emprestimo e
                    JOIN cliente c ON c.id = e.cliente_id
                    WHERE (CAST(:regionId AS bigint) IS NULL OR c.regiao_id = :regionId)
                      AND EXISTS (
                          SELECT 1 FROM regiao_usuario ur
                          WHERE ur.usuario_id = :userId
                            AND ur.regiao_id = c.regiao_id
                      )
                      AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND e.status <> 3
                ),
                period_loans AS MATERIALIZED (
                    SELECT *
                    FROM accessible_loans
                    WHERE (CAST(:startDate AS date) IS NULL OR data >= :startDate)
                      AND (CAST(:endDate AS date) IS NULL
                           OR data < CAST(:endDate AS date) + INTERVAL '1 day')
                ),
                payments AS MATERIALIZED (
                    SELECT
                        pg.parcela_id,
                        COALESCE(SUM(pg.valor), 0) AS recebido,
                        COALESCE(SUM(pg.valor) FILTER (
                            WHERE COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'), 0) AS amortizado
                    FROM pagamentos pg
                    JOIN parcelas p ON p.id = pg.parcela_id
                    JOIN accessible_loans e ON e.id = p.emprestimo_id
                    WHERE COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                    GROUP BY pg.parcela_id
                ),
                received_period AS MATERIALIZED (
                    SELECT COALESCE(SUM(pg.valor), 0) AS valor
                    FROM pagamentos pg
                    JOIN parcelas p ON p.id = pg.parcela_id
                    JOIN accessible_loans e ON e.id = p.emprestimo_id
                    WHERE COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND (CAST(:startDate AS date) IS NULL OR pg.data >= :startDate)
                      AND (CAST(:endDate AS date) IS NULL
                           OR pg.data < CAST(:endDate AS date) + INTERVAL '1 day')
                ),
                profit_payments AS MATERIALIZED (
                    SELECT
                        e.id AS emprestimo_id,
                        COALESCE(SUM(pg.valor) FILTER (
                            WHERE CAST(:startDate AS date) IS NOT NULL
                              AND pg.data < :startDate
                        ), 0) AS recebido_antes,
                        COALESCE(SUM(pg.valor) FILTER (
                            WHERE (CAST(:startDate AS date) IS NULL OR pg.data >= :startDate)
                              AND (CAST(:endDate AS date) IS NULL
                                   OR pg.data < CAST(:endDate AS date) + INTERVAL '1 day')
                        ), 0) AS recebido_periodo
                    FROM profit_loans e
                    LEFT JOIN parcelas p ON p.emprestimo_id = e.id
                    LEFT JOIN pagamentos pg
                      ON pg.parcela_id = p.id
                     AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                    GROUP BY e.id
                ),
                profit_period AS MATERIALIZED (
                    SELECT COALESCE(SUM(
                        GREATEST(
                            pp.recebido_antes + pp.recebido_periodo - e.capital, 0
                        ) - GREATEST(pp.recebido_antes - e.capital, 0)
                    ), 0) AS valor
                    FROM profit_loans e
                    JOIN profit_payments pp ON pp.emprestimo_id = e.id
                ),
                loan_balances AS MATERIALIZED (
                    SELECT
                        e.id,
                        e.cliente_id,
                        COALESCE(SUM(GREATEST(
                            COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                            - COALESCE(pg.amortizado, 0), 0
                        )) FILTER (WHERE p.pendente = true), 0) AS receber,
                        COALESCE(SUM(GREATEST(
                            COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                            - COALESCE(pg.amortizado, 0), 0
                        )) FILTER (
                            WHERE p.pendente = true AND p.vencimento < CURRENT_DATE
                        ), 0) AS atrasado
                    FROM period_loans e
                    LEFT JOIN parcelas p ON p.emprestimo_id = e.id
                    LEFT JOIN payments pg ON pg.parcela_id = p.id
                    GROUP BY e.id, e.cliente_id
                )
                SELECT
                    COUNT(DISTINCT cliente_id) FILTER (WHERE receber > 0) AS clientes,
                    COUNT(*) FILTER (WHERE receber > 0) AS contratos,
                    COALESCE((SELECT SUM(emprestado) FROM period_loans), 0) AS emprestado,
                    COALESCE((SELECT valor FROM received_period), 0) AS recebido,
                    COALESCE(SUM(receber), 0) AS receber,
                    COALESCE(SUM(atrasado), 0) AS atrasado,
                    COALESCE((SELECT valor FROM profit_period), 0) AS lucro
                FROM loan_balances
                """, parameters, (resultSet, row) ->
                new ChatFinancialSummaryResponse(
                        resultSet.getLong("clientes"),
                        resultSet.getLong("contratos"),
                        money(resultSet.getBigDecimal("emprestado")),
                        money(resultSet.getBigDecimal("recebido")),
                        money(resultSet.getBigDecimal("receber")),
                        money(resultSet.getBigDecimal("atrasado")),
                        money(resultSet.getBigDecimal("lucro"))));
        return result == null
                ? new ChatFinancialSummaryResponse(
                        0, 0, zero(), zero(), zero(), zero(), zero())
                : result;
    }

    public List<ChatRegionProfitSnapshot> profitRanking(
            long userId,
            LocalDate startDate,
            LocalDate endDate) {
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("userId", userId);
        parameters.put("startDate", startDate);
        parameters.put("endDate", endDate);
        return jdbc.query("""
                WITH accessible_regions AS MATERIALIZED (
                    SELECT DISTINCT r.id, r.descricao
                    FROM regiao_usuario ur
                    JOIN regioes r ON r.id = ur.regiao_id
                    WHERE ur.usuario_id = :userId
                ), profit_loans AS MATERIALIZED (
                    SELECT
                        e.id,
                        c.regiao_id,
                        COALESCE(e.valor_emprestado, 0) AS capital
                    FROM emprestimo e
                    JOIN cliente c ON c.id = e.cliente_id
                    JOIN accessible_regions r ON r.id = c.regiao_id
                    WHERE COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND e.status <> 3
                ), profit_payments AS MATERIALIZED (
                    SELECT
                        e.id AS emprestimo_id,
                        e.regiao_id,
                        e.capital,
                        COALESCE(SUM(pg.valor) FILTER (
                            WHERE CAST(:startDate AS date) IS NOT NULL
                              AND pg.data < :startDate
                        ), 0) AS recebido_antes,
                        COALESCE(SUM(pg.valor) FILTER (
                            WHERE (CAST(:startDate AS date) IS NULL OR pg.data >= :startDate)
                              AND (CAST(:endDate AS date) IS NULL
                                   OR pg.data < CAST(:endDate AS date) + INTERVAL '1 day')
                        ), 0) AS recebido_periodo
                    FROM profit_loans e
                    LEFT JOIN parcelas p ON p.emprestimo_id = e.id
                    LEFT JOIN pagamentos pg
                      ON pg.parcela_id = p.id
                     AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                    GROUP BY e.id, e.regiao_id, e.capital
                ), region_profit AS (
                    SELECT
                        regiao_id,
                        COALESCE(SUM(
                            GREATEST(recebido_antes + recebido_periodo - capital, 0)
                            - GREATEST(recebido_antes - capital, 0)
                        ), 0) AS lucro
                    FROM profit_payments
                    GROUP BY regiao_id
                )
                SELECT
                    r.id,
                    COALESCE(NULLIF(TRIM(r.descricao), ''), 'Região #' || r.id) AS regiao,
                    COALESCE(p.lucro, 0) AS lucro
                FROM accessible_regions r
                LEFT JOIN region_profit p ON p.regiao_id = r.id
                ORDER BY lucro DESC, lower(COALESCE(r.descricao, '')), r.id
                """, parameters, (row, index) -> new ChatRegionProfitSnapshot(
                row.getLong("id"),
                clean(row.getString("regiao")),
                money(row.getBigDecimal("lucro"))));
    }

    public ChatLoanStatusResponse loanStatus(
            long userId,
            long regionId,
            LocalDate startDate,
            LocalDate endDate) {
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("userId", userId);
        parameters.put("regionId", regionId);
        parameters.put("startDate", startDate);
        parameters.put("endDate", endDate);
        ChatLoanStatusResponse result = jdbc.queryForObject("""
                WITH period_loans AS MATERIALIZED (
                    SELECT
                        e.id,
                        e.status,
                        COALESCE(e.valor_emprestado, 0) AS emprestado
                    FROM emprestimo e
                    JOIN cliente c ON c.id = e.cliente_id
                    WHERE c.regiao_id = :regionId
                      AND EXISTS (
                          SELECT 1 FROM regiao_usuario ur
                          WHERE ur.usuario_id = :userId
                            AND ur.regiao_id = c.regiao_id
                      )
                      AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND e.status <> 3
                      AND COALESCE(e.refinanciado, false) = false
                      AND COALESCE(e.renovacao, false) = false
                      AND (CAST(:startDate AS date) IS NULL OR e.data >= :startDate)
                      AND (CAST(:endDate AS date) IS NULL
                           OR e.data < CAST(:endDate AS date) + INTERVAL '1 day')
                ),
                payments AS MATERIALIZED (
                    SELECT
                        pg.parcela_id,
                        COALESCE(SUM(pg.valor) FILTER (
                            WHERE COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'), 0) AS amortizado
                    FROM pagamentos pg
                    JOIN parcelas p ON p.id = pg.parcela_id
                    JOIN period_loans e ON e.id = p.emprestimo_id
                    WHERE COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                    GROUP BY pg.parcela_id
                ),
                loan_values AS MATERIALIZED (
                    SELECT
                        e.id,
                        e.status,
                        e.emprestado,
                        COALESCE(SUM(GREATEST(
                            COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                            - COALESCE(pg.amortizado, 0), 0
                        )) FILTER (WHERE p.pendente = true), 0) AS receber,
                        COALESCE(SUM(GREATEST(
                            COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                            - COALESCE(pg.amortizado, 0), 0
                        )) FILTER (
                            WHERE p.pendente = true AND p.vencimento < CURRENT_DATE
                        ), 0) AS atrasado
                    FROM period_loans e
                    LEFT JOIN parcelas p ON p.emprestimo_id = e.id
                    LEFT JOIN payments pg ON pg.parcela_id = p.id
                    GROUP BY e.id, e.status, e.emprestado
                ),
                categorized AS MATERIALIZED (
                    SELECT *, CASE
                        WHEN atrasado > 0 THEN 'ATRASADO'
                        WHEN status = 1 THEN 'EM_DIA'
                        WHEN receber <= 0 THEN 'QUITADO'
                        ELSE 'EM_DIA'
                    END AS categoria
                    FROM loan_values
                )
                SELECT
                    COUNT(*) FILTER (WHERE categoria = 'ATRASADO'),
                    COALESCE(SUM(atrasado) FILTER (WHERE categoria = 'ATRASADO'), 0),
                    COUNT(*) FILTER (WHERE categoria = 'EM_DIA'),
                    COALESCE(SUM(receber) FILTER (WHERE categoria = 'EM_DIA'), 0),
                    COUNT(*) FILTER (WHERE categoria = 'QUITADO'),
                    COALESCE(SUM(emprestado) FILTER (WHERE categoria = 'QUITADO'), 0)
                FROM categorized
                """, parameters, (row, index) -> new ChatLoanStatusResponse(
                row.getLong(1), money(row.getBigDecimal(2)),
                row.getLong(3), money(row.getBigDecimal(4)),
                row.getLong(5), money(row.getBigDecimal(6))));
        return result == null
                ? new ChatLoanStatusResponse(0, zero(), 0, zero(), 0, zero())
                : result;
    }

    public ChatClientStatusResponse clientStatus(long userId, long regionId) {
        ChatClientStatusResponse result = jdbc.queryForObject("""
                WITH accessible_clients AS MATERIALIZED (
                    SELECT c.id
                    FROM cliente c
                    WHERE c.regiao_id = :regionId
                      AND EXISTS (
                          SELECT 1 FROM regiao_usuario ur
                          WHERE ur.usuario_id = :userId
                            AND ur.regiao_id = c.regiao_id
                      )
                ), loan_flags AS MATERIALIZED (
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
                ), classified AS MATERIALIZED (
                    SELECT CASE
                        WHEN COALESCE(lf.is_missing, false) THEN 'MISSING'
                        WHEN COALESCE(lf.has_open_loan, false) THEN 'ACTIVE'
                        ELSE 'INACTIVE'
                    END AS client_status
                    FROM accessible_clients c
                    LEFT JOIN loan_flags lf ON lf.cliente_id = c.id
                )
                SELECT
                    COUNT(*) FILTER (WHERE client_status = 'ACTIVE'),
                    COUNT(*) FILTER (WHERE client_status = 'INACTIVE'),
                    COUNT(*) FILTER (WHERE client_status = 'MISSING')
                FROM classified
                """, Map.of("userId", userId, "regionId", regionId), (row, index) ->
                new ChatClientStatusResponse(
                        row.getLong(1), row.getLong(2), row.getLong(3)));
        return result == null ? new ChatClientStatusResponse(0, 0, 0) : result;
    }

    public List<ChatMonthOption> availableSummaryMonths(long userId, long regionId) {
        List<ChatMonthOption> months = jdbc.query("""
                WITH accessible_clients AS MATERIALIZED (
                    SELECT c.id
                    FROM cliente c
                    WHERE c.regiao_id = :regionId
                      AND EXISTS (
                          SELECT 1 FROM regiao_usuario ur
                          WHERE ur.usuario_id = :userId AND ur.regiao_id = c.regiao_id
                      )
                ), available_dates AS (
                    SELECT e.data::date AS value
                    FROM emprestimo e
                    JOIN accessible_clients c ON c.id = e.cliente_id
                    WHERE e.data IS NOT NULL
                      AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                    UNION
                    SELECT pg.data::date AS value
                    FROM pagamentos pg
                    JOIN parcelas p ON p.id = pg.parcela_id
                    JOIN emprestimo e ON e.id = p.emprestimo_id
                    JOIN accessible_clients c ON c.id = e.cliente_id
                    WHERE pg.data IS NOT NULL
                      AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                )
                SELECT DISTINCT
                    EXTRACT(YEAR FROM value)::integer AS ano,
                    EXTRACT(MONTH FROM value)::integer AS mes
                FROM available_dates
                ORDER BY ano DESC, mes DESC
                """, Map.of("userId", userId, "regionId", regionId), (row, index) -> {
            int year = row.getInt("ano");
            int month = row.getInt("mes");
            return new ChatMonthOption(year, month, monthLabel(year, month));
        });
        if (!months.isEmpty()) return months;
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        return List.of(new ChatMonthOption(
                today.getYear(), today.getMonthValue(),
                monthLabel(today.getYear(), today.getMonthValue())));
    }

    public List<FinancialGoalResponse> activeFinancialGoals(long userId, long regionId) {
        List<GoalSnapshot> goals = jdbc.query("""
                SELECT DISTINCT ON (goal.tipo)
                    goal.id,
                    goal.regiao_id,
                    COALESCE(NULLIF(TRIM(region.descricao), ''), 'Região #' || region.id) AS regiao,
                    goal.tipo,
                    goal.valor_meta,
                    goal.data_inicio,
                    goal.data_fim,
                    goal.dtcad,
                    goal.dtalter
                FROM money2_metas_financeiras goal
                JOIN regioes region ON region.id = goal.regiao_id
                WHERE goal.regiao_id = :regionId
                  AND goal.tipo IN ('EMPRESTADO','RECEBIDO','LUCRO')
                  AND (
                      SELECT COUNT(link.regiao_id)
                      FROM money2_metas_financeiras_regioes link
                      WHERE link.meta_id = goal.id
                  ) = 1
                  AND CURRENT_DATE BETWEEN goal.data_inicio AND goal.data_fim
                  AND EXISTS (
                      SELECT 1 FROM regiao_usuario ur
                      WHERE ur.usuario_id = :userId AND ur.regiao_id = goal.regiao_id
                  )
                ORDER BY goal.tipo, goal.data_fim, goal.id DESC
                """, Map.of("userId", userId, "regionId", regionId), (row, index) ->
                new GoalSnapshot(
                        row.getLong("id"),
                        row.getLong("regiao_id"),
                        clean(row.getString("regiao")),
                        FinancialGoalType.valueOf(row.getString("tipo")),
                        money(row.getBigDecimal("valor_meta")),
                        row.getObject("data_inicio", LocalDate.class),
                        row.getObject("data_fim", LocalDate.class),
                        row.getTimestamp("dtcad").toLocalDateTime(),
                        row.getTimestamp("dtalter").toLocalDateTime()));
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        return goals.stream()
                .map(goal -> financialGoalResponse(goal, today))
                .toList();
    }

    public FinancialGoalResponse activeFinancialGoal(long userId, long regionId) {
        List<FinancialGoalResponse> goals = activeFinancialGoals(userId, regionId);
        return goals.isEmpty() ? null : goals.get(0);
    }

    private FinancialGoalResponse financialGoalResponse(GoalSnapshot goal, LocalDate today) {
        BigDecimal achieved = goalProgress.achieved(
                goal.type(), goal.regionId(), goal.startDate(), today);
        BigDecimal remaining = goal.targetAmount().subtract(achieved)
                .max(BigDecimal.ZERO).setScale(2, RoundingMode.HALF_UP);
        BigDecimal percentage = goal.targetAmount().signum() == 0
                ? zero()
                : achieved.multiply(BigDecimal.valueOf(100))
                        .divide(goal.targetAmount(), 2, RoundingMode.HALF_UP);
        return new FinancialGoalResponse(
                goal.id(), goal.regionId(), goal.regionName(), goal.type(),
                goal.targetAmount(), achieved, remaining, percentage,
                goal.startDate(), goal.endDate(), FinancialGoalStatus.ATIVA,
                goal.createdAt(), goal.updatedAt(), false,
                List.of(goal.regionId()), List.of(goal.regionName()));
    }

    public ChatPaymentSnapshot latestPayment(long userId, long clientId) {
        List<ChatPaymentSnapshot> rows = jdbc.query("""
                SELECT
                    e.id AS loan_id,
                    COALESCE(NULLIF(TRIM(p.parcela), ''), '-') AS parcela,
                    pg.data,
                    COALESCE(pg.valor, 0) AS valor,
                    COALESCE(NULLIF(TRIM(pg.tipo), ''), 'NORMAL') AS tipo
                FROM cliente c
                JOIN emprestimo e ON e.cliente_id = c.id
                JOIN parcelas p ON p.emprestimo_id = e.id
                JOIN pagamentos pg ON pg.parcela_id = p.id
                WHERE c.id = :clientId
                  AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                  AND EXISTS (
                      SELECT 1 FROM regiao_usuario ur
                      WHERE ur.usuario_id = :userId AND ur.regiao_id = c.regiao_id
                  )
                ORDER BY pg.data DESC NULLS LAST, pg.id_pagamento DESC
                LIMIT 1
                """, Map.of("userId", userId, "clientId", clientId), (result, row) ->
                new ChatPaymentSnapshot(
                        result.getLong("loan_id"),
                        result.getString("parcela"),
                        result.getTimestamp("data") == null
                                ? null
                                : result.getTimestamp("data").toLocalDateTime(),
                        money(result.getBigDecimal("valor")),
                        result.getString("tipo")));
        return rows.isEmpty() ? null : rows.get(0);
    }

    public ChatPaymentSnapshot latestPaymentForLoan(long userId, long loanId) {
        List<ChatPaymentSnapshot> rows = jdbc.query("""
                SELECT
                    e.id AS loan_id,
                    COALESCE(NULLIF(TRIM(p.parcela), ''), '-') AS parcela,
                    pg.data,
                    COALESCE(pg.valor, 0) AS valor,
                    COALESCE(NULLIF(TRIM(pg.tipo), ''), 'NORMAL') AS tipo
                FROM pagamentos pg
                LEFT JOIN parcelas p ON p.id = pg.parcela_id
                JOIN emprestimo e ON e.id = COALESCE(p.emprestimo_id, pg.emprestimo_id)
                JOIN cliente c ON c.id = e.cliente_id
                WHERE e.id = :loanId
                  AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                  AND EXISTS (
                      SELECT 1 FROM regiao_usuario ur
                      WHERE ur.usuario_id = :userId AND ur.regiao_id = c.regiao_id
                  )
                ORDER BY pg.data DESC NULLS LAST, pg.id_pagamento DESC
                LIMIT 1
                """, Map.of("userId", userId, "loanId", loanId), (result, row) ->
                new ChatPaymentSnapshot(
                        result.getLong("loan_id"),
                        result.getString("parcela"),
                        result.getTimestamp("data") == null
                                ? null
                                : result.getTimestamp("data").toLocalDateTime(),
                        money(result.getBigDecimal("valor")),
                        result.getString("tipo")));
        return rows.isEmpty() ? null : rows.get(0);
    }

    public ChatInstallmentSnapshot nextDue(long userId, long clientId) {
        List<ChatInstallmentSnapshot> rows = jdbc.query("""
                SELECT
                    e.id AS loan_id,
                    COALESCE(NULLIF(TRIM(p.parcela), ''), '-') AS parcela,
                    p.vencimento,
                    GREATEST(
                        COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                        - COALESCE((
                            SELECT SUM(pg.valor)
                            FROM pagamentos pg
                            WHERE pg.parcela_id = p.id
                              AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                              AND COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                        ), 0),
                        0
                    ) AS saldo
                FROM cliente c
                JOIN emprestimo e ON e.cliente_id = c.id
                JOIN parcelas p ON p.emprestimo_id = e.id
                WHERE c.id = :clientId
                  AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                  AND e.status <> 3
                  AND COALESCE(e.refinanciado, false) = false
                  AND COALESCE(e.renovacao, false) = false
                  AND p.pendente = true
                  AND EXISTS (
                      SELECT 1 FROM regiao_usuario ur
                      WHERE ur.usuario_id = :userId AND ur.regiao_id = c.regiao_id
                  )
                  AND GREATEST(
                      COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                      - COALESCE((
                          SELECT SUM(pg.valor)
                          FROM pagamentos pg
                          WHERE pg.parcela_id = p.id
                            AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                            AND COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                      ), 0),
                      0
                  ) > 0
                ORDER BY p.vencimento, p.id
                LIMIT 1
                """, Map.of("userId", userId, "clientId", clientId), (result, row) ->
                new ChatInstallmentSnapshot(
                        result.getLong("loan_id"),
                        result.getString("parcela"),
                        result.getTimestamp("vencimento") == null
                                ? null
                                : result.getTimestamp("vencimento").toLocalDateTime(),
                        money(result.getBigDecimal("saldo"))));
        return rows.isEmpty() ? null : rows.get(0);
    }

    public long openInstallmentCount(long userId, long clientId) {
        Long count = jdbc.queryForObject("""
                SELECT COUNT(*)
                FROM cliente c
                JOIN emprestimo e ON e.cliente_id = c.id
                JOIN parcelas p ON p.emprestimo_id = e.id
                WHERE c.id = :clientId
                  AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                  AND e.status <> 3
                  AND COALESCE(e.refinanciado, false) = false
                  AND COALESCE(e.renovacao, false) = false
                  AND p.pendente = true
                  AND EXISTS (
                      SELECT 1 FROM regiao_usuario ur
                      WHERE ur.usuario_id = :userId AND ur.regiao_id = c.regiao_id
                  )
                  AND GREATEST(
                      COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                      - COALESCE((
                          SELECT SUM(pg.valor)
                          FROM pagamentos pg
                          WHERE pg.parcela_id = p.id
                            AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                            AND COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                      ), 0),
                      0
                  ) > 0
                """, Map.of("userId", userId, "clientId", clientId), Long.class);
        return count == null ? 0 : count;
    }

    public List<ChatLoanResponse> activeLoanResults(long userId, long clientId, int limit) {
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("userId", userId);
        parameters.put("clientId", clientId);
        parameters.put("limit", Math.max(1, Math.min(limit, 100)));
        return jdbc.query("""
                WITH eligible_loans AS MATERIALIZED (
                    SELECT
                        e.id,
                        e.tipo,
                        c.nome AS cliente,
                        c.regiao_id,
                        r.descricao AS regiao
                    FROM cliente c
                    JOIN emprestimo e ON e.cliente_id = c.id
                    JOIN regioes r ON r.id = c.regiao_id
                    WHERE c.id = :clientId
                      AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND e.status <> 3
                      AND COALESCE(e.refinanciado, false) = false
                      AND COALESCE(e.renovacao, false) = false
                      AND EXISTS (
                          SELECT 1 FROM regiao_usuario ur
                          WHERE ur.usuario_id = :userId AND ur.regiao_id = c.regiao_id
                      )
                ), payments AS MATERIALIZED (
                    SELECT
                        pg.parcela_id,
                        COALESCE(SUM(pg.valor) FILTER (
                            WHERE COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                        ), 0) AS amortizado
                    FROM pagamentos pg
                    JOIN parcelas p ON p.id = pg.parcela_id
                    JOIN eligible_loans e ON e.id = p.emprestimo_id
                    WHERE COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                    GROUP BY pg.parcela_id
                ), installment_values AS MATERIALIZED (
                    SELECT
                        e.id AS loan_id,
                        p.id AS installment_id,
                        p.vencimento,
                        p.pendente,
                        GREATEST(
                            COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                            - COALESCE(pg.amortizado, 0), 0
                        ) AS saldo
                    FROM eligible_loans e
                    LEFT JOIN parcelas p ON p.emprestimo_id = e.id
                    LEFT JOIN payments pg ON pg.parcela_id = p.id
                ), loan_values AS MATERIALIZED (
                    SELECT
                        e.id,
                        e.tipo,
                        e.cliente,
                        e.regiao_id,
                        e.regiao,
                        MIN(i.vencimento) FILTER (
                            WHERE i.pendente = true AND i.saldo > 0
                        )::date AS proximo_vencimento,
                        COUNT(i.installment_id) FILTER (
                            WHERE i.pendente = true AND i.saldo > 0
                        ) AS parcelas_abertas,
                        COALESCE(SUM(i.saldo) FILTER (
                            WHERE i.pendente = true
                        ), 0) AS saldo,
                        COUNT(i.installment_id) FILTER (
                            WHERE i.pendente = true AND i.saldo > 0
                              AND i.vencimento::date < CURRENT_DATE
                        ) AS parcelas_atrasadas,
                        COUNT(i.installment_id) FILTER (
                            WHERE i.pendente = true AND i.saldo > 0
                              AND i.vencimento::date = CURRENT_DATE
                        ) AS parcelas_hoje
                    FROM eligible_loans e
                    LEFT JOIN installment_values i ON i.loan_id = e.id
                    GROUP BY e.id, e.tipo, e.cliente, e.regiao_id, e.regiao
                )
                SELECT *
                FROM loan_values
                WHERE saldo > 0
                ORDER BY
                    CASE WHEN parcelas_atrasadas > 0 THEN 0
                         WHEN parcelas_hoje > 0 THEN 1 ELSE 2 END,
                    proximo_vencimento NULLS LAST,
                    id DESC
                LIMIT :limit
                """, parameters, (row, index) -> new ChatLoanResponse(
                row.getLong("id"),
                clean(row.getString("cliente")),
                clean(row.getString("regiao")),
                paymentTypeLabel(row.getString("tipo")),
                row.getObject("proximo_vencimento", LocalDate.class),
                row.getLong("parcelas_abertas"),
                money(row.getBigDecimal("saldo")),
                row.getLong("parcelas_atrasadas") > 0 ? "ATRASADO"
                        : row.getLong("parcelas_hoje") > 0 ? "VENCE_HOJE" : "EM_DIA"));
    }

    private List<ChatLoanResponse> regionalLoans(
            long userId,
            long regionId,
            boolean dueToday) {
        String dateCondition = dueToday
                ? "p.vencimento::date = CURRENT_DATE"
                : "p.vencimento::date < CURRENT_DATE";
        String status = dueToday ? "VENCE_HOJE" : "ATRASADO";
        String sql = """
                WITH eligible_loans AS MATERIALIZED (
                    SELECT e.id, e.cliente_id, e.tipo
                    FROM emprestimo e
                    JOIN cliente c ON c.id = e.cliente_id
                    WHERE c.regiao_id = :regionId
                      AND EXISTS (
                          SELECT 1 FROM regiao_usuario ur
                          WHERE ur.usuario_id = :userId AND ur.regiao_id = c.regiao_id
                      )
                      AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND e.status <> 3
                      AND COALESCE(e.refinanciado, false) = false
                      AND COALESCE(e.renovacao, false) = false
                ),
                payments AS MATERIALIZED (
                    SELECT
                        pg.parcela_id,
                        COALESCE(SUM(pg.valor) FILTER (
                            WHERE COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'), 0) AS amortizado
                    FROM pagamentos pg
                    JOIN parcelas p ON p.id = pg.parcela_id
                    JOIN eligible_loans e ON e.id = p.emprestimo_id
                    WHERE COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                    GROUP BY pg.parcela_id
                )
                SELECT
                    e.id,
                    COALESCE(NULLIF(TRIM(c.nome), ''), 'Cliente #' || c.id) AS cliente,
                    COALESCE(NULLIF(TRIM(r.descricao), ''), 'Região #' || r.id) AS regiao,
                    CASE e.tipo
                        WHEN 'D' THEN 'Diário'
                        WHEN 'S' THEN 'Semanal'
                        WHEN 'Q' THEN 'Quinzenal'
                        WHEN 'M' THEN 'Mensal'
                        WHEN 'Z' THEN 'Diário Seg-Sab'
                        WHEN 'A' THEN 'Dia sim e dia não'
                        WHEN 'B' THEN 'Todo sábado'
                        WHEN 'C' THEN 'Todo domingo'
                        ELSE 'Empréstimo'
                    END AS tipo,
                    MIN(p.vencimento)::date AS vencimento,
                    COUNT(*) AS parcelas,
                    SUM(GREATEST(
                        COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                        - COALESCE(pg.amortizado, 0), 0
                    )) AS valor
                FROM eligible_loans e
                JOIN cliente c ON c.id = e.cliente_id
                JOIN regioes r ON r.id = c.regiao_id
                JOIN parcelas p ON p.emprestimo_id = e.id AND p.pendente = true
                LEFT JOIN payments pg ON pg.parcela_id = p.id
                WHERE %s
                GROUP BY e.id, c.id, c.nome, r.id, r.descricao, e.tipo
                HAVING SUM(GREATEST(
                    COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0)
                    - COALESCE(pg.amortizado, 0), 0
                )) > 0
                ORDER BY MIN(p.vencimento), lower(COALESCE(c.nome, '')), e.id
                """.formatted(dateCondition);
        return jdbc.query(sql, Map.of("userId", userId, "regionId", regionId),
                (row, index) -> new ChatLoanResponse(
                        row.getLong("id"),
                        clean(row.getString("cliente")),
                        clean(row.getString("regiao")),
                        clean(row.getString("tipo")),
                        row.getObject("vencimento", LocalDate.class),
                        row.getLong("parcelas"),
                        money(row.getBigDecimal("valor")),
                        status));
    }

    private List<ChatClientResponse> listByFinancialCondition(
            long userId,
            Long regionId,
            String condition,
            int limit) {
        String metric = condition.startsWith("vence_hoje") ? "vence_hoje" : "atrasado";
        String sql = FINANCIAL_CTE
                + "SELECT * FROM client_financial WHERE " + condition
                + " AND (CAST(:regionId AS bigint) IS NULL OR regiao_id = :regionId)"
                + " ORDER BY " + metric
                + " DESC, lower(COALESCE(nome, '')) LIMIT :limit";
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("userId", userId);
        parameters.put("regionId", regionId);
        parameters.put("limit", Math.max(1, Math.min(limit, 25)));
        return jdbc.query(sql, parameters,
                (result, row) -> client(result));
    }

    private static IndexedClient indexed(java.sql.ResultSet result) throws java.sql.SQLException {
        return new IndexedClient(
                result.getLong("id"),
                clean(result.getString("nome")),
                nullable(result.getString("razao")),
                nullable(result.getString("cgc_cpf")),
                nullable(result.getString("telefone")),
                nullable(result.getString("telefone2")),
                result.getLong("regiao_id"),
                clean(result.getString("regiao_descricao")));
    }

    private static ChatClientResponse client(java.sql.ResultSet result) throws java.sql.SQLException {
        return new ChatClientResponse(
                result.getLong("id"),
                clean(result.getString("nome")),
                nullable(result.getString("cgc_cpf")),
                nullable(result.getString("telefone")),
                result.getLong("regiao_id"),
                clean(result.getString("regiao_descricao")),
                result.getLong("contratos"),
                money(result.getBigDecimal("emprestado")),
                money(result.getBigDecimal("recebido")),
                money(result.getBigDecimal("receber")),
                money(result.getBigDecimal("atrasado")),
                money(result.getBigDecimal("vence_hoje")));
    }

    private static BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value).setScale(2, RoundingMode.HALF_UP);
    }

    private static BigDecimal zero() {
        return BigDecimal.ZERO.setScale(2);
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static String nullable(String value) {
        String clean = clean(value);
        return clean.isEmpty() ? null : clean;
    }

    private static String monthLabel(int year, int month) {
        String name = Month.of(month).getDisplayName(TextStyle.FULL, BRAZIL);
        return Character.toUpperCase(name.charAt(0)) + name.substring(1) + " de " + year;
    }

    private static String paymentTypeLabel(String type) {
        return switch (clean(type).toUpperCase(Locale.ROOT)) {
            case "D" -> "Diário";
            case "S" -> "Semanal";
            case "Q" -> "Quinzenal";
            case "M" -> "Mensal";
            case "Z" -> "Diário Seg-Sab";
            case "A" -> "Dia sim e dia não";
            case "B" -> "Todo sábado";
            case "C" -> "Todo domingo";
            default -> "Empréstimo";
        };
    }

    private record GoalSnapshot(
            long id,
            long regionId,
            String regionName,
            FinancialGoalType type,
            BigDecimal targetAmount,
            LocalDate startDate,
            LocalDate endDate,
            java.time.LocalDateTime createdAt,
            java.time.LocalDateTime updatedAt) {
    }
}
