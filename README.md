# terraform-aws-ssm-bastion

A Terraform module for one small EC2 instance that is reachable only through AWS
Systems Manager: Session Manager shells, port forwarding and Run Command. It has no
inbound rules, no key pair and no public IP, requires IMDSv2, encrypts its root
volume, and its IAM role carries only `AmazonSSMManagedInstanceCore`.

Use it to reach private resources, for example to port-forward a database client
from your machine to a database in a private subnet, or to run a client on the
instance through Run Command. You do not need to know anything about the project it
came from.

It deliberately does **not** manage:

- **What the bastion may do or reach.** Attach policies to the `iam_role_name`
  output, and admit the `security_group_id` output in your databases' and services'
  security groups. The module never takes policy JSON.
- **Network plumbing.** The subnet needs a NAT gateway or interface VPC endpoints for
  `ssm`, `ssmmessages` and `ec2messages`; see
  [how to run without a NAT gateway](docs/how-to/run-without-a-nat-gateway.md).
- **Account-wide Systems Manager settings**: session logging, session encryption,
  idle timeout and patching. See [design decisions](docs/explanation/design-decisions.md).
- **Provider configuration and state.** There is no `provider` or `backend` block.

## Usage

```hcl
module "ssm_bastion" {
  source = "git::https://github.com/EG2development/terraform-aws-ssm-bastion.git?ref=v1.0.0" # x-release-please-version

  name      = "payments-prod-bastion"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.private_subnet_ids[0]
}
```

Pin `?ref=`
to a release tag (inside the organisation) or the release's full commit SHA (outside
it), never to a branch. Run `terraform init` after changing `source`.

## Examples

| Example | Shows |
| --- | --- |
| [`examples/basic`](examples/basic) | A bastion in an existing private subnet with a NAT gateway; all defaults |
| [`examples/complete`](examples/complete) | An x86_64 AMI with a matching instance type, a root volume encrypted with a customer managed key, egress limited to the VPC, and composition: a policy that reads one database secret, and a database ingress rule from the bastion's security group |

## Documentation

| You want to | Read |
| --- | --- |
| Deploy a bastion and open your first shell on it | [Tutorial: start your first session](docs/tutorials/start-your-first-session.md) |
| Reach a private database from your machine | [How to port-forward to a private database](docs/how-to/port-forward-to-a-private-database.md) |
| Let the bastion read a secret, a bucket or anything else | [How to grant extra permissions](docs/how-to/grant-extra-permissions.md) |
| Use the bastion in a VPC with no NAT gateway | [How to run without a NAT gateway](docs/how-to/run-without-a-nat-gateway.md) |
| Look up every name, tag and IAM permission the module creates | [Reference: names, tags and IAM](docs/reference/names-tags-and-iam.md) |
| See the resources and how they connect, on one page | [Architecture diagram](docs/reference/architecture.png) |
| Understand why it is built this way | [Design decisions](docs/explanation/design-decisions.md) |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.16.0 |
| aws | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_instance_profile.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ssm_core](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_security_group.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name of the bastion, for example "payments-prod-bastion". The instance, IAM role and instance profile are named `{name}`; the security group's name starts with `{name}-`. docs/reference/names-tags-and-iam.md lists every derived name. | `string` | n/a | yes |
| subnet\_id | ID of the private subnet the instance runs in. The subnet needs a route to the Systems Manager endpoints: a NAT gateway, or interface VPC endpoints for ssm, ssmmessages and ec2messages. Without one the instance never registers with Systems Manager and cannot be reached. | `string` | n/a | yes |
| vpc\_id | ID of the VPC the bastion's security group is created in. It must be the VPC of subnet\_id. | `string` | n/a | yes |
| ami\_id | ID of the AMI to launch. Null (default) reads the AMI ID from the SSM parameter ami\_ssm\_parameter\_name instead. Either way, a later change of AMI is ignored: replace the instance deliberately to move to a new one (see docs/explanation/design-decisions.md). | `string` | `null` | no |
| ami\_ssm\_parameter\_name | Name or ARN of the SSM parameter that holds the AMI ID, used when ami\_id is null. Default: the latest Amazon Linux 2023 AMI for arm64, which has the SSM Agent installed. For x86\_64 use "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86\_64" with an x86\_64 instance\_type. | `string` | `"/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"` | no |
| egress\_cidr\_blocks | IPv4 CIDR blocks the instance may send traffic to, on every port. Default ["0.0.0.0/0"]: Systems Manager, package repositories and the targets the bastion reaches. Narrowing it, for example to the VPC CIDR, requires interface VPC endpoints for ssm, ssmmessages and ec2messages, and blocks package installation from the internet. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| instance\_type | EC2 instance type. Default "t4g.nano" (Graviton, arm64), which matches the default AMI parameter. The instance type and the AMI must have the same architecture: with an x86\_64 AMI, choose an x86\_64 type such as "t3.micro". Changing it stops and starts the instance. | `string` | `"t4g.nano"` | no |
| root\_volume\_kms\_key\_arn | ARN of a customer managed KMS key to encrypt the root volume. Null (default) uses the account's default EBS encryption key (aws/ebs unless the account sets another). The principal that runs Terraform must be allowed to use the key for EBS. Changing it replaces the instance. | `string` | `null` | no |
| root\_volume\_size | Size of the encrypted gp3 root volume in GiB. Default 8, the size of the Amazon Linux 2023 AMI. An increase resizes the volume in place; AWS cannot shrink a volume. | `number` | `8` | no |
| tags | Tags for every resource that takes them (the instance profile takes none). The module adds a Name tag to the instance and the security group, not to the IAM role; a Name key here overrides it. Tags from the provider's default\_tags apply as usual. | `map(string)` | `{}` | no |
| user\_data | Script or cloud-init configuration run at the instance's first boot, for example to install a database client. Null (default) runs nothing. At most 16 KB. Changing it stops and starts the instance. It is stored in plain text in the state and readable by anyone allowed to describe the instance: never put a secret in it. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| iam\_role\_arn | ARN of the instance's IAM role, for resource policies (KMS keys, secrets, buckets) that admit the bastion. |
| iam\_role\_name | Name of the instance's IAM role. Attach your own policies to it to grant the bastion more than Systems Manager access. |
| instance\_id | ID of the instance: the target of aws ssm start-session, port forwarding and Run Command. |
| instance\_profile\_name | Name of the instance profile that attaches the role to the instance. |
| private\_ip | Private IPv4 address of the instance. |
| security\_group\_id | ID of the bastion's security group. Allow ingress from it on the security groups of the databases and services the bastion reaches. Do not add rules to this group itself. |
<!-- END_TF_DOCS -->

## Defaults and security decisions

| Decision | Default | Why | How to change it |
| --- | --- | --- | --- |
| Inbound access | No ingress rule, no key pair, no public IP | Systems Manager is the only way in; IAM decides who, CloudTrail records it | Not configurable |
| Instance metadata | IMDSv2 required | A request forgery on the host cannot read the role's credentials with a plain `GET` | Not configurable |
| Instance permissions | `AmazonSSMManagedInstanceCore` only | Each extra grant is the caller's, reviewed where it is used | Attach policies to the `iam_role_name` output |
| Root volume | Encrypted gp3, 8 GiB, the account's default EBS key | Encryption at rest with nothing to manage | `root_volume_size`, `root_volume_kms_key_arn` |
| Outbound traffic | All protocols to `0.0.0.0/0` | Reaches Systems Manager through NAT, and whatever private targets the caller admits it to | `egress_cidr_blocks` |
| AMI | Latest Amazon Linux 2023 arm64 at creation, never changed afterwards | No replacement when AWS publishes a new AMI | `ami_id`, `ami_ssm_parameter_name`; roll with `terraform apply -replace` |
| Instance type | `t4g.nano` | The smallest Graviton type; matches the arm64 AMI | `instance_type` (same architecture as the AMI) |
| User data | None | Nothing runs that the caller did not ask for | `user_data` (no secrets: it is readable) |

## Security scanning

Checkov runs on every pull request. Three checks are skipped, in
[`.github/workflows/ci.yml`](.github/workflows/ci.yml):

| Check | Why it is skipped |
| --- | --- |
| `CKV_AWS_126` "detailed monitoring is enabled for EC2 instances" | One-minute metrics are billed per instance and tell nothing useful about an idle bastion; basic five-minute monitoring stays on. Setting it would also change every existing caller's instance |
| `CKV_AWS_135` "EC2 is EBS optimized" | Current-generation types, including the default `t4g.nano`, are EBS-optimised by default at no extra cost, so the argument adds nothing |
| `CKV_AWS_382` "no security groups allow egress from 0.0.0.0/0 to port -1" | Unrestricted egress is the default on purpose: the SSM Agent reaches Systems Manager through NAT and the bastion reaches targets the module cannot predict. The group has no ingress. `egress_cidr_blocks` narrows it; `examples/complete` does, and passes the check |

## Upgrading

### From your own bastion code

If your code uses the same resource names (`aws_security_group.bastion`,
`aws_iam_role.bastion`, `aws_iam_instance_profile.bastion`, `aws_instance.bastion`,
`aws_iam_role_policy_attachment.ssm_core`), switching to this module keeps the
addresses.

1. Change `source` and pass `name`, `tags` and your `user_data` unchanged (the same
   string, byte for byte, or the instance is updated).
2. Any extra inline policy your code put on the role becomes your own
   `aws_iam_role_policy` with `role = module.<call>.iam_role_name`, keeping its name,
   plus a `moved` block from its old address to the new one.
3. Run `terraform init` and `terraform plan`. Nothing may be replaced. Expect at most
   an in-place update of the security group if your egress rule's description
   differs from the module's.

### Between releases

Read [`CHANGELOG.md`](CHANGELOG.md) for every version between yours and the new one,
change `?ref=`, run `terraform init`, and review the plan. A minor or patch release
plans no changes unless you opt into something new. A new AMI never reaches an
existing instance through an upgrade; replace the instance to move to one.

## Versioning and releases

Semantic versions, tags `vMAJOR.MINOR.PATCH`, created by release-please from
Conventional Commit pull-request titles. Patch: a fix that changes no plan. Minor: a
new optional input, output or off-by-default resource. Major: anything that can
change or replace an existing caller's resources, or raise a minimum version.
Details: [the standard](https://github.com/EG2development/terraform-module-standards/blob/main/docs/standard.md).

## Contributing and ownership

See [`CONTRIBUTING.md`](CONTRIBUTING.md). The team in
[`.github/CODEOWNERS`](.github/CODEOWNERS) reviews every change and owns releases.
Report vulnerabilities as described in [`SECURITY.md`](SECURITY.md).
