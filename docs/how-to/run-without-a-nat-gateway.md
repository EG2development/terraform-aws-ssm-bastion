# How to run without a NAT gateway

The SSM Agent must reach the Systems Manager endpoints. Without a NAT gateway, give
the VPC interface endpoints for `ssm`, `ssmmessages` and `ec2messages`, with private
DNS, so the agent's usual endpoint names resolve to addresses inside the VPC.

The VPC needs DNS support and DNS hostnames turned on. `terraform-aws-vpc` turns on
both.

## 1. Add the endpoints

Next to the module call:

```hcl
resource "aws_security_group" "ssm_endpoints" {
  name_prefix = "ssm-endpoints-"
  description = "Systems Manager interface endpoints"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "ssm_endpoints_from_bastion" {
  security_group_id            = aws_security_group.ssm_endpoints.id
  referenced_security_group_id = module.ssm_bastion.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from the SSM bastion"
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = toset(["ssm", "ssmmessages", "ec2messages"])

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.subnet_id]
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
}
```

Add more services to the set when the bastion or your account needs them:

| Add | When |
| --- | --- |
| `secretsmanager` | The bastion reads secrets |
| `kms` | Session data is encrypted with a KMS key (Session Manager preferences), or the bastion decrypts with KMS |
| `logs` | Session Manager preferences send session logs to CloudWatch Logs |
| An S3 gateway endpoint on the subnet's route table | Session logs go to S3, or the bastion installs packages: Amazon Linux 2023 repositories are served from S3 |

## 2. Narrow outbound traffic (optional)

With no NAT gateway, the route table already keeps traffic inside the VPC. To make
the security group say the same:

```hcl
module "ssm_bastion" {
  # ...
  egress_cidr_blocks = [var.vpc_cidr_block]
}
```

This also blocks the S3 gateway endpoint, whose addresses are outside the VPC. Keep
the default if the bastion installs packages.

## 3. Check registration

Apply, then run this until the status is `Online`:

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$(terraform output -raw bastion_instance_id)" \
  --query 'InstanceInformationList[].PingStatus' --output text
```

An instance that booted before the endpoints existed retries on its own and comes
online within a few minutes. To hurry it,
`aws ec2 reboot-instances --instance-ids <instance ID>`.
