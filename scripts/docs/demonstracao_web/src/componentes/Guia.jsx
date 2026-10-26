// Guia: texto solto sobre a página (como os títulos), que muda a cada toque no app. Começa com um resumo; um filtro
// tocado explica o filtro; um botão da barra inferior mostra o que tem na tela. Textos das regras de negócio
// (scripts/docs/gerar_regras.py) e dos rótulos reais do app (o app avisa o rótulo de cada toque).

const RESUMO = {
  celular: { titulo: 'GasPrice no celular', texto: 'O app de verdade, rodando aqui. O mapa mostra os postos ao redor e o valor do combustível em cada um. Toque nos filtros e nos botões: cada parte é explicada aqui.' },
  tablet: { titulo: 'GasPrice no tablet', texto: 'O mesmo app, reorganizado para a tela grande: a navegação vai para a lateral e as listas ganham colunas. Toque em qualquer botão para ver o que ele faz.' },
};

// Uma entrada por tela, com o mesmo título que a tela mostra (app/lib/servicos/monitor_demo.dart). Os itens
// descrevem o que está à vista nela.
export const TELAS = {
  Mapa: {
    texto: 'Os postos ao seu redor e quanto custa o combustível escolhido em cada um.',
    itens: [
      'A cor do pino mostra há quanto tempo o valor foi atualizado: verde até 24 h, âmbar de 2 a 7 dias e contorno vermelho depois disso.',
      'O pino tracejado com ≈ é uma estimativa, feita a partir dos postos pesquisados mais próximos.',
      'O combustível escolhido aqui vale também na busca e nos favoritos.',
    ],
  },
  Busca: {
    texto: 'Encontre postos pelo nome, endereço, bairro, cidade ou UF.',
    itens: ['A lista pode seguir a distância, o valor, a nota ou a data da última atualização.', 'O ícone ao lado da ordem abre os filtros: faixa de valor, distância, nota e período.'],
  },
  Favoritos: {
    texto: 'Os postos que você acompanha.',
    itens: ['Cada cartão traz quanto custa o combustível escolhido.', 'O sino liga ou desliga os avisos daquele posto.', 'Você é avisado quando um valor confirmado ou oficial muda R$ 0,05 ou mais.'],
  },
  Perfil: {
    texto: 'Sua conta, seus pontos e seu nível de confiança.',
    itens: ['Os números resumem pontos, posição no ranking, nível, envios, confirmações e avaliações.', 'O cartão de envios abre o que você mandou nas últimas duas semanas; o de avaliações, todas as suas notas.', 'Mais opções: dados da conta, senha, extrato, ranking e notificações.'],
  },
  'Preços enviados': {
    texto: 'Tudo o que você mandou nas últimas duas semanas, do mais novo ao mais antigo.',
    itens: ['Em cada envio: o combustível, quando foi mandado e a situação — confirmado, aguardando ou contrariado.', 'A confirmação vem quando outra pessoa informa o mesmo valor, com diferença de até R$ 0,02, em até 24 h.', 'Toque num envio para abrir o posto.'],
  },
  'Minhas avaliações': {
    texto: 'Todas as notas que você deu, da mais nova à mais antiga.',
    itens: ['Cada uma traz a nota, o comentário e quantas pessoas a acharam útil.', 'Toque numa delas para abrir o posto e, se quiser, editar.'],
  },
  Posto: {
    texto: 'A ficha do posto: quanto custa cada combustível, com origem e idade.',
    itens: ['A bolinha mostra há quanto tempo o valor foi atualizado; o ícone, de onde ele veio: comunidade, pesquisa da ANP ou estimativa.', 'Toque num combustível para ver quem informou e o dado oficial da ANP.', 'A ficha traz ainda o histórico, as avaliações e os dados cadastrais.'],
  },
  'Histórico de preços': {
    texto: 'Como o valor variou neste posto ao longo do tempo.',
    itens: ['Escolha o combustível e o período, de 30 dias a 2 anos.', 'A linha tracejada é a pesquisa semanal da ANP; a contínua, os envios da comunidade.', 'A lista de registros traz cada valor com data e origem.'],
  },
  Avaliações: {
    texto: 'Notas e comentários sobre o posto.',
    itens: ['Uma avaliação por pessoa e posto, de 0 a 5 estrelas.', 'A ordem por mais úteis usa os votos de outras pessoas.', 'O nome aparece sempre abreviado, como Carla M.'],
  },
  'Avaliar posto': {
    texto: 'A sua nota para o posto.',
    itens: ['De 0 a 5 estrelas, editável ou apagável.', 'Comentário opcional, de 3 a 500 caracteres.'],
  },
  'Atualizar preços': {
    texto: 'Foto do painel, conferência e envio.',
    itens: ['O painel é lido no próprio aparelho, sem internet; a foto é apagada em seguida e nunca sai do celular.', 'O envio é aceito a até 300 m do posto, ou 1 km quando a localização é aproximada.', 'O valor é confirmado quando duas pessoas concordam, com até R$ 0,02 de diferença, em 24 h.'],
  },
  'Estou neste posto': {
    texto: 'Confirma onde o posto fica no mapa.',
    itens: ['É preciso estar no posto, com GPS de até 100 m de precisão.', 'A posição vale quando duas pessoas informam pontos a até 150 m uma da outra.', 'Cada confirmação rende 5 pontos.'],
  },
  'Meus pontos': {
    texto: 'O total de pontos e o extrato.',
    itens: ['Cada linha do extrato mostra o motivo, quando aconteceu e quantos pontos valeu.', 'O ícone de informação no canto mostra como os pontos são ganhos e perdidos.'],
  },
  'Ranking da comunidade': { texto: 'Quem mais contribui com a comunidade.', itens: ['Ordenado pelos pontos de cada pessoa.', 'O nome aparece sempre abreviado.'] },
  Notificações: {
    texto: 'Os avisos sobre os seus favoritos.',
    itens: ['A seta mostra se o valor subiu ou caiu.', 'O aviso chega quando um valor confirmado ou oficial muda R$ 0,05 ou mais.', 'O ícone no canto ajusta as preferências.'],
  },
  'Sobre os dados e privacidade': {
    texto: 'De onde vêm os dados e o que cada cor significa.',
    itens: ['Três fontes: fotos da comunidade, pesquisa semanal da ANP e estimativa pelos postos vizinhos.', 'Verde até 24 h, âmbar de 2 a 7 dias, contorno vermelho acima disso.', 'Também explica o cadastro dos postos, a privacidade e os termos de uso.'],
  },
  'Alterar dados': {
    texto: 'Nome, foto de perfil e avisos.',
    itens: ['A foto de perfil é opcional.', 'O e-mail fica só para leitura.', 'O interruptor liga ou desliga os avisos sobre os favoritos.'],
  },
  'Alterar senha': {
    texto: 'Troca a senha da conta.',
    itens: ['Pede a senha atual e a nova duas vezes.', 'A nova senha tem 8 caracteres ou mais, com maiúscula, minúscula, número e símbolo.'],
  },
};

// Rótulo tocado → o que o controle faz (título null: a troca de tela já explica). O 4º item, quando existe, limita
// às telas em que o controle aparece (o nome de um combustível no posto é uma linha de preço, não o filtro).
// Só controles com algo a explicar entram aqui: textos, nomes, preços e o "voltar" não mudam o guia.
const TELAS_COM_FILTRO = ['Mapa', 'Busca', 'Favoritos'];
const CONTROLES = [
  [/^(\d+ combustíveis|Gasolina comum|Gasolina aditivada|Etanol|Diesel S10|Diesel S500|GNV)$/, 'Filtro de combustível',
    'Cada pino mostra o menor valor entre os escolhidos, e a escolha vale para o mapa, a busca e os favoritos.', TELAS_COM_FILTRO],
  [/^(Qualquer|\d+ km)$/, 'Raio de distância', 'Mostra só os postos a até 2, 5, 10 ou 20 km da sua posição; o círculo marca a área no mapa.', ['Mapa']],
  [/^Posto selecionado$/, 'Posto no mapa',
    'O resumo do posto tocado: quanto custa o combustível escolhido, com idade e origem. Ver detalhes abre a ficha completa; Atualizar começa pela foto do painel.'],
  [/^Como funciona$/, 'Como funciona',
    'Envio confirmado por outra pessoa em até 24 h: +10; contrariado: −5. Em cidades fora da pesquisa da ANP, os pontos valem o dobro. No máximo 200 pontos por dia.'],
  [/^Contribuições$/, 'Contribuições',
    'Quem informou este combustível no posto e há quanto tempo, ao lado do dado oficial da pesquisa semanal da ANP.'],
  [/^Buscar posto ou endereço$/, 'Busca', 'Procura postos pelo nome ou pelo endereço, sem precisar mover o mapa.'],
  [/^Minha localização$/, 'Minha localização', 'Centraliza o mapa onde você está, pelo GPS do aparelho.'],
  [/^Ver detalhes$/, 'Detalhes do posto', 'Abre a ficha do posto: cada combustível com origem e idade, avaliações e histórico.'],
  [/^Atualizar( preços)?$/, 'Atualizar preços', 'Começa pela foto do painel do posto. O texto é lido no próprio aparelho e você confere os valores antes de enviar.'],
  [/^(Ordenar|Mais próximos|Menor preço|Maior preço|Melhor avaliação|Pior avaliação|Atualização mais recente|Atualização menos recente)$/, 'Ordenação',
    'Ordena a lista por distância, valor, nota ou data da atualização.'],
  [/^(Filtros|Aplicar)$/, 'Filtros', 'Faixa de valor, distância máxima, nota mínima e período da última atualização.'],
  [/^(Limpar|Limpar filtros)$/, 'Limpar', 'Desfaz a busca ou os filtros e volta à lista completa.'],
  [/^Só postos favoritos$/, 'Só favoritos', 'Restringe a lista aos postos que você acompanha.'],
  [/^Incluir preços estimados$/, 'Preços estimados', 'Inclui postos sem coleta recente, com o valor calculado pela mediana dos 5 vizinhos pesquisados mais próximos.'],
  [/^Usar minha localização$/, 'Distância a partir de você', 'Usa o GPS para calcular a distância de cada posto e ordenar pelos mais próximos.'],
  [/^Como chegar$/, 'Como chegar', 'Abre a rota até o posto no aplicativo de mapas do aparelho.'],
  [/^Estou neste posto$/, 'Estou neste posto', 'Corrige a posição do posto no mapa. Exige GPS com até 100 m de precisão; vale quando duas pessoas concordam a até 150 m.'],
  [/^Ver completo$/, 'Histórico completo', 'Mostra como o valor variou ao longo do tempo, com a série da ANP e os envios da comunidade.'],
  [/^(Ver todas|Mais recentes|Mais úteis)$/, 'Avaliações', 'Notas e comentários, em ordem de data ou pelos votos de utilidade.'],
  [/estrela/, 'Nota', 'De 0 a 5 estrelas, uma avaliação por pessoa e posto, que pode ser editada.'],
  [/^Publicar avaliação$/, 'Publicar avaliação', 'Grava a nota e o comentário. Só a própria pessoa pode alterar a sua avaliação.'],
  [/^Informar a posição deste posto$/, 'Posição enviada',
    'A localização do aparelho vai para o servidor, que só aceita GPS com até 100 m de precisão. Quando outra pessoa informar um ponto a até 150 m, o posto muda de lugar no mapa e você ganha 5 pontos.'],
  [/^(Desligar|Ligar) avisos de preço$/, 'Avisos do posto',
    'Liga ou desliga os avisos deste favorito. Ligado, você é avisado quando um valor confirmado ou oficial muda R$ 0,05 ou mais.'],
  [/^Leitura concluída$/, 'Confira os valores',
    'O app leu o painel sozinho e preencheu cada combustível. Embaixo de cada campo aparece o que foi lido: corrija se precisar, desmarque o que não quiser mandar e toque em Enviar preços.'],
  [/^Envio concluído$/, 'Envio feito',
    'Os valores entram aguardando confirmação. Quando outra pessoa informar o mesmo valor em até 24 h, eles viram confirmados e você ganha 10 pontos.'],
  [/^(Abrir câmera|Tirar outra foto)$/, 'Foto do painel', 'Na demonstração, a leitura usa um painel de exemplo. No aparelho, o texto é lido sem internet e a foto é apagada em seguida.'],
  [/^Enviar preços$/, 'Enviar preços', 'Vão os valores conferidos, o texto lido e a posição — nunca a foto. O servidor confere a distância e o consenso.'],
  [/^(Sair da conta|Excluir minha conta|Excluir conta|Entrar|Criar conta)$/, 'Conta', 'Na demonstração as ações de conta ficam desligadas; a usuária de exemplo já está conectada.'],
  [/^(Alterar dados|Alterar senha|Extrato de pontos|Ranking|Ranking da comunidade|Notificações|Sobre os dados e privacidade|Preferências de aviso)$/, null, null],
];
const NAVEGACAO = /^(Mapa|Buscar|Favoritos|Perfil)$/;

// Filtros da busca (folha "Filtros"): todos explicados como "Filtro", com o valor escolhido logo abaixo
const FILTRO = { titulo: 'Filtro', texto: 'Usuário seleciona os filtros que deseja aplicar na pesquisa.' };
const VALORES_FILTRO = [
  // o app formata reais com espaço não separável (R$ 1,50): \s cobre os dois
  [/^R\$\s.+\sa\sR\$\s.+$/, 'Faixa de preço'],
  [/^Até\s\d+\skm$/, 'Distância'],
  [/^\d+(,\d+)?\+$/, 'Avaliação mínima'],
  [/^(Qualquer data|Últimas? .+|Últimos .+)$/, 'Última atualização'],
];
const PARTES_FILTRO = /^(Filtros|Faixa de preço|Distância|Avaliação mínima|Última atualização do preço|Qualquer)$/;

function filtroDaBusca(rotulo, tela) {
  const valor = VALORES_FILTRO.find(([re]) => re.test(rotulo));
  if (!valor && !PARTES_FILTRO.test(rotulo)) return null;
  return { tipo: 'controle', ...FILTRO, valor: valor ? `${valor[1]}: ${rotulo}` : '', rotulo, tela };
}

/** Converte o rótulo tocado num foco do guia; null quando a troca de tela já explica (barra inferior, postos da lista) */
export function focoDoToque(rotulo, tela) {
  if (NAVEGACAO.test(rotulo)) return null;
  if (tela === 'Busca') {
    const filtro = filtroDaBusca(rotulo, tela);
    if (filtro) return filtro;
  }
  // os controles conhecidos vêm antes: "Posto selecionado" é um aviso do app, não o nome de um posto
  const achado = CONTROLES.find(([re, , , telas]) => re.test(rotulo) && (!telas || telas.includes(tela)));
  if (!achado || !achado[1]) return null;
  return { tipo: 'controle', titulo: achado[1], texto: achado[2], rotulo, tela };
}

export default function Guia({ aparelho, nomeAparelho, foco, visivel, lateral, aberto, aoFechar }) {
  const tela = foco?.tipo === 'tela' ? TELAS[foco.nome] : null;
  const titulo = foco?.tipo === 'tela' ? foco.nome : foco?.tipo === 'controle' ? foco.titulo : RESUMO[aparelho].titulo;
  const texto = foco?.tipo === 'tela' ? (tela?.texto ?? '') : foco?.tipo === 'controle' ? foco.texto : RESUMO[aparelho].texto;
  const itens = tela?.itens ?? [];
  // o filtro com valor só troca o valor (arrastar a faixa de preço não deve piscar o guia a cada passo)
  const chave = foco?.valor !== undefined
    ? `${aparelho}-filtro`
    : `${aparelho}-${foco?.tipo}-${titulo}-${foco?.rotulo ?? ''}-${foco?.n ?? ''}`;
  const mostrar = lateral ? visivel : (aberto ? visivel : 0);

  return (
    <aside aria-label="Guia da tela" aria-live="polite"
           style={{ opacity: Math.max(mostrar, 0.002), pointerEvents: mostrar > 0.95 ? 'auto' : 'none' }}
           className={lateral
             ? 'fixed right-14 top-1/2 z-30 w-[380px] -translate-y-1/2'
             : `fixed inset-x-0 bottom-0 z-30 max-h-[70vh] overflow-y-auto rounded-t-3xl bg-asfalto-900 px-6 pb-[max(24px,env(safe-area-inset-bottom))] pt-6
                shadow-[0_-30px_60px_-20px_rgba(0,0,0,.8)] transition-transform duration-300 ${aberto ? 'translate-y-0' : 'translate-y-full'}`}>
      {!lateral && (
        <button type="button" onClick={aoFechar} aria-label="Fechar o guia" className="absolute right-4 top-4 rounded-full p-2 text-asfalto-400">
          <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true"><path d="M3 3l8 8M11 3l-8 8" stroke="currentColor" strokeWidth="1.6" /></svg>
        </button>
      )}
      <div key={chave} className="surgir">
        <p className="text-[12px] font-medium uppercase tracking-[0.22em] text-marca-claro">{nomeAparelho}</p>
        {foco?.tipo === 'controle' && foco.tela && (
          <p className="mt-6 text-[13px] text-asfalto-400">Na tela {foco.tela}</p>
        )}
        <h3 className={`titulo text-[clamp(30px,2.6vw,44px)] ${foco?.tipo === 'controle' ? 'mt-1' : 'mt-6'}`}>{titulo}</h3>
        {texto && <p className="mt-4 text-[clamp(16px,1.15vw,19px)] leading-relaxed text-asfalto-300">{texto}</p>}
        {foco?.valor && <p className="mt-5 text-[15px] tabular-nums text-asfalto-100">{foco.valor}</p>}
        {itens.length > 0 && (
          <ul className="mt-7 space-y-3.5">
            {itens.map(t => (
              <li key={t} className="flex gap-3 text-[15px] leading-relaxed text-asfalto-100/85">
                <span className="mt-[11px] h-px w-3 flex-none bg-marca-claro/70" aria-hidden="true" />{t}
              </li>
            ))}
          </ul>
        )}
      </div>
    </aside>
  );
}
