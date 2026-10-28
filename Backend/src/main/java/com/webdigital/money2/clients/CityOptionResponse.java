package com.webdigital.money2.clients;

public record CityOptionResponse(
        long id,
        Long ibgeCode,
        String name,
        String state,
        String displayName) {
}
