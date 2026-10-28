package com.webdigital.money2.codex;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class CodexMoneyRepository {

    private final NamedParameterJdbcTemplate jdbc;

    public CodexMoneyRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<CodexRegionSummary> regionSummaries(
            long userId,
            List<Long> regionIds,
            LocalDate startDate,
            LocalDate endDate) {
        Map<String, Object> parameters = scopedParameters(
                userId, regionIds, startDate, endDate);
        return jdbc.query("""
                WITH accessible_regions AS MATERIALIZED (
                    SELECT DISTINCT
                        r.id,
                        COALESCE(NULLIF(TRIM(r.descricao), ''), 'Região #' || r.id) AS nome
                    FROM regiao_usuario access
                    JOIN regioes r ON r.id = access.regiao_id
                    WHERE access.usuario_id = :userId
                      AND (:filterRegions = false OR r.id IN (:regionIds))
                ), accessible_loans AS MATERIALIZED (
                    SELECT
                        loan.id,
                        loan.cliente_id,
                        client.regiao_id,
                        loan.data,
                        COALESCE(loan.valor_emprestado, 0) AS emprestado
                    FROM emprestimo loan
                    JOIN cliente client ON client.id = loan.cliente_id
                    JOIN accessible_regions region ON region.id = client.regiao_id
                    WHERE COALESCE(loan.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND loan.status <> 3
                      AND COALESCE(loan.refinanciado, false) = false
                      AND COALESCE(loan.renovacao, false) = false
                ), period_loans AS MATERIALIZED (
                    SELECT *
                    FROM accessible_loans
                    WHERE (CAST(:startDate AS date) IS NULL OR data >= :startDate)
                      AND (CAST(:endDate AS date) IS NULL
                           OR data < CAST(:endDate AS date) + INTERVAL '1 day')
                ), installment_payments AS MATERIALIZED (
                    SELECT
                        payment.parcela_id,
                        COALESCE(SUM(payment.valor) FILTER (
                            WHERE COALESCE(payment.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                        ), 0) AS amortizado
                    FROM pagamentos payment
                    JOIN parcelas installment ON installment.id = payment.parcela_id
                    JOIN period_loans loan ON loan.id = installment.emprestimo_id
                    WHERE COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                    GROUP BY payment.parcela_id
                ), loan_balances AS MATERIALIZED (
                    SELECT
                        loan.regiao_id,
                        loan.id,
                        loan.cliente_id,
                        COALESCE(SUM(GREATEST(
                            COALESCE(installment.valor, 0)
                            + COALESCE(installment.valor_juros, 0)
                            - COALESCE(payment.amortizado, 0), 0
                        )) FILTER (WHERE installment.pendente = true), 0) AS receber,
                        COALESCE(SUM(GREATEST(
                            COALESCE(installment.valor, 0)
                            + COALESCE(installment.valor_juros, 0)
                            - COALESCE(payment.amortizado, 0), 0
                        )) FILTER (
                            WHERE installment.pendente = true
                              AND installment.vencimento::date < CURRENT_DATE
                        ), 0) AS atrasado,
                        COALESCE(SUM(GREATEST(
                            COALESCE(installment.valor, 0)
                            + COALESCE(installment.valor_juros, 0)
                            - COALESCE(payment.amortizado, 0), 0
                        )) FILTER (
                            WHERE installment.pendente = true
                              AND installment.vencimento::date = CURRENT_DATE
                        ), 0) AS vence_hoje
                    FROM period_loans loan
                    LEFT JOIN parcelas installment ON installment.emprestimo_id = loan.id
                    LEFT JOIN installment_payments payment
                      ON payment.parcela_id = installment.id
                    GROUP BY loan.regiao_id, loan.id, loan.cliente_id
                ), portfolio AS MATERIALIZED (
                    SELECT
                        regiao_id,
                        COUNT(DISTINCT cliente_id) FILTER (WHERE receber > 0) AS clientes,
                        COUNT(*) FILTER (WHERE receber > 0) AS contratos,
                        COUNT(*) FILTER (WHERE atrasado > 0) AS contratos_atrasados,
                        COUNT(*) FILTER (WHERE receber > 0 AND atrasado <= 0) AS contratos_em_dia,
                        COUNT(*) FILTER (WHERE receber <= 0) AS contratos_quitados,
                        COALESCE(SUM(receber), 0) AS receber,
                        COALESCE(SUM(atrasado), 0) AS atrasado,
                        COALESCE(SUM(vence_hoje), 0) AS vence_hoje
                    FROM loan_balances
                    GROUP BY regiao_id
                ), loaned_period AS MATERIALIZED (
                    SELECT regiao_id, COALESCE(SUM(emprestado), 0) AS valor
                    FROM period_loans
                    GROUP BY regiao_id
                ), received_period AS MATERIALIZED (
                    SELECT
                        loan.regiao_id,
                        COALESCE(SUM(payment.valor), 0) AS valor
                    FROM pagamentos payment
                    JOIN parcelas installment ON installment.id = payment.parcela_id
                    JOIN accessible_loans loan ON loan.id = installment.emprestimo_id
                    WHERE COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND (CAST(:startDate AS date) IS NULL OR payment.data >= :startDate)
                      AND (CAST(:endDate AS date) IS NULL
                           OR payment.data < CAST(:endDate AS date) + INTERVAL '1 day')
                    GROUP BY loan.regiao_id
                ), profit_loans AS MATERIALIZED (
                    SELECT
                        loan.id,
                        client.regiao_id,
                        COALESCE(loan.valor_emprestado, 0) AS capital
                    FROM emprestimo loan
                    JOIN cliente client ON client.id = loan.cliente_id
                    JOIN accessible_regions region ON region.id = client.regiao_id
                    WHERE COALESCE(loan.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND loan.status <> 3
                ), profit_payments AS MATERIALIZED (
                    SELECT
                        loan.id,
                        loan.regiao_id,
                        loan.capital,
                        COALESCE(SUM(payment.valor) FILTER (
                            WHERE CAST(:startDate AS date) IS NOT NULL
                              AND payment.data < :startDate
                        ), 0) AS recebido_antes,
                        COALESCE(SUM(payment.valor) FILTER (
                            WHERE (CAST(:startDate AS date) IS NULL OR payment.data >= :startDate)
                              AND (CAST(:endDate AS date) IS NULL
                                   OR payment.data < CAST(:endDate AS date) + INTERVAL '1 day')
                        ), 0) AS recebido_periodo
                    FROM profit_loans loan
                    LEFT JOIN parcelas installment ON installment.emprestimo_id = loan.id
                    LEFT JOIN pagamentos payment
                      ON payment.parcela_id = installment.id
                     AND COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                    GROUP BY loan.id, loan.regiao_id, loan.capital
                ), profit_period AS MATERIALIZED (
                    SELECT
                        regiao_id,
                        COALESCE(SUM(
                            GREATEST(recebido_antes + recebido_periodo - capital, 0)
                            - GREATEST(recebido_antes - capital, 0)
                        ), 0) AS valor
                    FROM profit_payments
                    GROUP BY regiao_id
                )
                SELECT
                    region.id,
                    region.nome,
                    COALESCE(portfolio.clientes, 0) AS clientes,
                    COALESCE(portfolio.contratos, 0) AS contratos,
                    COALESCE(portfolio.contratos_atrasados, 0) AS contratos_atrasados,
                    COALESCE(portfolio.contratos_em_dia, 0) AS contratos_em_dia,
                    COALESCE(portfolio.contratos_quitados, 0) AS contratos_quitados,
                    COALESCE(loaned.valor, 0) AS emprestado,
                    COALESCE(received.valor, 0) AS recebido,
                    COALESCE(portfolio.receber, 0) AS receber,
                    COALESCE(portfolio.atrasado, 0) AS atrasado,
                    COALESCE(portfolio.vence_hoje, 0) AS vence_hoje,
                    COALESCE(profit.valor, 0) AS lucro
                FROM accessible_regions region
                LEFT JOIN portfolio ON portfolio.regiao_id = region.id
                LEFT JOIN loaned_period loaned ON loaned.regiao_id = region.id
                LEFT JOIN received_period received ON received.regiao_id = region.id
                LEFT JOIN profit_period profit ON profit.regiao_id = region.id
                ORDER BY lower(region.nome), region.id
                """, parameters, (row, index) -> new CodexRegionSummary(
                row.getLong("id"),
                row.getString("nome"),
                row.getLong("clientes"),
                row.getLong("contratos"),
                row.getLong("contratos_atrasados"),
                row.getLong("contratos_em_dia"),
                row.getLong("contratos_quitados"),
                row.getBigDecimal("emprestado"),
                row.getBigDecimal("recebido"),
                row.getBigDecimal("receber"),
                row.getBigDecimal("atrasado"),
                row.getBigDecimal("vence_hoje"),
                row.getBigDecimal("lucro")));
    }

    public List<CodexPaymentData> recentPayments(
            long userId,
            List<Long> regionIds,
            LocalDate startDate,
            LocalDate endDate,
            String search,
            int limit) {
        Map<String, Object> parameters = scopedParameters(
                userId, regionIds, startDate, endDate);
        parameters.put("search", "%" + clean(search).toLowerCase() + "%");
        parameters.put("limit", Math.max(1, Math.min(limit, 100)));
        return jdbc.query("""
                SELECT
                    payment.id_pagamento,
                    payment.data,
                    COALESCE(payment.valor, 0) AS valor,
                    COALESCE(NULLIF(TRIM(payment.tipo), ''), 'NORMAL') AS tipo,
                    loan.id AS contrato_id,
                    COALESCE(NULLIF(TRIM(installment.parcela), ''), '-') AS parcela,
                    client.id AS cliente_id,
                    COALESCE(NULLIF(TRIM(client.nome), ''), 'Cliente #' || client.id) AS cliente,
                    region.id AS regiao_id,
                    COALESCE(NULLIF(TRIM(region.descricao), ''), 'Região #' || region.id) AS regiao
                FROM pagamentos payment
                JOIN parcelas installment ON installment.id = payment.parcela_id
                JOIN emprestimo loan ON loan.id = installment.emprestimo_id
                JOIN cliente client ON client.id = loan.cliente_id
                JOIN regioes region ON region.id = client.regiao_id
                WHERE COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                  AND EXISTS (
                      SELECT 1 FROM regiao_usuario access
                      WHERE access.usuario_id = :userId
                        AND access.regiao_id = client.regiao_id
                  )
                  AND (:filterRegions = false OR client.regiao_id IN (:regionIds))
                  AND (CAST(:startDate AS date) IS NULL OR payment.data >= :startDate)
                  AND (CAST(:endDate AS date) IS NULL
                       OR payment.data < CAST(:endDate AS date) + INTERVAL '1 day')
                  AND (:search = '%%'
                       OR lower(COALESCE(client.nome, '')) LIKE :search
                       OR CAST(loan.id AS text) LIKE :search
                       OR lower(COALESCE(region.descricao, '')) LIKE :search)
                ORDER BY payment.data DESC NULLS LAST, payment.id_pagamento DESC
                LIMIT :limit
                """, parameters, (row, index) -> new CodexPaymentData(
                row.getLong("id_pagamento"),
                row.getTimestamp("data") == null
                        ? null : row.getTimestamp("data").toLocalDateTime(),
                money(row.getBigDecimal("valor")),
                row.getString("tipo"),
                row.getLong("contrato_id"),
                row.getString("parcela"),
                row.getLong("cliente_id"),
                row.getString("cliente"),
                row.getLong("regiao_id"),
                row.getString("regiao")));
    }

    private Map<String, Object> scopedParameters(
            long userId,
            List<Long> regionIds,
            LocalDate startDate,
            LocalDate endDate) {
        List<Long> safeRegions = regionIds == null
                ? List.of() : regionIds.stream().filter(id -> id != null && id > 0).distinct().toList();
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("userId", userId);
        parameters.put("filterRegions", !safeRegions.isEmpty());
        parameters.put("regionIds", safeRegions.isEmpty() ? List.of(-1L) : safeRegions);
        parameters.put("startDate", startDate);
        parameters.put("endDate", endDate);
        return parameters;
    }

    private static BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value)
                .setScale(2, RoundingMode.HALF_UP);
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
