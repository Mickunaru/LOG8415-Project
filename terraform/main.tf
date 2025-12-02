module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "log8415-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a"]
  public_subnets  = ["10.0.1.0/24"]
  private_subnets = ["10.0.2.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Project = "LOG8415"
  }
}

module "sg_gatekeeper" {
  source  = "terraform-aws-modules/security-group/aws"
  name    = "gatekeeper-sg"
  vpc_id  = module.vpc.vpc_id

  ingress_rules = ["http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules = ["all-all"]
}

module "sg_proxy" {
  source = "terraform-aws-modules/security-group/aws"
  name   = "proxy-sg"
  vpc_id = module.vpc.vpc_id

  ingress_with_source_security_group_id = [{
    from_port                = 5000
    to_port                  = 5000
    protocol                 = "tcp"
    source_security_group_id = module.sg_gatekeeper.security_group_id
    description              = "Allow Gatekeeper to talk to Proxy on TCP 5000"
  }]

  egress_rules = ["all-all"]
}

module "sg_manager" {
  source = "terraform-aws-modules/security-group/aws"
  name   = "manager-sg"
  vpc_id = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "mysql-tcp"
      source_security_group_id = module.sg_proxy.security_group_id
    },
    {
      rule                     = "mysql-tcp"
      source_security_group_id = module.sg_worker.security_group_id
    },
    {
      rule                     = "all-icmp"
      source_security_group_id = module.sg_worker.security_group_id
    }
  ]

  egress_rules = ["all-all"]
}

module "sg_worker" {
  source = "terraform-aws-modules/security-group/aws"
  name   = "worker-sg"
  vpc_id = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "mysql-tcp"
      source_security_group_id = module.sg_proxy.security_group_id
    },
    {
      rule                     = "mysql-tcp"
      source_security_group_id = module.sg_manager.security_group_id
    },
    {
      rule                     = "all-icmp"
      source_security_group_id = module.sg_manager.security_group_id
    }
  ]

  egress_rules = ["all-all"]
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

// IAM Role and Instance Profile for SSM for AWS accounts with IAM creation permissions
# resource "aws_iam_role" "ssm" {
#   name = "log8415-ssm-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action    = "sts:AssumeRole"
#       Effect    = "Allow"
#       Principal = { Service = "ec2.amazonaws.com" }
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ssm_attach" {
#   role       = aws_iam_role.ssm.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }

# resource "aws_iam_instance_profile" "ssm" {
#   name = "log8415-ssm-profile"
#   role = aws_iam_role.ssm.name
# }

module "gatekeeper" {
  source  = "terraform-aws-modules/ec2-instance/aws"

  name = "gatekeeper"
  ami  = data.aws_ami.ubuntu.id
  instance_type = var.gatekeeper_instance_type

  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [module.sg_gatekeeper.security_group_id]
  
  // Custom IAM Instance Profile with SSM permissions
  # iam_instance_profile        = aws_iam_instance_profile.ssm.name

  // Pre-existing IAM Instance Profile with SSM permissions with AWS Academy
  iam_instance_profile        = "LabInstanceProfile" 

  user_data = templatefile("${path.module}/scripts/setup_gatekeeper.sh", {
    proxy_private_ip = module.proxy.private_ip
  })
}

module "proxy" {
  source  = "terraform-aws-modules/ec2-instance/aws"

  name = "proxy"
  ami  = data.aws_ami.ubuntu.id
  instance_type = var.proxy_instance_type

  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [module.sg_proxy.security_group_id]
  iam_instance_profile   = "LabInstanceProfile"

  user_data = templatefile("${path.module}/scripts/setup_proxy.sh", {
    manager_ip = module.manager.private_ip
    worker1_ip = module.worker1.private_ip
    worker2_ip = module.worker2.private_ip
  })

  depends_on = [module.vpc.nat_gateway_ids]
}

module "manager" {
  source  = "terraform-aws-modules/ec2-instance/aws"

  name = "manager"
  ami  = data.aws_ami.ubuntu.id
  instance_type = var.manager_instance_type

  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [module.sg_manager.security_group_id]
  iam_instance_profile   = "LabInstanceProfile"

  user_data = templatefile("${path.module}/scripts/setup_manager.sh", {
    MYSQL_ROOT_PWD = var.mysql_root_password
    MYSQL_REPLICA_PWD = var.mysql_replica_password
  })

  depends_on = [module.vpc.nat_gateway_ids]
}

module "worker1" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name = "worker1"
  ami  = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type

  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [module.sg_worker.security_group_id]
  iam_instance_profile   = "LabInstanceProfile"

  user_data = templatefile("${path.module}/scripts/setup_worker.sh", {
    MYSQL_ROOT_PWD = var.mysql_root_password
    MYSQL_REPLICA_PWD = var.mysql_replica_password
    SOURCE_IP = module.manager.private_ip
    SERVER_ID = 2
  })

  depends_on = [module.vpc.nat_gateway_ids, module.manager]
}

module "worker2" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name = "worker2"
  ami  = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type

  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [module.sg_worker.security_group_id]
  iam_instance_profile   = "LabInstanceProfile"

  user_data = templatefile("${path.module}/scripts/setup_worker.sh", {
    MYSQL_ROOT_PWD = var.mysql_root_password
    MYSQL_REPLICA_PWD = var.mysql_replica_password
    SOURCE_IP = module.manager.private_ip
    SERVER_ID = 3
  })

  depends_on = [module.vpc.nat_gateway_ids, module.manager]
}
