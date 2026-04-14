# 02.3 - Consumindo tabelas Iceberg no Athena

**Antes de começar, execute os passos abaixo para configurar o ambiente caso não tenha feito isso ainda na aula de HOJE: [Preparando Credenciais](../../00-create-codespaces/Inicio-de-aula.md)**

Neste laboratório, você explorará como usar o Amazon Athena para consultar tabelas Iceberg.

Observe que o Amazon Athena fornece suporte integrado para o Apache Iceberg, permitindo ler e gravar em tabelas Iceberg sem configurações adicionais. Isso é válido para tabelas na [especificação Iceberg v2](https://iceberg.apache.org/spec/#version-2-row-level-deletes).

## Principais pontos de aprendizagem

- consultar tabelas Iceberg no Athena
- usar `EXPLAIN` e `EXPLAIN ANALYZE`
- criar e consultar views sobre tabelas Iceberg

## O que você precisa já ter pronto

Você consultará as tabelas `web_sales_iceberg` e `customer_iceberg` que foram criadas em laboratórios anteriores de Glue, EMR ou Athena.

> [!IMPORTANT]
> Esta parte depende diretamente dos laboratórios anteriores. Se as tabelas ainda não existirem, volte e conclua os exercícios anteriores antes de continuar.

---

## Parte 1 - Escolhendo o banco correto

### Resultado esperado desta parte

Ao final desta etapa, você terá selecionado o banco correspondente ao laboratório anterior que usou para criar as tabelas.

Esta seção pode ser usada para consultar qualquer uma das tabelas criadas anteriormente.

Selecione no painel esquerdo do Athena o banco correspondente ao ambiente em que você criou as tabelas:

- `glue_iceberg_db`, se criou as tabelas no laboratório de Glue
- `emr_iceberg_db`, se criou as tabelas no laboratório de EMR
- `athena_iceberg_db`, se criou as tabelas no laboratório de Athena

![db_selection](img/select_db_athena.png)

> [!TIP]
> Esse é o ponto de erro mais comum deste laboratório. Se a consulta disser que a tabela não existe, a primeira validação é conferir se o banco selecionado está correto.

---

## Parte 2 - Consultando tabelas Iceberg

### Resultado esperado desta parte

Ao final desta etapa, você terá executado consultas básicas sobre as tabelas Iceberg.

1. Execute a consulta abaixo para consultar um conjunto de dados Iceberg:

```sql
SELECT ws_warehouse_sk, count(distinct(ws_order_number)) as num_orders
FROM web_sales_iceberg
WHERE ws_warehouse_sk in (5,6,10,11)
GROUP BY ws_warehouse_sk
```

2. Verifique a quantidade de registros presentes na tabela de clientes:

```sql
SELECT count(*)
FROM customer_iceberg
```

### Observação importante

As consultas seguem a [especificação de formato Iceberg v2](https://iceberg.apache.org/spec/#format-versioning). Caso a consulta seja executada sobre uma tabela que tenha usado `merge-on-read` — por exemplo, tabelas em `athena_iceberg_db` — os arquivos de exclusão por posição serão mesclados com os arquivos de dados no momento da leitura.

<details>
<summary><b>Explicação do consumo de tabelas Iceberg no Athena</b></summary>
<blockquote>

Do ponto de vista do usuário, a leitura parece uma consulta SQL comum. A diferença é que o Athena resolve internamente a camada de snapshots, manifestos e arquivos de deleção do Iceberg antes de entregar o resultado final.

Isso permite consultar dados atualizados e consistentes sem que você precise manipular arquivos do data lake manualmente.

Documentação oficial:
- [Consultar Apache Iceberg no Athena](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html)
- [Especificação oficial do Apache Iceberg](https://iceberg.apache.org/spec/)

</blockquote>
</details>

### Checkpoint

Se você chegou até aqui, então:

- o banco correto foi selecionado
- as tabelas estão acessíveis
- as consultas básicas estão funcionando

---

## Parte 3 - Usando EXPLAIN e EXPLAIN ANALYZE

### Resultado esperado desta parte

Ao final desta etapa, você terá inspecionado o plano de execução e o custo computacional de consultas no Athena.

3. Use `EXPLAIN` para visualizar o plano lógico ou distribuído da consulta:

```sql
EXPLAIN SELECT count(*) FROM customer_iceberg LIMIT 10;
```

4. Use `EXPLAIN ANALYZE` para visualizar o plano de execução distribuído com custo computacional:

```sql
EXPLAIN ANALYZE
SELECT ws_warehouse_sk, count(distinct(ws_order_number)) as num_orders
FROM web_sales_iceberg
WHERE ws_warehouse_sk in (5,6,10,11)
GROUP BY ws_warehouse_sk
```

<details>
<summary><b>Explicação dos comandos EXPLAIN e EXPLAIN ANALYZE</b></summary>
<blockquote>

Nesta aula, esses comandos são úteis para enxergar como o Athena pretende executar a consulta e quanto trabalho realmente foi feito.

Use:

- `EXPLAIN` para ver o plano lógico e distribuído antes da execução completa
- `EXPLAIN ANALYZE` para medir o comportamento real, incluindo leitura e processamento

Esse tipo de análise ajuda a validar pruning, distribuição e custo de consultas sobre tabelas Iceberg.

Documentação oficial:
- [EXPLAIN e EXPLAIN ANALYZE no Athena](https://docs.aws.amazon.com/athena/latest/ug/athena-explain-statement.html)
- [Como entender os resultados do EXPLAIN](https://docs.aws.amazon.com/athena/latest/ug/athena-explain-statement-understanding.html)

</blockquote>
</details>

> [!TIP]
> Use `EXPLAIN` quando quiser validar ou entender a estratégia de execução. Use `EXPLAIN ANALYZE` quando quiser inspecionar custo real de processamento.

---

## Parte 4 - Criando e consultando visualizações

### Resultado esperado desta parte

Ao final desta etapa, você terá criado uma view sobre a tabela Iceberg e consultado seu resultado.

5. Crie a view abaixo:

```sql
CREATE VIEW total_orders_by_warehouse
AS
SELECT ws_warehouse_sk, count(distinct(ws_order_number)) as num_orders
FROM web_sales_iceberg
WHERE ws_warehouse_sk in (5,6,10,11)
GROUP BY ws_warehouse_sk
```

A execução deve terminar com **Consulta bem-sucedida**.

<details>
<summary><b>Explicação do comando CREATE VIEW</b></summary>
<blockquote>

A view salva uma consulta lógica reutilizável sobre a tabela Iceberg, sem duplicar os dados no S3.

Isso é útil para:

- simplificar consultas recorrentes
- padronizar métricas e recortes analíticos
- entregar uma camada mais amigável para consumo por times de negócio

Documentação oficial:
- [CREATE VIEW no Athena](https://docs.aws.amazon.com/athena/latest/ug/views-console.html)
- [Consultar Apache Iceberg no Athena](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html)

</blockquote>
</details>

6. Consulte a view criada:

```sql
SELECT *
FROM total_orders_by_warehouse
```

### Checkpoint final

Se você chegou até aqui, então:

- conseguiu consultar tabelas Iceberg diretamente
- conseguiu analisar consultas com `EXPLAIN` e `EXPLAIN ANALYZE`
- conseguiu criar uma `VIEW` sobre dados Iceberg no Athena

---

## Conclusão

Este laboratório fecha o ciclo de uso das tabelas Iceberg pelo ponto de vista do consumo analítico.

A partir daqui, o aluno já consegue:

- localizar o banco correto
- consultar tabelas Iceberg
- interpretar o plano de execução
- criar abstrações reutilizáveis com `VIEW`
