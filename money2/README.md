# Money API V2

Backend isolado do novo aplicativo Money.

O serviço oferece autenticação compatível com os usuários existentes,
JWT próprio, acesso de leitura e escrita ao PostgreSQL 17, gestão financeira de
empréstimos e integrações isoladas do aplicativo legado. Nenhuma rotina deste
projeto altera o código ou o processo do backend antigo.

## Endpoints disponíveis

- `GET /api/v2/health`
- `GET /api/v2/dashboard` (indicadores, resumo mensal e vencimentos do dia por região)
- `POST /api/v2/auth/signin`
- `GET /api/v2/auth/session`
- `PUT /api/v2/auth/password` (troca da própria senha)
- `GET /api/v2/profile` (perfil e regiões do próprio usuário autenticado)
- `GET /api/v2/users` (somente administradores, busca paginada)
- `GET /api/v2/users/{id}` (somente administradores)
- `POST /api/v2/users` (somente administradores)
- `PUT /api/v2/users/{id}` (somente administradores)
- `PUT /api/v2/users/{id}/password` (somente administradores)
- `GET /api/v2/regions` (resumo financeiro por região, com período e filtros)
- `GET /api/v2/regions/options` (regiões permitidas para o usuário)
- `GET /api/v2/regions/{id}`
- `POST /api/v2/regions`
- `PUT /api/v2/regions/{id}`
- `DELETE /api/v2/regions/{id}` (somente quando não houver dados vinculados)
- `GET /api/v2/clients` (abas todos, ativos, sem empréstimos e desaparecidos)
- `GET /api/v2/clients/export-data` (dados completos da exportação Excel, respeitando a aba e os filtros)
- `GET /api/v2/clients/cities`
- `GET /api/v2/clients/company/{cnpj}` (consulta empresarial com cache)
- `GET/POST/PUT/DELETE /api/v2/clients/{id}`
- `GET /api/v2/clients/{id}/duplicate-regions` (destinos onde o CPF/CNPJ ainda não existe)
- `POST /api/v2/clients/{id}/duplicate` (duplica o cadastro para uma região permitida)
- `GET/POST/PUT/DELETE /api/v2/clients/{id}/contacts`
- `GET/POST/PATCH/DELETE /api/v2/clients/{id}/documents`
- `GET /api/v2/clients/{id}/documents/{documentId}/file`
- `GET /api/v2/loans` (listagem paginada, busca, status, regiões, período e totais)
- `GET /api/v2/loans/export-data` (dados completos da exportação Excel, respeitando os filtros)
- `GET/PUT /api/v2/loans/{id}` (contrato, parcelas, pagamentos e conferências)
- `POST /api/v2/loans/{id}/payments` e operações por parcela
- `POST /api/v2/loans/{id}/interest-roll` (baixa somente dos juros)
- `POST /api/v2/loans/{id}/refinance` e `/renew`
- `POST /api/v2/loans/{id}/closure` e decisão de conferências
- `GET /api/v2/loans/{id}/message/{CONTRATO|DIVIDA}`
- `GET /api/v2/loans/{id}/installments/{parcela}/message/{COBRANCA|ATRASO}`
- `GET /api/v2/reports/history` (histórico paginado por período, múltiplos usuários e regiões)
- `GET /api/v2/reports/history/export-data` (dados completos do histórico filtrado para Excel)
- `GET /api/v2/reports/history/users` (usuários disponíveis no filtro)
- `GET /api/v2/financial-goals` (metas e progresso calculado por região)
- `POST/PUT/DELETE /api/v2/financial-goals` (gestão exclusiva de administradores)
- `GET /api/v2/routes` (rota automática das dívidas vencidas por região)
- `GET /api/v2/routes/{clientId}` (dívida, contratos e histórico de cobranças)
- `POST /api/v2/routes/{clientId}/collections` (registro do cobrador com anexo opcional)
- `GET /api/v2/clients/{clientId}/collections` (histórico no perfil do cliente)
- `GET /api/v2/collections/{collectionId}/file` (anexo da cobrança)
- `GET /api/v2/conferences` (fila administrativa por tipo, região e pesquisa;
  aceita `includeDetails=false` para uma listagem leve)
- `GET /api/v2/conferences/{id}/details` (detalhes carregados sob demanda)
- `POST /api/v2/conferences/{id}/approve|reject` (conferência financeira)
- `GET/POST/DELETE /api/v2/loans/{id}/pix` (Sicredi com mTLS)
- `GET/POST/PUT /api/v2/integrations/banking/accounts` e upload de certificados
- `GET/PUT /api/v2/integrations/whatsapp/config`
- `GET /api/v2/integrations/whatsapp/devices`, sincronização e vínculo de regiões
- `POST /api/v2/integrations/whatsapp/devices/{id}/dispatch`
- `GET/DELETE /api/v2/integrations/whatsapp/logs`
- `POST /api/v2/chat/query` (consultas financeiras programadas com busca vetorial)
- `GET /api/v2/codex/status` (estado da conexão individual com ChatGPT)
- `POST /api/v2/codex/connect` e `DELETE /api/v2/codex/connection`
- `POST /api/v2/codex/query` (conversa com Codex e dados autorizados do Money)

## Chatbot e Qdrant

O PostgreSQL 17 continua sendo a fonte oficial de clientes, contratos,
parcelas, pagamentos, histórico e saldos. Toda mensagem do chat passa pelo
Qdrant. Há dois contextos vetoriais isolados: `money2_clients`, usado somente
depois que o usuário abre “Consultar cliente”, e `money2_financial_context`,
que reconhece intenções financeiras e contratos na conversa geral. Depois da
contextualização semântica, o backend valida o acesso do usuário e recalcula os
valores no PostgreSQL antes de responder.

O endpoint legado `/api/v2/chat/query` continua independente de APIs externas.
O `money2` possui um orquestrador conversacional seguro para consulta de
contratos, criação, aprovação, alterações, último pagamento, saldo, parcelas,
próximo vencimento, vencimentos do dia, atrasos, lucro regional e recomendação
de metas. A pesquisa por cliente não é rota de contingência: ela só é ativada
pelo botão próprio. Cada conversa mantém por até 45 minutos somente os
identificadores do contrato, cliente e região em foco; valores, datas,
permissões e auditoria são consultados novamente no PostgreSQL a cada resposta.
Assim, perguntas de continuação como “quando foi o último pagamento?” preservam
o contrato em foco sem armazenar dados financeiros no cache. Os índices são
reconciliados periodicamente para incluir dados recebidos pela replicação do
aplicativo legado.

O chat com Codex é uma integração experimental e opt-in. Cada usuário conecta
sua própria conta ChatGPT por código de dispositivo e recebe um `CODEX_HOME`
isolado no servidor; credenciais e conversas não são compartilhadas. Shell,
execução de comandos, apps, multiagentes e busca web ficam desativados. Quando
uma resposta depende dos dados do Money, o Codex usa uma única ferramenta
controlada que chama o orquestrador acima, preservando as permissões de região e
os componentes estruturados exibidos pelo aplicativo. A integração é ativada
somente no servidor por `MONEY2_CODEX_ENABLED=true`.

As consultas textuais da tela de usuários podem usar os índices PostgreSQL 17
documentados em `deploy/postgresql17-users-indexes.sql`. Eles aceleram buscas
parciais por nome, usuário e e-mail sem alterar o PostgreSQL 13 legado.

O resumo de regiões calcula os mesmos indicadores do aplicativo legado sem
consultar a view lenta `vw_emprestimos_resumo`. A consulta classifica os
empréstimos a partir das tabelas-base, agrega parcelas e pagamentos uma vez e
usa índices exclusivos do PostgreSQL 17. Valores monetários são normalizados
em duas casas decimais. O campo legado do MaxBot não é mapeado nem alterado
pelo `money2`.

A listagem de clientes preserva a semântica do sistema legado: “Sem
empréstimos” identifica clientes ativos sem empréstimo aprovado em aberto, e
“Desaparecidos” considera o estado atual dos empréstimos. Endereço e demais
dados pessoais completos são retornados apenas no detalhe. Documentos novos
ficam isolados em `money2/data`; arquivos legados são acessados somente para
leitura.

O novo cadastro utiliza um único link do Google Maps. Esse campo existe apenas
no PostgreSQL 17 e é criado por
`deploy/postgresql17-client-maps-link.sql`; as coordenadas legadas continuam
preservadas para compatibilidade e são convertidas em link na interface quando
o cliente ainda não possui o novo valor.

A listagem de empréstimos preserva a classificação, ordenação, cores e
cálculos do aplicativo legado, mas consulta as tabelas-base em uma única
operação paginada. Os totais consideram todo o resultado filtrado, não apenas
a página atual. Os índices exclusivos dessa consulta estão documentados em
`deploy/postgresql17-loans-indexes.sql`.

O histórico de alterações restringe primeiro o período por índice, evita uma
contagem total custosa e entrega páginas incrementais de 250 registros,
preservando o conteúdo e a ordem do aplicativo legado. A consulta aplica os
acessos por região do usuário e a tela inicia sempre nos últimos 30 dias. A
exportação reutiliza os mesmos filtros e colunas do arquivo histórico antigo.

No cadastro e na edição de um contrato comum, o usuário informa o valor
emprestado e o “Valor Juros”, preservando a regra histórica
`total = emprestado + juros - desconto`. Contratos originados por negociação
são identificados pela tabela `refinanciamentos`: no refinanciamento, o saldo
real das parcelas pendentes recebe o valor negociado de juros e o total passa
a ser o principal do novo contrato; na renovação, o usuário informa o novo
valor a emprestar, os juros permanecem separados e o valor líquido entregue ao
cliente corresponde ao novo principal menos a dívida anterior. O saldo anterior
é sempre recalculado pelo backend a partir das parcelas e pagamentos aprovados.
Administradores concluem empréstimos, refinanciamentos e renovações diretamente;
os demais usuários continuam seguindo o fluxo de aprovação.

A operação “baixar somente os juros” preserva a regra financeira histórica:
o pagamento é registrado imediatamente como `JUROS_ROLAGEM`, entra no valor
recebido, não amortiza parcela nem saldo devedor e prorroga o primeiro
vencimento pendente conforme o tipo de cobrança. A operação pode ser repetida
nos vencimentos seguintes. A fila administrativa registra somente a
conferência do lançamento; aprovar ou indeferir a conferência não desfaz o
recebimento nem a prorrogação já realizados.

As credenciais bancárias e do WhatsApp são administradas somente por usuários
administradores. Certificados e chaves bancárias são validados como par mTLS
antes de serem aceitos. Disparos coletivos exigem confirmação explícita no
aplicativo e o serviço registra o resultado individual de cada destinatário.

Todos os segredos são fornecidos pelo arquivo de ambiente do serviço no
servidor e não fazem parte do código-fonte.

O Qdrant é executado como serviço local, ligado somente em `127.0.0.1`, com
chave de API própria. As variáveis `MONEY2_QDRANT_ENABLED`,
`MONEY2_QDRANT_URL`, `MONEY2_QDRANT_API_KEY` e
`MONEY2_QDRANT_COLLECTION` são definidas apenas no servidor. A coleção
financeira usa `MONEY2_QDRANT_FINANCIAL_COLLECTION` quando informado, com
`money2_financial_context` como nome padrão.

## Publicação segura dos fontes

Use `deploy/sync-source.sh usuario@servidor` para sincronizar o código. O
script protege as pastas exclusivas do servidor (`app`, `backups`, `config`,
`data` e `target`) mesmo quando arquivos obsoletos dos fontes são removidos.

## Banco de produção

O PostgreSQL 17, na porta local `5433`, é o banco oficial e exclusivo do
`money2`. O aplicativo legado, o PostgreSQL 13 e a replicação lógica foram
desativados na migração definitiva de 23/08/2026, depois da confirmação de que
o assinante havia recebido todo o WAL pendente.

As sequências do PostgreSQL 17 seguem novamente a numeração normal dos dados
migrados. A faixa temporária a partir de 1 bilhão não deve ser restaurada. Os
IDs altos mantidos para a região `TUTORIAL WEBDIGITAL`, seu cliente e outros
registros administrativos não determinam o próximo valor das sequências.
