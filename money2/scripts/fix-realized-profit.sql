BEGIN;

CREATE OR REPLACE FUNCTION public.calcular_lucro_realizado(p_emprestimo_id bigint)
RETURNS double precision
LANGUAGE sql
STABLE
AS $function$
    SELECT GREATEST(
        COALESCE((
            SELECT SUM(pg.valor)
            FROM public.pagamentos pg
            JOIN public.parcelas p ON p.id = pg.parcela_id
            WHERE p.emprestimo_id = e.id
              AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
        ), 0) - COALESCE(e.valor_emprestado, 0),
        0
    )
    FROM public.emprestimo e
    WHERE e.id = p_emprestimo_id;
$function$;

CREATE OR REPLACE PROCEDURE public.atualizar_valores_emprestimo(p_emprestimo_id integer)
LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF p_emprestimo_id > 0 THEN
        PERFORM set_config('myapp.skip_trigger', '1', true);

        UPDATE public.emprestimo e
        SET vlr_receber = CASE
                WHEN COALESCE(e.aprovacao_status, 'APROVADO') = 'PENDENTE'
                  OR e.status IN (1, 3)
                  OR COALESCE(e.refinanciado, false)
                  OR COALESCE(e.renovacao, false)
                THEN 0
                ELSE COALESCE((
                    SELECT SUM(GREATEST(
                        COALESCE(p.valor, 0) + COALESCE(p.valor_juros, 0) - COALESCE((
                            SELECT SUM(pg.valor)
                            FROM public.pagamentos pg
                            WHERE pg.parcela_id = p.id
                              AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                              AND COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                        ), 0),
                        0
                    ))
                    FROM public.parcelas p
                    WHERE p.emprestimo_id = e.id
                      AND p.pendente = true
                ), 0)
            END,
            vlr_recebido = COALESCE((
                SELECT SUM(pg.valor)
                FROM public.pagamentos pg
                JOIN public.parcelas p ON p.id = pg.parcela_id
                WHERE p.emprestimo_id = e.id
                  AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
            ), 0),
            vlr_lucro = CASE
                WHEN COALESCE(e.aprovacao_status, 'APROVADO') = 'PENDENTE'
                  OR e.status = 3
                THEN 0
                ELSE public.calcular_lucro_realizado(e.id)
            END
        WHERE e.id = p_emprestimo_id;

        PERFORM set_config('myapp.skip_trigger', '0', true);
    END IF;
END;
$procedure$;

CREATE OR REPLACE VIEW public.vw_emprestimos_lucros AS
WITH pagamentos_por_parcela AS (
    SELECT
        p.id AS parcela_id,
        p.emprestimo_id,
        p.vencimento,
        COALESCE(SUM(pg.valor) FILTER (
            WHERE COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
        ), 0) AS valor_pago
    FROM public.parcelas p
    LEFT JOIN public.pagamentos pg ON pg.parcela_id = p.id
    GROUP BY p.id, p.emprestimo_id, p.vencimento
), evolucao AS (
    SELECT
        e.id,
        e.cliente_id,
        SUM(pp.valor_pago) OVER (
            PARTITION BY e.id
            ORDER BY pp.vencimento, pp.parcela_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) - COALESCE(e.valor_emprestado, 0) AS lucro,
        pp.vencimento,
        c.regiao_id
    FROM public.emprestimo e
    JOIN public.vw_emprestimos ew ON ew.id = e.id
    JOIN public.cliente c ON c.id = e.cliente_id
    JOIN pagamentos_por_parcela pp ON pp.emprestimo_id = e.id
    WHERE ew.status = ANY (ARRAY[
        'Lançamento'::text,
        'Em atraso'::text,
        'Em dia'::text,
        'Vence hoje'::text,
        'Quitado'::text,
        'Renov/Abat'::text,
        'Refinanciado'::text,
        'Desaparecido'::text
    ])
      AND COALESCE(e.aprovacao_status, 'APROVADO') = 'APROVADO'
)
SELECT id, cliente_id, lucro, vencimento, regiao_id
FROM evolucao
WHERE lucro > 0;

CALL public.atualizar_valores_emprestimo(44324);
CALL public.atualizar_valores_emprestimo(45899);

COMMIT;
