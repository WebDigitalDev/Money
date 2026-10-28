package com.webdigital.money2.clients;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.time.LocalDate;

public record ClientRequest(
        @NotBlank(message = "Informe o nome do cliente.") String name,
        String legalName,
        String document,
        String email,
        String type,
        String stateRegistration,
        LocalDate birthDate,
        String mobilePhone,
        String phone,
        String secondaryPhone,
        String homepage,
        Long postalCode,
        Long cityId,
        String address,
        String number,
        String complement,
        String neighborhood,
        String collector,
        String googleMapsLink,
        Double latitude,
        Double longitude,
        Double businessLatitude,
        Double businessLongitude,
        @NotNull(message = "Informe a região do cliente.")
        @Positive(message = "Informe uma região válida.") Long regionId,
        String notes,
        String business,
        String facebook,
        String instagram) {
}
