# LOG8415-Project

Cloud Design Patterns: Implementing a DB Cluster

Example curl request:

```bash
curl -X POST http://$GATEKEEPER_IP/query \
     -H "Content-Type: application/json" \
     -H "X-API-KEY: $GATEKEEPER_API_KEY" \
     -d '{"query": "SELECT * FROM actor LIMIT 5;", "strategy": "direct"}'
```
