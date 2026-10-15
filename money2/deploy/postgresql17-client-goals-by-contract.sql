BEGIN;

-- Client goals used to persist one row per client. Clear only those snapshots so
-- the backend can rebuild closed goals with the contract-based Regions rule.
UPDATE money2_metas_financeiras
SET clientes_ativos_final = NULL,
    clientes_em_dia_final = NULL,
    clientes_atraso_final = NULL,
    clientes_novos_final = NULL,
    valor_alcancado_final = NULL,
    finalizada_em = NULL
WHERE tipo IN ('CLIENTES_ATIVOS', 'CLIENTES_EM_DIA', 'CLIENTES_ATRASO')
  AND (
      clientes_ativos_final IS NOT NULL
      OR clientes_em_dia_final IS NOT NULL
      OR clientes_atraso_final IS NOT NULL
      OR clientes_novos_final IS NOT NULL
      OR valor_alcancado_final IS NOT NULL
  );

COMMIT;
