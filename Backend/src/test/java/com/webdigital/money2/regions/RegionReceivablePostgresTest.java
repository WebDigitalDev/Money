package com.webdigital.money2.regions;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.nullable;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.webdigital.money2.auth.UserAccount;
import com.webdigital.money2.users.RegionRepository;
import com.webdigital.money2.users.UserRegionRepository;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Types;
import java.time.LocalDate;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.data.jpa.repository.Query;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

@EnabledIfEnvironmentVariable(named = "MONEY2_TEST_DB_URL", matches = ".+")
class RegionReceivablePostgresTest {

    private Connection connection;
    private JdbcTemplate jdbc;
    private RegionManagementService service;
    private UserAccount user;

    @BeforeEach
    void setUp() throws Exception {
        connection = DriverManager.getConnection(
                System.getenv("MONEY2_TEST_DB_URL"),
                System.getenv("MONEY2_TEST_DB_USERNAME"),
                System.getenv("MONEY2_TEST_DB_PASSWORD"));
        connection.setAutoCommit(false);
        jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
        // Only session-local fixtures are visible; public tables cannot be used.
        jdbc.execute("SET LOCAL search_path TO pg_temp");
        jdbc.execute("SET LOCAL statement_timeout = '10s'");
        jdbc.execute("""
                CREATE TEMP TABLE regioes (
                    id bigint, descricao text, responsaveis text
                ) ON COMMIT DROP
                """);
        jdbc.execute("""
                CREATE TEMP TABLE regiao_usuario (
                    usuario_id bigint, regiao_id bigint
                ) ON COMMIT DROP
                """);
        jdbc.execute("""
                CREATE TEMP TABLE cliente (
                    id bigint, regiao_id bigint
                ) ON COMMIT DROP
                """);
        jdbc.execute("""
                CREATE TEMP TABLE emprestimo (
                    id bigint, cliente_id bigint, status integer,
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
        jdbc.update("INSERT INTO regioes VALUES (1, 'Região A', NULL), (2, 'Região B', NULL)");
        jdbc.update("INSERT INTO regiao_usuario VALUES (7, 1), (7, 2)");
        jdbc.update("INSERT INTO cliente VALUES (101, 1), (102, 2)");
        jdbc.update("""
                INSERT INTO emprestimo VALUES
                    (11, 101, 2, false, false, false, 'APROVADO', 0, 0, 500, CURRENT_DATE),
                    (12, 102, 2, false, false, false, 'APROVADO', 0, 0, 500, CURRENT_DATE)
                """);

        String sql = RegionRepository.class
                .getMethod("findSummaries", Long.class, LocalDate.class, LocalDate.class)
                .getAnnotation(Query.class).value();
        NamedParameterJdbcTemplate namedJdbc = new NamedParameterJdbcTemplate(jdbc);
        RegionRepository repository = mock(RegionRepository.class);
        when(repository.findSummaries(eq(7L), nullable(LocalDate.class), nullable(LocalDate.class)))
                .thenAnswer(invocation -> namedJdbc.query(sql,
                        new MapSqlParameterSource("userId", 7L)
                                .addValue("startDate", invocation.getArgument(1), Types.DATE)
                                .addValue("endDate", invocation.getArgument(2), Types.DATE),
                        (rs, rowNumber) -> {
                            Object[] row = new Object[rs.getMetaData().getColumnCount()];
                            for (int index = 0; index < row.length; index++) {
                                row[index] = rs.getObject(index + 1);
                            }
                            return row;
                        }));
        service = new RegionManagementService(repository, mock(UserRegionRepository.class));
        user = mock(UserAccount.class);
        when(user.getId()).thenReturn(7L);
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
    void receivableExcludesAdditionalInterestAndOnlyApprovedPaymentsAmortizeIt() {
        installment(1, 11, "600", "120", true);
        payment(1, "100", "APROVADO", "NORMAL");
        payment(1, "50", "PENDENTE", "NORMAL");
        payment(1, "40", "INDEFERIDO", "NORMAL");
        payment(1, "200", "APROVADO", "JUROS_ROLAGEM");

        RegionListResponse result = search("");
        RegionSummaryResponse region = result.items().get(0);

        assertThat(region.receivableAmount()).isEqualByComparingTo("500.00");
        assertThat(result.totals().receivableAmount()).isEqualByComparingTo("500.00");
        assertThat(region.overdueAmount()).isEqualByComparingTo("620.00");
        assertThat(region.receivedAmount()).isEqualByComparingTo("300.00");
    }

    @Test
    void settledInstallmentsAndOverpaymentsCannotMakeReceivableNegative() {
        installment(1, 11, "600", "120", true);
        payment(1, "650", "APROVADO", "NORMAL");
        installment(2, 11, "300", "80", false);
        installment(3, 11, "200", "30", true);
        payment(3, "50", "APROVADO", "NORMAL");

        assertThat(search("").totals().receivableAmount()).isEqualByComparingTo("150.00");
    }

    @Test
    void installmentsWithoutAdditionalInterestKeepTheirBalanceAndLegacyPaymentDefaults() {
        installment(1, 11, "600", null, true);
        payment(1, "100", null, null);

        assertThat(search("").totals().receivableAmount()).isEqualByComparingTo("500.00");
    }

    @Test
    void contractsAwaitingApprovalDoNotEnterReceivable() {
        installment(1, 11, "600", "120", true);
        jdbc.update("UPDATE emprestimo SET aprovacao_status = 'PENDENTE' WHERE id = 11");

        assertThat(search("").totals().receivableAmount()).isEqualByComparingTo("0.00");
    }

    @Test
    void totalsRespectRegionFiltersAndUserAccess() {
        installment(1, 11, "600", "120", true);
        installment(2, 12, "300", "90", true);
        jdbc.update("INSERT INTO regioes VALUES (3, 'Região não permitida', NULL)");
        jdbc.update("INSERT INTO cliente VALUES (103, 3)");
        jdbc.update("INSERT INTO emprestimo SELECT 13, 103, status, refinanciado, renovacao, "
                + "desaparecido, aprovacao_status, vlr_receber, vlr_lucro, valor_emprestado, data "
                + "FROM emprestimo WHERE id = 11");
        installment(3, 13, "9999", "999", true);

        RegionListResponse all = search("");
        assertThat(all.items()).extracting(RegionSummaryResponse::id).containsExactly(1L, 2L);
        assertThat(all.totals().receivableAmount()).isEqualByComparingTo("900.00");
        RegionListResponse filtered = search("2");
        assertThat(filtered.items()).extracting(RegionSummaryResponse::id).containsExactly(2L);
        assertThat(filtered.totals().receivableAmount()).isEqualByComparingTo("300.00");
    }

    @Test
    void periodFiltersReceiptsButPreservesCurrentReceivable() {
        installment(1, 11, "600", "120", true);
        payment(1, "100", "APROVADO", "NORMAL");
        jdbc.update("UPDATE pagamentos SET data = CURRENT_DATE - INTERVAL '2 days'");
        LocalDate today = jdbc.queryForObject("SELECT CURRENT_DATE", LocalDate.class);

        RegionListResponse result = service.search(user, "", today, today, "");

        assertThat(result.totals().receivableAmount()).isEqualByComparingTo("500.00");
        assertThat(result.totals().receivedAmount()).isEqualByComparingTo("0.00");
    }

    private RegionListResponse search(String regionIds) {
        return service.search(user, "", null, null, regionIds);
    }

    private void installment(long id, long loanId, String amount, String interest, boolean pending) {
        jdbc.update("""
                INSERT INTO parcelas VALUES (?, ?, ?, CURRENT_DATE - INTERVAL '1 day',
                    CAST(? AS numeric), CAST(? AS numeric))
                """, id, loanId, pending, amount, interest);
    }

    private void payment(long installmentId, String amount, String approval, String type) {
        jdbc.update("INSERT INTO pagamentos VALUES (?, CAST(? AS numeric), ?, ?, CURRENT_DATE)",
                installmentId, amount, approval, type);
    }
}
