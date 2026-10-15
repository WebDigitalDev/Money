package com.webdigital.money2.regions;

import java.time.LocalDate;
import java.util.List;

public record RegionListResponse(
        List<RegionSummaryResponse> items,
        RegionTotalsResponse totals,
        LocalDate startDate,
        LocalDate endDate) {
}
