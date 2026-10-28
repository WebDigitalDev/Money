package com.webdigital.money2.users;

import java.util.List;
import java.time.LocalDate;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface RegionRepository extends JpaRepository<Region, Long> {

    List<Region> findAllByOrderByDescriptionAsc();

    @Query("""
            select r from Region r
            where upper(trim(coalesce(r.description, ''))) = 'TUTORIAL'
            order by r.id
            """)
    List<Region> findTutorialRegions();

    @Query("""
            select r from Region r
            where r.id in (
                select ur.regionId from UserRegion ur where ur.userId = :userId
            )
            order by lower(coalesce(r.description, '')), r.id
            """)
    List<Region> findAccessibleByUserId(@Param("userId") Long userId);

    @Query("""
            select count(r) > 0 from Region r
            where r.id = :regionId
              and r.id in (
                  select ur.regionId from UserRegion ur where ur.userId = :userId
              )
            """)
    boolean isAccessible(
            @Param("regionId") Long regionId,
            @Param("userId") Long userId);

    @Query(value = """
            WITH periodo AS (
                SELECT
                    CAST(:startDate AS date) AS data_inicial,
                    CAST(:endDate AS date) AS data_final
            ),
            regioes_usuario AS (
                SELECT DISTINCT ur.regiao_id
                FROM regiao_usuario ur
                WHERE ur.usuario_id = :userId
                  AND ur.regiao_id IS NOT NULL
            ),
            emprestimos_permitidos AS MATERIALIZED (
                SELECT
                    e.id,
                    c.regiao_id,
                    e.status,
                    e.refinanciado,
                    e.renovacao,
                    e.desaparecido,
                    e.aprovacao_status,
                    e.vlr_receber,
                    e.vlr_lucro,
                    e.valor_emprestado,
                    e.data
                FROM emprestimo e
                JOIN cliente c ON c.id = e.cliente_id
                JOIN regioes_usuario ru ON ru.regiao_id = c.regiao_id
            ),
            parcelas_resumo AS MATERIALIZED (
                SELECT
                    pa.emprestimo_id,
                    COUNT(*) FILTER (
                        WHERE pa.pendente = true
                          AND pa.vencimento < CURRENT_DATE
                    ) AS qtd_vencidas,
                    COUNT(*) FILTER (
                        WHERE pa.pendente = true
                          AND pa.vencimento >= CURRENT_DATE
                          AND pa.vencimento < CURRENT_DATE + INTERVAL '1 day'
                    ) AS qtd_vence_hoje,
                    COUNT(*) FILTER (
                        WHERE pa.pendente IS DISTINCT FROM false
                    ) AS qtd_pendentes,
                    MIN(pa.vencimento) FILTER (
                        WHERE pa.pendente = true
                          AND pa.vencimento >= CURRENT_DATE
                    ) AS prox_vencimento,
                    MAX(pa.vencimento) AS max_vencimento,
                    COALESCE(SUM(GREATEST(
                        COALESCE(pa.valor, 0) + COALESCE(pa.valor_juros, 0)
                        - COALESCE(pp.valor_pago, 0), 0)
                    ) FILTER (WHERE pa.pendente = true), 0) AS valor_receber_calculado,
                    COALESCE(SUM(GREATEST(
                        COALESCE(pa.valor, 0) - COALESCE(pp.valor_pago, 0), 0)
                    ) FILTER (WHERE pa.pendente = true), 0) AS valor_receber_sem_juros_calculado
                FROM parcelas pa
                JOIN emprestimos_permitidos ep ON ep.id = pa.emprestimo_id
                LEFT JOIN LATERAL (
                    SELECT SUM(pg.valor) AS valor_pago
                    FROM pagamentos pg
                    WHERE pg.parcela_id = pa.id
                      AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                      AND COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                ) pp ON true
                GROUP BY pa.emprestimo_id
            ),
            status_base AS MATERIALIZED (
                SELECT
                    ep.*,
                    pr.prox_vencimento,
                    pr.max_vencimento,
                    pr.valor_receber_calculado,
                    pr.valor_receber_sem_juros_calculado,
                    CASE
                        WHEN COALESCE(ep.aprovacao_status, 'APROVADO') = 'PENDENTE'
                            THEN 'Pendente Aprovação'
                        WHEN ep.status = 3 THEN 'Cancelado'
                        WHEN ep.refinanciado = true THEN 'Refinanciado'
                        WHEN ep.renovacao = true THEN 'Renov/Abat'
                        WHEN ep.status = 1 THEN 'Lançamento'
                        WHEN ep.desaparecido = true THEN 'Desaparecido'
                        WHEN COALESCE(pr.qtd_vencidas, 0) >= 1 THEN 'Em atraso'
                        WHEN COALESCE(pr.qtd_pendentes, 0) = 0 THEN 'Quitado'
                        WHEN ep.status = 2
                         AND COALESCE(pr.qtd_vence_hoje, 0) >= 1 THEN 'Vence hoje'
                        WHEN ep.status = 2 THEN 'Em dia'
                        ELSE NULL
                    END AS status_descrito
                FROM emprestimos_permitidos ep
                LEFT JOIN parcelas_resumo pr ON pr.emprestimo_id = ep.id
            ),
            ultimo_pagamento_quitado AS MATERIALIZED (
                SELECT pa.emprestimo_id, MAX(pg.data) AS ultimo_pagamento
                FROM status_base sb
                JOIN parcelas pa ON pa.emprestimo_id = sb.id
                JOIN pagamentos pg ON pg.parcela_id = pa.id
                WHERE sb.status_descrito = 'Quitado'
                  AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                  AND COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                GROUP BY pa.emprestimo_id
            ),
            emprestimos_classificados AS MATERIALIZED (
                SELECT
                    sb.*,
                    CASE
                        WHEN sb.status_descrito = 'Quitado'
                            THEN COALESCE(up.ultimo_pagamento, sb.max_vencimento)
                        WHEN sb.status_descrito = 'Renov/Abat'
                            THEN sb.max_vencimento
                        ELSE COALESCE(sb.prox_vencimento, sb.max_vencimento)
                    END AS data_prox_vencimento,
                    CASE
                        WHEN sb.status_descrito = 'Pendente Aprovação' THEN 0
                        ELSE COALESCE(sb.valor_receber_calculado, 0)
                    END AS valor_receber,
                    CASE
                        WHEN sb.status_descrito = 'Pendente Aprovação' THEN 0
                        ELSE COALESCE(sb.valor_receber_sem_juros_calculado, 0)
                    END AS valor_receber_sem_juros,
                    CASE
                        WHEN sb.status_descrito = 'Pendente Aprovação' THEN 0
                        ELSE COALESCE(sb.vlr_lucro, 0)
                    END AS valor_lucro
                FROM status_base sb
                LEFT JOIN ultimo_pagamento_quitado up
                    ON up.emprestimo_id = sb.id
            ),
            resumo AS (
                SELECT
                    ec.regiao_id,
                    COUNT(*) FILTER (WHERE ec.status_descrito IN
                        ('Lançamento', 'Em atraso', 'Em dia', 'Vence hoje')) AS ativos,
                    COUNT(*) FILTER (
                        WHERE ec.status_descrito = 'Desaparecido') AS desaparecidos,
                    COUNT(*) FILTER (WHERE ec.status_descrito NOT IN
                        ('Quitado', 'Renov/Abat', 'Refinanciado', 'Cancelado',
                         'Em atraso', 'Desaparecido')) AS em_dia,
                    COUNT(*) FILTER (
                        WHERE ec.status_descrito = 'Em atraso') AS atrasados,
                    COALESCE(SUM(ec.valor_receber) FILTER (
                        WHERE ec.status_descrito = 'Em atraso'), 0) AS valor_atrasado,
                    COALESCE(SUM(ec.valor_receber_sem_juros), 0) AS valor_receber,
                    COALESCE(SUM(ec.valor_receber) FILTER (
                        WHERE ec.status_descrito = 'Desaparecido'), 0)
                        AS valor_desaparecido,
                    COALESCE(SUM(ec.valor_lucro) FILTER (
                        WHERE ec.status_descrito IN ('Quitado', 'Renov/Abat')
                          AND (p.data_inicial IS NULL
                               OR ec.data_prox_vencimento >= p.data_inicial)
                          AND (p.data_final IS NULL
                               OR ec.data_prox_vencimento < p.data_final + INTERVAL '1 day')
                    ), 0) AS lucro
                FROM emprestimos_classificados ec
                CROSS JOIN periodo p
                GROUP BY ec.regiao_id
            ),
            recebido_periodo AS (
                SELECT
                    c.regiao_id,
                    COALESCE(SUM(pg.valor), 0) AS recebido
                FROM pagamentos pg
                JOIN parcelas pa ON pa.id = pg.parcela_id
                JOIN emprestimo e ON e.id = pa.emprestimo_id
                JOIN cliente c ON c.id = e.cliente_id
                JOIN regioes_usuario ru ON ru.regiao_id = c.regiao_id
                CROSS JOIN periodo p
                WHERE (p.data_inicial IS NULL OR pg.data >= p.data_inicial)
                  AND (p.data_final IS NULL
                       OR pg.data < p.data_final + INTERVAL '1 day')
                  AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                GROUP BY c.regiao_id
            ),
            pagamentos_por_parcela AS (
                SELECT pg.parcela_id, SUM(pg.valor) AS valor_pago
                FROM pagamentos pg
                JOIN parcelas pa ON pa.id = pg.parcela_id
                JOIN emprestimo e ON e.id = pa.emprestimo_id
                WHERE pa.vencimento >= CURRENT_DATE
                  AND pa.vencimento < CURRENT_DATE + INTERVAL '1 day'
                  AND COALESCE(pg.aprovacao_status, 'APROVADO') = 'APROVADO'
                  AND COALESCE(pg.tipo, 'NORMAL') <> 'JUROS_ROLAGEM'
                GROUP BY pg.parcela_id
            ),
            vencendo_hoje AS (
                SELECT
                    c.regiao_id,
                    COALESCE(SUM(
                        (COALESCE(pa.valor, 0) + COALESCE(pa.valor_juros, 0))
                        - COALESCE(pp.valor_pago, 0)), 0) AS vencendo_hoje
                FROM parcelas pa
                JOIN emprestimo e ON e.id = pa.emprestimo_id
                JOIN cliente c ON c.id = e.cliente_id
                JOIN regioes_usuario ru ON ru.regiao_id = c.regiao_id
                LEFT JOIN pagamentos_por_parcela pp ON pp.parcela_id = pa.id
                WHERE pa.pendente = true
                  AND pa.vencimento >= CURRENT_DATE
                  AND pa.vencimento < CURRENT_DATE + INTERVAL '1 day'
                  AND e.status <> 3
                  AND COALESCE(e.refinanciado, false) = false
                GROUP BY c.regiao_id
            ),
            emprestado_periodo AS (
                SELECT
                    c.regiao_id,
                    COALESCE(SUM(e.valor_emprestado), 0) AS emprestado
                FROM emprestimo e
                JOIN cliente c ON c.id = e.cliente_id
                JOIN regioes_usuario ru ON ru.regiao_id = c.regiao_id
                CROSS JOIN periodo p
                WHERE (p.data_inicial IS NULL OR e.data >= p.data_inicial)
                  AND (p.data_final IS NULL
                       OR e.data < p.data_final + INTERVAL '1 day')
                  AND e.status <> 3
                GROUP BY c.regiao_id
            )
            SELECT
                r.id,
                r.descricao,
                r.responsaveis,
                COALESCE(res.ativos, 0),
                COALESCE(res.desaparecidos, 0),
                COALESCE(res.em_dia, 0),
                COALESCE(res.atrasados, 0),
                COALESCE(res.valor_atrasado, 0),
                COALESCE(rec.recebido, 0),
                COALESCE(hoje.vencendo_hoje, 0),
                COALESCE(res.valor_receber, 0),
                COALESCE(res.valor_desaparecido, 0),
                COALESCE(res.lucro, 0),
                COALESCE(emp.emprestado, 0)
            FROM regioes r
            JOIN regioes_usuario ru ON ru.regiao_id = r.id
            LEFT JOIN resumo res ON res.regiao_id = r.id
            LEFT JOIN recebido_periodo rec ON rec.regiao_id = r.id
            LEFT JOIN vencendo_hoje hoje ON hoje.regiao_id = r.id
            LEFT JOIN emprestado_periodo emp ON emp.regiao_id = r.id
            ORDER BY lower(COALESCE(r.descricao, '')), r.id
            """, nativeQuery = true)
    List<Object[]> findSummaries(
            @Param("userId") Long userId,
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate);

    @Query(value = """
            SELECT
                (SELECT COUNT(*) FROM cliente WHERE regiao_id = :regionId)
              + (SELECT COUNT(*) FROM conta_bancaria_configuracao WHERE regiao_id = :regionId)
              + (SELECT COUNT(*) FROM conta_bancaria_regiao WHERE regiao_id = :regionId)
              + (SELECT COUNT(*) FROM regiao_cliente WHERE regiao_id = :regionId)
              + (SELECT COUNT(*) FROM whatsapp_dispositivo_regioes WHERE regiao_id = :regionId)
            """, nativeQuery = true)
    long countBusinessReferences(@Param("regionId") Long regionId);
}
