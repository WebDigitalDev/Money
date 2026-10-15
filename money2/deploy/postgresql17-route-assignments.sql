BEGIN;

CREATE TABLE IF NOT EXISTS money2_rotas_cobranca (
    id bigserial PRIMARY KEY,
    cliente_id bigint NOT NULL UNIQUE REFERENCES cliente(id),
    regiao_id bigint NOT NULL REFERENCES regioes(id),
    cobrador_id bigint NOT NULL REFERENCES users(id),
    criado_por_id bigint NOT NULL REFERENCES users(id),
    dtcad timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    dtalter timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_money2_rotas_cobrador_data
    ON money2_rotas_cobranca (cobrador_id, dtalter DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_money2_rotas_regiao_data
    ON money2_rotas_cobranca (regiao_id, dtalter DESC, id DESC);

COMMIT;
