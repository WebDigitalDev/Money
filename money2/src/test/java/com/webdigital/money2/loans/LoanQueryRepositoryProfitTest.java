package com.webdigital.money2.loans;

import static org.assertj.core.api.Assertions.assertThat;

import java.lang.reflect.Field;
import org.junit.jupiter.api.Test;

class LoanQueryRepositoryProfitTest {

    @Test
    void filteredTotalAndCardsUseTheSameSetBasedProfitCalculation() throws Exception {
        Field field = LoanQueryRepository.class.getDeclaredField("SEARCH_SQL");
        field.setAccessible(true);

        String query = (String) field.get(null);

        assertThat(query)
                .contains("profit_targets AS MATERIALIZED")
                .contains("profit_chain(target_id, loan_id)")
                .contains("chain_payments AS")
                .contains("chain_root_capital AS")
                .contains("chain_renewal_capital AS")
                .contains("SUM(COALESCE(profits.profit_amount, 0))")
                .contains("WHERE loan_status IN ('Quitado', 'Renov/Abat')")
                .doesNotContain("calcular_lucro_fluxo")
                .doesNotContain("cached_profit_amount");
    }

    @Test
    void pageMarksAnyLoanWithAnAwaitingPixCharge() throws Exception {
        Field field = LoanQueryRepository.class.getDeclaredField("SEARCH_SQL");
        field.setAccessible(true);

        String query = (String) field.get(null);

        assertThat(query)
                .contains("EXISTS (")
                .contains("FROM pix_cobrancas pix")
                .contains("UPPER(COALESCE(pix.status, '')) = 'AGUARDANDO'")
                .contains("pix.pix_copia_cola")
                .contains(") AS has_pending_pix")
                .doesNotContain("WHEN paged_base.loan_status = 'Vence hoje' THEN EXISTS");
    }
}
