package com.webdigital.money2.regions;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RegionRequest(
        @NotBlank(message = "Informe a descrição da região.")
        @Size(max = 255, message = "A descrição deve ter no máximo 255 caracteres.")
        String description,

        @Size(max = 255, message = "Os responsáveis devem ter no máximo 255 caracteres.")
        String responsiblePeople,

        @Size(max = 255, message = "A região pai deve ter no máximo 255 caracteres.")
        String parentDescription,

        @Size(max = 4000, message = "A mensagem de empréstimo deve ter no máximo 4000 caracteres.")
        String loanMessage,

        @Size(max = 4000, message = "A mensagem de refinanciamento deve ter no máximo 4000 caracteres.")
        String refinancedLoanMessage,

        @Size(max = 4000, message = "A mensagem de cobrança deve ter no máximo 4000 caracteres.")
        String collectionMessage,

        @Size(max = 4000, message = "A mensagem de cobrança com link deve ter no máximo 4000 caracteres.")
        String collectionLinkMessage,

        @Size(max = 4000, message = "A mensagem de atraso deve ter no máximo 4000 caracteres.")
        String overdueMessage,

        boolean clientOwnerRequired) {
}
