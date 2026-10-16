# What a caller gets from the required inputs alone. These assertions pin names,
# tags and secure defaults; a change to any of them changes existing callers'
# infrastructure, which is a major release.
# The provider is mocked: no credentials, nothing created.

mock_provider "aws" {
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/example-bastion" }
  }
  # The mock returns these for arguments the module leaves unset, so any other
  # value after apply came from the module's configuration.
  mock_resource "aws_instance" {
    defaults = {
      key_name   = ""
      private_ip = "10.0.10.25"
    }
  }
}

variables {
  name      = "example-bastion"
  vpc_id    = "vpc-0123456789abcdef0"
  subnet_id = "subnet-0123456789abcdef0"
}

run "reachable_only_through_systems_manager" {
  command = apply

  assert {
    condition     = length(aws_security_group.bastion.ingress) == 0
    error_message = "The security group must have no ingress rule."
  }

  assert {
    condition = (
      length(aws_security_group.bastion.egress) == 1 &&
      one(aws_security_group.bastion.egress).cidr_blocks == tolist(["0.0.0.0/0"]) &&
      one(aws_security_group.bastion.egress).protocol == "-1" &&
      one(aws_security_group.bastion.egress).from_port == 0 &&
      one(aws_security_group.bastion.egress).to_port == 0
    )
    error_message = "By default the security group allows all outbound traffic and nothing else."
  }

  assert {
    condition     = aws_instance.bastion.associate_public_ip_address == false && aws_instance.bastion.key_name == ""
    error_message = "The instance must have no public IP and no key pair."
  }

  assert {
    condition     = aws_instance.bastion.metadata_options[0].http_tokens == "required" && aws_instance.bastion.metadata_options[0].http_endpoint == "enabled"
    error_message = "The instance metadata service must require IMDSv2 session tokens."
  }

  assert {
    condition     = aws_instance.bastion.vpc_security_group_ids == toset([aws_security_group.bastion.id]) && aws_instance.bastion.subnet_id == "subnet-0123456789abcdef0"
    error_message = "The instance must run in subnet_id with the module's security group only."
  }

  assert {
    condition     = aws_security_group.bastion.vpc_id == "vpc-0123456789abcdef0"
    error_message = "The security group must be created in vpc_id."
  }

  assert {
    condition = (
      output.instance_id == aws_instance.bastion.id &&
      output.private_ip == "10.0.10.25" &&
      output.security_group_id == aws_security_group.bastion.id &&
      output.iam_role_name == "example-bastion" &&
      output.iam_role_arn == "arn:aws:iam::111122223333:role/example-bastion" &&
      output.instance_profile_name == "example-bastion"
    )
    error_message = "Every output must report its resource."
  }
}

run "instance_defaults" {
  command = plan

  assert {
    condition     = aws_instance.bastion.instance_type == "t4g.nano"
    error_message = "The default instance type is t4g.nano (arm64, matching the default AMI)."
  }

  assert {
    condition = (
      data.aws_ssm_parameter.ami[0].name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64" &&
      aws_instance.bastion.ami == "ami-0123456789abcdef0"
    )
    error_message = "Without ami_id the AMI comes from the latest Amazon Linux 2023 arm64 SSM parameter."
  }

  assert {
    condition = (
      aws_instance.bastion.root_block_device[0].encrypted == true &&
      aws_instance.bastion.root_block_device[0].volume_type == "gp3" &&
      aws_instance.bastion.root_block_device[0].volume_size == 8
    )
    error_message = "The root volume must be an encrypted 8 GiB gp3 volume."
  }

  assert {
    condition     = aws_instance.bastion.user_data == null
    error_message = "No user data unless the caller supplies it."
  }

  assert {
    condition     = aws_instance.bastion.iam_instance_profile == aws_iam_instance_profile.bastion.name && aws_iam_instance_profile.bastion.role == aws_iam_role.bastion.name
    error_message = "The instance must use the module's instance profile, which carries the module's role."
  }
}

run "iam_is_systems_manager_only" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.ssm_core.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" && aws_iam_role_policy_attachment.ssm_core.role == "example-bastion"
    error_message = "The role must have AmazonSSMManagedInstanceCore attached."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role.bastion.assume_role_policy).Statement) == 1 &&
      jsondecode(aws_iam_role.bastion.assume_role_policy).Statement[0].Principal == { Service = "ec2.amazonaws.com" } &&
      jsondecode(aws_iam_role.bastion.assume_role_policy).Statement[0].Action == "sts:AssumeRole"
    )
    error_message = "Only EC2 may assume the role."
  }
}

run "names_and_tags_are_stable" {
  command = plan

  # The rendering of an existing caller (an in-repository bastion module with the
  # same resource names). Callers that migrate rely on these exact values to get
  # a plan without replacements; changing one is a breaking change.
  variables {
    name = "example-prod-bastion"
    tags = {
      Project     = "example"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
    user_data = <<-EOT
      #!/bin/bash
      set -euo pipefail
      dnf install -y unzip
      dnf install -y postgresql17 || dnf install -y postgresql16
    EOT
  }

  assert {
    condition = (
      aws_security_group.bastion.name_prefix == "example-prod-bastion-" &&
      aws_security_group.bastion.description == "SSM bastion - egress only, no ingress" &&
      aws_security_group.bastion.tags == tomap({ Name = "example-prod-bastion-sg", Project = "example", Environment = "prod", ManagedBy = "terraform" })
    )
    error_message = "The security group's name prefix, description (which forces replacement) or tags changed."
  }

  assert {
    condition     = one(aws_security_group.bastion.egress).description == "Allow all outbound: Systems Manager, package repositories and the targets the bastion reaches"
    error_message = "The egress rule description changed."
  }

  assert {
    condition = (
      aws_iam_role.bastion.name == "example-prod-bastion" &&
      aws_iam_role.bastion.tags == tomap({ Project = "example", Environment = "prod", ManagedBy = "terraform" }) &&
      aws_iam_instance_profile.bastion.name == "example-prod-bastion"
    )
    error_message = "The role and instance profile are named <name>; the role carries the caller's tags only (no Name tag)."
  }

  assert {
    # Byte for byte what the original module's jsonencode produced (jsonencode
    # sorts keys), so the role plans no change.
    condition = (
      aws_iam_role.bastion.assume_role_policy == "{\"Statement\":[{\"Action\":\"sts:AssumeRole\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"}}],\"Version\":\"2012-10-17\"}" &&
      aws_iam_role.bastion.assume_role_policy == jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Action    = "sts:AssumeRole"
            Effect    = "Allow"
            Principal = { Service = "ec2.amazonaws.com" }
          }
        ]
      })
    )
    error_message = "The trust policy JSON changed."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ssm_core.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "The managed policy ARN changed."
  }

  assert {
    condition = (
      aws_instance.bastion.tags == tomap({ Name = "example-prod-bastion", Project = "example", Environment = "prod", ManagedBy = "terraform" }) &&
      aws_instance.bastion.user_data == "#!/bin/bash\nset -euo pipefail\ndnf install -y unzip\ndnf install -y postgresql17 || dnf install -y postgresql16\n" &&
      aws_instance.bastion.user_data == var.user_data
    )
    error_message = "The instance's tags or user data changed."
  }

  assert {
    condition = (
      aws_instance.bastion.associate_public_ip_address == false &&
      aws_instance.bastion.metadata_options[0].http_tokens == "required" &&
      aws_instance.bastion.root_block_device[0].encrypted == true &&
      aws_instance.bastion.root_block_device[0].volume_type == "gp3" &&
      aws_instance.bastion.root_block_device[0].volume_size == 8
    )
    error_message = "The instance's network, metadata or root-volume settings changed."
  }
}
