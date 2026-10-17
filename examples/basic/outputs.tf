output "instance_id" {
  description = "ID of the bastion: the target of aws ssm start-session."
  value       = module.ssm_bastion.instance_id
}

output "security_group_id" {
  description = "Security group to allow ingress from on the resources the bastion reaches."
  value       = module.ssm_bastion.security_group_id
}

output "start_session_command" {
  description = "Command that opens a shell on the bastion."
  value       = "aws ssm start-session --region ${var.region} --target ${module.ssm_bastion.instance_id}"
}
