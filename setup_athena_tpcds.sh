#!/usr/bin/env bash
set -Eeuo pipefail
export AWS_PAGER=""

#############################################
# setup_athena_tpcds_gdrive_uuid.sh
#
# - Descobre accountID (STS)
# - Cria bucket: otfs-aula-$accountID (idempotente)
# - Baixa ZIP público do Google Drive (sem login) usando FILE_ID + uuid
# - Valida que o download NÃO é HTML e que é um ZIP válido (unzip -t)
# - Extrai e valida estrutura esperada (datasets/TPC-DS-100-GB/...)
# - Faz upload APENAS do prefixo datasets/ para o bucket
# - Configura Athena (WorkGroup) para resultados em s3://bucket/athena-results/
# - Cria database tpcds e as tabelas (idempotente)
# - Substitui "$accountID" literal nos DDLs
#
# Requisitos (Ubuntu):
#   sudo apt-get update && sudo apt-get install -y curl unzip file
#   (awscli v2 já configurado com credenciais e região)
#############################################

#############################################
# Ajuste aqui: FILE_ID do Google Drive
#############################################
FILE_ID="1BT6QPiLktRdkGb43r9lKEn_ns6Jn3Y59"

ATHENA_WORKGROUP="otfs-aula-workgroup"
WORKDIR="/tmp/otfs-aula-setup"

# Quantidade REAL de etapas que chamam progress() abaixo.
TOTAL_STEPS=18
CURRENT_STEP=0

progress() {
  local msg="$1"
  CURRENT_STEP=$((CURRENT_STEP + 1))
  local pct=$((CURRENT_STEP * 100 / TOTAL_STEPS))
  printf "\n[%3d%%] %s\n" "$pct" "$msg"
}

die() {
  echo
  echo "ERRO: $1" >&2
  exit 1
}

on_error() {
  local lineno="$1"
  local cmd="$2"
  echo
  echo "ERRO: falha ao executar (linha $lineno): $cmd" >&2
  echo "Dica: verifique credenciais IAM, região configurada e conectividade." >&2
  exit 1
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1 (instale e rode novamente)."
}

detect_region() {
  local region=""
  region="$(aws configure get region 2>/dev/null || true)"
  if [[ -z "$region" ]]; then
    region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  fi
  if [[ -z "$region" ]]; then
    # tenta IMDS (EC2)
    local token
    token="$(curl -sS -m 2 -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true)"
    if [[ -n "$token" ]]; then
      region="$(curl -sS -m 2 -H "X-aws-ec2-metadata-token: $token" \
        "http://169.254.169.254/latest/dynamic/instance-identity/document" \
        | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)"
    else
      region="$(curl -sS -m 2 "http://169.254.169.254/latest/dynamic/instance-identity/document" \
        | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)"
    fi
  fi
  [[ -n "$region" ]] || die "Não foi possível detectar a região. Configure AWS_DEFAULT_REGION (ou aws configure set region <região>)."
  echo "$region"
}

#############################################
# Google Drive: download (sem login) usando uuid (método validado por você)
# - 1) Captura cookies e uuid da página do Drive
# - 2) Baixa pelo endpoint drive.usercontent... com confirm=t e uuid (se existir)
# - Valida: não aceita HTML e exige ZIP válido
#############################################
gdrive_download_zip_or_die() {
  local file_id="$1"
  local out_path="$2"

  local cookie_file="$WORKDIR/gdrive_cookie.txt"
  rm -f "$cookie_file" "$out_path" || true

  echo "Capturando cookies e uuid do Google Drive..."
  local uuid
  uuid="$(
    curl -sS -L -c "$cookie_file" "https://drive.google.com/uc?export=download&id=${file_id}" \
    | sed -n 's/.*name="uuid" value="\([^"]*\)".*/\1/p' \
    | head -n 1
  )"

  echo "Baixando arquivo do Google Drive (usercontent)..."
  if [[ -n "$uuid" ]]; then
    curl -fsSL -L --retry 5 --retry-all-errors --retry-delay 1 \
      -b "$cookie_file" -o "$out_path" \
      "https://drive.usercontent.google.com/download?id=${file_id}&export=download&confirm=t&uuid=${uuid}"
  else
    curl -fsSL -L --retry 5 --retry-all-errors --retry-delay 1 \
      -b "$cookie_file" -o "$out_path" \
      "https://drive.usercontent.google.com/download?id=${file_id}&export=download&confirm=t"
  fi

  [[ -s "$out_path" ]] || die "Falha no download do Google Drive ou arquivo vazio."

  # Proteção contra subir HTML por engano
  local mime
  mime="$(file -b --mime-type "$out_path" || true)"
  [[ "$mime" != "text/html" ]] || die "Download inválido: o Drive retornou HTML (página de aviso/erro), não o ZIP."

  # Valida ZIP de verdade (estrutura/CRC)
  unzip -t "$out_path" >/dev/null 2>&1 || die "Arquivo baixado não é um ZIP válido (unzip -t falhou)."

  echo "Download OK e ZIP validado: $out_path"
}

#############################################
# Extração + validação de estrutura
# Espera encontrar:
# - datasets/TPC-DS-100-GB/prepared_customer/
# - datasets/TPC-DS-100-GB/prepared_web_sales/
# Se o ZIP vier com TPC-DS-100-GB/ na raiz, reorganiza para datasets/
#############################################
extract_zip_and_validate_or_die() {
  local zip_path="$1"
  local out_dir="$2"

  rm -rf "$out_dir"
  mkdir -p "$out_dir"

  unzip -o "$zip_path" -d "$out_dir" >/dev/null

  if [[ -d "$out_dir/datasets/TPC-DS-100-GB" ]]; then
    :
  elif [[ -d "$out_dir/TPC-DS-100-GB" ]]; then
    mkdir -p "$out_dir/datasets"
    mv "$out_dir/TPC-DS-100-GB" "$out_dir/datasets/"
  else
    die "Estrutura inesperada no ZIP. Não encontrei 'datasets/TPC-DS-100-GB' nem 'TPC-DS-100-GB'. Abortando para evitar upload incorreto ao S3."
  fi

  [[ -d "$out_dir/datasets/TPC-DS-100-GB/prepared_customer" ]] || die "Não encontrei datasets/TPC-DS-100-GB/prepared_customer (estrutura incompatível com os DDLs)."
  [[ -d "$out_dir/datasets/TPC-DS-100-GB/prepared_web_sales" ]] || die "Não encontrei datasets/TPC-DS-100-GB/prepared_web_sales (estrutura incompatível com os DDLs)."

  if ! find "$out_dir/datasets/TPC-DS-100-GB" -type f | head -n 1 | grep -q .; then
    die "ZIP extraído, mas não encontrei nenhum arquivo dentro de datasets/TPC-DS-100-GB. Abortando."
  fi
}

ensure_bucket() {
  local bucket="$1"
  local region="$2"

  if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    echo "Bucket já existe: s3://$bucket"
    return 0
  fi

  echo "Criando bucket: s3://$bucket (região: $region)"
  if [[ "$region" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$bucket" >/dev/null 2>&1 || true
  else
    aws s3api create-bucket --bucket "$bucket" --create-bucket-configuration "LocationConstraint=$region" >/dev/null 2>&1 || true
  fi

  aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1 || die "Não foi possível criar/acessar o bucket s3://$bucket (nome pode existir em outra conta, ou falta permissão)."
}

ensure_workgroup() {
  local wg="$1"
  local output_location="$2"

  if aws athena get-work-group --work-group "$wg" >/dev/null 2>&1; then
    echo "WorkGroup já existe: $wg (atualizando configuração de resultados)..."
    aws athena update-work-group \
      --work-group "$wg" \
      --configuration-updates "ResultConfigurationUpdates={OutputLocation=$output_location},EnforceWorkGroupConfiguration=true,PublishCloudWatchMetricsEnabled=true" \
      >/dev/null
  else
    echo "Criando WorkGroup: $wg"
    aws athena create-work-group \
      --name "$wg" \
      --configuration "ResultConfiguration={OutputLocation=$output_location},EnforceWorkGroupConfiguration=true,PublishCloudWatchMetricsEnabled=true" \
      >/dev/null
  fi
}

athena_exec_and_wait() {
  local wg="$1"
  local output_location="$2"
  local db="$3"   # pode ser vazio
  local q="$4"

  local qid
  if [[ -n "$db" ]]; then
    qid="$(aws athena start-query-execution \
      --work-group "$wg" \
      --result-configuration "OutputLocation=$output_location" \
      --query-execution-context "Database=$db" \
      --query-string "$q" \
      --query 'QueryExecutionId' --output text)"
  else
    qid="$(aws athena start-query-execution \
      --work-group "$wg" \
      --result-configuration "OutputLocation=$output_location" \
      --query-string "$q" \
      --query 'QueryExecutionId' --output text)"
  fi

  [[ -n "$qid" && "$qid" != "None" ]] || die "Falha ao iniciar query no Athena."

  while true; do
    local state
    state="$(aws athena get-query-execution --query-execution-id "$qid" --query 'QueryExecution.Status.State' --output text)"
    case "$state" in
      SUCCEEDED) return 0 ;;
      FAILED|CANCELLED)
        local reason
        reason="$(aws athena get-query-execution --query-execution-id "$qid" --query 'QueryExecution.Status.StateChangeReason' --output text 2>/dev/null || true)"
        die "Query do Athena falhou ($state). Motivo: ${reason:-não informado}"
        ;;
      *) sleep 2 ;;
    esac
  done
}

prepare_ddl() {
  local ddl="$1"
  ddl="${ddl//\$accountID/$accountID}"
  ddl="$(echo "$ddl" | sed -E 's/^CREATE[[:space:]]+EXTERNAL[[:space:]]+TABLE[[:space:]]+/CREATE EXTERNAL TABLE IF NOT EXISTS /')"
  echo "$ddl"
}

#########################################
# Execução
#########################################

progress "Validando pré-requisitos (aws, curl, unzip, file)..."
need_cmd aws
need_cmd curl
need_cmd unzip
need_cmd file

progress "Preparando diretório de trabalho..."
mkdir -p "$WORKDIR"

progress "Detectando região AWS..."
REGION="$(detect_region)"
export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"
echo "Região: $REGION"

progress "Obtendo accountID via STS..."
accountID="$(aws sts get-caller-identity --query 'Account' --output text)"
[[ -n "$accountID" && "$accountID" != "None" ]] || die "Não foi possível obter accountID. Verifique sts:GetCallerIdentity."
echo "Account ID: $accountID"

progress "Definindo recursos..."
BUCKET="otfs-aula-$accountID"
ATHENA_OUTPUT="s3://$BUCKET/athena-results/"
echo "Bucket alvo: s3://$BUCKET"
echo "Athena output: $ATHENA_OUTPUT"
echo "WorkGroup: $ATHENA_WORKGROUP"

progress "Criando bucket S3 (idempotente)..."
ensure_bucket "$BUCKET" "$REGION"

progress "Baixando ZIP do Google Drive (validado)..."
DOWNLOADED_ZIP="$WORKDIR/bucket.zip"
gdrive_download_zip_or_die "$FILE_ID" "$DOWNLOADED_ZIP"

progress "Extraindo ZIP e validando estrutura datasets/TPC-DS-100-GB..."
EXTRACT_DIR="$WORKDIR/extracted"
extract_zip_and_validate_or_die "$DOWNLOADED_ZIP" "$EXTRACT_DIR"
echo "Conteúdo validado em: $EXTRACT_DIR/datasets/TPC-DS-100-GB"

progress "Upload do dataset para o bucket (prefixo datasets/, idempotente)..."
aws s3 sync "$EXTRACT_DIR/datasets/" "s3://$BUCKET/datasets/" --delete --only-show-errors
echo "Upload concluído: s3://$BUCKET/datasets/"

progress "Criando/atualizando WorkGroup do Athena (idempotente)..."
ensure_workgroup "$ATHENA_WORKGROUP" "$ATHENA_OUTPUT"

progress "Criando database tpcds (idempotente)..."
athena_exec_and_wait "$ATHENA_WORKGROUP" "$ATHENA_OUTPUT" "" "CREATE DATABASE IF NOT EXISTS tpcds"

progress "Criando tabela customer (idempotente)..."
DDL_CUSTOMER="$(cat <<'SQL'
CREATE EXTERNAL TABLE `customer`(
  `c_customer_sk` int, 
  `c_customer_id` string, 
  `c_current_cdemo_sk` int, 
  `c_current_hdemo_sk` int, 
  `c_current_addr_sk` int, 
  `c_first_shipto_date_sk` int, 
  `c_first_sales_date_sk` int, 
  `c_salutation` string, 
  `c_first_name` string, 
  `c_last_name` string, 
  `c_preferred_cust_flag` string, 
  `c_birth_day` int, 
  `c_birth_month` int, 
  `c_birth_year` int, 
  `c_birth_country` string, 
  `c_login` string, 
  `c_email_address` string, 
  `c_last_review_date_sk` int)
ROW FORMAT DELIMITED 
  FIELDS TERMINATED BY '|' 
STORED AS INPUTFORMAT 
  'org.apache.hadoop.mapred.TextInputFormat' 
OUTPUTFORMAT 
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://redshift-downloads/TPC-DS/100GB/customer'
TBLPROPERTIES (
  'classification'='csv', 
  'transient_lastDdlTime'='1769278218')
SQL
)"
athena_exec_and_wait "$ATHENA_WORKGROUP" "$ATHENA_OUTPUT" "tpcds" "$(prepare_ddl "$DDL_CUSTOMER")"

progress "Criando tabela date_dim (idempotente)..."
DDL_DATE_DIM="$(cat <<'SQL'
CREATE EXTERNAL TABLE `date_dim`(
  `d_date_sk` int, 
  `d_date_id` string, 
  `d_date` string, 
  `d_month_seq` int, 
  `d_week_seq` int, 
  `d_quarter_seq` int, 
  `d_year` int, 
  `d_dow` int, 
  `d_moy` int, 
  `d_dom` int, 
  `d_qoy` int, 
  `d_fy_year` int, 
  `d_fy_quarter_seq` int, 
  `d_fy_week_seq` int, 
  `d_day_name` string, 
  `d_quarter_name` string, 
  `d_holiday` string, 
  `d_weekend` string, 
  `d_following_holiday` string, 
  `d_first_dom` int, 
  `d_last_dom` int, 
  `d_same_day_ly` int, 
  `d_same_day_lq` int, 
  `d_current_day` string, 
  `d_current_week` string, 
  `d_current_month` string, 
  `d_current_quarter` string, 
  `d_current_year` string)
ROW FORMAT DELIMITED 
  FIELDS TERMINATED BY '|' 
STORED AS INPUTFORMAT 
  'org.apache.hadoop.mapred.TextInputFormat' 
OUTPUTFORMAT 
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://redshift-downloads/TPC-DS/100GB/date_dim'
TBLPROPERTIES (
  'classification'='csv', 
  'transient_lastDdlTime'='1769278296')
SQL
)"
athena_exec_and_wait "$ATHENA_WORKGROUP" "$ATHENA_OUTPUT" "tpcds" "$(prepare_ddl "$DDL_DATE_DIM")"

progress "Criando tabela prepared_customer (idempotente)..."
DDL_PREPARED_CUSTOMER="$(cat <<'SQL'
CREATE EXTERNAL TABLE `prepared_customer`
(
  `c_customer_sk` int, 
  `c_customer_id` string, 
  `c_first_name` string, 
  `c_last_name` string, 
  `c_email_address` string)
ROW FORMAT SERDE 
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe' 
STORED AS INPUTFORMAT 
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat' 
OUTPUTFORMAT 
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://otfs-aula-$accountID/datasets/TPC-DS-100-GB/prepared_customer'
TBLPROPERTIES
(
  'auto.purge'='false', 
  'has_encrypted_data'='false', 
  'numFiles'='-1', 
  'parquet.compression'='GZIP', 
  'totalSize'='-1', 
  'transactional'='false', 
  'transient_lastDdlTime'='1769278351', 
  'trino_query_id'='20260124_174744_00070_rwp9d', 
  'trino_version'='0.215-24526-g02c3358')
SQL
)"
athena_exec_and_wait "$ATHENA_WORKGROUP" "$ATHENA_OUTPUT" "tpcds" "$(prepare_ddl "$DDL_PREPARED_CUSTOMER")"

progress "Criando tabela prepared_web_sales (idempotente)..."
DDL_PREPARED_WEB_SALES="$(cat <<'SQL'
CREATE EXTERNAL TABLE `prepared_web_sales`(
  `ws_order_number` int, 
  `ws_item_sk` int, 
  `ws_quantity` int, 
  `ws_sales_price` double, 
  `ws_warehouse_sk` int, 
  `ws_sales_time` timestamp)
ROW FORMAT SERDE 
  'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe' 
STORED AS INPUTFORMAT 
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat' 
OUTPUTFORMAT 
  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
LOCATION
  's3://otfs-aula-$accountID/datasets/TPC-DS-100-GB/prepared_web_sales'
TBLPROPERTIES (
  'auto.purge'='false', 
  'has_encrypted_data'='false', 
  'numFiles'='-1', 
  'parquet.compression'='GZIP', 
  'totalSize'='-1', 
  'transactional'='false', 
  'transient_lastDdlTime'='1769278388', 
  'trino_query_id'='20260124_174744_00142_v5cch', 
  'trino_version'='0.215-24526-g02c3358')
SQL
)"
athena_exec_and_wait "$ATHENA_WORKGROUP" "$ATHENA_OUTPUT" "tpcds" "$(prepare_ddl "$DDL_PREPARED_WEB_SALES")"

progress "Criando tabela time_dim (idempotente)..."
DDL_TIME_DIM="$(cat <<'SQL'
CREATE EXTERNAL TABLE `time_dim`(
  `t_time_sk` int, 
  `t_time_id` string, 
  `t_time` int, 
  `t_hour` int, 
  `t_minute` int, 
  `t_second` int, 
  `t_am_pm` string, 
  `t_shift` string, 
  `t_sub_shift` string, 
  `t_meal_time` string)
ROW FORMAT DELIMITED 
  FIELDS TERMINATED BY '|' 
STORED AS INPUTFORMAT 
  'org.apache.hadoop.mapred.TextInputFormat' 
OUTPUTFORMAT 
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://redshift-downloads/TPC-DS/100GB/time_dim'
TBLPROPERTIES (
  'classification'='csv', 
  'transient_lastDdlTime'='1769278457')
SQL
)"
athena_exec_and_wait "$ATHENA_WORKGROUP" "$ATHENA_OUTPUT" "tpcds" "$(prepare_ddl "$DDL_TIME_DIM")"

progress "Criando tabela web_sales (idempotente)..."
DDL_WEB_SALES="$(cat <<'SQL'
CREATE EXTERNAL TABLE `web_sales`(
  `ws_sold_date_sk` int, 
  `ws_sold_time_sk` int, 
  `ws_ship_date_sk` int, 
  `ws_item_sk` int, 
  `ws_bill_customer_sk` int, 
  `ws_bill_cdemo_sk` int, 
  `ws_bill_hdemo_sk` int, 
  `ws_bill_addr_sk` int, 
  `ws_ship_customer_sk` int, 
  `ws_ship_cdemo_sk` int, 
  `ws_ship_hdemo_sk` int, 
  `ws_ship_addr_sk` int, 
  `ws_web_page_sk` int, 
  `ws_web_site_sk` int, 
  `ws_ship_mode_sk` int, 
  `ws_warehouse_sk` int, 
  `ws_promo_sk` int, 
  `ws_order_number` int, 
  `ws_quantity` int, 
  `ws_wholesale_cost` double, 
  `ws_list_price` double, 
  `ws_sales_price` double, 
  `ws_ext_discount_amt` double, 
  `ws_ext_sales_price` double, 
  `ws_ext_wholesale_cost` double, 
  `ws_ext_list_price` double, 
  `ws_ext_tax` double, 
  `ws_coupon_amt` double, 
  `ws_ext_ship_cost` double, 
  `ws_net_paid` double, 
  `ws_net_paid_inc_tax` double, 
  `ws_net_paid_inc_ship` double, 
  `ws_net_paid_inc_ship_tax` double, 
  `ws_net_profit` double)
ROW FORMAT DELIMITED 
  FIELDS TERMINATED BY '|' 
STORED AS INPUTFORMAT 
  'org.apache.hadoop.mapred.TextInputFormat' 
OUTPUTFORMAT 
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://redshift-downloads/TPC-DS/100GB/web_sales'
TBLPROPERTIES (
  'classification'='csv', 
  'transient_lastDdlTime'='1769278100')
SQL
)"
athena_exec_and_wait "$ATHENA_WORKGROUP" "$ATHENA_OUTPUT" "tpcds" "$(prepare_ddl "$DDL_WEB_SALES")"

progress "Validação final (SHOW TABLES)..."
athena_exec_and_wait "$ATHENA_WORKGROUP" "$ATHENA_OUTPUT" "tpcds" "SHOW TABLES"

echo
echo "[100%] Concluído com sucesso."
echo "Bucket: s3://$BUCKET"
echo "Athena WorkGroup: $ATHENA_WORKGROUP"
echo "Athena Output: $ATHENA_OUTPUT"
echo "Database: tpcds"
echo "Tabelas: customer, date_dim, prepared_customer, prepared_web_sales, time_dim, web_sales"
