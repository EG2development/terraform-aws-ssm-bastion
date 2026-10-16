# How to port-forward to a private database

Reach a database in a private subnet from your own machine. Session Manager opens a
local port and forwards it through the bastion to the database. Nothing is opened
to the internet.

You need the AWS CLI version 2 with the Session Manager plugin, permission to call
`ssm:StartSession` on the instance and on the document
`AWS-StartPortForwardingSessionToRemoteHost`, and a database client.

## 1. Let the bastion reach the database

Add an ingress rule to the database's security group, next to the module call:

```hcl
resource "aws_vpc_security_group_ingress_rule" "database_from_bastion" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = module.ssm_bastion.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from the SSM bastion"
}
```

Apply it. Do not add rules to the bastion's own security group.

## 2. Start the forward

Set the values at the top, then run the session. It keeps running in this terminal.

```bash
INSTANCE_ID="$(terraform output -raw bastion_instance_id)"  # your output of module.ssm_bastion.instance_id
DB_HOST=mydb.cluster-abcdefghijkl.eu-west-2.rds.amazonaws.com
DB_PORT=5432
LOCAL_PORT=15432

aws ssm start-session \
  --target "${INSTANCE_ID}" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${DB_HOST}\"],\"portNumber\":[\"${DB_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
```

The bastion resolves `DB_HOST`, so private DNS names work.

## 3. Connect

In a second terminal:

```bash
psql "host=localhost port=15432 dbname=app user=app sslmode=require"
```

Use `sslmode=require`, not `verify-full`: the database's certificate names
`DB_HOST`, not `localhost`.

## 4. Stop

Press Ctrl+C in the first terminal. Session Manager also ends an idle session after
the timeout set in the account's Session Manager preferences.

## If it does not connect

| Symptom | Check |
| --- | --- |
| `TargetNotConnected` | The instance is not `Online` in `aws ssm describe-instance-information`. Its subnet needs a NAT gateway or [interface endpoints](run-without-a-nat-gateway.md) |
| `AccessDeniedException` | Your identity lacks `ssm:StartSession` on the instance or on the document |
| Session starts, client times out | The database's security group does not admit the bastion's security group on the port, or `egress_cidr_blocks` excludes the database's subnet |
