package com.webdigital.money2.clients;

public record ClientSummaryResponse(
        long id,
        String name,
        String document,
        String primaryPhone,
        long regionId,
        String regionName,
        ClientStatus status) {
}
