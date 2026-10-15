package com.webdigital.money2.users;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record ChangePasswordRequest(
        @NotBlank(message = "Informe a nova senha.")
        @Pattern(regexp = "\\d+", message = "A senha deve conter somente números.")
        @Size(max = 64, message = "A senha deve ter no máximo 64 números.")
        String password) {
}
