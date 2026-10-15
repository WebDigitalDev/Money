package com.webdigital.money2.clients;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public record ClientDuplicateRequest(
        @NotNull(message = "Selecione a região de destino.")
        @Positive(message = "Selecione uma região válida.")
        Long regionId) {
}
