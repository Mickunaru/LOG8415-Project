#!/bin/bash
set -e

cd terraform

PROXY_ID=$(terraform output -raw proxy_instance_id)
GATEKEEPER_PRIVATE_IP=$(terraform output -raw gatekeeper_private_ip)

FIREWALL_SCRIPT=$(cat << EOF
#!/bin/bash
set -e

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow from ${GATEKEEPER_PRIVATE_IP} to any port 5000 proto tcp

ufw --force enable
EOF
)

aws ssm send-command \
--instance-ids "$PROXY_ID" \
--document-name "AWS-RunShellScript" \
--parameters 'commands=["'"$FIREWALL_SCRIPT"'"]' \
--output text >/dev/null 2>&1
