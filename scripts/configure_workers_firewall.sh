#!/bin/bash
set -e

cd terraform

PROXY_PRIVATE_IP=$(terraform output -raw proxy_private_ip)

WORKER1_ID=$(terraform output -raw worker1_instance_id)
WORKER2_ID=$(terraform output -raw worker2_instance_id)

WORKER_IDS=("$WORKER1_ID" "$WORKER2_ID")

FIREWALL_SCRIPT=$(cat << EOF
#!/bin/bash
set -e

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow from ${PROXY_PRIVATE_IP} to any port 3306 proto tcp

ufw --force enable
EOF
)

for ID in "${WORKER_IDS[@]}"; do
  aws ssm send-command \
  --instance-ids "$ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["'"$FIREWALL_SCRIPT"'"]' \
  --output text
done
