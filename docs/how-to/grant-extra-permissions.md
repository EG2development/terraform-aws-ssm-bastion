# How to grant the bastion extra permissions

The module's role carries only `AmazonSSMManagedInstanceCore`. Give the bastion
anything else by attaching your own policy to the role, next to the module call.
The `iam_role_name` output names the role.

## Attach an inline policy

This lets the bastion read one Secrets Manager secret, for example so that a
script run through Run Command fetches database credentials itself:

```hcl
resource "aws_iam_role_policy" "read_database_secret" {
  name = "read-database-secret"
  role = module.ssm_bastion.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.database.arn
      }
    ]
  })
}
```

Name each resource precisely. Do not use `"Resource": "*"`.

If the secret is encrypted with a customer managed KMS key, also allow
`kms:Decrypt` on that key, in this policy or in the key policy using the
`iam_role_arn` output.

## Attach a managed policy

To reuse a policy that several roles share:

```hcl
resource "aws_iam_role_policy_attachment" "schema_bucket_read" {
  role       = module.ssm_bastion.iam_role_name
  policy_arn = aws_iam_policy.schema_bucket_read.arn
}
```

## Check it

Apply, then open a session:

```bash
aws ssm start-session --target "$(terraform output -raw bastion_instance_id)"
```

In the session, call the API you granted. This prints the secret's name, not its
value:

```bash
aws secretsmanager get-secret-value --secret-id <secret ARN> --query Name --output text
```

Amazon Linux 2023 includes the AWS CLI. The bastion uses its role's credentials
automatically.

## Remove a permission

Delete the policy resource from your configuration and apply. The module's own
policy attachment is not affected.
