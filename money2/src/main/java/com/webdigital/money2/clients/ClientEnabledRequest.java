package com.webdigital.money2.clients;

import jakarta.validation.constraints.NotNull;

public record ClientEnabledRequest(
        @NotNull(message = "Informe se o cliente deve ficar ativo.") Boolean enabled) {
}
