# Atualizações Android

Publique aqui somente o APK assinado com o nome fixo `money.apk`. Envie a nova
compilação com um nome temporário, valide tamanho, assinatura e SHA-256 e então
substitua `money.apk` de forma atômica. O `update.json` deve ser alterado por
último.

A página pública `/download/android` e a atualização obrigatória dentro do
aplicativo usam o mesmo `android.downloadUrl` do `update.json`. Assim, os dois
fluxos sempre baixam exatamente o mesmo APK publicado nesta pasta.
