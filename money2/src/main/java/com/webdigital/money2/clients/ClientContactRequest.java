package com.webdigital.money2.clients;

import jakarta.validation.constraints.NotBlank;

public record ClientContactRequest(
        @NotBlank(message = "Informe o nome do contato.") String name,
        String phone,
        String type,
        String notes) {
}
