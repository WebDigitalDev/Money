package com.webdigital.money2.chat;

import java.util.List;

public record FinancialSemanticContext(
        List<Long> contractIds,
        List<String> intents,
        boolean qdrantUsed) {

    public FinancialSemanticContext {
        contractIds = contractIds == null ? List.of() : List.copyOf(contractIds);
        intents = intents == null ? List.of() : List.copyOf(intents);
    }

    public static FinancialSemanticContext empty() {
        return new FinancialSemanticContext(List.of(), List.of(), false);
    }

    public boolean suggests(String intent) {
        return intent != null && intents.contains(intent);
    }
}
