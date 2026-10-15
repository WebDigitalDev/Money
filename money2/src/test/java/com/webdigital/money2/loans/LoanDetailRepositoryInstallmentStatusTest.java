package com.webdigital.money2.loans;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class LoanDetailRepositoryInstallmentStatusTest {

    @Test
    void derivesStatusFromCurrentBalanceAndDueDate() {
        assertThat(status(true, "0", 1, false)).isEqualTo("Vencido");
        assertThat(status(true, "0", 0, true)).isEqualTo("Vence hoje");
        assertThat(status(true, "0", 0, false)).isEqualTo("À Vencer");
        assertThat(status(true, "10", 3, false)).isEqualTo("Parcial");
        assertThat(status(false, "38", 3, false)).isEqualTo("Pago");
    }

    private static String status(
            boolean pending, String paid, int overdueDays, boolean dueToday) {
        return LoanDetailRepository.installmentStatus(
                pending, new BigDecimal(paid), overdueDays, dueToday);
    }
}
