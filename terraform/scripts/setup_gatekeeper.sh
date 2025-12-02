#!/bin/bash

set -e
exec > /var/log/setup_gatekeeper.log 2>&1

export PROXY_IP="${proxy_private_ip}"
export PROXY_PORT=5000
export GATEKEEPER_API_KEY="${gatekeeper_api_key}"

apt-get update
apt-get install -y python3 python3-pip
pip3 install fastapi uvicorn requests

mkdir -p /opt/gatekeeper

cat > /opt/gatekeeper/app.py <<'EOF'
from fastapi import FastAPI, Request, Response, HTTPException
import requests
import os
import json

app = FastAPI()

PROXY_IP = os.getenv("PROXY_IP")
PROXY_PORT = os.getenv("PROXY_PORT")
PROXY_URL = f"http://{PROXY_IP}:{PROXY_PORT}"

API_KEY = os.getenv("GATEKEEPER_API_KEY")

UNSAFE_COMMANDS = [
    "drop",
    "truncate",
    "delete all"
]

def is_safe(query: str) -> bool:
    q = query.lower()
    return not any(cmd in q for cmd in UNSAFE_COMMANDS)

def check_auth(request: Request):
    key = request.headers.get("X-API-KEY")
    if key != API_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized: Invalid API key")

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/query")
async def query_endpoint(request: Request):
    check_auth(request)

    try:
        body = await request.json()
    except:
        raise HTTPException(status_code=400, detail="Invalid JSON")

    if "query" not in body:
        raise HTTPException(status_code=400, detail="Missing 'query' field")

    query = body["query"]
    strategy = body["strategy"] if "strategy" in body else "direct"

    if not is_safe(query):
        raise HTTPException(status_code=400, detail="Unsafe SQL detected")

    payload = {
        "query": query,
        "strategy": strategy
    }

    try:
        resp = requests.post(
            f"{PROXY_URL}/query",
            json=payload,
            timeout=5
        )
    except requests.RequestException as e:
        raise HTTPException(status_code=502, detail=f"Proxy unreachable: {e}")

    return Response(
        content=resp.content,
        status_code=resp.status_code,
        media_type="application/json"
    )
EOF

uvicorn app:app --app-dir /opt/gatekeeper --host 0.0.0.0 --port 80 > /var/log/gatekeeper.log 2>&1 &
echo READY > /var/run/ready
