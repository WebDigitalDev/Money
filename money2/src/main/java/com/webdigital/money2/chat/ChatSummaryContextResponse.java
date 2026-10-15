package com.webdigital.money2.chat;

import java.time.LocalDate;

public record ChatSummaryContextResponse(
        long regionId,
        String regionName,
        LocalDate startDate,
        LocalDate endDate) {
}
