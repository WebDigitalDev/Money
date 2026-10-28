package com.webdigital.money2.auth;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record PasswordChangeRequest(
        @NotBlank(message = "Informe a nova senha.")
        @Pattern(regexp = "\\d+", message = "A senha deve conter somente números.")
        @Size(min = 4, max = 64, message = "A senha deve ter entre 4 e 64 números.")
        String password) {
}
