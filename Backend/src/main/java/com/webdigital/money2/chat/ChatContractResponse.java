package com.webdigital.money2.chat;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

public record ChatContractResponse(
        long loanId,
        long clientId,
        String clientName,
        long regionId,
        String regionName,
        LocalDate contractDate,
        String paymentType,
        int installmentCount,
        long paidInstallments,
        long openInstallments,
        long overdueInstallments,
        BigDecimal loanedAmount,
        BigDecimal totalAmount,
        BigDecimal receivedAmount,
        BigDecimal receivableAmount,
        BigDecimal profitAmount,
        String status,
        String approvalStatus,
        LocalDate lastPaymentDate,
        BigDecimal lastPaymentAmount,
        String lastPaymentInstallment,
        LocalDate nextDueDate,
        BigDecimal nextDueAmount,
        String nextDueInstallment,
        String createdBy,
        LocalDateTime createdAt,
        String approvedBy,
        LocalDateTime approvedAt,
        String lastChangedBy,
        LocalDateTime lastChangedAt,
        List<ChatContractEventResponse> history) {

    public ChatContractResponse {
        history = history == null ? List.of() : List.copyOf(history);
    }
}
