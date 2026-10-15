BEGIN;

-- Valores financeiros legados usam double precision. Toda decisão de quitação
-- deve acontecer na precisão monetária exibida e aceita pelo aplicativo.
CREATE OR REPLACE FUNCTION public.trigger_pagamento_update()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_parcela_id BIGINT := COALESCE(NEW.parcela_id, OLD.parcela_id);
BEGIN
    UPDATE parcelas p
    SET pendente = ROUND(COALESCE((
            SELECT SUM(pg.valor)
            FROM pagamentos pg
            WHERE pg.parcela_id = p.id
              AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
              AND COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
        ), 0)::numeric, 2)
        < ROUND((COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0))::numeric, 2),
        status = NULL,
        dtalter = NOW()
    WHERE p.id = v_parcela_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

-- Corrige parcelas antigas cujo saldo é zero quando expresso em centavos.
WITH changed AS (
    SELECT p.id
    FROM parcelas p
    LEFT JOIN pagamentos pg ON pg.parcela_id = p.id
    WHERE p.pendente = true
    GROUP BY p.id
    HAVING ROUND((COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0))::numeric, 2) > 0
       AND ROUND(COALESCE(SUM(pg.valor) FILTER (
               WHERE COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                 AND COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
           ), 0)::numeric, 2)
           >= ROUND((COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0))::numeric, 2)
)
UPDATE parcelas p
SET pendente = false,
    status = NULL,
    dtalter = NOW()
FROM changed
WHERE p.id = changed.id;

COMMIT;
