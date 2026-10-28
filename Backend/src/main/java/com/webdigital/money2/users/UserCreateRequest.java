package com.webdigital.money2.users;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.Set;

public record UserCreateRequest(
        @NotBlank(message = "Informe o primeiro nome.")
        @Size(max = 255, message = "O primeiro nome deve ter no máximo 255 caracteres.")
        String firstName,
        @Size(max = 255, message = "O sobrenome deve ter no máximo 255 caracteres.")
        String lastName,
        @NotBlank(message = "Informe o usuário.")
        @Size(max = 255, message = "O usuário deve ter no máximo 255 caracteres.")
        String username,
        @Email(message = "Informe um e-mail válido.")
        @Size(max = 255, message = "O e-mail deve ter no máximo 255 caracteres.")
        String email,
        @NotBlank(message = "Informe a senha inicial.")
        @Pattern(regexp = "\\d+", message = "A senha deve conter somente números.")
        @Size(max = 64, message = "A senha deve ter no máximo 64 números.")
        String password,
        boolean enabled,
        boolean forcePasswordChange,
        boolean administrator,
        boolean canEdit,
        Boolean collector,
        Set<Long> regionIds) {
}
