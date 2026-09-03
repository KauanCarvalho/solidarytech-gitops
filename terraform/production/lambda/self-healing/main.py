"""Self-Healing bridge: recebe o webhook do Alertmanager e aciona, via
repository_dispatch, o workflow .github/workflows/self-healing.yml no
repositorio solidarytech-app - fechando o loop "alerta disparou -> self-
healing roda sozinho", sem intervencao humana.
"""
import base64
import json
import os
import urllib.error
import urllib.request

GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
GITHUB_REPO = os.environ["GITHUB_REPO"]
WEBHOOK_TOKEN = os.environ["WEBHOOK_TOKEN"]

# Neste projeto o namespace do K8s e sempre igual ao nome do servico/deployment
# (ver k8s/apps/00-namespaces.yaml no repo gitops), entao o label "namespace"
# do alerta ja identifica sozinho qual Deployment reiniciar.
KNOWN_NAMESPACES = {
    "ngo-service",
    "donation-service",
    "volunteer-service",
}


def handler(event, context):
    query = event.get("queryStringParameters") or {}
    if query.get("token") != WEBHOOK_TOKEN:
        return _response(403, {"message": "invalid token"})

    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")

    payload = json.loads(body)

    if payload.get("status") != "firing":
        return _response(200, {"message": "ignored: alertmanager status != firing"})

    triggered = []
    failed = []

    for alert in payload.get("alerts", []):
        if alert.get("status") != "firing":
            continue

        labels = alert.get("labels", {})
        namespace = labels.get("namespace")
        alertname = labels.get("alertname", "unknown")

        if namespace not in KNOWN_NAMESPACES:
            print(
                f"ignorando alerta '{alertname}': namespace '{namespace}' "
                "nao mapeia para um deployment conhecido"
            )
            continue

        try:
            _dispatch(service=namespace, namespace=namespace, alertname=alertname)
            triggered.append(f"{alertname}/{namespace}")
        except urllib.error.HTTPError as exc:
            print(f"falha ao disparar repository_dispatch para {namespace}: {exc.code} {exc.read()}")
            failed.append(namespace)

    return _response(502 if failed else 200, {"triggered": triggered, "failed": failed})


def _dispatch(service, namespace, alertname):
    url = f"https://api.github.com/repos/{GITHUB_REPO}/dispatches"
    data = json.dumps(
        {
            "event_type": "alert-firing",
            "client_payload": {
                "service": service,
                "namespace": namespace,
                "alertname": alertname,
            },
        }
    ).encode("utf-8")

    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Authorization", f"Bearer {GITHUB_TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Content-Type", "application/json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")

    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload),
    }
