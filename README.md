# scos-tf-rds

Terraform module for creating an RDS database instance with the SCOS team best practices.

## Usage

Example with all required arguments

```terraform
resource "aws_vpc" "my_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "dedicated"

  tags = {
    Name = "mine"
  }
}

resource "aws_subnet" "my_subnet" {
  vpc_id     = "${aws_vpc.my_vpc.id}"
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "mine"
  }
}

resource "aws_security_group" "my_sg" {
  name        = "my_sg"
  description = "Allow my traffic"
  vpc_id      = "${aws_vpc.my_vpc.id}"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

module "my_database" {
  source = "git@github.com:SmartColumbusOS/scos-tf-rds?ref=1.0.0"
  identifier               = "my-database-instance"
  prefix                   = "${var.environment}-mine"
  database_name            = "mine"
  type                     = "postgres"
  attached_vpc_id          = "${aws_vpc.my_vpc.id}"
  attached_subnet_ids      = ["${aws_subnet.my_subnet.id}"]
  attached_security_groups = ["${aws_security_group.my_sg.id}"]
}
```

### Required variables

- `identifier` - the name of the RDS instance
- `prefix` - the prefix to put on the names for the RDS database and all related resources (KMS keys, secrets, etc.)
- `name` - the database name to create in the RDS, as well as the username for that database
- `type` - the database type, currently supports `mysql` and `postgresql`
- `attached_vpc_id` - the VPC you want the RDS attached to
- `attached_subnet_ids` - the subnets inside that VPC you want the RDS on
- `attached_security_groups` - the security group you want to be able to talk to the database on its configured port

### Optional variables

- `port` - the port for the database in the RDS to listen on, defaults to `5432` for type `postgresql` and `3306` for type `mysql`
- `vers` - the version of the database software to use, defaults to `10.6` for type `postgres` and `5.6.37` for type `mysql`
- `instance_class` - the instance type to use for the RDS databases, defaults to `db.t3.small`

### Outputs

- `address` - the address at which the RDS database can be reached
- `id` - the id of the generated database"
- `port` - the port that was assigned to the RDS database
- `password_secret_id` - the AWS secret ID where the password can be looked up
- `name` - the name used for the database in RDS, will be the same as the `name` variable, but included this way for clarity
- `username` - the username assigned to the database, will be the same as the `name` variable, but included this way for clarity
- `kms_key_id` - the ID of the AWS KMS key used to encrypted the database, for reference

## Other notes

This module does not allow for configuration of some variables that are part of team best practices:

- `auto_minor_version_upgrade` - forced to true so we stay up to date
- `maintenance_window` - will always occur Wednesday morning at a seeded (on prefix) random time between 0-6 AM UTC
- `backup_retention_period` - always 14 days
- `backup_window` - will occur every morning at a seeded (on prefix) random time between 0-6 AM UTC which won't overlap with the maintenance window
- `multi_az` - will always be set to true so the database is fault tolerant
- `storage_encrypted` - will always be set to true so the database is encrypted with a generated KMS key
- `password` - will always be set with a seeded (on prefix) random string and stored in an AWS secret
- `allocated_storage` - will always be set to `100` (Gi) as this is largely what we use nearly everywhere
- `storage_type` - will always be set to `gp2` as we currently have no need for anything better, such as `ssd`
