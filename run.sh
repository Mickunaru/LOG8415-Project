set -e

echo "LOG8415E Assignment - Starting deployment"

cd terraform
echo "Initializing Terraform"
terraform init

echo "Applying Terraform configuration"
terraform apply -auto-approve
echo "Terraform apply completed"

echo "Waiting 10 seconds to allow EC2 instances to complete initial startup before configuring firewalls"
sleep 10

cd ..

echo "Configuring proxy firewall"
./scripts/configure_proxy_firewall.sh

echo "Configuring manager firewall"
./scripts/configure_manager_firewall.sh

echo "Configuring workers firewall"
./scripts/configure_workers_firewall.sh