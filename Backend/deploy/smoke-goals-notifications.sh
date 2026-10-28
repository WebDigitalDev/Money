#!/usr/bin/env bash
# Read-only checks. Prints timings and counts, never credentials or client data.
set -euo pipefail
properties_file="${1:-/home/money/money2/config/application-production.properties}"
property_value() { sed -n "s/^$1=//p" "$properties_file" | head -1; }
database_url="$(property_value spring.datasource.url)"
database_user="$(property_value spring.datasource.username)"
database_password="$(property_value spring.datasource.password)"
jwt_secret="$(property_value money.security.jwt-secret)"
row="$(PGPASSWORD="$database_password" psql "${database_url#jdbc:}" -U "$database_user" -Atc \
  "SELECT u.id||'|'||u.username FROM users u JOIN regiao_usuario r ON r.usuario_id=u.id
   WHERE u.administrador=true AND u.enable=true AND u.locked=false GROUP BY u.id,u.username ORDER BY count(*) DESC LIMIT 1")"
token="$(JWT_SECRET="$jwt_secret" MONEY_USER_ID="${row%%|*}" MONEY_USERNAME="${row#*|}" python3 -c '
import base64,hashlib,hmac,json,os,time
enc=lambda x:base64.urlsafe_b64encode(x).rstrip(b"=")
now=int(time.time())
head=enc(b"{\"alg\":\"HS256\"}")
body=enc(json.dumps({"sub":os.environ["MONEY_USERNAME"],"userName":os.environ["MONEY_USERNAME"],"userId":int(os.environ["MONEY_USER_ID"]),"iat":now,"exp":now+300}).encode())
msg=head+b"."+body
print((msg+b"."+enc(hmac.new(base64.b64decode(os.environ["JWT_SECRET"]),msg,hashlib.sha256).digest())).decode())')"
response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT
endpoints=(financial-goals)
if [[ "${2:-}" != before ]]; then endpoints+=(notifications notifications/preferences dashboard); fi
for endpoint in "${endpoints[@]}"; do
  info="$(curl -sS --max-time 60 -o "$response_file" -w '%{http_code} %{time_total}' \
    -H "Authorization: Bearer $token" "http://127.0.0.1:8081/api/v2/$endpoint")"
  [[ "$info" == 200\ * ]] || { echo "$endpoint failed: $info"; exit 1; }
  jq -e 'has("responseBody")' "$response_file" >/dev/null
  if [[ "$endpoint" == notifications/preferences ]]; then
    jq -e '.responseBody | (.payments|type)=="boolean" and (.goals|type)=="boolean"' "$response_file" >/dev/null
  fi
  printf '%s HTTP/seconds=%s\n' "$endpoint" "$info"
done
