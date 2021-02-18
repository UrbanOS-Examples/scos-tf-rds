variable "identifier" {
  description = "The name/identifier of the RDS instance"
  type        = string
}

variable "prefix" {
  description = "The prefix to attach to resources related to the database"
  type        = string
}

variable "database_name" {
  description = "The name of the database"
  type        = string
  default     = ""
}

variable "delete_automated_backups" {
  description = "delete automated backups after the DB instance is deleted"
  type        = string
  default     = false
}

variable "multi_az" {
  description = "Whether or not the instance should span multiple availability zones"
  type        = string
  default     = true
}

variable "port" {
  description = "The port to listen on for the database"
  type        = string
  default     = ""
}

variable "type" {
  description = "The type of the database (postgres, mysql, etc.)"
  type        = string
}

variable "username" {
  description = "The admin username for the database instance"
  type        = string
  default     = ""
}

variable "vers" {
  description = "The version of the database"
  type        = string
  default     = ""
}

variable "attached_vpc_id" {
  description = "The VPC to which the database should attach"
  type        = string
}

variable "attached_subnet_ids" {
  description = "The subnets to which the database should attach"
  type        = list(string)
}

variable "attached_security_groups" {
  description = "The security groups that should be attached to the database"
  type        = list(string)
}

variable "attached_security_group_cidr_blocks" {
  description = "The cidr blocks that are allowed to access the database"
  type        = list(string)
  default     = []
}

variable "instance_class" {
  description = "The instance type to use for the database"
  default     = "db.t3.small"
}

variable "allocated_storage" {
  description = "The hard drive space (in GB) provided to the database"
  default     = 100
}

variable "parameter_group_name" {
  description = "The name of the parameter group to use"
  type        = string
  default     = ""
}

locals {
  backup_start_hour        = random_integer.start_hour.result
  backup_start_minute      = random_integer.start_minute.result
  backup_end_hour          = local.backup_start_hour + 1
  backup_end_minute        = local.backup_start_minute
  maintenance_start_hour   = local.backup_start_hour + 1
  maintenance_start_minute = local.backup_start_minute
  maintenance_end_hour     = local.backup_end_hour + 1
  maintenance_end_minute   = local.backup_end_minute
  backup_window = format(
    "%02s:%02s-%02s:%02s",
    local.backup_start_hour,
    local.backup_start_minute,
    local.backup_end_hour,
    local.backup_end_minute,
  )
  maintenance_window = format(
    "Wed:%02s:%02s-Wed:%02s:%02s",
    local.maintenance_start_hour,
    local.maintenance_start_minute,
    local.maintenance_end_hour,
    local.maintenance_end_minute,
  )

  default_versions = {
    postgres = "10.13"
    mysql    = "5.7.22"
  }

  default_ports = {
    postgres = 5432
    mysql    = 3306
  }

  default_parameter_groups = {
    postgres = "default.postgres10"
    mysql    = "default.mysql5.7"
  }

  version = coalesce(var.vers, lookup(local.default_versions, var.type, ""))
  port    = coalesce(var.port, lookup(local.default_ports, var.type, ""))
  parameter_group_name = coalesce(
    var.parameter_group_name,
    lookup(local.default_parameter_groups, var.type, ""),
  )
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
  secret_id     = aws_secretsmanager_secret.password.id
  secret_string = random_string.password.result
}

resource "aws_kms_key" "key" {
  description         = "Encryption key for RDS ${var.prefix}"
  enable_key_rotation = true
}

resource "aws_kms_alias" "key_alias" {
  name_prefix   = "alias/${var.prefix}-rds-kms-key"
  target_key_id = aws_kms_key.key.key_id
}

resource "aws_db_subnet_group" "subnet_group" {
  description = "Subnet group for RDS ${var.prefix}"
  subnet_ids  = var.attached_subnet_ids

  tags = {
    Name = "${var.prefix}-rds-subnet-group"
  }
}

resource "aws_security_group" "allowed" {
  name_prefix = "${var.prefix}-rds-security-group"
  vpc_id      = var.attached_vpc_id

  tags = {
    Name = "${var.prefix}-rds-allowed"
  }
}

resource "aws_security_group_rule" "allowed_from_groups" {
  count                    = length(var.attached_security_groups)
  type                     = "ingress"
  description              = "Default port allow for RDS ${var.prefix}"
  from_port                = local.port
  protocol                 = "tcp"
  source_security_group_id = var.attached_security_groups[count.index]
  to_port                  = local.port
  security_group_id        = aws_security_group.allowed.id
}

resource "aws_security_group_rule" "allowed_from_cidr" {
  count             = length(var.attached_security_group_cidr_blocks) > 0 ? 1 : 0
  type              = "ingress"
  description       = "Default port allow for RDS ${var.prefix} from CIDR blocks"
  from_port         = local.port
  protocol          = "tcp"
  cidr_blocks       = var.attached_security_group_cidr_blocks
  to_port           = local.port
  security_group_id = aws_security_group.allowed.id
}

# hours are in UTC
resource "random_integer" "start_hour" {
  min  = 0
  max  = 5
  seed = var.prefix
}

resource "random_integer" "start_minute" {
  min  = 0
  max  = 59
  seed = var.prefix
}

resource "aws_db_instance" "database" {
  allocated_storage          = var.allocated_storage
  apply_immediately          = false
  auto_minor_version_upgrade = true
  backup_retention_period    = 14
  backup_window              = local.backup_window
  db_subnet_group_name       = aws_db_subnet_group.subnet_group.name
  engine                     = var.type
  engine_version             = local.version
  identifier                 = var.identifier
  instance_class             = var.instance_class
  kms_key_id                 = aws_kms_key.key.arn
  maintenance_window         = local.maintenance_window
  multi_az                   = var.multi_az
  name                       = var.database_name
  password                   = random_string.password.result
  port                       = local.port
  skip_final_snapshot        = true
  storage_encrypted          = true
  storage_type               = "gp2"
  username                   = coalesce(var.username, var.database_name, "admin")
  vpc_security_group_ids     = [aws_security_group.allowed.id]
  delete_automated_backups   = var.delete_automated_backups
  parameter_group_name       = local.parameter_group_name

  tags = {
    Name = "${var.prefix}-rds"
  }
}

output "id" {
  description = "The id of the generated database"
  value       = aws_db_instance.database.id
}

output "name" {
  description = "The name of the database created inside of the RDS database"
  value       = aws_db_instance.database.name
}

output "address" {
  description = "The address at which the RDS database can be reached"
  value       = aws_db_instance.database.address
}

output "port" {
  description = "The port at which the RDS database can be reached"
  value       = aws_db_instance.database.port
}

output "kms_key_id" {
  description = "The KMS key ID that is used to encrypt the database and its snapshots"
  value       = aws_db_instance.database.kms_key_id
}

output "username" {
  description = "The username used for logging into the RDS database"
  value       = aws_db_instance.database.username
}

output "password_secret_id" {
  depends_on = [aws_secretsmanager_secret_version.password_version]

  description = "The username used for logging into the RDS database"
  value       = aws_secretsmanager_secret.password.id
}

