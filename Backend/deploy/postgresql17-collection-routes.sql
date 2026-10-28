BEGIN;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS cobrador boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS money2_cobrancas (
    id bigserial PRIMARY KEY,
    cliente_id bigint NOT NULL REFERENCES cliente(id),
    regiao_id bigint NOT NULL REFERENCES regioes(id),
    usuario_id bigint NOT NULL REFERENCES users(id),
    observacao text NOT NULL,
    valor_divida numeric(19, 2) NOT NULL DEFAULT 0,
    dias_atraso integer NOT NULL DEFAULT 0,
    arquivo_nome varchar(512),
    arquivo_disco varchar(255),
    arquivo_tipo varchar(255),
    arquivo_tamanho bigint,
    dtcad timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_money2_cobrancas_observacao
        CHECK (length(trim(observacao)) BETWEEN 1 AND 4000),
    CONSTRAINT chk_money2_cobrancas_valor
        CHECK (valor_divida >= 0),
    CONSTRAINT chk_money2_cobrancas_dias
        CHECK (dias_atraso >= 0)
);

CREATE INDEX IF NOT EXISTS idx_money2_cobrancas_cliente_data
    ON money2_cobrancas (cliente_id, dtcad DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_money2_cobrancas_usuario_data
    ON money2_cobrancas (usuario_id, dtcad DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_money2_cobrancas_regiao_data
    ON money2_cobrancas (regiao_id, dtcad DESC, id DESC);

COMMIT;
