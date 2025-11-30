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

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_iam_role" "ssm" {
  name = "log8415-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "log8415-ssm-profile"
  role = aws_iam_role.ssm.name
}

module "gatekeeper" {
  source  = "terraform-aws-modules/ec2-instance/aws"

  name = "gatekeeper"
  ami  = data.aws_ami.ubuntu.id
  instance_type = var.gatekeeper_instance_type

  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [module.sg_gatekeeper.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
}
