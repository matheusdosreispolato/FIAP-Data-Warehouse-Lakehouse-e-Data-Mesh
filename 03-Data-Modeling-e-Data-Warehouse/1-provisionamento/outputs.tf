# =============================================================================
# Outputs — tudo que o aluno precisa para rodar o resto do lab
# =============================================================================

output "account_id" {
  description = "AWS Account ID descoberto em runtime"
  value       = local.account_id
}

output "region" {
  description = "Região onde tudo foi criado"
  value       = data.aws_region.current.name
}

output "s3_bucket_name" {
  description = "Bucket S3 do lab (onde o TPC-H será armazenado)"
  value       = aws_s3_bucket.dw_lab.id
}

output "s3_bucket_arn" {
  description = "ARN do bucket S3 — usado em COPY e IAM policies"
  value       = aws_s3_bucket.dw_lab.arn
}

output "s3_raw_tpch_prefix" {
  description = "Prefixo S3 onde o TPC-H Parquet será carregado pelo script"
  value       = "s3://${aws_s3_bucket.dw_lab.id}/raw/tpch/"
}

output "glue_database_name" {
  description = "Nome do database no Glue Data Catalog"
  value       = aws_glue_catalog_database.tpch_raw.name
}

output "lab_role_arn" {
  description = "ARN da LabRole (usado em COPY FROM 's3://...' IAM_ROLE ...)"
  value       = data.aws_iam_role.lab_role.arn
}

output "redshift_cluster_identifier" {
  description = "Identifier do cluster Redshift"
  value       = aws_redshift_cluster.dw.cluster_identifier
}

output "redshift_endpoint" {
  description = "Endpoint completo (host:port) do Redshift"
  value       = aws_redshift_cluster.dw.endpoint
}

output "redshift_host" {
  description = "Host do Redshift (sem a porta) — use com psql"
  value       = aws_redshift_cluster.dw.dns_name
}

output "redshift_port" {
  description = "Porta do Redshift"
  value       = aws_redshift_cluster.dw.port
}

output "redshift_database" {
  description = "Banco inicial do Redshift"
  value       = aws_redshift_cluster.dw.database_name
}

output "redshift_master_username" {
  description = "Usuário master do Redshift"
  value       = aws_redshift_cluster.dw.master_username
}

output "redshift_master_password" {
  description = "Senha master do Redshift (sensível — não commite outputs)"
  value       = local.redshift_password
  sensitive   = true
}

output "psql_connection_string" {
  description = "String pronta para conectar via psql"
  value       = "PGPASSWORD='***' psql -h ${aws_redshift_cluster.dw.dns_name} -p 5439 -U ${aws_redshift_cluster.dw.master_username} -d ${aws_redshift_cluster.dw.database_name}"
}

output "next_steps" {
  description = "Próximos passos após terraform apply"
  value       = <<-EOT

    ══════════════════════════════════════════════════════════════════
     INFRAESTRUTURA PRONTA — Lab 03 Data Modeling & Data Warehouse
    ══════════════════════════════════════════════════════════════════

    1) Carregue o dataset TPC-H SF1 para o S3:

         cd ../  # sair de 1-provisionamento
         bash 1-provisionamento/scripts/load_tpch.sh

    2) Veja a senha do Redshift (sensível):

         terraform output -raw redshift_master_password

    3) Conecte via Query Editor v2 no console AWS:
         https://console.aws.amazon.com/sqlworkbench/home

       Ou via psql no Codespaces:
         $(terraform output -raw psql_connection_string)

    4) Abra o Lab 03.1:
         cd ../2-modelagem-e-carga/
         cat README.md

    LEMBRETE: ao final da aula, rode terraform destroy!

  EOT
}
