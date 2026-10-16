# The examples are real configurations. Each must plan against the mocked
# provider, so an example that stops working fails CI. Their VPC, subnet and
# database come from variables, which these runs supply.

mock_provider "aws" {
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  # The provider checks that these are ARNs, so the mock must return ARN-shaped values.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/example-bastion" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-west-2:111122223333:key/00000000-0000-0000-0000-000000000000" }
  }
}

run "basic_example_plans" {
  command = plan

  module {
    source = "./examples/basic"
  }

  variables {
    vpc_id    = "vpc-0123456789abcdef0"
    subnet_id = "subnet-0123456789abcdef0"
  }

  assert {
    condition     = module.ssm_bastion.iam_role_name == "example-bastion" && module.ssm_bastion.instance_profile_name == "example-bastion"
    error_message = "The basic example creates a bastion named from var.name."
  }
}

run "complete_example_plans" {
  command = plan

  module {
    source = "./examples/complete"
  }

  variables {
    vpc_id                     = "vpc-0123456789abcdef0"
    vpc_cidr_block             = "10.20.0.0/16"
    subnet_id                  = "subnet-0123456789abcdef0"
    database_security_group_id = "sg-0123456789abcdef0"
    database_secret_arn        = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:example-prod-db-AbCdEf"
  }

  assert {
    condition     = aws_iam_role_policy.read_database_secret.role == "example-prod-bastion"
    error_message = "The secret policy is attached to the module's role."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.database_from_bastion.from_port == 5432 && aws_vpc_security_group_ingress_rule.database_from_bastion.security_group_id == "sg-0123456789abcdef0"
    error_message = "The database's security group admits PostgreSQL from the bastion."
  }
}
