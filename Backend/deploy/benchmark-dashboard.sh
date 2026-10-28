#!/usr/bin/env bash
set -euo pipefail

properties_file="${1:-/home/money/money2/config/application-production.properties}"
base_url="${MONEY2_BASE_URL:-http://127.0.0.1:8081}"

property_value() {
  sed -n "s/^$1=//p" "$properties_file" | head -1
}

database_url="$(property_value spring.datasource.url)"
database_user="$(property_value spring.datasource.username)"
database_password="$(property_value spring.datasource.password)"
jwt_secret="$(property_value money.security.jwt-secret)"
postgres_url="${database_url#jdbc:}"

admin_row="$(PGPASSWORD="$database_password" psql "$postgres_url" -U "$database_user" -Atc \
  "select u.id || '|' || u.username
     from users u
     join regiao_usuario access on access.usuario_id = u.id
    where u.administrador = true and u.enable = true and u.locked = false
    group by u.id, u.username
    order by count(*) desc, u.id
    limit 1")"
admin_id="${admin_row%%|*}"
admin_username="${admin_row#*|}"
region_ids="$(PGPASSWORD="$database_password" psql "$postgres_url" -U "$database_user" -Atc \
  "select string_agg(regiao_id::text, ',' order by regiao_id)
     from regiao_usuario
    where usuario_id = $admin_id")"

if [[ -z "$admin_id" || -z "$admin_username" || -z "$region_ids" ]]; then
  echo "Não foi possível montar o cenário com todas as regiões." >&2
  exit 1
fi

token="$(JWT_SECRET="$jwt_secret" MONEY_ADMIN_ID="$admin_id" \
  MONEY_ADMIN_USERNAME="$admin_username" python3 -c 'import base64, hashlib, hmac, json, os, time
enc=lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
now=int(time.time())
header=enc(json.dumps({"alg":"HS256"},separators=(",",":")).encode())
payload=enc(json.dumps({"sub":os.environ["MONEY_ADMIN_USERNAME"],"userName":os.environ["MONEY_ADMIN_USERNAME"],"userId":int(os.environ["MONEY_ADMIN_ID"]),"iat":now,"exp":now+300},separators=(",",":")).encode())
unsigned=header+b"."+payload
key=base64.b64decode(os.environ["JWT_SECRET"])
print((unsigned+b"."+enc(hmac.new(key,unsigned,hashlib.sha256).digest())).decode())')"

response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT
region_count="$(tr ',' '\n' <<<"$region_ids" | wc -l | tr -d ' ')"

for attempt in 1 2; do
  result="$(curl --silent --show-error --output "$response_file" \
    --write-out '%{http_code}|%{time_total}|%{size_download}' \
    --header "Authorization: Bearer $token" \
    "$base_url/api/v2/dashboard?regionIds=$region_ids")"
  IFS='|' read -r status duration size <<<"$result"
  if [[ "$status" != "200" ]]; then
    echo "Dashboard: HTTP $status" >&2
    exit 1
  fi
  jq -e '
    .responseBody.regions and
    .responseBody.metrics and
    (.responseBody.financial.points | length == 31) and
    (.responseBody as $d |
      $d.financial.points[-1].date == $d.date and
      (($d.financial.points[0].date + "T00:00:00Z" | fromdateiso8601) ==
       (($d.date + "T00:00:00Z" | fromdateiso8601) - 30 * 86400))) and
    .responseBody.activeGoals and
    .responseBody.dueToday
  ' "$response_file" >/dev/null
  goals="$(jq '.responseBody.activeGoals | length' "$response_file")"
  jq -r '.responseBody.financial.points | "periodo=\(.[0].date) ate \(.[-1].date) pontos=\(length)"' "$response_file"
  due_today="$(jq '.responseBody.dueToday | length' "$response_file")"
  printf 'tentativa=%s regioes=%s tempo=%ss bytes=%s metas=%s vencimentos=%s\n' \
    "$attempt" "$region_count" "$duration" "$size" "$goals" "$due_today"
done
