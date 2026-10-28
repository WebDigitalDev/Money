BEGIN;

CREATE TABLE IF NOT EXISTS money2_emprestimo_feedbacks (
    id bigserial PRIMARY KEY,
    emprestimo_id bigint NOT NULL REFERENCES emprestimo(id) ON DELETE CASCADE,
    usuario_id bigint REFERENCES users(id) ON DELETE SET NULL,
    autor_username varchar(255) NOT NULL,
    texto varchar(2000) NOT NULL,
    herdado_de_emprestimo_id bigint REFERENCES emprestimo(id) ON DELETE SET NULL,
    feedback_origem_id bigint,
    dtcad timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_money2_feedback_texto
        CHECK (length(trim(texto)) BETWEEN 1 AND 2000),
    CONSTRAINT uq_money2_feedback_herdado
        UNIQUE (emprestimo_id, feedback_origem_id)
);

CREATE INDEX IF NOT EXISTS idx_money2_feedback_emprestimo_data
    ON money2_emprestimo_feedbacks (emprestimo_id, dtcad DESC, id DESC);

COMMIT;
