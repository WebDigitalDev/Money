package com.webdigital.money2.dashboard;

import static org.assertj.core.api.Assertions.assertThat;

import com.webdigital.money2.users.RegionRepository;
import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.data.jpa.repository.Query;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

@EnabledIfEnvironmentVariable(named = "MONEY2_TEST_DB_URL", matches = ".+")
class DashboardReceivedPostgresTest {

    private Connection connection;
    private JdbcTemplate jdbc;
    private NamedParameterJdbcTemplate namedJdbc;
    private DashboardRepository repository;
    private LocalDate today;

    @BeforeEach
    void setUp() throws Exception {
        connection = DriverManager.getConnection(
                System.getenv("MONEY2_TEST_DB_URL"),
                System.getenv("MONEY2_TEST_DB_USERNAME"),
                System.getenv("MONEY2_TEST_DB_PASSWORD"));
        connection.setAutoCommit(false);
        jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
        jdbc.execute("SET LOCAL search_path TO pg_temp");
        jdbc.execute("SET LOCAL statement_timeout = '10s'");
        jdbc.execute("CREATE TEMP TABLE regioes (id bigint, descricao text, responsaveis text) ON COMMIT DROP");
        jdbc.execute("CREATE TEMP TABLE regiao_usuario (usuario_id bigint, regiao_id bigint) ON COMMIT DROP");
        jdbc.execute("CREATE TEMP TABLE cliente (id bigint, regiao_id bigint, nome text) ON COMMIT DROP");
        jdbc.execute("""
                CREATE TEMP TABLE emprestimo (
                    id bigint, cliente_id bigint, status integer, tipo text,
                    refinanciado boolean, renovacao boolean, desaparecido boolean,
                    aprovacao_status text, vlr_receber numeric, vlr_lucro numeric,
                    valor_emprestado numeric, data timestamp
                ) ON COMMIT DROP
                """);
        jdbc.execute("""
                CREATE TEMP TABLE parcelas (
                    id bigint, emprestimo_id bigint, pendente boolean,
                    vencimento timestamp, valor numeric, valor_juros numeric
                ) ON COMMIT DROP
                """);
        jdbc.execute("""
                CREATE TEMP TABLE pagamentos (
                    parcela_id bigint, valor numeric, aprovacao_status text,
                    tipo text, data timestamp
                ) ON COMMIT DROP
                """);
        jdbc.update("INSERT INTO regioes VALUES (1, 'A', NULL), (2, 'B', NULL), (3, 'C', NULL)");
        jdbc.update("INSERT INTO regiao_usuario VALUES (7, 1), (7, 2)");
        jdbc.update("INSERT INTO cliente VALUES (101, 1, 'A'), (102, 2, 'B'), (103, 3, 'C')");
        jdbc.update("""
                INSERT INTO emprestimo
                SELECT id, cliente_id, 2, 'D', false, false, false, 'APROVADO',
                       0, 0, 500, CURRENT_DATE
                FROM (VALUES (11, 101), (12, 102), (13, 103)) fixture(id, cliente_id)
                """);
        jdbc.update("""
                INSERT INTO parcelas
                SELECT id, emprestimo_id, true, CURRENT_DATE - INTERVAL '1 day', 600, 20
                FROM (VALUES (1, 11), (2, 12), (3, 13)) fixture(id, emprestimo_id)
                """);
        namedJdbc = new NamedParameterJdbcTemplate(jdbc) {
            // Stub unrelated profit calculation so fixtures never access public tables.
            @Override
            public <T> List<T> query(String sql, Map<String, ?> parameters, RowMapper<T> mapper) {
                return super.query(withoutProfitFunction(sql), parameters, mapper);
            }

            @Override
            public <T> T queryForObject(String sql, Map<String, ?> parameters, RowMapper<T> mapper) {
                return super.queryForObject(withoutProfitFunction(sql), parameters, mapper);
            }
        };
        repository = new DashboardRepository(namedJdbc);
        today = jdbc.queryForObject("SELECT CURRENT_DATE", LocalDate.class);
    }

    @AfterEach
    void tearDown() throws Exception {
        if (connection != null) {
            try {
                connection.rollback();
            } finally {
                connection.close();
            }
        }
    }

    @Test
    void receivedPaymentsSurviveRefinancingAndOtherLoanStatusChanges() throws Exception {
        payment(1, "100", "APROVADO", "NORMAL", today);
        assertReceived("100.00", List.of(1L));
        assertThat(repository.metrics(7, List.of(1L)).overdueAmount()).isEqualByComparingTo("520.00");

        jdbc.update("UPDATE emprestimo SET refinanciado = true WHERE id = 11");
        assertReceived("100.00", List.of(1L));
        assertThat(repository.metrics(7, List.of(1L)).overdueAmount()).isEqualByComparingTo("0.00");
        assertThat(repository.financial(7, List.of(1L)).overdueAmount()).isEqualByComparingTo("0.00");

        jdbc.update("UPDATE emprestimo SET refinanciado = false, renovacao = true WHERE id = 11");
        assertReceived("100.00", List.of(1L));
        jdbc.update("UPDATE emprestimo SET renovacao = false, desaparecido = true WHERE id = 11");
        assertReceived("100.00", List.of(1L));
        jdbc.update("UPDATE emprestimo SET desaparecido = false, status = 3 WHERE id = 11");
        assertReceived("100.00", List.of(1L));
        jdbc.update("UPDATE emprestimo SET status = 1, aprovacao_status = 'PENDENTE' WHERE id = 11");
        assertReceived("100.00", List.of(1L));
    }

    @Test
    void approvedPaymentsMatchRegionsAtBothPeriodBoundariesIncludingLegacyAndInterestPayments() throws Exception {
        payment(1, "100", "APROVADO", "NORMAL", today.minusDays(30));
        payment(1, "200", "APROVADO", "NORMAL", today);
        jdbc.update("UPDATE pagamentos SET data = data + INTERVAL '23 hours 59 minutes 59 seconds' WHERE valor = 200");
        payment(1, "30", null, null, today);
        payment(1, "40", "APROVADO", "JUROS_ROLAGEM", today);
        payment(1, "1000", "PENDENTE", "NORMAL", today);
        payment(1, "2000", "INDEFERIDO", "NORMAL", today);
        payment(1, "4000", "APROVADO", "NORMAL", today.minusDays(31));
        payment(1, "8000", "APROVADO", "NORMAL", today.plusDays(1));

        var financial = repository.financial(7, List.of(1L));
        assertThat(financial.receivedAmount()).isEqualByComparingTo("370.00");
        assertThat(financial.receivedAmount()).isEqualByComparingTo(regionsReceived(List.of(1L)));
        assertThat(financial.points()).hasSize(31);
        assertThat(financial.points().get(0).receivedAmount()).isEqualByComparingTo("100.00");
        assertThat(financial.points().get(30).receivedAmount()).isEqualByComparingTo("270.00");
        assertThat(repository.metrics(7, List.of(1L)).receivedTodayAmount()).isEqualByComparingTo("270.00");
        assertThat(repository.metrics(7, List.of(1L)).receivedTodayPayments()).isEqualTo(3);
    }

    @Test
    void receivedPaymentsRespectSelectedRegionsAndMembershipAndAllowTutorialMode() throws Exception {
        payment(1, "100", "APROVADO", "NORMAL", today);
        payment(2, "200", "APROVADO", "NORMAL", today);
        payment(3, "9000", "APROVADO", "NORMAL", today);
        assertReceived("100.00", List.of(1L));
        assertReceived("200.00", List.of(2L));
        assertReceived("300.00", List.of(1L, 2L, 3L));
        assertReceived("0.00", List.of(3L));
        assertThat(repository.financial(7, List.of(3L), true).receivedAmount()).isEqualByComparingTo("9000.00");
        assertThat(repository.metrics(7, List.of(3L), true).receivedTodayAmount()).isEqualByComparingTo("9000.00");
    }

    private void assertReceived(String amount, List<Long> regionIds) throws Exception {
        var financial = repository.financial(7, regionIds);
        assertThat(financial.receivedAmount()).isEqualByComparingTo(amount);
        assertThat(financial.receivedAmount()).isEqualByComparingTo(regionsReceived(regionIds));
        assertThat(repository.metrics(7, regionIds).receivedTodayAmount()).isEqualByComparingTo(amount);
    }

    private BigDecimal regionsReceived(List<Long> regionIds) throws Exception {
        String sql = RegionRepository.class
                .getMethod("findSummaries", Long.class, LocalDate.class, LocalDate.class)
                .getAnnotation(Query.class).value();
        return namedJdbc.query(sql,
                new MapSqlParameterSource("userId", 7L)
                        .addValue("startDate", today.minusDays(30), Types.DATE)
                        .addValue("endDate", today, Types.DATE),
                (rs, row) -> regionIds.contains(rs.getLong(1)) ? rs.getBigDecimal(9) : BigDecimal.ZERO)
                .stream().reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    private void payment(long installment, String amount, String approval, String type, LocalDate date) {
        jdbc.update("INSERT INTO pagamentos VALUES (?, CAST(? AS numeric), ?, ?, ?)",
                installment, amount, approval, type, java.sql.Date.valueOf(date));
    }

    private String withoutProfitFunction(String sql) {
        return sql.replace("public.calcular_lucro_fluxo(event.id)", "0::numeric");
    }
}
