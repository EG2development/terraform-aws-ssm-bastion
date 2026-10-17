# A bastion for reaching one private PostgreSQL database: an x86_64 AMI with a
# matching instance type, a root volume encrypted with a customer managed key,
# outbound traffic limited to the VPC, and two additions next to the module
# call that use its outputs: permission to read the database secret, and an
# ingress rule on the database's security group.

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

module "ssm_bastion" {
  source = "../.."

  name      = var.name
  vpc_id    = var.vpc_id
  subnet_id = var.subnet_id

  # An x86_64 AMI needs an x86_64 instance type.
  ami_ssm_parameter_name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  instance_type          = "t3.micro"

  root_volume_size        = 16
  root_volume_kms_key_arn = aws_kms_key.bastion.arn

  # Outbound traffic stays inside the VPC. Systems Manager and Secrets Manager
  # are then reachable only through interface VPC endpoints in this VPC (ssm,
  # ssmmessages, ec2messages, secretsmanager; see
  # docs/how-to/run-without-a-nat-gateway.md). Package repositories on the
  # internet are out of reach too, so there is no user_data.
  egress_cidr_blocks = [var.vpc_cidr_block]

  tags = {
    Environment = "prod"
    Team        = "platform"
  }
}

# Customer managed key for the root volume. The key policy delegates to IAM in
# this account: the principal that runs Terraform needs kms:CreateGrant,
# kms:Decrypt, kms:DescribeKey, kms:GenerateDataKeyWithoutPlaintext and
# kms:ReEncrypt* on this key in its own IAM policy.
resource "aws_kms_key" "bastion" {
  description         = "${var.name} root volume"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
    ]
  })
}

# Composition: the bastion may read the database secret, and nothing else
# beyond Systems Manager. The module never takes policy JSON; callers attach
# policies to its role.
resource "aws_iam_role_policy" "read_database_secret" {
  name = "read-database-secret"
  role = module.ssm_bastion.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.database_secret_arn
      }
    ]
  })
}

# Composition: the database admits PostgreSQL from the bastion's security
# group only.
resource "aws_vpc_security_group_ingress_rule" "database_from_bastion" {
  security_group_id            = var.database_security_group_id
  referenced_security_group_id = module.ssm_bastion.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from the SSM bastion"
}
