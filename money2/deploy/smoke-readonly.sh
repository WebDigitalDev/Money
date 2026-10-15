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
  "select id || '|' || username from users where administrador=true and enable=true and locked=false order by id limit 1")"
admin_id="${admin_row%%|*}"
admin_username="${admin_row#*|}"
loan_id="$(PGPASSWORD="$database_password" psql "$postgres_url" -U "$database_user" -Atc \
  "select id from emprestimo order by id desc limit 1")"
client_id="$(PGPASSWORD="$database_password" psql "$postgres_url" -U "$database_user" -Atc \
  "select c.id from cliente c where c.ativo=true and exists (select 1 from regiao_usuario ur where ur.usuario_id=$admin_id and ur.regiao_id=c.regiao_id) order by c.id desc limit 1")"
active_client_id="$(PGPASSWORD="$database_password" psql "$postgres_url" -U "$database_user" -Atc \
  "select c.id from cliente c join emprestimo e on e.cliente_id=c.id where c.ativo=true and coalesce(e.aprovacao_status,'APROVADO')='APROVADO' and e.status<>3 and coalesce(e.refinanciado,false)=false and coalesce(e.renovacao,false)=false and exists (select 1 from parcelas p where p.emprestimo_id=e.id and p.pendente=true and greatest(coalesce(p.valor,0)+coalesce(p.valor_juros,0)-coalesce((select sum(pg.valor) from pagamentos pg where pg.parcela_id=p.id and coalesce(pg.aprovacao_status,'APROVADO')='APROVADO' and coalesce(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0),0)>0) and exists (select 1 from regiao_usuario ur where ur.usuario_id=$admin_id and ur.regiao_id=c.regiao_id) order by e.id desc limit 1")"
missing_client_id="$(PGPASSWORD="$database_password" psql "$postgres_url" -U "$database_user" -Atc \
  "select c.id from cliente c where exists (select 1 from regiao_usuario ur where ur.usuario_id=$admin_id and ur.regiao_id=c.regiao_id) and exists (select 1 from emprestimo e where e.cliente_id=c.id and coalesce(e.aprovacao_status,'APROVADO')='APROVADO' and e.status<>3 and e.status<>1 and coalesce(e.refinanciado,false)=false and coalesce(e.renovacao,false)=false and coalesce(e.desaparecido,false)=true) order by c.id desc limit 1")"
settled_late_client_id="$(PGPASSWORD="$database_password" psql "$postgres_url" -U "$database_user" -Atc \
  "select c.id from cliente c where exists (select 1 from regiao_usuario ur where ur.usuario_id=$admin_id and ur.regiao_id=c.regiao_id) and exists (select 1 from emprestimo e where e.cliente_id=c.id and coalesce(e.aprovacao_status,'APROVADO')='APROVADO' and e.status<>3 and e.status<>1 and coalesce(e.refinanciado,false)=false and coalesce(e.renovacao,false)=false and coalesce(e.desaparecido,false)=false and not exists (select 1 from parcelas p where p.emprestimo_id=e.id and greatest(round((coalesce(p.valor,0)+coalesce(p.valor_juros,0))::numeric,2)-round(coalesce((select sum(pg.valor) from pagamentos pg where pg.parcela_id=p.id and coalesce(pg.aprovacao_status,'APROVADO')='APROVADO' and coalesce(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0)::numeric,2),0)>0) and (select max(pg.data)::date from pagamentos pg join parcelas p on p.id=pg.parcela_id where p.emprestimo_id=e.id and coalesce(pg.aprovacao_status,'APROVADO')='APROVADO' and coalesce(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM') > (select max(p.vencimento)::date from parcelas p where p.emprestimo_id=e.id)) and not exists (select 1 from emprestimo e join parcelas p on p.emprestimo_id=e.id where e.cliente_id=c.id and coalesce(e.aprovacao_status,'APROVADO')='APROVADO' and e.status<>3 and e.status<>1 and coalesce(e.refinanciado,false)=false and coalesce(e.renovacao,false)=false and p.vencimento::date<current_date and greatest(round((coalesce(p.valor,0)+coalesce(p.valor_juros,0))::numeric,2)-round(coalesce((select sum(pg.valor) from pagamentos pg where pg.parcela_id=p.id and coalesce(pg.aprovacao_status,'APROVADO')='APROVADO' and coalesce(pg.tipo,'NORMAL')<>'JUROS_ROLAGEM'),0)::numeric,2),0)>0) order by c.id desc limit 1")"
common_loan_id="$(PGPASSWORD="$database_password" psql "$postgres_url" -U "$database_user" -Atc \
  "select e.id from emprestimo e where coalesce(e.aprovacao_status, 'APROVADO') = 'APROVADO' and coalesce(e.juros, 0) > 0 and not exists (select 1 from refinanciamentos r where r.emp_id_destino = e.id) order by e.id desc limit 1")"
negotiated_loan_id="$(PGPASSWORD="$database_password" psql "$postgres_url" -U "$database_user" -Atc \
  "select e.id from emprestimo e where coalesce(e.aprovacao_status, 'APROVADO') = 'APROVADO' and exists (select 1 from refinanciamentos r where r.emp_id_destino = e.id) order by e.id desc limit 1")"

if [[ -z "$admin_id" || -z "$admin_username" || -z "$loan_id" || -z "$client_id" || -z "$active_client_id" ]]; then
  echo "Não foi possível localizar um administrador, cliente e empréstimo para o smoke test." >&2
  exit 1
fi

token="$(JWT_SECRET="$jwt_secret" MONEY_ADMIN_ID="$admin_id" MONEY_ADMIN_USERNAME="$admin_username" \
  python3 -c 'import base64, hashlib, hmac, json, os, time
enc=lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
now=int(time.time())
header=enc(json.dumps({"alg":"HS256"},separators=(",",":")).encode())
payload=enc(json.dumps({"sub":os.environ["MONEY_ADMIN_USERNAME"],"userName":os.environ["MONEY_ADMIN_USERNAME"],"userId":int(os.environ["MONEY_ADMIN_ID"]),"iat":now,"exp":now+300},separators=(",",":")).encode())
unsigned=header+b"."+payload
key=base64.b64decode(os.environ["JWT_SECRET"])
print((unsigned+b"."+enc(hmac.new(key,unsigned,hashlib.sha256).digest())).decode())')"

response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

check_get() {
  local label="$1"
  local path="$2"
  local status
  status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --header "Authorization: Bearer $token" "$base_url$path")"
  if [[ "$status" != "200" ]]; then
    echo "$label: HTTP $status" >&2
    sed -n '1,5p' "$response_file" >&2
    exit 1
  fi
  echo "$label: HTTP 200"
}

check_post() {
  local label="$1"
  local path="$2"
  local body="$3"
  local status
  status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    --data "$body" "$base_url$path")"
  if [[ "$status" != "200" ]]; then
    echo "$label: HTTP $status" >&2
    sed -n '1,5p' "$response_file" >&2
    exit 1
  fi
  echo "$label: HTTP 200"
}

check_get "Sessão" "/api/v2/auth/session"
check_get "Dashboard" "/api/v2/dashboard"
python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
dashboard = payload.get("responseBody", {})
required = {"regions", "metrics", "financial", "dueToday"}
missing = sorted(required.difference(dashboard))
if missing:
    raise SystemExit(f"Dashboard incompleto: {', '.join(missing)}")
if not dashboard.get("regions"):
    raise SystemExit("Dashboard sem regiões acessíveis.")
points = dashboard.get("financial", {}).get("points", [])
if len(points) < 28:
    raise SystemExit("Dashboard sem a série financeira mensal completa.")
print(f"Dashboard validado: {len(dashboard['regions'])} região(ões), {len(points)} pontos financeiros e {len(dashboard['dueToday'])} vencimento(s) hoje")
PY
if [[ -n "$missing_client_id" ]]; then
  check_get "Score de cliente desaparecido" "/api/v2/clients/$missing_client_id"
  python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
client = payload.get("responseBody", payload)
score = client.get("score") or {}
if client.get("status") != "MISSING":
    raise SystemExit("Cliente escolhido para o smoke não foi retornado como desaparecido.")
if score.get("points") != 0:
    raise SystemExit(f"Score do cliente desaparecido deveria ser 0, recebido: {score.get('points')}")
print("Score de cliente desaparecido validado em 0 ponto")
PY
fi
if [[ -n "$settled_late_client_id" ]]; then
  check_get "Atraso atual após quitação" "/api/v2/clients/$settled_late_client_id"
  python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
client = payload.get("responseBody", payload)
score = client.get("score") or {}
if score.get("overdueDays") != 0:
    raise SystemExit(f"Atraso atual deveria voltar a 0 após a quitação, recebido: {score.get('overdueDays')}")
print("Atraso atual após quitação validado em 0 dia")
PY
fi
check_post "Seleção de região do resumo" "/api/v2/chat/query" \
  '{"message":"Resumo financeiro","mode":"READY","conversationId":"smoke-summary"}'
summary_region_id="$(python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
response = payload.get("responseBody", {})
if response.get("mode") != "SUMMARY_REGION":
    raise SystemExit("O resumo não solicitou a região.")
regions = response.get("suggestions", [])
if not regions or not regions[0].get("regionId"):
    raise SystemExit("O resumo não retornou regiões autorizadas.")
print(regions[0]["regionId"])
PY
)"
summary_region_name="$(python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
regions = response.get("suggestions", [])
print(regions[0].get("label", "") if regions else "")
PY
)"
profit_body="$(python3 - "$summary_region_name" <<'PY'
import json
import sys
print(json.dumps({
    "message": f"Quanto lucrou a região {sys.argv[1]}?",
    "mode": "READY",
    "conversationId": "smoke-direct-profit",
}, ensure_ascii=False))
PY
)"
check_post "Lucro regional em linguagem natural" "/api/v2/chat/query" "$profit_body"
python3 - "$response_file" "$summary_region_name" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
if not response.get("summary") or sys.argv[2].lower() not in response.get("message", "").lower():
    raise SystemExit("A pergunta direta de lucro regional não retornou o indicador esperado.")
if response.get("semanticSearch") is not True:
    raise SystemExit("A pergunta regional não passou pelo contexto financeiro do Qdrant.")
print("Pergunta direta de lucro regional validada")
PY
goal_body="$(python3 - "$summary_region_name" <<'PY'
import json
import sys
print(json.dumps({
    "message": f"Quanto de meta recomenda para região {sys.argv[1]}?",
    "mode": "READY",
    "conversationId": "smoke-direct-goal",
}, ensure_ascii=False))
PY
)"
check_post "Recomendação regional de meta" "/api/v2/chat/query" "$goal_body"
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
message = response.get("message", "").lower()
if "três meses" not in message and "movimento suficiente" not in message:
    raise SystemExit("A recomendação regional não explicou a base financeira utilizada.")
print("Recomendação regional de meta validada")
PY
check_post "Seleção de período do resumo" "/api/v2/chat/query" \
  "{\"message\":\"Resumo financeiro\",\"mode\":\"SUMMARY_REGION\",\"regionId\":$summary_region_id,\"conversationId\":\"smoke-summary\"}"
python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
response = payload.get("responseBody", {})
if response.get("mode") != "SUMMARY_PERIOD":
    raise SystemExit("O resumo regional não solicitou o período.")
labels = [item.get("label") for item in response.get("suggestions", [])]
expected = ["Últimos 30 dias", "Escolher mês", "Geral", "Outro assunto"]
if labels != expected:
    raise SystemExit(f"Períodos do resumo inválidos: {labels}")
print("Períodos do resumo regional validados")
PY
check_post "Resumo regional do chatbot" "/api/v2/chat/query" \
  '{"message":"Últimos 30 dias","mode":"SUMMARY_PERIOD","conversationId":"smoke-summary"}'
python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
response = payload.get("responseBody", {})
summary = response.get("summary", {})
required = {
    "clients", "openLoans", "loaned", "received",
    "receivable", "overdue", "profit",
}
missing = sorted(required.difference(summary))
if missing:
    raise SystemExit(f"Resumo do chatbot incompleto: {', '.join(missing)}")
loan_status = response.get("loanStatus", {})
status_required = {
    "overdueCount", "overdueAmount", "onTimeCount", "onTimeAmount",
    "settledCount", "settledAmount",
}
status_missing = sorted(status_required.difference(loan_status))
if status_missing:
    raise SystemExit(f"Situações do resumo incompletas: {', '.join(status_missing)}")
removed = {"dueToday"}.intersection(summary)
removed.update({"dueTodayCount", "dueTodayAmount"}.intersection(loan_status))
if removed:
    raise SystemExit(f"Campos removidos ainda presentes no resumo: {', '.join(sorted(removed))}")
client_status = response.get("clientStatus", {})
client_required = {"activeCount", "withoutLoansCount", "missingCount"}
client_missing = sorted(client_required.difference(client_status))
if client_missing:
    raise SystemExit(f"Contadores de clientes incompletos: {', '.join(client_missing)}")
if not isinstance(response.get("financialGoals"), list):
    raise SystemExit("Lista de metas financeiras do resumo inválida.")
summary_context = response.get("summaryContext", {})
if not summary_context.get("regionId") or not summary_context.get("regionName"):
    raise SystemExit("Contexto de exportação do resumo inválido.")
labels = [item.get("label") for item in response.get("suggestions", [])]
if labels != ["Exportar PDF", "Outro assunto"]:
    raise SystemExit(f"Ações finais do resumo inválidas: {labels}")
print("Resumo regional do chatbot validado no PostgreSQL")
PY
check_post "Seleção de mês do resumo" "/api/v2/chat/query" \
  '{"message":"Escolher mês","mode":"SUMMARY_PERIOD","conversationId":"smoke-summary"}'
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
months = [
    item for item in response.get("suggestions", [])
    if item.get("action") == "SELECT_MONTH"
]
if response.get("mode") != "SUMMARY_MONTH" or not months:
    raise SystemExit("O resumo não retornou os meses disponíveis.")
if response.get("suggestions", [])[-1].get("label") != "Outro assunto":
    raise SystemExit("A seleção de mês não oferece Outro assunto.")
print(f"Seleção compacta de mês validada: {len(months)} mês(es)")
PY
current_year="$(date +%Y)"
current_month="$(date +%-m)"
check_post "Resumo mensal do chatbot" "/api/v2/chat/query" \
  "{\"message\":\"Resumo financeiro $current_year $current_month\",\"mode\":\"SUMMARY_MONTH\",\"conversationId\":\"smoke-summary\"}"
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
if not response.get("summary") or not response.get("loanStatus"):
    raise SystemExit("O resumo do mês escolhido não retornou os dados completos.")
print("Resumo do mês escolhido validado")
PY
check_post "Retorno do resumo ao início" "/api/v2/chat/query" \
  '{"message":"Outro assunto","mode":"READY","conversationId":"smoke-summary"}'
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
labels = [item.get("label") for item in response.get("suggestions", [])]
expected = [
    "Consultar cliente", "Vencimentos de hoje",
    "Empréstimos Atrasados", "Resumo financeiro",
]
if response.get("mode") != "READY" or labels != expected:
    raise SystemExit("Outro assunto não retornou às quatro opções iniciais.")
print("Outro assunto limpou o contexto e retornou ao início")
PY
check_get "PDF do resumo financeiro" "/api/v2/chat/summary-pdf?regionId=$summary_region_id"
python3 - "$response_file" <<'PY'
import os
import sys

path = sys.argv[1]
with open(path, "rb") as stream:
    signature = stream.read(5)
if signature != b"%PDF-":
    raise SystemExit("A exportação do resumo não retornou um PDF válido.")
if os.path.getsize(path) < 30000:
    raise SystemExit("O PDF do resumo está incompleto.")
print(f"PDF do resumo validado: {os.path.getsize(path)} bytes")
PY
if [[ -n "${MONEY2_PDF_OUTPUT:-}" ]]; then
  cp "$response_file" "$MONEY2_PDF_OUTPUT"
fi
check_post "Seleção de região dos vencimentos" "/api/v2/chat/query" \
  '{"message":"Vencimentos de hoje","mode":"READY"}'
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
if response.get("mode") != "DUE_TODAY_REGION" or not response.get("suggestions"):
    raise SystemExit("Vencimentos de hoje não solicitaram a região.")
print("Seleção regional dos vencimentos validada")
PY
check_post "Lista completa de vencimentos" "/api/v2/chat/query" \
  "{\"message\":\"Vencimentos de hoje\",\"mode\":\"DUE_TODAY_REGION\",\"regionId\":$summary_region_id}"
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
loans = response.get("loans", [])
if any(not loan.get("loanId") for loan in loans):
    raise SystemExit("A lista de vencimentos retornou empréstimo sem ID.")
labels = [item.get("label") for item in response.get("suggestions", [])]
if labels != ["Exportar", "Outro assunto"]:
    raise SystemExit(f"Ações dos vencimentos inválidas: {labels}")
print(f"Lista completa de vencimentos validada: {len(loans)} empréstimo(s)")
PY
check_post "Seleção de região dos atrasos" "/api/v2/chat/query" \
  '{"message":"Empréstimos Atrasados","mode":"READY"}'
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
if response.get("mode") != "OVERDUE_REGION" or not response.get("suggestions"):
    raise SystemExit("Clientes em atraso não solicitaram a região.")
print("Seleção regional dos atrasos validada")
PY
check_post "Lista completa de empréstimos atrasados" "/api/v2/chat/query" \
  "{\"message\":\"Empréstimos Atrasados\",\"mode\":\"OVERDUE_REGION\",\"regionId\":$summary_region_id}"
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
loans = response.get("loans", [])
if any(not loan.get("loanId") for loan in loans):
    raise SystemExit("A lista de atrasados retornou empréstimo sem ID.")
labels = [item.get("label") for item in response.get("suggestions", [])]
if labels != ["Exportar", "Outro assunto"]:
    raise SystemExit(f"Ações dos atrasados inválidas: {labels}")
print(f"Lista completa de atrasados validada: {len(loans)} empréstimo(s)")
PY
check_post "Consulta direta de contrato no chatbot" "/api/v2/chat/query" \
  "{\"message\":\"$loan_id\",\"mode\":\"READY\",\"conversationId\":\"smoke-contract\"}"
python3 - "$response_file" "$loan_id" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
expected_id = int(sys.argv[2])
contract = response.get("contract") or {}
required = {
    "loanId", "clientId", "clientName", "regionId", "regionName",
    "paymentType", "installmentCount", "paidInstallments",
    "openInstallments", "overdueInstallments", "loanedAmount",
    "totalAmount", "receivedAmount", "receivableAmount", "profitAmount",
    "status", "approvalStatus", "history",
}
missing = sorted(required.difference(contract))
if response.get("mode") != "CONTRACT_CONTEXT" or contract.get("loanId") != expected_id:
    raise SystemExit("A consulta numérica não retornou o contrato esperado.")
if missing:
    raise SystemExit(f"Contrato do chatbot incompleto: {', '.join(missing)}")
if response.get("semanticSearch") is not True:
    raise SystemExit("A consulta de contrato não passou pelo contexto financeiro do Qdrant.")
labels = [item.get("label") for item in response.get("suggestions", [])]
expected = ["Histórico", "Outro assunto"]
if labels != expected:
    raise SystemExit(f"Ações do contrato inválidas: {labels}")
print(f"Contrato #{expected_id} validado no chatbot com contexto Qdrant")
PY
check_post "Histórico contextual do contrato" "/api/v2/chat/query" \
  '{"message":"Quem criou e quais foram as alterações?","mode":"CONTRACT_CONTEXT","conversationId":"smoke-contract"}'
python3 - "$response_file" "$loan_id" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
contract = response.get("contract") or {}
if response.get("mode") != "CONTRACT_HISTORY" or contract.get("loanId") != int(sys.argv[2]):
    raise SystemExit("A pergunta de histórico perdeu o contexto do contrato.")
if not isinstance(contract.get("history"), list):
    raise SystemExit("O histórico contextual do contrato possui formato inválido.")
labels = [item.get("label") for item in response.get("suggestions", [])]
if labels != ["Histórico", "Outro assunto"]:
    raise SystemExit(f"Ações após o histórico são inválidas: {labels}")
print(f"Histórico contextual validado: {len(contract['history'])} evento(s)")
PY
check_post "Resposta contextual sem repetir card do contrato" "/api/v2/chat/query" \
  '{"message":"Qual foi o último pagamento?","mode":"CONTRACT_HISTORY","conversationId":"smoke-contract"}'
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
if response.get("mode") != "CONTRACT_CONTEXT" or response.get("contract") is not None:
    raise SystemExit("A resposta contextual repetiu o card do contrato.")
labels = [item.get("label") for item in response.get("suggestions", [])]
if labels != ["Histórico", "Outro assunto"]:
    raise SystemExit(f"Ações contextuais do contrato são inválidas: {labels}")
print("Resposta contextual manteve as ações sem repetir o card do contrato")
PY
check_post "Contrato inexistente no chatbot" "/api/v2/chat/query" \
  '{"message":"9223372036854775806","mode":"READY","conversationId":"smoke-not-found"}'
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
message = response.get("message", "").lower()
if response.get("contract") is not None or "número está correto" not in message:
    raise SystemExit("Contrato inexistente não retornou o feedback esperado.")
print("Feedback de contrato inexistente validado")
PY
check_post "Texto geral não pesquisa clientes" "/api/v2/chat/query" \
  '{"message":"silva","mode":"READY","conversationId":"smoke-no-client-fallback"}'
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
if response.get("clients") or response.get("mode") == "CLIENT_SEARCH":
    raise SystemExit("A caixa geral ainda está desviando mensagens para a busca de clientes.")
print("Caixa geral isolada da busca de clientes")
PY
check_post "Busca exata do chatbot" "/api/v2/chat/query" \
  '{"message":"silva","mode":"CLIENT_SEARCH"}'
python3 - "$response_file" <<'PY'
import json
import sys
import unicodedata

payload = json.load(open(sys.argv[1], encoding="utf-8"))
response = payload.get("responseBody", {})
clients = response.get("clients", [])
message = response.get("message", "").lower()
if not clients:
    if "nome e o sobrenome" not in message:
        raise SystemExit("A busca exata não retornou clientes nem solicitou um nome completo.")
    print("Busca exata ampla solicitou nome e sobrenome")
else:
    def normalize(value):
        decomposed = unicodedata.normalize("NFD", value or "")
        return "".join(char for char in decomposed if not unicodedata.combining(char)).lower()

    invalid = [client.get("name", "") for client in clients if "silva" not in normalize(client.get("name"))]
    if invalid:
        raise SystemExit("A busca exata misturou clientes sem a palavra pesquisada.")
    if len(clients) > 50:
        raise SystemExit("A busca exata ultrapassou o limite de 50 clientes.")
    print(f"Busca exata validada: {len(clients)} resultado(s) autorizado(s)")
PY
check_post "Seleção contextual do cliente" "/api/v2/chat/query" \
  "{\"message\":\"Abrir cliente\",\"mode\":\"CLIENT_SEARCH\",\"clientId\":$active_client_id,\"conversationId\":\"smoke-context\"}"
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
if response.get("mode") != "CLIENT_CONTEXT" or len(response.get("clients", [])) != 1:
    raise SystemExit("O chatbot não preservou o cliente selecionado.")
loans = response.get("loans", [])
if not loans:
    raise SystemExit("O retorno do cliente não listou seus empréstimos ativos.")
required = {
    "loanId", "clientName", "regionName", "paymentType",
    "dueDate", "installmentCount", "amount", "status",
}
for loan in loans:
    missing = sorted(required.difference(loan))
    if missing:
        raise SystemExit(f"Empréstimo ativo incompleto: {', '.join(missing)}")
print(f"Cliente selecionado com {len(loans)} empréstimo(s) ativo(s) clicável(is)")
PY
check_post "Continuação contextual do chatbot" "/api/v2/chat/query" \
  '{"message":"quando foi a data desse último pagamento?","mode":"CLIENT_CONTEXT","conversationId":"smoke-context"}'
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
if response.get("mode") != "CLIENT_CONTEXT" or response.get("clients"):
    raise SystemExit("A continuação perdeu o contexto ou repetiu o card do cliente.")
message = response.get("message", "").lower()
if "pagamento" not in message and "pagou" not in message:
    raise SystemExit(
        "A continuação não respondeu sobre o último pagamento: "
        + response.get("message", "")
    )
print("Pergunta de continuação respondeu sobre o cliente em contexto")
PY
check_post "Continuação curta do último pagamento" "/api/v2/chat/query" \
  '{"message":"e qual foi o valor?","mode":"CLIENT_CONTEXT","conversationId":"smoke-context"}'
check_post "Próximo vencimento contextual" "/api/v2/chat/query" \
  '{"message":"quando vence a próxima parcela?","mode":"CLIENT_CONTEXT","conversationId":"smoke-context"}'
check_post "Parcelas abertas contextuais" "/api/v2/chat/query" \
  '{"message":"quantas parcelas estão em aberto?","mode":"CLIENT_CONTEXT","conversationId":"smoke-context"}'
check_post "Contratos contextuais" "/api/v2/chat/query" \
  '{"message":"quais contratos estão ativos?","mode":"CLIENT_CONTEXT","conversationId":"smoke-context"}'
python3 - "$response_file" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8")).get("responseBody", {})
if (response.get("mode") != "CLIENT_CONTEXT" or not response.get("loans")
        or response.get("clients")):
    raise SystemExit("A pergunta por contratos ativos não retornou a lista clicável.")
print(f"Lista contextual validada: {len(response['loans'])} empréstimo(s) ativo(s)")
PY
check_get "Metas financeiras" "/api/v2/financial-goals"
python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
goals = payload.get("responseBody")
if not isinstance(goals, list):
    raise SystemExit("A rota de metas financeiras retornou formato inválido.")
required = {
    "id", "regionId", "regionName", "type", "targetAmount",
    "achievedAmount", "remainingAmount", "percentage", "startDate",
    "endDate", "status", "canManage",
}
for goal in goals:
    missing = sorted(required.difference(goal))
    if missing:
        raise SystemExit(f"Meta financeira incompleta: {', '.join(missing)}")
print(f"Metas financeiras validadas: {len(goals)} meta(s)")
PY
check_get "Contas bancárias" "/api/v2/integrations/banking/accounts"
check_get "Configuração WhatsApp" "/api/v2/integrations/whatsapp/config"
check_get "Logs WhatsApp" "/api/v2/integrations/whatsapp/logs"
check_get "Dispositivos WhatsApp" "/api/v2/integrations/whatsapp/devices"
python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
devices = payload.get("responseBody", [])
if any(not device.get("remoteId") for device in devices):
    raise SystemExit("A lista do WhatsApp retornou dispositivo local sem vínculo WebDigital.")
print(f"Dispositivos exclusivos da WebDigital: {len(devices)}")
print(f"Dispositivos conectados: {sum(device.get('connected') is True for device in devices)}")
PY
check_get "Dados para exportação de clientes" "/api/v2/clients/export-data?status=ALL&query=$client_id"
python3 - "$response_file" "$client_id" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
items = payload.get("responseBody", {}).get("items", [])
expected_id = int(sys.argv[2])
if not any(item.get("id") == expected_id for item in items):
    raise SystemExit("A rota de exportação não retornou o cliente esperado.")
print("Rota de exportação de clientes validada")
PY
check_get "Detalhes do empréstimo" "/api/v2/loans/$loan_id"
check_get "Dados para exportação de empréstimos" "/api/v2/loans/export-data?query=$loan_id"
python3 - "$response_file" "$loan_id" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
items = payload.get("responseBody", {}).get("items", [])
expected_id = int(sys.argv[2])
if len(items) != 1 or items[0].get("id") != expected_id:
    raise SystemExit("A rota de exportação não retornou o empréstimo esperado.")
print("Rota de exportação de empréstimos validada")
PY
validate_financial_contract() {
  local label="$1"
  local id="$2"
  local expected_origin="$3"
  [[ -z "$id" ]] && return
  check_get "$label" "/api/v2/loans/$id"
  python3 - "$response_file" "$expected_origin" <<'PY'
from decimal import Decimal
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
loan = payload.get("responseBody", {})
expected_origin = sys.argv[2].lower() == "true"
money = lambda key: Decimal(str(loan.get(key) or 0)).quantize(Decimal("0.01"))

if bool(loan.get("negotiatedOrigin")) != expected_origin:
    raise SystemExit("Classificação financeira do contrato divergente.")

loaned = money("loanedAmount")
interest = money("interestAmount")
discount = money("discountAmount")
negotiated = money("negotiatedAmount")
total = money("totalAmount")

if expected_origin:
    if money("originalLoanAmount") <= 0 or negotiated != loaned:
        raise SystemExit("Valores de origem/negociação do contrato refinanciado divergentes.")
else:
    if negotiated != interest:
        raise SystemExit("Valor negociado do contrato comum não corresponde ao campo financeiro legado.")

if total != loaned + interest - discount:
    raise SystemExit("Total do contrato não corresponde à regra financeira legada.")

print(f"Fluxo financeiro validado: contrato {loan.get('id')} ({'negociado' if expected_origin else 'comum'})")
PY
}
validate_financial_contract "Contrato comum" "$common_loan_id" false
validate_financial_contract "Contrato refinanciado/renovado" "$negotiated_loan_id" true
check_get "Conferências" "/api/v2/conferences?size=2"
check_get "Mensagem do contrato" "/api/v2/loans/$loan_id/message/CONTRATO"
check_get "Mensagem da dívida" "/api/v2/loans/$loan_id/message/DIVIDA"
check_get "PIX atual" "/api/v2/loans/$loan_id/pix/current"
history_end="$(date +%F)"
history_start="$(date -d '30 days ago' +%F)"
check_get "Usuários do histórico" "/api/v2/reports/history/users"
python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
users = payload.get("responseBody")
if not isinstance(users, list):
    raise SystemExit("A rota do filtro de usuários retornou formato inválido.")
print(f"Filtro do histórico validado: {len(users)} usuário(s)")
PY
check_get "Histórico de alterações" "/api/v2/reports/history?startDate=$history_start&endDate=$history_end&page=0&size=2"
python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
history = payload.get("responseBody", {})
if not isinstance(history.get("items"), list):
    raise SystemExit("A rota do histórico retornou itens inválidos.")
required = {"page", "size", "hasNext"}
missing = sorted(required.difference(history))
if missing:
    raise SystemExit(f"Histórico incompleto: {', '.join(missing)}")
print(f"Histórico validado: {len(history['items'])} linha(s) na primeira página")
PY
history_usernames="$(python3 - "$response_file" <<'PY'
import json
import sys
from urllib.parse import quote

payload = json.load(open(sys.argv[1], encoding="utf-8"))
items = payload.get("responseBody", {}).get("items", [])
users = list(dict.fromkeys(
    str(item.get("username") or "").strip()
    for item in items
    if str(item.get("username") or "").strip()
))[:2]
print(quote(",".join(users)))
PY
)"
if [[ -n "$history_usernames" ]]; then
  check_get "Histórico com múltiplos usuários" "/api/v2/reports/history?startDate=$history_start&endDate=$history_end&usernames=$history_usernames&page=0&size=2"
fi
check_get "Dados para exportação do histórico" "/api/v2/reports/history/export-data?startDate=$history_end&endDate=$history_end"
python3 - "$response_file" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
history = payload.get("responseBody", {})
if not isinstance(history.get("items"), list):
    raise SystemExit("A exportação do histórico retornou formato inválido.")
print(f"Exportação do histórico validada: {len(history['items'])} linha(s) de hoje")
PY
