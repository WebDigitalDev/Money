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

-- Cálculo interno da cadeia. Ele não é mais exposto pela API como um segundo
-- campo: o resultado é incorporado ao Lucro do último contrato.
CREATE OR REPLACE FUNCTION public.calcular_lucro_acumulado(p_emprestimo_id bigint)
RETURNS double precision
LANGUAGE sql
STABLE
AS $function$
    WITH RECURSIVE cadeia(emprestimo_id) AS (
        SELECT p_emprestimo_id
        UNION
        SELECT r.emp_id_origem
        FROM cadeia c
        JOIN public.refinanciamentos r
          ON r.emp_id_destino = c.emprestimo_id
    ), contexto AS (
        SELECT
            EXISTS (
                SELECT 1
                FROM public.refinanciamentos r
                WHERE r.emp_id_destino = p_emprestimo_id
            ) AS possui_origem,
            NOT EXISTS (
                SELECT 1
                FROM public.refinanciamentos r
                WHERE r.emp_id_origem = p_emprestimo_id
            ) AS ultimo_da_cadeia
    ), pagamentos_cadeia AS (
        SELECT COALESCE(SUM(pg.valor), 0) AS total_pago
        FROM cadeia c
        JOIN public.parcelas p ON p.emprestimo_id = c.emprestimo_id
        JOIN public.pagamentos pg ON pg.parcela_id = p.id
        WHERE COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
    ), capital_raiz AS (
        SELECT COALESCE(SUM(e.valor_emprestado), 0) AS total_capital
        FROM cadeia c
        JOIN public.emprestimo e ON e.id = c.emprestimo_id
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.refinanciamentos r
            WHERE r.emp_id_destino = c.emprestimo_id
        )
    ), capital_renovacoes AS (
        SELECT COALESCE(SUM(GREATEST(
            COALESCE(destino.valor_emprestado, 0) - COALESCE(r.valor_devedor, 0),
            0
        )), 0) AS total_capital
        FROM public.refinanciamentos r
        JOIN cadeia origem_c ON origem_c.emprestimo_id = r.emp_id_origem
        JOIN cadeia destino_c ON destino_c.emprestimo_id = r.emp_id_destino
        JOIN public.emprestimo origem ON origem.id = r.emp_id_origem
        JOIN public.emprestimo destino ON destino.id = r.emp_id_destino
        WHERE COALESCE(origem.renovacao, false) = true
    )
    SELECT CASE
        WHEN contexto.possui_origem AND contexto.ultimo_da_cadeia THEN
            GREATEST(
                pagamentos_cadeia.total_pago
                - capital_raiz.total_capital
                - capital_renovacoes.total_capital,
                0
            )
        ELSE NULL::double precision
    END
    FROM contexto
    CROSS JOIN pagamentos_cadeia
    CROSS JOIN capital_raiz
    CROSS JOIN capital_renovacoes;
$function$;

CREATE OR REPLACE FUNCTION public.calcular_lucro_fluxo(p_emprestimo_id bigint)
RETURNS double precision
LANGUAGE sql
STABLE
AS $function$
    SELECT GREATEST(COALESCE(
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM public.refinanciamentos r
                WHERE r.emp_id_origem = p_emprestimo_id
            ) THEN 0
            WHEN EXISTS (
                SELECT 1
                FROM public.refinanciamentos r
                WHERE r.emp_id_destino = p_emprestimo_id
            ) THEN public.calcular_lucro_acumulado(p_emprestimo_id)
            ELSE public.calcular_lucro_realizado(p_emprestimo_id)
        END,
        0
    ), 0);
$function$;

CREATE OR REPLACE PROCEDURE public.atualizar_valores_emprestimo(p_emprestimo_id integer)
LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF p_emprestimo_id > 0 THEN
        PERFORM set_config('myapp.skip_trigger', '1', true);

        UPDATE public.emprestimo e
        SET status = 2,
            dtalter = NOW()
        WHERE e.id = p_emprestimo_id
          AND e.status = 1
          AND EXISTS (
              SELECT 1
              FROM public.pagamentos pg
              JOIN public.parcelas p ON p.id = pg.parcela_id
              WHERE p.emprestimo_id = e.id
                AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
          );

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
                ELSE GREATEST(COALESCE(public.calcular_lucro_fluxo(e.id), 0), 0)
            END
        WHERE e.id = p_emprestimo_id;

        PERFORM set_config('myapp.skip_trigger', '0', true);
    END IF;
END;
$procedure$;

-- Repara contratos antigos lançados diretamente pelo administrador: após o
-- primeiro pagamento aprovado eles passam a participar da situação normal.
UPDATE public.emprestimo e
SET status = 2,
    dtalter = NOW()
WHERE e.status = 1
  AND EXISTS (
      SELECT 1
      FROM public.pagamentos pg
      JOIN public.parcelas p ON p.id = pg.parcela_id
      WHERE p.emprestimo_id = e.id
        AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
  );

SELECT set_config('myapp.skip_trigger', '1', true);

UPDATE public.emprestimo e
SET vlr_lucro = CASE
        WHEN COALESCE(e.aprovacao_status, 'APROVADO') = 'PENDENTE'
          OR e.status = 3
        THEN 0
        ELSE GREATEST(COALESCE(public.calcular_lucro_fluxo(e.id), 0), 0)
    END,
    dtalter = NOW()
WHERE COALESCE(e.vlr_lucro, 0) IS DISTINCT FROM CASE
        WHEN COALESCE(e.aprovacao_status, 'APROVADO') = 'PENDENTE'
          OR e.status = 3
        THEN 0
        ELSE GREATEST(COALESCE(public.calcular_lucro_fluxo(e.id), 0), 0)
    END;

SELECT set_config('myapp.skip_trigger', '0', true);

COMMIT;
