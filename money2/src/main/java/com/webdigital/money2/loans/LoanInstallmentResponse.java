package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public record LoanInstallmentResponse(
        long id,
        String number,
        LocalDateTime dueDate,
        LocalDateTime lastPaymentDate,
        BigDecimal amount,
        BigDecimal interestAmount,
        BigDecimal totalAmount,
        BigDecimal paidAmount,
        BigDecimal balanceAmount,
        BigDecimal overdueAmount,
        BigDecimal overdueInterestAmount,
        int overdueDays,
        String status,
        String dueDateNote,
        boolean pending,
        boolean paymentPendingApproval,
        List<LoanPaymentResponse> payments) {
}
