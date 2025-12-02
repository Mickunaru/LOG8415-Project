#!/bin/bash
set -e
exec > /var/log/setup_proxy.log 2>&1

export MANAGER_IP="${manager_ip}"
export WORKER1_IP="${worker1_ip}"
export WORKER2_IP="${worker2_ip}"
export WORKER_IPS="${worker1_ip},${worker2_ip}"
export MYSQL_PROXY_PWD="${MYSQL_PROXY_PWD}"

apt-get update
apt-get install -y python3 python3-pip
pip3 install fastapi uvicorn requests mysql-connector-python

mkdir -p /opt/proxy

cat > /opt/proxy/app.py << 'EOF'
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
from fastapi.encoders import jsonable_encoder
import os
import random
import time
import mysql.connector
from mysql.connector import pooling, Error

app = FastAPI()

PING_TIMEOUT = 0.2
MANAGER_IP = os.getenv("MANAGER_IP")
WORKER_IPS = os.getenv("WORKER_IPS").split(",")

MYSQL_USER = "proxy_user"
MYSQL_PASSWORD = os.getenv("MYSQL_PROXY_PWD")
MYSQL_PORT = 3306

POOL_SIZE = 5
QUERY_TIMEOUT = 5

pools = {}

def get_pool(host, port=MYSQL_PORT):
    key = f"{host}:{port}"
    if key in pools:
        return pools[key]

    pool = pooling.MySQLConnectionPool(
        pool_name=f"pool_{host.replace('.', '_')}",
        pool_size=POOL_SIZE,
        pool_reset_session=True,
        host=host,
        port=port,
        user=MYSQL_USER,
        password=MYSQL_PASSWORD,
        connection_timeout=QUERY_TIMEOUT
    )
    pools[key] = pool
    return pool

def execute_sql(host, query, is_write):
    conn = None
    try:
        pool = get_pool(host)
        conn = pool.get_connection()
        cur = conn.cursor(dictionary=True)

        cur.execute("USE sakila;")
        cur.execute(query)

        if is_write:
            conn.commit()
            return {"ok": True, "rows_affected": cur.rowcount}

        rows = cur.fetchall()
        cur.close()
        return {"ok": True, "rows": rows}

    except Error as e:
        raise HTTPException(status_code=502, detail=f"MySQL error on {host}: {str(e)}")

    finally:
        if conn:
            conn.close()

def is_write_operation(query: str) -> bool:
    q = query.strip().lower()
    return q.startswith(("update", "insert", "delete", "replace", "set", "create", "alter", "drop"))

def ping_worker(ip: str) -> float:
    start = time.time()
    try:
        result = execute_sql(ip, "SELECT 1", False)
        if result["ok"]:
            return time.time() - start
        return float("inf")
    except Exception:
        return float("inf")

def handle_strategy(query: str, strategy: str):
    if strategy == "direct":
        return {"target_ip": MANAGER_IP, "target_port": 3306, "forwarded_to": "manager"}

    if strategy == "random":
        if is_write_operation(query):
            return {"target_ip": MANAGER_IP, "target_port": 3306, "forwarded_to": "manager"}
        ip = random.choice(WORKER_IPS)
        return {"target_ip": ip, "target_port": 3306, "forwarded_to": "worker"}

    if strategy == "custom":
        if is_write_operation(query):
            return {"target_ip": MANAGER_IP, "target_port": 3306, "forwarded_to": "manager"}

        latencies = [(ip, ping_worker(ip)) for ip in WORKER_IPS]
        worker_ip, best_worker_latency = min(latencies, key=lambda x: x[1])

        if best_worker_latency == float("inf"):
            return {"target_ip": MANAGER_IP, "target_port": 3306, "forwarded_to": "manager"}

        return {"target_ip": worker_ip, "target_port": 3306, "forwarded_to": "worker"}

    raise HTTPException(status_code=400, detail="Invalid strategy")

@app.post("/query")
async def handle_query(request: Request):
    body = await request.json()

    if "query" not in body:
        raise HTTPException(status_code=400, detail="Missing 'query' field")

    query = body["query"]
    strategy = body.get("strategy", "direct").lower()

    target = handle_strategy(query, strategy)
    result = execute_sql(target["target_ip"], query, is_write_operation(query))
    target["result"] = result

    return JSONResponse(jsonable_encoder(target))
EOF

uvicorn app:app --app-dir /opt/proxy --host 0.0.0.0 --port 5000 > /var/log/proxy.log 2>&1 &
echo READY > /var/run/ready
