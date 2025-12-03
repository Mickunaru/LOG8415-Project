# Cloud Design Patterns: Implementing a DB Cluster

## Overview

This project deploys a secure multi-node MySQL setup on AWS using Terraform.  
It includes a manager node, two worker nodes, a gatekeeper, proxy, and all required networking components.  
The provided scripts handle provisioning, configuration, security hardening, and service initialization.

## Setup Instructions

Follow these steps to deploy the environment.

### Step 1 - Configure AWS Credentials

Make sure your AWS credentials are configured:

```bash
aws configure
```

Enter your AWS credentials when prompted:

-   AWS Access Key ID
-   AWS Secret Access Key
-   AWS Session Token (might not appear)
-   Default region: `us-east-1`
-   Default output format: `None`

### Step 2 - Install Terraform

Verify that Terraform is installed:

```bash
terraform -v
```

### Step 3 - Deploy

Run the deployment script:

```bash
./run.sh
```

This script will:

1. Initialize Terraform
2. Provision all instances
3. Configure gatekeeper, proxy and MySQL nodes
4. Harden firewall rules
5. Run load tests

## Deployed components

### Networking

-   Custom VPC
-   Public and private subnets
-   Internet Gateway + NAT Gateway
-   Route tables and associations
-   Security groups with firewall hardening

### EC2 Instances

-   2 x t2.large (Gatekeeper and Proxy)
-   3 x t2.micro (Manager node and 2 Replica nodes)

## Generated Files

Deployment produces:

-   terraform/terraform.tfstate – Tracks AWS resources
-   logs/sysbench\_\* – MySQL DB Benchmark output
-   logs/\*\_reads.log – Read load tests output
-   logs/\*\_writes.log – Write load tests output

## Cleanup

To tear down the deployment:

```bash
./teardown.sh
```

This will destroy all AWS resources and remove generated local files.

## Sending your own queries

Example curl request:

```bash
curl -X POST http://$GATEKEEPER_IP/query \
     -H "Content-Type: application/json" \
     -H "X-API-KEY: $GATEKEEPER_API_KEY" \
     -d '{"query": "SELECT * FROM actor LIMIT 5;", "strategy": "direct"}'
```

Simply replace $GATEKEEPER_IP with the gatekeeper's public IP and $GATEKEEPER_API_KEY with the gatekeeper's api key.
