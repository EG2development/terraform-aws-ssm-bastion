output "instance_id" {
  description = "ID of the bastion: the target of port forwarding and Run Command."
  value       = module.ssm_bastion.instance_id
}

output "security_group_id" {
  description = "ID of the bastion's security group."
  value       = module.ssm_bastion.security_group_id
}

output "iam_role_arn" {
  description = "ARN of the bastion's role, for resource policies that admit it."
  value       = module.ssm_bastion.iam_role_arn
}
