package com.webdigital.money2.integrations;

import com.webdigital.money2.shared.ApiException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;

@Repository
public class PixRepository {

    private static final String CHARGE_COLUMNS = """
            p.id,p.emprestimo_id,p.parcela_id,p.pagamento_id,p.conta_bancaria_configuracao_id,
            p.txid,p.valor,p.status,p.pix_copia_cola,p.qr_code,p.location,p.erro,
            COALESCE(p.pagamento_processado,false) pagamento_processado,p.dt_pagamento,p.dtcad,p.dtalter
            """;

    private final NamedParameterJdbcTemplate jdbc;

    public PixRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public BankConfig bankForRegion(long regionId) {
        List<BankConfig> rows = jdbc.query("""
                SELECT c.id,c.client_id,c.client_secret,c.chave_pix,c.token_url,c.api_base_url,
                       c.certificado_path,c.chave_privada_path,c.cadeia_certificados_path,c.dtalter
                FROM conta_bancaria_configuracao c
                WHERE COALESCE(c.ativo,false)=true
                  AND COALESCE(c.banco,'SICREDI')='SICREDI'
                  AND (EXISTS (SELECT 1 FROM conta_bancaria_regiao cr
                               WHERE cr.conta_bancaria_configuracao_id=c.id AND cr.regiao_id=:regionId)
                       OR (NOT EXISTS (SELECT 1 FROM conta_bancaria_regiao cr
                                       WHERE cr.conta_bancaria_configuracao_id=c.id)
                           AND c.regiao_id=:regionId))
                ORDER BY c.id LIMIT 1
                """, Map.of("regionId", regionId), (rs, row) -> new BankConfig(
                rs.getLong("id"), nullable(rs.getString("client_id")), nullable(rs.getString("client_secret")),
                nullable(rs.getString("chave_pix")), nullable(rs.getString("token_url")),
                nullable(rs.getString("api_base_url")), nullable(rs.getString("certificado_path")),
                nullable(rs.getString("chave_privada_path")), nullable(rs.getString("cadeia_certificados_path")),
                dateTime(rs.getTimestamp("dtalter"))));
        if (rows.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "Nenhuma conta Sicredi ativa está vinculada à região deste contrato.");
        }
        return rows.get(0);
    }

    public PixChargeResponse current(long userId, long loanId, Long installmentId) {
        String installment = installmentId == null ? "p.parcela_id IS NULL" : "p.parcela_id=:installmentId";
        MapSqlParameterSource values = new MapSqlParameterSource().addValue("userId", userId)
                .addValue("loanId", loanId).addValue("installmentId", installmentId);
        List<PixChargeResponse> rows = jdbc.query("SELECT " + CHARGE_COLUMNS + """
                FROM pix_cobrancas p
                JOIN emprestimo e ON e.id=p.emprestimo_id
                JOIN cliente c ON c.id=e.cliente_id
                WHERE p.emprestimo_id=:loanId AND
                """ + installment + """
                  AND UPPER(COALESCE(p.status,'')) <> 'CANCELADO'
                  AND NULLIF(trim(COALESCE(p.pix_copia_cola,'')),'') IS NOT NULL
                  AND EXISTS (SELECT 1 FROM regiao_usuario ru
                              WHERE ru.usuario_id=:userId AND ru.regiao_id=c.regiao_id)
                ORDER BY p.dtcad DESC NULLS LAST,p.id DESC LIMIT 1
                """, values, (rs, row) -> charge(rs));
        return rows.isEmpty() ? null : rows.get(0);
    }

    public ChargeState requireCharge(long userId, long pixId) {
        List<ChargeState> rows = jdbc.query("SELECT " + CHARGE_COLUMNS + """
                       ,c.nome cliente_nome,c.regiao_id,
                       COALESCE(
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.celular,''),'[^0-9]','','g'))>=10 THEN c.celular END,
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.telefone,''),'[^0-9]','','g'))>=10 THEN c.telefone END,
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.telefone2,''),'[^0-9]','','g'))>=10 THEN c.telefone2 END
                       ) telefone,
                       COALESCE(p.confirmacao_whatsapp_enviada,false) confirmacao_enviada,
                       p.dt_tentativa_whatsapp IS NOT NULL confirmacao_tentada
                FROM pix_cobrancas p
                JOIN emprestimo e ON e.id=p.emprestimo_id
                JOIN cliente c ON c.id=e.cliente_id
                WHERE p.id=:pixId AND EXISTS (SELECT 1 FROM regiao_usuario ru
                    WHERE ru.usuario_id=:userId AND ru.regiao_id=c.regiao_id)
                """, Map.of("userId", userId, "pixId", pixId), (rs, row) -> new ChargeState(
                    charge(rs), clean(rs.getString("cliente_nome")), rs.getLong("regiao_id"),
                nullable(rs.getString("telefone")), rs.getBoolean("confirmacao_enviada"),
                rs.getBoolean("confirmacao_tentada")));
        if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "Cobrança PIX não encontrada.");
        return rows.get(0);
    }

    public ChargeState requireChargeForUpdate(long pixId) {
        List<ChargeState> rows = jdbc.query("SELECT " + CHARGE_COLUMNS + """
                       ,c.nome cliente_nome,c.regiao_id,
                       COALESCE(
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.celular,''),'[^0-9]','','g'))>=10 THEN c.celular END,
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.telefone,''),'[^0-9]','','g'))>=10 THEN c.telefone END,
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.telefone2,''),'[^0-9]','','g'))>=10 THEN c.telefone2 END
                       ) telefone,
                       COALESCE(p.confirmacao_whatsapp_enviada,false) confirmacao_enviada,
                       p.dt_tentativa_whatsapp IS NOT NULL confirmacao_tentada
                FROM pix_cobrancas p
                JOIN emprestimo e ON e.id=p.emprestimo_id
                JOIN cliente c ON c.id=e.cliente_id
                WHERE p.id=:pixId FOR UPDATE OF p
                """, Map.of("pixId", pixId), (rs, row) -> new ChargeState(
                    charge(rs), clean(rs.getString("cliente_nome")), rs.getLong("regiao_id"),
                nullable(rs.getString("telefone")), rs.getBoolean("confirmacao_enviada"),
                rs.getBoolean("confirmacao_tentada")));
        if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "Cobrança PIX não encontrada.");
        return rows.get(0);
    }

    public BankConfig bank(long bankId) {
        List<BankConfig> rows = jdbc.query("""
                SELECT id,client_id,client_secret,chave_pix,token_url,api_base_url,
                       certificado_path,chave_privada_path,cadeia_certificados_path,dtalter
                FROM conta_bancaria_configuracao WHERE id=:id
                """, Map.of("id", bankId), (rs, row) -> new BankConfig(
                rs.getLong("id"), nullable(rs.getString("client_id")), nullable(rs.getString("client_secret")),
                nullable(rs.getString("chave_pix")), nullable(rs.getString("token_url")),
                nullable(rs.getString("api_base_url")), nullable(rs.getString("certificado_path")),
                nullable(rs.getString("chave_privada_path")), nullable(rs.getString("cadeia_certificados_path")),
                dateTime(rs.getTimestamp("dtalter"))));
        if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "Conta bancária do PIX não encontrada.");
        return rows.get(0);
    }

    public List<PixChargeResponse> waiting(long loanId, Long installmentId) {
        String installment = installmentId == null
                ? "p.parcela_id IS NULL"
                : "p.parcela_id=:installmentId";
        return jdbc.query("SELECT " + CHARGE_COLUMNS + """
                FROM pix_cobrancas p
                WHERE p.emprestimo_id=:loanId AND
                """ + installment + """
                  AND p.status='AGUARDANDO'
                ORDER BY p.dtcad,p.id
                """, new MapSqlParameterSource().addValue("loanId", loanId)
                .addValue("installmentId", installmentId), (rs, row) -> charge(rs));
    }

    public List<PixChargeResponse> waitingForLoan(long userId, long loanId) {
        return jdbc.query("SELECT " + CHARGE_COLUMNS + """
                FROM pix_cobrancas p
                JOIN emprestimo e ON e.id=p.emprestimo_id
                JOIN cliente c ON c.id=e.cliente_id
                WHERE p.emprestimo_id=:loanId AND p.status='AGUARDANDO'
                  AND EXISTS (SELECT 1 FROM regiao_usuario ru
                              WHERE ru.usuario_id=:userId AND ru.regiao_id=c.regiao_id)
                ORDER BY p.dtcad,p.id
                """, Map.of("loanId", loanId, "userId", userId), (rs, row) -> charge(rs));
    }

    public List<Long> pendingMoney2Ids() {
        return jdbc.queryForList("""
                SELECT id FROM pix_cobrancas
                WHERE txid LIKE 'M2%'
                  AND (status='AGUARDANDO'
                       OR (status='PAGO' AND COALESCE(pagamento_processado,false)=false)
                       OR (status='PAGO' AND COALESCE(pagamento_processado,false)=true
                           AND COALESCE(confirmacao_whatsapp_enviada,false)=false
                           AND dt_tentativa_whatsapp IS NULL))
                ORDER BY CASE status
                             WHEN 'PAGO' THEN 0
                             WHEN 'AGUARDANDO' THEN 1
                             ELSE 2
                         END,
                         dtalter NULLS FIRST,dtcad,id
                LIMIT 50
                """, Map.of(), Long.class);
    }

    public long insert(long loanId, Long installmentId, long bankId, String transactionId, BigDecimal amount) {
        KeyHolder key = new GeneratedKeyHolder();
        jdbc.update("""
                INSERT INTO pix_cobrancas
                    (emprestimo_id,parcela_id,conta_bancaria_configuracao_id,txid,valor,status,
                     pagamento_processado,confirmacao_whatsapp_enviada,dtcad,dtalter)
                VALUES (:loanId,:installmentId,:bankId,:txid,:amount,'AGUARDANDO',false,false,NOW(),NOW())
                """, new MapSqlParameterSource().addValue("loanId", loanId)
                .addValue("installmentId", installmentId).addValue("bankId", bankId)
                .addValue("txid", transactionId).addValue("amount", amount), key, new String[]{"id"});
        Number value = key.getKey();
        if (value == null) throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Não foi possível registrar o PIX.");
        return value.longValue();
    }

    public PixChargeResponse charge(long pixId) {
        List<PixChargeResponse> rows = jdbc.query("SELECT " + CHARGE_COLUMNS +
                " FROM pix_cobrancas p WHERE p.id=:id", Map.of("id", pixId), (rs, row) -> charge(rs));
        if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "Cobrança PIX não encontrada.");
        return rows.get(0);
    }

    public void generated(long pixId, String copy, String qrCode, String location, String raw, String status,
                          LocalDateTime paidAt) {
        jdbc.update("""
                UPDATE pix_cobrancas SET pix_copia_cola=:copy,qr_code=:qrCode,location=:location,
                    raw_response=:raw,status=:status,erro=NULL,dt_pagamento=:paidAt,dtalter=NOW()
                WHERE id=:id
                """, new MapSqlParameterSource().addValue("id", pixId).addValue("copy", copy)
                .addValue("qrCode", qrCode).addValue("location", location).addValue("raw", raw)
                .addValue("status", status).addValue("paidAt", timestamp(paidAt)));
    }

    public void failed(long pixId, String status, String error) {
        jdbc.update("UPDATE pix_cobrancas SET status=:status,erro=:error,dtalter=NOW() WHERE id=:id",
                Map.of("id", pixId, "status", status, "error", truncate(error, 4000)));
    }

    public void rawStatus(long pixId, String status, String raw, String error, LocalDateTime paidAt) {
        jdbc.update("""
                UPDATE pix_cobrancas SET status=:status,raw_response=COALESCE(:raw,raw_response),erro=:error,
                    dt_pagamento=COALESCE(:paidAt,dt_pagamento),dtalter=NOW() WHERE id=:id
                """, new MapSqlParameterSource().addValue("id", pixId).addValue("status", status)
                .addValue("raw", raw).addValue("error", error).addValue("paidAt", timestamp(paidAt)));
    }

    public PaymentProcessingResult processPayment(long pixId, String transactionId, LocalDateTime paidAt) {
        ChargeState state = requireChargeForUpdate(pixId);
        PixChargeResponse pix = state.charge();
        if (pix.paymentProcessed()) {
            return new PaymentProcessingResult(pix.paymentId() == null ? 0 : pix.paymentId(), false, pix.loanId());
        }
        BigDecimal remaining = pix.amount();
        List<InstallmentBalance> installments = installmentBalancesForUpdate(pix.loanId(), pix.installmentId());
        BigDecimal available = installments.stream().map(InstallmentBalance::balance)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        if (remaining.compareTo(available) > 0) {
            throw new ApiException(HttpStatus.CONFLICT,
                    "O valor recebido pelo PIX ultrapassa o saldo atual do contrato.");
        }
        Long firstPayment = null;
        List<Long> changed = new ArrayList<>();
        for (InstallmentBalance installment : installments) {
            if (remaining.signum() <= 0) break;
            BigDecimal amount = remaining.min(installment.balance()).setScale(2, RoundingMode.HALF_UP);
            KeyHolder key = new GeneratedKeyHolder();
            jdbc.update("""
                    INSERT INTO pagamentos
                        (parcela_id,emprestimo_id,data,valor,observacao,automatico,
                         aprovacao_status,tipo,dtcad,dtalter)
                    VALUES (:installmentId,:loanId,:date,:amount,:note,true,'APROVADO','NORMAL',NOW(),NOW())
                    """, new MapSqlParameterSource().addValue("installmentId", installment.id())
                    .addValue("loanId", pix.loanId()).addValue("date", Timestamp.valueOf(paidAt))
                    .addValue("amount", amount).addValue("note", "PIX TXID " + transactionId),
                    key, new String[]{"id_pagamento"});
            Number payment = key.getKey();
            if (payment == null) throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Pagamento PIX não foi criado.");
            if (firstPayment == null) firstPayment = payment.longValue();
            changed.add(installment.id());
            remaining = remaining.subtract(amount);
        }
        synchronizeInstallments(changed);
        jdbc.update("""
                UPDATE pix_cobrancas SET pagamento_id=:paymentId,pagamento_processado=true,
                    status='PAGO',dt_pagamento=:paidAt,erro=NULL,dtalter=NOW() WHERE id=:id
                """, new MapSqlParameterSource().addValue("id", pixId).addValue("paymentId", firstPayment)
                .addValue("paidAt", Timestamp.valueOf(paidAt)));
        jdbc.update("""
                INSERT INTO entity_log_detalhado(entity_name,entity_id,operation,description,username,timestamp)
                VALUES ('PAGAMENTO',:loanId,'pagamentoRecebidoPix',:description,'SISTEMA',NOW())
                """, Map.of("loanId", pix.loanId(), "description",
                "Pagamento recebido via PIX no contrato " + pix.loanId() + ". TXID " + transactionId + "."));
        return new PaymentProcessingResult(firstPayment == null ? 0 : firstPayment, true, pix.loanId());
    }

    void synchronizeInstallments(List<Long> installmentIds) {
        if (installmentIds.isEmpty()) return;
        jdbc.update("""
                UPDATE parcelas p SET pendente=ROUND(COALESCE((SELECT SUM(pg.valor)
                    FROM pagamentos pg
                    WHERE pg.parcela_id=p.id AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                      AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0)::numeric,2)
                    < ROUND((COALESCE(p.valor,0)+COALESCE(p.valor_juros,0))::numeric,2),
                    status=NULL,dtalter=NOW()
                WHERE p.id IN (:ids)
                """, Map.of("ids", installmentIds));
    }

    private List<InstallmentBalance> installmentBalancesForUpdate(long loanId, Long installmentId) {
        String target = installmentId == null ? "" : " AND p.id=:installmentId";
        return jdbc.query("""
                SELECT p.id,GREATEST(COALESCE(p.valor,0)+COALESCE(p.valor_juros,0)
                    -COALESCE((SELECT SUM(pg.valor) FROM pagamentos pg WHERE pg.parcela_id=p.id
                      AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                      AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0),0) saldo
                FROM parcelas p WHERE p.emprestimo_id=:loanId AND p.pendente=true
                """ + target + " ORDER BY p.vencimento,p.id FOR UPDATE OF p",
                new MapSqlParameterSource().addValue("loanId", loanId).addValue("installmentId", installmentId),
                (rs, row) -> new InstallmentBalance(rs.getLong("id"), money(rs.getBigDecimal("saldo"))));
    }

    public BigDecimal available(long loanId, Long installmentId) {
        String target = installmentId == null ? "" : " AND p.id=:installmentId";
        BigDecimal value = jdbc.queryForObject("""
                SELECT COALESCE(SUM(GREATEST(COALESCE(p.valor,0)+COALESCE(p.valor_juros,0)
                    -COALESCE((SELECT SUM(pg.valor) FROM pagamentos pg WHERE pg.parcela_id=p.id
                      AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                      AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0),0)),0)
                FROM parcelas p WHERE p.emprestimo_id=:loanId AND p.pendente=true
                """ + target,
                new MapSqlParameterSource().addValue("loanId", loanId).addValue("installmentId", installmentId),
                BigDecimal.class);
        return money(value);
    }

    public IntegrationModels.WhatsappSecret whatsappSecret() {
        List<IntegrationModels.WhatsappSecret> rows = jdbc.query("""
                SELECT COALESCE(ativo,false),webdigital_api_token,
                       COALESCE(NULLIF(trim(base_url),''),'https://webdigital.dev/api/v1'),
                       mensagem_atrasadas,mensagem_vence_hoje,mensagem_desaparecidas,
                       mensagem_aquisicao,mensagem_pix,mensagem_pix_recebido
                FROM whatsapp_configuracao WHERE id=1
                """, Map.of(), (rs, row) -> new IntegrationModels.WhatsappSecret(
                rs.getBoolean(1), nullable(rs.getString(2)), rs.getString(3), nullable(rs.getString(4)),
                nullable(rs.getString(5)), nullable(rs.getString(6)), nullable(rs.getString(7)),
                nullable(rs.getString(8)), nullable(rs.getString(9))));
        return rows.isEmpty() ? new IntegrationModels.WhatsappSecret(false, null,
                "https://webdigital.dev/api/v1", null, null, null, null, null, null) : rows.get(0);
    }

    public WhatsappTarget whatsappTarget(long regionId) {
        List<WhatsappTarget> rows = jdbc.query("""
                SELECT d.id,d.webdigital_device_id,d.nome,COALESCE(d.pix_copy_supported,false)
                FROM whatsapp_dispositivos d
                JOIN whatsapp_dispositivo_regioes dr ON dr.dispositivo_id=d.id
                WHERE dr.regiao_id=:regionId AND COALESCE(d.connected,false)=true
                  AND NULLIF(trim(d.webdigital_device_id),'') IS NOT NULL
                ORDER BY COALESCE(d.disparando,false),d.id LIMIT 1
                """, Map.of("regionId", regionId), (rs, row) -> new WhatsappTarget(
                rs.getLong(1), rs.getString(2), clean(rs.getString(3)), rs.getBoolean(4)));
        if (rows.isEmpty()) throw new ApiException(HttpStatus.BAD_REQUEST,
                "Nenhum dispositivo WhatsApp conectado está vinculado à região do cliente.");
        return rows.get(0);
    }

    public void whatsappLog(ChargeState state, WhatsappTarget device, String type,
                            String status, String message, String error) {
        jdbc.update("""
                INSERT INTO whatsapp_disparo_logs(dispositivo_id,cliente_id,emprestimo_id,parcela_id,
                    tipo,telefone,cliente_nome,status,mensagem,erro,dtcad)
                SELECT :deviceId,e.cliente_id,p.emprestimo_id,p.parcela_id,:type,:phone,:clientName,
                       :status,:message,:error,NOW()
                FROM pix_cobrancas p JOIN emprestimo e ON e.id=p.emprestimo_id WHERE p.id=:pixId
                """, new MapSqlParameterSource().addValue("deviceId", device.id())
                .addValue("type", type)
                .addValue("phone", state.phone()).addValue("clientName", state.clientName())
                .addValue("status", status).addValue("message", message).addValue("error", error)
                .addValue("pixId", state.charge().id()));
    }

    public void markWhatsappConfirmation(long pixId, boolean sent, String error) {
        jdbc.update("""
                UPDATE pix_cobrancas SET confirmacao_whatsapp_enviada=:sent,
                    dt_tentativa_whatsapp=NOW(),erro_whatsapp=:error,dtalter=NOW() WHERE id=:id
                """, new MapSqlParameterSource().addValue("id", pixId).addValue("sent", sent)
                .addValue("error", error));
    }

    public boolean claimWhatsappConfirmation(long pixId) {
        return jdbc.update("""
                UPDATE pix_cobrancas SET dt_tentativa_whatsapp=NOW(),dtalter=NOW()
                WHERE id=:id AND COALESCE(confirmacao_whatsapp_enviada,false)=false
                  AND dt_tentativa_whatsapp IS NULL
                """, Map.of("id", pixId)) == 1;
    }

    public void paymentProcessingFailed(long pixId, String error) {
        jdbc.update("""
                UPDATE pix_cobrancas SET status='PAGO',erro=:error,dtalter=NOW() WHERE id=:id
                """, Map.of("id", pixId, "error", truncate(error, 4000)));
    }

    private PixChargeResponse charge(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new PixChargeResponse(rs.getLong("id"), rs.getLong("emprestimo_id"),
                rs.getObject("parcela_id", Long.class), rs.getObject("pagamento_id", Long.class),
                rs.getLong("conta_bancaria_configuracao_id"), clean(rs.getString("txid")),
                money(rs.getBigDecimal("valor")), clean(rs.getString("status")),
                nullable(rs.getString("pix_copia_cola")), nullable(rs.getString("qr_code")),
                nullable(rs.getString("location")), nullable(rs.getString("erro")),
                rs.getBoolean("pagamento_processado"), dateTime(rs.getTimestamp("dt_pagamento")),
                dateTime(rs.getTimestamp("dtcad")), dateTime(rs.getTimestamp("dtalter")));
    }

    private static BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value).setScale(2, RoundingMode.HALF_UP);
    }

    private static Timestamp timestamp(LocalDateTime value) {
        return value == null ? null : Timestamp.valueOf(value);
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

    private static String truncate(String value, int length) {
        String result = clean(value);
        return result.length() <= length ? result : result.substring(0, length);
    }

    record BankConfig(long id, String clientId, String clientSecret, String pixKey,
                      String tokenUrl, String apiBaseUrl, String certificatePath,
                      String privateKeyPath, String chainPath, LocalDateTime updatedAt) { }
    record ChargeState(PixChargeResponse charge, String clientName, long regionId, String phone,
                       boolean whatsappConfirmationSent, boolean whatsappConfirmationAttempted) { }
    record WhatsappTarget(long id, String remoteId, String name, boolean pixCopySupported) { }
    record PaymentProcessingResult(long paymentId, boolean processedNow, long loanId) { }
    private record InstallmentBalance(long id, BigDecimal balance) { }
}
