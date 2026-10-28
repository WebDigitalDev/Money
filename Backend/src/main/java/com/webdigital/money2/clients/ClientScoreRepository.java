package com.webdigital.money2.clients;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class ClientScoreRepository {

    static final int INITIAL_SCORE = 100;
    static final int MINIMUM_SCORE = 0;
    static final int MAXIMUM_SCORE = 100;

    private static final String SCORE_SQL = """
            WITH client_loans AS MATERIALIZED (
                SELECT
                    e.id,
                    e.status,
                    COALESCE(e.refinanciado, false) AS refinanced,
                    COALESCE(e.renovacao, false) AS renewed,
                    COALESCE(e.desaparecido, false) AS missing
                FROM emprestimo e
                WHERE e.cliente_id = :clientId
                  AND e.status <> 3
                  AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
            ), installment_rows AS MATERIALIZED (
                SELECT
                    installment.id,
                    installment.emprestimo_id,
                    installment.vencimento::date AS due_date,
                    GREATEST(
                        ROUND((
                            COALESCE(installment.valor, 0)
                            + COALESCE(installment.valor_juros, 0)
                        )::numeric, 2)
                        - ROUND(COALESCE(SUM(payment.valor) FILTER (
                            WHERE COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                              AND COALESCE(payment.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                        ), 0)::numeric, 2),
                        0
                    ) AS outstanding_amount,
                    (MAX(payment.data) FILTER (
                        WHERE COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                          AND COALESCE(payment.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                    ))::date AS last_payment_date
                FROM parcelas installment
                JOIN client_loans loan ON loan.id = installment.emprestimo_id
                LEFT JOIN pagamentos payment ON payment.parcela_id = installment.id
                GROUP BY installment.id
            ), loan_summary AS MATERIALIZED (
                SELECT
                    loan.id,
                    loan.status,
                    loan.refinanced,
                    loan.renewed,
                    loan.missing,
                    COUNT(*) FILTER (
                        WHERE installment.id IS NOT NULL
                          AND installment.outstanding_amount > 0
                    ) AS pending_count,
                    MAX(installment.due_date) AS last_due_date,
                    MAX(installment.last_payment_date) AS last_payment_date,
                    MIN(installment.due_date) FILTER (
                        WHERE installment.outstanding_amount > 0
                          AND installment.due_date < CURRENT_DATE
                    ) AS first_overdue_date,
                    COALESCE(SUM(installment.outstanding_amount) FILTER (
                        WHERE installment.outstanding_amount > 0
                    ), 0) AS debt_amount
                FROM client_loans loan
                LEFT JOIN installment_rows installment
                    ON installment.emprestimo_id = loan.id
                GROUP BY loan.id, loan.status, loan.refinanced,
                         loan.renewed, loan.missing
            ), closed_events AS MATERIALIZED (
                SELECT
                    loan.id AS loan_id,
                    loan.last_due_date AS due_date,
                    COALESCE(loan.last_payment_date, loan.last_due_date) AS settlement_date
                FROM loan_summary loan
                WHERE loan.refinanced = false
                  AND loan.renewed = false
                  AND loan.missing = false
                  AND loan.status <> 1
                  AND loan.pending_count = 0
                  AND loan.last_due_date IS NOT NULL
                  AND COALESCE(loan.last_payment_date, loan.last_due_date) IS NOT NULL
            ), score_events AS MATERIALIZED (
                SELECT
                    closed.loan_id AS event_id,
                    closed.settlement_date AS event_date,
                    false AS missing_event,
                    closed.due_date,
                    closed.settlement_date
                FROM closed_events closed
                UNION ALL
                SELECT
                    loan.id AS event_id,
                    CURRENT_DATE AS event_date,
                    true AS missing_event,
                    NULL::date AS due_date,
                    NULL::date AS settlement_date
                FROM loan_summary loan
                WHERE loan.refinanced = false
                  AND loan.renewed = false
                  AND loan.status <> 1
                  AND loan.missing = true
            ), metrics AS (
                SELECT
                    COALESCE(SUM(CASE
                        WHEN loan.refinanced = false
                         AND loan.renewed = false
                         AND loan.status <> 1
                         AND loan.first_overdue_date IS NOT NULL
                        THEN CURRENT_DATE - loan.first_overdue_date
                        ELSE 0
                    END), 0) AS overdue_days,
                    COALESCE(SUM(CASE
                        WHEN loan.refinanced = false
                         AND loan.renewed = false
                         AND loan.status <> 1
                        THEN loan.debt_amount
                        ELSE 0
                    END), 0) AS total_debt
                FROM loan_summary loan
            )
            SELECT
                score_event.event_id,
                score_event.event_date,
                score_event.missing_event,
                score_event.due_date,
                score_event.settlement_date,
                metrics.overdue_days,
                metrics.total_debt
            FROM metrics
            LEFT JOIN score_events score_event ON true
            ORDER BY score_event.event_date NULLS LAST,
                     score_event.missing_event,
                     score_event.event_id
            """;

    private final NamedParameterJdbcTemplate jdbc;

    public ClientScoreRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public ClientScoreResponse profile(long clientId) {
        List<ScoreRow> rows = jdbc.query(
                SCORE_SQL,
                Map.of("clientId", clientId),
                (result, index) -> new ScoreRow(
                        result.getObject("event_id", Long.class),
                        result.getObject("missing_event", Boolean.class),
                        result.getObject("due_date", LocalDate.class),
                        result.getObject("settlement_date", LocalDate.class),
                        result.getLong("overdue_days"),
                        money(result.getBigDecimal("total_debt"))));
        if (rows.isEmpty()) {
            return new ClientScoreResponse(
                    INITIAL_SCORE, 0, BigDecimal.ZERO.setScale(2));
        }
        int score = INITIAL_SCORE;
        for (ScoreRow row : rows) {
            if (row.eventId() == null) continue;
            int adjustment = Boolean.TRUE.equals(row.missingEvent())
                    ? -100
                    : settlementAdjustment(row.dueDate(), row.settlementDate());
            score = bounded(score + adjustment);
        }
        ScoreRow metrics = rows.get(0);
        return new ClientScoreResponse(
                score,
                Math.max(metrics.overdueDays(), 0),
                metrics.totalDebt());
    }

    static int settlementAdjustment(LocalDate dueDate, LocalDate settlementDate) {
        if (dueDate == null || settlementDate == null) return 0;
        long overdueDays = ChronoUnit.DAYS.between(dueDate, settlementDate);
        if (overdueDays < 0) return 10;
        if (overdueDays == 0) return 5;
        if (overdueDays <= 10) return -5;
        if (overdueDays <= 30) return -10;
        return -20;
    }

    static int scoreAfter(List<Integer> adjustments) {
        int score = INITIAL_SCORE;
        for (int adjustment : adjustments) {
            score = bounded(score + adjustment);
        }
        return score;
    }

    private static int bounded(int value) {
        return Math.max(MINIMUM_SCORE, Math.min(MAXIMUM_SCORE, value));
    }

    private BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value)
                .setScale(2, RoundingMode.HALF_UP);
    }

    private record ScoreRow(
            Long eventId,
            Boolean missingEvent,
            LocalDate dueDate,
            LocalDate settlementDate,
            long overdueDays,
            BigDecimal totalDebt) {
    }
}
