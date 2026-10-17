# Every validation rejects bad input at plan time, before any API call.

mock_provider "aws" {
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  name      = "example-bastion"
  vpc_id    = "vpc-0123456789abcdef0"
  subnet_id = "subnet-0123456789abcdef0"
}

run "accepts_valid_input" {
  command = plan
}

run "accepts_name_of_64_characters" {
  command = plan
  variables {
    name = "a234567890123456789012345678901234567890123456789012345678901234"
  }
}

run "rejects_name_with_invalid_characters" {
  command = plan
  variables {
    name = "my_bastion"
  }
  expect_failures = [var.name]
}

run "rejects_name_starting_with_hyphen" {
  command = plan
  variables {
    name = "-bastion"
  }
  expect_failures = [var.name]
}

run "rejects_name_too_long_for_iam" {
  command = plan
  variables {
    name = "a2345678901234567890123456789012345678901234567890123456789012345"
  }
  expect_failures = [var.name]
}

run "rejects_malformed_instance_type" {
  command = plan
  variables {
    instance_type = "t4g nano"
  }
  expect_failures = [var.instance_type]
}

run "rejects_malformed_ami_parameter_name" {
  command = plan
  variables {
    ami_ssm_parameter_name = "latest amazon linux"
  }
  expect_failures = [var.ami_ssm_parameter_name]
}

run "rejects_user_data_over_16_kb" {
  command = plan
  variables {
    user_data = format("%-16385s", "#")
  }
  expect_failures = [var.user_data]
}

run "rejects_user_data_over_16_kb_in_bytes" {
  command = plan
  variables {
    # 8200 characters, but 16400 bytes: EC2 counts bytes.
    user_data = replace(format("%8200s", ""), " ", "é")
  }
  expect_failures = [var.user_data]
}

run "rejects_root_volume_smaller_than_the_ami" {
  command = plan
  variables {
    root_volume_size = 4
  }
  expect_failures = [var.root_volume_size]
}

run "rejects_root_volume_over_64_gib" {
  command = plan
  variables {
    root_volume_size = 65
  }
  expect_failures = [var.root_volume_size]
}

run "rejects_fractional_root_volume_size" {
  command = plan
  variables {
    root_volume_size = 8.5
  }
  expect_failures = [var.root_volume_size]
}

run "rejects_kms_alias_for_root_volume" {
  command = plan
  variables {
    root_volume_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:alias/ebs"
  }
  expect_failures = [var.root_volume_kms_key_arn]
}

run "rejects_empty_egress" {
  command = plan
  variables {
    egress_cidr_blocks = []
  }
  expect_failures = [var.egress_cidr_blocks]
}

run "rejects_invalid_egress_cidr" {
  command = plan
  variables {
    egress_cidr_blocks = ["10.0.0.0/16", "not-a-cidr"]
  }
  expect_failures = [var.egress_cidr_blocks]
}

run "rejects_ipv6_egress_cidr" {
  command = plan
  variables {
    egress_cidr_blocks = ["::/0"]
  }
  expect_failures = [var.egress_cidr_blocks]
}

run "rejects_egress_cidr_with_host_bits" {
  command = plan
  variables {
    egress_cidr_blocks = ["10.0.0.1/16"]
  }
  expect_failures = [var.egress_cidr_blocks]
}

run "rejects_duplicate_egress_cidrs" {
  command = plan
  variables {
    egress_cidr_blocks = ["10.0.0.0/16", "10.0.0.0/16"]
  }
  expect_failures = [var.egress_cidr_blocks]
}
