<p align="center">
  <img src="FIAP.png" alt="FIAP" width="100%"/>
</p>

# Data Warehouse, Lakehouse e Data Mesh

Repositório oficial dos laboratórios práticos da disciplina **Data Warehouse, Lakehouse e Data Mesh** do MBA da FIAP. Aqui você encontrará todos os exercícios guiados, scripts de apoio e instruções para evoluir da camada de storage até o consumo de tabelas em formato aberto (Open Table Format) na nuvem AWS.

---

## Visão geral

Os laboratórios foram desenhados para serem executados em um ambiente padronizado (GitHub Codespaces + AWS Academy), garantindo que todos os alunos tenham a mesma experiência, sem precisar instalar nada localmente.

Você irá percorrer um caminho que evolui da fundação do Data Lake até o consumo analítico em um Data Warehouse tradicional:

1. **Preparação do ambiente** — configuração do Codespaces, AWS Academy, credenciais e chave SSH.
2. **Storage** — envio de arquivos ao S3 e estratégias de upload.
3. **Open Table Format** — criação, evolução e consumo de tabelas Apache Iceberg usando o Amazon Athena.
4. **Data Modeling e Data Warehouse** — infraestrutura Redshift via Terraform, modelagem dimensional com star schema, SCDs e análise de como a evolução do negócio impacta o modelo.

---

## Pré-requisitos

Antes de iniciar qualquer laboratório, você precisa de:

- uma conta no [GitHub](https://github.com) (para fork do repositório e Codespaces)
- uma conta ativa no [AWS Academy](https://www.awsacademy.com/LMS_Login) com a turma `AWS Academy Learner Lab`
- acesso ao email institucional da FIAP (`rm<SEU RM>@fiap.com.br`)

> [!IMPORTANT]
> **SEMPRE DESLIGUE** o Codespaces ao final da aula para não consumir créditos desnecessariamente. Acesse [github.com/codespaces](https://github.com/codespaces), clique nos três pontinhos ao lado do ambiente e selecione `Stop Codespace`.

---

## Como usar este repositório

### 1. Faça o fork

Clique em `Fork` no canto superior direito da página do repositório no GitHub e copie-o para sua conta. Mantenha a opção `Copy the master branch only` **desmarcada** para ter acesso a todas as branches.

### 2. Crie o Codespaces

A partir do seu fork, crie um Codespace usando a configuração `FIAP Lab` na região `US East` com máquina `2-core`. O ambiente já vem com todas as dependências necessárias (AWS CLI, Python, bibliotecas e scripts de apoio).

### 3. Configure as credenciais AWS

A cada sessão do AWS Academy, copie as credenciais em `AWS Details → AWS CLI` para o arquivo `~/.aws/credentials` do Codespaces. Valide com:

```bash
aws s3 ls
```

### 4. Siga os laboratórios na ordem

Comece pelo setup e avance sequencialmente. Cada laboratório tem seu próprio `README.md` com instruções passo a passo, explicações contextuais (blocos `💡 Clique para entender`) e prints de referência.

> [!TIP]
> O passo a passo completo de configuração está em [00-create-codespaces/README.md](00-create-codespaces/README.md). Guarde esse material — você vai reutilizá-lo em toda aula ao atualizar as credenciais.

---

## Demos disponíveis

| # | Laboratório | Descrição | Link |
|---|-------------|-----------|------|
| 00 | **Setup e configuração do ambiente** | Fork do repositório, criação do Codespaces, acesso à conta AWS Academy, criação do bucket base no S3, configuração de credenciais e chave SSH. | [00-create-codespaces](00-create-codespaces/README.md) |
| 01.1 | **Storage de objetos no S3** | Envio de arquivos de diferentes tamanhos para o S3, comparação entre estratégias de upload (multipart, transfer acceleration) e análise do comportamento do S3 para arquivos grandes, médios e pequenos. | [01-Storage/01-Storage-de-Objetos](01-Storage/01-Storage-de-Objetos/README.md) |
| 02.1 | **Iceberg — Funcionalidades básicas** | Criação de tabelas Apache Iceberg no Athena, operações de `INSERT`, `UPDATE`, `DELETE`, consulta de snapshots e histórico (`FOR VERSION AS OF`, `FOR TIMESTAMP AS OF`) e evolução de esquema. | [02-Open-Table-Format/01-Funcionalidades-Basicas](02-Open-Table-Format/01-Funcionalidades-Basicas/README.md) |
| 02.2 | **Iceberg — Funcionalidades avançadas** | Particionamento oculto (hidden partitioning), uso de `MERGE INTO` para atualizações condicionais e manutenção de tabelas com `OPTIMIZE`. | [02-Open-Table-Format/02-Funcionalidades-avancadas](02-Open-Table-Format/02-Funcionalidades-avancadas/README.md) |
| 02.3 | **Iceberg — Consumindo tabelas** | Consulta de tabelas Iceberg no Athena, uso de `EXPLAIN` e `EXPLAIN ANALYZE` para análise de planos e criação de views sobre tabelas Iceberg. | [02-Open-Table-Format/03-Consumindo-tabelas](02-Open-Table-Format/03-Consumindo-tabelas/README.md) |
| 03.1 | **Data Modeling — Provisionamento** | Sobe toda a infraestrutura do lab (S3, Glue Data Catalog, cluster Redshift `ra3.large` × 2 nós) via Terraform com state remoto no S3 e carrega o dataset TPC-H SF10 (~10 GB, 60M linhas em `lineitem`) com o script `load_tpch.sh` em ~1m40 via S3-to-S3 server-side copy. | [03-Data-Modeling-e-Data-Warehouse/01-provisionamento](03-Data-Modeling-e-Data-Warehouse/01-provisionamento/README.md) |
| 03.2 | **Do OLTP ao Star Schema** | Implementa três modelagens da mesma base TPC-H (espelho OLTP, star SCD Tipo 1, star SCD Tipo 2), executa a mesma pergunta de negócio nas três e observa por que os números divergem legitimamente. Fecha com um `DECISION.md` no estilo ADR. | [03-Data-Modeling-e-Data-Warehouse/02-modelagem-e-carga](03-Data-Modeling-e-Data-Warehouse/02-modelagem-e-carga/README.md) |
| 03.3 | **Evolução do negócio no warehouse** | Três evoluções aplicadas sobre o star schema: nova fórmula de receita com Materialized Views versionadas, redefinição de "cliente ativo" (SCD2 × fato snapshot periódico) e SLA de 5s no dashboard executivo via redesign de distkey + MV pré-agregada. | [03-Data-Modeling-e-Data-Warehouse/03-analise-dimensional](03-Data-Modeling-e-Data-Warehouse/03-analise-dimensional/README.md) |

---

## Estrutura do repositório

```
.
├── 00-create-codespaces/              # Setup do ambiente (Codespaces, AWS Academy, credenciais)
├── 01-Storage/
│   └── 01-Storage-de-Objetos/         # Lab de storage no S3
├── 02-Open-Table-Format/
│   ├── 01-Funcionalidades-Basicas/     # Lab Iceberg básico (INSERT/UPDATE/DELETE, time travel)
│   ├── 02-Funcionalidades-avancadas/   # Lab Iceberg avançado (partitioning, MERGE, OPTIMIZE)
│   └── 03-Consumindo-tabelas/          # Lab de consumo de tabelas Iceberg
├── 03-Data-Modeling-e-Data-Warehouse/
│   ├── 01-provisionamento/             # Lab 03.1 — Terraform + script de carga do TPC-H SF10
│   ├── 02-modelagem-e-carga/           # Lab 03.2 — três modelagens, três respostas
│   └── 03-analise-dimensional/         # Lab 03.3 — evolução do negócio no warehouse
├── .devcontainer/                     # Configuração do GitHub Codespaces
└── FIAP.png
```

---

## Fluxo recomendado

```
00 Setup
   │
   ▼
01 Storage
   │
   ▼
02.1 Iceberg básico ──▶ 02.2 Iceberg avançado ──▶ 02.3 Consumo
   │
   ▼
03.1 Provisionamento ──▶ 03.2 Star Schema ──▶ 03.3 Evolução do negócio
```

Cada laboratório assume que os anteriores foram concluídos. Em especial:

- Os labs de **Open Table Format (02.x)** dependem do bucket `base-config-<SEU RM>` criado no setup inicial e do ambiente TPC-DS preparado no primeiro lab do Athena.
- Os labs de **Data Warehouse (03.x)** dependem da infraestrutura provisionada pelo Terraform em `03-Data-Modeling-e-Data-Warehouse/01-provisionamento/` e usam o dataset TPC-H SF10 carregado pelo script `load_tpch.sh` (S3-to-S3 server-side copy, ~1m40).

---

## Dicas gerais

- **Blocos `💡 Clique para entender`**: sempre que encontrar nos READMEs, abra — eles trazem o contexto técnico e a motivação pedagógica de cada comando.
- **Erro de tabela inexistente no Athena?** Verifique se o banco selecionado no painel esquerdo corresponde ao laboratório em que as tabelas foram criadas (`athena_iceberg_db`, `glue_iceberg_db`, etc.).
- **Credenciais expiradas?** Cada sessão do AWS Academy dura 4 horas. Basta iniciar uma nova sessão e recopiar as credenciais para `~/.aws/credentials`.
- **Cluster Redshift consumindo budget?** Ao final de cada aula, rode `terraform destroy -auto-approve` dentro de `03-Data-Modeling-e-Data-Warehouse/01-provisionamento/` para zerar os recursos. O cluster `ra3.large` × 2 nós custa ~$0,51/h enquanto estiver provisionado, mesmo ocioso (~$12/dia se esquecer ligado).

---

## Suporte

Caso encontre algum problema:

1. Releia atentamente o passo em que você está — os READMEs trazem os erros mais comuns sinalizados com `> [!IMPORTANT]` ou `> [!WARNING]`.
2. Valide os pré-requisitos listados no início de cada laboratório.
3. Consulte o professor ou monitores durante a aula.

### Contato

Ficou com alguma dúvida ou quer trocar uma ideia sobre os laboratórios?

- 📧 **Email:** [Rafael@rfbarbosa.com](mailto:Rafael@rfbarbosa.com)
- 💼 **LinkedIn:** [Rafael Barbosa](https://www.linkedin.com/in/rafael-barbosa-serverless/)

---

**Bons estudos!** 🎓
