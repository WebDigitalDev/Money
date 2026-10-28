BEGIN;

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
        SELECT COALESCE(SUM(destino.valor_emprestado), 0) AS total_capital
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

COMMIT;
