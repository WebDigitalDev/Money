package com.webdigital.money2.integrations;

import com.webdigital.money2.integrations.IntegrationModels.BankAccount;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappConfig;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappDevice;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappLog;
import com.webdigital.money2.integrations.IntegrationModels.WhatsappSecret;
import com.webdigital.money2.shared.ApiException;
import java.math.BigDecimal;
import java.sql.Array;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class IntegrationRepository {

    private static final String SICREDI = "SICREDI";
    private static final String COLLECTION_PAYMENT_GUARD = """
            NOT EXISTS (SELECT 1 FROM pix_cobrancas px
                        WHERE px.emprestimo_id=e.id AND px.status='PAGO'
                          AND COALESCE(px.pagamento_processado,false)=false)
            AND NOT EXISTS (SELECT 1 FROM pagamentos payment
                            WHERE payment.emprestimo_id=e.id AND payment.aprovacao_status='PENDENTE'
                              AND COALESCE(payment.tipo,'NORMAL')<>'JUROS_ROLAGEM')
            """;
    private final NamedParameterJdbcTemplate jdbc;

    public IntegrationRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<BankAccount> bankAccounts() {
        return jdbc.query("""
                SELECT id, COALESCE(NULLIF(trim(nome), ''), 'Conta ' || id) AS nome,
                       COALESCE(banco, 'SICREDI') AS banco, COALESCE(ativo, false) AS ativo,
                       NULLIF(trim(client_id), '') IS NOT NULL AS client_id_configurado,
                       NULLIF(trim(client_secret), '') IS NOT NULL AS client_secret_configurado,
                       chave_pix, certificado_nome, chave_privada_nome,
                       cadeia_certificados_nome, dtalter
                FROM conta_bancaria_configuracao
                WHERE COALESCE(banco, 'SICREDI') = 'SICREDI'
                ORDER BY id
                """, Map.of(), (rs, row) -> bankAccount(rs.getLong("id"),
                rs.getString("nome"), rs.getString("banco"), rs.getBoolean("ativo"),
                rs.getBoolean("client_id_configurado"), rs.getBoolean("client_secret_configurado"),
                nullable(rs.getString("chave_pix")), nullable(rs.getString("certificado_nome")),
                nullable(rs.getString("chave_privada_nome")),
                nullable(rs.getString("cadeia_certificados_nome")),
                dateTime(rs.getTimestamp("dtalter"))));
    }

    public BankAccount requireBank(long id) {
        return bankAccounts().stream().filter(account -> account.id() == id).findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Conta bancária não encontrada."));
    }

    public long createBank(String name) {
        Long id = jdbc.queryForObject("""
                INSERT INTO conta_bancaria_configuracao
                    (banco, nome, ativo, token_url, api_base_url, dtcad, dtalter)
                VALUES ('SICREDI', :name, false,
                        'https://api-pix.sicredi.com.br/oauth/token',
                        'https://api-pix.sicredi.com.br/api', NOW(), NOW())
                RETURNING id
                """, Map.of("name", name), Long.class);
        if (id == null) throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Não foi possível criar a conta.");
        return id;
    }

    public void updateBankName(long id, String name) {
        requireUpdated(jdbc.update("""
                UPDATE conta_bancaria_configuracao SET nome=:name, dtalter=NOW()
                WHERE id=:id AND COALESCE(banco,'SICREDI')='SICREDI'
                """, Map.of("id", id, "name", name)), "Conta bancária não encontrada.");
    }

    public void replaceBankRegions(long accountId, List<Long> regionIds) {
        if (!regionIds.isEmpty()) {
            Integer regions = jdbc.queryForObject(
                    "SELECT COUNT(*) FROM regioes WHERE id IN (:ids)", Map.of("ids", regionIds), Integer.class);
            if (regions == null || regions != regionIds.size()) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "Uma ou mais regiões não foram encontradas.");
            }
            Integer occupied = jdbc.queryForObject("""
                    SELECT COUNT(*) FROM conta_bancaria_regiao
                    WHERE regiao_id IN (:ids) AND conta_bancaria_configuracao_id <> :accountId
                    """, Map.of("ids", regionIds, "accountId", accountId), Integer.class);
            if (occupied != null && occupied > 0) {
                throw new ApiException(HttpStatus.CONFLICT,
                        "Uma das regiões selecionadas já está vinculada a outra conta bancária.");
            }
        }
        jdbc.update("DELETE FROM conta_bancaria_regiao WHERE conta_bancaria_configuracao_id=:id",
                Map.of("id", accountId));
        for (Long regionId : regionIds) {
            jdbc.update("""
                    INSERT INTO conta_bancaria_regiao (conta_bancaria_configuracao_id, regiao_id)
                    VALUES (:accountId, :regionId)
                    """, Map.of("accountId", accountId, "regionId", regionId));
        }
        jdbc.update("UPDATE conta_bancaria_configuracao SET regiao_id=NULL, dtalter=NOW() WHERE id=:id",
                Map.of("id", accountId));
    }

    public BankCredentials bankCredentials(long id) {
        List<BankCredentials> rows = jdbc.query("""
                SELECT client_id, client_secret, chave_pix, certificado_path,
                       chave_privada_path, cadeia_certificados_path
                FROM conta_bancaria_configuracao WHERE id=:id
                """, Map.of("id", id), (rs, row) -> new BankCredentials(
                nullable(rs.getString("client_id")), nullable(rs.getString("client_secret")),
                nullable(rs.getString("chave_pix")), nullable(rs.getString("certificado_path")),
                nullable(rs.getString("chave_privada_path")),
                nullable(rs.getString("cadeia_certificados_path"))));
        if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "Conta bancária não encontrada.");
        return rows.get(0);
    }

    public void updateSicredi(long id, boolean active, String clientId, String clientSecret, String pixKey) {
        requireUpdated(jdbc.update("""
                UPDATE conta_bancaria_configuracao
                   SET ativo=:active, client_id=:clientId, client_secret=:clientSecret,
                       chave_pix=:pixKey,
                       token_url='https://api-pix.sicredi.com.br/oauth/token',
                       api_base_url='https://api-pix.sicredi.com.br/api', dtalter=NOW()
                 WHERE id=:id AND COALESCE(banco,'SICREDI')='SICREDI'
                """, new MapSqlParameterSource()
                .addValue("id", id).addValue("active", active)
                .addValue("clientId", clientId).addValue("clientSecret", clientSecret)
                .addValue("pixKey", pixKey)), "Conta bancária não encontrada.");
    }

    public void updateBankFiles(long id, StoredFiles files) {
        MapSqlParameterSource values = new MapSqlParameterSource()
                .addValue("id", id)
                .addValue("certificatePath", files.certificatePath())
                .addValue("certificateName", files.certificateName())
                .addValue("privateKeyPath", files.privateKeyPath())
                .addValue("privateKeyName", files.privateKeyName())
                .addValue("chainPath", files.chainPath())
                .addValue("chainName", files.chainName());
        requireUpdated(jdbc.update("""
                UPDATE conta_bancaria_configuracao SET
                    certificado_path=COALESCE(:certificatePath, certificado_path),
                    certificado_nome=COALESCE(:certificateName, certificado_nome),
                    chave_privada_path=COALESCE(:privateKeyPath, chave_privada_path),
                    chave_privada_nome=COALESCE(:privateKeyName, chave_privada_nome),
                    cadeia_certificados_path=COALESCE(:chainPath, cadeia_certificados_path),
                    cadeia_certificados_nome=COALESCE(:chainName, cadeia_certificados_nome),
                    dtalter=NOW()
                WHERE id=:id
                """, values), "Conta bancária não encontrada.");
    }

    public WhatsappSecret whatsappSecret() {
        List<WhatsappSecret> rows = jdbc.query("""
                SELECT COALESCE(ativo,false) ativo, webdigital_api_token,
                       COALESCE(NULLIF(trim(base_url),''),'https://webdigital.dev/api/v1') base_url,
                       mensagem_atrasadas, mensagem_vence_hoje, mensagem_desaparecidas,
                       mensagem_aquisicao, mensagem_pix, mensagem_pix_recebido
                FROM whatsapp_configuracao WHERE id=1
                """, Map.of(), (rs, row) -> new WhatsappSecret(
                rs.getBoolean("ativo"), nullable(rs.getString("webdigital_api_token")),
                rs.getString("base_url"), nullable(rs.getString("mensagem_atrasadas")),
                nullable(rs.getString("mensagem_vence_hoje")),
                nullable(rs.getString("mensagem_desaparecidas")),
                nullable(rs.getString("mensagem_aquisicao")), nullable(rs.getString("mensagem_pix")),
                nullable(rs.getString("mensagem_pix_recebido"))));
        return rows.isEmpty() ? new WhatsappSecret(false, null,
                "https://webdigital.dev/api/v1", null, null, null, null, null, null) : rows.get(0);
    }

    public WhatsappConfig whatsappConfig() {
        WhatsappSecret value = whatsappSecret();
        return new WhatsappConfig(value.active(), value.token() != null, value.baseUrl(),
                value.overdueMessage(), value.dueTodayMessage(), value.missingMessage(),
                value.acquisitionMessage(), value.pixMessage(), value.pixReceivedMessage());
    }

    public void saveWhatsappConfig(WhatsappSecret value) {
        jdbc.update("""
                INSERT INTO whatsapp_configuracao
                    (id, ativo, webdigital_api_token, base_url, mensagem_atrasadas,
                     mensagem_vence_hoje, mensagem_desaparecidas, mensagem_aquisicao,
                     mensagem_pix, mensagem_pix_recebido, dtcad, dtalter)
                VALUES (1, :active, :token, :baseUrl, :overdue, :dueToday, :missing,
                        :acquisition, :pix, :pixReceived, NOW(), NOW())
                ON CONFLICT (id) DO UPDATE SET
                    ativo=EXCLUDED.ativo,
                    webdigital_api_token=EXCLUDED.webdigital_api_token,
                    base_url=EXCLUDED.base_url,
                    mensagem_atrasadas=EXCLUDED.mensagem_atrasadas,
                    mensagem_vence_hoje=EXCLUDED.mensagem_vence_hoje,
                    mensagem_desaparecidas=EXCLUDED.mensagem_desaparecidas,
                    mensagem_aquisicao=EXCLUDED.mensagem_aquisicao,
                    mensagem_pix=EXCLUDED.mensagem_pix,
                    mensagem_pix_recebido=EXCLUDED.mensagem_pix_recebido,
                    dtalter=NOW()
                """, new MapSqlParameterSource()
                .addValue("active", value.active()).addValue("token", value.token())
                .addValue("baseUrl", value.baseUrl()).addValue("overdue", value.overdueMessage())
                .addValue("dueToday", value.dueTodayMessage()).addValue("missing", value.missingMessage())
                .addValue("acquisition", value.acquisitionMessage()).addValue("pix", value.pixMessage())
                .addValue("pixReceived", value.pixReceivedMessage()));
    }

    public List<WhatsappDevice> whatsappDevices() {
        return jdbc.query("""
                SELECT id, webdigital_device_id, nome, telefone, status, provider,
                       COALESCE(connected,false) connected,
                       COALESCE(pix_copy_supported,false) pix_copy_supported,
                       COALESCE(disparando,false) disparando, tipo_disparo,
                       COALESCE(disparo_total,0) disparo_total,
                       COALESCE(disparo_processados,0) disparo_processados,
                       COALESCE(disparo_sucessos,0) disparo_sucessos,
                       COALESCE(disparo_erros,0) disparo_erros,
                       COALESCE(disparo_ignorados,0) disparo_ignorados,
                       dt_inicio_disparo, dtalter
                FROM whatsapp_dispositivos ORDER BY COALESCE(nome,''), id
                """, Map.of(), (rs, row) -> whatsappDevice(
                rs.getLong("id"), nullable(rs.getString("webdigital_device_id")),
                nullable(rs.getString("nome")), nullable(rs.getString("telefone")),
                nullable(rs.getString("status")), nullable(rs.getString("provider")),
                rs.getBoolean("connected"), rs.getBoolean("pix_copy_supported"),
                rs.getBoolean("disparando"), nullable(rs.getString("tipo_disparo")),
                rs.getInt("disparo_total"), rs.getInt("disparo_processados"),
                rs.getInt("disparo_sucessos"), rs.getInt("disparo_erros"),
                rs.getInt("disparo_ignorados"), dateTime(rs.getTimestamp("dt_inicio_disparo")),
                dateTime(rs.getTimestamp("dtalter"))));
    }

    public List<WhatsappDevice> whatsappDevices(Set<String> remoteIds) {
        if (remoteIds == null || remoteIds.isEmpty()) return List.of();
        return jdbc.query("""
                SELECT id, webdigital_device_id, nome, telefone, status, provider,
                       COALESCE(connected,false) connected,
                       COALESCE(pix_copy_supported,false) pix_copy_supported,
                       COALESCE(disparando,false) disparando, tipo_disparo,
                       COALESCE(disparo_total,0) disparo_total,
                       COALESCE(disparo_processados,0) disparo_processados,
                       COALESCE(disparo_sucessos,0) disparo_sucessos,
                       COALESCE(disparo_erros,0) disparo_erros,
                       COALESCE(disparo_ignorados,0) disparo_ignorados,
                       dt_inicio_disparo, dtalter
                FROM whatsapp_dispositivos
                WHERE webdigital_device_id IN (:remoteIds)
                ORDER BY COALESCE(nome,''), id
                """, Map.of("remoteIds", remoteIds), (rs, row) -> whatsappDevice(
                rs.getLong("id"), nullable(rs.getString("webdigital_device_id")),
                nullable(rs.getString("nome")), nullable(rs.getString("telefone")),
                nullable(rs.getString("status")), nullable(rs.getString("provider")),
                rs.getBoolean("connected"), rs.getBoolean("pix_copy_supported"),
                rs.getBoolean("disparando"), nullable(rs.getString("tipo_disparo")),
                rs.getInt("disparo_total"), rs.getInt("disparo_processados"),
                rs.getInt("disparo_sucessos"), rs.getInt("disparo_erros"),
                rs.getInt("disparo_ignorados"), dateTime(rs.getTimestamp("dt_inicio_disparo")),
                dateTime(rs.getTimestamp("dtalter"))));
    }

    public WhatsappDevice requireDevice(long id) {
        return whatsappDevices().stream().filter(device -> device.id() == id).findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Dispositivo WhatsApp não encontrado."));
    }

    public long upsertRemoteDevice(
            String remoteId, String name, String phone, String status, String provider,
            boolean connected, boolean pixCopySupported) {
        Long id = jdbc.queryForObject("""
                INSERT INTO whatsapp_dispositivos
                    (webdigital_device_id, device, nome, telefone, status, provider,
                     connected, pix_copy_supported, disparando, dtcad, dtalter)
                VALUES (:remoteId,:remoteId,:name,:phone,:status,:provider,
                        :connected,:pix,false,NOW(),NOW())
                ON CONFLICT (webdigital_device_id) DO UPDATE SET
                    nome=EXCLUDED.nome, telefone=EXCLUDED.telefone,
                    status=EXCLUDED.status, provider=EXCLUDED.provider,
                    connected=EXCLUDED.connected,
                    pix_copy_supported=EXCLUDED.pix_copy_supported,
                    disparando=CASE WHEN EXCLUDED.connected THEN whatsapp_dispositivos.disparando ELSE false END,
                    dtalter=NOW()
                RETURNING id
                """, new MapSqlParameterSource().addValue("remoteId", remoteId)
                .addValue("name", name).addValue("phone", phone).addValue("status", status)
                .addValue("provider", provider).addValue("connected", connected)
                .addValue("pix", pixCopySupported), Long.class);
        return id == null ? 0 : id;
    }

    public void markMissingRemoteDevicesDisconnected(Set<String> remoteIds) {
        if (remoteIds.isEmpty()) {
            jdbc.update("DELETE FROM whatsapp_dispositivo_regioes", Map.of());
            jdbc.update("UPDATE whatsapp_dispositivos SET connected=false, status='DESCONECTADO', disparando=false",
                    Map.of());
            return;
        }
        // Registros criados pelo backend antigo podem não ter webdigital_device_id. Antes de
        // liberar suas regiões, preserva o vínculo quando o mesmo número ainda existe na API.
        jdbc.update("""
                WITH matches AS (
                    SELECT old.id old_id,
                           (SELECT current.id
                            FROM whatsapp_dispositivos current
                            WHERE current.webdigital_device_id IN (:ids)
                              AND (NULLIF(BTRIM(old.device),'')=current.webdigital_device_id
                                   OR (LENGTH(regexp_replace(COALESCE(old.telefone,''),'[^0-9]','','g'))>=10
                                       AND regexp_replace(COALESCE(old.telefone,''),'[^0-9]','','g')=
                                           regexp_replace(COALESCE(current.telefone,''),'[^0-9]','','g')))
                            ORDER BY COALESCE(current.connected,false) DESC,current.id
                            LIMIT 1) current_id
                    FROM whatsapp_dispositivos old
                    WHERE old.webdigital_device_id IS NULL
                )
                DELETE FROM whatsapp_dispositivo_regioes legacy_link
                USING matches match
                WHERE legacy_link.dispositivo_id=match.old_id
                  AND match.current_id IS NOT NULL
                  AND EXISTS (
                      SELECT 1
                      FROM whatsapp_dispositivo_regioes current_link
                      JOIN whatsapp_dispositivos current_device
                        ON current_device.id=current_link.dispositivo_id
                      WHERE current_link.regiao_id=legacy_link.regiao_id
                        AND current_link.dispositivo_id<>legacy_link.dispositivo_id
                        AND current_device.webdigital_device_id IN (:ids)
                  )
                """, Map.of("ids", remoteIds));
        jdbc.update("""
                WITH matches AS (
                    SELECT old.id old_id,
                           (SELECT current.id
                            FROM whatsapp_dispositivos current
                            WHERE current.webdigital_device_id IN (:ids)
                              AND (NULLIF(BTRIM(old.device),'')=current.webdigital_device_id
                                   OR (LENGTH(regexp_replace(COALESCE(old.telefone,''),'[^0-9]','','g'))>=10
                                       AND regexp_replace(COALESCE(old.telefone,''),'[^0-9]','','g')=
                                           regexp_replace(COALESCE(current.telefone,''),'[^0-9]','','g')))
                            ORDER BY COALESCE(current.connected,false) DESC,current.id
                            LIMIT 1) current_id
                    FROM whatsapp_dispositivos old
                    WHERE old.webdigital_device_id IS NULL
                )
                UPDATE whatsapp_dispositivo_regioes legacy_link
                SET dispositivo_id=match.current_id
                FROM matches match
                WHERE legacy_link.dispositivo_id=match.old_id
                  AND match.current_id IS NOT NULL
                """, Map.of("ids", remoteIds));
        jdbc.update("""
                DELETE FROM whatsapp_dispositivo_regioes wr
                USING whatsapp_dispositivos d
                WHERE d.id=wr.dispositivo_id
                  AND (d.webdigital_device_id IS NULL OR d.webdigital_device_id NOT IN (:ids))
                """, Map.of("ids", remoteIds));
        jdbc.update("""
                UPDATE whatsapp_dispositivos SET connected=false, status='DESCONECTADO', disparando=false
                WHERE webdigital_device_id IS NULL OR webdigital_device_id NOT IN (:ids)
                """, Map.of("ids", remoteIds));
    }

    public void replaceDeviceRegions(long deviceId, List<Long> regionIds) {
        requireDevice(deviceId);
        if (!regionIds.isEmpty()) {
            Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM regioes WHERE id IN (:ids)",
                    Map.of("ids", regionIds), Integer.class);
            if (count == null || count != regionIds.size()) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "Uma ou mais regiões não foram encontradas.");
            }
            Integer occupied = jdbc.queryForObject("""
                    SELECT COUNT(*) FROM whatsapp_dispositivo_regioes
                    WHERE regiao_id IN (:ids) AND dispositivo_id <> :deviceId
                    """, Map.of("ids", regionIds, "deviceId", deviceId), Integer.class);
            if (occupied != null && occupied > 0) {
                throw new ApiException(HttpStatus.CONFLICT,
                        "Uma das regiões selecionadas já está vinculada a outro número do WhatsApp.");
            }
        }
        jdbc.update("DELETE FROM whatsapp_dispositivo_regioes WHERE dispositivo_id=:id", Map.of("id", deviceId));
        for (Long regionId : regionIds) {
            jdbc.update("""
                    INSERT INTO whatsapp_dispositivo_regioes (dispositivo_id, regiao_id)
                    VALUES (:deviceId,:regionId)
                    """, Map.of("deviceId", deviceId, "regionId", regionId));
        }
    }

    public void setDispatching(long deviceId, boolean dispatching) {
        jdbc.update("""
                UPDATE whatsapp_dispositivos SET disparando=:value,
                    dt_inicio_disparo=CASE WHEN :value THEN NOW() ELSE dt_inicio_disparo END,
                    dt_fim_disparo=CASE WHEN :value THEN NULL ELSE NOW() END,
                    dtalter=NOW() WHERE id=:id
                """, Map.of("id", deviceId, "value", dispatching));
    }

    public boolean tryStartDispatch(long deviceId, String type, int total) {
        return jdbc.update("""
                UPDATE whatsapp_dispositivos SET disparando=true,dt_inicio_disparo=NOW(),
                    dt_fim_disparo=NULL,tipo_disparo=:type,disparo_total=:total,
                    disparo_processados=0,disparo_sucessos=0,disparo_erros=0,
                    disparo_ignorados=0,dtalter=NOW()
                WHERE id=:id AND COALESCE(disparando,false)=false
                """, Map.of("id", deviceId, "type", type, "total", Math.max(0, total))) == 1;
    }

    public void recordDispatchProgress(long deviceId, String status) {
        String normalized = status == null ? "ERRO" : status.trim().toUpperCase();
        jdbc.update("""
                UPDATE whatsapp_dispositivos SET
                    disparo_processados=LEAST(COALESCE(disparo_total,0),
                        COALESCE(disparo_processados,0)+1),
                    disparo_sucessos=COALESCE(disparo_sucessos,0)
                        + CASE WHEN :status='SUCESSO' THEN 1 ELSE 0 END,
                    disparo_erros=COALESCE(disparo_erros,0)
                        + CASE WHEN :status='ERRO' THEN 1 ELSE 0 END,
                    disparo_ignorados=COALESCE(disparo_ignorados,0)
                        + CASE WHEN :status='AVISO' THEN 1 ELSE 0 END,
                    dtalter=NOW()
                WHERE id=:id
                """, Map.of("id", deviceId, "status", normalized));
    }

    public void clearInterruptedDispatches() {
        jdbc.update("""
                UPDATE whatsapp_dispositivos SET disparando=false,dt_fim_disparo=NOW(),dtalter=NOW()
                WHERE COALESCE(disparando,false)=true
                """, Map.of());
    }

    public boolean isDispatching(long deviceId) {
        Boolean value = jdbc.queryForObject("SELECT COALESCE(disparando,false) FROM whatsapp_dispositivos WHERE id=:id",
                Map.of("id", deviceId), Boolean.class);
        return Boolean.TRUE.equals(value);
    }

    public List<WhatsappLog> whatsappLogs() {
        return jdbc.query("""
                SELECT l.*, d.nome AS dispositivo_nome, r.descricao AS regiao_nome
                FROM whatsapp_disparo_logs l
                LEFT JOIN whatsapp_dispositivos d ON d.id=l.dispositivo_id
                LEFT JOIN emprestimo e ON e.id=l.emprestimo_id
                LEFT JOIN cliente c ON c.id=COALESCE(l.cliente_id,e.cliente_id)
                LEFT JOIN regioes r ON r.id=c.regiao_id
                ORDER BY l.dtcad DESC NULLS LAST, l.id DESC LIMIT 200
                """, Map.of(), (rs, row) -> new WhatsappLog(
                rs.getLong("id"), rs.getObject("dispositivo_id", Long.class),
                nullable(rs.getString("dispositivo_nome")), rs.getObject("cliente_id", Long.class),
                rs.getObject("emprestimo_id", Long.class), rs.getObject("parcela_id", Long.class),
                nullable(rs.getString("tipo")), nullable(rs.getString("telefone")),
                nullable(rs.getString("cliente_nome")), nullable(rs.getString("regiao_nome")),
                nullable(rs.getString("status")),
                nullable(rs.getString("mensagem")), nullable(rs.getString("erro")),
                dateTime(rs.getTimestamp("dtcad"))));
    }

    public void clearWhatsappLogs() {
        jdbc.update("DELETE FROM whatsapp_disparo_logs", Map.of());
    }

    public void insertWhatsappLog(
            Long deviceId, Long clientId, Long loanId, Long installmentId,
            String type, String phone, String clientName, String status,
            String message, String error) {
        jdbc.update("""
                INSERT INTO whatsapp_disparo_logs
                    (dispositivo_id, cliente_id, emprestimo_id, parcela_id, tipo,
                     telefone, cliente_nome, status, mensagem, erro, dtcad)
                VALUES (:deviceId,:clientId,:loanId,:installmentId,:type,
                        :phone,:clientName,:status,:message,:error,NOW())
                """, new MapSqlParameterSource().addValue("deviceId", deviceId)
                .addValue("clientId", clientId).addValue("loanId", loanId)
                .addValue("installmentId", installmentId).addValue("type", type)
                .addValue("phone", phone).addValue("clientName", clientName)
                .addValue("status", status).addValue("message", message).addValue("error", error));
    }

    public List<DispatchTarget> dispatchTargets(long deviceId, String type) {
        if ("AQUISICAO".equals(type)) {
            return acquisitionTargets(deviceId);
        }
        String typeCondition = switch (type) {
            case "VENCE_HOJE" -> "p.vencimento::date = CURRENT_DATE AND COALESCE(e.desaparecido,false)=false";
            case "DESAPARECIDAS" -> "COALESCE(e.desaparecido,false)=true";
            default -> "p.vencimento::date < CURRENT_DATE AND COALESCE(e.desaparecido,false)=false";
        };
        String sql = """
                SELECT DISTINCT ON (e.id) c.id cliente_id, c.nome cliente_nome,
                       COALESCE(
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.celular,''),'[^0-9]','','g'))>=10 THEN c.celular END,
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.telefone,''),'[^0-9]','','g'))>=10 THEN c.telefone END,
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.telefone2,''),'[^0-9]','','g'))>=10 THEN c.telefone2 END
                       ) telefone,
                       e.id emprestimo_id, p.id parcela_id, COALESCE(p.parcela,'') parcela,
                       p.vencimento, GREATEST(ROUND((COALESCE(p.valor,0) + COALESCE(p.valor_juros,0))::numeric,2)
                           - ROUND(COALESCE((SELECT SUM(pg.valor) FROM pagamentos pg
                                      WHERE pg.parcela_id=p.id
                                        AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                                        AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0)::numeric,2),0) pendente
                FROM whatsapp_dispositivo_regioes wr
                JOIN cliente c ON c.regiao_id=wr.regiao_id AND c.ativo=true
                JOIN emprestimo e ON e.cliente_id=c.id AND e.status=2
                    AND COALESCE(e.aprovacao_status,'APROVADO')='APROVADO'
                    AND COALESCE(e.refinanciado,false)=false AND COALESCE(e.renovacao,false)=false
                JOIN parcelas p ON p.emprestimo_id=e.id AND p.pendente=true
                WHERE wr.dispositivo_id=:deviceId AND
                """ + typeCondition + """
                  AND COALESCE(p.status,'')<>'Cancelado'
                  AND GREATEST(ROUND((COALESCE(p.valor,0)+COALESCE(p.valor_juros,0))::numeric,2)
                      -ROUND(COALESCE((SELECT SUM(pg.valor) FROM pagamentos pg
                                WHERE pg.parcela_id=p.id
                                  AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                                  AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0)::numeric,2),0)>0
                  AND %s
                ORDER BY e.id, p.vencimento, p.id
                """.formatted(COLLECTION_PAYMENT_GUARD);
        return jdbc.query(sql, Map.of("deviceId", deviceId), (rs, row) -> new DispatchTarget(
                rs.getLong("cliente_id"), clean(rs.getString("cliente_nome")),
                nullable(rs.getString("telefone")), rs.getLong("emprestimo_id"),
                rs.getLong("parcela_id"), clean(rs.getString("parcela")),
                rs.getTimestamp("vencimento").toLocalDateTime(), rs.getBigDecimal("pendente")));
    }

    private List<DispatchTarget> acquisitionTargets(long deviceId) {
        return jdbc.query("""
                SELECT DISTINCT ON (c.id) c.id cliente_id, c.nome cliente_nome,
                       COALESCE(
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.celular,''),'[^0-9]','','g'))>=10 THEN c.celular END,
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.telefone,''),'[^0-9]','','g'))>=10 THEN c.telefone END,
                           CASE WHEN LENGTH(regexp_replace(COALESCE(c.telefone2,''),'[^0-9]','','g'))>=10 THEN c.telefone2 END
                       ) telefone,
                       e.id emprestimo_id, NULL::bigint parcela_id, ''::text parcela,
                       COALESCE(pa.max_pagamento,pa.max_vencimento,NOW()) vencimento,
                       0::numeric pendente
                FROM whatsapp_dispositivo_regioes wr
                JOIN cliente c ON c.regiao_id=wr.regiao_id AND COALESCE(c.ativo,true)=true
                JOIN emprestimo e ON e.cliente_id=c.id
                LEFT JOIN LATERAL (
                    SELECT MAX(p.vencimento) max_vencimento,
                           MAX((SELECT MAX(pg.data) FROM pagamentos pg WHERE pg.parcela_id=p.id)) max_pagamento,
                           SUM(CASE WHEN p.pendente=true THEN 1 ELSE 0 END) qtd_pendentes
                    FROM parcelas p WHERE p.emprestimo_id=e.id
                ) pa ON true
                WHERE wr.dispositivo_id=:deviceId
                  AND COALESCE(e.aprovacao_status,'APROVADO')='APROVADO'
                  AND e.status=2
                  AND COALESCE(e.refinanciado,false)=false
                  AND COALESCE(e.renovacao,false)=false
                  AND COALESCE(pa.qtd_pendentes,0)=0
                  AND NOT EXISTS (
                      SELECT 1 FROM emprestimo aberto
                      WHERE aberto.cliente_id=c.id
                        AND COALESCE(aberto.aprovacao_status,'APROVADO')='APROVADO'
                        AND aberto.status<>3
                        AND COALESCE(aberto.refinanciado,false)=false
                        AND COALESCE(aberto.renovacao,false)=false
                        AND EXISTS (SELECT 1 FROM parcelas p2
                                    WHERE p2.emprestimo_id=aberto.id AND p2.pendente=true)
                  )
                ORDER BY c.id,COALESCE(pa.max_pagamento,pa.max_vencimento) DESC NULLS LAST,e.id DESC
                """, Map.of("deviceId", deviceId), (rs, row) -> new DispatchTarget(
                rs.getLong("cliente_id"), clean(rs.getString("cliente_nome")),
                nullable(rs.getString("telefone")), rs.getLong("emprestimo_id"),
                null, "", rs.getTimestamp("vencimento").toLocalDateTime(),
                rs.getBigDecimal("pendente")));
    }

    public boolean isDispatchTargetEligible(String type, DispatchTarget target) {
        if ("AQUISICAO".equals(type)) {
            Integer count = jdbc.queryForObject("""
                    SELECT COUNT(*) FROM emprestimo e
                    JOIN cliente c ON c.id=e.cliente_id
                    WHERE c.id=:clientId AND e.id=:loanId AND COALESCE(c.ativo,true)=true
                      AND COALESCE(e.aprovacao_status,'APROVADO')='APROVADO'
                      AND e.status=2 AND COALESCE(e.refinanciado,false)=false
                      AND COALESCE(e.renovacao,false)=false
                      AND NOT EXISTS (SELECT 1 FROM parcelas p
                                      WHERE p.emprestimo_id=e.id AND p.pendente=true)
                      AND NOT EXISTS (
                          SELECT 1 FROM emprestimo aberto
                          WHERE aberto.cliente_id=c.id
                            AND COALESCE(aberto.aprovacao_status,'APROVADO')='APROVADO'
                            AND aberto.status<>3
                            AND COALESCE(aberto.refinanciado,false)=false
                            AND COALESCE(aberto.renovacao,false)=false
                            AND EXISTS (SELECT 1 FROM parcelas p2
                                        WHERE p2.emprestimo_id=aberto.id AND p2.pendente=true)
                      )
                    """, Map.of("clientId", target.clientId(), "loanId", target.loanId()), Integer.class);
            return count != null && count > 0;
        }
        if (target.installmentId() == null) return false;
        String condition = switch (type) {
            case "VENCE_HOJE" -> "p.vencimento::date=CURRENT_DATE AND COALESCE(e.desaparecido,false)=false";
            case "DESAPARECIDAS" -> "COALESCE(e.desaparecido,false)=true";
            default -> "p.vencimento::date<CURRENT_DATE AND COALESCE(e.desaparecido,false)=false";
        };
        String eligibilitySql = """
                SELECT COUNT(*) FROM parcelas p
                JOIN emprestimo e ON e.id=p.emprestimo_id
                JOIN cliente c ON c.id=e.cliente_id
                WHERE p.id=:installmentId AND e.id=:loanId AND c.id=:clientId
                  AND c.ativo=true AND p.pendente=true AND COALESCE(p.status,'')<>'Cancelado'
                  AND e.status=2 AND COALESCE(e.aprovacao_status,'APROVADO')='APROVADO'
                  AND COALESCE(e.refinanciado,false)=false AND COALESCE(e.renovacao,false)=false
                  AND %s
                  AND GREATEST(ROUND((COALESCE(p.valor,0)+COALESCE(p.valor_juros,0))::numeric,2)
                      -ROUND(COALESCE((SELECT SUM(pg.valor) FROM pagamentos pg
                                WHERE pg.parcela_id=p.id
                                  AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                                  AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0)::numeric,2),0)>0
                  AND %s
                """.formatted(condition, COLLECTION_PAYMENT_GUARD);
        Integer count = jdbc.queryForObject(eligibilitySql,
                Map.of("installmentId", target.installmentId(), "loanId", target.loanId(),
                "clientId", target.clientId()), Integer.class);
        return count != null && count > 0;
    }

    public BigDecimal pendingAmount(long installmentId) {
        BigDecimal value = jdbc.queryForObject("""
                SELECT GREATEST(ROUND((COALESCE(p.valor,0)+COALESCE(p.valor_juros,0))::numeric,2)
                    -ROUND(COALESCE((SELECT SUM(pg.valor) FROM pagamentos pg
                              WHERE pg.parcela_id=p.id
                                AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                                AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0)::numeric,2),0)
                FROM parcelas p WHERE p.id=:id
                """, Map.of("id", installmentId), BigDecimal.class);
        return value == null ? BigDecimal.ZERO : value;
    }

    public OverdueSummary overdueSummary(long loanId) {
        List<OverdueSummary> rows = jdbc.query("""
                WITH open_installments AS (
                    SELECT p.parcela,p.vencimento,COALESCE(e.vlrmulta,0) late_fee,
                           ROUND((COALESCE(p.valor,0)+COALESCE(p.valor_juros,0))::numeric,2) total,
                           COALESCE(p.valor_juros,0) contract_interest,
                           ROUND(COALESCE((SELECT SUM(pg.valor) FROM pagamentos pg
                                    WHERE pg.parcela_id=p.id
                                      AND COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                                      AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0)::numeric,2) paid,
                           GREATEST(CURRENT_DATE-p.vencimento::date,0) overdue_days
                    FROM parcelas p JOIN emprestimo e ON e.id=p.emprestimo_id
                    WHERE p.emprestimo_id=:loanId AND p.pendente=true
                      AND p.vencimento::date<CURRENT_DATE AND COALESCE(p.status,'')<>'Cancelado'
                      AND e.status=2 AND COALESCE(e.aprovacao_status,'APROVADO')='APROVADO'
                      AND COALESCE(e.refinanciado,false)=false AND COALESCE(e.renovacao,false)=false
                      AND %s
                ), overdue AS (
                    SELECT *,GREATEST(total-paid,0) pending,overdue_days*late_fee overdue_fee
                    FROM open_installments
                )
                SELECT COUNT(*) installment_count,MIN(vencimento) first_due,
                       COALESCE(SUM(total),0) original_total,
                       COALESCE(SUM(contract_interest),0) contract_interest,
                       COALESCE(SUM(overdue_fee),0) overdue_fee,
                       COALESCE(SUM(pending),0) debt,
                       COALESCE(SUM(pending+overdue_fee),0) updated_total,
                       COALESCE(MAX(late_fee),0) daily_fee,
                       STRING_AGG(parcela || ' (' || TO_CHAR(vencimento,'DD/MM/YYYY') || ')',
                                  ', ' ORDER BY vencimento) installments
                FROM overdue WHERE pending>0
                """.formatted(COLLECTION_PAYMENT_GUARD), Map.of("loanId", loanId), (rs, row) -> new OverdueSummary(
                rs.getInt("installment_count"), dateTime(rs.getTimestamp("first_due")),
                rs.getBigDecimal("original_total"), rs.getBigDecimal("contract_interest"),
                rs.getBigDecimal("overdue_fee"), rs.getBigDecimal("debt"),
                rs.getBigDecimal("updated_total"), rs.getBigDecimal("daily_fee"),
                nullable(rs.getString("installments"))));
        return rows.isEmpty() || rows.get(0).installmentCount() == 0 ? null : rows.get(0);
    }

    private BankAccount bankAccount(
            long id, String name, String bank, boolean active, boolean clientIdConfigured,
            boolean clientSecretConfigured, String pixKey, String certificateName,
            String privateKeyName, String chainName, LocalDateTime updatedAt) {
        List<RegionLink> links = regionLinks("conta_bancaria_regiao", "conta_bancaria_configuracao_id", id);
        return new BankAccount(id, clean(name), clean(bank), active, clientIdConfigured,
                clientSecretConfigured, pixKey, links.stream().map(RegionLink::id).toList(),
                links.stream().map(RegionLink::name).toList(), certificateName,
                privateKeyName, chainName, updatedAt);
    }

    private WhatsappDevice whatsappDevice(
            long id, String remoteId, String name, String phone, String status, String provider,
            boolean connected, boolean pixCopySupported, boolean dispatching,
            String dispatchType, int dispatchTotal, int dispatchProcessed,
            int dispatchSucceeded, int dispatchErrors, int dispatchIgnored,
            LocalDateTime dispatchStartedAt, LocalDateTime updatedAt) {
        List<RegionLink> links = regionLinks("whatsapp_dispositivo_regioes", "dispositivo_id", id);
        return new WhatsappDevice(id, remoteId, name, phone, status, provider, connected,
                pixCopySupported, dispatching, dispatchType, dispatchTotal, dispatchProcessed,
                dispatchSucceeded, dispatchErrors, dispatchIgnored,
                links.stream().map(RegionLink::id).toList(),
                links.stream().map(RegionLink::name).toList(), dispatchStartedAt, updatedAt);
    }

    private List<RegionLink> regionLinks(String table, String idColumn, long id) {
        if (!("conta_bancaria_regiao".equals(table) || "whatsapp_dispositivo_regioes".equals(table))) {
            throw new IllegalArgumentException("Tabela de vínculo inválida.");
        }
        return jdbc.query("SELECT r.id, COALESCE(NULLIF(trim(r.descricao),''),'Região #' || r.id) nome " +
                        "FROM " + table + " x JOIN regioes r ON r.id=x.regiao_id " +
                        "WHERE x." + idColumn + "=:id ORDER BY lower(COALESCE(r.descricao,'')),r.id",
                Map.of("id", id), (rs, row) -> new RegionLink(rs.getLong("id"), rs.getString("nome")));
    }

    private static void requireUpdated(int updated, String message) {
        if (updated == 0) throw new ApiException(HttpStatus.NOT_FOUND, message);
    }

    private static LocalDateTime dateTime(Timestamp value) {
        return value == null ? null : value.toLocalDateTime();
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static String nullable(String value) {
        String result = clean(value);
        return result.isEmpty() ? null : result;
    }

    record RegionLink(long id, String name) {
    }

    record BankCredentials(
            String clientId, String clientSecret, String pixKey,
            String certificatePath, String privateKeyPath, String chainPath) {
    }

    record StoredFiles(
            String certificatePath, String certificateName,
            String privateKeyPath, String privateKeyName,
            String chainPath, String chainName) {
    }

    record DispatchTarget(
            long clientId, String clientName, String phone, long loanId,
            Long installmentId, String installment, LocalDateTime dueDate,
            java.math.BigDecimal pendingAmount) {
    }

    record OverdueSummary(
            int installmentCount, LocalDateTime firstDue, BigDecimal originalTotal,
            BigDecimal contractInterest, BigDecimal overdueFee, BigDecimal debt,
            BigDecimal updatedTotal, BigDecimal dailyFee, String installments) {
    }
}
