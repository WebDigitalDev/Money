package com.webdigital.money2.dashboard;

import com.webdigital.money2.dashboard.DashboardModels.DueTodayLoan;
import com.webdigital.money2.dashboard.DashboardModels.FinancialPoint;
import com.webdigital.money2.dashboard.DashboardModels.FinancialSummary;
import com.webdigital.money2.dashboard.DashboardModels.Metrics;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class DashboardRepository {

    private static final String ELIGIBLE_LOANS = """
            SELECT e.id,e.cliente_id,e.tipo
            FROM emprestimo e
            JOIN cliente c ON c.id=e.cliente_id
            WHERE c.regiao_id IN (:regionIds)
              AND (:tutorialMode = true OR EXISTS (
                  SELECT 1 FROM regiao_usuario ru
                  WHERE ru.usuario_id=:userId AND ru.regiao_id=c.regiao_id
              ))
              AND e.status=2
              AND (e.aprovacao_status IS NULL OR e.aprovacao_status='APROVADO')
              AND e.refinanciado IS NOT TRUE
              AND e.renovacao IS NOT TRUE
              AND e.desaparecido IS NOT TRUE
            """;

    private static final String PROFIT_LOANS = """
            SELECT e.id,e.status,
                   e.refinanciado IS TRUE refinanced,
                   e.renovacao IS TRUE renewed,
                   e.desaparecido IS TRUE missing
            FROM emprestimo e
            JOIN cliente c ON c.id=e.cliente_id
            WHERE c.regiao_id IN (:regionIds)
              AND (:tutorialMode = true OR EXISTS (
                  SELECT 1 FROM regiao_usuario ru
                  WHERE ru.usuario_id=:userId AND ru.regiao_id=c.regiao_id
              ))
              AND e.status<>3
              AND (e.aprovacao_status IS NULL OR e.aprovacao_status='APROVADO')
            """;

    private static final String PROFIT_EVENT_CTES = """
            profit_installment_summary AS MATERIALIZED (
                SELECT installment.emprestimo_id,
                       COUNT(*) FILTER (
                           WHERE installment.pendente IS DISTINCT FROM false
                       ) pending_count,
                       MAX(installment.vencimento) last_due_date
                FROM parcelas installment
                JOIN profit_loans loan ON loan.id=installment.emprestimo_id
                GROUP BY installment.emprestimo_id
            ), closed_loans AS MATERIALIZED (
                SELECT loan.id,loan.renewed,summary.last_due_date
                FROM profit_loans loan
                LEFT JOIN profit_installment_summary summary
                    ON summary.emprestimo_id=loan.id
                WHERE loan.refinanced=false
                  AND (loan.renewed=true OR (
                      loan.status<>1
                      AND loan.missing=false
                      AND COALESCE(summary.pending_count,0)=0
                  ))
            ), last_settlement_payment AS MATERIALIZED (
                SELECT installment.emprestimo_id,MAX(payment.data) last_payment_date
                FROM closed_loans loan
                JOIN parcelas installment ON installment.emprestimo_id=loan.id
                JOIN pagamentos payment ON payment.parcela_id=installment.id
                WHERE loan.renewed=false
                GROUP BY installment.emprestimo_id
            ), profit_events AS MATERIALIZED (
                SELECT loan.id,
                       CASE WHEN loan.renewed
                           THEN 'Renov/Abat' ELSE 'Quitado' END closed_status,
                       CASE WHEN loan.renewed THEN loan.last_due_date
                           ELSE COALESCE(payment.last_payment_date,loan.last_due_date)
                       END recognition_date
                FROM closed_loans loan
                LEFT JOIN last_settlement_payment payment
                    ON payment.emprestimo_id=loan.id
            )
            """;

    private final NamedParameterJdbcTemplate jdbc;

    public DashboardRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Metrics metrics(long userId, List<Long> regionIds) {
        return metrics(userId, regionIds, false);
    }

    public Metrics metrics(long userId, List<Long> regionIds, boolean tutorialMode) {
        String sql = """
                WITH eligible_loans AS MATERIALIZED (
                """ + ELIGIBLE_LOANS + """
                ), pending_installments AS MATERIALIZED (
                    SELECT p.id,p.emprestimo_id,e.cliente_id,p.vencimento,
                           p.valor,p.valor_juros
                    FROM parcelas p
                    JOIN eligible_loans e ON e.id=p.emprestimo_id
                    WHERE p.pendente=true
                ), payments AS MATERIALIZED (
                    SELECT pg.parcela_id,COALESCE(SUM(pg.valor),0) paid
                    FROM pagamentos pg
                    JOIN pending_installments p ON p.id=pg.parcela_id
                    WHERE (pg.aprovacao_status IS NULL
                           OR pg.aprovacao_status='APROVADO')
                      AND (pg.tipo IS NULL OR pg.tipo<>'JUROS_ROLAGEM')
                    GROUP BY pg.parcela_id
                ), balances AS MATERIALIZED (
                    SELECT p.id,p.emprestimo_id,p.cliente_id,p.vencimento::date due_date,
                           GREATEST(COALESCE(p.valor,0)+COALESCE(p.valor_juros,0)
                               -COALESCE(pg.paid,0),0) balance
                    FROM pending_installments p
                    LEFT JOIN payments pg ON pg.parcela_id=p.id
                ), today_payments AS MATERIALIZED (
                    SELECT COALESCE(SUM(pg.valor),0) amount,COUNT(*) payment_count
                    FROM pagamentos pg
                    JOIN parcelas p ON p.id=pg.parcela_id
                    JOIN eligible_loans e ON e.id=p.emprestimo_id
                    WHERE (pg.aprovacao_status IS NULL
                           OR pg.aprovacao_status='APROVADO')
                      AND (pg.tipo IS NULL OR pg.tipo<>'JUROS_ROLAGEM')
                      AND pg.data>=CURRENT_DATE
                      AND pg.data<CURRENT_DATE+INTERVAL '1 day'
                ), profit_loans AS MATERIALIZED (
                """ + PROFIT_LOANS + """
                ), """ + PROFIT_EVENT_CTES + """
                , closed_today AS MATERIALIZED (
                    SELECT COUNT(*) FILTER (
                               WHERE event.closed_status='Quitado') settled_count,
                           COUNT(*) FILTER (
                               WHERE event.closed_status='Renov/Abat') renewed_count,
                           COALESCE(SUM(public.calcular_lucro_fluxo(event.id)),0)
                               profit_amount
                    FROM profit_events event
                    WHERE event.recognition_date>=CURRENT_DATE
                      AND event.recognition_date<CURRENT_DATE+INTERVAL '1 day'
                )
                SELECT
                    COUNT(DISTINCT b.cliente_id) FILTER (
                        WHERE b.balance>0 AND b.due_date<CURRENT_DATE),
                    COUNT(DISTINCT b.emprestimo_id) FILTER (
                        WHERE b.balance>0 AND b.due_date<CURRENT_DATE),
                    COALESCE(SUM(b.balance) FILTER (
                        WHERE b.balance>0 AND b.due_date<CURRENT_DATE),0),
                    (SELECT amount FROM today_payments),
                    (SELECT payment_count FROM today_payments),
                    (SELECT profit_amount FROM closed_today),
                    (SELECT settled_count FROM closed_today),
                    (SELECT renewed_count FROM closed_today),
                    COUNT(*) FILTER (WHERE b.balance>0 AND b.due_date<CURRENT_DATE),
                    COALESCE(CURRENT_DATE-MIN(b.due_date) FILTER (
                        WHERE b.balance>0 AND b.due_date<CURRENT_DATE),0),
                    COUNT(DISTINCT b.emprestimo_id) FILTER (
                        WHERE b.balance>0 AND b.due_date=CURRENT_DATE),
                    COUNT(*) FILTER (WHERE b.balance>0 AND b.due_date=CURRENT_DATE),
                    COALESCE(SUM(b.balance) FILTER (
                        WHERE b.balance>0 AND b.due_date=CURRENT_DATE),0)
                FROM balances b
                """;
        return jdbc.queryForObject(sql, parameters(userId, regionIds, tutorialMode), (rs, row) -> new Metrics(
                rs.getLong(1), rs.getLong(2), money(rs.getBigDecimal(3)),
                money(rs.getBigDecimal(4)), rs.getLong(5), money(rs.getBigDecimal(6)),
                rs.getLong(7), rs.getLong(8), rs.getLong(9), rs.getLong(10),
                rs.getLong(11), rs.getLong(12), money(rs.getBigDecimal(13))));
    }

    public Metrics metrics(long userId, long regionId) {
        return metrics(userId, List.of(regionId));
    }

    public FinancialSummary financial(long userId, List<Long> regionIds) {
        return financial(userId, regionIds, false);
    }

    public FinancialSummary financial(
            long userId,
            List<Long> regionIds,
            boolean tutorialMode) {
        String sql = """
                WITH limits AS (
                    SELECT (CURRENT_DATE-INTERVAL '30 days')::date first_day,
                           CURRENT_DATE last_day
                ), days AS (
                    SELECT generate_series(l.first_day,l.last_day,INTERVAL '1 day')::date report_date
                    FROM limits l
                ), eligible_loans AS MATERIALIZED (
                """ + ELIGIBLE_LOANS + """
                ), loaned_daily AS MATERIALIZED (
                    SELECT e.data::date report_date,
                           COALESCE(SUM(e.valor_emprestado),0) amount
                    FROM emprestimo e
                    JOIN cliente c ON c.id=e.cliente_id
                    CROSS JOIN limits l
                    WHERE c.regiao_id IN (:regionIds)
                      AND (:tutorialMode = true OR EXISTS (
                          SELECT 1 FROM regiao_usuario ru
                          WHERE ru.usuario_id=:userId AND ru.regiao_id=c.regiao_id
                      ))
                      AND e.data>=l.first_day
                      AND e.data<l.last_day+INTERVAL '1 day'
                      AND e.status<>3
                    GROUP BY e.data::date
                ), received_daily AS MATERIALIZED (
                    SELECT pg.data::date report_date,COALESCE(SUM(pg.valor),0) amount
                    FROM pagamentos pg
                    JOIN parcelas p ON p.id=pg.parcela_id
                    JOIN eligible_loans e ON e.id=p.emprestimo_id
                    CROSS JOIN limits l
                    WHERE (pg.aprovacao_status IS NULL
                           OR pg.aprovacao_status='APROVADO')
                      AND pg.data>=l.first_day
                      AND pg.data<l.last_day+INTERVAL '1 day'
                    GROUP BY pg.data::date
                ), profit_loans AS MATERIALIZED (
                """ + PROFIT_LOANS + """
                ), """ + PROFIT_EVENT_CTES + """
                , profit_by_day AS MATERIALIZED (
                    SELECT event.recognition_date::date report_date,
                           COALESCE(SUM(
                               public.calcular_lucro_fluxo(event.id)),0) amount
                    FROM profit_events event
                    CROSS JOIN limits l
                    WHERE event.recognition_date>=l.first_day
                      AND event.recognition_date<l.last_day+INTERVAL '1 day'
                    GROUP BY event.recognition_date::date
                ), pending_installments AS MATERIALIZED (
                    SELECT p.id,p.vencimento,p.valor,p.valor_juros
                    FROM parcelas p
                    JOIN eligible_loans e ON e.id=p.emprestimo_id
                    CROSS JOIN limits l
                    WHERE p.pendente=true
                      AND p.vencimento>=l.first_day
                      AND p.vencimento<l.last_day+INTERVAL '1 day'
                ), payments AS MATERIALIZED (
                    SELECT pg.parcela_id,COALESCE(SUM(pg.valor),0) paid
                    FROM pagamentos pg
                    JOIN pending_installments p ON p.id=pg.parcela_id
                    WHERE (pg.aprovacao_status IS NULL
                           OR pg.aprovacao_status='APROVADO')
                      AND (pg.tipo IS NULL OR pg.tipo<>'JUROS_ROLAGEM')
                    GROUP BY pg.parcela_id
                ), pending_daily AS MATERIALIZED (
                    SELECT p.vencimento::date report_date,
                           COALESCE(SUM(GREATEST(
                               COALESCE(p.valor,0)+COALESCE(p.valor_juros,0)-COALESCE(pg.paid,0),0)),0) amount
                    FROM pending_installments p
                    LEFT JOIN payments pg ON pg.parcela_id=p.id
                    GROUP BY p.vencimento::date
                )
                SELECT d.report_date,COALESCE(l.amount,0),COALESCE(r.amount,0),
                       CASE WHEN d.report_date<CURRENT_DATE THEN COALESCE(p.amount,0) ELSE 0 END,
                       COALESCE(pr.amount,0)
                FROM days d
                LEFT JOIN loaned_daily l ON l.report_date=d.report_date
                LEFT JOIN received_daily r ON r.report_date=d.report_date
                LEFT JOIN pending_daily p ON p.report_date=d.report_date
                LEFT JOIN profit_by_day pr ON pr.report_date=d.report_date
                ORDER BY d.report_date
                """;
        List<FinancialPoint> points = jdbc.query(sql, parameters(userId, regionIds, tutorialMode), (rs, row) ->
                new FinancialPoint(rs.getObject(1, LocalDate.class), money(rs.getBigDecimal(2)),
                        money(rs.getBigDecimal(3)), money(rs.getBigDecimal(4)),
                        money(rs.getBigDecimal(5))));
        BigDecimal loaned = BigDecimal.ZERO;
        BigDecimal received = BigDecimal.ZERO;
        BigDecimal overdue = BigDecimal.ZERO;
        BigDecimal profit = BigDecimal.ZERO;
        for (FinancialPoint point : points) {
            loaned = loaned.add(point.loanedAmount());
            received = received.add(point.receivedAmount());
            overdue = overdue.add(point.overdueAmount());
            profit = profit.add(point.profitAmount());
        }
        return new FinancialSummary(money(loaned), money(received), money(overdue), money(profit), points);
    }

    public List<DueTodayLoan> dueToday(long userId, List<Long> regionIds) {
        return dueToday(userId, regionIds, false);
    }

    public List<DueTodayLoan> dueToday(
            long userId,
            List<Long> regionIds,
            boolean tutorialMode) {
        String sql = """
                WITH eligible_loans AS MATERIALIZED (
                """ + ELIGIBLE_LOANS + """
                ), due_installments AS MATERIALIZED (
                    SELECT p.id,p.emprestimo_id,p.valor,p.valor_juros
                    FROM parcelas p
                    JOIN eligible_loans e ON e.id=p.emprestimo_id
                    WHERE p.pendente=true
                      AND p.vencimento>=CURRENT_DATE
                      AND p.vencimento<CURRENT_DATE+INTERVAL '1 day'
                ), payments AS MATERIALIZED (
                    SELECT pg.parcela_id,COALESCE(SUM(pg.valor),0) paid
                    FROM pagamentos pg
                    JOIN due_installments p ON p.id=pg.parcela_id
                    WHERE (pg.aprovacao_status IS NULL
                           OR pg.aprovacao_status='APROVADO')
                      AND (pg.tipo IS NULL OR pg.tipo<>'JUROS_ROLAGEM')
                    GROUP BY pg.parcela_id
                )
                SELECT e.id,c.nome,r.descricao,
                       CASE e.tipo WHEN 'D' THEN 'Diário' WHEN 'S' THEN 'Semanal'
                           WHEN 'Q' THEN 'Quinzenal' WHEN 'M' THEN 'Mensal'
                           WHEN 'Z' THEN 'Diário Seg-Sab' WHEN 'A' THEN 'Dia sim e Dia não'
                           WHEN 'B' THEN 'Todo Sábado' WHEN 'C' THEN 'Todo Domingo' ELSE '' END,
                       SUM(GREATEST(COALESCE(p.valor,0)+COALESCE(p.valor_juros,0)-COALESCE(pg.paid,0),0)) amount
                FROM eligible_loans e
                JOIN cliente c ON c.id=e.cliente_id
                JOIN regioes r ON r.id=c.regiao_id
                JOIN due_installments p ON p.emprestimo_id=e.id
                LEFT JOIN payments pg ON pg.parcela_id=p.id
                GROUP BY e.id,c.nome,r.descricao,e.tipo
                HAVING SUM(GREATEST(COALESCE(p.valor,0)+COALESCE(p.valor_juros,0)-COALESCE(pg.paid,0),0))>0
                ORDER BY c.nome,e.id
                """;
        return jdbc.query(sql, parameters(userId, regionIds, tutorialMode), (rs, row) -> new DueTodayLoan(
                rs.getLong(1), clean(rs.getString(2)), clean(rs.getString(3)),
                clean(rs.getString(4)), money(rs.getBigDecimal(5))));
    }

    private Map<String, Object> parameters(
            long userId,
            List<Long> regionIds,
            boolean tutorialMode) {
        return Map.of(
                "userId", userId,
                "regionIds", regionIds,
                "tutorialMode", tutorialMode);
    }

    private static BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value).setScale(2, RoundingMode.HALF_UP);
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
