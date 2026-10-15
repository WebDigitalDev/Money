CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_metas_regiao_fim
    ON money2_metas_financeiras (regiao_id, data_fim DESC, id DESC);
