variable "name" {
  description = "Name of the bastion, for example \"payments-prod-bastion\". The instance, IAM role and instance profile are named `{name}`; the security group's name starts with `{name}-`. docs/reference/names-tags-and-iam.md lists every derived name."
  type        = string
  nullable    = false

  validation {
    # The IAM role is named exactly "<name>", and IAM role names are limited to
    # 64 characters. Every other derived name allows more.
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,63}$", var.name))
    error_message = "name must be 1-64 characters: letters, digits and hyphens, starting with a letter or digit."
  }
}

variable "vpc_id" {
  description = "ID of the VPC the bastion's security group is created in. It must be the VPC of subnet_id."
  type        = string
  nullable    = false
}

variable "subnet_id" {
  description = "ID of the private subnet the instance runs in. The subnet needs a route to the Systems Manager endpoints: a NAT gateway, or interface VPC endpoints for ssm, ssmmessages and ec2messages. Without one the instance never registers with Systems Manager and cannot be reached."
  type        = string
  nullable    = false
}

variable "instance_type" {
  description = "EC2 instance type. Default \"t4g.nano\" (Graviton, arm64), which matches the default AMI parameter. The instance type and the AMI must have the same architecture: with an x86_64 AMI, choose an x86_64 type such as \"t3.micro\". Changing it stops and starts the instance."
  type        = string
  default     = "t4g.nano"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be an EC2 instance type, for example \"t4g.nano\" or \"t3.micro\"."
  }
}

variable "ami_id" {
  description = "ID of the AMI to launch. Null (default) reads the AMI ID from the SSM parameter ami_ssm_parameter_name instead. Either way, a later change of AMI is ignored: replace the instance deliberately to move to a new one (see docs/explanation/design-decisions.md)."
  type        = string
  default     = null

}

variable "ami_ssm_parameter_name" {
  description = "Name or ARN of the SSM parameter that holds the AMI ID, used when ami_id is null. Default: the latest Amazon Linux 2023 AMI for arm64, which has the SSM Agent installed. For x86_64 use \"/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64\" with an x86_64 instance_type."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_./:-]+$", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an SSM parameter name or ARN: letters, digits and _ . / : - only."
  }
}

variable "user_data" {
  description = "Script or cloud-init configuration run at the instance's first boot, for example to install a database client. Null (default) runs nothing. At most 16 KB. Changing it stops and starts the instance. It is stored in plain text in the state and readable by anyone allowed to describe the instance: never put a secret in it."
  type        = string
  default     = null

  validation {
    # EC2 limits user data to 16 KB before base64 encoding. The size is
    # measured in bytes, through base64, because length() counts characters.
    condition = var.user_data == null ? true : (
      length(base64encode(var.user_data)) / 4 * 3 - length(regex("=*$", base64encode(var.user_data))) <= 16384
    )
    error_message = "user_data must be at most 16 KB (16384 bytes); EC2 rejects anything larger."
  }
}

variable "root_volume_size" {
  description = "Size of the encrypted gp3 root volume in GiB. Default 8, the size of the Amazon Linux 2023 AMI. An increase resizes the volume in place; AWS cannot shrink a volume."
  type        = number
  default     = 8
  nullable    = false

  validation {
    condition     = var.root_volume_size == floor(var.root_volume_size) && var.root_volume_size >= 8 && var.root_volume_size <= 64
    error_message = "root_volume_size must be a whole number of GiB between 8 and 64."
  }
}

variable "root_volume_kms_key_arn" {
  description = "ARN of a customer managed KMS key to encrypt the root volume. Null (default) uses the account's default EBS encryption key (aws/ebs unless the account sets another). The principal that runs Terraform must be allowed to use the key for EBS. Changing it replaces the instance."
  type        = string
  default     = null

  validation {
    condition     = var.root_volume_kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.root_volume_kms_key_arn))
    error_message = "root_volume_kms_key_arn must be null or the ARN of a KMS key (arn:<partition>:kms:<region>:<account>:key/<id>). An alias does not work: EC2 records the key ARN, so an alias would plan a replacement on every run."
  }
}

variable "egress_cidr_blocks" {
  description = "IPv4 CIDR blocks the instance may send traffic to, on every port. Default [\"0.0.0.0/0\"]: Systems Manager, package repositories and the targets the bastion reaches. Narrowing it, for example to the VPC CIDR, requires interface VPC endpoints for ssm, ssmmessages and ec2messages, and blocks package installation from the internet."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false

  validation {
    condition     = length(var.egress_cidr_blocks) > 0
    error_message = "egress_cidr_blocks must not be empty: the SSM Agent needs outbound access to reach Systems Manager."
  }

  validation {
    condition = alltrue([
      for c in var.egress_cidr_blocks : can(regex("^[0-9.]+/[0-9]{1,2}$", c)) && try(cidrsubnet(c, 0, 0) == c, false)
    ])
    error_message = "Every entry of egress_cidr_blocks must be an IPv4 CIDR block with no host bits set, for example \"10.0.0.0/16\" (not \"10.0.0.1/16\")."
  }

  validation {
    condition     = length(var.egress_cidr_blocks) == length(distinct(var.egress_cidr_blocks))
    error_message = "egress_cidr_blocks must not contain duplicates."
  }
}

variable "tags" {
  description = "Tags for every resource that takes them (the instance profile takes none). The module adds a Name tag to the instance and the security group, not to the IAM role; a Name key here overrides it. Tags from the provider's default_tags apply as usual."
  type        = map(string)
  default     = {}
  nullable    = false
}
