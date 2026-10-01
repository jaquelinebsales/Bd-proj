# Limpeza dos dados de preços da ANP

Este documento registra o que foi removido, alterado e mantido na preparação das planilhas semestrais de preços da ANP para o gasprice.

- **Script:** `scripts/anp/limpar_anp.py`, somente com a biblioteca padrão do Python.
- **Entrada:** `precos_ANP/`. Os arquivos originais não foram alterados.
- **Saída:** `dados/anp_limpo/`.
- **Como executar de novo:** `python scripts/anp/limpar_anp.py`.

## 1. Resumo

| Item | Quantidade |
|---|---:|
| Semestres processados | 13, de 2020-1 a 2026-1 |
| Linhas lidas | 5.473.024 |
| Linhas removidas | 9.134 (0,17%) |
| Preços mantidos | 5.463.890 |
| Preços mantidos e marcados como anomalia | 388 |
| Postos únicos por CNPJ | 21.103 |
| Postos com coleta a partir de jul/2025 | 9.189 |

**Nenhum preço foi apagado por ter um valor estranho.** Esses preços continuam na base com `anomalia = true`. Só saíram linhas vazias e linhas repetidas.

## 2. O que foi removido

### 2.1 Arquivo inteiro ignorado

| Arquivo | Motivo |
|---|---|
| `ca-2026-01.zip` | É idêntico a `Preços semestrais - AUTOMOTIVOS_2026.01.csv`, com o mesmo conteúdo e o mesmo tamanho. Usar os dois duplicaria o semestre 2026-1. |

### 2.2 Linhas removidas

| Motivo | Linhas | Semestre | Explicação |
|---|---:|---|---|
| Linha vazia | 9.114 | 2025-1 | Linhas com todos os 16 campos vazios no arquivo da ANP. Não têm nenhuma informação. |
| Duplicata idêntica | 16 | 2024-1 e 2026-1 | Mesmo posto, produto, data e preço repetidos no arquivo. Foi mantida uma cópia. |
| Duplicata com preço divergente | 4 | 2024-1 | Mesmo posto, produto e data com dois preços diferentes. Foi mantida a primeira ocorrência, marcada como anomalia. A segunda está registrada em `removidos.csv`. |

Cada linha removida, exceto as vazias, está listada em `dados/anp_limpo/removidos.csv` com o arquivo de origem, o número da linha, o motivo e o valor mantido no lugar.

As duplicatas divergentes vieram de um único posto, o CNPJ 00.008.226/0001-39:

| Data | Produto | Preço mantido | Preço removido |
|---|---|---:|---:|
| 10/06/2024 | Gasolina comum | 5,480 | 5,650 |
| 10/06/2024 | Gasolina aditivada | 5,590 | 5,770 |
| 12/06/2024 | Gasolina comum | 5,480 | 5,650 |
| 12/06/2024 | Gasolina aditivada | 5,590 | 5,770 |

O script também removeria linhas com número de colunas errado, produto desconhecido, CNPJ inválido, data inválida, data fora do semestre do arquivo ou preço não numérico. **Nenhuma linha caiu nesses casos** nos arquivos atuais. As regras continuam no script para as próximas importações.

### 2.3 Colunas removidas

| Coluna original | Motivo |
|---|---|
| Regiao - Sigla | Pode ser derivada da UF. |
| Valor de Compra | Só existe em 2020, e mesmo assim em uma minoria das linhas. Não é usada pelo app nem pelo modelo. |
| Unidade de Medida | É determinada pelo produto: litro para todos e m³ para o GNV. Passou para a tabela de produtos. |

Os dados cadastrais do posto, como razão social, endereço, bairro, município, UF, CEP e bandeira, saíram da tabela de preços. Eles ficam uma única vez por posto em `postos.csv`, com a versão mais recente de cada campo.

## 3. O que foi alterado sem perda de informação

- **CNPJ:** apenas os 14 dígitos, sem pontuação e sem o espaço inicial dos arquivos antigos. Os dígitos verificadores foram validados.
- **Campos com ponto e vírgula:** alguns complementos vinham entre aspas com ponto e vírgula dentro, como `"KM: 20;"`. A leitura trata esse caso, e nenhuma linha foi perdida por isso.
- **Complemento:** separadores foram trocados por vírgula, e marcadores vazios como `: XXXXXXXXXXXX` foram removidos.
- **Textos:** maiúsculas e espaços duplicados colapsados.
- **CEP:** apenas os 8 dígitos. Valores inválidos ficaram vazios.
- **Datas:** formato ISO, `AAAA-MM-DD`.
- **Preço:** ponto como separador decimal e 3 casas.
- **Codificação:** tudo em UTF-8. Os arquivos antigos usavam Windows-1252.
- **Produtos:** os nomes da ANP foram mapeados para códigos.

| id | Código | Nome no app | Nome na ANP | Unidade |
|---:|---|---|---|---|
| 1 | GC | Gasolina comum | GASOLINA | L |
| 2 | GA | Gasolina aditivada | GASOLINA ADITIVADA | L |
| 3 | ET | Etanol | ETANOL | L |
| 4 | DS | Diesel S500 | DIESEL | L |
| 5 | S10 | Diesel S10 | DIESEL S10 | L |
| 6 | GNV | GNV | GNV | m³ |

## 4. Anomalias: mantidas e marcadas

Um preço recebe `anomalia = true` quando cai em pelo menos uma destas regras:

1. **Destoa da UF e do próprio posto.** O preço fica mais de 35% longe da mediana do mesmo produto na mesma UF e na mesma semana, com pelo menos 5 preços na comparação. Ao mesmo tempo, fica mais de 20% longe da mediana do próprio posto naquele semestre.
2. **Fora da faixa plausível.** O preço fica fora de R$ 2,00 a R$ 15,00, ou de R$ 1,50 a R$ 12,00 no caso de etanol e GNV. Nenhum caso nos dados atuais.
3. **Duplicado com preço divergente.** É a ocorrência mantida dos casos da seção 2.2.

A segunda condição da regra 1 existe porque há postos caros de forma consistente, como postos de rodovia, aeroporto ou áreas nobres de São Paulo. Numa primeira versão, a regra usava só a comparação com a UF e marcava mais de 7 mil preços, quase todos de postos que sempre cobram acima da média. Esses preços são reais e não são anomalia.

| Motivo | Preços |
|---|---:|
| Destoa da UF e do próprio posto | 384 |
| Duplicado com preço divergente | 4 |

- **Etanol concentra a maior parte**, com 260 casos, seguido de diesel S10 com 48.
- **São Paulo concentra a maior parte**, com 251 casos.
- **Quase todos estão acima do esperado**, 383 dos 384.

O detalhe de cada caso, com a mediana da UF e a do posto usadas na comparação, está em `dados/anp_limpo/anomalias.csv`.

### Como tratar anomalias nos cálculos

- **Preço exibido no app:** um preço anômalo nunca é o "preço atual" da ANP de um posto. Nesse caso, usa-se o preço anterior não anômalo.
- **Médias e medianas regionais:** as anomalias ficam fora do cálculo.
- **Modelo de previsão:** as anomalias ficam fora do treino. O modelo pode usar a marca como informação para aprender a detectar envios suspeitos dos usuários.
- **Gráfico de histórico:** o ponto aparece com destaque visual ou fica oculto, a definir com o time de design.

## 5. Arquivos gerados

| Arquivo | Conteúdo | Tamanho |
|---|---|---:|
| `produtos.csv` | 6 combustíveis | < 1 KB |
| `postos.csv` | 21.103 postos com dados cadastrais, primeira e última coleta | 3,2 MB |
| `precos_anp.csv` | `posto_id, produto_id, data_coleta, preco, anomalia` | 166 MB, ou 20 MB compactado |
| `anomalias.csv` | Detalhes das 388 anomalias | 34 KB |
| `removidos.csv` | As 20 linhas duplicadas removidas | 2 KB |
| `relatorio.json` | Contagens por semestre, bandeiras e postos por UF | 8 KB |

`posto_id` é um identificador numérico interno que liga os preços a `postos.csv`. O CNPJ continua como identificador único do posto. O id numérico existe só para economizar espaço na tabela de preços, que tem 5,4 milhões de linhas.

## 6. Espaço ocupado no Supabase

Os arquivos foram carregados num PostgreSQL 16 local, igual ao do Supabase, com o esquema proposto e as chaves primárias. Os tamanhos abaixo foram medidos, não estimados.

| Tabela | Linhas | Dados + índices |
|---|---:|---:|
| Postos, com colunas de latitude e longitude | 21.103 | 5 MB |
| Preços ANP, série completa de 2020 a 2026 | 5.463.890 | 457 MB |
| Preços ANP, últimos 2 anos, de jul/2024 a jun/2026 | 1.648.411 | 138 MB |
| Preços anteriores a jul/2024 agregados por mês | 1.487.131 | 125 MB |

**Limites dos planos do Supabase**, consultados em 29/09/2026:
- **Free:** banco de 500 MB e 1 GB de arquivos. O projeto é pausado após 1 semana sem uso.
- **Pro:** US$ 25 por mês, com 8 GB de banco e 100 GB de arquivos.

| Opção | Banco usado pela ANP | Cabe no Free? |
|---|---:|---|
| A. Série completa no banco | cerca de 462 MB | Não. Sobram menos de 40 MB para usuários, envios e avaliações. |
| B. Últimos 2 anos no banco e série completa em arquivo no Storage | cerca de 143 MB no banco e 20 MB no Storage | Sim, com folga. |
| C. Últimos 2 anos diários e o período anterior agregado por mês | cerca de 268 MB | Sim, mas sobra pouco espaço. |

**Recomendação: opção B.**
- O app só precisa do histórico recente para os gráficos.
- O modelo de previsão treina fora do Supabase, lendo o arquivo compactado no Storage.
- Cada semestre novo acrescenta cerca de 35 MB. Uma rotina semestral move para o Storage o que passar de 2 anos.
- No plano Pro, a opção A cabe sem problema e pode ser adotada depois.
