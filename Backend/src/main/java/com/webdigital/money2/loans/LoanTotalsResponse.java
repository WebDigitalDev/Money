package com.webdigital.money2.loans;

import java.math.BigDecimal;

public record LoanTotalsResponse(
        long loans,
        BigDecimal receivableAmount,
        BigDecimal receivedAmount,
        BigDecimal profitAmount,
        BigDecimal loanedAmount) {
}
