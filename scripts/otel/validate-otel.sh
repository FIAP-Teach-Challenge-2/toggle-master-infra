#!/usr/bin/env bash
# Validação da Fase 4 — Parte 2 (OpenTelemetry Collector).
#
#   scripts/otel/validate-otel.sh static    # antes do push: não precisa de cluster
#   scripts/otel/validate-otel.sh cluster   # depois do sync do Argo CD e do deploy dos serviços
#
# Requisitos: bash (Git Bash/WSL/Linux/macOS), helm, kubectl e curl.
# Opcionais: docker (valida a config com o próprio collector), terraform e python3/python.
# Rode a partir da raiz do toggle-master-infra.

set -uo pipefail

MODE="${1:-static}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

NS_MON="monitoring"
NS_APP="toggle-master"
SERVICES=(auth-service flag-service targeting-service evaluation-service analytics-service)
VALUES="aws/monitoring/otel-collector/values.yaml"
APP_FILE="aws/argocd/applications/otel-collector.yaml"
TMP="$(mktemp -d)"
PIDS=()

PASS=0; FAIL=0; WARN=0
ok()   { echo "  [OK]   $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FALHA] $*"; FAIL=$((FAIL + 1)); }
warn() { echo "  [AVISO] $*"; WARN=$((WARN + 1)); }
step() { echo; echo "== $* =="; }
have() { command -v "$1" >/dev/null 2>&1; }

cleanup() {
  for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" >/dev/null 2>&1; done
  rm -rf "$TMP"
}
trap cleanup EXIT

PY=""
for c in python3 python; do
  if have "$c" && "$c" -c 'import json' >/dev/null 2>&1; then PY="$c"; break; fi
done

summary() {
  echo
  echo "Resultado: $PASS ok, $WARN aviso(s), $FAIL falha(s)"
  [ "$FAIL" -eq 0 ]
  exit $?
}

# ---------------------------------------------------------------------------
# static — o que dá para validar sem cluster
# ---------------------------------------------------------------------------
static_checks() {
  step "1. Chart do OTel Collector renderiza com o values.yaml"
  if ! have helm; then
    fail "helm não encontrado"; return
  fi
  CHART_VERSION="$(grep -m1 'targetRevision:' "$APP_FILE" | awk '{print $2}')"
  helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1
  helm repo update open-telemetry >/dev/null 2>&1
  if helm template otel-collector open-telemetry/opentelemetry-collector \
      --version "$CHART_VERSION" -n "$NS_MON" -f "$VALUES" >"$TMP/rendered.yaml" 2>"$TMP/helm.err"; then
    ok "helm template (chart $CHART_VERSION)"
  else
    fail "helm template falhou (versão $CHART_VERSION existe? confira 'helm search repo open-telemetry/opentelemetry-collector')"
    sed 's/^/         /' "$TMP/helm.err"
    return
  fi

  step "2. Recursos e pipelines esperados no manifesto renderizado"
  grep -q '^kind: DaemonSet' "$TMP/rendered.yaml" && ok "modo DaemonSet" || fail "DaemonSet não encontrado"
  SVC_NAME="$(grep -A3 '^kind: Service$' "$TMP/rendered.yaml" | awk '/^  name:/{print $2; exit}')"
  [ "$SVC_NAME" = "otel-collector" ] \
    && ok "Service 'otel-collector' (endpoint usado nos Deployments)" \
    || fail "Service se chama '$SVC_NAME' — ajuste OTEL_EXPORTER_OTLP_ENDPOINT em aws/apps/*"
  grep -q 'internalTrafficPolicy: Local' "$TMP/rendered.yaml" && ok "internalTrafficPolicy: Local" || warn "internalTrafficPolicy Local ausente"
  for p in 4317 4318; do
    grep -q "port: $p" "$TMP/rendered.yaml" && ok "porta $p exposta" || fail "porta $p ausente no Service"
  done

  # Extrai a config do collector (chave 'relay' do ConfigMap) sem depender de yq/PyYAML
  awk '/^  relay: \|/{f=1; next} f && /^    /{print substr($0, 5); next} f && NF==0{print ""; next} f{exit}' \
    "$TMP/rendered.yaml" >"$TMP/relay.yaml"
  if [ ! -s "$TMP/relay.yaml" ]; then
    fail "não consegui extrair a config 'relay' do ConfigMap"; return
  fi
  for c in filelog k8sattributes spanmetrics prometheusremotewrite 'otlphttp/loki' 'otlphttp/newrelic' memory_limiter; do
    grep -q "$c" "$TMP/relay.yaml" && ok "config contém $c" || fail "config sem $c"
  done
  awk '/^  pipelines:/{f=1} f' "$TMP/relay.yaml" | grep -q 'filelog' \
    && ok "preset logsCollection ligou o filelog no pipeline de logs" \
    || fail "filelog não está em nenhum pipeline"

  step "3. Collector valida a própria config (docker)"
  if have docker && docker info >/dev/null 2>&1; then
    IMAGE="$(grep -m1 'image: .*opentelemetry-collector' "$TMP/rendered.yaml" | awk '{print $2}' | tr -d '"')"
    if docker run --rm \
        -e NEW_RELIC_LICENSE_KEY=dummy -e MY_POD_IP=127.0.0.1 -e K8S_NODE_NAME=node \
        "$IMAGE" validate --config="yaml:$(cat "$TMP/relay.yaml")" >"$TMP/validate.log" 2>&1; then
      ok "otelcol validate ($IMAGE)"
    else
      fail "otelcol validate falhou ($IMAGE)"; sed 's/^/         /' "$TMP/validate.log" | tail -20
    fi
  else
    warn "docker indisponível — pulei 'otelcol validate'"
  fi

  step "4. Deployments com as variáveis OTEL_* (kustomize)"
  if have kubectl; then
    for s in "${SERVICES[@]}"; do
      if kubectl kustomize "aws/apps/$s" >"$TMP/$s.yaml" 2>/dev/null; then
        grep -q "value: \"\?$s\"\?$" "$TMP/$s.yaml" && grep -q 'OTEL_EXPORTER_OTLP_ENDPOINT' "$TMP/$s.yaml" \
          && grep -q 'otel-collector.monitoring.svc' "$TMP/$s.yaml" \
          && ok "$s: OTEL_SERVICE_NAME + endpoint do collector" \
          || fail "$s: variáveis OTEL_* ausentes ou incorretas"
      else
        fail "kubectl kustomize aws/apps/$s falhou"
      fi
    done
    kubectl kustomize aws/monitoring/dashboards >"$TMP/dash.yaml" 2>/dev/null \
      && grep -q 'traces_span_metrics_calls_total' "$TMP/dash.yaml" \
      && grep -q 'k8s_namespace_name' "$TMP/dash.yaml" \
      && ok "dashboard com painéis OTel e logs via labels OTLP" \
      || fail "dashboard sem os painéis OTel"
  else
    fail "kubectl não encontrado"
  fi
  if [ -n "$PY" ]; then
    "$PY" -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' \
      aws/monitoring/dashboards/togglemaster-overview.json && ok "dashboard JSON válido" || fail "dashboard JSON inválido"
  fi

  step "5. Prometheus aceita remote write"
  grep -q 'enableRemoteWriteReceiver: true' aws/monitoring/kube-prometheus-stack/values.yaml \
    && ok "enableRemoteWriteReceiver: true" || fail "habilite prometheus.prometheusSpec.enableRemoteWriteReceiver"

  step "6. Terraform (secret otel-apm-credentials)"
  grep -q 'otel_apm_credentials' terraform/platform/main.tf && ok "recurso do secret presente" || fail "secret ausente em terraform/platform"
  if have terraform; then
    terraform -chdir=terraform/platform fmt -check >/dev/null && ok "terraform fmt" || fail "rode: terraform -chdir=terraform/platform fmt"
    if [ -d terraform/platform/.terraform ]; then
      terraform -chdir=terraform/platform validate >/dev/null && ok "terraform validate" || fail "terraform validate falhou"
    else
      warn "terraform/platform sem init — pulei validate"
    fi
  else
    warn "terraform não encontrado — pulei fmt/validate"
  fi

  step "7. Promtail"
  if [ -f aws/argocd/applications/promtail.yaml ]; then
    warn "Promtail ainda ativo: remova após validar os logs pelo collector (logs duplicados no Loki)"
  else
    ok "Promtail removido"
  fi
}

# ---------------------------------------------------------------------------
# cluster — validação ponta a ponta no EKS
# ---------------------------------------------------------------------------
port_forward() { # svc porta_local porta_remota
  kubectl -n "$NS_MON" port-forward "svc/$1" "$2:$3" >/dev/null 2>&1 &
  PIDS+=("$!")
  for _ in $(seq 1 20); do
    curl -s -o /dev/null "http://127.0.0.1:$2" && return 0
    sleep 1
  done
  return 1
}

prom_query() { # expr → imprime "label=valor" por série
  curl -s -G "http://127.0.0.1:19090/api/v1/query" --data-urlencode "query=$1" >"$TMP/prom.json"
  if [ -n "$PY" ]; then
    "$PY" -c '
import json,sys
d=json.load(open(sys.argv[1]))
for r in d.get("data",{}).get("result",[]):
    m=r["metric"]; print(m.get("service_name", m.get("__name__","?")), r["value"][1])
' "$TMP/prom.json"
  else
    grep -o '"service_name":"[^"]*"' "$TMP/prom.json" | cut -d'"' -f4
  fi
}

cluster_checks() {
  step "1. Contexto do kubectl"
  if ! kubectl get nodes >/dev/null 2>&1; then
    fail "sem acesso ao cluster (aws eks update-kubeconfig --region us-east-1 --name toggle-master-dev-eks; credenciais da AWS Academy expiradas?)"
    return
  fi
  ok "cluster acessível: $(kubectl config current-context)"

  step "2. Applications do Argo CD"
  for app in otel-collector kube-prometheus-stack loki monitoring-dashboards "${SERVICES[@]}"; do
    st="$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)"
    [ "$st" = "Synced/Healthy" ] && ok "$app $st" || fail "$app ${st:-não encontrada}"
  done

  step "3. OTel Collector (DaemonSet)"
  DS="$(kubectl -n "$NS_MON" get ds -l app.kubernetes.io/instance=otel-collector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  if [ -z "$DS" ]; then
    fail "DaemonSet do collector não encontrado"; return
  fi
  desired="$(kubectl -n "$NS_MON" get ds "$DS" -o jsonpath='{.status.desiredNumberScheduled}')"
  ready="$(kubectl -n "$NS_MON" get ds "$DS" -o jsonpath='{.status.numberReady}')"
  [ "$desired" = "$ready" ] && [ "${ready:-0}" -gt 0 ] && ok "ds/$DS $ready/$desired pods prontos (1 por nó)" || fail "ds/$DS $ready/$desired prontos"

  key_len="$(kubectl -n "$NS_MON" get secret otel-apm-credentials -o jsonpath='{.data.new-relic-license-key}' 2>/dev/null | wc -c)"
  [ "${key_len:-0}" -gt 10 ] && ok "secret otel-apm-credentials com a license key" \
    || fail "secret otel-apm-credentials vazio/ausente (terraform.tfvars: new_relic_license_key + terraform apply)"

  kubectl -n "$NS_MON" logs "ds/$DS" --since=10m >"$TMP/col.log" 2>/dev/null
  errs="$(grep -ciE 'Exporting failed|error.*export|Permanent error' "$TMP/col.log")"
  if [ "${errs:-0}" -eq 0 ]; then
    ok "sem erros de export nos últimos 10 min"
  else
    fail "$errs erro(s) de export no collector (últimos):"
    grep -iE 'Exporting failed|error.*export|Permanent error' "$TMP/col.log" | tail -5 | cut -c1-240 | sed 's/^/         /'
  fi

  step "4. Serviços instrumentados (variáveis no pod em execução)"
  for s in "${SERVICES[@]}"; do
    env_name="$(kubectl -n "$NS_APP" get deploy "$s" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OTEL_SERVICE_NAME")].value}' 2>/dev/null)"
    [ "$env_name" = "$s" ] && ok "$s com OTEL_SERVICE_NAME" || fail "$s sem OTEL_SERVICE_NAME (Argo sincronizou?)"
  done

  step "5. Gerando tráfego (/evaluate → flag/targeting → auth, SQS → analytics)"
  LB="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"
  FLAG="${FLAG:-test-flag}"
  if [ -n "$LB" ]; then
    codes=""
    for i in $(seq 1 40); do
      codes+="$(curl -sk -o /dev/null -w '%{http_code}' "https://$LB/evaluate?user_id=u$i&flag_name=$FLAG") "
    done
    echo "  status HTTP: $(echo "$codes" | tr ' ' '\n' | sort | uniq -c | tr '\n' ' ')"
    ok "40 requisições em https://$LB/evaluate (FLAG=$FLAG)"
    echo "  aguardando 75s (flush do spanmetrics + scrape + janela do rate)..."
    sleep 75
  else
    warn "LoadBalancer do ingress não encontrado — gere tráfego manualmente"
  fi

  step "6. Métricas no Prometheus (via OTel Collector)"
  if port_forward kube-prometheus-stack-prometheus 19090 9090; then
    prom_query 'sum(rate(traces_span_metrics_calls_total[5m])) by (service_name)' >"$TMP/svc.txt"
    if [ -s "$TMP/svc.txt" ]; then
      ok "spanmetrics chegando: $(awk '{print $1}' "$TMP/svc.txt" | sort | tr '\n' ' ')"
      for s in "${SERVICES[@]}"; do
        grep -q "^$s" "$TMP/svc.txt" && ok "  $s com spans" || warn "  $s ainda sem spans (sem tráfego até ele?)"
      done
    else
      fail "nenhuma série traces_span_metrics_calls_total (remote write habilitado? erros no collector?)"
    fi
    prom_query 'count({__name__=~"http_server_request_duration_seconds_count|http_server_duration_milliseconds_count"}) by (service_name)' >"$TMP/http.txt"
    [ -s "$TMP/http.txt" ] && ok "métricas HTTP do SDK: $(awk '{print $1}' "$TMP/http.txt" | sort | tr '\n' ' ')" \
      || warn "métricas http.server.* do SDK ainda não apareceram"
  else
    fail "port-forward para o Prometheus falhou"
  fi

  step "7. Logs no Loki (filelog → OTLP)"
  if port_forward loki 13100 3100; then
    curl -s -G "http://127.0.0.1:13100/loki/api/v1/query_range" \
      --data-urlencode 'query={k8s_namespace_name="toggle-master"}' \
      --data-urlencode 'limit=5' --data-urlencode "since=15m" >"$TMP/loki.json"
    if grep -q '"values":\[\["' "$TMP/loki.json"; then
      ok "logs do namespace toggle-master no Loki"
    else
      fail "Loki sem logs para {k8s_namespace_name=\"toggle-master\"}"
    fi
    curl -s -G "http://127.0.0.1:13100/loki/api/v1/label/service_name/values" --data-urlencode "since=15m" >"$TMP/loki-svc.json"
    echo "  service_name no Loki: $(grep -o '"[a-z-]*-service"' "$TMP/loki-svc.json" | tr -d '"' | sort -u | tr '\n' ' ')"
  else
    fail "port-forward para o Loki falhou"
  fi

  step "8. New Relic (verificação manual)"
  echo "  - one.newrelic.com > APM & Services: os 5 serviços listados"
  echo "  - Service Map: evaluation → flag/targeting → auth; evaluation → analytics (SQS)"
  echo "  - Distributed Tracing: abra um 'GET /evaluate' e confira os spans dos 5 serviços"
}

case "$MODE" in
  static)  static_checks ;;
  cluster) cluster_checks ;;
  *) echo "uso: $0 [static|cluster]"; exit 2 ;;
esac
summary
