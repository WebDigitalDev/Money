# Sistema de atualização do Money

## Objetivo

Este documento descreve o sistema de atualização obrigatória implementado no
novo aplicativo Money e o processo de publicação dos instaladores.

O sistema deverá atender às seguintes plataformas:

- Android: download do APK pelo próprio aplicativo e instalação confirmada
  pelo usuário.
- iOS: distribuição Ad Hoc para aparelhos previamente cadastrados pelo UDID.
- Web: detecção de uma nova publicação e recarregamento da página.

O aplicativo antigo `money`, que está em produção, não deve ser modificado.
Toda implementação deverá ocorrer no Flutter local `Money` e, quando
necessário, somente no backend novo `money2`.

## Decisão de distribuição

### Android

O Android será distribuído fora da Google Play. O APK ficará hospedado no
servidor do `money2`.

Para que uma nova versão substitua a instalada, todas as versões deverão usar:

- o mesmo `applicationId`: `com.webdigital.money`;
- a mesma chave de assinatura de produção;
- um `versionCode` sempre maior que o da versão anterior;
- um domínio HTTPS permanente para download.

O Android exige confirmação do usuário para instalar a atualização. A
instalação não poderá ser totalmente silenciosa.

### iOS Ad Hoc

Enrollment ID: 8U7B35LPDX

Team ID de assinatura: 7X26NZDZ6L

O iOS será distribuído por Ad Hoc, sem publicação na App Store.

Condições obrigatórias:

- possuir uma assinatura ativa do Apple Developer Program;
- cadastrar previamente o UDID de cada iPhone;
- gerar um perfil Ad Hoc contendo os aparelhos autorizados;
- assinar o IPA com certificado e perfil válidos;
- manter o mesmo Bundle Identifier e a mesma identidade de assinatura;
- aumentar o número do build em cada atualização.

A Apple permite até 100 iPhones cadastrados por família de produto e por ano
de assinatura. Desativar um aparelho durante o ano não devolve a vaga. A lista
pode ser revisada no início do próximo ano da assinatura.

Se um novo UDID for cadastrado depois que o IPA tiver sido gerado, será
necessário atualizar o perfil Ad Hoc e exportar um novo IPA. O IPA antigo não
passa a reconhecer automaticamente o novo aparelho.

Na primeira instalação, o usuário receberá um link ou QR Code. Depois que o
Money estiver instalado, as próximas versões serão detectadas pelo próprio
aplicativo e o botão `ATUALIZAR` abrirá a instalação da nova versão.

O iOS continuará exigindo a ação e a confirmação do usuário. O download e a
instalação serão controlados pelo sistema operacional; por isso, o Flutter não
terá acesso à porcentagem real do download no iOS.

O aparelho também poderá exigir que o Modo de Desenvolvedor seja ativado para
executar um aplicativo distribuído dessa forma.

### Web

A versão web não baixará APK ou IPA. Quando detectar uma publicação mais nova,
ela exibirá a mesma tela obrigatória e o botão `ATUALIZAR` recarregará a página.

O servidor web deverá entregar o arquivo inicial e o bootstrap com política de
cache adequada, para impedir que o navegador continue carregando uma versão
antiga depois da publicação.

Na publicação rotineira da web, compilar o novo release, validar o pacote,
substituir diretamente a pasta web ativa e atualizar o `releaseId`. Não criar
uma cópia `web.backup-*` a cada versão, para evitar consumo acumulado de disco
no servidor. Se for necessário voltar uma versão, recompilar e publicar o
release desejado.

## Estrutura prevista no servidor

A estrutura deverá ficar isolada dentro do backend novo:

```text
/home/money/money2/appupdate/
├── update.json
├── android/
│   └── money.apk
└── ios/
    ├── money-1.0.1+2.ipa
    └── manifest-1.0.1+2.plist
```

O Android usa sempre o nome fixo `money.apk`, compartilhado pela página pública
e pela atualização dentro do aplicativo. Por isso, esse endereço deve ser
servido sem cache persistente e a substituição do APK deve ser atômica. No iOS,
o IPA e o manifesto continuam usando nomes versionados.

A pasta `appupdate` deverá ser adicionada às exclusões do script
`money2/deploy/sync-source.sh`. Atualmente o script usa `rsync --delete`; sem a
exclusão, uma publicação de fontes poderia remover os instaladores mantidos no
servidor.

## Manifesto principal `update.json`

Um único JSON controlará as três plataformas. Exemplo:

```json
{
  "schema": 1,
  "publishedAt": "2026-08-22T11:20:00-04:00",
  "android": {
    "minimumBuild": 2,
    "latestBuild": 2,
    "version": "1.0.1",
    "available": true,
    "downloadUrl": "https://moneyapp.site/appupdate/android/money.apk",
    "size": 48201931,
    "sha256": "SHA256_DO_APK"
  },
  "ios": {
    "minimumBuild": 2,
    "latestBuild": 2,
    "version": "1.0.1",
    "available": true,
    "installUrl": "itms-services://?action=download-manifest&url=https%3A%2F%2Fmoneyapp.site%2Fappupdate%2Fios%2Fmanifest-1.0.1%2B2.plist"
  },
  "web": {
    "available": true,
    "releaseId": "2026.08.24.1"
  }
}
```

Regras:

- `minimumBuild` determina a menor compilação autorizada a usar o sistema.
- `latestBuild` identifica a compilação mais recente disponível.
- Para tornar toda atualização obrigatória, `minimumBuild` e `latestBuild`
  recebem o novo número de build.
- Android e iOS podem ter números de build diferentes, caso as publicações não
  ocorram juntas.
- O manifesto deverá ser pequeno, público e servido sem cache persistente.
- O aplicativo deverá comparar números inteiros de build, não somente textos
  como `1.0.1`.

## Manifesto Ad Hoc do iOS

O `manifest.plist` aponta para o IPA hospedado por HTTPS. Estrutura de
referência:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>
          <string>software-package</string>
          <key>url</key>
          <string>https://moneyapp.site/appupdate/ios/money-1.0.1+2.ipa</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key>
        <string>com.webdigital.money</string>
        <key>bundle-version</key>
        <string>2</string>
        <key>kind</key>
        <string>software</string>
        <key>title</key>
        <string>Money</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
```

Na exportação Ad Hoc, o Xcode também pode gerar o manifesto ao selecionar a
opção de instalação over-the-air.

## Fluxo dentro do Flutter

O sistema deverá ser implementado como um bloqueio global acima de login,
biometria, página inicial, diálogos e demais rotas.

Fluxo de abertura:

```text
Abrir o Money
    |
    v
Consultar update.json
    |
    +-- build permitido --> continuar para login, bloqueio ou aplicação
    |
    +-- build obsoleto --> exibir a tela obrigatória de atualização
```

A verificação deverá acontecer:

- antes de liberar o fluxo normal na abertura;
- quando o aplicativo voltar ao primeiro plano;
- quando a conexão com a internet retornar;
- periodicamente enquanto o aplicativo estiver aberto.

Um intervalo entre 15 e 30 segundos, com suporte a `ETag` e resposta `304`, é
suficiente para uma detecção rápida sem manter conexão permanente. Uma
atualização verdadeiramente instantânea exigiria WebSocket, SSE ou push e não
é necessária para a primeira versão desse sistema.

## Tela de atualização

A página deverá reutilizar o layout de
`Money/lib/presentation/screens/locked_app_screen.dart`.

Alterações visuais:

- usar `assets/images/update.png`;
- manter o logotipo e o dimensionamento da página de bloqueio;
- trocar o botão principal por `ATUALIZAR`;
- impedir voltar, fechar ou acessar outra parte do aplicativo enquanto a
  atualização for obrigatória.

Comportamento do botão:

### Android

1. Substituir o conteúdo do botão por progresso com porcentagem.
2. Fazer download por streaming usando o `Content-Length`.
3. Salvar o APK em uma pasta temporária privada do aplicativo.
4. Conferir o tamanho e o SHA-256.
5. Solicitar a permissão de instalação de aplicativos desconhecidos, quando
   necessária.
6. Abrir o instalador do Android.
7. Manter a tela bloqueada se a instalação for cancelada ou falhar.

Não será necessária permissão geral de armazenamento se o APK for mantido na
pasta temporária do próprio aplicativo e compartilhado com o instalador por um
`FileProvider`.

### iOS

1. Mostrar um carregamento indeterminado com o texto `Abrindo atualização...`.
2. Abrir o `installUrl` recebido no JSON.
3. Deixar o iOS baixar, validar e instalar o IPA.
4. Manter a tela bloqueada se o usuário retornar sem concluir a atualização.

Não deve ser exibida porcentagem artificial no iOS, pois o sistema não entrega
ao Flutter o progresso do instalador Ad Hoc.

### Web

1. Mostrar um carregamento indeterminado.
2. Recarregar a página com um identificador de versão ou cache buster.
3. Se a versão carregada continuar antiga, manter a tela e permitir nova
   tentativa.

## Comportamento sem internet

O Money já possui funcionamento offline. O sistema de atualização deverá
preservar esse comportamento:

- se o servidor estiver indisponível e o aparelho nunca tiver recebido a
  informação de uma atualização obrigatória, permitir o fluxo offline atual;
- depois que uma atualização obrigatória tiver sido detectada, armazenar
  localmente o `minimumBuild` e continuar bloqueando mesmo sem internet;
- na tela de atualização sem conexão, informar que é necessário reconectar
  para baixar a nova versão.

Essa regra evita bloquear todos os usuários por uma indisponibilidade
temporária do servidor, sem permitir que uma atualização obrigatória já
conhecida seja ignorada.

## Backend `money2`

Os arquivos públicos são entregues diretamente pelo Nginx, sem autenticação,
pois a checagem acontece antes do login:

```text
GET /appupdate/update.json
GET /appupdate/android/{arquivo}
GET /appupdate/ios/{arquivo}
```

Não existe listagem pública do conteúdo da pasta. O restante da API continua
em `/api/v2/` e é encaminhado pelo Nginx para o backend novo na porta `8081`.

Cabeçalhos recomendados:

- `update.json`: `Cache-Control: no-store` e suporte a `ETag`;
- APK, IPA e PLIST versionados: cache imutável;
- APK: `application/vnd.android.package-archive`;
- IPA: `application/octet-stream`;
- PLIST: `application/xml` ou `text/xml`;
- downloads: informar `Content-Length` e, preferencialmente, aceitar `Range`.

O domínio utilizado deve ser HTTPS, permanente e possuir certificado válido.
O endereço temporário `trycloudflare` não deve ser usado como endereço de
distribuição definitiva.

## Ordem segura de publicação

Nunca atualizar o JSON antes de os instaladores estarem disponíveis.

Ordem obrigatória:

1. Incrementar versão e build no Flutter.
2. Gerar o APK de produção com a chave definitiva.
3. Gerar o IPA Ad Hoc com todos os UDIDs autorizados.
4. Gerar o `manifest.plist` versionado.
5. Calcular tamanho e SHA-256 dos arquivos.
6. Enviar APK, IPA e PLIST para nomes temporários no servidor.
7. Validar download, assinatura e hash.
8. Renomear os arquivos de forma atômica para os nomes definitivos; no Android,
   o destino é sempre `appupdate/android/money.apk`.
9. Atualizar o `update.json` por último, também de forma atômica.
10. Testar a atualização em pelo menos um Android, um iPhone cadastrado e um
    navegador.

Se o JSON for publicado antes do arquivo, os usuários serão bloqueados em uma
tela cuja atualização ainda não pode ser instalada.

## Primeira instalação no iOS

Para cada novo iPhone:

1. Obter o UDID do aparelho.
2. Cadastrar o UDID em Certificates, Identifiers & Profiles.
3. Atualizar ou recriar o perfil Ad Hoc.
4. Gerar um IPA que inclua o novo perfil.
5. Publicar o IPA e o manifesto.
6. Enviar ao usuário o link HTTPS da página de instalação ou um QR Code.
7. Orientar a confirmação da instalação e a ativação do Modo de Desenvolvedor,
   se solicitado pelo iOS.

A página pública para o primeiro acesso é:

```text
https://moneyapp.site/download/ios
```

Ela consulta o mesmo `update.json` e só libera o botão de instalação quando a
publicação do iOS estiver marcada com `available: true` e tiver um
`installUrl` válido.

Depois dessa instalação, o próprio Money fará a detecção das novas versões. O
usuário não precisará receber manualmente outro link, desde que o aparelho
continue incluído no perfil usado para assinar o novo IPA.

## Validações antes da publicação dos instaladores

- O domínio permanente definido é `moneyapp.site`.
- Confirmar e guardar com segurança a chave de assinatura Android.
- Confirmar a conta, o certificado e o Bundle Identifier no Apple Developer.
- Definir o responsável pelo cadastro e controle dos UDIDs.
- Definir o processo anual de renovação dos certificados e perfis Ad Hoc.
- Garantir que `appupdate` seja preservada pelo processo de publicação do
  backend.
- Definir um aparelho Android e um iPhone exclusivos para validar atualizações
  antes de liberar um novo `minimumBuild`.

## Referências oficiais

- Apple — dispositivos registrados e limite anual:
  <https://developer.apple.com/help/account/devices/devices-overview/>
- Apple — distribuição para aparelhos registrados:
  <https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices>
- Apple — exportação e manifesto para instalação OTA:
  <https://help.apple.com/xcode/mac/current/en.lproj/dev23ea8b877.html>
- Android — instalação e atualização de pacotes:
  <https://developer.android.com/reference/android/content/pm/PackageInstaller>
- Android — controle de versões:
  <https://developer.android.com/studio/publish/versioning>
- Flutter Web — atualização e cache:
  <https://docs.flutter.dev/platform-integration/web/faq>

## Estado atual

Implementado em 22 de agosto de 2026:

- bloqueio global obrigatório no Android, iOS e web;
- verificação na abertura, no retorno ao primeiro plano, no retorno da conexão
  e a cada 20 segundos;
- persistência local de uma atualização obrigatória já detectada;
- tela baseada na página de bloqueio, usando `update.png`;
- download Android com progresso real, tamanho, SHA-256 e abertura do
  instalador pelo `FileProvider`;
- abertura da instalação OTA Ad Hoc no iOS;
- recarregamento com cache buster na web;
- página pública de primeira instalação do iOS em `/download/ios`;
- página pública de download do Android em `/download/android`;
- compartilhamento de links específicos para Android, iOS e web nas
  configurações;
- estrutura `money2/appupdate`, preservada pelo `sync-source.sh`;
- APK Android `1.0.39+40` publicado como `appupdate/android/money.apk`, usado
  tanto pela página pública quanto pela atualização dentro do aplicativo;
- IPA iOS Ad Hoc `1.0.39+40` publicado para os cinco aparelhos cadastrados,
  incluindo o aparelho `Matheus 2`;
- web na versão `2026.10.16.1`;
- URL padrão da API fixada em `https://moneyapp.site` para Android, iOS e Web,
  eliminando a dependência do túnel temporário Cloudflare;
- contratos com PIX aguardando pagamento bloqueiam refinanciamento, renovação,
  cancelamento e finalização;
- contratos permitem cancelar os PIX pendentes diretamente no Sicredi; só são
  liberados quando o banco confirma o cancelamento;
- a mensagem automática após o pagamento PIX informa parcelas com base no saldo
  aprovado, evitando marcar como quitada uma parcela ainda pendente.

Android e iOS estão com `minimumBuild: 40`, direcionando versões anteriores ao
build `1.0.39+40`. Em uma atualização futura, aumente o build do aplicativo,
substitua `money.apk`, atualize tamanho e SHA-256 e só então aumente
`minimumBuild`. O iOS aponta para o manifesto Ad Hoc versionado
`manifest-1.0.39+40.plist`.
