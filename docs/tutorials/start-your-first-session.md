# Tutorial: start your first session

In this tutorial you put a bastion into an existing private subnet, open a shell on
it through Session Manager, and remove it again. It takes about fifteen minutes and
costs a few pence: a `t4g.nano` instance and an 8 GiB volume, billed while they
exist.

## Before you start

- Terraform 1.9 or later, and credentials for a sandbox AWS account that may create
  EC2 instances, security groups, IAM roles and instance profiles, and start
  Session Manager sessions.
- The AWS CLI version 2 and the Session Manager plugin.
  `session-manager-plugin --version` prints a version number when the plugin is
  installed.
- A VPC with a private subnet whose route table sends `0.0.0.0/0` to a NAT gateway.
  [terraform-aws-vpc](https://github.com/EG2development/terraform-aws-vpc) creates one.
- Read access to this repository (`git ls-remote https://github.com/EG2development/terraform-aws-ssm-bastion.git`
  lists its tags).

Set the two IDs once; every command below uses them:

```bash
export AWS_REGION=eu-west-2
VPC_ID=vpc-0123456789abcdef0        # your VPC
SUBNET_ID=subnet-0123456789abcdef0  # a private subnet in it
```

Check that the subnet routes to a NAT gateway. The command prints a `nat-` ID:

```bash
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=${SUBNET_ID}" \
  --query 'RouteTables[].Routes[?DestinationCidrBlock==`0.0.0.0/0`].NatGatewayId' --output text
```

## 1. Write the configuration

Create an empty directory and a file `main.tf` in it:

```hcl
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

module "ssm_bastion" {
  source = "git::https://github.com/EG2development/terraform-aws-ssm-bastion.git?ref=v1.0.0"

  name      = "tutorial-bastion"
  vpc_id    = var.vpc_id
  subnet_id = var.subnet_id
}

output "instance_id" {
  value = module.ssm_bastion.instance_id
}
```

## 2. Create the bastion

```bash
terraform init
terraform apply -var "vpc_id=${VPC_ID}" -var "subnet_id=${SUBNET_ID}"
```

Read the plan before you type `yes`. You should see five resources: the security
group, the IAM role, its policy attachment, the instance profile and the instance.

## 3. Wait for Systems Manager

The SSM Agent on the instance registers with Systems Manager a minute or two after
boot. Run this until the status is `Online`:

```bash
INSTANCE_ID="$(terraform output -raw instance_id)"
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
  --query 'InstanceInformationList[].[InstanceId,PingStatus,PlatformName]' --output table
```

## 4. Open a shell

```bash
aws ssm start-session --target "${INSTANCE_ID}"
```

You are now `ssm-user` on the instance, with no SSH key and no open port. Try the
instance metadata service without a session token:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://169.254.169.254/latest/meta-data/instance-id
```

It prints `401`: only IMDSv2 requests are answered. With a token it works:

```bash
TOKEN="$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')"
curl -s -H "X-aws-ec2-metadata-token: ${TOKEN}" http://169.254.169.254/latest/meta-data/instance-id
```

Type `exit` to end the session.

## 5. Clean up

```bash
terraform destroy -var "vpc_id=${VPC_ID}" -var "subnet_id=${SUBNET_ID}"
```

The instance and its root volume are deleted. Nothing on them is kept.

## Next steps

- [Port-forward to a private database](../how-to/port-forward-to-a-private-database.md)
  from your machine.
- [Grant the bastion extra permissions](../how-to/grant-extra-permissions.md), for
  example to read a database secret.
