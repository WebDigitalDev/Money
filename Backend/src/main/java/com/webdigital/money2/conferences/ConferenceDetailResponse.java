package com.webdigital.money2.conferences;

import java.math.BigDecimal;
import java.time.LocalDate;

public record ConferenceDetailResponse(
        Long approvalId,
        Long paymentId,
        Long installmentId,
        String installment,
        LocalDate dueDate,
        BigDecimal amount,
        BigDecimal installmentAmount,
        BigDecimal interestAmount,
        BigDecimal totalAmount,
        String description,
        String dueDateObservation) {
}
