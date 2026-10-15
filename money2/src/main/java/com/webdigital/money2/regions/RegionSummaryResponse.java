package com.webdigital.money2.regions;

import java.math.BigDecimal;

public record RegionSummaryResponse(
        Long id,
        String description,
        String responsiblePeople,
        int activeClients,
        int missingClients,
        int currentClients,
        int overdueClients,
        BigDecimal overdueAmount,
        BigDecimal receivedAmount,
        BigDecimal dueTodayAmount,
        BigDecimal receivableAmount,
        BigDecimal missingAmount,
        BigDecimal profitAmount,
        BigDecimal loanedAmount) {
}
