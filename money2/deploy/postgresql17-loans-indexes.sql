-- Índices exclusivos do PostgreSQL 17 para a listagem paginada de
-- empréstimos do Money 2. Não são aplicados no PostgreSQL 13 legado.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_regiao_usuario_usuario_regiao
    ON regiao_usuario (usuario_id, regiao_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_emprestimo_lista_cliente
    ON emprestimo (cliente_id, id)
    INCLUDE (status, aprovacao_status, refinanciado, renovacao, desaparecido,
             tipo, vlr_receber, vlr_recebido, valor_emprestado, vlr_lucro, data);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_parcelas_emprestimo_resumo
    ON parcelas (emprestimo_id)
    INCLUDE (id, pendente, vencimento);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_pagamentos_parcela_data
    ON pagamentos (parcela_id, data DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_refinanciamentos_destino
    ON refinanciamentos (emp_id_destino);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_money2_refinanciamentos_origem
    ON refinanciamentos (emp_id_origem);
