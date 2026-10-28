package com.webdigital.money2.users;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.Set;

public record UserUpdateRequest(
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
        boolean enabled,
        boolean locked,
        boolean expired,
        boolean credentialsExpired,
        boolean forcePasswordChange,
        boolean administrator,
        boolean canEdit,
        Boolean collector,
        Boolean showTutorial,
        Set<Long> regionIds) {
}
