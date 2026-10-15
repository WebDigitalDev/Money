package com.webdigital.money2.loans;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record LoanFeedbackRequest(
        @NotBlank(message = "Digite o feedback.")
        @Size(max = 2000, message = "O feedback deve ter no máximo 2.000 caracteres.")
        String text) {
}
