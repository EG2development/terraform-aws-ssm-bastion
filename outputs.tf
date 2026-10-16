output "instance_id" {
  description = "ID of the instance: the target of aws ssm start-session, port forwarding and Run Command."
  value       = aws_instance.bastion.id
}

output "private_ip" {
  description = "Private IPv4 address of the instance."
  value       = aws_instance.bastion.private_ip
}

output "security_group_id" {
  description = "ID of the bastion's security group. Allow ingress from it on the security groups of the databases and services the bastion reaches. Do not add rules to this group itself."
  value       = aws_security_group.bastion.id
}

output "iam_role_name" {
  description = "Name of the instance's IAM role. Attach your own policies to it to grant the bastion more than Systems Manager access."
  value       = aws_iam_role.bastion.name
}

output "iam_role_arn" {
  description = "ARN of the instance's IAM role, for resource policies (KMS keys, secrets, buckets) that admit the bastion."
  value       = aws_iam_role.bastion.arn
}

output "instance_profile_name" {
  description = "Name of the instance profile that attaches the role to the instance."
  value       = aws_iam_instance_profile.bastion.name
}
