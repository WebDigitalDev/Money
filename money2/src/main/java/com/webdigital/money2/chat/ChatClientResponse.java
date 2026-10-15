package com.webdigital.money2.chat;

import java.math.BigDecimal;

public record ChatClientResponse(
        Long id,
        String name,
        String document,
        String phone,
        Long regionId,
        String regionName,
        long openLoans,
        BigDecimal loaned,
        BigDecimal received,
        BigDecimal receivable,
        BigDecimal overdue,
        BigDecimal dueToday) {
}
