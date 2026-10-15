BEGIN;

CREATE TABLE IF NOT EXISTS money2_metas_financeiras_regioes (
    meta_id bigint NOT NULL
        REFERENCES money2_metas_financeiras(id) ON DELETE CASCADE,
    regiao_id bigint NOT NULL
        REFERENCES regioes(id),
    PRIMARY KEY (meta_id, regiao_id)
);

CREATE INDEX IF NOT EXISTS idx_money2_metas_regioes_regiao
    ON money2_metas_financeiras_regioes (regiao_id, meta_id);

INSERT INTO money2_metas_financeiras_regioes (meta_id, regiao_id)
SELECT goal.id, goal.regiao_id
FROM money2_metas_financeiras goal
ON CONFLICT (meta_id, regiao_id) DO NOTHING;

DELETE FROM regiao_usuario access
USING regioes region, users account
WHERE access.regiao_id = region.id
  AND access.usuario_id = account.id
  AND UPPER(TRIM(COALESCE(region.descricao, ''))) = 'TUTORIAL'
  AND UPPER(TRIM(COALESCE(account.username, ''))) <> 'NAKASAWA';

INSERT INTO regiao_usuario (usuario_id, regiao_id, dtcad, dtalter)
SELECT account.id, region.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM users account
CROSS JOIN regioes region
WHERE UPPER(TRIM(COALESCE(account.username, ''))) = 'NAKASAWA'
  AND UPPER(TRIM(COALESCE(region.descricao, ''))) = 'TUTORIAL'
  AND NOT EXISTS (
      SELECT 1
      FROM regiao_usuario access
      WHERE access.usuario_id = account.id
        AND access.regiao_id = region.id
  );

COMMIT;
