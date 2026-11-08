#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-toggle-master}"
ACTION="${1:-}"
LOCAL_PORT_BASE="${LOCAL_PORT_BASE:-18001}"

case "$ACTION" in
  on) METHOD=POST ;;
  off) METHOD=DELETE ;;
  status) METHOD=GET ;;
  *)
    echo "uso: $0 on|off|status" >&2
    exit 2
    ;;
esac

MASTER_KEY="$(kubectl -n "$NAMESPACE" get secret toggle-master-secrets -o jsonpath='{.data.MASTER_KEY}' | base64 -d)"
mapfile -t PODS < <(kubectl -n "$NAMESPACE" get pods -l app=auth-service --field-selector=status.phase=Running -o name)

if [ "${#PODS[@]}" -eq 0 ]; then
  echo "nenhum pod do auth-service em Running no namespace $NAMESPACE" >&2
  exit 1
fi

port="$LOCAL_PORT_BASE"
for pod in "${PODS[@]}"; do
  kubectl -n "$NAMESPACE" port-forward "$pod" "$port:8001" >/dev/null 2>&1 &
  pf_pid=$!
  trap 'kill "$pf_pid" 2>/dev/null || true' EXIT

  for _ in $(seq 1 20); do
    if curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done

  response="$(curl -sS -X "$METHOD" -H "Authorization: Bearer $MASTER_KEY" "http://127.0.0.1:$port/admin/chaos")"
  echo "$pod -> $response"

  kill "$pf_pid" 2>/dev/null || true
  wait "$pf_pid" 2>/dev/null || true
  trap - EXIT
  port=$((port + 1))
done
