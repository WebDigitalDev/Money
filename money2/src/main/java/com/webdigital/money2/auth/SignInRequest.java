package com.webdigital.money2.auth;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record SignInRequest(
        @NotBlank(message = "Informe o usuário.")
        @Size(max = 100, message = "Usuário inválido.")
        String username,
        @NotBlank(message = "Informe a senha.")
        @Size(max = 200, message = "Senha inválida.")
        String password) {
}

