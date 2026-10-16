variable "region" {
  description = "AWS Region of the VPC."
  type        = string
  default     = "eu-west-2"
}

variable "name" {
  description = "Name of the bastion and its IAM role."
  type        = string
  default     = "example-prod-bastion"
}

variable "vpc_id" {
  description = "ID of an existing VPC with interface endpoints for ssm, ssmmessages, ec2messages and secretsmanager."
  type        = string
}

variable "vpc_cidr_block" {
  description = "IPv4 CIDR block of that VPC: the only destination the bastion may send traffic to."
  type        = string
}

variable "subnet_id" {
  description = "ID of a private subnet in that VPC."
  type        = string
}

variable "database_security_group_id" {
  description = "ID of the database's security group, which gets an ingress rule from the bastion."
  type        = string
}

variable "database_secret_arn" {
  description = "ARN of the Secrets Manager secret that holds the database credentials."
  type        = string
}
