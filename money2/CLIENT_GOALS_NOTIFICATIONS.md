# Metas de clientes e notificações

## Metas

Os três indicadores são armazenados junto das metas existentes, com regiões e
períodos inclusivos. O endpoint continua `/api/v2/financial-goals`.

- `CLIENTES_ATIVOS`: quantidade de clientes cujo primeiro empréstimo aprovado,
  não cancelado, ocorreu no período. Empréstimos posteriores não contam novamente.
- `CLIENTES_EM_DIA`: percentual mínimo dos clientes com saldo aberto que não têm
  parcelas vencidas e não pagas na data de acompanhamento.
- `CLIENTES_ATRASO`: percentual máximo dos clientes com saldo aberto que têm ao
  menos uma parcela vencida e não paga. Permite objetivo de zero por cento.

A situação é acompanhada até hoje ou o fim do período, o que vier primeiro.
Contam-se clientes distintos; vários contratos não duplicam uma pessoa/cadastro.
O card mostra ativos atuais, em dia, atrasados e novos clientes no período.
Pagamentos reprovados e baixa somente de juros não amortizam o saldo nesse cálculo.
Nenhuma meta percentual é alcançada com zero clientes ativos.

O progresso de atraso representa `(100 - atraso atual) / (100 - limite)`, limitado
a 100% na apresentação. Atinge a meta somente quando o atraso é menor ou igual
ao limite. Para as demais metas, usa-se `alcançado / objetivo`.

Ao encerrar, contagens e resultado são preservados. A reconstrução de uma meta
histórica usa pagamentos até a data final e os dados contratuais atualmente
disponíveis; não recria alterações antigas de região ou renegociações que não
tenham sido historizadas. Recomenda-se cadastrar metas antes de iniciar o período.

A listagem agrupa cálculos financeiros em uma consulta e cálculos de clientes
em outra. As regiões do formulário são buscadas somente quando necessário.
O Flutter reutiliza cache por usuário e revalida ao abrir a página.
O dashboard inclui metas financeiras e de clientes em andamento, respeitando
as regiões selecionadas e as permissões de acesso.

## Notificações sem Firebase

O servidor coleta PIX confirmados/processados a cada 30 segundos e verifica metas
a cada 2 minutos. Eventos têm chaves únicas para não repetir o mesmo PIX/meta.
O app consulta os eventos habilitados a cada 20 segundos. Alertas são desligados
por padrão; ao habilitar, solicita permissão ao sistema/navegador.

- `GET /api/v2/notifications`: histórico das últimas 24 horas.
- `GET/PUT /api/v2/notifications/preferences`: compatibilidade com versões anteriores.

A partir de 1.0.28, a ativação é salva localmente por usuário e instalação
(SharedPreferences), independentemente das preferências antigas do servidor.
Novo aparelho/navegador começa desativado. Sair e entrar na mesma instalação
preserva a escolha; limpar os dados locais a remove. Datas locais de ativação
impedem alertas retroativos. O app não consulta/grava preferências na API.

O histórico independe de os alertas estarem habilitados. Eventos anteriores à
ativação não disparam alertas retroativos. O backend exige acesso a todas as
regiões de um evento agregado de meta. O histórico expira no servidor e na tela;
as chaves dos eventos permanecem armazenadas para deduplicação.

O próprio aplicativo exibe notificação local no dispositivo e toast. **Não é push
remoto**: com o aplicativo suspenso/encerrado, consultas podem parar. Ao reabrir,
o histórico disponível é carregado, sem disparar todos os avisos antigos.
Entrega com app fechado exigiria APNs no iOS e uma solução de transporte em
segundo plano no Android. Não há Firebase nem chaves de serviços externos.

## Aplicação e teste

1. Fazer backup do JAR e das tabelas de metas.
2. Executar `deploy/postgresql17-client-goals-notifications.sql` como manutenção.
3. Publicar somente o backend e executar `deploy/smoke-goals-notifications.sh`.
4. Flutter: `flutter pub get` e `flutter run --dart-define=MONEY_API_BASE_URL=https://moneyapp.site`.
   Reiniciar a execução, pois há um novo plugin nativo; hot reload não o registra.
5. Habilitar cada switch e testar com um PIX real autorizado/ambiente de teste.

O sino abre Notificações. O ícone à esquerda abre Conferências apenas para os
usuários que já tinham essa permissão. Notificações usa a navegação principal,
com menu lateral, barra inferior no celular e botão Voltar no rodapé.
