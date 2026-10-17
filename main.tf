# One EC2 instance reachable only through AWS Systems Manager: no inbound
# rules, no key pair, no public IP. Session Manager, Run Command and port
# forwarding all work over the SSM Agent's outbound connection, so the
# security group admits nothing.
#
# Resource names are "bastion" so that a caller migrating from an in-repository
# bastion module with the same names keeps its addresses. Renaming one is a
# breaking change and needs a moved block.

data "aws_ssm_parameter" "ami" {
  count = var.ami_id == null ? 1 : 0

  name = var.ami_ssm_parameter_name
}

data "aws_partition" "current" {}

resource "aws_security_group" "bastion" {
  name_prefix = "${var.name}-"
  # The description forces replacement of the group when it changes.
  description = "SSM bastion - egress only, no ingress"
  vpc_id      = var.vpc_id

  # No ingress block: nothing reaches the instance over the network. The SSM
  # Agent opens every connection outbound.
  egress {
    description = "Allow all outbound: Systems Manager, package repositories and the targets the bastion reaches"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidr_blocks
  }

  tags = merge({ Name = "${var.name}-sg" }, var.tags)

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Instance identity. The role carries only AmazonSSMManagedInstanceCore; a
# caller grants anything else by attaching its own policies to the role
# (output iam_role_name).
# ---------------------------------------------------------------------------

resource "aws_iam_role" "bastion" {
  name = var.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = var.name
  role = aws_iam_role.bastion.name
}

# ---------------------------------------------------------------------------
# Instance
# ---------------------------------------------------------------------------

resource "aws_instance" "bastion" {
  ami                  = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.ami[0].value
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  iam_instance_profile = aws_iam_instance_profile.bastion.name

  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = false

  # IMDSv2 only: a request for instance credentials needs a session token, so
  # a server-side request forgery cannot read them with a plain GET.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_size = var.root_volume_size
    volume_type = "gp3"
    kms_key_id  = var.root_volume_kms_key_arn
  }

  user_data = var.user_data

  # AMI tracks the SSM "latest" alias; don't churn the instance on every
  # AMI release. A destroy/recreate picks up the current AMI anyway.
  lifecycle {
    ignore_changes = [ami]
  }

  tags = merge({ Name = var.name }, var.tags)
}
