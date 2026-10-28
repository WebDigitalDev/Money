-- Tabela mantida por compatibilidade com solicitações criadas por versões
-- anteriores do Money 2. O fluxo atual segue o aplicativo legado: a baixa dos
-- juros e a prorrogação são imediatas e a fila administrativa é só conferência.
CREATE TABLE IF NOT EXISTS money2_interest_roll_requests (
    approval_id bigint PRIMARY KEY REFERENCES aprovacoes(id) ON DELETE CASCADE,
    payment_id bigint NOT NULL,
    installment_id bigint NOT NULL,
    previous_due_date timestamp without time zone,
    new_due_date timestamp without time zone NOT NULL,
    applied boolean NOT NULL DEFAULT false,
    created_at timestamp without time zone NOT NULL DEFAULT now(),
    processed_at timestamp without time zone
);

CREATE INDEX IF NOT EXISTS idx_money2_interest_roll_payment
    ON money2_interest_roll_requests(payment_id);
