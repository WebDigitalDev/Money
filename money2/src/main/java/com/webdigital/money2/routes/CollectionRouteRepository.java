package com.webdigital.money2.routes;

import com.webdigital.money2.clients.CityOptionResponse;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class CollectionRouteRepository {

    private static final String DEBT_CTES = """
            WITH candidate_loans AS MATERIALIZED (
                SELECT e.id,e.cliente_id,e.tipo,c.regiao_id
                FROM emprestimo e
                JOIN cliente c ON c.id=e.cliente_id
                WHERE e.status=2
                  AND COALESCE(e.aprovacao_status,'APROVADO')='APROVADO'
                  AND COALESCE(e.refinanciado,false)=false
                  AND COALESCE(e.renovacao,false)=false
                  AND EXISTS (
                      SELECT 1 FROM regiao_usuario ru
                      WHERE ru.usuario_id=:userId AND ru.regiao_id=c.regiao_id
                  )
                  AND (:filterRegions=false OR c.regiao_id IN (:regionIds))
                  AND (:filterCity=false OR c.cidade_id=:cityId)
                  AND (:filterClient=false OR c.id=:clientId)
            ), installment_balances AS MATERIALIZED (
                SELECT p.id,p.emprestimo_id,p.vencimento::date due_date,
                       GREATEST(
                           ROUND((COALESCE(p.valor,0)+COALESCE(p.valor_juros,0))::numeric,2)
                           - ROUND(COALESCE(SUM(pg.valor) FILTER (
                               WHERE COALESCE(pg.aprovacao_status,'APROVADO')='APROVADO'
                                 AND COALESCE(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'
                           ),0)::numeric,2),
                           0
                       ) balance
                FROM parcelas p
                JOIN candidate_loans loan ON loan.id=p.emprestimo_id
                LEFT JOIN pagamentos pg ON pg.parcela_id=p.id
                WHERE p.pendente IS DISTINCT FROM false
                GROUP BY p.id,p.emprestimo_id,p.vencimento,p.valor,p.valor_juros
            ), loan_debts AS MATERIALIZED (
                SELECT loan.id loan_id,loan.cliente_id,loan.tipo,loan.regiao_id,
                       COALESCE(SUM(balance.balance) FILTER (
                           WHERE balance.balance>0),0) total_debt,
                       COALESCE(SUM(balance.balance) FILTER (
                           WHERE balance.balance>0 AND balance.due_date<CURRENT_DATE),0) overdue_debt,
                       MIN(balance.due_date) FILTER (
                           WHERE balance.balance>0 AND balance.due_date<CURRENT_DATE) oldest_due_date
                FROM candidate_loans loan
                JOIN installment_balances balance ON balance.emprestimo_id=loan.id
                GROUP BY loan.id,loan.cliente_id,loan.tipo,loan.regiao_id
                HAVING COALESCE(SUM(balance.balance) FILTER (
                    WHERE balance.balance>0 AND balance.due_date<CURRENT_DATE),0)>0
            ), collection_summary AS MATERIALIZED (
                SELECT collection.cliente_id,COUNT(*) collection_count,
                       MAX(collection.dtcad) last_collection_at
                FROM money2_cobrancas collection
                JOIN (SELECT DISTINCT cliente_id FROM loan_debts) debt_client
                  ON debt_client.cliente_id=collection.cliente_id
                GROUP BY collection.cliente_id
            ), client_debts AS MATERIALIZED (
                SELECT c.id client_id,c.nome client_name,c.regiao_id,r.descricao region_name,
                       c.cidade_id city_id,city.codibge city_ibge,
                       city.descricao city_description,city.uf city_state,
                       COALESCE(SUM(debt.total_debt),0) total_debt,
                       COALESCE(SUM(debt.overdue_debt),0) overdue_debt,
                       GREATEST(CURRENT_DATE-MIN(debt.oldest_due_date),0) overdue_days,
                       COUNT(*) overdue_loans,
                       TRIM(CONCAT_WS(' - ',
                           NULLIF(TRIM(COALESCE(city.descricao,'')),''),
                           NULLIF(TRIM(COALESCE(city.uf,'')),''))) city_name,
                       CONCAT_WS(', ',
                           NULLIF(TRIM(COALESCE(c.endereco,'')),''),
                           NULLIF(TRIM(COALESCE(c.numero,'')),''),
                           NULLIF(TRIM(COALESCE(c.complemento,'')),''),
                           NULLIF(TRIM(COALESCE(c.bairro,'')),''),
                           NULLIF(TRIM(CONCAT_WS(' - ',
                               NULLIF(TRIM(COALESCE(city.descricao,'')),''),
                               NULLIF(TRIM(COALESCE(city.uf,'')),''))), '')
                           ,CASE WHEN COALESCE(c.cep,0)>0 THEN
                               CONCAT('CEP ',SUBSTRING(LPAD(c.cep::text,8,'0'),1,5),'-',
                                      SUBSTRING(LPAD(c.cep::text,8,'0'),6,3))
                             END
                       ) address,
                       COALESCE(summary.collection_count,0) collection_count,
                       summary.last_collection_at,
                       assignment.id route_id,assignment.cobrador_id collector_id,
                       TRIM(CONCAT_WS(' ',NULLIF(collector.first_name,''),
                           NULLIF(collector.last_name,''))) collector_full_name,
                       collector.username collector_username,
                       assignment.dtcad assigned_at,
                       COALESCE(summary.last_collection_at>=assignment.dtcad,false)
                           route_completed
                FROM loan_debts debt
                JOIN cliente c ON c.id=debt.cliente_id
                JOIN regioes r ON r.id=c.regiao_id
                LEFT JOIN cidade city ON city.codigo=c.cidade_id
                LEFT JOIN collection_summary summary ON summary.cliente_id=c.id
                LEFT JOIN money2_rotas_cobranca assignment ON assignment.cliente_id=c.id
                LEFT JOIN users collector ON collector.id=assignment.cobrador_id
                GROUP BY c.id,c.nome,c.regiao_id,r.descricao,c.endereco,c.numero,
                         c.complemento,c.bairro,c.cep,c.cidade_id,city.codibge,
                         city.descricao,city.uf,
                         summary.collection_count,summary.last_collection_at,
                         assignment.id,assignment.cobrador_id,assignment.dtcad,
                         collector.first_name,collector.last_name,collector.username
            )
            """;

    private final NamedParameterJdbcTemplate jdbc;

    public CollectionRouteRepository(NamedParameterJdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public CollectionRoutePageResponse search(
            long userId,
            Long collectorId,
            Set<Long> regionIds,
            Long cityId,
            String rawCity,
            CollectionRouteSort sort,
            String rawQuery,
            boolean assignedOnly,
            int page,
            int size) {
        Map<String, Object> parameters = parameters(userId, regionIds, null);
        parameters.put("filterCity", cityId != null && cityId > 0);
        parameters.put("cityId", cityId == null || cityId <= 0 ? -1L : cityId);
        String query = rawQuery == null ? "" : rawQuery.trim().toLowerCase();
        String city = rawCity == null ? "" : rawCity.trim().toLowerCase();
        parameters.put("query", query);
        parameters.put("search", "%" + query + "%");
        parameters.put("city", city);
        parameters.put("citySearch", "%" + city + "%");
        parameters.put("assignedOnly", assignedOnly);
        parameters.put("filterCollector", collectorId != null && collectorId > 0);
        parameters.put("collectorId", collectorId == null || collectorId <= 0 ? -1L : collectorId);
        parameters.put("limit", size);
        parameters.put("offset", page * size);

        String orderBy = sort == CollectionRouteSort.OVERDUE_AMOUNT
                ? "overdue_debt DESC,overdue_days DESC"
                : "overdue_days DESC,overdue_debt DESC";

        String sql = DEBT_CTES + """
                , filtered AS MATERIALIZED (
                    SELECT * FROM client_debts debt
                    WHERE ((:assignedOnly=true AND debt.route_id IS NOT NULL)
                           OR (:assignedOnly=false AND debt.route_id IS NULL))
                      AND (:filterCollector=false OR debt.collector_id=:collectorId)
                      AND (:city='' OR lower(COALESCE(debt.city_name,'')) LIKE :citySearch)
                      AND (:query=''
                        OR lower(COALESCE(debt.client_name,'')) LIKE :search
                        OR lower(COALESCE(debt.region_name,'')) LIKE :search
                        OR lower(COALESCE(debt.address,'')) LIKE :search
                        OR CAST(debt.client_id AS text) LIKE :search)
                )
                SELECT filtered.*,
                       COUNT(*) OVER() total_items,
                       COALESCE(SUM(total_debt) OVER(),0) filtered_total_debt,
                       COALESCE(SUM(overdue_debt) OVER(),0) filtered_total_overdue_debt
                FROM filtered
                ORDER BY %s,
                         lower(COALESCE(client_name,'')),client_id
                LIMIT :limit OFFSET :offset
                """.formatted(orderBy);

        return jdbc.query(sql, parameters, result -> {
            List<CollectionRouteItemResponse> items = new ArrayList<>();
            long totalItems = 0;
            BigDecimal totalDebt = money(null);
            BigDecimal totalOverdueDebt = money(null);
            while (result.next()) {
                totalItems = result.getLong("total_items");
                totalDebt = money(result.getBigDecimal("filtered_total_debt"));
                totalOverdueDebt = money(result.getBigDecimal("filtered_total_overdue_debt"));
                items.add(routeItem(result));
            }
            int totalPages = totalItems == 0
                    ? 0
                    : (int) Math.ceil((double) totalItems / size);
            return new CollectionRoutePageResponse(
                    List.copyOf(items), page, size, totalItems, totalPages,
                    page + 1 < totalPages, totalDebt, totalOverdueDebt);
        });
    }

    public CollectionRouteItemResponse requireDebt(long userId, long clientId) {
        return requireDebt(userId, clientId, false);
    }

    public CollectionRouteItemResponse requireAssignedDebt(long userId, long clientId) {
        return requireDebt(userId, clientId, true);
    }

    private CollectionRouteItemResponse requireDebt(
            long userId,
            long clientId,
            boolean assignedOnly) {
        Map<String, Object> parameters = parameters(userId, Set.of(), clientId);
        parameters.put("assignedOnly", assignedOnly);
        List<CollectionRouteItemResponse> rows = jdbc.query(
                DEBT_CTES + """
                        SELECT * FROM client_debts
                        WHERE (:assignedOnly=false OR route_id IS NOT NULL)
                        """,
                parameters,
                (result, row) -> routeItem(result));
        return rows.isEmpty() ? null : rows.get(0);
    }

    public List<CollectionRouteCollectorResponse> collectors() {
        return jdbc.query("""
                SELECT account.id,
                       TRIM(CONCAT_WS(' ',NULLIF(account.first_name,''),
                           NULLIF(account.last_name,''))) collector_name,
                       account.username
                FROM users account
                WHERE account.cobrador=true
                  AND account.enable=true
                  AND COALESCE(account.locked,false)=false
                  AND COALESCE(account.expired,false)=false
                  AND COALESCE(account.expired_credentials,false)=false
                ORDER BY lower(COALESCE(NULLIF(TRIM(CONCAT_WS(' ',
                             account.first_name,account.last_name)),''),account.username)),
                         account.id
                """, Map.of(), (result, row) -> {
            String name = clean(result.getString("collector_name"));
            String username = clean(result.getString("username"));
            return new CollectionRouteCollectorResponse(
                    result.getLong("id"), name.isBlank() ? username : name, username);
        });
    }

    public List<CollectionRouteCollectorResponse> assignedCollectors(
            long userId,
            Long visibleCollectorId,
            Set<Long> regionIds,
            Long cityId,
            String rawQuery) {
        Map<String, Object> parameters = parameters(userId, regionIds, null);
        parameters.put("filterCity", cityId != null && cityId > 0);
        parameters.put("cityId", cityId == null || cityId <= 0 ? -1L : cityId);
        parameters.put("filterCollector", visibleCollectorId != null && visibleCollectorId > 0);
        parameters.put("collectorId", visibleCollectorId == null || visibleCollectorId <= 0
                ? -1L : visibleCollectorId);
        String query = rawQuery == null ? "" : rawQuery.trim().toLowerCase();
        parameters.put("query", query);
        parameters.put("search", "%" + query + "%");
        return jdbc.query(DEBT_CTES + """
                SELECT DISTINCT debt.collector_id,
                       COALESCE(NULLIF(debt.collector_full_name,''),
                                debt.collector_username) collector_name,
                       debt.collector_username
                FROM client_debts debt
                WHERE debt.route_id IS NOT NULL
                  AND debt.collector_id IS NOT NULL
                  AND (:filterCollector=false OR debt.collector_id=:collectorId)
                  AND (:query=''
                    OR lower(COALESCE(debt.client_name,'')) LIKE :search
                    OR lower(COALESCE(debt.region_name,'')) LIKE :search
                    OR lower(COALESCE(debt.address,'')) LIKE :search
                    OR CAST(debt.client_id AS text) LIKE :search)
                ORDER BY collector_name,debt.collector_id
                """, parameters, (result, row) -> new CollectionRouteCollectorResponse(
                result.getLong("collector_id"),
                clean(result.getString("collector_name")),
                clean(result.getString("collector_username"))));
    }

    public List<CityOptionResponse> cities(
            long userId,
            Long collectorId,
            Set<Long> regionIds,
            String rawQuery,
            boolean assignedOnly) {
        Map<String, Object> parameters = parameters(userId, regionIds, null);
        String query = rawQuery == null ? "" : rawQuery.trim().toLowerCase();
        parameters.put("query", query);
        parameters.put("search", "%" + query + "%");
        parameters.put("assignedOnly", assignedOnly);
        parameters.put("filterCollector", collectorId != null && collectorId > 0);
        parameters.put("collectorId", collectorId == null || collectorId <= 0 ? -1L : collectorId);
        return jdbc.query(DEBT_CTES + """
                SELECT DISTINCT debt.city_id,debt.city_ibge,
                       debt.city_description,debt.city_state,debt.city_name
                FROM client_debts debt
                WHERE ((:assignedOnly=true AND debt.route_id IS NOT NULL)
                       OR (:assignedOnly=false AND debt.route_id IS NULL))
                  AND (:filterCollector=false OR debt.collector_id=:collectorId)
                  AND debt.city_id IS NOT NULL
                  AND COALESCE(debt.city_name,'')<>''
                  AND (:query=''
                    OR lower(COALESCE(debt.client_name,'')) LIKE :search
                    OR lower(COALESCE(debt.region_name,'')) LIKE :search
                    OR lower(COALESCE(debt.address,'')) LIKE :search
                    OR CAST(debt.client_id AS text) LIKE :search)
                ORDER BY debt.city_description,debt.city_state,debt.city_id
                """, parameters, (result, row) -> new CityOptionResponse(
                result.getLong("city_id"),
                result.getObject("city_ibge", Long.class),
                clean(result.getString("city_description")),
                clean(result.getString("city_state")),
                clean(result.getString("city_name"))));
    }

    public boolean collectorAvailable(long collectorId) {
        Boolean available = jdbc.queryForObject("""
                SELECT EXISTS (
                    SELECT 1 FROM users account
                    WHERE account.id=:collectorId
                      AND account.cobrador=true
                      AND account.enable=true
                      AND COALESCE(account.locked,false)=false
                      AND COALESCE(account.expired,false)=false
                      AND COALESCE(account.expired_credentials,false)=false
                )
                """, Map.of("collectorId", collectorId), Boolean.class);
        return Boolean.TRUE.equals(available);
    }

    public int assign(
            long userId,
            long collectorId,
            Set<Long> clientIds) {
        Map<String, Object> parameters = parameters(userId, Set.of(), null);
        parameters.put("collectorId", collectorId);
        parameters.put("clientIds", clientIds);
        parameters.put("administratorId", userId);
        List<Long> assigned = jdbc.query(
                DEBT_CTES + """
                        , eligible AS (
                            SELECT debt.client_id,debt.regiao_id
                            FROM client_debts debt
                            WHERE debt.client_id IN (:clientIds)
                              AND EXISTS (
                                  SELECT 1 FROM regiao_usuario collector_access
                                  WHERE collector_access.usuario_id=:collectorId
                                    AND collector_access.regiao_id=debt.regiao_id
                              )
                        ), saved AS (
                            INSERT INTO money2_rotas_cobranca (
                                cliente_id,regiao_id,cobrador_id,criado_por_id,dtcad,dtalter)
                            SELECT client_id,regiao_id,:collectorId,:administratorId,
                                   CURRENT_TIMESTAMP,CURRENT_TIMESTAMP
                            FROM eligible
                            ON CONFLICT (cliente_id) DO UPDATE
                            SET regiao_id=EXCLUDED.regiao_id,
                                cobrador_id=EXCLUDED.cobrador_id,
                                criado_por_id=EXCLUDED.criado_por_id,
                                dtcad=CURRENT_TIMESTAMP,
                                dtalter=CURRENT_TIMESTAMP
                            RETURNING cliente_id
                        )
                        SELECT cliente_id FROM saved
                        """,
                parameters,
                (result, row) -> result.getLong("cliente_id"));
        return assigned.size();
    }

    public boolean removeAssignment(long userId, long clientId) {
        int removed = jdbc.update("""
                DELETE FROM money2_rotas_cobranca assignment
                WHERE assignment.cliente_id=:clientId
                  AND EXISTS (
                      SELECT 1
                      FROM cliente client
                      JOIN regiao_usuario access
                        ON access.regiao_id=client.regiao_id
                      WHERE client.id=assignment.cliente_id
                        AND access.usuario_id=:userId
                  )
                """, Map.of(
                "userId", userId,
                "clientId", clientId));
        return removed > 0;
    }

    public List<CollectionContractResponse> contracts(long userId, long clientId) {
        Map<String, Object> parameters = parameters(userId, Set.of(), clientId);
        String sql = DEBT_CTES + """
                SELECT loan_id,tipo,total_debt,overdue_debt,
                       GREATEST(CURRENT_DATE-oldest_due_date,0) overdue_days,
                       oldest_due_date
                FROM loan_debts
                ORDER BY oldest_due_date,overdue_debt DESC,loan_id
                """;
        return jdbc.query(sql, parameters, (result, row) -> new CollectionContractResponse(
                result.getLong("loan_id"), typeName(result.getString("tipo")),
                money(result.getBigDecimal("total_debt")),
                money(result.getBigDecimal("overdue_debt")),
                Math.max(result.getInt("overdue_days"), 0),
                result.getObject("oldest_due_date", LocalDate.class)));
    }

    public List<CollectionHistoryResponse> history(long clientId) {
        String sql = """
                SELECT collection.id,collection.cliente_id,collection.regiao_id,
                       region.descricao region_name,collection.usuario_id,
                       TRIM(CONCAT_WS(' ',NULLIF(user_account.first_name,''),
                           NULLIF(user_account.last_name,''))) collector_name,
                       user_account.username,collection.observacao,
                       collection.valor_divida,collection.dias_atraso,
                       collection.arquivo_nome,collection.arquivo_tipo,
                       collection.arquivo_tamanho,collection.arquivo_disco,
                       collection.dtcad
                FROM money2_cobrancas collection
                JOIN users user_account ON user_account.id=collection.usuario_id
                JOIN regioes region ON region.id=collection.regiao_id
                WHERE collection.cliente_id=:clientId
                ORDER BY collection.dtcad DESC,collection.id DESC
                """;
        return jdbc.query(sql, Map.of("clientId", clientId), (result, row) -> {
            String collectorName = clean(result.getString("collector_name"));
            if (collectorName.isBlank()) collectorName = clean(result.getString("username"));
            return new CollectionHistoryResponse(
                    result.getLong("id"), result.getLong("cliente_id"),
                    result.getLong("regiao_id"), clean(result.getString("region_name")),
                    result.getLong("usuario_id"), collectorName,
                    clean(result.getString("observacao")),
                    money(result.getBigDecimal("valor_divida")),
                    Math.max(result.getInt("dias_atraso"), 0),
                    nullable(result.getString("arquivo_nome")),
                    nullable(result.getString("arquivo_tipo")),
                    result.getObject("arquivo_tamanho", Long.class),
                    nullable(result.getString("arquivo_disco")) != null,
                    dateTime(result.getTimestamp("dtcad")));
        });
    }

    public boolean clientAccessible(long userId, long clientId) {
        Boolean accessible = jdbc.queryForObject("""
                SELECT EXISTS (
                    SELECT 1 FROM cliente client
                    JOIN regiao_usuario access ON access.regiao_id=client.regiao_id
                    WHERE client.id=:clientId AND access.usuario_id=:userId
                )
                """, Map.of("userId", userId, "clientId", clientId), Boolean.class);
        return Boolean.TRUE.equals(accessible);
    }

    private Map<String, Object> parameters(
            long userId,
            Set<Long> regionIds,
            Long clientId) {
        Map<String, Object> result = new HashMap<>();
        result.put("userId", userId);
        result.put("filterRegions", regionIds != null && !regionIds.isEmpty());
        result.put("regionIds", regionIds == null || regionIds.isEmpty()
                ? List.of(-1L) : regionIds);
        result.put("filterClient", clientId != null);
        result.put("clientId", clientId == null ? -1L : clientId);
        result.put("filterCity", false);
        result.put("cityId", -1L);
        return result;
    }

    private CollectionRouteItemResponse routeItem(java.sql.ResultSet result)
            throws java.sql.SQLException {
        int collectionCount = result.getInt("collection_count");
        String collectorName = clean(result.getString("collector_full_name"));
        if (collectorName.isBlank()) {
            collectorName = clean(result.getString("collector_username"));
        }
        return new CollectionRouteItemResponse(
                result.getLong("client_id"), clean(result.getString("client_name")),
                result.getLong("regiao_id"), clean(result.getString("region_name")),
                money(result.getBigDecimal("total_debt")),
                money(result.getBigDecimal("overdue_debt")),
                Math.max(result.getInt("overdue_days"), 0),
                result.getInt("overdue_loans"), clean(result.getString("address")),
                result.getBoolean("route_completed")
                        ? CollectionRouteStatus.COMPLETED
                        : CollectionRouteStatus.IN_PROGRESS,
                collectionCount, dateTime(result.getTimestamp("last_collection_at")),
                result.getObject("route_id", Long.class),
                result.getObject("collector_id", Long.class), nullable(collectorName),
                dateTime(result.getTimestamp("assigned_at")));
    }

    private static String typeName(String value) {
        return switch (clean(value)) {
            case "D" -> "Diário";
            case "S" -> "Semanal";
            case "Q" -> "Quinzenal";
            case "M" -> "Mensal";
            case "Z" -> "Diário Seg-Sab";
            case "A" -> "Dia sim e dia não";
            case "B" -> "Todo sábado";
            case "C" -> "Todo domingo";
            default -> "Empréstimo";
        };
    }

    private static BigDecimal money(BigDecimal value) {
        return (value == null ? BigDecimal.ZERO : value)
                .setScale(2, RoundingMode.HALF_UP);
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static String nullable(String value) {
        String cleaned = clean(value);
        return cleaned.isBlank() ? null : cleaned;
    }

    private static LocalDateTime dateTime(Timestamp value) {
        return value == null ? null : value.toLocalDateTime();
    }
}
