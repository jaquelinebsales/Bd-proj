# Experimento: quanto histórico da ANP o modelo de previsão precisa?

**Pergunta.** No plano gratuito do Supabase, o banco guarda só os últimos 2 anos de preços da ANP. Isso piora a previsão do preço do combustível?

**Resposta curta.** Não. Treinar com 2 anos deu o mesmo erro que treinar com a série completa desde 2020 na previsão de 1 semana. Na previsão de 4 semanas, o erro foi menor com 2 anos. Os dados de 2020 a 2022 atrapalham porque vêm de um período atípico.

O experimento também mostrou um problema que não tem relação com a janela de dados. O modelo atual acerta melhor que a regra ingênua quando o preço muda, mas erra mais quando o preço fica parado. Por isso, **ainda não deve ir para produção**. A seção 7 lista as melhorias.

- **Script:** `scripts/ml/experimento_janela_treino.py`
- **Resultados completos:** `dados/ml/experimento_janela_treino.json`
- **Data de execução:** 29/09/2026

## 1. O que o modelo prevê

O modelo prevê o **preço mediano da semana** de um combustível em um município, 1 semana e 4 semanas à frente.

O nível escolhido foi o município, e não o posto, por três motivos:
- A ANP não visita o mesmo posto toda semana, então a série de um posto tem muitas lacunas.
- O município tem série quase contínua. Há 2.580 séries, uma para cada combinação de município e combustível, com mediana de 256 semanas observadas em 332 possíveis.
- O preço de cada posto pode ser derivado depois, a partir da diferença habitual entre o posto e a mediana do município.

## 2. Dados

| Item | Valor |
|---|---|
| Fonte | `dados/anp_limpo/precos_anp.csv`, gerado pela limpeza documentada em `limpeza_dados_anp.md` |
| Período | 01/01/2020 a 30/06/2026 |
| Preços marcados como anomalia | Excluídos do treino e do teste |
| Agregação | Mediana semanal por município e combustível, com a semana começando na segunda-feira |
| Pontos semanais | 606.418 |
| Municípios | 471 |
| Combustíveis | 6 |

## 3. Variáveis de entrada

Todas são calculadas com dados até a semana da previsão, sem nenhuma informação do futuro. Os preços entram em logaritmo, de modo que as variações são percentuais.

| Grupo | Variáveis | Para que serve |
|---|---|---|
| Histórico do próprio município | Variação do preço em relação a 1, 2, 4, 8, 13, 26 e 52 semanas atrás | Tendência e sazonalidade locais |
| Mercado nacional | Variação da mediana nacional do combustível em 1, 4 e 13 semanas | Reajustes da Petrobras e mudanças de imposto aparecem primeiro aqui |
| Mercado estadual | Variação da mediana da UF em 1, 4 e 13 semanas | Efeito do ICMS e da logística do estado |
| Posição relativa | Distância do preço do município para a mediana da UF e para a mediana nacional | Municípios caros tendem a voltar para perto da média |
| Contexto | Semana do ano, combustível, UF, número de postos pesquisados e semanas com dado nas últimas 13 | Sazonalidade, diferenças estruturais e confiabilidade da série |

**Alvo:** a variação percentual do preço entre a semana atual e a semana prevista. O preço previsto é o preço atual multiplicado por essa variação.

## 4. Modelo

- **Algoritmo:** árvores com reforço de gradiente, com a implementação `HistGradientBoostingRegressor` do scikit-learn 1.9.
  - O LightGBM, sugerido antes, é da mesma família.
  - Ele não foi usado porque depende de uma biblioteca do Windows que não está instalada nesta máquina. O resultado esperado é equivalente.
- **Perda:** erro absoluto, a mesma métrica usada na avaliação.
- **Hiperparâmetros:**
  - taxa de aprendizado 0,05;
  - até 400 árvores, com parada antecipada usando 10% do treino como validação;
  - 31 folhas por árvore e 50 amostras mínimas por folha;
  - regularização L2 igual a 1;
  - semente 42.
- Os hiperparâmetros **não foram otimizados**. O experimento compara janelas de dados, e a mesma configuração foi usada em todos os cenários.

## 5. Como o experimento foi feito

### 5.1 Cenários comparados

| Cenário | Dados usados | O que representa |
|---|---|---|
| Ingênuo | Nenhum treino. Repete o preço da semana atual. | Referência mínima. Um modelo só vale a pena se errar menos que ele. |
| Completo | Todos os dados desde 2020 | Treinar com o arquivo completo guardado no Storage |
| 4 anos | Só os 4 anos anteriores ao início do teste | Meio-termo |
| 2 anos | Só os 2 anos anteriores ao início do teste | O que cabe no banco do Supabase gratuito |

Em cada cenário, o modelo só enxerga os dados da sua janela, **inclusive para calcular as variáveis**. No cenário de 2 anos, por exemplo, a variação de 52 semanas só existe a partir do segundo ano e fica vazia antes disso. Essa é exatamente a situação real de quem só tem 2 anos no banco.

### 5.2 Validação fora da amostra

Foram feitos dois testes independentes. Nos dois, o modelo é treinado só com semanas anteriores ao período de teste, e o erro é medido em semanas que ele nunca viu.

| Teste | Treino com alvos até | Teste com alvos entre | Janela de 2 anos começa em |
|---|---|---|---|
| 2025-2 | 30/06/2025 | jul e dez/2025 | 03/07/2023 |
| 2026-1 | 31/12/2025 | jan e jun/2026 | 01/01/2024 |

Todos os cenários são avaliados **nos mesmos casos de teste**, então a comparação é direta.

### 5.3 Métricas

- **MAE (R$):** erro absoluto médio em reais por litro, ou por m³ no caso do GNV. É a métrica principal.
- **MAPE (%):** o mesmo erro em percentual do preço.
- **MAE quando o preço mudou:** o MAE só nos casos em que o preço real variou 1% ou mais. Esses são os casos em que uma previsão é útil para o usuário.

## 6. Resultados

### 6.1 Previsão de 1 semana

| Teste | Cenário | Linhas de treino | MAE (R$) | MAPE | MAE quando o preço mudou |
|---|---|---:|---:|---:|---:|
| 2025-2 | Ingênuo | 0 | 0,0446 | 0,79% | 0,1591 |
| 2025-2 | Completo | 489.292 | 0,0446 | 0,79% | **0,1534** |
| 2025-2 | 4 anos | 397.505 | **0,0445** | 0,79% | 0,1541 |
| 2025-2 | 2 anos | 211.649 | 0,0448 | 0,79% | 0,1565 |
| 2026-1 | Ingênuo | 0 | 0,0857 | 1,34% | 0,2130 |
| 2026-1 | Completo | 529.452 | **0,0851** | 1,33% | **0,2065** |
| 2026-1 | 4 anos | 393.165 | 0,0853 | 1,33% | 0,2076 |
| 2026-1 | 2 anos | 192.048 | 0,0853 | 1,34% | 0,2111 |

### 6.2 Previsão de 4 semanas

| Teste | Cenário | Linhas de treino | MAE (R$) | MAPE | MAE quando o preço mudou |
|---|---|---:|---:|---:|---:|
| 2025-2 | Ingênuo | 0 | **0,0697** | 1,25% | 0,1671 |
| 2025-2 | Completo | 467.299 | 0,0865 | 1,53% | 0,1546 |
| 2025-2 | 4 anos | 381.922 | 0,0784 | 1,40% | 0,1502 |
| 2025-2 | 2 anos | 203.032 | 0,0783 | 1,40% | **0,1452** |
| 2026-1 | Ingênuo | 0 | **0,2257** | 3,47% | 0,3452 |
| 2026-1 | Completo | 505.745 | 0,2499 | 3,86% | 0,3264 |
| 2026-1 | 4 anos | 376.462 | 0,2318 | 3,57% | **0,3116** |
| 2026-1 | 2 anos | 182.001 | 0,2314 | 3,56% | 0,3292 |

### 6.3 Diferença entre as janelas

- **Em 1 semana, as janelas empatam.** A maior diferença entre elas é de R$ 0,0003 por litro, o que é imperceptível para o usuário.
- **Em 4 semanas, a janela completa é a pior.** Ela erra entre R$ 0,008 e R$ 0,018 a mais que as janelas de 2 e 4 anos.
  - O período de 2020 a 2022 teve pandemia, disparada de preços em 2021 e 2022 e corte do ICMS em julho de 2022.
  - O modelo aprende que variações grandes são comuns, e isso não vale para o período atual.
- **2 anos e 4 anos ficam praticamente iguais.** Não há ganho em guardar mais que 2 anos para a previsão.

**Conclusão para o projeto:** guardar só 2 anos no banco não prejudica a previsão. O arquivo completo no Storage continua útil para gráficos de longo prazo e para análises futuras, mas não é necessário para treinar o modelo.

### 6.4 O modelo em relação à regra ingênua

Esta é a parte que exige atenção:
- **Quando o preço muda**, o modelo erra de 1% a 13% menos que a regra ingênua. Ele percebe parte dos reajustes.
- **No geral**, empata com a regra ingênua em 1 semana e erra mais em 4 semanas.
- **O motivo é que o preço do combustível fica parado na maior parte das semanas.** O modelo prevê pequenas variações que não acontecem, e esses pequenos erros somados superam o ganho nas semanas com reajuste.

## 7. Limitações e próximos passos

**Limitações:**
- São só dois semestres de teste. Um terceiro teste, em 2024-2, daria mais segurança.
- Os hiperparâmetros não foram ajustados.
- O modelo só conhece preços passados. Reajustes da Petrobras e mudanças de imposto, que causam as maiores variações, chegam sem aviso para ele.
- Os erros por UF valem apenas para os municípios que a ANP pesquisa. Nos municípios sem pesquisa, o erro é maior. Isso está detalhado no mapa de cobertura.

**Melhorias antes de colocar em produção, em ordem de impacto esperado:**
1. **Separar em duas perguntas.** Primeiro, "o preço vai mudar?", com um classificador. Depois, "quanto?". Quando a probabilidade de mudança for baixa, o app repete o preço atual. Isso ataca diretamente o problema da seção 6.4.
2. **Incluir variáveis externas.** Os anúncios de reajuste da Petrobras nas refinarias, as alíquotas de ICMS e PIS/Cofins, o petróleo Brent, o dólar e a safra de cana para o etanol explicam a maior parte das variações grandes.
3. **Aproximar a previsão da regra ingênua** quando o modelo estiver pouco confiante.
4. **Adotar a regra de publicação:** o modelo só entra no app se superar a regra ingênua no MAE geral em dois testes seguidos.

## 8. Como reproduzir

```
python -m venv .venv
.venv\Scripts\pip install pandas numpy scikit-learn
.venv\Scripts\python scripts\anp\limpar_anp.py
.venv\Scripts\python scripts\ml\experimento_janela_treino.py
```

O experimento leva alguns minutos num computador comum. Com a semente fixa, os resultados se repetem.
