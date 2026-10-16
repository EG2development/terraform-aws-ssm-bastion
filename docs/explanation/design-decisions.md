# Design decisions

Why the module is shaped the way it is, and what it leaves out on purpose.

## Systems Manager is the only way in

A traditional bastion accepts SSH from somewhere. That means a port open to a list
of addresses, key pairs to distribute, rotate and revoke, and a host that anyone on
the internet can try. This bastion has none of them: no ingress rule, no key pair,
no public IP. The SSM Agent on the instance opens every connection outbound to
Systems Manager, and Session Manager, Run Command and port forwarding all travel
over it.

Access is then an IAM question. Whoever may call `ssm:StartSession` on the instance
can reach it, nobody else can, and CloudTrail records every session start. Removing
someone's access is an IAM change, not a key hunt. Port forwarding covers the main
reason people kept SSH: tunnelling a database client from a laptop.

## IMDSv2 is required

The instance metadata service hands out the role's temporary credentials. With
IMDSv1, a single unauthenticated `GET` returns them, so any server-side request
forgery in software on the host can leak them. IMDSv2 requires a session token
obtained with a `PUT` first, which such a forgery usually cannot send. A bastion
runs whatever its users run, so the stricter mode costs nothing and closes the most
common credential leak on EC2.

## AMI changes are ignored

By default the AMI comes from an SSM parameter that AWS updates with every Amazon
Linux release. If Terraform followed it, the next apply after each release would
replace the instance, at a moment chosen by AWS's release schedule rather than by
the team, cutting off any open session. The module therefore reads the AMI once, at
creation, and ignores later changes, including a change of `ami_id`.

The instance holds nothing that needs keeping, so moving to a new AMI is a
deliberate replacement: `terraform apply -replace='module.ssm_bastion.aws_instance.bastion'`
creates a new instance from the AMI the parameter names at that moment. Teams that
want regular rolls schedule that command; teams that want in-place patching use
Patch Manager.

## Permissions are composed by the caller

The role carries only what Systems Manager needs. What else the bastion needs
depends entirely on what it is for: one team reads a database secret, another
fetches a schema archive from S3, a third needs nothing. A policy-JSON input would
hide those grants inside the module call, couple a permission change to the module's
interface, and invite one shared policy that grows with every use.

Instead the module exposes `iam_role_name` and `iam_role_arn`. Each grant is a
separate resource in the caller's configuration, reviewed next to the resource it
opens, and removable on its own. The same applies to the other direction: databases
and services admit the bastion by referring to `security_group_id` in their own
security groups.

## All outbound traffic is allowed by default

Without endpoints, the SSM Agent reaches Systems Manager's public regional endpoints
through a NAT gateway, so its egress must include the internet. The bastion's job is
to reach private targets whose addresses and ports differ from one caller to the
next. A default that allowed less would break the module's main use until each
caller worked out the exact list. The protection that matters is on the other side:
nothing can come in.

`egress_cidr_blocks` narrows the destinations, for example to the VPC's own CIDR
when interface endpoints replace the NAT gateway. Ports are not narrowed: one rule
for every protocol keeps the interface to a single input, and the targets' own
security groups decide which ports the bastion may use. The rule is inline in the
security group so that the module alone owns the group's egress, as the module it
was generalised from did.

## Small, encrypted and disposable

A bastion forwards bytes and runs a database client now and then. A `t4g.nano` does
that for a few pounds a month. The root volume is encrypted, with the account's
default key or a customer managed one. Nothing on the instance is meant to persist,
which is what makes replacing it, for an AMI roll or after a fault, a non-event.

## Names and addresses are stable

Resource names inside the module are fixed (`bastion`, `ssm_core`) and every derived
name is `<name>` or `<name>-<suffix>`. Callers who migrate from an in-repository
bastion module with the same names keep their resource addresses, and the
[reference](../reference/names-tags-and-iam.md) is the contract: changing any of
those names, or the security group's description, is a breaking change.

## Left out on purpose

| Not included | Why |
| --- | --- |
| Auto Scaling group or self-healing | An Auto Scaling group replaces the instance outside Terraform, so the module could no longer output the instance ID that callers' Run Command and port-forwarding targets use, and it needs a launch template besides. A bastion is not on a request path; when it fails, `terraform apply -replace` restores it in minutes |
| Session logging to S3 or CloudWatch Logs | It is an account-wide Session Manager preference that covers every instance, not a property of one bastion. Configure it once per account and Region |
| Patching | Patch Manager and its baselines are account-level configuration. Replacing the instance from a current AMI is the module's own way to get patches |
| More than one instance | Callers that need two bastions, for two VPCs or two teams, call the module twice. A count inside the module would only add indices to every name |
| Windows | Windows instances need a different AMI, user-data format and access model (Fleet Manager, RDP over port forwarding). A separate module if someone needs it |
| SSH over Session Manager | It brings back key pairs, the thing the module exists to remove. Session Manager shells and port forwarding cover the same uses |
