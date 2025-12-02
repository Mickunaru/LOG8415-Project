variable "aws_region" {
  default = "us-east-1"
}

variable "mysql_root_password" {
  default   = "rootpassword"
  type      = string
  sensitive = true
}

variable "mysql_replica_password" {
  default   = "replicapassword"
  type      = string
  sensitive = true
}

variable "mysql_proxy_password" {
  default   = "proxypassword"
  type      = string
  sensitive = true
}

variable "gatekeeper_api_key" {
  default   = "gatekeeperapikey"
  type      = string
  sensitive = true
}

variable "manager_instance_type" {
  default = "t2.micro"
}

variable "worker_instance_type" {
  default = "t2.micro"
}

variable "proxy_instance_type" {
  default = "t2.large"
}

variable "gatekeeper_instance_type" {
  default = "t2.large"
}
