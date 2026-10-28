package com.webdigital.money2.loans;

import java.time.LocalDateTime;

public record LoanHistoryResponse(
        long id,
        String category,
        String operation,
        String description,
        String username,
        LocalDateTime occurredAt) {
}
