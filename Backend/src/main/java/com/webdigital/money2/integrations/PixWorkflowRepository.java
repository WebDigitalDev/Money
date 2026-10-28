package com.webdigital.money2.integrations;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
public class PixWorkflowRepository {
    private final NamedParameterJdbcTemplate jdbc;

    public PixWorkflowRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Long> reconciliationIds() {
        return jdbc.queryForList("""
                SELECT p.id FROM pix_cobrancas p
                JOIN emprestimo e ON e.id=p.emprestimo_id
                JOIN cliente c ON c.id=e.cliente_id
                WHERE p.txid LIKE 'M2%'
                  AND (p.status='AGUARDANDO'
                       OR (p.status='PAGO' AND COALESCE(p.pagamento_processado,false)=false
                           AND (p.erro IS NULL OR p.dtalter<LOCALTIMESTAMP-INTERVAL '15 minutes')))
                ORDER BY CASE p.status WHEN 'PAGO' THEN 0 ELSE 1 END,
                         p.dtalter NULLS FIRST,p.dtcad,p.id
                LIMIT 200
                """, Map.of(), Long.class);
    }

    public List<Long> collectionChargeIds(long loanId) {
        return jdbc.queryForList("""
                SELECT id FROM pix_cobrancas WHERE emprestimo_id=:loanId
                  AND (status='AGUARDANDO'
                    OR (status='PAGO' AND COALESCE(pagamento_processado,false)=false))
                ORDER BY id
                """, Map.of("loanId", loanId), Long.class);
    }

    public void enqueue(long pixId) {
        jdbc.update("""
                INSERT INTO money2_pix_whatsapp_outbox(pix_id,tipo)
                VALUES (:id,'PIX_RECEBIDO'),(:id,'EMPRESTIMO_ATUALIZADO')
                ON CONFLICT (pix_id,tipo) DO NOTHING
                """, Map.of("id", pixId));
    }

    public Delivery claim() {
        List<Delivery> rows = jdbc.query("""
                WITH candidate AS (
                    SELECT o.pix_id,o.tipo FROM money2_pix_whatsapp_outbox o
                    WHERE (o.status='PENDENTE' AND o.proxima_tentativa<=LOCALTIMESTAMP
                           OR o.status='PROCESSANDO' AND o.bloqueado_em<LOCALTIMESTAMP-INTERVAL '3 minutes')
                      AND (o.tipo='PIX_RECEBIDO' OR NOT EXISTS (
                          SELECT 1 FROM money2_pix_whatsapp_outbox receipt
                          WHERE receipt.pix_id=o.pix_id AND receipt.tipo='PIX_RECEBIDO'
                            AND (receipt.tentativas=0 OR receipt.status='PROCESSANDO')
                      ))
                    ORDER BY o.proxima_tentativa,o.pix_id,
                             CASE o.tipo WHEN 'PIX_RECEBIDO' THEN 0 ELSE 1 END
                    LIMIT 1 FOR UPDATE OF o SKIP LOCKED
                )
                UPDATE money2_pix_whatsapp_outbox o
                SET status='PROCESSANDO',tentativas=o.tentativas+1,bloqueado_em=LOCALTIMESTAMP,
                    lease_token=:token,dtalter=LOCALTIMESTAMP
                FROM candidate c WHERE o.pix_id=c.pix_id AND o.tipo=c.tipo
                RETURNING o.*
                """, Map.of("token", UUID.randomUUID().toString()), (rs, row) -> new Delivery(
                rs.getLong("pix_id"), rs.getString("tipo"), rs.getInt("tentativas"),
                rs.getString("lease_token"), rs.getObject("dispositivo_id", Long.class),
                rs.getString("remote_device_id"), rs.getString("telefone"),
                rs.getString("cliente_nome"), rs.getString("mensagem")));
        return rows.isEmpty() ? null : rows.get(0);
    }

    public void savePayload(Delivery delivery) {
        jdbc.update("""
                UPDATE money2_pix_whatsapp_outbox
                SET dispositivo_id=:deviceId,remote_device_id=:remoteId,telefone=:phone,
                    cliente_nome=:clientName,mensagem=:message,dtalter=LOCALTIMESTAMP
                WHERE pix_id=:id AND tipo=:type AND lease_token=:token AND status='PROCESSANDO'
                """, parameters(delivery).addValue("deviceId", delivery.deviceId())
                .addValue("remoteId", delivery.remoteId()).addValue("phone", delivery.phone())
                .addValue("clientName", delivery.clientName()).addValue("message", delivery.message()));
    }

    @Transactional
    public void accepted(Delivery delivery, String dispatchId, String notice) {
        int updated = jdbc.update("""
                UPDATE money2_pix_whatsapp_outbox
                SET status='ACEITO',dispatch_id=:dispatchId,erro=:notice,
                    bloqueado_em=NULL,dtalter=LOCALTIMESTAMP
                WHERE pix_id=:id AND tipo=:type AND lease_token=:token AND status='PROCESSANDO'
                """, parameters(delivery).addValue("dispatchId", dispatchId).addValue("notice", notice));
        if (updated == 1 && delivery.receipt()) {
            jdbc.update("""
                    UPDATE pix_cobrancas SET confirmacao_whatsapp_enviada=true,
                        dt_tentativa_whatsapp=LOCALTIMESTAMP,erro_whatsapp=:notice
                    WHERE id=:id
                    """, new MapSqlParameterSource("id", delivery.pixId()).addValue("notice", notice));
        }
    }

    @Transactional
    public void failed(Delivery delivery, String error) {
        int updated = jdbc.update("""
                UPDATE money2_pix_whatsapp_outbox
                SET status=CASE WHEN tentativas>=12 THEN 'FALHOU' ELSE 'PENDENTE' END,
                    proxima_tentativa=LOCALTIMESTAMP+make_interval(secs=>:delay),
                    bloqueado_em=NULL,erro=:error,dtalter=LOCALTIMESTAMP
                WHERE pix_id=:id AND tipo=:type AND lease_token=:token AND status='PROCESSANDO'
                """, parameters(delivery).addValue("error", error)
                .addValue("delay", Math.min(1800, 30 * (1 << Math.min(delivery.attempts() - 1, 6)))));
        if (updated == 1 && delivery.receipt()) {
            jdbc.update("""
                    UPDATE pix_cobrancas SET dt_tentativa_whatsapp=LOCALTIMESTAMP,erro_whatsapp=:error
                    WHERE id=:id
                    """, Map.of("id", delivery.pixId(), "error", error));
        }
    }

    private MapSqlParameterSource parameters(Delivery delivery) {
        return new MapSqlParameterSource("id", delivery.pixId()).addValue("type", delivery.type())
                .addValue("token", delivery.token());
    }

    record Delivery(long pixId, String type, int attempts, String token, Long deviceId,
                    String remoteId, String phone, String clientName, String message) {
        boolean receipt() { return "PIX_RECEBIDO".equals(type); }
        String reference() { return (receipt() ? "pix-received:" : "loan-updated-after-pix:") + pixId; }
        String event() { return receipt() ? "money.pix.received" : "money.loan.updated"; }
        Delivery withPayload(PixRepository.ChargeState state, PixRepository.WhatsappTarget device, String text) {
            return new Delivery(pixId, type, attempts, token, device.id(), device.remoteId(),
                    state.phone(), state.clientName(), text);
        }
    }
}
