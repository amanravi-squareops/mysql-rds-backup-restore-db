locals {
  name                        = "mysql"
  snap                        = true
  demo                        = "demo"
  region                      = "us-west-2"
  family                      = "mysql8.0"
  environment                 = "prod"
  mysql_instance_class        = "db.t3.micro"
  mysql_engine_version        = "8.0.32"
  major_engine_version        = "8.0"
  create_namespace            = true
  namespace                   = "mysql-test"
  allowed_security_groups     = ["sg-02313c561173cff42"]
  vpc_cidr                    = "192.168.0.0/16"
  current_identity            = data.aws_caller_identity.current.arn
  manage_master_user_password = false
  custom_user_password        = "Amanravi12"
  enable_storage_autoscaling  = false
  mysqldb_permission          = true
  additional_tags = {
    Owner      = "Organization_Name"
    Expires    = "Never"
    Department = "Engineering"
  }
}


data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

module "kms" {
  source = "terraform-aws-modules/kms/aws"

  deletion_window_in_days = 7
  description             = "Complete key example showing various configurations available"
  enable_key_rotation     = false
  is_enabled              = true
  key_usage               = "ENCRYPT_DECRYPT"
  multi_region            = false

  # Policy
  enable_default_policy = true
  key_owners            = [local.current_identity]
  key_administrators    = [local.current_identity]
  key_users             = [local.current_identity]
  key_service_users     = [local.current_identity]
  key_statements = [
    {
      sid = "Allow use of the key"
      actions = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ]
      resources = ["*"]

      principals = [
        {
          type = "Service"
          identifiers = [
            "monitoring.rds.amazonaws.com",
            "rds.amazonaws.com",
          ]
        }
      ]
    },
    {
      sid       = "Enable IAM User Permissions"
      actions   = ["kms:*"]
      resources = ["*"]

      principals = [
        {
          type = "AWS"
          identifiers = [
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
            data.aws_caller_identity.current.arn,
          ]
        }
      ]
    }
  ]

  # Aliases
  aliases = ["${local.name}-test"]

  tags = local.additional_tags
}

module "vpc" {
  source                  = "squareops/vpc/aws"
  name                    = local.name
  vpc_cidr                = local.vpc_cidr
  environment             = local.environment
  availability_zones      = ["us-east-1a", "us-east-1b"]
  public_subnet_enabled   = true
  auto_assign_public_ip   = true
  intra_subnet_enabled    = false
  private_subnet_enabled  = true
  one_nat_gateway_per_az  = false
  database_subnet_enabled = true
}

module "rds-mysql" {
  source                           = "squareops/rds-mysql/aws"
  version                          = "1.1.1"
  name                             = local.name
  vpc_id                           = module.vpc.vpc_id
  family                           = local.family
  multi_az                         = false
  subnet_ids                       = module.vpc.database_subnets
  db_name                          = "testdb"
  environment                      = local.environment
  kms_key_arn                      = module.kms.key_arn
  engine_version                   = local.mysql_engine_version
  instance_class                   = local.mysql_instance_class
  master_username                  = "admin"
  custom_user_password             = local.custom_user_password
  storage_type                     = "gp2"
  allowed_security_groups          = local.allowed_security_groups
  allocated_storage                = 10
  max_allocated_storage            = 120
  rds_instance_name                = local.name
  major_engine_version             = local.major_engine_version
  publicly_accessible              = false
  skip_final_snapshot              = true
  backup_window                    = "03:00-06:00"
  snapshot_identifier              = null
  maintenance_window               = "Mon:00:00-Mon:03:00"
  deletion_protection              = false
  final_snapshot_identifier_prefix = "finalamanravi"
  cloudwatch_metric_alarms_enabled = false
  alarm_cpu_threshold_percent      = 70
  disk_free_storage_space          = "10000000" # in bytes
  slack_notification_enabled       = false
  slack_username                   = "Admin"
  slack_channel                    = "mysql-notification"
  slack_webhook_url                = "https://hooks/xxxxxxxx"

}


module "backup_restore" {
  depends_on             = [module.rds-mysql]
  source                 = "../../modules/backup-restore"
  cluster_name           = "prod-eks"
  mysqldb_backup_enabled = false
  namespace              = local.namespace
  bucket_provider_type   = "s3"
  mysqldb_backup_config = {
    db_username          = module.rds-mysql.db_instance_username
    db_password          = module.rds-mysql.db_instance_password
    mysql_database_name  = ""                          # always a user defined
    s3_bucket_region     = "us-west-2"                 # always a user defined
    cron_for_full_backup = "*/3 * * * *"               # always a user defined
    bucket_uri           = "s3://my-rds-backup-files/" #always a user defined
    db_endpoint          = replace(module.rds-mysql.db_instance_endpoint, ":3306", "")
  }

  mysqldb_restore_enabled = true
  mysqldb_permission      = local.mysqldb_permission
  mysqldb_restore_config = {
    db_endpoint      = replace(module.rds-mysql.db_instance_endpoint, ":3306", "")
    db_username      = module.rds-mysql.db_instance_username
    db_password      = module.rds-mysql.db_instance_password
    bucket_uri       = "s3://my-rds-backup-files/mysqldump_20240201_114539.zip" # always a user defined
    file_name        = "mysqldump_20240201_114539.zip"                          # always a user defined
    s3_bucket_region = "us-west-2"                                              # always a user defined
  }
}
