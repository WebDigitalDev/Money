# Money

Aplicação para gestão de empréstimos pessoais, com interface Flutter e backend Java.

- `Flutter/`: aplicativo para Android, iOS e web. Veja [Flutter/README.md](Flutter/README.md).
- `Backend/`: API em Java 17 e Spring Boot, configurações de implantação e scripts SQL. Veja [Backend/README.md](Backend/README.md).

## Configuração

O backend usa PostgreSQL. Defina `MONEY2_DB_URL`, `MONEY2_DB_USERNAME`,
`MONEY2_DB_PASSWORD` e `MONEY2_JWT_SECRET` no ambiente antes de executar:

```sh
cd Backend
mvn spring-boot:run
```

Os arquivos `Backend/config/*.example` servem de modelo para a configuração
de produção. Copie-os sem o sufixo `.example` e preencha os valores do seu ambiente.
As configurações reais, credenciais SSH e chaves de assinatura ficam fora do Git.

Para preparar o aplicativo, use uma instalação do Flutter compatível com a
versão do Dart definida em `Flutter/pubspec.yaml`:

```sh
cd Flutter
flutter pub get
flutter run
```

Backups, dados de usuários, caches e arquivos compilados não fazem parte do repositório.
