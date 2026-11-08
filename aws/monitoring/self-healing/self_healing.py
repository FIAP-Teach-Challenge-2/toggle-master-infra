import json
import logging
import os
import ssl
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICE_ACCOUNT_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"
KUBERNETES_API = "https://kubernetes.default.svc"
RESTART_ANNOTATION = "kubectl.kubernetes.io/restartedAt"

PORT = int(os.environ.get("PORT", "8080"))
TARGET_NAMESPACE = os.environ.get("TARGET_NAMESPACE", "toggle-master")
ALLOWED_DEPLOYMENTS = {
    name.strip()
    for name in os.environ.get("ALLOWED_DEPLOYMENTS", "").split(",")
    if name.strip()
}
COOLDOWN_SECONDS = int(os.environ.get("COOLDOWN_SECONDS", "300"))
DISCORD_WEBHOOK_URL_FILE = os.environ.get("DISCORD_WEBHOOK_URL_FILE", "")
HTTP_TIMEOUT_SECONDS = 10

logging.basicConfig(stream=sys.stdout, level=logging.INFO, format="%(message)s")
logger = logging.getLogger("self-healing")

last_restart_by_deployment = {}
cooldown_lock = threading.Lock()


def log_event(event, **fields):
    record = {"ts": datetime.now(timezone.utc).isoformat(), "event": event, **fields}
    logger.info(json.dumps(record, ensure_ascii=False))


def read_file(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read().strip()


def kubernetes_ssl_context():
    return ssl.create_default_context(cafile=f"{SERVICE_ACCOUNT_DIR}/ca.crt")


def rollout_restart(deployment):
    restarted_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    patch = {"spec": {"template": {"metadata": {"annotations": {RESTART_ANNOTATION: restarted_at}}}}}
    request = urllib.request.Request(
        f"{KUBERNETES_API}/apis/apps/v1/namespaces/{TARGET_NAMESPACE}/deployments/{deployment}",
        data=json.dumps(patch).encode("utf-8"),
        method="PATCH",
        headers={
            "Authorization": f"Bearer {read_file(f'{SERVICE_ACCOUNT_DIR}/token')}",
            "Content-Type": "application/strategic-merge-patch+json",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, context=kubernetes_ssl_context(), timeout=HTTP_TIMEOUT_SECONDS) as response:
        body = json.loads(response.read())
    return restarted_at, body["metadata"].get("generation")


def notify_discord(message):
    if not DISCORD_WEBHOOK_URL_FILE or not os.path.exists(DISCORD_WEBHOOK_URL_FILE):
        log_event("discord_skipped", reason="webhook file not mounted")
        return
    webhook_url = read_file(DISCORD_WEBHOOK_URL_FILE)
    if not webhook_url:
        log_event("discord_skipped", reason="webhook url empty")
        return
    request = urllib.request.Request(
        webhook_url,
        data=json.dumps({"username": "ToggleMaster Self-Healing", "content": message}).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json", "User-Agent": "ToggleMaster-SelfHealing/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS):
            log_event("discord_notified")
    except (urllib.error.URLError, TimeoutError) as error:
        log_event("discord_failed", error=str(error))


def reserve_cooldown(deployment):
    now = time.monotonic()
    with cooldown_lock:
        last_restart = last_restart_by_deployment.get(deployment)
        if last_restart is not None and now - last_restart < COOLDOWN_SECONDS:
            return int(COOLDOWN_SECONDS - (now - last_restart))
        last_restart_by_deployment[deployment] = now
        return 0


def release_cooldown(deployment):
    with cooldown_lock:
        last_restart_by_deployment.pop(deployment, None)


def heal(alert):
    labels = alert.get("labels", {})
    alertname = labels.get("alertname", "unknown")
    deployment = labels.get("deployment", "")

    if alert.get("status") != "firing" or labels.get("self_heal") != "true":
        return {"alertname": alertname, "deployment": deployment, "action": "ignored"}

    if deployment not in ALLOWED_DEPLOYMENTS:
        log_event("restart_rejected", alertname=alertname, deployment=deployment, reason="deployment not allowed")
        return {"alertname": alertname, "deployment": deployment, "action": "rejected"}

    remaining = reserve_cooldown(deployment)
    if remaining:
        log_event("restart_skipped", alertname=alertname, deployment=deployment, cooldown_remaining_s=remaining)
        return {"alertname": alertname, "deployment": deployment, "action": "cooldown"}

    log_event("restart_started", alertname=alertname, deployment=deployment, namespace=TARGET_NAMESPACE)
    try:
        restarted_at, generation = rollout_restart(deployment)
    except urllib.error.HTTPError as error:
        release_cooldown(deployment)
        detail = error.read().decode("utf-8", errors="replace")
        log_event("restart_failed", alertname=alertname, deployment=deployment, status=error.code, error=detail)
        return {"alertname": alertname, "deployment": deployment, "action": "failed"}
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        release_cooldown(deployment)
        log_event("restart_failed", alertname=alertname, deployment=deployment, error=str(error))
        return {"alertname": alertname, "deployment": deployment, "action": "failed"}

    log_event(
        "restart_succeeded",
        alertname=alertname,
        deployment=deployment,
        namespace=TARGET_NAMESPACE,
        restarted_at=restarted_at,
        generation=generation,
    )
    notify_discord(
        f"🛠️ **Self-healing executado** — `kubectl rollout restart deployment/{deployment}` "
        f"no namespace `{TARGET_NAMESPACE}` em {restarted_at}.\n"
        f"Gatilho: alerta `{alertname}` — {alert.get('annotations', {}).get('summary', '')}"
    )
    return {"alertname": alertname, "deployment": deployment, "action": "restarted", "restarted_at": restarted_at}


class AlertWebhookHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.respond(200, {"status": "ok"})
            return
        self.respond(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/alerts":
            self.respond(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length))
        except (ValueError, json.JSONDecodeError) as error:
            log_event("payload_invalid", error=str(error))
            self.respond(400, {"error": "invalid payload"})
            return

        alerts = payload.get("alerts", [])
        log_event("webhook_received", receiver=payload.get("receiver"), status=payload.get("status"), alerts=len(alerts))
        results = [heal(alert) for alert in alerts]
        failed = any(result["action"] == "failed" for result in results)
        self.respond(502 if failed else 200, {"results": results})

    def respond(self, status, body):
        encoded = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format, *args):
        return


def main():
    log_event(
        "server_started",
        port=PORT,
        namespace=TARGET_NAMESPACE,
        allowed_deployments=sorted(ALLOWED_DEPLOYMENTS),
        cooldown_s=COOLDOWN_SECONDS,
    )
    ThreadingHTTPServer(("0.0.0.0", PORT), AlertWebhookHandler).serve_forever()


if __name__ == "__main__":
    main()
