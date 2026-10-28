BEGIN;

ALTER TABLE whatsapp_dispositivos
    ADD COLUMN IF NOT EXISTS tipo_disparo varchar(40),
    ADD COLUMN IF NOT EXISTS disparo_total integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS disparo_processados integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS disparo_sucessos integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS disparo_erros integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS disparo_ignorados integer NOT NULL DEFAULT 0;

UPDATE whatsapp_dispositivos
SET disparo_total=GREATEST(COALESCE(disparo_total,0),0),
    disparo_processados=GREATEST(COALESCE(disparo_processados,0),0),
    disparo_sucessos=GREATEST(COALESCE(disparo_sucessos,0),0),
    disparo_erros=GREATEST(COALESCE(disparo_erros,0),0),
    disparo_ignorados=GREATEST(COALESCE(disparo_ignorados,0),0);

COMMIT;
