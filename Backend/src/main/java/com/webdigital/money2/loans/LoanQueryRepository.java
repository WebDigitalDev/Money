package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class LoanQueryRepository {

    private static final String SEARCH_SQL = """
            WITH RECURSIVE filter_input AS (
                SELECT
                    CAST(:startDate AS date) AS start_date,
                    CAST(:endDate AS date) AS end_date,
                    CAST(:loanId AS bigint) AS loan_id
            ),
            filtered AS MATERIALIZED (
                SELECT
                    v.id,
                    v.regiao_id,
                    COALESCE(v.nome, '') AS client_name,
                    COALESCE(v.regiao_descricao, '') AS region_name,
                    v.cidade_descricao AS city_name,
                    v.data_prox_vencimento AS display_date,
                    v.data,
                    v.status_descrito AS loan_status,
                    COALESCE(v.cor_status, '#FFFFFF') AS status_color,
                    COALESCE(v.vlr_receber, 0) AS receivable_amount,
                    COALESCE(v.vlr_recebido, 0) AS received_amount,
                    COALESCE(v.vlr_emprestado, 0) AS loaned_amount,
                    COALESCE(v.tipo, '') AS payment_type,
                    COALESCE(v.tem_refinanciamento, false) AS negotiated,
                    COALESCE(v.parcelas, '0/0') AS installment_progress,
                    e.penhora,
                    CASE
                        WHEN v.status_descrito = 'Lançamento' THEN 13
                        WHEN v.status_descrito = 'Em atraso'
                         AND lower(COALESCE(v.cor_status, '')) <> '#fcf883' THEN 12
                        WHEN v.status_descrito = 'Em atraso' THEN 11
                        WHEN v.status_descrito = 'Pendente Aprovação' THEN 10
                        WHEN v.status_descrito = 'Vence hoje' THEN 9
                        WHEN v.status_descrito = 'Em dia'
                         AND lower(COALESCE(v.cor_status, '')) <> '#40e0d0' THEN 8
                        WHEN v.status_descrito = 'Em dia' THEN 7
                        WHEN v.status_descrito = 'Desaparecido' THEN 5
                        WHEN v.status_descrito = 'Quitado' THEN 4
                        WHEN v.status_descrito = 'Renov/Abat' THEN 3
                        WHEN v.status_descrito = 'Refinanciado' THEN 2
                        WHEN v.status_descrito = 'Cancelado' THEN 1
                        ELSE 0
                    END AS status_order,
                    CASE e.tipo
                        WHEN 'D' THEN 6 WHEN 'A' THEN 6 WHEN 'S' THEN 5
                        WHEN 'Z' THEN 4 WHEN 'B' THEN 4 WHEN 'C' THEN 4
                        WHEN 'Q' THEN 3 WHEN 'M' THEN 2 ELSE 1
                    END AS type_order
                FROM vw_emprestimos_resumo v
                JOIN emprestimo e ON e.id = v.id
                CROSS JOIN filter_input fi
                WHERE v.status_descrito IS NOT NULL
                  AND (
                      (:tutorialMode = true AND v.regiao_id = :tutorialRegionId)
                      OR
                      (:tutorialMode = false AND EXISTS (
                          SELECT 1
                          FROM regiao_usuario ur
                          WHERE ur.usuario_id = :userId
                            AND ur.regiao_id = v.regiao_id
                      ))
                  )
                  AND (:filterRegions = false OR v.regiao_id IN (:regionIds))
                  AND (:filterStatuses = false OR v.status_descrito IN (:statuses))
                  AND (
                      v.status_descrito NOT IN ('Quitado', 'Renov/Abat')
                      OR (
                          (fi.start_date IS NULL OR v.data_prox_vencimento >= fi.start_date)
                          AND (fi.end_date IS NULL
                               OR v.data_prox_vencimento < fi.end_date + INTERVAL '1 day')
                      )
                  )
                  AND (
                      v.status_descrito <> 'Refinanciado'
                      OR NOT EXISTS (
                          SELECT 1
                          FROM refinanciamentos origin_ref
                          WHERE origin_ref.emp_id_origem = v.id
                      )
                  )
                  AND (
                      (fi.loan_id IS NOT NULL AND v.id = fi.loan_id)
                      OR (
                          fi.loan_id IS NULL
                          AND (
                              :query = ''
                              OR lower(COALESCE(v.nome, '')) LIKE :search
                              OR CAST(v.id AS text) LIKE :search
                          )
                      )
                  )
            ),
            paged_base AS MATERIALIZED (
                SELECT filtered.*
                FROM filtered
                ORDER BY status_order DESC, type_order DESC, received_amount, id DESC
                LIMIT :limit OFFSET :offset
            ),
            profit_targets AS MATERIALIZED (
                SELECT id
                FROM paged_base
                UNION
                SELECT id
                FROM filtered
                WHERE loan_status IN ('Quitado', 'Renov/Abat')
            ),
            profit_context AS MATERIALIZED (
                SELECT
                    target.id,
                    COALESCE(e.valor_emprestado, 0) AS principal_amount,
                    EXISTS (
                        SELECT 1
                        FROM refinanciamentos r
                        WHERE r.emp_id_origem = target.id
                    ) AS has_successor,
                    EXISTS (
                        SELECT 1
                        FROM refinanciamentos r
                        WHERE r.emp_id_destino = target.id
                    ) AS has_predecessor
                FROM profit_targets target
                JOIN emprestimo e ON e.id = target.id
            ),
            calculation_targets AS MATERIALIZED (
                SELECT id
                FROM profit_context
                WHERE has_successor = false
            ),
            profit_chain(target_id, loan_id) AS (
                SELECT id, id
                FROM calculation_targets
                UNION
                SELECT chain.target_id, refinancing.emp_id_origem
                FROM profit_chain chain
                JOIN refinanciamentos refinancing
                  ON refinancing.emp_id_destino = chain.loan_id
            ),
            chain_payments AS (
                SELECT
                    chain.target_id,
                    COALESCE(SUM(payment.valor), 0) AS paid_amount
                FROM profit_chain chain
                LEFT JOIN parcelas installment
                  ON installment.emprestimo_id = chain.loan_id
                LEFT JOIN pagamentos payment
                  ON payment.parcela_id = installment.id
                 AND COALESCE(payment.aprovacao_status, 'APROVADO') = 'APROVADO'
                GROUP BY chain.target_id
            ),
            chain_root_capital AS (
                SELECT
                    chain.target_id,
                    COALESCE(SUM(COALESCE(e.valor_emprestado, 0)) FILTER (
                        WHERE NOT EXISTS (
                            SELECT 1
                            FROM refinanciamentos predecessor
                            WHERE predecessor.emp_id_destino = chain.loan_id
                        )
                    ), 0) AS root_capital_amount
                FROM profit_chain chain
                JOIN emprestimo e ON e.id = chain.loan_id
                GROUP BY chain.target_id
            ),
            chain_renewal_capital AS (
                SELECT
                    origin_chain.target_id,
                    COALESCE(SUM(GREATEST(
                        COALESCE(destination.valor_emprestado, 0)
                        - COALESCE(refinancing.valor_devedor, 0),
                        0
                    )), 0) AS renewal_capital_amount
                FROM profit_chain origin_chain
                JOIN refinanciamentos refinancing
                  ON refinancing.emp_id_origem = origin_chain.loan_id
                JOIN profit_chain destination_chain
                  ON destination_chain.target_id = origin_chain.target_id
                 AND destination_chain.loan_id = refinancing.emp_id_destino
                JOIN emprestimo origin ON origin.id = refinancing.emp_id_origem
                JOIN emprestimo destination ON destination.id = refinancing.emp_id_destino
                WHERE COALESCE(origin.renovacao, false) = true
                GROUP BY origin_chain.target_id
            ),
            profits AS MATERIALIZED (
                SELECT
                    context.id,
                    CASE
                        WHEN context.has_successor THEN 0
                        WHEN context.has_predecessor THEN GREATEST(
                            COALESCE(payments.paid_amount, 0)
                            - COALESCE(root_capital.root_capital_amount, 0)
                            - COALESCE(renewal_capital.renewal_capital_amount, 0),
                            0
                        )
                        ELSE GREATEST(
                            COALESCE(payments.paid_amount, 0)
                            - context.principal_amount,
                            0
                        )
                    END AS profit_amount
                FROM profit_context context
                LEFT JOIN chain_payments payments ON payments.target_id = context.id
                LEFT JOIN chain_root_capital root_capital ON root_capital.target_id = context.id
                LEFT JOIN chain_renewal_capital renewal_capital
                  ON renewal_capital.target_id = context.id
            ),
            totals AS (
                SELECT
                    COUNT(*) AS total_items,
                    COALESCE(SUM(receivable_amount), 0) AS total_receivable,
                    COALESCE(SUM(received_amount), 0) AS total_received,
                    COALESCE(SUM(COALESCE(profits.profit_amount, 0)) FILTER (
                        WHERE loan_status IN ('Quitado', 'Renov/Abat')), 0) AS total_profit,
                    COALESCE(SUM(loaned_amount), 0) AS total_loaned
                FROM filtered
                LEFT JOIN profits ON profits.id = filtered.id
            ),
            paged AS (
                SELECT paged_base.*,
                       COALESCE(profits.profit_amount, 0) AS profit_amount,
                       EXISTS (
                           SELECT 1
                           FROM pix_cobrancas pix
                           WHERE pix.emprestimo_id = paged_base.id
                             AND UPPER(COALESCE(pix.status, '')) = 'AGUARDANDO'
                             AND NULLIF(trim(COALESCE(pix.pix_copia_cola, '')), '') IS NOT NULL
                       ) AS has_pending_pix
                FROM paged_base
                LEFT JOIN profits ON profits.id = paged_base.id
            )
            SELECT
                p.*,
                t.total_items,
                t.total_receivable,
                t.total_received,
                t.total_profit,
                t.total_loaned
            FROM totals t
            LEFT JOIN paged p ON true
            ORDER BY p.status_order DESC NULLS LAST,
                     p.type_order DESC NULLS LAST,
                     p.received_amount NULLS LAST,
                     p.id DESC NULLS LAST
            """;

    private final NamedParameterJdbcTemplate jdbc;

    public LoanQueryRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public LoanListResponse search(
            long userId,
            String query,
            Set<String> statuses,
            Set<Long> regionIds,
            boolean tutorialMode,
            Long tutorialRegionId,
            LocalDate startDate,
            LocalDate endDate,
            int page,
            int size) {
        Map<String, Object> parameters = new HashMap<>();
        String normalizedQuery = query == null ? "" : query.trim().toLowerCase();
        parameters.put("userId", userId);
        parameters.put("tutorialMode", tutorialMode);
        parameters.put("tutorialRegionId", tutorialRegionId == null ? -1L : tutorialRegionId);
        parameters.put("query", normalizedQuery);
        parameters.put("search", "%" + normalizedQuery + "%");
        parameters.put("loanId", contractId(normalizedQuery));
        parameters.put("filterStatuses", statuses != null && !statuses.isEmpty());
        parameters.put("statuses", statuses == null || statuses.isEmpty()
                ? List.of("__ALL__") : statuses);
        parameters.put("filterRegions", regionIds != null && !regionIds.isEmpty());
        parameters.put("regionIds", regionIds == null || regionIds.isEmpty()
                ? List.of(-1L) : regionIds);
        parameters.put("startDate", startDate);
        parameters.put("endDate", endDate);
        parameters.put("limit", size);
        parameters.put("offset", page * size);

        return jdbc.query(SEARCH_SQL, parameters, result -> {
            List<LoanSummaryResponse> items = new java.util.ArrayList<>();
            LoanTotalsResponse totals = emptyTotals();
            while (result.next()) {
                totals = new LoanTotalsResponse(
                        result.getLong("total_items"),
                        decimal(result.getBigDecimal("total_receivable")),
                        decimal(result.getBigDecimal("total_received")),
                        decimal(result.getBigDecimal("total_profit")),
                        decimal(result.getBigDecimal("total_loaned")));
                Long id = result.getObject("id", Long.class);
                if (id == null) continue;
                items.add(new LoanSummaryResponse(
                        id,
                        clean(result.getString("client_name")),
                        result.getLong("regiao_id"),
                        clean(result.getString("region_name")),
                        nullable(result.getString("city_name")),
                        dateTime(result.getTimestamp("display_date")),
                        dateTime(result.getTimestamp("data")),
                        clean(result.getString("loan_status")),
                        clean(result.getString("status_color")),
                        decimal(result.getBigDecimal("receivable_amount")),
                        decimal(result.getBigDecimal("received_amount")),
                        decimal(result.getBigDecimal("loaned_amount")),
                        decimal(result.getBigDecimal("profit_amount")),
                        clean(result.getString("payment_type")),
                        result.getBoolean("negotiated"),
                        clean(result.getString("installment_progress")),
                        result.getBoolean("has_pending_pix"),
                        nullable(result.getString("penhora"))));
            }
            long totalItems = totals.loans();
            int totalPages = totalItems == 0
                    ? 0 : (int) Math.ceil((double) totalItems / size);
            return new LoanListResponse(
                    List.copyOf(items),
                    page,
                    size,
                    totalItems,
                    totalPages,
                    page + 1 < totalPages,
                    totals);
        });
    }

    private static LoanTotalsResponse emptyTotals() {
        BigDecimal zero = BigDecimal.ZERO.setScale(2);
        return new LoanTotalsResponse(0, zero, zero, zero, zero);
    }

    private static Long contractId(String query) {
        if (query == null || !query.matches("[0-9]{4,}")) return null;
        try {
            return Long.valueOf(query);
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static BigDecimal decimal(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value)
                .setScale(2, RoundingMode.HALF_UP);
    }

    private static BigDecimal nullableDecimal(BigDecimal value) {
        return value == null ? null : value.setScale(2, RoundingMode.HALF_UP);
    }

    private static LocalDateTime dateTime(Timestamp value) {
        return value == null ? null : value.toLocalDateTime();
    }

    private static String nullable(String value) {
        String result = clean(value);
        return result.isEmpty() ? null : result;
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
