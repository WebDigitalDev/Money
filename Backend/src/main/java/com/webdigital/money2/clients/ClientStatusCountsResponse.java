package com.webdigital.money2.clients;

public record ClientStatusCountsResponse(
        long active,
        long withoutLoans,
        long missing) {
}
