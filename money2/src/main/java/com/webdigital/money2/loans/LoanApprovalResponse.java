package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record LoanApprovalResponse(
        long id,
        String type,
        String action,
        String status,
        String description,
        BigDecimal amount,
        String requester,
        String approver,
        String rejectionReason,
        LocalDateTime createdAt,
        LocalDateTime decidedAt) {
}
