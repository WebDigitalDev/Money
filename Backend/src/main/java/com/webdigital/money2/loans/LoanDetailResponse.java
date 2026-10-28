package com.webdigital.money2.loans;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

public record LoanDetailResponse(
        long id,
        long clientId,
        String clientName,
        long regionId,
        String regionName,
        LocalDateTime contractDate,
        LocalDateTime firstDueDate,
        int installmentCount,
        String notes,
        String paymentTypeCode,
        String paymentType,
        BigDecimal loanedAmount,
        BigDecimal originalLoanAmount,
        BigDecimal discountAmount,
        BigDecimal interestAmount,
        BigDecimal negotiatedAmount,
        boolean negotiatedOrigin,
        BigDecimal lateFeeAmount,
        BigDecimal totalAmount,
        BigDecimal installmentAmount,
        BigDecimal receivedAmount,
        BigDecimal receivableAmount,
        BigDecimal profitAmount,
        String collateral,
        String clientOwner,
        boolean missing,
        boolean active,
        boolean refinanced,
        boolean renewed,
        int numericStatus,
        String status,
        String approvalStatus,
        boolean operationLocked,
        String lockReason,
        boolean canEdit,
        boolean administrator,
        List<LoanInstallmentResponse> installments,
        List<LoanHistoryResponse> history,
        List<LoanApprovalResponse> approvals,
        List<LoanOriginResponse> origins) {
}
