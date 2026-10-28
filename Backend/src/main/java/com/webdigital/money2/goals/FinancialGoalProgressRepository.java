package com.webdigital.money2.goals;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.Duration;
import java.util.Collection;
import java.util.concurrent.ConcurrentHashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.List;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class FinancialGoalProgressRepository {

    private static final long CLIENT_STATS_CACHE_NANOS = Duration.ofSeconds(10).toNanos();

    private final NamedParameterJdbcTemplate jdbc;
    private final Map<Long, CachedClientStats> clientStatsCache = new ConcurrentHashMap<>();
    private final Object clientStatsLock = new Object();

    public FinancialGoalProgressRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void lockGoalType(long regionId, FinancialGoalType type) {
        long lockKey = regionId * 10 + type.ordinal();
        jdbc.query(
                "SELECT pg_advisory_xact_lock(:lockKey)",
                Map.of("lockKey", lockKey),
                resultSet -> null);
    }

    public BigDecimal achieved(
            FinancialGoalType type,
            long regionId,
            LocalDate startDate,
            LocalDate endDate) {
        return achieved(type, List.of(regionId), startDate, endDate);
    }

    public BigDecimal achieved(
            FinancialGoalType type,
            List<Long> regionIds,
            LocalDate startDate,
            LocalDate endDate) {
        Map<String, Object> parameters = Map.of(
                "regionIds", regionIds,
                "startDate", startDate,
                "endDate", endDate);
        String sql = switch (type) {
            case EMPRESTADO -> loanedSql();
            case RECEBIDO -> receivedSql();
            case LUCRO -> profitSql();
            default -> throw new IllegalArgumentException("Use o resumo de clientes");
        };
        BigDecimal value = jdbc.queryForObject(
                sql, parameters, (row, index) -> row.getBigDecimal(1));
        return money(value);
    }

    public Map<Long, BigDecimal> achievedActive(List<Long> goalIds) {
        if (goalIds == null || goalIds.isEmpty()) return Map.of();
        Map<Long, BigDecimal> result = new LinkedHashMap<>();
        jdbc.query(
                activeGoalsSql(),
                Map.of("goalIds", goalIds),
                rows -> {
                    while (rows.next()) {
                        result.put(rows.getLong(1), money(rows.getBigDecimal(2)));
                    }
                    return null;
                });
        return Map.copyOf(result);
    }

    /** One set-based query for all client goals, using the same contract-based
     * classification shown by the Regions screen. Payments are reconstructed as
     * of the end date, so a payment today cannot improve an already closed period. */
    public Map<Long, ClientGoalStats> clientStats(List<Long> ids) {
        if (ids.isEmpty()) return Map.of();
        List<Long> goalIds = ids.stream().distinct().toList();
        synchronized (clientStatsLock) {
            long now = System.nanoTime();
            Map<Long, ClientGoalStats> result = cachedClientStats(goalIds, now);
            List<Long> missing = goalIds.stream().filter(id -> !result.containsKey(id)).toList();
            if (!missing.isEmpty()) {
                Map<Long, ClientGoalStats> loaded = new LinkedHashMap<>();
                jdbc.query(clientStatsSql(), Map.of("ids", missing), rs -> {
                    while (rs.next()) loaded.put(rs.getLong("goal_id"), new ClientGoalStats(
                            rs.getLong("active"), rs.getLong("on_time"),
                            rs.getLong("overdue"), rs.getLong("new_clients")));
                    return null;
                });
                long expiresAt = System.nanoTime() + CLIENT_STATS_CACHE_NANOS;
                for (Long id : missing) {
                    ClientGoalStats stats = loaded.getOrDefault(id, ClientGoalStats.EMPTY);
                    clientStatsCache.put(id, new CachedClientStats(stats, expiresAt));
                    result.put(id, stats);
                }
            }
            return Map.copyOf(result);
        }
    }

    private Map<Long, ClientGoalStats> cachedClientStats(Collection<Long> ids, long now) {
        Map<Long, ClientGoalStats> result = new LinkedHashMap<>();
        for (Long id : ids) {
            CachedClientStats cached = clientStatsCache.get(id);
            if (cached != null && cached.expiresAtNanos() > now) result.put(id, cached.stats());
        }
        return result;
    }

    private record CachedClientStats(ClientGoalStats stats, long expiresAtNanos) {}

    private String clientStatsSql() {
        return """
            WITH goals AS MATERIALIZED (
                SELECT id, regiao_id, data_inicio, LEAST(data_fim, CURRENT_DATE) cutoff
                FROM money2_metas_financeiras WHERE id IN (:ids) AND data_inicio <= CURRENT_DATE
            ), goal_regions AS MATERIALIZED (
                SELECT g.id goal_id, r.regiao_id
                FROM goals g
                JOIN money2_metas_financeiras_regioes r ON r.meta_id=g.id
                UNION
                SELECT g.id, g.regiao_id FROM goals g
                WHERE NOT EXISTS (
                    SELECT 1 FROM money2_metas_financeiras_regioes r WHERE r.meta_id=g.id
                )
            ), goal_contracts AS MATERIALIZED (
                SELECT g.id goal_id, g.data_inicio, g.cutoff,
                       e.id contract_id, e.data::date contract_date,
                       e.status, COALESCE(e.aprovacao_status,'APROVADO') approval_status,
                       COALESCE(e.refinanciado,false) refinanced,
                       COALESCE(e.renovacao,false) renewed,
                       COALESCE(e.desaparecido,false) missing
                FROM goals g
                JOIN goal_regions gr ON gr.goal_id=g.id
                JOIN cliente c ON c.regiao_id=gr.regiao_id
                JOIN emprestimo e ON e.cliente_id=c.id AND e.data::date<=g.cutoff
            ), historical_contracts AS MATERIALIZED (
                SELECT DISTINCT cutoff, contract_id
                FROM goal_contracts WHERE cutoff<CURRENT_DATE
            ), payment_totals AS MATERIALIZED (
                SELECT hc.cutoff, p.id parcela_id, SUM(pg.valor) amount
                FROM historical_contracts hc
                JOIN parcelas p ON p.emprestimo_id=hc.contract_id
                JOIN pagamentos pg ON pg.parcela_id=p.id
                    AND pg.data<hc.cutoff + INTERVAL '1 day'
                    AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                    AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'
                GROUP BY hc.cutoff,p.id
            ), contract_balances AS MATERIALIZED (
                SELECT gc.cutoff, gc.contract_id,
                       COUNT(p.id) FILTER (WHERE
                           (gc.cutoff=CURRENT_DATE AND p.pendente IS DISTINCT FROM false)
                           OR (gc.cutoff<CURRENT_DATE AND ROUND(CAST(
                               COALESCE(p.valor,0)+COALESCE(p.valor_juros,0)
                               - COALESCE(paid.amount,0) AS numeric),2)>0)
                       ) pending_count,
                       COUNT(p.id) FILTER (WHERE p.vencimento::date < gc.cutoff AND (
                           (gc.cutoff=CURRENT_DATE AND p.pendente=true)
                           OR (gc.cutoff<CURRENT_DATE AND ROUND(CAST(
                               COALESCE(p.valor,0)+COALESCE(p.valor_juros,0)
                               - COALESCE(paid.amount,0) AS numeric),2)>0)
                       )) overdue_count
                FROM (SELECT DISTINCT cutoff,contract_id FROM goal_contracts) gc
                LEFT JOIN parcelas p ON p.emprestimo_id=gc.contract_id
                LEFT JOIN payment_totals paid ON paid.parcela_id=p.id AND paid.cutoff=gc.cutoff
                GROUP BY gc.cutoff,gc.contract_id
            ), classified AS MATERIALIZED (
                SELECT gc.*,
                    CASE
                        WHEN gc.approval_status='PENDENTE' THEN 'Pendente Aprovação'
                        WHEN gc.status=3 THEN 'Cancelado'
                        WHEN gc.refinanced THEN 'Refinanciado'
                        WHEN gc.renewed THEN 'Renov/Abat'
                        WHEN gc.status=1 THEN 'Lançamento'
                        WHEN gc.missing THEN 'Desaparecido'
                        WHEN COALESCE(b.overdue_count,0)>0 THEN 'Em atraso'
                        WHEN COALESCE(b.pending_count,0)=0 THEN 'Quitado'
                        WHEN gc.status=2 THEN 'Em dia'
                        ELSE NULL
                    END contract_state
                FROM goal_contracts gc
                LEFT JOIN contract_balances b
                  ON b.cutoff=gc.cutoff AND b.contract_id=gc.contract_id
            )
            SELECT goal_id,
                COUNT(*) FILTER (WHERE contract_state IN
                    ('Lançamento','Em atraso','Em dia')) active,
                COUNT(*) FILTER (WHERE contract_state NOT IN
                    ('Quitado','Renov/Abat','Refinanciado','Cancelado',
                     'Em atraso','Desaparecido')) on_time,
                COUNT(*) FILTER (WHERE contract_state='Em atraso') overdue,
                COUNT(*) FILTER (WHERE contract_date BETWEEN data_inicio AND cutoff
                    AND approval_status='APROVADO' AND status<>3) new_clients
            FROM classified GROUP BY goal_id
            """;
    }

    private String activeGoalsSql() {
        return """
                WITH target_goals AS MATERIALIZED (
                    SELECT
                        goal.id,
                        goal.tipo,
                        goal.data_inicio,
                        LEAST(goal.data_fim, CURRENT_DATE) AS data_fim
                    FROM money2_metas_financeiras goal
                    WHERE goal.id IN (:goalIds)
                ), goal_regions AS MATERIALIZED (
                    SELECT DISTINCT goal.id AS goal_id, region.regiao_id
                    FROM target_goals goal
                    JOIN money2_metas_financeiras_regioes region
                      ON region.meta_id = goal.id
                    UNION
                    SELECT goal.id, source.regiao_id
                    FROM target_goals goal
                    JOIN money2_metas_financeiras source ON source.id = goal.id
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM money2_metas_financeiras_regioes region
                        WHERE region.meta_id = goal.id
                    )
                ), overall_limits AS MATERIALIZED (
                    SELECT MIN(data_inicio) AS first_day, MAX(data_fim) AS last_day
                    FROM target_goals
                ), relevant_regions AS MATERIALIZED (
                    SELECT DISTINCT region.regiao_id
                    FROM goal_regions region
                ), loaned_values AS MATERIALIZED (
                    SELECT goal.id AS goal_id, COALESCE(SUM(loan.valor_emprestado), 0) AS amount
                    FROM target_goals goal
                    JOIN goal_regions region ON region.goal_id = goal.id
                    JOIN cliente client ON client.regiao_id = region.regiao_id
                    JOIN emprestimo loan ON loan.cliente_id = client.id
                    WHERE goal.tipo = 'EMPRESTADO'
                      AND loan.data >= goal.data_inicio
                      AND loan.data < goal.data_fim + INTERVAL '1 day'
                      AND loan.status <> 3
                      AND COALESCE(loan.aprovacao_status, 'APROVADO') = 'APROVADO'
                    GROUP BY goal.id
                ), received_values AS MATERIALIZED (
                    SELECT goal.id AS goal_id, COALESCE(SUM(payment.valor), 0) AS amount
                    FROM target_goals goal
                    JOIN goal_regions region ON region.goal_id = goal.id
                    JOIN cliente client ON client.regiao_id = region.regiao_id
                    JOIN emprestimo loan ON loan.cliente_id = client.id
                    JOIN parcelas installment ON installment.emprestimo_id = loan.id
                    JOIN pagamentos payment ON payment.parcela_id = installment.id
                    WHERE goal.tipo = 'RECEBIDO'
                      AND payment.data >= goal.data_inicio
                      AND payment.data < goal.data_fim + INTERVAL '1 day'
                      AND COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                    GROUP BY goal.id
                ), profit_loans AS MATERIALIZED (
                    SELECT
                        loan.id,
                        client.regiao_id,
                        loan.status,
                        COALESCE(loan.refinanciado, false) AS refinanced,
                        COALESCE(loan.renovacao, false) AS renewed,
                        COALESCE(loan.desaparecido, false) AS missing
                    FROM emprestimo loan
                    JOIN cliente client ON client.id = loan.cliente_id
                    WHERE client.regiao_id IN (SELECT regiao_id FROM relevant_regions)
                      AND loan.status <> 3
                      AND COALESCE(loan.aprovacao_status, 'APROVADO') = 'APROVADO'
                ), recent_payment_loans AS MATERIALIZED (
                    SELECT DISTINCT installment.emprestimo_id AS id
                    FROM overall_limits limits
                    JOIN pagamentos payment
                      ON payment.data >= limits.first_day
                     AND payment.data < limits.last_day + INTERVAL '1 day'
                    JOIN parcelas installment ON installment.id = payment.parcela_id
                    WHERE COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND COALESCE(payment.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                ), recent_due_loans AS MATERIALIZED (
                    SELECT DISTINCT installment.emprestimo_id AS id
                    FROM overall_limits limits
                    JOIN parcelas installment
                      ON installment.vencimento >= limits.first_day
                     AND installment.vencimento < limits.last_day + INTERVAL '1 day'
                ), settlement_candidates AS MATERIALIZED (
                    SELECT id FROM recent_payment_loans
                    UNION
                    SELECT id FROM recent_due_loans
                ), settled_recognition AS MATERIALIZED (
                    SELECT
                        loan.id,
                        loan.regiao_id,
                        COALESCE(payment.last_payment_date, installments.last_due_date)
                            AS recognition_date
                    FROM profit_loans loan
                    JOIN settlement_candidates candidate ON candidate.id = loan.id
                    JOIN LATERAL (
                        SELECT MAX(installment.vencimento) AS last_due_date
                        FROM parcelas installment
                        WHERE installment.emprestimo_id = loan.id
                    ) installments ON true
                    LEFT JOIN LATERAL (
                        SELECT MAX(payment.data) AS last_payment_date
                        FROM parcelas installment
                        JOIN pagamentos payment ON payment.parcela_id = installment.id
                        WHERE installment.emprestimo_id = loan.id
                          AND COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                          AND COALESCE(payment.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                    ) payment ON true
                    WHERE loan.refinanced = false
                      AND loan.renewed = false
                      AND loan.status <> 1
                      AND loan.missing = false
                      AND NOT EXISTS (
                          SELECT 1
                          FROM parcelas pending
                          WHERE pending.emprestimo_id = loan.id
                            AND pending.pendente IS DISTINCT FROM false
                      )
                ), settled_events AS MATERIALIZED (
                    SELECT loan.id, loan.regiao_id, loan.recognition_date
                    FROM settled_recognition loan
                    CROSS JOIN overall_limits limits
                    WHERE loan.recognition_date >= limits.first_day
                      AND loan.recognition_date < limits.last_day + INTERVAL '1 day'
                ), renewed_recognition AS MATERIALIZED (
                    SELECT
                        loan.id,
                        loan.regiao_id,
                        MAX(installment.vencimento) AS recognition_date
                    FROM profit_loans loan
                    JOIN recent_due_loans candidate ON candidate.id = loan.id
                    JOIN parcelas installment ON installment.emprestimo_id = loan.id
                    WHERE loan.refinanced = false
                      AND loan.renewed = true
                    GROUP BY loan.id, loan.regiao_id
                ), renewed_events AS MATERIALIZED (
                    SELECT loan.id, loan.regiao_id, loan.recognition_date
                    FROM renewed_recognition loan
                    CROSS JOIN overall_limits limits
                    WHERE loan.recognition_date >= limits.first_day
                      AND loan.recognition_date < limits.last_day + INTERVAL '1 day'
                ), recognized_profit AS MATERIALIZED (
                    SELECT * FROM settled_events
                    UNION ALL
                    SELECT * FROM renewed_events
                ), profit_events AS MATERIALIZED (
                    SELECT
                        loan.id,
                        loan.regiao_id,
                        loan.recognition_date,
                        public.calcular_lucro_fluxo(loan.id) AS amount
                    FROM recognized_profit loan
                ), profit_values AS MATERIALIZED (
                    SELECT goal.id AS goal_id, COALESCE(SUM(profit.amount), 0) AS amount
                    FROM target_goals goal
                    JOIN goal_regions region ON region.goal_id = goal.id
                    JOIN profit_events profit ON profit.regiao_id = region.regiao_id
                    WHERE goal.tipo = 'LUCRO'
                      AND profit.recognition_date >= goal.data_inicio
                      AND profit.recognition_date < goal.data_fim + INTERVAL '1 day'
                    GROUP BY goal.id
                ), achieved_values AS MATERIALIZED (
                    SELECT * FROM loaned_values
                    UNION ALL
                    SELECT * FROM received_values
                    UNION ALL
                    SELECT * FROM profit_values
                )
                SELECT goal.id, COALESCE(value.amount, 0)
                FROM target_goals goal
                LEFT JOIN achieved_values value ON value.goal_id = goal.id
                ORDER BY goal.id
                """;
    }

    private String loanedSql() {
        return """
                SELECT COALESCE(SUM(e.valor_emprestado), 0)
                FROM emprestimo e
                JOIN cliente c ON c.id = e.cliente_id
                WHERE c.regiao_id IN (:regionIds)
                  AND e.data >= :startDate
                  AND e.data < CAST(:endDate AS date) + INTERVAL '1 day'
                  AND e.status <> 3
                  AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                """;
    }

    private String receivedSql() {
        return """
                SELECT COALESCE(SUM(pg.valor), 0)
                FROM pagamentos pg
                JOIN parcelas pa ON pa.id = pg.parcela_id
                JOIN emprestimo e ON e.id = pa.emprestimo_id
                JOIN cliente c ON c.id = e.cliente_id
                WHERE c.regiao_id IN (:regionIds)
                  AND pg.data >= :startDate
                  AND pg.data < CAST(:endDate AS date) + INTERVAL '1 day'
                  AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                """;
    }

    private String profitSql() {
        return """
                WITH goal_loans AS MATERIALIZED (
                    SELECT
                        e.id,
                        e.status,
                        COALESCE(e.refinanciado, false) AS refinanced,
                        COALESCE(e.renovacao, false) AS renewed,
                        COALESCE(e.desaparecido, false) AS missing
                    FROM emprestimo e
                    JOIN cliente c ON c.id = e.cliente_id
                    WHERE c.regiao_id IN (:regionIds)
                      AND e.status <> 3
                      AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
                ), installment_summary AS MATERIALIZED (
                    SELECT
                        installment.emprestimo_id,
                        COUNT(*) FILTER (
                            WHERE installment.pendente IS DISTINCT FROM false
                        ) AS pending_count,
                        MAX(installment.vencimento) AS last_due_date
                    FROM parcelas installment
                    JOIN goal_loans loan ON loan.id = installment.emprestimo_id
                    GROUP BY installment.emprestimo_id
                ), closed_loans AS MATERIALIZED (
                    SELECT
                        loan.id,
                        loan.renewed,
                        summary.last_due_date
                    FROM goal_loans loan
                    LEFT JOIN installment_summary summary
                        ON summary.emprestimo_id = loan.id
                    WHERE loan.refinanced = false
                      AND (
                          loan.renewed = true
                          OR (
                              loan.status <> 1
                              AND loan.missing = false
                              AND COALESCE(summary.pending_count, 0) = 0
                          )
                      )
                ), last_settlement_payment AS MATERIALIZED (
                    SELECT
                        installment.emprestimo_id,
                        MAX(payment.data) AS last_payment_date
                    FROM closed_loans loan
                    JOIN parcelas installment
                        ON installment.emprestimo_id = loan.id
                    JOIN pagamentos payment
                        ON payment.parcela_id = installment.id
                    WHERE loan.renewed = false
                      AND COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND COALESCE(payment.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                    GROUP BY installment.emprestimo_id
                ), recognized_profit AS MATERIALIZED (
                    SELECT
                        loan.id,
                        CASE
                            WHEN loan.renewed THEN loan.last_due_date
                            ELSE COALESCE(payment.last_payment_date, loan.last_due_date)
                        END AS recognition_date
                    FROM closed_loans loan
                    LEFT JOIN last_settlement_payment payment
                        ON payment.emprestimo_id = loan.id
                )
                SELECT COALESCE(SUM(public.calcular_lucro_fluxo(loan.id)), 0)
                FROM recognized_profit loan
                WHERE loan.recognition_date >= :startDate
                  AND loan.recognition_date
                      < CAST(:endDate AS date) + INTERVAL '1 day'
                """;
    }

    private BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value)
                .setScale(2, RoundingMode.HALF_UP);
    }
}
