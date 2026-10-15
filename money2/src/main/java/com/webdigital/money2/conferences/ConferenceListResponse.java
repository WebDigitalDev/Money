package com.webdigital.money2.conferences;

import java.util.List;
import java.util.Map;

public record ConferenceListResponse(
        List<ConferenceItemResponse> items,
        long total,
        int page,
        int size,
        Map<String, Long> counts) {
}
