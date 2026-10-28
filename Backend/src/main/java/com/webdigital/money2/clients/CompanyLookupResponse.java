package com.webdigital.money2.clients;

public record CompanyLookupResponse(
        String document,
        String legalName,
        String tradeName,
        String stateRegistration,
        String email,
        String primaryPhone,
        String secondaryPhone,
        Long postalCode,
        Long cityIbgeCode,
        String cityName,
        String state,
        String address,
        String number,
        String complement,
        String neighborhood) {
}
