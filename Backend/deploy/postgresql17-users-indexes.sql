CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_first_name_trgm
    ON users USING gin (lower(coalesce(first_name, '')) gin_trgm_ops);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_last_name_trgm
    ON users USING gin (lower(coalesce(last_name, '')) gin_trgm_ops);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_username_trgm
    ON users USING gin (lower(username) gin_trgm_ops);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email_trgm
    ON users USING gin (lower(coalesce(email, '')) gin_trgm_ops);

-- Consultas resumidas de regiões do Money 2. Estes índices existem somente
-- no PostgreSQL 17 e não alteram o banco usado pelo aplicativo antigo.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_pagamentos_data_parcela
    ON pagamentos (data, parcela_id) INCLUDE (valor);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_parcelas_vencimento_pendente
    ON parcelas (vencimento, emprestimo_id)
    INCLUDE (id, valor, valor_juros)
    WHERE pendente = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_emprestimo_data_cliente
    ON emprestimo (data, cliente_id)
    INCLUDE (valor_emprestado, status);

-- Listagem e pesquisa de clientes do Money 2. Mantidos somente na réplica
-- PostgreSQL 17 para não gerar custo de escrita no aplicativo legado.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_cliente_nome_trgm
    ON cliente USING gin (lower(coalesce(nome, '')) gin_trgm_ops)
    WHERE ativo = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_cliente_razao_trgm
    ON cliente USING gin (lower(coalesce(razao, '')) gin_trgm_ops)
    WHERE ativo = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_cliente_documento_trgm
    ON cliente USING gin (lower(coalesce(cgc_cpf, '')) gin_trgm_ops)
    WHERE ativo = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_cliente_telefone_trgm
    ON cliente USING gin (lower(coalesce(celular, '') || ' ' || coalesce(telefone, '')) gin_trgm_ops)
    WHERE ativo = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_emprestimo_cliente_aberto
    ON emprestimo (cliente_id, status)
    INCLUDE (aprovacao_status, refinanciado, renovacao, desaparecido)
    WHERE status <> 3;
