#!/bin/bash

set -e
exec > /var/log/setup_gatekeeper.log 2>&1

export PROXY_IP="${proxy_private_ip}"
export PROXY_PORT=5000

apt-get update
apt-get install -y python3 python3-pip
pip3 install fastapi uvicorn requests

mkdir -p /opt/gatekeeper

cat > /opt/gatekeeper/app.py <<'EOF'
from fastapi import FastAPI, Request, Response
import requests
import os

app = FastAPI()

PROXY_IP = os.getenv("PROXY_IP")
PROXY_PORT = os.getenv("PROXY_PORT")
PROXY_URL = f"http://{PROXY_IP}:{PROXY_PORT}"

UNSAFE_COMMANDS = [
    "drop",
    "truncate",
    "delete all"
]

def is_safe(content: str) -> bool:
    c = content.lower()
    return not ("drop" in c or "truncate" in c or "delete all" in c)

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/execute")
async def execute_endpoint(request: Request):
    body_bytes = await request.body()
    body_str = body_bytes.decode() if body_bytes else ""

    if not body_str:
        return Response("empty body", status_code=400)
    if not is_safe(body_str):
        return Response("unsafe", status_code=400)

    try:
        response = requests.post(
            PROXY_URL,
            data=body_bytes,
            timeout=5
        )
    except requests.RequestException as e:
        return Response(f"proxy error: {e}", status_code=502)

    return Response(
        content=response.content,
        status_code=response.status_code,
    )
EOF

uvicorn app:app --app-dir /opt/gatekeeper --host 0.0.0.0 --port 80 > /var/log/gatekeeper.log 2>&1 &
echo READY > /var/run/ready
