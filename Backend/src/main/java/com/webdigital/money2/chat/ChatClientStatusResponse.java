package com.webdigital.money2.chat;

public record ChatClientStatusResponse(
        long activeCount,
        long withoutLoansCount,
        long missingCount) {
}
