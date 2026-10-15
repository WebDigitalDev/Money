package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDate;

public record LoanUpdateRequest(
        LocalDate contractDate,
        LocalDate firstDueDate,
        Integer installmentCount,
        String notes,
        String paymentType,
        BigDecimal loanedAmount,
        BigDecimal discountAmount,
        BigDecimal negotiatedAmount,
        BigDecimal interestAmount,
        BigDecimal lateFeeAmount,
        String collateral,
        String clientOwner,
        Boolean missing) {
}
