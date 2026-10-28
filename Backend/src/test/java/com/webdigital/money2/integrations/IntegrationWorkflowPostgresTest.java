package com.webdigital.money2.integrations;

import static org.junit.jupiter.api.Assertions.*;

import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

/** Exercises production SQL against session-local fixtures; public tables cannot be used. */
@EnabledIfEnvironmentVariable(named = "MONEY2_TEST_DB_URL", matches = ".+")
class IntegrationWorkflowPostgresTest {
    private Connection connection;
    private JdbcTemplate jdbc;
    private IntegrationRepository collections;
    private PixWorkflowRepository workflow;

    @BeforeEach
    void setUp() throws Exception {
        connection = DriverManager.getConnection(System.getenv("MONEY2_TEST_DB_URL"),
                System.getenv("MONEY2_TEST_DB_USERNAME"), System.getenv("MONEY2_TEST_DB_PASSWORD"));
        connection.setAutoCommit(false);
        jdbc = new JdbcTemplate(new SingleConnectionDataSource(connection, true));
        jdbc.execute("SET LOCAL search_path TO pg_temp");
        jdbc.execute("SET LOCAL statement_timeout='10s'");
        jdbc.execute("""
                CREATE TEMP TABLE cliente (id bigint PRIMARY KEY,nome text,regiao_id bigint,ativo boolean,
                    celular text,telefone text,telefone2 text) ON COMMIT DROP
                """);
        jdbc.execute("""
                CREATE TEMP TABLE emprestimo (id bigint PRIMARY KEY,cliente_id bigint,status integer,
                    aprovacao_status text,refinanciado boolean,renovacao boolean,desaparecido boolean,
                    vlrmulta double precision) ON COMMIT DROP
                """);
        jdbc.execute("""
                CREATE TEMP TABLE parcelas (id bigint PRIMARY KEY,emprestimo_id bigint,parcela text,
                    vencimento timestamp,pendente boolean,status text,valor double precision,
                    valor_juros double precision,dtalter timestamp) ON COMMIT DROP
                """);
        jdbc.execute("""
                CREATE TEMP TABLE pagamentos (parcela_id bigint,emprestimo_id bigint,valor double precision,
                    aprovacao_status text,tipo text,id_pagamento bigserial PRIMARY KEY,data timestamp,
                    observacao text,automatico boolean,dtcad timestamp,dtalter timestamp) ON COMMIT DROP
                """);
        jdbc.execute("""
                CREATE TEMP TABLE pix_cobrancas (id bigint PRIMARY KEY,emprestimo_id bigint,status text,
                    pagamento_processado boolean,txid text,dtalter timestamp,dtcad timestamp,erro text,
                    confirmacao_whatsapp_enviada boolean,dt_tentativa_whatsapp timestamp,erro_whatsapp text,
                    parcela_id bigint,pagamento_id bigint,conta_bancaria_configuracao_id bigint DEFAULT 3,
                    valor double precision DEFAULT 100,pix_copia_cola text,qr_code text,location text,
                    dt_pagamento timestamp)
                    ON COMMIT DROP
                """);
        jdbc.execute("CREATE TEMP TABLE whatsapp_dispositivo_regioes (dispositivo_id bigint,regiao_id bigint) ON COMMIT DROP");
        jdbc.execute("CREATE TEMP TABLE entity_log_detalhado (entity_name text,entity_id bigint,operation text,description text,username text,timestamp timestamp) ON COMMIT DROP");
        String migration = Files.readString(Path.of("deploy/postgresql17-pix-whatsapp-outbox.sql"));
        jdbc.execute(migration.substring(migration.indexOf("CREATE TABLE"), migration.indexOf("CREATE INDEX"))
                .replace("CREATE TABLE IF NOT EXISTS", "CREATE TEMP TABLE"));
        jdbc.update("INSERT INTO cliente VALUES (10,'CLIENTE',7,true,'65999999999',NULL,NULL)");
        jdbc.update("INSERT INTO emprestimo VALUES (700,10,2,'APROVADO',false,false,false,0)");
        jdbc.update("INSERT INTO parcelas(id,emprestimo_id,parcela,vencimento,pendente,valor,valor_juros) VALUES (30,700,'1',CURRENT_DATE-INTERVAL '2 days',true,100,0)");
        jdbc.update("INSERT INTO whatsapp_dispositivo_regioes VALUES (1,7)");
        var named = new NamedParameterJdbcTemplate(jdbc);
        collections = new IntegrationRepository(named);
        workflow = new PixWorkflowRepository(named);
    }

    @AfterEach
    void close() throws Exception {
        if (connection != null) {
            try { connection.rollback(); } finally { connection.close(); }
        }
    }

    @Test
    void fullPaymentIsExcludedEvenWithStalePendingFlagAndFloatingPointResidue() {
        jdbc.update("UPDATE parcelas SET valor=100.0000000001");
        payment("100", "APROVADO", "NORMAL");

        assertTrue(collections.dispatchTargets(1, "ATRASADAS").isEmpty());
        assertEquals(0, collections.pendingAmount(30).compareTo(BigDecimal.ZERO));
        assertNull(collections.overdueSummary(700));
    }

    @Test
    void paymentConfirmedAtBankButNotPostedSuppressesCollection() {
        assertEquals(1, collections.dispatchTargets(1, "ATRASADAS").size());
        pix("PAGO", false);

        assertTrue(collections.dispatchTargets(1, "ATRASADAS").isEmpty());
        assertNull(collections.overdueSummary(700));
    }

    @Test
    void pendingPaymentSuspendsCollectionUntilReview() {
        var target = collections.dispatchTargets(1, "ATRASADAS").get(0);
        payment("100", "PENDENTE", "NORMAL");

        assertFalse(collections.isDispatchTargetEligible("ATRASADAS", target));
        assertTrue(collections.dispatchTargets(1, "ATRASADAS").isEmpty());
    }

    @Test
    void partialPaymentOnlyCollectsRemainingDebtAndInterestRolloverDoesNotAmortizeIt() {
        payment("40", "APROVADO", "NORMAL");
        payment("20", "APROVADO", "JUROS_ROLAGEM");
        payment("40", "INDEFERIDO", "NORMAL");

        var target = collections.dispatchTargets(1, "ATRASADAS").get(0);
        assertTrue(collections.isDispatchTargetEligible("ATRASADAS", target));
        assertEquals(0, new BigDecimal("60").compareTo(target.pendingAmount()));
        assertEquals(0, new BigDecimal("60").compareTo(collections.overdueSummary(700).debt()));
    }

    @Test
    void queuedTargetBecomesIneligibleAfterPayment() {
        var target = collections.dispatchTargets(1, "ATRASADAS").get(0);
        payment("100", "APROVADO", "NORMAL");

        assertFalse(collections.isDispatchTargetEligible("ATRASADAS", target));
    }

    @Test
    void bothMessagesArePersistedOnceAndContractSurvivesReceiptFailure() {
        pix("PAGO", true);
        workflow.enqueue(92);
        workflow.enqueue(92);
        assertEquals(2, jdbc.queryForObject("SELECT COUNT(*) FROM money2_pix_whatsapp_outbox", Integer.class));
        var receipt = workflow.claim();
        assertTrue(receipt.receipt());
        assertNull(workflow.claim()); // Contract waits for the first receipt attempt to finish.
        workflow.failed(receipt, "Dispositivo indisponível");

        var contract = workflow.claim();
        assertEquals("EMPRESTIMO_ATUALIZADO", contract.type());
        workflow.accepted(contract, "dispatch-contract", null);
        assertNull(workflow.claim());
        jdbc.update("UPDATE money2_pix_whatsapp_outbox SET proxima_tentativa=LOCALTIMESTAMP-INTERVAL '1 second' WHERE tipo='PIX_RECEBIDO'");
        var retried = workflow.claim();
        assertTrue(retried.receipt());
        assertEquals(2, retried.attempts());
        workflow.accepted(retried, "dispatch-receipt", null);
        assertNull(workflow.claim());
        assertTrue(jdbc.queryForObject("SELECT confirmacao_whatsapp_enviada FROM pix_cobrancas WHERE id=92", Boolean.class));
    }

    @Test
    void crashRecoveryKeepsPayloadAndDoesNotReplayAcceptedReceipt() {
        pix("PAGO", true);
        workflow.enqueue(92);
        var receipt = workflow.claim();
        workflow.accepted(receipt, "receipt", null);
        var contract = workflow.claim();
        var frozen = new PixWorkflowRepository.Delivery(92, contract.type(), contract.attempts(), contract.token(),
                1L, "device", "65999999999", "CLIENTE", "Contrato congelado");
        workflow.savePayload(frozen);
        jdbc.update("UPDATE money2_pix_whatsapp_outbox SET bloqueado_em=LOCALTIMESTAMP-INTERVAL '4 minutes' WHERE tipo='EMPRESTIMO_ATUALIZADO'");

        var recovered = workflow.claim();
        assertEquals("Contrato congelado", recovered.message());
        assertNotEquals(contract.token(), recovered.token());
        workflow.accepted(contract, "stale-worker", null);
        assertEquals("PROCESSANDO", jdbc.queryForObject("SELECT status FROM money2_pix_whatsapp_outbox WHERE tipo='EMPRESTIMO_ATUALIZADO'", String.class));
        workflow.accepted(recovered, "contract", null);
        assertNull(workflow.claim());
    }

    @Test
    void rollbackCannotLeaveMessagesForAnUncommittedPayment() throws Exception {
        pix("PAGO", true);
        var savepoint = connection.setSavepoint();
        workflow.enqueue(92);
        connection.rollback(savepoint);
        assertNull(workflow.claim());
    }

    @Test
    void failingHistoricalPaymentsDoNotStarveWaitingCharges() {
        pix("PAGO", false);
        jdbc.update("UPDATE pix_cobrancas SET erro='Falha anterior',dtalter=LOCALTIMESTAMP");
        jdbc.update("INSERT INTO pix_cobrancas(id,emprestimo_id,status,txid,dtcad,dtalter) VALUES (93,700,'AGUARDANDO','M2-new',LOCALTIMESTAMP,LOCALTIMESTAMP)");

        assertEquals(java.util.List.of(93L), workflow.reconciliationIds());
        assertEquals(java.util.List.of(92L,93L), workflow.collectionChargeIds(700));
    }

    @Test
    void oversizedPixPaysAllInstallmentsAndBooksEntireExcessOnLastOne() {
        twoInstallments();
        pix("PAGO", false);
        jdbc.update("UPDATE pix_cobrancas SET valor=150");
        var repository = new PixRepository(new NamedParameterJdbcTemplate(jdbc));

        assertTrue(repository.processPayment(92, "M2-test", java.time.LocalDateTime.now()).processedNow());
        assertEquals(150.0, jdbc.queryForObject("SELECT SUM(valor) FROM pagamentos", Double.class));
        assertEquals(50.0, jdbc.queryForObject("SELECT SUM(valor) FROM pagamentos WHERE parcela_id=30", Double.class));
        assertEquals(100.0, jdbc.queryForObject("SELECT SUM(valor) FROM pagamentos WHERE parcela_id=31", Double.class));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM parcelas WHERE pendente", Integer.class));
        assertEquals(2, jdbc.queryForObject("SELECT COUNT(*) FROM pagamentos", Integer.class));
        assertFalse(repository.processPayment(92, "M2-test", java.time.LocalDateTime.now()).processedNow());
        assertEquals(150.0, jdbc.queryForObject("SELECT SUM(valor) FROM pagamentos", Double.class));
    }

    @Test
    void pixForOneInstallmentCanPayRestOfContractAndAllocateExcessToFinalInstallment() {
        twoInstallments();
        pix("PAGO", false);
        jdbc.update("UPDATE pix_cobrancas SET valor=150,parcela_id=30");

        new PixRepository(new NamedParameterJdbcTemplate(jdbc))
                .processPayment(92, "M2-test", java.time.LocalDateTime.now());

        assertEquals(50.0, jdbc.queryForObject("SELECT SUM(valor) FROM pagamentos WHERE parcela_id=30", Double.class));
        assertEquals(100.0, jdbc.queryForObject("SELECT SUM(valor) FROM pagamentos WHERE parcela_id=31", Double.class));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM parcelas WHERE pendente", Integer.class));
    }

    @Test
    void paymentOnAlreadySettledContractIsStillRecordedInFullOnLastInstallment() {
        twoInstallments();
        jdbc.update("UPDATE parcelas SET pendente=false");
        payment("50", "APROVADO", "NORMAL");
        jdbc.update("INSERT INTO pagamentos(parcela_id,emprestimo_id,valor,aprovacao_status,tipo) VALUES (31,700,50,'APROVADO','NORMAL')");
        pix("PAGO", false);
        jdbc.update("UPDATE pix_cobrancas SET valor=25,parcela_id=30");

        new PixRepository(new NamedParameterJdbcTemplate(jdbc))
                .processPayment(92, "M2-test", java.time.LocalDateTime.now());

        assertEquals(125.0, jdbc.queryForObject("SELECT SUM(valor) FROM pagamentos", Double.class));
        assertEquals(25.0, jdbc.queryForObject("SELECT SUM(valor) FROM pagamentos WHERE parcela_id=31 AND observacao='PIX TXID M2-test'", Double.class));
        assertTrue(jdbc.queryForObject("SELECT pagamento_processado FROM pix_cobrancas WHERE id=92", Boolean.class));
    }

    @Test
    void lastInstallmentGetsExcessEvenWhenItWasAlreadyPaid() {
        twoInstallments();
        jdbc.update("UPDATE parcelas SET pendente=false WHERE id=31");
        jdbc.update("INSERT INTO pagamentos(parcela_id,emprestimo_id,valor,aprovacao_status,tipo) VALUES (31,700,50,'APROVADO','NORMAL')");
        pix("PAGO", false);
        jdbc.update("UPDATE pix_cobrancas SET valor=75");

        new PixRepository(new NamedParameterJdbcTemplate(jdbc))
                .processPayment(92, "M2-test", java.time.LocalDateTime.now());

        assertEquals(50.0, jdbc.queryForObject("SELECT SUM(valor) FROM pagamentos WHERE parcela_id=30", Double.class));
        assertEquals(75.0, jdbc.queryForObject("SELECT SUM(valor) FROM pagamentos WHERE parcela_id=31", Double.class));
        assertEquals(2, jdbc.queryForObject("SELECT COUNT(*) FROM pagamentos WHERE observacao='PIX TXID M2-test'", Integer.class));
    }

    private void twoInstallments() {
        jdbc.update("UPDATE parcelas SET valor=50");
        jdbc.update("INSERT INTO parcelas(id,emprestimo_id,parcela,vencimento,pendente,valor,valor_juros) VALUES (31,700,'2',CURRENT_DATE-INTERVAL '1 day',true,50,0)");
    }

    private void payment(String value, String approval, String type) {
        jdbc.update("INSERT INTO pagamentos(parcela_id,emprestimo_id,valor,aprovacao_status,tipo) VALUES (30,700,?,?,?)", Double.valueOf(value), approval, type);
    }

    private void pix(String status, boolean processed) {
        jdbc.update("INSERT INTO pix_cobrancas(id,emprestimo_id,status,pagamento_processado,txid,dtcad,dtalter) VALUES (92,700,?,?,'M2-test',LOCALTIMESTAMP,LOCALTIMESTAMP)", status, processed);
    }
}
