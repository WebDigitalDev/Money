package com.webdigital.money2.goals;

public enum FinancialGoalType {
    EMPRESTADO,
    RECEBIDO,
    LUCRO,
    CLIENTES_ATIVOS,
    CLIENTES_EM_DIA,
    CLIENTES_ATRASO;

    public boolean isClient() { return name().startsWith("CLIENTES_"); }
    public boolean isPercentage() { return this == CLIENTES_EM_DIA || this == CLIENTES_ATRASO; }
}
