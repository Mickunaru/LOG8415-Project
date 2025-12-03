#!/bin/bash
set -e

mkdir -p logs

cd terraform

MANAGER_ID=$(terraform output -raw manager_instance_id)
WORKER_ID1=$(terraform output -raw worker1_instance_id)
WORKER_ID2=$(terraform output -raw worker2_instance_id)

INSTANCE_IDS=("$MANAGER_ID" "$WORKER_ID1" "$WORKER_ID2")
INSTANCE_NAMES=("manager" "worker1" "worker2")

cd ..
for i in "${!INSTANCE_IDS[@]}"; do
    INSTANCE_ID=${INSTANCE_IDS[$i]}
    INSTANCE_NAME=${INSTANCE_NAMES[$i]}
    echo "Collecting Sysbench results from $INSTANCE_NAME (ID: $INSTANCE_ID)"

    COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["cat /var/log/sysbench_results.log"]' \
    --query "Command.CommandId" \
    --output text)

    sleep 5

    aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query "StandardOutputContent" \
    --output text | tee logs/sysbench_${INSTANCE_NAME}_output.log
done


