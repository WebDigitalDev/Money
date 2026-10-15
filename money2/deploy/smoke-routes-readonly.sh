#!/usr/bin/env bash
set -euo pipefail

properties_file="${1:-/home/money/money2/config/application-production.properties}"
internal_base_url="${MONEY2_BASE_URL:-http://127.0.0.1:8081}"
public_base_url="${MONEY2_PUBLIC_BASE_URL:-https://moneyapp.site}"

property_value() {
  sed -n "s/^$1=//p" "$properties_file" | head -1
}

database_url="$(property_value spring.datasource.url)"
database_user="$(property_value spring.datasource.username)"
database_password="$(property_value spring.datasource.password)"
jwt_secret="$(property_value money.security.jwt-secret)"
postgres_url="${database_url#jdbc:}"

database_query() {
  PGPASSWORD="$database_password" psql "$postgres_url" -U "$database_user" -Atc "$1"
}

admin_row="$(database_query \
  "select id || '|' || username from users where administrador=true and enable=true and locked=false order by id limit 1")"
admin_id="${admin_row%%|*}"
admin_username="${admin_row#*|}"
regular_row="$(database_query \
  "select id || '|' || username from users where administrador=false and coalesce(cobrador,false)=false and enable=true and locked=false order by id limit 1")"

if [[ -z "$admin_id" || -z "$admin_username" ]]; then
  echo "Administrador ativo não encontrado para o smoke test." >&2
  exit 1
fi

issue_token() {
  local user_id="$1"
  local username="$2"
  JWT_SECRET="$jwt_secret" MONEY_USER_ID="$user_id" MONEY_USERNAME="$username" \
    python3 -c 'import base64, hashlib, hmac, json, os, time
enc=lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
now=int(time.time())
header=enc(json.dumps({"alg":"HS256"},separators=(",",":")).encode())
payload=enc(json.dumps({"sub":os.environ["MONEY_USERNAME"],"userName":os.environ["MONEY_USERNAME"],"userId":int(os.environ["MONEY_USER_ID"]),"iat":now,"exp":now+300},separators=(",",":")).encode())
unsigned=header+b"."+payload
key=base64.b64decode(os.environ["JWT_SECRET"])
print((unsigned+b"."+enc(hmac.new(key,unsigned,hashlib.sha256).digest())).decode())'
}

admin_token="$(issue_token "$admin_id" "$admin_username")"
response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

request_get() {
  local base_url="$1"
  local path="$2"
  local token="$3"
  curl --silent --show-error --output "$response_file" \
    --write-out '%{http_code}|%{time_total}|%{size_download}' \
    --header "Authorization: Bearer $token" "$base_url$path"
}

session_result="$(request_get "$internal_base_url" "/api/v2/auth/session" "$admin_token")"
IFS='|' read -r session_status session_time session_size <<<"$session_result"
[[ "$session_status" == "200" ]]
jq -e '.responseBody | (.administrator == true and (.collector | type == "boolean"))' "$response_file" >/dev/null
printf 'sessao=http_%s tempo=%ss cobrador_exposto=sim\n' "$session_status" "$session_time"

routes_result="$(request_get "$internal_base_url" "/api/v2/routes?page=0&size=5" "$admin_token")"
IFS='|' read -r routes_status routes_time routes_size <<<"$routes_result"
[[ "$routes_status" == "200" ]]
jq -e '.responseBody.items and (.responseBody.totalItems >= 1)' "$response_file" >/dev/null
client_id="$(jq -r '.responseBody.items[0].clientId' "$response_file")"
total_items="$(jq -r '.responseBody.totalItems' "$response_file")"
total_debt="$(jq -r '.responseBody.totalDebt' "$response_file")"
total_overdue="$(jq -r '.responseBody.totalOverdueDebt' "$response_file")"
printf 'rotas_interno=http_%s tempo=%ss bytes=%s clientes=%s divida_total=%s vencida=%s\n' \
  "$routes_status" "$routes_time" "$routes_size" "$total_items" "$total_debt" "$total_overdue"

detail_result="$(request_get "$internal_base_url" "/api/v2/routes/$client_id" "$admin_token")"
IFS='|' read -r detail_status detail_time detail_size <<<"$detail_result"
[[ "$detail_status" == "200" ]]
jq -e --argjson client_id "$client_id" \
  '.responseBody.debt.clientId == $client_id and (.responseBody.contracts | length) >= 1 and (.responseBody.canRegisterCollection == true)' \
  "$response_file" >/dev/null
contract_count="$(jq -r '.responseBody.contracts | length' "$response_file")"
history_count="$(jq -r '.responseBody.history | length' "$response_file")"
printf 'detalhe=http_%s tempo=%ss contratos=%s historico=%s registro_permitido=sim\n' \
  "$detail_status" "$detail_time" "$contract_count" "$history_count"

history_result="$(request_get "$internal_base_url" "/api/v2/clients/$client_id/collections" "$admin_token")"
IFS='|' read -r history_status history_time history_size <<<"$history_result"
[[ "$history_status" == "200" ]]
jq -e '.responseBody | type == "array"' "$response_file" >/dev/null
printf 'historico_cliente=http_%s tempo=%ss\n' "$history_status" "$history_time"

public_result="$(request_get "$public_base_url" "/api/v2/routes?page=0&size=1" "$admin_token")"
IFS='|' read -r public_status public_time public_size <<<"$public_result"
[[ "$public_status" == "200" ]]
jq -e '.responseBody.items | length >= 1' "$response_file" >/dev/null
printf 'rotas_publico=http_%s tempo=%ss bytes=%s\n' "$public_status" "$public_time" "$public_size"

before_count="$(database_query 'select count(*) from money2_cobrancas')"
invalid_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
  --header "Authorization: Bearer $admin_token" \
  --form 'observation=' \
  "$internal_base_url/api/v2/routes/$client_id/collections")"
after_count="$(database_query 'select count(*) from money2_cobrancas')"
printf 'diagnostico_registro_vazio=http_%s antes=%s depois=%s\n' "$invalid_status" "$before_count" "$after_count"
[[ "$invalid_status" == "400" && "$before_count" == "$after_count" ]]
printf 'validacao_registro_vazio=http_%s sem_gravacao=sim\n' "$invalid_status"

if [[ -n "$regular_row" ]]; then
  regular_id="${regular_row%%|*}"
  regular_username="${regular_row#*|}"
  regular_token="$(issue_token "$regular_id" "$regular_username")"
  forbidden_result="$(request_get "$internal_base_url" "/api/v2/routes?page=0&size=1" "$regular_token")"
  IFS='|' read -r forbidden_status forbidden_time forbidden_size <<<"$forbidden_result"
  printf 'diagnostico_usuario_sem_permissao=http_%s\n' "$forbidden_status"
  [[ "$forbidden_status" == "403" ]]
  printf 'usuario_sem_permissao=http_%s\n' "$forbidden_status"
fi

collector_count="$(database_query 'select count(*) from users where coalesce(cobrador,false)=true')"
printf 'schema=ok cobradores_ativos_configurados=%s cobrancas_registradas=%s\n' "$collector_count" "$after_count"
