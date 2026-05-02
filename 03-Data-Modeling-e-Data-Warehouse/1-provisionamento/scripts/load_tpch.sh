#!/usr/bin/env bash
# =============================================================================
# load_tpch.sh — Download TPC-H SF1, conversão para Parquet, upload para S3
# =============================================================================
# Executar APÓS terraform apply. Este script:
#   1. Lê os outputs do Terraform (bucket, região)
#   2. Baixa os arquivos .tbl do TPC-H SF1 do bucket público da AWS
#   3. Converte cada .tbl para Parquet (snappy) via Python/pyarrow
#   4. Gera a tabela sintética customer_history (reclassificações pós-1995)
#   5. Faz upload para s3://<bucket>/raw/tpch/<tabela>/
#   6. Registra as tabelas no Glue Data Catalog
#
# Uso:
#   bash 1-provisionamento/scripts/load_tpch.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# -----------------------------------------------------------------------------
# Pré-requisitos
# -----------------------------------------------------------------------------
command -v aws >/dev/null || { echo "ERRO: aws CLI não encontrado"; exit 1; }
command -v terraform >/dev/null || { echo "ERRO: terraform não encontrado"; exit 1; }
command -v python3 >/dev/null || { echo "ERRO: python3 não encontrado"; exit 1; }

python3 -c "import pandas, pyarrow" 2>/dev/null || {
  echo ">> Instalando pandas + pyarrow..."
  pip install --quiet --user pandas pyarrow
}

# -----------------------------------------------------------------------------
# Ler outputs do Terraform (fonte única de verdade)
# -----------------------------------------------------------------------------
cd "${TF_DIR}"

if [[ ! -f terraform.tfstate ]]; then
  echo "ERRO: terraform.tfstate não encontrado em ${TF_DIR}"
  echo "      Rode 'terraform init && terraform apply' antes deste script."
  exit 1
fi

BUCKET=$(terraform output -raw s3_bucket_name)
REGION=$(terraform output -raw region)
GLUE_DB=$(terraform output -raw glue_database_name)

echo "══════════════════════════════════════════════════════════════════"
echo " TPC-H SF1 Loader"
echo "══════════════════════════════════════════════════════════════════"
echo " Bucket  : s3://${BUCKET}/raw/tpch/"
echo " Região  : ${REGION}"
echo " Glue DB : ${GLUE_DB}"
echo "══════════════════════════════════════════════════════════════════"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT
echo ">> Workspace temporário: ${WORK_DIR}"

# -----------------------------------------------------------------------------
# TPC-H SF1 schemas (DDL) — para registrar no Glue Catalog
# -----------------------------------------------------------------------------
# Ordem matters: nation/region primeiro (pequenas, referenciadas por join)
TABLES=(nation region customer supplier part partsupp orders lineitem)

# -----------------------------------------------------------------------------
# Download do TPC-H (bucket público oficial usado em tutoriais Redshift)
# Fonte: s3://redshift-downloads/TPC-H/2.18/1GB/<table>.tbl
# Cada arquivo é texto delimitado por "|" — convertido para Parquet a seguir.
# -----------------------------------------------------------------------------
echo ""
echo ">> Baixando TPC-H SF1 do bucket público AWS..."
for t in "${TABLES[@]}"; do
  echo "   - ${t}.tbl"
  aws s3 cp "s3://redshift-downloads/TPC-H/2.18/1GB/${t}.tbl" "${WORK_DIR}/${t}.tbl" \
    --no-sign-request --only-show-errors
done

# -----------------------------------------------------------------------------
# Conversão .tbl -> Parquet via Python
# -----------------------------------------------------------------------------
echo ""
echo ">> Convertendo para Parquet (snappy)..."

python3 - <<'PYEOF'
import os
import sys
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

WORK_DIR = os.environ["WORK_DIR"]

# Schemas TPC-H (nome e tipo de cada coluna)
# Baseados na especificação oficial TPC-H v2.18
SCHEMAS = {
    "nation": [
        ("n_nationkey", "int32"),
        ("n_name", "string"),
        ("n_regionkey", "int32"),
        ("n_comment", "string"),
    ],
    "region": [
        ("r_regionkey", "int32"),
        ("r_name", "string"),
        ("r_comment", "string"),
    ],
    "customer": [
        ("c_custkey", "int64"),
        ("c_name", "string"),
        ("c_address", "string"),
        ("c_nationkey", "int32"),
        ("c_phone", "string"),
        ("c_acctbal", "float64"),
        ("c_mktsegment", "string"),
        ("c_comment", "string"),
    ],
    "supplier": [
        ("s_suppkey", "int64"),
        ("s_name", "string"),
        ("s_address", "string"),
        ("s_nationkey", "int32"),
        ("s_phone", "string"),
        ("s_acctbal", "float64"),
        ("s_comment", "string"),
    ],
    "part": [
        ("p_partkey", "int64"),
        ("p_name", "string"),
        ("p_mfgr", "string"),
        ("p_brand", "string"),
        ("p_type", "string"),
        ("p_size", "int32"),
        ("p_container", "string"),
        ("p_retailprice", "float64"),
        ("p_comment", "string"),
    ],
    "partsupp": [
        ("ps_partkey", "int64"),
        ("ps_suppkey", "int64"),
        ("ps_availqty", "int32"),
        ("ps_supplycost", "float64"),
        ("ps_comment", "string"),
    ],
    "orders": [
        ("o_orderkey", "int64"),
        ("o_custkey", "int64"),
        ("o_orderstatus", "string"),
        ("o_totalprice", "float64"),
        ("o_orderdate", "date32"),
        ("o_orderpriority", "string"),
        ("o_clerk", "string"),
        ("o_shippriority", "int32"),
        ("o_comment", "string"),
    ],
    "lineitem": [
        ("l_orderkey", "int64"),
        ("l_partkey", "int64"),
        ("l_suppkey", "int64"),
        ("l_linenumber", "int32"),
        ("l_quantity", "float64"),
        ("l_extendedprice", "float64"),
        ("l_discount", "float64"),
        ("l_tax", "float64"),
        ("l_returnflag", "string"),
        ("l_linestatus", "string"),
        ("l_shipdate", "date32"),
        ("l_commitdate", "date32"),
        ("l_receiptdate", "date32"),
        ("l_shipinstruct", "string"),
        ("l_shipmode", "string"),
        ("l_comment", "string"),
    ],
}

pd_dtype = {
    "int32": "Int32",
    "int64": "Int64",
    "float64": "float64",
    "string": "string",
    "date32": "string",  # ler como string, converter para date depois
}

for table, schema in SCHEMAS.items():
    in_path = os.path.join(WORK_DIR, f"{table}.tbl")
    out_path = os.path.join(WORK_DIR, f"{table}.parquet")
    col_names = [c[0] for c in schema]
    dtypes = {c[0]: pd_dtype[c[1]] for c in schema}

    print(f"   - {table} ({os.path.getsize(in_path)/1024/1024:.1f} MB)")

    # TPC-H .tbl tem um separador "|" e um pipe final em cada linha → coluna extra
    df = pd.read_csv(
        in_path,
        sep="|",
        header=None,
        names=col_names + ["__trailing"],
        dtype=dtypes,
        parse_dates=False,
        engine="c",
    ).drop(columns="__trailing")

    # Converte colunas de data
    for col, typ in schema:
        if typ == "date32":
            df[col] = pd.to_datetime(df[col], format="%Y-%m-%d", errors="coerce").dt.date

    # Grava Parquet
    table_pa = pa.Table.from_pandas(df, preserve_index=False)
    pq.write_table(table_pa, out_path, compression="snappy")
    print(f"     -> {out_path}")

PYEOF

export WORK_DIR

# -----------------------------------------------------------------------------
# Geração da tabela sintética customer_history
# -----------------------------------------------------------------------------
# Para viabilizar SCD Tipo 2 no Lab 03.1, injetamos reclassificações
# posteriores a 1995 em ~5% dos clientes. Essa tabela NÃO existe no TPC-H
# original; é uma simulação didática.
#
# Schema:
#   c_custkey      (int64)       — FK para customer
#   mktsegment_new (string)      — novo segmento (reclassificação)
#   valid_from     (date)        — data em que o novo segmento passou a valer
#
# Pedagogicamente, isso permite perguntas como:
#   "Qual era o segmento do cliente X no momento da venda em 1995-06-12?"
# -----------------------------------------------------------------------------
echo ""
echo ">> Gerando customer_history (reclassificações sintéticas)..."

python3 - <<'PYEOF'
import os
import random
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

WORK_DIR = os.environ["WORK_DIR"]
random.seed(42)  # reproduzibilidade — todo aluno gera o mesmo dataset

# Lê a dimensão customer já convertida para Parquet
cust = pd.read_parquet(os.path.join(WORK_DIR, "customer.parquet"))

# Sorteia 5% dos clientes para reclassificação
sample = cust.sample(frac=0.05, random_state=42).copy()

segments = ["BUILDING", "AUTOMOBILE", "MACHINERY", "HOUSEHOLD", "FURNITURE"]

def pick_new(old):
    choices = [s for s in segments if s != old]
    return random.choice(choices)

sample["mktsegment_new"] = sample["c_mktsegment"].apply(pick_new)

# Distribui datas de mudança entre 1996-01-01 e 1998-12-31
# (após o ano de 1995 usado na query-âncora — mudanças "futuras" em relação à venda)
dates = pd.date_range("1996-01-01", "1998-12-31", freq="D")
sample["valid_from"] = [random.choice(dates).date() for _ in range(len(sample))]

history = sample[["c_custkey", "mktsegment_new", "valid_from"]].reset_index(drop=True)

out_path = os.path.join(WORK_DIR, "customer_history.parquet")
pq.write_table(pa.Table.from_pandas(history, preserve_index=False), out_path, compression="snappy")

print(f"   - customer_history: {len(history)} reclassificações")
print(f"     -> {out_path}")
PYEOF

# -----------------------------------------------------------------------------
# Upload para S3
# -----------------------------------------------------------------------------
echo ""
echo ">> Enviando Parquet para s3://${BUCKET}/raw/tpch/..."

for t in "${TABLES[@]}" customer_history; do
  src="${WORK_DIR}/${t}.parquet"
  dst="s3://${BUCKET}/raw/tpch/${t}/${t}.parquet"
  echo "   - ${t} -> ${dst}"
  aws s3 cp "${src}" "${dst}" --only-show-errors
done

# -----------------------------------------------------------------------------
# Registro no Glue Data Catalog
# -----------------------------------------------------------------------------
# Catalogamos as tabelas para referência/visualização no console Glue.
# O lab não usa Spectrum (não listado no PDF do Learner Lab), mas o catálogo
# serve como documentação viva da estrutura dos Parquets.
# -----------------------------------------------------------------------------
echo ""
echo ">> Registrando tabelas no Glue Data Catalog (${GLUE_DB})..."

register_glue_table() {
  local table=$1
  local columns_json=$2
  local location="s3://${BUCKET}/raw/tpch/${table}/"

  # Remove se já existir (idempotência)
  aws glue delete-table \
    --database-name "${GLUE_DB}" \
    --name "${table}" \
    --region "${REGION}" 2>/dev/null || true

  aws glue create-table \
    --database-name "${GLUE_DB}" \
    --region "${REGION}" \
    --table-input "{
      \"Name\": \"${table}\",
      \"TableType\": \"EXTERNAL_TABLE\",
      \"Parameters\": {
        \"classification\": \"parquet\",
        \"has_encrypted_data\": \"false\"
      },
      \"StorageDescriptor\": {
        \"Columns\": ${columns_json},
        \"Location\": \"${location}\",
        \"InputFormat\": \"org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat\",
        \"OutputFormat\": \"org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat\",
        \"SerdeInfo\": {
          \"SerializationLibrary\": \"org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe\"
        }
      }
    }" >/dev/null
  echo "   - ${table}"
}

register_glue_table nation '[
  {"Name":"n_nationkey","Type":"int"},
  {"Name":"n_name","Type":"string"},
  {"Name":"n_regionkey","Type":"int"},
  {"Name":"n_comment","Type":"string"}
]'

register_glue_table region '[
  {"Name":"r_regionkey","Type":"int"},
  {"Name":"r_name","Type":"string"},
  {"Name":"r_comment","Type":"string"}
]'

register_glue_table customer '[
  {"Name":"c_custkey","Type":"bigint"},
  {"Name":"c_name","Type":"string"},
  {"Name":"c_address","Type":"string"},
  {"Name":"c_nationkey","Type":"int"},
  {"Name":"c_phone","Type":"string"},
  {"Name":"c_acctbal","Type":"double"},
  {"Name":"c_mktsegment","Type":"string"},
  {"Name":"c_comment","Type":"string"}
]'

register_glue_table supplier '[
  {"Name":"s_suppkey","Type":"bigint"},
  {"Name":"s_name","Type":"string"},
  {"Name":"s_address","Type":"string"},
  {"Name":"s_nationkey","Type":"int"},
  {"Name":"s_phone","Type":"string"},
  {"Name":"s_acctbal","Type":"double"},
  {"Name":"s_comment","Type":"string"}
]'

register_glue_table part '[
  {"Name":"p_partkey","Type":"bigint"},
  {"Name":"p_name","Type":"string"},
  {"Name":"p_mfgr","Type":"string"},
  {"Name":"p_brand","Type":"string"},
  {"Name":"p_type","Type":"string"},
  {"Name":"p_size","Type":"int"},
  {"Name":"p_container","Type":"string"},
  {"Name":"p_retailprice","Type":"double"},
  {"Name":"p_comment","Type":"string"}
]'

register_glue_table partsupp '[
  {"Name":"ps_partkey","Type":"bigint"},
  {"Name":"ps_suppkey","Type":"bigint"},
  {"Name":"ps_availqty","Type":"int"},
  {"Name":"ps_supplycost","Type":"double"},
  {"Name":"ps_comment","Type":"string"}
]'

register_glue_table orders '[
  {"Name":"o_orderkey","Type":"bigint"},
  {"Name":"o_custkey","Type":"bigint"},
  {"Name":"o_orderstatus","Type":"string"},
  {"Name":"o_totalprice","Type":"double"},
  {"Name":"o_orderdate","Type":"date"},
  {"Name":"o_orderpriority","Type":"string"},
  {"Name":"o_clerk","Type":"string"},
  {"Name":"o_shippriority","Type":"int"},
  {"Name":"o_comment","Type":"string"}
]'

register_glue_table lineitem '[
  {"Name":"l_orderkey","Type":"bigint"},
  {"Name":"l_partkey","Type":"bigint"},
  {"Name":"l_suppkey","Type":"bigint"},
  {"Name":"l_linenumber","Type":"int"},
  {"Name":"l_quantity","Type":"double"},
  {"Name":"l_extendedprice","Type":"double"},
  {"Name":"l_discount","Type":"double"},
  {"Name":"l_tax","Type":"double"},
  {"Name":"l_returnflag","Type":"string"},
  {"Name":"l_linestatus","Type":"string"},
  {"Name":"l_shipdate","Type":"date"},
  {"Name":"l_commitdate","Type":"date"},
  {"Name":"l_receiptdate","Type":"date"},
  {"Name":"l_shipinstruct","Type":"string"},
  {"Name":"l_shipmode","Type":"string"},
  {"Name":"l_comment","Type":"string"}
]'

register_glue_table customer_history '[
  {"Name":"c_custkey","Type":"bigint"},
  {"Name":"mktsegment_new","Type":"string"},
  {"Name":"valid_from","Type":"date"}
]'

echo ""
echo "══════════════════════════════════════════════════════════════════"
echo " ✅ TPC-H SF1 carregado com sucesso!"
echo "══════════════════════════════════════════════════════════════════"
echo " Listagem:"
aws s3 ls "s3://${BUCKET}/raw/tpch/" --recursive --human-readable --summarize | tail -20
echo ""
echo " Próximo passo: abra 2-modelagem-e-carga/README.md"
echo "══════════════════════════════════════════════════════════════════"
