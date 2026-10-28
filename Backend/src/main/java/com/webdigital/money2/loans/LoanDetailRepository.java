package com.webdigital.money2.loans;

import com.webdigital.money2.shared.ApiException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;

@Repository
public class LoanDetailRepository {

    private static final String BASE_SQL = """
            WITH summary AS (
                SELECT
                    COUNT(*) FILTER (WHERE p.pendente = true) AS pending_count,
                    COUNT(*) FILTER (WHERE p.pendente = true AND p.vencimento::date < CURRENT_DATE) AS overdue_count,
                    COUNT(*) FILTER (WHERE p.pendente = true AND p.vencimento::date = CURRENT_DATE) AS due_today_count
                FROM parcelas p WHERE p.emprestimo_id = :loanId
            )
            SELECT e.*, c.nome AS client_name, c.regiao_id, r.descricao AS region_name,
                   CASE
                     WHEN COALESCE(e.aprovacao_status,'APROVADO')='PENDENTE'
                       OR e.status IN (1,3)
                       OR COALESCE(e.refinanciado,false)
                       OR COALESCE(e.renovacao,false)
                     THEN 0
                     ELSE COALESCE((
                       SELECT SUM(GREATEST(
                         COALESCE(p.valor,0)+COALESCE(p.valor_juros,0)-COALESCE((
                           SELECT SUM(pg.valor) FROM pagamentos pg
                           WHERE pg.parcela_id=p.id
                             AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                             AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'
                         ),0),0))
                       FROM parcelas p WHERE p.emprestimo_id=e.id AND p.pendente=true
                     ),0)
                   END AS calculated_receivable,
                   COALESCE((
                     SELECT SUM(pg.valor) FROM pagamentos pg
                     JOIN parcelas p ON p.id=pg.parcela_id
                     WHERE p.emprestimo_id=e.id
                       AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                   ),0) AS calculated_received,
                   COALESCE(public.calcular_lucro_fluxo(e.id), 0) AS calculated_profit,
                   COALESCE((
                     SELECT MAX(rf.valor_original)
                     FROM refinanciamentos rf
                     WHERE rf.emp_id_destino = e.id
                   ), 0) AS original_loan_amount,
                   CASE
                     WHEN COALESCE(e.aprovacao_status, 'APROVADO') = 'PENDENTE' THEN 'Pendente Aprovação'
                     WHEN e.status = 3 THEN 'Cancelado'
                     WHEN COALESCE(e.refinanciado, false) THEN 'Refinanciado'
                     WHEN COALESCE(e.renovacao, false) THEN 'Renov/Abat'
                     WHEN e.status = 1 THEN 'Lançamento'
                     WHEN COALESCE(e.desaparecido, false) THEN 'Desaparecido'
                     WHEN COALESCE(s.overdue_count, 0) > 0 THEN 'Em atraso'
                     WHEN COALESCE(s.pending_count, 0) = 0 THEN 'Quitado'
                     WHEN COALESCE(s.due_today_count, 0) > 0 THEN 'Vence hoje'
                     ELSE 'Em dia'
                   END AS described_status,
                   EXISTS (
                     SELECT 1 FROM aprovacoes a
                     WHERE (a.emprestimo_id = e.id OR a.emprestimo_origem_id = e.id)
                       AND a.status = 'PENDENTE'
                       AND a.tipo IN ('FINALIZACAO','REFINANCIAMENTO','RENOVACAO')
                   ) AS operation_locked
            FROM emprestimo e
            JOIN cliente c ON c.id = e.cliente_id
            JOIN regioes r ON r.id = c.regiao_id
            CROSS JOIN summary s
            WHERE e.id = :loanId
              AND (:systemAccess OR EXISTS (
                SELECT 1 FROM regiao_usuario ru
                WHERE ru.usuario_id = :userId AND ru.regiao_id = c.regiao_id
              ))
            """;

    private static final String INSTALLMENTS_SQL = """
            SELECT p.id, p.parcela, p.vencimento, p.valor, COALESCE(p.valor_juros,0) AS valor_juros,
                   COALESCE(SUM(pg.valor) FILTER (
                     WHERE COALESCE(pg.aprovacao_status,'APROVADO') = 'APROVADO'
                       AND COALESCE(pg.tipo,'NORMAL') <> 'JUROS_ROLAGEM'), 0) AS paid,
                   MAX(pg.data) FILTER (
                     WHERE COALESCE(pg.aprovacao_status,'APROVADO') = 'APROVADO'
                       AND COALESCE(pg.tipo,'NORMAL') <> 'JUROS_ROLAGEM') AS last_payment,
                   p.pendente, p.observacao_vencimento,
                   GREATEST(CURRENT_DATE - p.vencimento::date, 0) AS overdue_days,
                   p.vencimento::date = CURRENT_DATE AS due_today,
                   EXISTS (SELECT 1 FROM pagamentos pp WHERE pp.parcela_id = p.id
                           AND pp.aprovacao_status = 'PENDENTE') AS payment_pending
            FROM parcelas p
            LEFT JOIN pagamentos pg ON pg.parcela_id = p.id
            WHERE p.emprestimo_id = :loanId
            GROUP BY p.id
            ORDER BY p.vencimento, p.id
            """;

    private static final String PAYMENTS_SQL = """
            SELECT id_pagamento, parcela_id, data, valor, observacao,
                   COALESCE(automatico,false) AS automatico,
                   COALESCE(aprovacao_status,'APROVADO') AS aprovacao_status,
                   COALESCE(tipo,'NORMAL') AS tipo
            FROM pagamentos
            WHERE emprestimo_id = :loanId
               OR parcela_id IN (SELECT id FROM parcelas WHERE emprestimo_id = :loanId)
            ORDER BY data DESC, id_pagamento DESC
            """;

    private final NamedParameterJdbcTemplate jdbc;

    public LoanDetailRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public LoanSnapshot requireSnapshot(long userId, long loanId) {
        return requireSnapshot(Map.of(
                "userId", userId, "loanId", loanId, "systemAccess", false));
    }

    public LoanSnapshot requireSnapshotForSystem(long loanId) {
        return requireSnapshot(Map.of(
                "userId", -1L, "loanId", loanId, "systemAccess", true));
    }

    private LoanSnapshot requireSnapshot(Map<String, ?> parameters) {
        List<LoanSnapshot> rows = jdbc.query(BASE_SQL, parameters,
                (rs, row) -> new LoanSnapshot(
                        rs.getLong("id"), rs.getLong("cliente_id"), clean(rs.getString("client_name")),
                        rs.getLong("regiao_id"), clean(rs.getString("region_name")),
                        dateTime(rs.getTimestamp("data")), dateTime(rs.getTimestamp("data_privencimento")),
                        rs.getInt("parcela"), nullable(rs.getString("observacoes")), clean(rs.getString("tipo")),
                        decimal(rs.getBigDecimal("valor_emprestado")),
                        decimal(rs.getBigDecimal("original_loan_amount")),
                        decimal(rs.getBigDecimal("vlr_desconto")),
                        decimal(rs.getBigDecimal("juros")), decimal(rs.getBigDecimal("vlrmulta")),
                        decimal(rs.getBigDecimal("calculated_received")), decimal(rs.getBigDecimal("calculated_receivable")),
                        decimal(rs.getBigDecimal("calculated_profit")),
                        nullable(rs.getString("penhora")),
                        nullable(rs.getString("dono_cliente")), rs.getBoolean("desaparecido"),
                        Boolean.TRUE.equals(rs.getObject("ativo", Boolean.class)),
                        Boolean.TRUE.equals(rs.getObject("refinanciado", Boolean.class)),
                        Boolean.TRUE.equals(rs.getObject("renovacao", Boolean.class)), rs.getInt("status"),
                        clean(rs.getString("described_status")), clean(rs.getString("aprovacao_status")),
                        rs.getBoolean("operation_locked")));
        if (rows.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Empréstimo não encontrado.");
        }
        return rows.get(0);
    }

    public List<LoanInstallmentResponse> installments(long loanId, BigDecimal lateFee) {
        Map<Long, List<LoanPaymentResponse>> payments = payments(loanId);
        return jdbc.query(INSTALLMENTS_SQL, Map.of("loanId", loanId), (rs, row) -> {
            long id = rs.getLong("id");
            BigDecimal amount = decimal(rs.getBigDecimal("valor"));
            BigDecimal interest = decimal(rs.getBigDecimal("valor_juros"));
            BigDecimal total = amount.add(interest).setScale(2, RoundingMode.HALF_UP);
            BigDecimal paid = decimal(rs.getBigDecimal("paid"));
            BigDecimal balance = total.subtract(paid).max(BigDecimal.ZERO).setScale(2, RoundingMode.HALF_UP);
            int overdueDays = rs.getInt("overdue_days");
            // O saldo aprovado é a fonte financeira definitiva. Isso também
            // protege a interface de registros antigos cujo campo `pendente`
            // não foi sincronizado depois da edição de uma parcela já quitada.
            boolean pending = rs.getBoolean("pendente") && balance.signum() > 0;
            boolean refinanced = false;
            LocalDateTime due = dateTime(rs.getTimestamp("vencimento"));
            String status = installmentStatus(
                    pending, paid, overdueDays, rs.getBoolean("due_today"));
            BigDecimal overdue = pending && overdueDays > 0 ? balance : zero();
            BigDecimal overdueInterest = pending && overdueDays > 0
                    ? lateFee.multiply(BigDecimal.valueOf(overdueDays)).setScale(2, RoundingMode.HALF_UP)
                    : zero();
            return new LoanInstallmentResponse(
                    id, clean(rs.getString("parcela")), due, dateTime(rs.getTimestamp("last_payment")),
                    amount, interest, total, paid, balance, overdue, overdueInterest, overdueDays,
                    status, nullable(rs.getString("observacao_vencimento")), pending,
                    rs.getBoolean("payment_pending"), payments.getOrDefault(id, List.of()));
        });
    }

    static String installmentStatus(
            boolean pending, BigDecimal paid, int overdueDays, boolean dueToday) {
        if (!pending) return "Pago";
        if (paid.signum() > 0) return "Parcial";
        if (overdueDays > 0) return "Vencido";
        if (dueToday) return "Vence hoje";
        return "À Vencer";
    }

    public BigDecimal pendingDebt(long loanId) {
        BigDecimal value = jdbc.queryForObject("""
                SELECT COALESCE(SUM(GREATEST(
                    COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0) - COALESCE((
                        SELECT SUM(pg.valor)
                        FROM pagamentos pg
                        WHERE pg.parcela_id = p.id
                          AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                          AND COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                    ), 0), 0)), 0)
                FROM parcelas p
                WHERE p.emprestimo_id = :loanId
                  AND p.pendente = true
                """, Map.of("loanId", loanId), BigDecimal.class);
        return decimal(value);
    }

    private Map<Long, List<LoanPaymentResponse>> payments(long loanId) {
        Map<Long, List<LoanPaymentResponse>> result = new LinkedHashMap<>();
        jdbc.query(PAYMENTS_SQL, Map.of("loanId", loanId), rs -> {
            long installmentId = rs.getLong("parcela_id");
            result.computeIfAbsent(installmentId, ignored -> new ArrayList<>()).add(
                    new LoanPaymentResponse(rs.getLong("id_pagamento"), dateTime(rs.getTimestamp("data")),
                            decimal(rs.getBigDecimal("valor")), nullable(rs.getString("observacao")),
                            rs.getBoolean("automatico"), clean(rs.getString("aprovacao_status")),
                            clean(rs.getString("tipo"))));
        });
        result.replaceAll((key, value) -> List.copyOf(value));
        return result;
    }

    public List<LoanHistoryResponse> history(long loanId) {
        String sql = """
                SELECT l.id, l.entity_name, l.operation, l.description, l.username, l.timestamp
                FROM entity_log_detalhado l
                WHERE (l.entity_name = 'EMPRESTIMO' AND l.entity_id = :loanId)
                   OR (l.entity_name = 'PARCELA' AND l.entity_id IN
                       (SELECT id FROM parcelas WHERE emprestimo_id = :loanId))
                   OR (l.entity_name = 'PAGAMENTO' AND (
                       l.entity_id IN (
                           SELECT id_pagamento FROM pagamentos
                           WHERE emprestimo_id = :loanId OR parcela_id IN
                                 (SELECT id FROM parcelas WHERE emprestimo_id = :loanId)
                       )
                       OR (
                           l.entity_id = :loanId
                           AND l.operation IN (
                               'adicionaPagamento',
                               'deletaPagamentoEmprestimo',
                               'aprovarPagamentoContrato',
                               'reprovarPagamentoContrato'
                           )
                       )
                   ))
                   OR (l.entity_name = 'APROVACAO' AND l.entity_id IN (
                       SELECT a.id FROM aprovacoes a
                       WHERE a.emprestimo_id = :loanId
                          OR a.emprestimo_origem_id = :loanId
                          OR a.entidade_id = :loanId
                   ))
                ORDER BY l.timestamp DESC NULLS LAST, l.id DESC
                LIMIT 300
                """;
        return jdbc.query(sql, Map.of("loanId", loanId), (rs, row) -> new LoanHistoryResponse(
                rs.getLong("id"), clean(rs.getString("entity_name")), clean(rs.getString("operation")),
                clean(rs.getString("description")), clean(rs.getString("username")),
                dateTime(rs.getTimestamp("timestamp"))));
    }

    public List<LoanApprovalResponse> approvals(long loanId) {
        String sql = """
                SELECT id,tipo,acao,status,descricao,valor,solicitante_username,
                       aprovador_username,motivo_recusa,dtcad,dtdecisao
                FROM (
                  SELECT a.id,a.tipo,a.acao,a.status,COALESCE(a.descricao,'') descricao,
                         COALESCE(a.valor,0) valor,COALESCE(a.solicitante_username,'') solicitante_username,
                         a.aprovador_username,a.motivo_recusa,a.dtcad,a.dtdecisao
                  FROM aprovacoes a
                  WHERE a.emprestimo_id=:loanId OR a.emprestimo_origem_id=:loanId OR a.entidade_id=:loanId
                  UNION ALL
                  SELECT -p.id id,'PIX' tipo,'COBRANCA' acao,COALESCE(p.status,'') status,
                         CONCAT('Cobrança PIX',
                                CASE WHEN p.parcela_id IS NULL THEN ' do contrato'
                                     ELSE CONCAT(' da parcela #',p.parcela_id) END,
                                CASE WHEN NULLIF(trim(COALESCE(p.txid,'')),'') IS NULL THEN ''
                                     ELSE CONCAT(' • TXID ',p.txid) END) descricao,
                         COALESCE(p.valor,0) valor,'SISTEMA' solicitante_username,
                         NULL::varchar aprovador_username,NULL::varchar motivo_recusa,
                         p.dtcad,CASE WHEN UPPER(COALESCE(p.status,'')) IN ('PAGO','CANCELADO','ERRO')
                                      THEN COALESCE(p.dt_pagamento,p.dtalter) ELSE NULL END dtdecisao
                  FROM pix_cobrancas p
                  WHERE p.emprestimo_id=:loanId
                ) conferencias
                ORDER BY dtcad DESC NULLS LAST,id DESC LIMIT 200
                """;
        return jdbc.query(sql, Map.of("loanId", loanId), (rs, row) -> new LoanApprovalResponse(
                rs.getLong("id"), clean(rs.getString("tipo")), nullable(rs.getString("acao")),
                clean(rs.getString("status")), clean(rs.getString("descricao")),
                decimal(rs.getBigDecimal("valor")), clean(rs.getString("solicitante_username")),
                nullable(rs.getString("aprovador_username")), nullable(rs.getString("motivo_recusa")),
                dateTime(rs.getTimestamp("dtcad")), dateTime(rs.getTimestamp("dtdecisao"))));
    }

    public List<LoanOriginResponse> origins(long loanId) {
        String sql = """
                WITH RECURSIVE chain(id, depth) AS (
                  SELECT r.emp_id_origem, 1 FROM refinanciamentos r WHERE r.emp_id_destino = :loanId
                  UNION ALL
                  SELECT r.emp_id_origem, c.depth + 1
                  FROM refinanciamentos r JOIN chain c ON r.emp_id_destino = c.id
                  WHERE c.depth < 30
                ), installment_summary AS (
                  SELECT p.emprestimo_id,
                         COUNT(*) FILTER (WHERE p.pendente = true) pending_count,
                         COUNT(*) FILTER (WHERE p.pendente = true AND p.vencimento::date < CURRENT_DATE) overdue_count,
                         COUNT(*) FILTER (WHERE p.pendente = true AND p.vencimento::date = CURRENT_DATE) due_today_count,
                         MIN(p.vencimento) FILTER (WHERE p.pendente = true) next_due_date,
                         MAX(p.vencimento) last_due_date
                  FROM parcelas p WHERE p.emprestimo_id IN (SELECT id FROM chain)
                  GROUP BY p.emprestimo_id
                )
                SELECT e.id, COALESCE(c.nome,''), COALESCE(r.descricao,''),
                       CASE WHEN ci.codigo IS NULL THEN NULL
                            ELSE ci.descricao || ' - ' || COALESCE(ci.uf,'') END,
                       COALESCE(ins.next_due_date,ins.last_due_date),
                       CASE WHEN COALESCE(e.aprovacao_status,'APROVADO') = 'PENDENTE' THEN 'Pendente Aprovação'
                            WHEN e.status = 3 THEN 'Cancelado'
                            WHEN COALESCE(e.refinanciado,false) THEN 'Refinanciado'
                            WHEN COALESCE(e.renovacao,false) THEN 'Renov/Abat'
                            WHEN e.status = 1 THEN 'Lançamento'
                            WHEN COALESCE(e.desaparecido,false) THEN 'Desaparecido'
                            WHEN COALESCE(ins.overdue_count,0) > 0 THEN 'Em atraso'
                            WHEN COALESCE(ins.pending_count,0) = 0 THEN 'Quitado'
                            WHEN COALESCE(ins.due_today_count,0) > 0 THEN 'Vence hoje'
                            ELSE 'Em dia' END described_status,
                       CASE
                            WHEN COALESCE(e.aprovacao_status,'APROVADO') = 'PENDENTE' THEN '#FFFFFF'
                            WHEN e.status = 3 OR e.status = 1 THEN '#FFFFFF'
                            WHEN COALESCE(e.refinanciado,false) THEN '#AAF0B1'
                            WHEN COALESCE(e.renovacao,false) THEN '#CEAAF0'
                            WHEN COALESCE(e.desaparecido,false) THEN '#F54242'
                            WHEN COALESCE(ins.overdue_count,0) > 1 THEN '#FA8282'
                            WHEN COALESCE(ins.overdue_count,0) = 1 THEN '#FCF883'
                            WHEN COALESCE(ins.pending_count,0) = 0 THEN '#CEAAF0'
                            WHEN COALESCE(ins.due_today_count,0) > 0 THEN '#FFFFFF'
                            WHEN e.tipo IN ('S','Q','M','Z','B','C') THEN '#ADD8E6'
                            ELSE '#AAF0B1' END status_color,
                       COALESCE(e.valor_emprestado,0),
                       COALESCE((SELECT SUM(pg.valor) FROM pagamentos pg
                                JOIN parcelas pp ON pp.id=pg.parcela_id
                                WHERE pp.emprestimo_id=e.id
                                  AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'),0),
                       COALESCE((SELECT SUM(GREATEST(
                                    COALESCE(pp.valor,0)+COALESCE(pp.valor_juros,0)-COALESCE((
                                      SELECT SUM(pg.valor) FROM pagamentos pg
                                      WHERE pg.parcela_id=pp.id
                                        AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                                        AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0),0))
                                 FROM parcelas pp
                                 WHERE pp.emprestimo_id=e.id AND pp.pendente=true),0),
                       COALESCE(public.calcular_lucro_fluxo(e.id),0),
                       CASE e.tipo WHEN 'D' THEN 'Diário' WHEN 'S' THEN 'Semanal'
                            WHEN 'Q' THEN 'Quinzenal' WHEN 'M' THEN 'Mensal'
                            WHEN 'Z' THEN 'Diário Seg-Sab' WHEN 'A' THEN 'Dia sim e Dia não'
                            WHEN 'B' THEN 'Todo Sábado' WHEN 'C' THEN 'Todo Domingo' ELSE '' END,
                       EXISTS (SELECT 1 FROM refinanciamentos rf WHERE rf.emp_id_destino=e.id),
                       ch.depth
                FROM chain ch JOIN emprestimo e ON e.id = ch.id
                JOIN cliente c ON c.id = e.cliente_id
                JOIN regioes r ON r.id = c.regiao_id
                LEFT JOIN cidade ci ON ci.codigo = c.cidade_id
                LEFT JOIN installment_summary ins ON ins.emprestimo_id=e.id
                ORDER BY ch.depth
                """;
        return jdbc.query(sql, Map.of("loanId", loanId), (rs, row) -> new LoanOriginResponse(
                rs.getLong(1), clean(rs.getString(2)), clean(rs.getString(3)), nullable(rs.getString(4)),
                dateTime(rs.getTimestamp(5)), clean(rs.getString(6)), clean(rs.getString(7)),
                decimal(rs.getBigDecimal(8)), decimal(rs.getBigDecimal(9)), decimal(rs.getBigDecimal(10)),
                decimal(rs.getBigDecimal(11)), clean(rs.getString(12)), rs.getBoolean(13)));
    }

    public int paymentCount(long loanId) {
        Integer value = jdbc.queryForObject("""
                SELECT COUNT(*) FROM pagamentos pg JOIN parcelas p ON p.id = pg.parcela_id
                WHERE p.emprestimo_id = :loanId
                """, Map.of("loanId", loanId), Integer.class);
        return value == null ? 0 : value;
    }

    public void requireAccessibleClient(long userId, long clientId) {
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM cliente c
                WHERE c.id=:clientId AND COALESCE(c.ativo,true)=true
                  AND EXISTS (SELECT 1 FROM regiao_usuario ru
                              WHERE ru.usuario_id=:userId AND ru.regiao_id=c.regiao_id)
                """, Map.of("userId", userId, "clientId", clientId), Integer.class);
        if (count == null || count == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND,
                    "Cliente não encontrado ou não permitido para este usuário.");
        }
    }

    public long insertLoan(long clientId, LocalDate contractDate, LocalDate firstDueDate,
                           int installments, String notes, String paymentType,
                           BigDecimal principal, BigDecimal discount, BigDecimal interest,
                           BigDecimal lateFee, String collateral, String clientOwner,
                           boolean missing, String approvalStatus) {
        BigDecimal total = principal.add(interest).subtract(discount).setScale(2, RoundingMode.HALF_UP);
        KeyHolder key = new GeneratedKeyHolder();
        jdbc.update("""
                INSERT INTO emprestimo (cliente_id,data,data_privencimento,parcela,observacoes,tipo,
                    valor_emprestado,vlr_desconto,juros,vlrmulta,vlr_recebido,vlr_receber,
                    vlr_lucro,ativo,refinanciado,renovacao,dono_cliente,status,
                    aprovacao_status,desaparecido,penhora,dtcad,dtalter)
                VALUES (:clientId,:contractDate,:firstDueDate,:installments,:notes,:paymentType,
                    :principal,:discount,:interest,:lateFee,0,:total,0,true,false,false,
                    :clientOwner,1,:approvalStatus,:missing,:collateral,NOW(),NOW())
                """, new MapSqlParameterSource().addValue("clientId", clientId)
                .addValue("contractDate", Timestamp.valueOf(contractDate.atTime(12, 0)))
                .addValue("firstDueDate", Timestamp.valueOf(firstDueDate.atTime(12, 0)))
                .addValue("installments", installments).addValue("notes", notes)
                .addValue("paymentType", paymentType).addValue("principal", principal)
                .addValue("discount", discount).addValue("interest", interest)
                .addValue("lateFee", lateFee).addValue("total", total)
                .addValue("clientOwner", clientOwner).addValue("approvalStatus", approvalStatus)
                .addValue("missing", missing).addValue("collateral", collateral),
                key, new String[]{"id"});
        Number value = key.getKey();
        if (value == null) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "O novo empréstimo não pôde ser criado.");
        }
        return value.longValue();
    }

    public void updateLoan(long loanId, MapSqlParameterSource parameters) {
        parameters.addValue("loanId", loanId);
        jdbc.update("""
                UPDATE emprestimo SET data=:contractDate, data_privencimento=:firstDueDate,
                    parcela=:installmentCount, observacoes=:notes, tipo=:paymentType,
                    valor_emprestado=:loanedAmount, vlr_desconto=:discountAmount,
                    juros=:interestAmount, vlrmulta=:lateFeeAmount, penhora=:collateral,
                    vlr_receber=:totalAmount, vlr_lucro=:profitAmount,
                    dono_cliente=:clientOwner, desaparecido=:missing, dtalter=NOW()
                WHERE id=:loanId
                """, parameters);
    }

    public void deleteInstallments(long loanId) {
        jdbc.update("DELETE FROM parcelas WHERE emprestimo_id=:loanId", Map.of("loanId", loanId));
    }

    public void insertInstallments(long loanId, List<InstallmentSeed> installments) {
        MapSqlParameterSource[] batch = installments.stream().map(seed -> new MapSqlParameterSource()
                .addValue("loanId", loanId).addValue("number", seed.number())
                .addValue("dueDate", Timestamp.valueOf(seed.dueDate().atTime(12, 0)))
                .addValue("amount", seed.amount()).addValue("now", Timestamp.valueOf(LocalDateTime.now())))
                .toArray(MapSqlParameterSource[]::new);
        jdbc.batchUpdate("""
                INSERT INTO parcelas (emprestimo_id, parcela, vencimento, valor, valor_juros,
                                      pendente, dtcad, dtalter)
                VALUES (:loanId,:number,:dueDate,:amount,0,true,:now,:now)
                """, batch);
    }

    public InstallmentSnapshot requireInstallment(long loanId, long installmentId) {
        List<InstallmentSnapshot> values = jdbc.query("""
                SELECT p.id, p.vencimento, p.valor, COALESCE(p.valor_juros,0),
                       COALESCE(SUM(pg.valor) FILTER (
                           WHERE COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                             AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0)
                FROM parcelas p LEFT JOIN pagamentos pg ON pg.parcela_id=p.id
                WHERE p.id=:installmentId AND p.emprestimo_id=:loanId GROUP BY p.id
                """, Map.of("loanId", loanId, "installmentId", installmentId), (rs, row) ->
                new InstallmentSnapshot(rs.getLong(1), dateTime(rs.getTimestamp(2)), decimal(rs.getBigDecimal(3)),
                        decimal(rs.getBigDecimal(4)), decimal(rs.getBigDecimal(5))));
        if (values.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "Parcela não encontrada.");
        return values.get(0);
    }

    public InstallmentMessageSnapshot requireInstallmentMessage(long loanId, long installmentId) {
        List<InstallmentMessageSnapshot> values = jdbc.query("""
                SELECT c.nome, p.link, r.mensagem_cobranca,
                       r.mensagem_cobranca_link, r.mensagem_atraso
                FROM parcelas p
                JOIN emprestimo e ON e.id=p.emprestimo_id
                JOIN cliente c ON c.id=e.cliente_id
                JOIN regioes r ON r.id=c.regiao_id
                WHERE p.id=:installmentId AND p.emprestimo_id=:loanId
                """, Map.of("loanId", loanId, "installmentId", installmentId), (rs, row) ->
                new InstallmentMessageSnapshot(
                        clean(rs.getString("nome")), nullable(rs.getString("link")),
                        nullable(rs.getString("mensagem_cobranca")),
                        nullable(rs.getString("mensagem_cobranca_link")),
                        nullable(rs.getString("mensagem_atraso"))));
        if (values.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "Parcela não encontrada.");
        return values.get(0);
    }

    public ContractMessageSnapshot requireContractMessage(long loanId) {
        List<ContractMessageSnapshot> values = jdbc.query("""
                SELECT c.nome, c.endereco, c.bairro, c.numero, c.cep, c.comercio,
                       ci.descricao AS cidade, ci.uf,
                       r.mensagem_emprestimo, r.mensagem_emprestimo_refinanciado
                FROM emprestimo e
                JOIN cliente c ON c.id=e.cliente_id
                JOIN regioes r ON r.id=c.regiao_id
                LEFT JOIN cidade ci ON ci.codigo=c.cidade_id
                WHERE e.id=:loanId
                """, Map.of("loanId", loanId), (rs, row) ->
                new ContractMessageSnapshot(
                        clean(rs.getString("nome")), nullable(rs.getString("endereco")),
                        nullable(rs.getString("bairro")), nullable(rs.getString("numero")),
                        nullable(rs.getString("cep")), nullable(rs.getString("comercio")),
                        nullable(rs.getString("cidade")), nullable(rs.getString("uf")),
                        nullable(rs.getString("mensagem_emprestimo")),
                        nullable(rs.getString("mensagem_emprestimo_refinanciado"))));
        if (values.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Empréstimo não encontrado.");
        }
        return values.get(0);
    }

    public void updateInstallment(long installmentId, LocalDate dueDate, BigDecimal amount,
                                  BigDecimal interest, String note) {
        jdbc.update("""
                UPDATE parcelas SET vencimento=:dueDate, valor=:amount, valor_juros=:interest,
                    observacao_vencimento=:note, dtalter=NOW() WHERE id=:id
                """, new MapSqlParameterSource().addValue("id", installmentId)
                .addValue("dueDate", Timestamp.valueOf(dueDate.atTime(12, 0)))
                .addValue("amount", amount).addValue("interest", interest).addValue("note", note));
    }

    public int renumberInstallmentsByDueDate(long loanId) {
        return jdbc.update("""
                WITH ordered AS (
                    SELECT p.id,
                           CAST(ROW_NUMBER() OVER (ORDER BY p.vencimento, p.id) AS text) AS new_number
                    FROM parcelas p
                    WHERE p.emprestimo_id=:loanId
                )
                UPDATE parcelas p
                SET parcela=ordered.new_number, dtalter=NOW()
                FROM ordered
                WHERE p.id=ordered.id
                  AND p.parcela IS DISTINCT FROM ordered.new_number
                """, Map.of("loanId", loanId));
    }

    public long insertPayment(long loanId, long installmentId, BigDecimal amount, LocalDate date,
                              String note, String approvalStatus) {
        return insertPayment(loanId, installmentId, amount, date, note, approvalStatus, "NORMAL");
    }

    public long insertPayment(long loanId, long installmentId, BigDecimal amount, LocalDate date,
                              String note, String approvalStatus, String type) {
        KeyHolder key = new GeneratedKeyHolder();
        jdbc.update("""
                INSERT INTO pagamentos (parcela_id, emprestimo_id, data, valor, observacao,
                                        automatico, aprovacao_status, tipo, dtcad, dtalter)
                VALUES (:installmentId,:loanId,:date,:amount,:note,false,:approvalStatus,:type,NOW(),NOW())
                """, new MapSqlParameterSource().addValue("installmentId", installmentId)
                .addValue("loanId", loanId).addValue("date", Timestamp.valueOf(date.atTime(12, 0)))
                .addValue("amount", amount).addValue("note", note).addValue("approvalStatus", approvalStatus)
                .addValue("type", type),
                key, new String[]{"id_pagamento"});
        Number value = key.getKey();
        if (value == null) throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Pagamento não foi criado.");
        return value.longValue();
    }

    public PaymentSnapshot requirePayment(long loanId, long installmentId, long paymentId) {
        List<PaymentSnapshot> values = jdbc.query("""
                SELECT pg.id_pagamento, pg.valor, COALESCE(pg.automatico,false),
                       COALESCE(pg.aprovacao_status,'APROVADO'),COALESCE(pg.tipo,'NORMAL')
                FROM pagamentos pg JOIN parcelas p ON p.id=pg.parcela_id
                WHERE pg.id_pagamento=:paymentId AND pg.parcela_id=:installmentId AND p.emprestimo_id=:loanId
                """, Map.of("loanId", loanId, "installmentId", installmentId, "paymentId", paymentId),
                (rs, row) -> new PaymentSnapshot(rs.getLong(1), decimal(rs.getBigDecimal(2)),
                        rs.getBoolean(3), clean(rs.getString(4)), clean(rs.getString(5))));
        if (values.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "Pagamento não encontrado.");
        return values.get(0);
    }

    public void updatePayment(long paymentId, BigDecimal amount, LocalDate date, String note, String status) {
        jdbc.update("""
                UPDATE pagamentos SET valor=:amount, data=:date, observacao=:note,
                    aprovacao_status=:status, dtalter=NOW() WHERE id_pagamento=:id
                """, new MapSqlParameterSource().addValue("id", paymentId).addValue("amount", amount)
                .addValue("date", Timestamp.valueOf(date.atTime(12, 0))).addValue("note", note)
                .addValue("status", status));
    }

    public void deletePayment(long paymentId) {
        jdbc.update("DELETE FROM aprovacoes WHERE tipo='PAGAMENTO' AND entidade_id=:id", Map.of("id", paymentId));
        jdbc.update("DELETE FROM pagamentos WHERE id_pagamento=:id", Map.of("id", paymentId));
    }

    public void synchronizeInstallment(long installmentId) {
        jdbc.update("""
                UPDATE parcelas p SET pendente=ROUND(COALESCE((SELECT SUM(pg.valor)
                    FROM pagamentos pg
                    WHERE pg.parcela_id=p.id AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                      AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0)::numeric,2)
                    < ROUND((COALESCE(p.valor,0)+COALESCE(p.valor_juros,0))::numeric,2),
                    status=NULL,dtalter=NOW()
                WHERE p.id=:id
                """, Map.of("id", installmentId));
    }

    public void refreshLoanFinancialTotals(long loanId) {
        jdbc.queryForObject("SELECT set_config('myapp.skip_trigger','1',true)",
                Map.of(), String.class);
        jdbc.update("""
                UPDATE emprestimo e
                SET status=2,dtalter=NOW()
                WHERE e.id=:loanId
                  AND e.status=1
                  AND EXISTS (
                      SELECT 1
                      FROM pagamentos pg
                      JOIN parcelas p ON p.id=pg.parcela_id
                      WHERE p.emprestimo_id=e.id
                        AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                  )
                """, Map.of("loanId", loanId));
        jdbc.update("""
                UPDATE emprestimo e SET
                    vlr_receber = ROUND((CASE
                        WHEN COALESCE(e.aprovacao_status,'APROVADO')='PENDENTE'
                          OR e.status IN (1,3)
                          OR COALESCE(e.refinanciado,false)
                          OR COALESCE(e.renovacao,false)
                        THEN 0
                        ELSE COALESCE((
                            SELECT SUM(GREATEST(
                                COALESCE(p.valor,0)+COALESCE(p.valor_juros,0)-COALESCE((
                                    SELECT SUM(pg.valor) FROM pagamentos pg
                                    WHERE pg.parcela_id=p.id
                                      AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                                      AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'
                                ),0),0))
                            FROM parcelas p
                            WHERE p.emprestimo_id=e.id AND p.pendente=true
                        ),0)
                    END)::numeric,2),
                    vlr_recebido = ROUND(COALESCE((
                        SELECT SUM(pg.valor)
                        FROM pagamentos pg
                        JOIN parcelas p ON p.id=pg.parcela_id
                        WHERE p.emprestimo_id=e.id
                          AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                    ),0)::numeric,2),
                    vlr_lucro = ROUND((CASE
                        WHEN COALESCE(e.aprovacao_status,'APROVADO')='PENDENTE'
                          OR e.status=3 THEN 0
                        ELSE GREATEST(COALESCE(public.calcular_lucro_fluxo(e.id),0),0)
                    END)::numeric,2),
                    dtalter=NOW()
                WHERE e.id=:loanId
                """, Map.of("loanId", loanId));
        jdbc.queryForObject("SELECT set_config('myapp.skip_trigger','0',true)",
                Map.of(), String.class);
    }

    public int transitionPreviousDayLaunches() {
        return jdbc.update("""
                WITH transitioned AS (
                    UPDATE emprestimo e
                    SET status=2, dtalter=NOW()
                    WHERE e.status=1
                      AND COALESCE(e.aprovacao_status,'APROVADO')='APROVADO'
                      AND COALESCE((
                          SELECT MAX(a.dtdecisao)
                          FROM aprovacoes a
                          WHERE (a.emprestimo_id=e.id OR a.entidade_id=e.id)
                            AND a.tipo IN ('EMPRESTIMO','REFINANCIAMENTO','RENOVACAO')
                            AND a.status='APROVADO'
                      ), e.dtcad)::date < CURRENT_DATE
                    RETURNING e.id
                )
                INSERT INTO entity_log_detalhado
                    (entity_name,entity_id,operation,description,username,timestamp)
                SELECT 'EMPRESTIMO',id,'ativarEmprestimoAutomaticamente',
                       'Contrato saiu de Lançamento automaticamente na virada do dia após a aprovação.',
                       'SISTEMA',NOW()
                FROM transitioned
                """, Map.of());
    }

    public void updateInstallmentDueDate(long installmentId, LocalDate dueDate, String note) {
        jdbc.update("""
                UPDATE parcelas SET vencimento=:dueDate,pendente=true,status=NULL,
                    observacao_vencimento=:note,dtalter=NOW() WHERE id=:id
                """, new MapSqlParameterSource().addValue("id", installmentId)
                .addValue("dueDate", Timestamp.valueOf(dueDate.atTime(12, 0)))
                .addValue("note", note));
    }

    public void insertInterestRollRequest(long approvalId, long paymentId, long installmentId,
                                          LocalDate previousDueDate, LocalDate newDueDate) {
        jdbc.update("""
                INSERT INTO money2_interest_roll_requests
                    (approval_id,payment_id,installment_id,previous_due_date,new_due_date,applied,created_at)
                VALUES (:approvalId,:paymentId,:installmentId,:previousDue,:newDue,false,NOW())
                """, new MapSqlParameterSource().addValue("approvalId", approvalId)
                .addValue("paymentId", paymentId).addValue("installmentId", installmentId)
                .addValue("previousDue", Timestamp.valueOf(previousDueDate.atTime(12, 0)))
                .addValue("newDue", Timestamp.valueOf(newDueDate.atTime(12, 0))));
    }

    public void applyDeferredInterestRollIfPresent(long approvalId) {
        List<InterestRollSnapshot> rows = jdbc.query("""
                SELECT installment_id,new_due_date FROM money2_interest_roll_requests
                WHERE approval_id=:approvalId AND applied=false FOR UPDATE
                """, Map.of("approvalId", approvalId), (rs, row) -> new InterestRollSnapshot(
                rs.getLong(1), dateTime(rs.getTimestamp(2))));
        if (rows.isEmpty()) return;
        InterestRollSnapshot value = rows.get(0);
        updateInstallmentDueDate(value.installmentId(), value.newDueDate().toLocalDate(),
                "Vencimento prorrogado após baixa somente dos juros.");
        jdbc.update("""
                UPDATE money2_interest_roll_requests SET applied=true,processed_at=NOW()
                WHERE approval_id=:approvalId
                """, Map.of("approvalId", approvalId));
    }

    public long createApproval(LoanSnapshot loan, String type, String action, Long entityId,
                               Long installmentId, BigDecimal amount, String username, String description,
                               String group) {
        KeyHolder key = new GeneratedKeyHolder();
        jdbc.update("""
                INSERT INTO aprovacoes (tipo,status,entidade_id,emprestimo_id,parcela_id,regiao_id,
                    solicitante_username,solicitante_nome,descricao,valor,grupo_aprovacao,
                    pagamento_contrato,acao,dtcad,dtalter,recusa_confirmada)
                VALUES (:type,'PENDENTE',:entityId,:loanId,:installmentId,:regionId,
                    :username,:username,:description,:amount,:group,:contractPayment,:action,NOW(),NOW(),false)
                """, new MapSqlParameterSource().addValue("type", type).addValue("entityId", entityId)
                .addValue("loanId", loan.id()).addValue("installmentId", installmentId)
                .addValue("regionId", loan.regionId()).addValue("username", username)
                .addValue("description", description).addValue("amount", amount).addValue("group", group)
                .addValue("contractPayment", group != null).addValue("action", action), key, new String[]{"id"});
        return key.getKey().longValue();
    }

    public void log(String entity, long entityId, String operation, String description, String username) {
        jdbc.update("""
                INSERT INTO entity_log_detalhado
                    (entity_name,entity_id,operation,description,username,timestamp)
                VALUES (:entity,:entityId,:operation,:description,:username,NOW())
                """, Map.of("entity", entity, "entityId", entityId, "operation", operation,
                "description", description, "username", username));
    }

    public ApprovalSnapshot requirePendingApproval(long userId, long loanId, long approvalId) {
        List<ApprovalSnapshot> values = jdbc.query("""
                SELECT a.id,a.tipo,a.acao,a.entidade_id,a.emprestimo_id,a.emprestimo_origem_id,a.parcela_id,
                       a.status,a.valor,a.valor_original,a.valor_devedor,a.vlr_juros,a.perc_juros,a.valor_total
                FROM aprovacoes a
                WHERE a.id=:approvalId AND (a.emprestimo_id=:loanId OR a.emprestimo_origem_id=:loanId)
                  AND EXISTS (SELECT 1 FROM regiao_usuario ru WHERE ru.usuario_id=:userId AND ru.regiao_id=a.regiao_id)
                FOR UPDATE OF a
                """, Map.of("userId", userId, "loanId", loanId, "approvalId", approvalId), (rs, row) ->
                new ApprovalSnapshot(rs.getLong(1), clean(rs.getString(2)), nullable(rs.getString(3)),
                        rs.getObject(4, Long.class), rs.getObject(5, Long.class), rs.getObject(6, Long.class),
                        rs.getObject(7, Long.class), clean(rs.getString(8)), decimal(rs.getBigDecimal(9)),
                        decimal(rs.getBigDecimal(10)), decimal(rs.getBigDecimal(11)), decimal(rs.getBigDecimal(12)),
                        decimal(rs.getBigDecimal(13)), decimal(rs.getBigDecimal(14))));
        if (values.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "Conferência não encontrada.");
        return values.get(0);
    }

    public ApprovalSnapshot lockExpiredPaymentApproval(long loanId, long approvalId) {
        List<ApprovalSnapshot> values = jdbc.query("""
                SELECT a.id,a.tipo,a.acao,a.entidade_id,a.emprestimo_id,a.emprestimo_origem_id,a.parcela_id,
                       a.status,a.valor,a.valor_original,a.valor_devedor,a.vlr_juros,a.perc_juros,a.valor_total
                FROM aprovacoes a
                WHERE a.id=:approvalId AND a.emprestimo_id=:loanId
                  AND a.tipo='PAGAMENTO' AND a.status='PENDENTE'
                  AND a.dtcad < NOW() - INTERVAL '30 days'
                FOR UPDATE OF a SKIP LOCKED
                """, Map.of("loanId", loanId, "approvalId", approvalId), (rs, row) ->
                new ApprovalSnapshot(rs.getLong(1), clean(rs.getString(2)), nullable(rs.getString(3)),
                        rs.getObject(4, Long.class), rs.getObject(5, Long.class), rs.getObject(6, Long.class),
                        rs.getObject(7, Long.class), clean(rs.getString(8)), decimal(rs.getBigDecimal(9)),
                        decimal(rs.getBigDecimal(10)), decimal(rs.getBigDecimal(11)), decimal(rs.getBigDecimal(12)),
                        decimal(rs.getBigDecimal(13)), decimal(rs.getBigDecimal(14))));
        return values.isEmpty() ? null : values.get(0);
    }

    public void decideApproval(long approvalId, String status, String username, String reason) {
        jdbc.update("""
                UPDATE aprovacoes SET status=:status, aprovador_username=:username,
                    motivo_recusa=:reason, dtdecisao=NOW(), dtalter=NOW(), recusa_confirmada=true,
                    dtconfirmacao_recusa=NOW() WHERE id=:id
                """, Map.of("status", status, "username", username, "reason", reason == null ? "" : reason,
                "id", approvalId));
    }

    public void setPaymentApproval(long paymentId, String status) {
        jdbc.update("UPDATE pagamentos SET aprovacao_status=:status,dtalter=NOW() WHERE id_pagamento=:id",
                Map.of("status", status, "id", paymentId));
    }

    public void setLoanApproval(long loanId, String status) {
        jdbc.update("UPDATE emprestimo SET aprovacao_status=:status,dtalter=NOW() WHERE id=:id",
                Map.of("status", status, "id", loanId));
    }

    public void cancelLoan(long loanId) {
        jdbc.update("UPDATE emprestimo SET status=3,aprovacao_status='APROVADO',dtalter=NOW() WHERE id=:id",
                Map.of("id", loanId));
    }

    public void deleteLoan(long loanId) {
        jdbc.update("DELETE FROM aprovacoes WHERE emprestimo_id=:id OR emprestimo_origem_id=:id", Map.of("id", loanId));
        jdbc.update("DELETE FROM pagamentos WHERE emprestimo_id=:id OR parcela_id IN (SELECT id FROM parcelas WHERE emprestimo_id=:id)", Map.of("id", loanId));
        jdbc.update("DELETE FROM parcelas WHERE emprestimo_id=:id", Map.of("id", loanId));
        jdbc.update("DELETE FROM emprestimo WHERE id=:id", Map.of("id", loanId));
    }

    public void linkRejectedNegotiationToOrigin(long approvalId, long originLoanId) {
        jdbc.update("""
                UPDATE aprovacoes
                SET emprestimo_id=:originLoanId, emprestimo_origem_id=:originLoanId, dtalter=NOW()
                WHERE id=:approvalId
                """, Map.of("approvalId", approvalId, "originLoanId", originLoanId));
    }

    public void deleteLoanPreservingApproval(long loanId, long approvalId) {
        jdbc.update("""
                DELETE FROM aprovacoes
                WHERE (emprestimo_id=:loanId OR emprestimo_origem_id=:loanId)
                  AND id<>:approvalId
                """, Map.of("loanId", loanId, "approvalId", approvalId));
        jdbc.update("DELETE FROM pagamentos WHERE emprestimo_id=:id OR parcela_id IN (SELECT id FROM parcelas WHERE emprestimo_id=:id)", Map.of("id", loanId));
        jdbc.update("DELETE FROM parcelas WHERE emprestimo_id=:id", Map.of("id", loanId));
        jdbc.update("DELETE FROM emprestimo WHERE id=:id", Map.of("id", loanId));
    }

    public long insertNegotiatedLoan(LoanSnapshot origin, BigDecimal principal, BigDecimal interest,
                                     BigDecimal profit,
                                     int installments, LocalDate firstDueDate, String paymentType,
                                     String notes, String approvalStatus) {
        BigDecimal total = principal.add(interest).setScale(2, RoundingMode.HALF_UP);
        KeyHolder key = new GeneratedKeyHolder();
        jdbc.update("""
                INSERT INTO emprestimo (cliente_id,data,data_privencimento,parcela,observacoes,tipo,
                    valor_emprestado,vlr_desconto,juros,vlrmulta,vlr_recebido,vlr_receber,vlr_lucro,
                    ativo,refinanciado,renovacao,
                    dono_cliente,status,aprovacao_status,desaparecido,penhora,dtcad,dtalter)
                VALUES (:clientId,NOW(),:firstDueDate,:installments,:notes,:paymentType,
                    :principal,0,:interest,:lateFee,0,:total,:profit,true,false,false,:clientOwner,2,
                    :approvalStatus,:missing,:collateral,NOW(),NOW())
                """, new MapSqlParameterSource().addValue("clientId", origin.clientId())
                .addValue("firstDueDate", Timestamp.valueOf(firstDueDate.atTime(12, 0)))
                .addValue("installments", installments).addValue("notes", notes)
                .addValue("paymentType", paymentType).addValue("principal", principal)
                .addValue("interest", interest).addValue("lateFee", origin.lateFee())
                .addValue("total", total).addValue("profit", profit)
                .addValue("clientOwner", origin.clientOwner()).addValue("approvalStatus", approvalStatus)
                .addValue("missing", origin.missing())
                .addValue("collateral", origin.collateral()), key, new String[]{"id"});
        Number value = key.getKey();
        if (value == null) throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Novo contrato não foi criado.");
        return value.longValue();
    }

    public void insertRefinancing(long originId, long destinationId, BigDecimal originalAmount,
                                  BigDecimal debtAmount, BigDecimal interestAmount,
                                  BigDecimal interestPercent, BigDecimal totalAmount) {
        jdbc.update("""
                INSERT INTO refinanciamentos (emp_id_origem,emp_id_destino,valor_original,
                    valor_devedor,vlr_juros,perc_juros,valor_total,dtcad,dtalter)
                VALUES (:originId,:destinationId,:original,:debt,:interest,:percent,:total,NOW(),NOW())
                """, new MapSqlParameterSource().addValue("originId", originId)
                .addValue("destinationId", destinationId).addValue("original", originalAmount)
                .addValue("debt", debtAmount).addValue("interest", interestAmount)
                .addValue("percent", interestPercent).addValue("total", totalAmount));
    }

    public void setNegotiatedOrigin(long originId, boolean renewal) {
        jdbc.update(renewal
                        ? "UPDATE emprestimo SET renovacao=true,aprovacao_status='APROVADO',dtalter=NOW() WHERE id=:id"
                        : "UPDATE emprestimo SET refinanciado=true,aprovacao_status='APROVADO',dtalter=NOW() WHERE id=:id",
                Map.of("id", originId));
    }

    public void setApprovalNegotiationData(long approvalId, long originId, BigDecimal original,
                                           BigDecimal debt, BigDecimal interest, BigDecimal percent,
                                           BigDecimal total) {
        jdbc.update("""
                UPDATE aprovacoes SET emprestimo_origem_id=:originId,valor_original=:original,
                    valor_devedor=:debt,vlr_juros=:interest,perc_juros=:percent,valor_total=:total
                WHERE id=:id
                """, new MapSqlParameterSource().addValue("id", approvalId).addValue("originId", originId)
                .addValue("original", original).addValue("debt", debt).addValue("interest", interest)
                .addValue("percent", percent).addValue("total", total));
    }

    public record LoanSnapshot(long id, long clientId, String clientName, long regionId, String regionName,
            LocalDateTime contractDate, LocalDateTime firstDueDate, int installmentCount, String notes,
            String paymentType, BigDecimal loaned, BigDecimal originalLoanAmount,
            BigDecimal discount, BigDecimal interest, BigDecimal lateFee,
            BigDecimal received, BigDecimal receivable, BigDecimal profit,
            String collateral, String clientOwner,
            boolean missing, boolean active, boolean refinanced, boolean renewed, int numericStatus,
            String status, String approvalStatus, boolean operationLocked) { }
    public record InstallmentSnapshot(long id, LocalDateTime dueDate, BigDecimal amount,
            BigDecimal interest, BigDecimal paid) { }
    public record InstallmentMessageSnapshot(String clientName, String link,
            String collectionMessage, String collectionLinkMessage, String overdueMessage) { }
    public record ContractMessageSnapshot(String clientName, String address, String neighborhood,
            String number, String postalCode, String business, String city, String state,
            String loanMessage, String refinancedLoanMessage) { }
    public record PaymentSnapshot(long id, BigDecimal amount, boolean automatic,
            String approvalStatus, String type) { }
    private record InterestRollSnapshot(long installmentId, LocalDateTime newDueDate) { }
    public record InstallmentSeed(String number, LocalDate dueDate, BigDecimal amount) { }
    public record ApprovalSnapshot(long id, String type, String action, Long entityId, Long loanId,
            Long originLoanId, Long installmentId, String status, BigDecimal amount,
            BigDecimal originalAmount, BigDecimal debtAmount, BigDecimal interestAmount,
            BigDecimal interestPercent, BigDecimal totalAmount) { }

    private static BigDecimal decimal(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value).setScale(2, RoundingMode.HALF_UP);
    }
    private static BigDecimal nullableDecimal(BigDecimal value) {
        return value == null ? null : value.setScale(2, RoundingMode.HALF_UP);
    }
    private static BigDecimal zero() { return BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP); }
    private static LocalDateTime dateTime(Timestamp value) { return value == null ? null : value.toLocalDateTime(); }
    private static String nullable(String value) { String clean = clean(value); return clean.isEmpty() ? null : clean; }
    private static String clean(String value) { return value == null ? "" : value.trim(); }
}
