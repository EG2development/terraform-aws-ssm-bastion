# Optional inputs change only what they say.

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
}

variables {
  name      = "example-bastion"
  vpc_id    = "vpc-0123456789abcdef0"
  subnet_id = "subnet-0123456789abcdef0"
}

run "explicit_ami_skips_the_lookup" {
  command = plan

  variables {
    ami_id = "ami-0fedcba9876543210"
  }

  assert {
    condition     = length(data.aws_ssm_parameter.ami) == 0
    error_message = "With ami_id set, the module must not read the SSM parameter."
  }

  assert {
    condition     = aws_instance.bastion.ami == "ami-0fedcba9876543210"
    error_message = "ami_id must reach the instance."
  }
}

run "x86_64_ami_parameter_and_instance_type" {
  command = plan

  variables {
    ami_ssm_parameter_name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    instance_type          = "t3.micro"
  }

  assert {
    condition     = data.aws_ssm_parameter.ami[0].name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    error_message = "ami_ssm_parameter_name must reach the parameter lookup."
  }

  assert {
    condition     = aws_instance.bastion.instance_type == "t3.micro"
    error_message = "instance_type must reach the instance."
  }
}

run "user_data" {
  command = plan

  variables {
    user_data = "#!/bin/bash\ndnf install -y postgresql17\n"
  }

  assert {
    condition     = aws_instance.bastion.user_data == "#!/bin/bash\ndnf install -y postgresql17\n"
    error_message = "user_data must reach the instance unchanged."
  }
}

run "user_data_at_the_limit" {
  command = plan

  variables {
    # 16384 bytes exactly: accepted.
    user_data = format("%-16384s", "#")
  }

  assert {
    condition     = length(aws_instance.bastion.user_data) == 16384
    error_message = "User data of exactly 16 KB must be accepted."
  }
}

run "root_volume_size_and_key" {
  command = plan

  variables {
    root_volume_size        = 20
    root_volume_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition = (
      aws_instance.bastion.root_block_device[0].volume_size == 20 &&
      aws_instance.bastion.root_block_device[0].kms_key_id == "arn:aws:kms:eu-west-2:111122223333:key/00000000-0000-0000-0000-000000000000" &&
      aws_instance.bastion.root_block_device[0].encrypted == true
    )
    error_message = "root_volume_size and root_volume_kms_key_arn must reach the encrypted root volume."
  }
}

run "egress_narrowed" {
  command = plan

  variables {
    egress_cidr_blocks = ["10.0.0.0/16", "192.168.0.0/24"]
  }

  assert {
    condition = (
      length(aws_security_group.bastion.egress) == 1 &&
      one(aws_security_group.bastion.egress).cidr_blocks == tolist(["10.0.0.0/16", "192.168.0.0/24"])
    )
    error_message = "egress_cidr_blocks must replace the destinations of the single egress rule."
  }
}

run "tags" {
  command = plan

  variables {
    tags = { Team = "platform" }
  }

  assert {
    condition = (
      aws_instance.bastion.tags == tomap({ Name = "example-bastion", Team = "platform" }) &&
      aws_security_group.bastion.tags == tomap({ Name = "example-bastion-sg", Team = "platform" }) &&
      aws_iam_role.bastion.tags == tomap({ Team = "platform" })
    )
    error_message = "var.tags must reach every taggable resource, next to the module's Name tags."
  }
}

run "caller_name_tag_wins" {
  command = plan

  variables {
    tags = { Name = "jump-host" }
  }

  assert {
    condition     = aws_instance.bastion.tags["Name"] == "jump-host" && aws_security_group.bastion.tags["Name"] == "jump-host"
    error_message = "A Name key in var.tags overrides the module's Name tag."
  }
}
