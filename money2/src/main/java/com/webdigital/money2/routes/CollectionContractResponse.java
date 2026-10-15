package com.webdigital.money2.routes;

import java.math.BigDecimal;
import java.time.LocalDate;

public record CollectionContractResponse(
        long loanId,
        String type,
        BigDecimal totalDebt,
        BigDecimal overdueDebt,
        int overdueDays,
        LocalDate oldestDueDate) {
}
