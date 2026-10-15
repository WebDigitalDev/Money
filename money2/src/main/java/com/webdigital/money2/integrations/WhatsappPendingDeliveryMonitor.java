package com.webdigital.money2.integrations;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Reconciles accepted sends using GET only; it never sends a message again. */
@Component
public class WhatsappPendingDeliveryMonitor {
    private static final Logger log = LoggerFactory.getLogger(WhatsappPendingDeliveryMonitor.class);
    private static final String PREFIX = "Envio aceito pela API; aguardando confirmação de entrega. Protocolo: ";
    private final NamedParameterJdbcTemplate jdbc;
    private final IntegrationRepository repository;
    private final WebDigitalWhatsappClient client;
    private long cursor;

    public WhatsappPendingDeliveryMonitor(NamedParameterJdbcTemplate jdbc,
            IntegrationRepository repository, WebDigitalWhatsappClient client) {
        this.jdbc = jdbc;
        this.repository = repository;
        this.client = client;
    }

    @Scheduled(initialDelay = 60000, fixedDelay = 60000)
    public void reconcile() {
        var config = repository.whatsappSecret();
        if (!config.active() || config.token() == null || config.token().isBlank()) return;
        List<Pending> pending = jdbc.query("""
                SELECT l.id, l.erro, d.webdigital_device_id
                FROM whatsapp_disparo_logs l
                JOIN whatsapp_dispositivos d ON d.id=l.dispositivo_id
                WHERE l.status='AVISO' AND l.erro LIKE :prefix AND l.id>:cursor
                  AND l.dtcad > NOW()-INTERVAL '14 days'
                  AND d.webdigital_device_id IS NOT NULL
                ORDER BY l.id LIMIT 10
                """, Map.of("prefix", PREFIX + "%", "cursor", cursor), (rs, row) ->
                new Pending(rs.getLong(1), rs.getString(2), rs.getString(3)));
        if (pending.isEmpty()) { cursor = 0; return; }
        for (Pending item : pending) {
            cursor = item.id();
            String dispatchId = item.notice().substring(PREFIX.length()).trim();
            if (!dispatchId.matches("[A-Za-z0-9._-]+")) continue;
            try {
                JsonNode response = client.dispatchStatus(config, item.device(), dispatchId);
                String status = response.path("status").asText();
                if (!"sent".equals(status) && !"failed".equals(status)) continue;
                String detail = "sent".equals(status)
                        ? "Entrega confirmada pelo WhatsApp."
                        : response.path("error").asText("O WhatsApp informou falha na entrega.");
                jdbc.update("""
                        UPDATE whatsapp_disparo_logs SET status=:status,erro=:detail
                        WHERE id=:id AND status='AVISO' AND erro=:notice
                        """, Map.of("id", item.id(), "status", "sent".equals(status) ? "SUCESSO" : "ERRO",
                        "detail", detail, "notice", item.notice()));
            } catch (RuntimeException ex) {
                // A failed status lookup is not a failed send; retry next cycle.
                log.debug("WhatsApp confirmation lookup deferred for log {}", item.id());
            }
        }
    }

    private record Pending(long id, String notice, String device) {}
}
