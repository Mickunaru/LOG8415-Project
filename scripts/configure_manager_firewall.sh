#!/bin/bash
set -e

cd terraform

PROXY_PRIVATE_IP=$(terraform output -raw proxy_private_ip)
WORKER1_PRIVATE_IP=$(terraform output -raw worker1_private_ip)
WORKER2_PRIVATE_IP=$(terraform output -raw worker2_private_ip)

MANAGER_ID=$(terraform output -raw manager_instance_id)

FIREWALL_SCRIPT=$(cat << EOF
#!/bin/bash
set -e

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow from ${PROXY_PRIVATE_IP} to any port 3306 proto tcp
ufw allow from ${WORKER1_PRIVATE_IP} to any port 3306 proto tcp
ufw allow from ${WORKER2_PRIVATE_IP} to any port 3306 proto tcp

ufw --force enable
EOF
)

aws ssm send-command \
--instance-ids "$MANAGER_ID" \
--document-name "AWS-RunShellScript" \
--parameters 'commands=["'"$FIREWALL_SCRIPT"'"]' \
--output text
