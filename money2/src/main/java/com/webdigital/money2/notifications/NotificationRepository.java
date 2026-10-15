package com.webdigital.money2.notifications;

import java.util.*;
import java.time.Instant;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class NotificationRepository {
    private final NamedParameterJdbcTemplate jdbc;
    public NotificationRepository(NamedParameterJdbcTemplate jdbc) { this.jdbc = jdbc; }
    public record Preferences(boolean payments, boolean goals, Instant paymentsSince, Instant goalsSince) {
        public Preferences(boolean payments, boolean goals) { this(payments,goals,null,null); }
    }
    public record Item(long id, String kind, String title, String body, Instant createdAt, Instant expiresAt) {}

    // Require every region for aggregated goal events, never expose another region's totals.
    static final String ACCESS = """
        NOT EXISTS (SELECT 1 FROM unnest(e.region_ids) r(id)
            WHERE NOT EXISTS (SELECT 1 FROM regiao_usuario ur WHERE ur.usuario_id=:userId AND ur.regiao_id=r.id))
        """;
    public Preferences preferences(long userId) {
        return jdbc.query("SELECT payments,goals,payments_since,goals_since FROM money2_notification_preferences WHERE user_id=:id",
                Map.of("id",userId),(rs,n)->new Preferences(rs.getBoolean(1),rs.getBoolean(2),
                    rs.getTimestamp(3).toInstant(),rs.getTimestamp(4).toInstant()))
                .stream().findFirst().orElse(new Preferences(false,false));
    }
    public void preferences(long userId, Preferences p) {
        jdbc.update("""
            INSERT INTO money2_notification_preferences(user_id,payments,goals) VALUES(:id,:payments,:goals)
            ON CONFLICT(user_id) DO UPDATE SET payments=excluded.payments,goals=excluded.goals,
            payments_since=CASE WHEN NOT money2_notification_preferences.payments AND excluded.payments
                THEN now() ELSE money2_notification_preferences.payments_since END,
            goals_since=CASE WHEN NOT money2_notification_preferences.goals AND excluded.goals
                THEN now() ELSE money2_notification_preferences.goals_since END
            """,Map.of("id",userId,"payments",p.payments(),"goals",p.goals()));
    }
    public List<Item> list(long userId) {
        return jdbc.query("""
            SELECT e.* FROM money2_notification_events e
            WHERE e.created_at>now()-INTERVAL '24 hours' AND
            """+ACCESS+" ORDER BY e.created_at DESC,e.id DESC",
            Map.of("userId",userId),(rs,n)->new Item(rs.getLong("id"),rs.getString("kind"),
                rs.getString("title"),rs.getString("body"),rs.getTimestamp("created_at").toInstant(),
                rs.getTimestamp("created_at").toInstant().plusSeconds(86400)));
    }
    public void collectPayments() {
        jdbc.update("""
            INSERT INTO money2_notification_events(event_key,kind,title,body,region_ids,created_at)
            SELECT 'PIX:'||p.id,'PAYMENT','Pagamento PIX recebido',
                COALESCE(c.nome,'Cliente')||' • Contrato #'||e.id||' • R$ '||REPLACE(p.valor::text,'.',',')||
                    ' • '||COALESCE((SELECT r.descricao FROM regioes r WHERE r.id=c.regiao_id),'Região'),
                ARRAY[c.regiao_id], COALESCE(p.dt_pagamento,p.dtalter) AT TIME ZONE 'America/Cuiaba'
            FROM pix_cobrancas p JOIN emprestimo e ON e.id=p.emprestimo_id
            JOIN cliente c ON c.id=e.cliente_id
            WHERE p.pagamento_processado=true AND p.status='PAGO' AND c.regiao_id IS NOT NULL
              AND COALESCE(p.dt_pagamento,p.dtalter) >
                  (SELECT started_at AT TIME ZONE 'America/Cuiaba' FROM money2_notification_state WHERE id=1)
              AND COALESCE(p.dt_pagamento,p.dtalter) > (now() AT TIME ZONE 'America/Cuiaba')-INTERVAL '24 hours'
            ON CONFLICT(event_key) DO NOTHING
            """,Map.of());
    }
    public void goal(long id, String title, String body, Set<Long> regionIds) {
        String regions = regionIds.stream().sorted().map(String::valueOf).collect(java.util.stream.Collectors.joining(","));
        jdbc.update("""
            INSERT INTO money2_notification_events(event_key,kind,title,body,region_ids)
            VALUES(:key,'GOAL',:title,:body||' • '||COALESCE((
                SELECT string_agg(r.descricao,', ' ORDER BY r.id) FROM regioes r
                WHERE r.id=ANY(CAST(:regions AS bigint[]))), 'Região'),CAST(:regions AS bigint[]))
            ON CONFLICT(event_key) DO NOTHING
            """,Map.of("key","GOAL:"+id,"title",title,"body",body,"regions","{"+regions+"}"));
    }
}
