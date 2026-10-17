# The smallest useful call: one bastion in an existing private subnet whose
# route table sends 0.0.0.0/0 to a NAT gateway. Examples call the module from
# the working copy so CI validates this repository's code; a real caller pins a
# Git source (README.md, "Usage").

provider "aws" {
  region = var.region
}

module "ssm_bastion" {
  source = "../.."

  name      = var.name
  vpc_id    = var.vpc_id
  subnet_id = var.subnet_id
}
