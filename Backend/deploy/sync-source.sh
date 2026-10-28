#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Uso: $0 usuario@servidor" >&2
  exit 2
fi

target="$1"
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_directory="$(cd -- "$script_directory/.." && pwd)"
workspace_directory="$(cd -- "$source_directory/.." && pwd)"
pdf_asset_directory="$workspace_directory/Money/assets/images"

# Os diretórios abaixo pertencem ao servidor. Além de não serem enviados,
# a exclusão impede que o --delete remova configurações, binários, arquivos
# de clientes, certificados ou snapshots operacionais.
rsync -az --delete \
  --exclude '/app/***' \
  --exclude '/appupdate/***' \
  --exclude '/backups/***' \
  --exclude '/config/***' \
  --exclude '/data/***' \
  --exclude '/target/***' \
  --exclude '/web/***' \
  --exclude '/web.previous-*/***' \
  --exclude '/staging/***' \
  --exclude '/release-staging*/***' \
  --exclude '/tmp-release-*/***' \
  --exclude '/.git/***' \
  --exclude '.DS_Store' \
  "$source_directory/" \
  "$target:/home/money/money2/"

if [[ ! -f "$pdf_asset_directory/moneybr.png" ]]; then
  echo "A imagem moneybr.png não foi encontrada." >&2
  exit 1
fi

ssh "$target" \
  "mkdir -p /home/money/money2/data/pdf-assets && chmod 0755 /home/money/money2/data/pdf-assets"
rsync -az \
  "$pdf_asset_directory/moneybr.png" \
  "$target:/home/money/money2/data/pdf-assets/"
ssh "$target" \
  "chown -R money:money /home/money/money2/data/pdf-assets && chmod 0644 /home/money/money2/data/pdf-assets/*.png"
