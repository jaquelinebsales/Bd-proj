# Mapa e Busca: o que se repete e o que sugiro

Análise do código em 14/10/2026 (`app/lib/telas/mapa/tela_mapa.dart` e `app/lib/telas/busca/`). Nada foi alterado: este texto serve para decidir o caminho.

## Resumo

As duas abas respondem à mesma pergunta: **quais postos perto de mim, de qual combustível, por quanto**. Elas usam os mesmos dados, o mesmo seletor de combustível, o mesmo raio e o mesmo cartão de posto. A diferença real é só a forma de mostrar: pinos num mapa ou cartões numa lista. Hoje cada aba tem a própria carga de dados, os próprios filtros e a própria ordenação, e isso já gera resultados diferentes para a mesma escolha do usuário.

Sugestão: juntar as duas numa aba **Postos**, com um botão **Mapa | Lista** e um estado único de busca e filtros. É o padrão do Google Maps, do Airbnb e do GasBuddy.

## Onde as duas telas se repetem

| Peça | Mapa | Busca |
|---|---|---|
| Combustível | `SeletorProduto` (vários) | `SeletorProduto` (vários) **e** um seletor de um só na folha de filtros |
| Distância | `SeletorRaio` (2, 5, 10, 20 km) | Mesma preferência, escolhida na folha de filtros |
| Carga dos postos | `postosNaArea` (retângulo visível) ou `postosProximos` (com raio) | `postosProximos` (raio ou 20 km) ou `buscar` (texto) |
| Exibição | Pino + folha inferior; no tablet, uma **lista lateral com `CartaoPosto`** | Grade de `CartaoPosto` |
| Ordenação | `_ordenadosPorPreco` própria (lista do tablet) | `aplicarFiltros` em `servicos/filtros.dart` |
| Busca por texto | A barra "Buscar posto ou endereço" **só abre a aba Buscar** | Campo de texto de verdade |

No tablet, o mapa já mostra uma lista de cartões ao lado. Na prática, a tela "mapa + lista" já existe, só que duplicada.

## Inconsistências que o usuário já sente

1. **A folha de filtros desfaz a multisseleção.** Com três combustíveis marcados no botão, a folha de filtros mostra só um, como se fosse o único. Se a pessoa escolher outro combustível ali, `_usarFiltros` grava `Preferencias.produto = {novo.produtoId}` e os outros dois somem.
2. **O mesmo posto mostra preços diferentes nas duas abas.** O pino usa `melhorPreco(produtos)` (o primeiro combustível marcado que tem preço). O cartão da lista usa só o combustível principal e mostra "Sem preço" quando ele falta.
3. **"Qualquer distância" significa coisas diferentes.** No mapa é a área visível da tela. Na busca vira 20 km fixos ("N postos em até 20 km").
4. **Os filtros da busca não valem no mapa.** Faixa de preço, avaliação mínima, período, só favoritos e estimativas só existem na lista. Quem filtra "4 estrelas ou mais" e volta ao mapa vê todos os postos.
5. **O resultado de uma busca por texto não aparece no mapa.** Quem busca "Paulista" não consegue ver onde ficam aqueles postos.
6. **A barra de busca do mapa é um atalho para outra aba.** O usuário toca, a tela muda e o mapa some. Isso é confuso quando se espera buscar no próprio mapa.

## Proposta

**Uma aba "Postos" com um estado compartilhado.**

- Um objeto `ConsultaPostos` (um `ChangeNotifier`) guarda o texto buscado, os combustíveis, o raio, os filtros e a ordenação. Mapa e lista leem e alteram só ele.
- Uma única carga de dados: com texto, `buscar`; sem texto, a área visível (no mapa) ou o raio (na lista). Os dois modos aplicam o mesmo `aplicarFiltros`.
- Uma barra de busca real no topo, igual nos dois modos. Os filtros ficam ao lado, em pílulas: combustível, distância e "Filtros" com selo.
- O botão **Mapa | Lista** troca só a forma de mostrar. No mapa, buscar por texto enquadra os resultados. Na lista, a ordenação aparece. No tablet, mapa e lista ficam lado a lado, como já acontece.
- O preço exibido sai de uma função só (pino, folha e cartão), então o mesmo posto mostra o mesmo valor em qualquer lugar.
- A barra inferior fica com 3 abas: **Postos**, **Favoritos** e **Perfil**.

## Caminho em etapas

1. **Corrigir sem mudar a navegação** (pequeno, resolve os itens 1 a 3). A folha de filtros passa a usar a mesma multisseleção do botão. Uma função única decide o preço exibido. "Qualquer distância" na lista passa a ser explícita ("Até 20 km").
2. **Estado compartilhado** (médio, resolve o item 4). Criar o `ConsultaPostos` e fazer o mapa respeitar todos os filtros. As duas abas continuam existindo.
3. **Juntar as abas** (maior, resolve os itens 5 e 6). Criar a aba Postos com Mapa | Lista e remover a aba Buscar. Testar de novo com a suíte do Android (`testes_android/executar.py`), porque a navegação muda.

## Pontos de atenção

- Com raio, a lista depende da localização. Sem localização e sem texto, a lista precisa do mesmo estado vazio de hoje ("Busque uma cidade ou endereço").
- O mapa carrega por área e a lista por distância. Na troca de modo, convém reaproveitar o que já veio, para não fazer uma consulta nova a cada toque.
- A ordenação faz sentido só na lista. No mapa, a ordem define qual pino aparece por cima quando eles se sobrepõem (`symbol-sort-key`). Vale usar o mesmo critério: menor preço por cima.

## Achado fora do tema: dados do cadastro

O cadastro novo envia sobrenome, gênero e data de nascimento. Esses campos ficam só nos metadados da conta (`auth.users.raw_user_meta_data`): o gatilho `criar_perfil` (`supabase/migrations/20260929000003_regras.sql`, linha 50) grava apenas `nome` na tabela de perfis. É o mesmo gatilho que usa o começo do e-mail quando o nome vem vazio, a origem do bug do nome no perfil. Se esses dados forem usados no app, falta uma migração com as colunas em `perfis` e a cópia no gatilho.
