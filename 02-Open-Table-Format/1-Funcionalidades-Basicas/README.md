# 02.1 - Funcionalidades básicas com Apache Iceberg no Athena

**Antes de começar, execute os passos abaixo para configurar o ambiente caso não tenha feito isso ainda na aula de HOJE: [Preparando Credenciais](../../00-create-codespaces/Inicio-de-aula.md)**

Neste laboratório, você explorará as funcionalidades básicas do Apache Iceberg e aprenderá a criar e modificar tabelas Iceberg com o Amazon Athena.

Observe que o Amazon Athena fornece suporte integrado para o Apache Iceberg, permitindo ler e gravar em tabelas Iceberg sem adicionar dependências ou configurações extras. Isso é válido para tabelas na [especificação Iceberg v2](https://iceberg.apache.org/spec/#version-2-row-level-deletes).

## Principais pontos de aprendizagem

- criar tabelas Iceberg
- inserir dados em uma tabela Iceberg
- atualizar um único registro
- excluir registros de uma tabela Iceberg
- consultar snapshots e histórico
- evoluir o esquema da tabela

## O que você terá ao final

Ao final deste laboratório, você terá criado uma tabela Iceberg no Athena, carregado dados nela, executado operações de `INSERT`, `UPDATE`, `DELETE`, `FOR VERSION AS OF`, `FOR TIMESTAMP AS OF` e mudanças de esquema.

---

## Parte 1 - Pré-requisitos e criação do ambiente

### Resultado esperado desta parte

Ao final desta etapa, o ambiente base do Athena estará pronto para o laboratório.

1. No Codespaces da disciplina, abra um terminal integrado.

![](img/terminal-inicial.png)

2. No terminal, execute o script abaixo para preparar automaticamente o ambiente do laboratório no Athena, baixando os dados TPC-DS, enviando-os ao S3 e criando as tabelas necessárias:

```bash
cd /workspaces/fiap-cloud-based-analytics && bash setup_athena_tpcds.sh
```

<details>
<summary><b>Explicação do preparo automático do ambiente</b></summary>
<blockquote>

Esse script centraliza a preparação do laboratório para que o foco fique no Apache Iceberg e não no setup manual.

No contexto desta aula, ele normalmente:

- prepara ou baixa os dados de exemplo
- envia os arquivos necessários para o S3
- cria a base que será usada nas consultas do Athena
- deixa o ambiente pronto para as operações com tabelas Iceberg

Você não precisa memorizar o conteúdo interno do script neste momento. O importante é garantir que a base esteja pronta para as próximas consultas e alterações de dados.

Documentação oficial:
- [Usando Apache Iceberg com o Athena](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html)
- [Criação de tabelas no Athena](https://docs.aws.amazon.com/athena/latest/ug/create-table.html)

</blockquote>
</details>

![img/criacao-tabela.png](img/criacao-tabela.png)

> [!IMPORTANT]
> Só siga para a próxima parte depois que esse script terminar com sucesso.

---

## Parte 2 - Configurando o Athena

### Resultado esperado desta parte

Ao final desta etapa, o editor de consultas do Athena estará configurado para salvar resultados no bucket correto.

3. Acesse o [console do Amazon Athena](https://us-east-1.console.aws.amazon.com/athena/home?region=us-east-1#/landing-page).

4. Selecione **Consulte seus dados no console do Athena** e depois **Iniciar editor de consultas**.

![athena_searchbar](img/athena_launch_query_editor.png)

5. Quando estiver dentro do Athena, clique em **Editar configurações** e depois em **Gerenciar**.

![athena_setup](img/athena_initial_setup.png)

![athena_setup1](img/athena_initial_setup1.png)

6. Clique em `Browse S3`, selecione o bucket que inicia com `otfs-aula`, escolha a pasta `athena_res/` e depois clique em `Choose` e `Salvar`.

![athena_reslocation_setup](img/athena_reslocation_setup.png)

![athena_reslocation_setup](img/athena_reslocation_setup1.png)

![athena_reslocation_setup](img/athena_reslocation_setup2.png)

![athena_reslocation_setup](img/athena_reslocation_setup3.png)

7. Volte para a tela do **Editor**.

![athena_editor](img/athena-editor.png)

### Checkpoint

Se você chegou até aqui, então:

- o Athena está acessível
- o editor de consultas está aberto
- o local de saída das consultas foi configurado

---

## Parte 3 - Criando a base Iceberg

### Resultado esperado desta parte

Ao final desta etapa, o banco `athena_iceberg_db` e a tabela `customer_iceberg` estarão criados.

8. Crie o banco de dados:

```sql
create database athena_iceberg_db;
```

![create-iceberg-db](img/create-iceberg-db.png)

9. Crie a tabela Iceberg abaixo. Antes de executar, substitua `<your-account-id>` pelo ID da sua conta atual.

![](img/getIdAccount.png)

```sql
CREATE TABLE athena_iceberg_db.customer_iceberg (
    c_customer_sk INT COMMENT 'unique id',
    c_customer_id STRING,
    c_first_name STRING,
    c_last_name STRING,
    c_email_address STRING)
LOCATION 's3://otfs-aula-<your-account-id>/datasets/athena_iceberg/customer_iceberg'
TBLPROPERTIES (
  'table_type'='iceberg',
  'format'='PARQUET',
  'write_compression'='zstd'
);
```

![Create-iceberg-table](img/create-iceberg-table.png)

![](img/create-iceberg-table-2.png)

<details>
<summary><b>Explicação do comando de criação da tabela Iceberg</b></summary>
<blockquote>

Os pontos mais importantes dessa instrução são:

- `LOCATION`: define o caminho no S3 onde os arquivos e metadados da tabela ficarão armazenados
- `'table_type'='iceberg'`: informa ao Athena que a tabela usará o formato aberto Apache Iceberg
- `'format'='PARQUET'`: define o formato físico dos dados, otimizado para analytics
- `'write_compression'='zstd'`: reduz armazenamento e leitura com boa eficiência de compressão

Essa combinação permite usar recursos como snapshots, histórico, evolução de esquema e operações de linha, que não fazem parte do comportamento tradicional de uma tabela externa simples.

Documentação oficial:
- [Criando tabelas Iceberg no Athena](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-creating-tables.html)
- [Especificação oficial do Apache Iceberg](https://iceberg.apache.org/spec/)

</blockquote>
</details>

10. Valide se a tabela foi criada:

```sql
SHOW TABLES IN athena_iceberg_db;
```

![Create-iceberg-table](img/show_tables_in_db.png)

11. Consulte o esquema da tabela:

```sql
DESCRIBE customer_iceberg;
```

![Create-iceberg-table](img/describe_athena_iceberg_table.png)

### O que validar aqui

- o banco `athena_iceberg_db` existe
- a tabela `customer_iceberg` existe
- a tabela ainda está vazia

---

## Parte 4 - Entendendo a estrutura da tabela Iceberg

A estrutura subjacente do Iceberg é organizada em metadados, snapshots, manifestos e arquivos de dados.

![Create-iceberg-table](img/iceberg_underlying_table_structure.png)

Em alto nível:

- cada operação confirmada gera um novo snapshot
- cada alteração relevante gera um novo arquivo de metadados
- a tabela aponta sempre para o metadado mais recente
- os manifestos apontam para os arquivos de dados

As tabelas Athena Iceberg expõem metadados de tabela, como `files`, `manifests`, `history` e `snapshots`.

12. Consulte os arquivos da tabela. Como a tabela ainda não tem dados, o retorno deverá estar vazio.

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$files"
```

![Create-iceberg-table](img/athena_table_files_no_data.png)

13. Consulte os manifestos da tabela:

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$manifests"
```

14. Consulte os snapshots da tabela:

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$snapshots"
```

<details>
<summary><b>Explicação das tabelas de metadados do Iceberg</b></summary>
<blockquote>

Os sufixos especiais do Iceberg ajudam a enxergar a estrutura interna da tabela sem precisar abrir arquivos no S3 manualmente.

- `$files`: mostra quais arquivos de dados estão ativos no snapshot atual
- `$manifests`: lista os manifestos que agrupam referências para esses arquivos
- `$snapshots`: apresenta cada versão confirmada da tabela
- `$history`: mostra quando cada snapshot passou a ser o estado corrente

Essas consultas são especialmente úteis para entender como o Iceberg implementa versionamento, governança e time travel.

Documentação oficial:
- [Consultar tabelas Iceberg no Athena](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-table-data.html)
- [Inspeção de metadados no Apache Iceberg](https://iceberg.apache.org/docs/latest/spark-queries/#inspecting-tables)

</blockquote>
</details>

> [!NOTE]
> Neste momento, essas consultas não devem retornar dados relevantes, porque a tabela ainda está vazia.

---

## Parte 5 - Inserindo dados

### Resultado esperado desta parte

Ao final desta etapa, a tabela `customer_iceberg` terá dados carregados a partir de `tpcds.prepared_customer`.

15. Insira os registros na tabela:

```sql
INSERT INTO athena_iceberg_db.customer_iceberg
SELECT * FROM tpcds.prepared_customer
```

A execução deve terminar com a mensagem **Consulta bem-sucedida**.

16. Consulte os primeiros registros:

```sql
select * from athena_iceberg_db.customer_iceberg limit 10;
```

![iceberg-test-query](img/query-iceberg-table.png)

17. Conte o total de registros:

```sql
select count(*) from athena_iceberg_db.customer_iceberg;
```

O resultado esperado é **2.000.000** registros.

### Checkpoint

Se você chegou até aqui, então:

- a tabela foi carregada com sucesso
- já existem arquivos de dados e metadados associados a ela

---

## Parte 6 - Explorando dados e metadados no S3

18. No local da tabela no [Amazon S3](https://us-east-1.console.aws.amazon.com/s3/home?region=us-east-1), abra:

`s3://otfs-aula-<your-account-id>/datasets/athena_iceberg/customer_iceberg/`

Você deverá ver duas pastas:

- `data`
- `metadata`

A pasta `data` contém os dados em Parquet, e a pasta `metadata` contém os arquivos de metadados.

Tipos de arquivo esperados em `metadata`:

- arquivos `.metadata.json`
- listas de manifesto `*-m*.avro`
- manifestos `snap-*.avro`

Pasta de metadados:

![iceberg-test-query](img/iceberg_table_metadata_s3_folder.png)

Pasta de dados:

![iceberg-test-query](img/iceberg_table_data_s3_folder.png)

19. Liste os arquivos da tabela:

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$files"
```

20. Liste os manifestos:

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$manifests"
```

21. Consulte o histórico:

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$history"
```

22. Consulte os snapshots:

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$snapshots"
```

### O que observar

- em `files`, caminhos de arquivos `.parquet`
- em `manifests`, caminhos de arquivos `.avro`
- em `history` e `snapshots`, valores como `snapshot_id`, `parent_id` e `manifest_list`

---

## Parte 7 - Atualizando registros

### Resultado esperado desta parte

Ao final desta etapa, o registro do cliente com `c_customer_sk = 15` terá sido corrigido.

23. Consulte o registro do cliente:

```sql
select * from athena_iceberg_db.customer_iceberg
WHERE c_customer_sk = 15
```

Observe que `c_last_name` e `c_email_address` estão `null`.

24. Atualize o registro:

```sql
UPDATE athena_iceberg_db.customer_iceberg
SET c_last_name = 'John', c_email_address = 'johnTonya@abx.com'
WHERE c_customer_sk = 15
```

A consulta deve terminar com **Consulta bem-sucedida**.

<details>
<summary><b>Explicação do comando UPDATE em tabela Iceberg</b></summary>
<blockquote>

Aqui o Athena altera apenas o registro filtrado pelo `WHERE`, mas o ponto mais importante é o comportamento interno do Iceberg.

Em vez de reescrever a tabela inteira, a engine trabalha com metadados, arquivos de deleção e novos arquivos de dados, preservando consistência e histórico da tabela.

Esse é um dos motivos pelos quais o Iceberg é tão útil em cenários de data lake com necessidade de correção de dados.

Documentação oficial:
- [UPDATE em tabelas Iceberg no Athena](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-update.html)
- [Boas práticas de escrita com Apache Iceberg na AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/apache-iceberg-on-aws/best-practices-write.html)

</blockquote>
</details>

25. Valide a alteração:

```sql
select * from athena_iceberg_db.customer_iceberg
WHERE c_customer_sk = 15
```

Agora o sobrenome e o e-mail devem aparecer preenchidos.

### Observação técnica

Athena usa [merge-on-read](https://docs.aws.amazon.com/pt_br/prescriptive-guidance/latest/apache-iceberg-on-aws/best-practices-write.html) para operações `UPDATE`.

Na prática, isso significa que:

- ele grava arquivos de exclusão por posição
- grava também as linhas atualizadas
- evita reescrever arquivos inteiros desnecessariamente

26. Verifique o impacto da operação na camada de dados:

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$files"
```

![iceberg-test-query](img/data_file_path_after_update.png)

> [!TIP]
> Você pode identificar novos arquivos observando o `LastModified` no S3.

---

## Parte 8 - Excluindo registros

### Resultado esperado desta parte

Ao final desta etapa, o registro do cliente com `c_customer_sk = 15` terá sido removido da visualização atual da tabela.

27. Exclua o registro:

```sql
delete from athena_iceberg_db.customer_iceberg
WHERE c_customer_sk = 15
```

A consulta deve terminar com **Consulta bem-sucedida**.

28. Valide a remoção:

```sql
SELECT * FROM athena_iceberg_db.customer_iceberg WHERE c_customer_sk = 15
```

O resultado esperado é **Nenhum resultado**.

### Observação técnica

Athena também usa `merge-on-read` para `DELETE`, criando arquivos de exclusão baseados em posição em vez de reescrever todos os arquivos de dados.

<details>
<summary><b>Explicação do comando DELETE em tabela Iceberg</b></summary>
<blockquote>

Quando você executa o `DELETE`, o snapshot atual passa a ignorar as linhas removidas. Em termos práticos, a exclusão é controlada pela camada de metadados do Iceberg, o que mantém o comportamento transacional da tabela.

Isso é importante porque remove registros sem perder o histórico das versões anteriores, que ainda podem ser acessadas por time travel.

Documentação oficial:
- [DELETE em tabelas Iceberg no Athena](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-delete.html)
- [Operações de linha no Apache Iceberg](https://iceberg.apache.org/spec/#row-level-deletes)

</blockquote>
</details>

---

## Parte 9 - Time travel

### Resultado esperado desta parte

Ao final desta etapa, você terá consultado versões anteriores da tabela usando snapshot e timestamp.

29. Consulte o histórico da tabela:

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$history"
order by made_current_at;
```

![iceberg-test-query](img/iceberg_table_history.png)

Você deverá ver 3 momentos principais:

- inserção inicial
- atualização
- exclusão

30. Substitua `5418594889737463157` pelo `snapshot_id` da linha correspondente ao segundo snapshot e consulte a tabela naquele ponto do tempo:

```sql
select * from athena_iceberg_db.customer_iceberg
FOR VERSION AS OF  5418594889737463157
WHERE c_customer_sk = 15
```

O resultado deve mostrar o registro do cliente Tonya.

31. Agora faça a mesma ideia usando timestamp. Substitua o timestamp abaixo pelo valor de `made_current_at` da linha correta no histórico:

```sql
select * from athena_iceberg_db.customer_iceberg
FOR TIMESTAMP AS OF TIMESTAMP '2024-04-16 17:21:49.771 UTC'
WHERE c_customer_sk = 15
```

Novamente, o resultado deve mostrar o registro do cliente Tonya.

<details>
<summary><b>Explicação do time travel com snapshot e timestamp</b></summary>
<blockquote>

Os operadores `FOR VERSION AS OF` e `FOR TIMESTAMP AS OF` permitem consultar estados anteriores da tabela sem restaurar arquivos manualmente.

Use:

- `FOR VERSION AS OF` quando você já conhece o `snapshot_id`
- `FOR TIMESTAMP AS OF` quando quer ver como a tabela estava em um instante específico

Esse recurso é muito útil para auditoria, depuração de pipelines e validação de mudanças em ambientes analíticos.

Documentação oficial:
- [Time travel em tabelas Iceberg no Athena](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-time-travel-and-version-travel-queries.html)
- [Time travel no Apache Iceberg](https://iceberg.apache.org/docs/latest/spark-queries/#time-travel)

</blockquote>
</details>

---

## Parte 10 - Evolução do esquema

### Resultado esperado desta parte

Ao final desta etapa, a tabela terá uma coluna renomeada e uma nova coluna adicionada, sem reescrita dos arquivos de dados.

As mudanças de esquema no Iceberg são alterações de metadados. Em geral, os arquivos de dados não precisam ser recriados.

32. Consulte os arquivos de dados da tabela:

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$files"
```

Anote o caminho e o nome do arquivo.

33. Renomeie a coluna `c_email_address` para `email`:

```sql
ALTER TABLE athena_iceberg_db.customer_iceberg
change column c_email_address email STRING
```

34. Consulte os arquivos novamente:

```sql
SELECT * FROM "athena_iceberg_db"."customer_iceberg$files"
```

Observe que não há novos arquivos de dados criados por causa da mudança de esquema.

35. Valide o novo esquema:

```sql
DESCRIBE customer_iceberg;
```

36. Adicione uma nova coluna chamada `c_birth_date`:

```sql
ALTER TABLE athena_iceberg_db.customer_iceberg ADD COLUMNS (c_birth_date int)
```

37. Valide novamente:

```sql
DESCRIBE customer_iceberg;
```

38. Consulte a tabela com a nova coluna:

```sql
SELECT *
FROM athena_iceberg_db.customer_iceberg
LIMIT 10
```

A nova coluna deverá aparecer com valores `null` para os registros já existentes.

<details>
<summary><b>Explicação da evolução de esquema no Iceberg</b></summary>
<blockquote>

Renomear colunas e adicionar novas colunas são operações de metadados no Iceberg. Por isso, em geral, os arquivos Parquet existentes não precisam ser recriados.

Esse comportamento reduz custo, evita reprocessamentos desnecessários e facilita a evolução do modelo analítico ao longo do tempo.

Documentação oficial:
- [Usando Apache Iceberg com o Athena](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html)
- [Evolução de esquema no Apache Iceberg](https://iceberg.apache.org/docs/latest/evolution/#schema-evolution)

</blockquote>
</details>

---

## Conclusão

Se você chegou até aqui, então já executou:

- criação de banco e tabela Iceberg
- inserção de dados
- leitura de metadados
- atualização de registros
- exclusão de registros
- time travel por snapshot e timestamp
- evolução de esquema

Este laboratório forma a base para os próximos exercícios com funcionalidades mais avançadas do Iceberg.
