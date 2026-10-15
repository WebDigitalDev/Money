package com.webdigital.money2.clients;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;

class ClientScoreRepositoryTest {

    private static final LocalDate DUE_DATE = LocalDate.of(2026, 9, 1);

    @Test
    void appliesSettlementAdjustmentsAtEveryBoundary() {
        assertThat(adjustment(-1)).isEqualTo(10);
        assertThat(adjustment(0)).isEqualTo(5);
        assertThat(adjustment(1)).isEqualTo(-5);
        assertThat(adjustment(10)).isEqualTo(-5);
        assertThat(adjustment(11)).isEqualTo(-10);
        assertThat(adjustment(30)).isEqualTo(-10);
        assertThat(adjustment(31)).isEqualTo(-20);
    }

    @Test
    void appliesEventsInOrderAndKeepsScoreBetweenZeroAndOneHundred() {
        assertThat(ClientScoreRepository.scoreAfter(List.of(10, -5)))
                .isEqualTo(95);
        assertThat(ClientScoreRepository.scoreAfter(List.of(-20, 10)))
                .isEqualTo(90);
        assertThat(ClientScoreRepository.scoreAfter(List.of(-100, -20)))
                .isZero();
        assertThat(ClientScoreRepository.scoreAfter(List.of(-100, 10)))
                .isEqualTo(10);
    }

    private int adjustment(int daysAfterDueDate) {
        return ClientScoreRepository.settlementAdjustment(
                DUE_DATE, DUE_DATE.plusDays(daysAfterDueDate));
    }
}
