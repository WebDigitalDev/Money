package com.webdigital.money2.loans;

import java.time.LocalDateTime;

public record LoanFeedbackResponse(
        long id,
        long loanId,
        String text,
        Long authorId,
        String authorName,
        LocalDateTime createdAt,
        Long inheritedFromLoanId) {

    public boolean inherited() {
        return inheritedFromLoanId != null;
    }
}
