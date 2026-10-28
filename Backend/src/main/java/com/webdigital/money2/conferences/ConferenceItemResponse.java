package com.webdigital.money2.conferences;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public record ConferenceItemResponse(
        long id,
        String type,
        String action,
        String status,
        Long loanId,
        Long originLoanId,
        Long installmentId,
        Long regionId,
        String regionName,
        String clientName,
        String description,
        BigDecimal amount,
        String requester,
        LocalDateTime createdAt,
        int itemCount,
        List<ConferenceDetailResponse> details) {
}
