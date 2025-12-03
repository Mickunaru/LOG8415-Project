#!/bin/bash

mkdir -p logs

cd terraform

GATEKEEPER=$(terraform output -raw gatekeeper_public_ip)
GATEKEEPER_API_KEY=$(terraform output -raw gatekeeper_api_key)

STRATEGIES=("direct" "random" "custom")

cd ..
for STRATEGY in "${STRATEGIES[@]}"; do
    echo "Sending 1000 READ requests with strategy \"$STRATEGY\""
    for i in {1..1000}; do
        curl -s -w "\n" -X POST "http://$GATEKEEPER/query" \
            -H "Content-Type: application/json" \
            -H "X-API-KEY: $GATEKEEPER_API_KEY" \
            -d "{\"query\": \"SELECT * FROM actor LIMIT 1;\", \"strategy\": \"$STRATEGY\"}" \
            >> "logs/${STRATEGY}_reads.log"
    done

    echo "Sending 1000 WRITE requests with strategy \"$STRATEGY\""

    for i in {1..1000}; do
        curl -s -w "\n" -X POST "http://$GATEKEEPER/query" \
            -H "Content-Type: application/json" \
            -H "X-API-KEY: $GATEKEEPER_API_KEY" \
            -d "{\"query\": \"INSERT INTO actor(first_name, last_name) VALUES('Load', 'Test$i');\", \"strategy\": \"$STRATEGY\"}" \
            >> "logs/${STRATEGY}_writes.log"
    done

done

echo "Load test completed. Logs are saved in the logs/ directory."