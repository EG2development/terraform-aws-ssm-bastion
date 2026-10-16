variable "region" {
  description = "AWS Region of the VPC."
  type        = string
  default     = "eu-west-2"
}

variable "name" {
  description = "Name of the bastion and its IAM role."
  type        = string
  default     = "example-bastion"
}

variable "vpc_id" {
  description = "ID of an existing VPC."
  type        = string
}

variable "subnet_id" {
  description = "ID of a private subnet in that VPC with a route to a NAT gateway."
  type        = string
}
