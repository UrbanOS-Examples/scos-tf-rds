variable "prefix" {
  description = "The prefix to attach to resources related to the database"
  type        = "string"
}

variable "name" {
  description = "The name of the database"
  type        = "string"
}

variable "port" {
  description = "The port to listen on for the database"
  type        = "string"
  default     = ""
}

variable "type" {
  description = "The type of the database (postgres, mysql, etc.)"
  type        = "string"
}

variable "vers" {
  description = "The version of the database"
  type        = "string"
  default     = ""
}

variable "attached_vpc_id" {
  description = "The VPC to which the database should attach"
  type        = "string"
}

variable "attached_subnet_ids" {
  description = "The subnets to which the database should attach"
  type        = "list"
}

variable "attached_security_groups" {
  description = "The security groups that should be attached to the database"
  type        = "list"
}

variable "instance_class" {
  description = "The instance type to use for the database"
  default     = "db.t3.small"
}

locals {
  backup_start_hour        = "${random_integer.start_hour.result}"
  backup_start_minute      = "${random_integer.start_minute.result}"
  backup_end_hour          = "${local.backup_start_hour + 1}"
  backup_end_minute        = "${local.backup_start_minute}"
  maintenance_start_hour   = "${local.backup_start_hour + 1}"
  maintenance_start_minute = "${local.backup_start_minute}"
  maintenance_end_hour     = "${local.backup_end_hour + 1}"
  maintenance_end_minute   = "${local.backup_end_minute}"
  backup_window            = "${format("%02s:%02s-%02s:%02s", local.backup_start_hour, local.backup_start_minute, local.backup_end_hour, local.backup_end_minute)}"
  maintenance_window       = "${format("Wed:%02s:%02s-Wed:%02s:%02s", local.maintenance_start_hour, local.maintenance_start_minute, local.maintenance_end_hour, local.maintenance_end_minute)}"

  default_versions = {
    postgres = "10.6"
    mysql    = "5.6.37"
  }

  default_ports = {
    postgres = 5432
    mysql    = 3306
  }

  version = "${coalesce(var.vers, lookup(local.default_versions, var.type))}"
  port    = "${coalesce(var.port, lookup(local.default_ports, var.type))}"
}

resource "random_string" "password" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "password" {
  name                    = "${var.prefix}-rds-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "password_version" {
  secret_id     = "${aws_secretsmanager_secret.password.id}"
  secret_string = "${random_string.password.result}"
}

resource "aws_kms_key" "key" {
  description = "Encryption key for RDS ${var.prefix}"
}

resource "aws_kms_alias" "key_alias" {
  name_prefix   = "alias/${var.prefix}-rds-kms-key"
  target_key_id = "${aws_kms_key.key.key_id}"
}

resource "aws_db_subnet_group" "subnet_group" {
  description = "Subnet group for RDS ${var.prefix}"
  subnet_ids  = ["${var.attached_subnet_ids}"]

  tags {
    Name = "${var.prefix}-rds-subnet-group"
  }
}

resource "aws_security_group" "allowed" {
  name_prefix = "${var.prefix}-rds-security-group"
  vpc_id      = "${var.attached_vpc_id}"

  tags {
    Name = "${var.prefix}-rds-allowed"
  }

  ingress {
    description     = "Default port allow for RDS ${var.prefix}"
    from_port       = "${local.port}"
    protocol        = "tcp"
    security_groups = ["${var.attached_security_groups}"]
    to_port         = "${local.port}"
  }
}

# hours are in UTC
resource "random_integer" "start_hour" {
  min  = 0
  max  = 5
  seed = "${var.prefix}"
}

resource "random_integer" "start_minute" {
  min  = 0
  max  = 59
  seed = "${var.prefix}"
}

resource "aws_db_instance" "database" {
  allocated_storage          = 100
  apply_immediately          = false
  auto_minor_version_upgrade = true
  backup_retention_period    = 14
  backup_window              = "${local.backup_window}"
  db_subnet_group_name       = "${aws_db_subnet_group.subnet_group.name}"
  engine                     = "${var.type}"
  engine_version             = "${local.version}"
  instance_class             = "${var.instance_class}"
  kms_key_id                 = "${aws_kms_key.key.arn}"
  maintenance_window         = "${local.maintenance_window}"
  multi_az                   = true
  name                       = "${var.name}"
  password                   = "${random_string.password.result}"
  port                       = "${local.port}"
  skip_final_snapshot        = true
  storage_encrypted          = true
  storage_type               = "gp2"
  username                   = "${var.name}"
  vpc_security_group_ids     = ["${aws_security_group.allowed.id}"]

  tags {
    Name = "${var.prefix}-rds"
  }
}

output "name" {
  description = "The name of the database created inside of the RDS database"
  value       = "${aws_db_instance.database.name}"
}

output "address" {
  description = "The address at which the RDS database can be reached"
  value       = "${aws_db_instance.database.address}"
}

output "port" {
  description = "The port at which the RDS database can be reached"
  value       = "${aws_db_instance.database.port}"
}

output "kms_key_id" {
  description = "The KMS key ID that is used to encrypt the database and its snapshots"
  value       = "${aws_db_instance.database.kms_key_id}"
}

output "username" {
  description = "The username used for logging into the RDS database"
  value       = "${aws_db_instance.database.username}"
}

output "password_secret_id" {
  depends_on = ["aws_secretsmanager_secret_version.password_version"]

  description = "The username used for logging into the RDS database"
  value       = "${aws_secretsmanager_secret.password.id}"
}
