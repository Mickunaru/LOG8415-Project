#!/bin/bash
set -e
exec > /var/log/setup_proxy.log 2>&1

export MANAGER_IP="${manager_ip}"
export WORKER1_IP="${worker1_ip}"
export WORKER2_IP="${worker2_ip}"
export WORKER_IPS="${worker1_ip},${worker2_ip}"

apt-get update
apt-get install -y python3 python3-pip
pip3 install fastapi uvicorn requests

mkdir -p /opt/proxy

cat > /opt/proxy/app.py << 'EOF'
from fastapi import FastAPI, Request
import os
import random
import time
import socket

app = FastAPI()

PING_TIMEOUT = 0.2
MANAGER_IP = os.getenv("MANAGER_IP")
WORKER_IPS = os.getenv("WORKER_IPS").split(",")
WRITE_KEYWORDS = {"update", "insert", "delete", "replace", "set"}

def is_write_operation(payload: dict) -> bool:
    query = json.dumps(payload).lower()
    return any(word in query for word in WRITE_KEYWORDS)

def ping_worker(ip: str) -> float:
    start = time.time()
    try:
        with socket.create_connection((ip, 3306), timeout=PING_TIMEOUT):
            return time.time() - start
    except Exception:
        return float('inf')

def handle_direct_strategy(payload: dict) -> dict:
    return {
        "forwarded_to": "manager",
        "target_ip": MANAGER_IP,
        "target_port": 3306
    }

def handle_random_strategy(payload: dict) -> dict:
    if is_write_operation(payload):
        return {
            "forwarded_to": "manager",
            "target_ip": MANAGER_IP,
            "target_port": 3306
        }
    else:
        chosen = random.choice(WORKER_IPS)
        return {
            "forwarded_to": "worker",
            "target_ip": chosen,
            "target_port": 3306
        }

def handle_custom_strategy(payload: dict) -> dict:
    if is_write_operation(payload):
        return {
            "forwarded_to": "manager",
            "target_ip": MANAGER_IP,
            "target_port": 3306
        }

    worker_latencies = []
    for worker_ip in WORKER_IPS:
        latency = ping_worker(worker_ip)
        worker_latencies.append((worker_ip, latency))

    worker_ip, best_latency = min(worker_latencies, key=lambda x: x[1])

    if best_latency == float("inf"):
        return {
            "forwarded_to": "manager",
            "target_ip": MANAGER_IP,
            "target_port": 3306
        }

    return {
        "forwarded_to": "worker",
        "target_ip": worker_ip,
        "target_port": 3306,
    }

@app.post("/query")
async def handle_query(request: Request):
    body_bytes = await request.body()
    strategy = request.headers.get("X-Strategy", "direct").lower()
    
    if not body_bytes:
        return Response("empty query", status_code=400)

    sql_query = body_bytes.decode()

    if strategy == "direct":
        return handle_direct_strategy(sql_query)
    elif strategy == "random":
        return handle_random_strategy(sql_query)
    elif strategy == "custom":
        return handle_custom_strategy(sql_query)
    else:
        return "invalid strategy", 400
EOF

uvicorn app:app --app-dir /opt/proxy --host 0.0.0.0 --port 5000 > /var/log/proxy.log 2>&1 &
echo READY > /var/run/ready
