package com.webdigital.money2.reports;

import static org.assertj.core.api.Assertions.assertThat;

import java.lang.reflect.Field;
import org.junit.jupiter.api.Test;

class AuditHistoryRepositoryTest {

    @Test
    void distributedPaymentUsesLoanToResolveClientAndRegion() throws Exception {
        Field field = AuditHistoryRepository.class.getDeclaredField("HISTORY_SQL");
        field.setAccessible(true);

        String query = (String) field.get(null);

        assertThat(query)
                .contains("payment_log.id_pagamento = l.entity_id")
                .contains("contract_payment_loan.id = l.entity_id")
                .containsPattern("operation NOT IN \\([\\s\\S]*'lancarPagamentoContrato'")
                .containsPattern("l\\.operation IN \\([\\s\\S]*'lancarPagamentoContrato'");
        assertThat(countOccurrences(query, "'lancarPagamentoContrato'"))
                .isEqualTo(2);
    }

    private static int countOccurrences(String source, String target) {
        int count = 0;
        int offset = 0;
        while ((offset = source.indexOf(target, offset)) >= 0) {
            count++;
            offset += target.length();
        }
        return count;
    }
}
