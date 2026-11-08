#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-toggle-master}"
RATE_PER_SECOND="${RATE_PER_SECOND:-5}"
DURATION_SECONDS="${DURATION_SECONDS:-600}"

LB="${LB:-$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')}"
SERVICE_API_KEY="$(kubectl -n "$NAMESPACE" get secret toggle-master-secrets -o jsonpath='{.data.SERVICE_API_KEY}' | base64 -d)"

if [ -z "$LB" ]; then
  echo "não encontrei o hostname do Load Balancer do ingress-nginx" >&2
  exit 1
fi

echo "gerando ~${RATE_PER_SECOND} req/s em http://$LB/validate por ${DURATION_SECONDS}s (Ctrl+C para parar)"

interval="$(awk -v r="$RATE_PER_SECOND" 'BEGIN { printf "%.3f", 1 / r }')"
end=$((SECONDS + DURATION_SECONDS))
declare -A counts=()

while [ "$SECONDS" -lt "$end" ]; do
  for _ in $(seq 1 "$RATE_PER_SECOND"); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H "Authorization: Bearer $SERVICE_API_KEY" "http://$LB/validate" || true)"
    counts[$code]=$(( ${counts[$code]:-0} + 1 ))
    sleep "$interval"
  done
  summary=""
  for status in "${!counts[@]}"; do
    summary+="$status=${counts[$status]} "
  done
  printf '%s  %s\n' "$(date +%H:%M:%S)" "$summary"
  counts=()
done
