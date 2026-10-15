package com.webdigital.money2.chat;

public record IndexedFinancialContract(
        Long id,
        Long regionId,
        String regionName,
        String clientName,
        String paymentType,
        String status) {

    public String searchableText() {
        return String.join(" ",
                "contrato " + id,
                "emprestimo " + id,
                "numero " + id,
                clean(clientName),
                clean(regionName),
                clean(paymentType),
                clean(status),
                "pagamento parcela vencimento saldo historico alteracoes criacao aprovacao");
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
