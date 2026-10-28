package com.webdigital.money2.chat;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ChatRequest(
        @NotBlank(message = "Digite uma mensagem.")
        @Size(max = 200, message = "A mensagem deve ter no máximo 200 caracteres.")
        String message,
        String mode,
        Long clientId,
        Long regionId,
        @Size(max = 80, message = "A conversa informada é inválida.")
        String conversationId,
        @Size(max = 120, message = "O modelo informado é inválido.")
        String model,
        @Size(max = 40, message = "A velocidade informada é inválida.")
        String serviceTier) {

    public ChatRequest(
            String message,
            String mode,
            Long clientId,
            Long regionId,
            String conversationId) {
        this(message, mode, clientId, regionId, conversationId, null, null);
    }
}
