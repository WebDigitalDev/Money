BEGIN;

ALTER TABLE money2_metas_financeiras
    ADD COLUMN IF NOT EXISTS repetir_frequencia BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS meta_anterior_id BIGINT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_money2_meta_anterior'
          AND conrelid = 'money2_metas_financeiras'::regclass
    ) THEN
        ALTER TABLE money2_metas_financeiras
            ADD CONSTRAINT fk_money2_meta_anterior
            FOREIGN KEY (meta_anterior_id)
            REFERENCES money2_metas_financeiras(id)
            ON DELETE SET NULL;
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_money2_meta_anterior
    ON money2_metas_financeiras(meta_anterior_id)
    WHERE meta_anterior_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_money2_meta_recorrencia
    ON money2_metas_financeiras(data_fim, id)
    WHERE repetir_frequencia = true;

COMMIT;
