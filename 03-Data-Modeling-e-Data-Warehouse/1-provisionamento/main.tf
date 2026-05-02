# =============================================================================
# Lab 03 — Data Modeling e Data Warehouse no Amazon Redshift
# =============================================================================
# Infraestrutura mínima para o laboratório rodar dentro das restrições do
# AWS Academy Learner Lab:
#   - NÃO cria IAM roles (usa LabRole pré-existente)
#   - Redshift provisionado ra3.large com 1 nó (máx permitido: 2)
#   - Região us-east-1 (ou us-west-2)
#   - Recursos nomeados com AccountID para evitar colisão entre alunos
# =============================================================================

# -----------------------------------------------------------------------------
# Data sources: descobre contexto da conta sem precisar de input do aluno
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# LabRole pré-criada pelo Learner Lab (não podemos criar roles novas)
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# VPC default (Learner Lab não permite criar VPC)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------------------------------------------------------
# Locals: convenções de nomeação e short ID estável
# -----------------------------------------------------------------------------
locals {
  account_id = data.aws_caller_identity.current.account_id

  # ID curto estável para nomes (últimos 8 chars do account id)
  short_id = substr(local.account_id, -8, 8)

  # Prefixo padronizado para todos os recursos do lab
  name_prefix = "dw-aula3-${local.short_id}"

  # Bucket S3 global-unique
  bucket_name = "dw-lab-${local.account_id}"

  common_tags = {
    Lab       = "03"
    CreatedBy = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# Senha do Redshift (gera aleatória se o aluno não passou uma)
# -----------------------------------------------------------------------------
resource "random_password" "redshift" {
  count            = var.redshift_master_password == "" ? 1 : 0
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]"
}

locals {
  redshift_password = var.redshift_master_password != "" ? var.redshift_master_password : random_password.redshift[0].result
}

# =============================================================================
# S3 — Bucket para dataset TPC-H + resultados + logs
# =============================================================================
resource "aws_s3_bucket" "dw_lab" {
  bucket        = local.bucket_name
  force_destroy = true # permite terraform destroy mesmo com objetos

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "dw_lab" {
  bucket = aws_s3_bucket.dw_lab.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "dw_lab" {
  bucket = aws_s3_bucket.dw_lab.id

  versioning_configuration {
    status = "Disabled" # laboratório — desabilitado para simplificar teardown
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dw_lab" {
  bucket = aws_s3_bucket.dw_lab.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Estrutura inicial de prefixos (cria placeholders para organização visual)
resource "aws_s3_object" "prefix_raw" {
  bucket  = aws_s3_bucket.dw_lab.id
  key     = "raw/tpch/.keep"
  content = "placeholder"
}

resource "aws_s3_object" "prefix_staging" {
  bucket  = aws_s3_bucket.dw_lab.id
  key     = "staging/.keep"
  content = "placeholder"
}

resource "aws_s3_object" "prefix_results" {
  bucket  = aws_s3_bucket.dw_lab.id
  key     = "results/.keep"
  content = "placeholder"
}

resource "aws_s3_object" "prefix_unload" {
  bucket  = aws_s3_bucket.dw_lab.id
  key     = "unload/.keep"
  content = "placeholder"
}

# =============================================================================
# Glue Data Catalog — database para catalogar o TPC-H em S3
# =============================================================================
# Obs.: usamos apenas o catálogo (não rodamos ETL jobs). O catálogo serve como
# referência para o script load_tpch.sh registrar partições, útil para
# auditoria e para o aluno ver o dataset no console Glue.
resource "aws_glue_catalog_database" "tpch_raw" {
  name        = "tpch_raw_${local.short_id}"
  description = "Catálogo do TPC-H SF1 em Parquet para o Lab 03"

  catalog_id = local.account_id
}

# =============================================================================
# Networking — Subnet group e security group para o Redshift
# =============================================================================
resource "aws_redshift_subnet_group" "dw" {
  name        = "${local.name_prefix}-subnet-group"
  description = "Subnet group para cluster Redshift do Lab 03"
  subnet_ids  = data.aws_subnets.default.ids

  tags = local.common_tags
}

resource "aws_security_group" "redshift" {
  name        = "${local.name_prefix}-redshift-sg"
  description = "SG para Redshift do Lab 03 (acesso educacional)"
  vpc_id      = data.aws_vpc.default.id

  tags = local.common_tags
}

resource "aws_security_group_rule" "redshift_ingress" {
  type              = "ingress"
  from_port         = 5439
  to_port           = 5439
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.redshift.id
  description       = "Redshift port open to Codespaces (laboratorio)"
}

resource "aws_security_group_rule" "redshift_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.redshift.id
  description       = "Egress allowed for COPY from S3"
}

# =============================================================================
# Redshift — Cluster provisionado single-node ra3.large
# =============================================================================
# Restrições Learner Lab respeitadas:
#   - node_type = ra3.large (único permitido)
#   - number_of_nodes = 1 (dentro do limite de 2)
#   - iam_roles = [LabRole ARN] (role pré-existente, não criamos nova)
#   - enhanced_vpc_routing = false (evita custo de VPC Endpoint)
#   - encrypted = true (boa prática)
# =============================================================================
resource "aws_redshift_cluster" "dw" {
  cluster_identifier = local.name_prefix

  # Hardware — limites do Learner Lab
  node_type       = var.redshift_node_type
  number_of_nodes = var.redshift_number_of_nodes
  cluster_type    = var.redshift_number_of_nodes == 1 ? "single-node" : "multi-node"

  # Banco e credenciais
  database_name   = var.redshift_database_name
  master_username = var.redshift_master_username
  master_password = local.redshift_password

  # Network
  publicly_accessible       = var.enable_public_access
  vpc_security_group_ids    = [aws_security_group.redshift.id]
  cluster_subnet_group_name = aws_redshift_subnet_group.dw.name
  port                      = 5439

  # IAM role pré-criada do Learner Lab (permite COPY do S3, acesso ao Glue, etc.)
  iam_roles            = [data.aws_iam_role.lab_role.arn]
  default_iam_role_arn = data.aws_iam_role.lab_role.arn

  # Encriptação
  encrypted = true

  # Config de manutenção mínima (cluster de laboratório, sem janela estrita)
  automated_snapshot_retention_period = 1
  preferred_maintenance_window        = "sun:03:00-sun:04:00"
  skip_final_snapshot                 = true
  apply_immediately                   = true

  # Evita apontar para algum parameter group customizado (usa o default)
  # cluster_parameter_group_name = "default.redshift-1.0"

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })

  # Ignora mudanças de senha (evita rotação acidental em re-apply)
  lifecycle {
    ignore_changes = [master_password]
  }
}
