import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Palco, Aparelho, APARELHOS, escalaPara, tamanhoNaTela } from './motor/palco.js';
import Guia, { focoDoToque } from './componentes/Guia.jsx';

// Os apps Flutter ficam na pasta app/ ao lado e conversam com esta página só por mensagens
const ENDERECO_APP = new URL('app/', location.href).href;
const ORIGEM_APP = new URL(ENDERECO_APP).origin;

// Rolagem em alturas de tela: telas 1 a 3 (0–2) com o fundo parado; a partir de SAIDA o tablet sai e o celular
// vem; depois duas faixas em que o aparelho fica parado, de frente e utilizável (o celular em CEL, o tablet em TAB)
const SAIDA = 2.3;
const CEL = [2.9, 3.7];
const TAB = [4.4, 5.2];
const P_CEL = 3.3;
const P_TAB = 4.8;
const FIM = TAB[1];
// Guia ao lado (texto solto à direita) a partir desta largura; abaixo dela, painel inferior aberto pelo botão "Guia"
const LARGURA_LATERAL = 1100;
const GUIA = { largura: 380, margem: 56, folga: 48 };
const limitar = x => Math.min(1, Math.max(0, x));
const suave = x => { const t = limitar(x); return t * t * (3 - 2 * t); };
const misturar = (a, b, e) => a + (b - a) * e;
const misturarPose = (p, q, e) => ({ x: misturar(p.x, q.x, e), y: misturar(p.y, q.y, e), z: misturar(p.z, q.z, e), s: misturar(p.s, q.s, e) });
// Altura do palco (estável: não muda quando as barras do navegador do celular somem ou voltam)
let ALTURA = window.innerHeight;
const progresso = () => window.scrollY / ALTURA;
// Aparelho de quem visita (só com toque): celular se o lado menor da tela tem menos de 600 px, senão tablet
const aparelhoDoVisitante = () =>
  !window.matchMedia('(pointer: coarse)').matches ? null : Math.min(screen.width, screen.height) < 600 ? 'celular' : 'tablet';
// Transformação que leva o elemento (sem transformação, origem no canto) a ocupar o retângulo r
function transformarPara(el, r) {
  const b = el.getBoundingClientRect();
  return `translate(${r.left - b.left}px, ${r.top - b.top}px) scale(${r.width / b.width}, ${r.height / b.height})`;
}

// Fundo das telas 1 a 3: os dois juntos, em exposição, abaixo dos textos — o tablet à esquerda virado para a
// esquerda, o celular à direita virado para a direita (INCL), com as bordas de dentro mais perto de quem olha
const INCL = 0.32;
function composicao(W, H) {
  const estreito = W < 900;
  const sTab = escalaPara('tablet', 0, { w: W * (estreito ? 0.62 : 0.46), h: H * (estreito ? 0.24 : 0.38) });
  const sCel = escalaPara('celular', 0, { w: W * (estreito ? 0.3 : 0.24), h: H * (estreito ? 0.3 : 0.46) });
  const tab = tamanhoNaTela('tablet', sTab), cel = tamanhoNaTela('celular', sCel);
  const vao = W * (estreito ? 0.05 : 0.04);
  const x0 = (W - (tab.w + vao + cel.w)) / 2;
  // em tela estreita os aparelhos sobem para o meio do espaço livre abaixo do texto (sem vão nem encostar no rodapé)
  const yTab = H * (estreito ? 0.64 : 0.73);
  return {
    tablet: { x: x0 + tab.w / 2, y: yTab, z: 0, s: sTab },
    celular: { x: x0 + tab.w + vao + cel.w / 2, y: yTab + tab.h / 2 - cel.h / 2 + 10, z: 0, s: sCel },
  };
}

// Pose de frente na seção: centralizado se couber sem encostar no guia; senão, centralizado no espaço à esquerda
// do guia (o tablet, e o celular deitado em telas menores). O texto do guia fica sempre à direita.
function deFrente(tipo, rz, W, H) {
  // Tela de celular: o aparelho ocupa todo o espaço entre o cabeçalho (52 px) e os controles (84 px)
  // (escalaPara desconta 40 px de margem da área; aqui sobram 8 px de cada lado)
  if (W < 700) {
    const livre = H - 52 - 84;
    return { x: W / 2, y: 52 + livre / 2, z: 0, s: escalaPara(tipo, rz, { w: W + 24, h: livre + 32 }) };
  }
  const altura = H * (W < 900 ? 0.72 : 0.78);
  if (W < LARGURA_LATERAL) return { x: W / 2, y: H * 0.52, z: 0, s: escalaPara(tipo, rz, { w: W * 0.94, h: altura }) };
  const limite = W - GUIA.margem - GUIA.largura - GUIA.folga;
  const centrado = escalaPara(tipo, rz, { w: 2 * (limite - W / 2), h: altura });
  const esquerda = escalaPara(tipo, rz, { w: limite - 32, h: altura });
  // fica no centro se perder pouco tamanho; senão vai para a esquerda
  if (tipo === 'celular' && centrado >= esquerda * 0.85) return { x: W / 2, y: H * 0.53, z: 0, s: centrado };
  return { x: 32 + (limite - 32) / 2, y: H * 0.53, z: 0, s: esquerda };
}

// Escala de cada aparelho na sua seção (é nela que o app é visto de perto): define a densidade fixa
const escalasSecao = (W, H) => ({ celular: deFrente('celular', 0, W, H).s, tablet: deFrente('tablet', 0, W, H).s });

// Centro (em px da página, no plano z = 0) para um aparelho recuado em z aparecer com o centro em xTela:
// a perspectiva puxa para o meio o que está ao fundo, então o ponto precisa ir mais longe
const DIST = H => H / 2 / Math.tan((15 * Math.PI) / 180);
const xNoFundo = (xTela, z, W, H) => W / 2 + (xTela - W / 2) * (DIST(H) - z) / DIST(H);

function alvos(p, W, H, giros) {
  const comp = composicao(W, H);
  const t1 = suave((p - SAIDA) / (CEL[0] - SAIDA)), t2 = suave((p - CEL[1]) / (TAB[0] - CEL[1]));
  // Numa tela em pé (celular), o tablet chega em pé: deitado ele ficaria pequeno demais para ler. "Girar" inverte.
  const tabletEmPe = W < H && t2 > 0.5;
  const rzCel = giros.celular ? APARELHOS.celular.giro : 0;
  const rzTab = giros.tablet !== tabletEmPe ? APARELHOS.tablet.giro : 0;
  const celFrente = deFrente('celular', rzCel, W, H);
  const tabFrente = deFrente('tablet', rzTab, W, H);
  // Fora de cena: recuados em profundidade e inteiramente além da borda (sem sobrar uma faixa visível).
  // Cada um sai pelo seu lado: o tablet pela esquerda, o celular pela direita.
  const Z_FORA = -650, f = DIST(H) / (DIST(H) - Z_FORA);
  const tabFora = { x: xNoFundo(-tamanhoNaTela('tablet', comp.tablet.s).w * f * 0.6, Z_FORA, W, H), y: H * 0.56, z: Z_FORA, s: comp.tablet.s };
  const celFora = { x: xNoFundo(W + tamanhoNaTela('celular', celFrente.s).w * f * 0.6, Z_FORA, W, H), y: H * 0.56, z: Z_FORA, s: celFrente.s };
  // t1: o tablet gira como um pião (da esquerda para a direita) e se afasta; o celular vem ao centro, de frente.
  // t2: o celular faz o mesmo giro saindo pela direita; o tablet volta desfazendo o seu giro.
  // Tudo é função da rolagem: subindo, cada quadro volta pelo mesmo caminho, ao contrário.
  const cel = misturarPose(misturarPose(comp.celular, celFrente, t1), celFora, t2);
  const tab = misturarPose(misturarPose(comp.tablet, tabFora, t1), tabFrente, t2);
  const VOLTA = 2 * Math.PI;
  return {
    celular: { ...cel, rz: rzCel, inclX: 0, inclY: INCL * (1 - t1) + VOLTA * t2 },
    tablet: { ...tab, rz: rzTab, inclX: 0, inclY: -INCL * (1 - t1) + VOLTA * t1 * (1 - t2) },
  };
}

// Textos das telas: entram em [a, b] e saem em [c, d]
const TEXTOS = [
  // Os três pilares do app, um por tela: o que compensa pela distância, o histórico e a comunidade que ganha pontos
  { faixa: [-1, -0.5, 0.35, 0.7], olho: 'GasPrice', titulo: 'Abasteça onde compensa.', sub: 'Veja quanto custa o litro nos postos ao seu redor e escolha o melhor para o seu caminho.', h1: true },
  { faixa: [0.62, 0.85, 1.3, 1.55], titulo: 'Acompanhe cada variação.', sub: 'Confira como o combustível mudou com o tempo e saiba na hora quando ele subir ou cair.' },
  { faixa: [1.62, 1.85, 2.25, 2.5], titulo: 'Quem abastece,\natualiza.', sub: 'Fotografe o painel, confirme os valores com a comunidade e ganhe pontos.' },
];
const visivel = (p, [a, b, c, d]) => suave((p - a) / (b - a)) * (1 - suave((p - c) / (d - c)));

let sequencia = 0;
const TIPOS = ['celular', 'tablet'];

export default function App() {
  const caixa = useRef(null);
  const motor = useRef({});
  const textos = useRef([]);
  const dica = useRef(null);
  const giros = useRef({ celular: false, tablet: false });
  const [ativo, setAtivo] = useState(null);           // aparelho da seção atual
  const [presenca, setPresenca] = useState(0);        // 0..1: quanto os controles e o guia aparecem
  const [largura, setLargura] = useState(() => window.innerWidth);
  const [guiaAberto, setGuiaAberto] = useState(false); // só em telas estreitas (no computador o guia fica sempre ao lado)
  const [focos, setFocos] = useState({ celular: null, tablet: null });
  const [xControles, setXControles] = useState(null);
  // Trava: ao chegar num aparelho (com mouse), a página para e a roda passa a agir no app, até um clique fora dele
  const [travado, setTravado] = useState(null);       // aparelho travado
  const [aviso, setAviso] = useState(null);           // { x, y }: o alto do aparelho, onde fica o aviso
  const [altura, setAltura] = useState(() => ALTURA);
  const telas = useRef({ celular: 'Mapa', tablet: 'Mapa' });
  const ativoRef = useRef(null);
  const lateral = largura >= LARGURA_LATERAL;

  // base: a explicação da tela à vista (o resumo, no início); folhas, menus e diálogos explicam por cima dela e,
  // quando fecham, o guia volta a ela
  const bases = useRef({ celular: null, tablet: null });
  const focar = useCallback((tipo, foco) => {
    if (foco.tipo === 'tela') bases.current[tipo] = foco;
    setFocos(f => ({ ...f, [tipo]: { ...foco, n: ++sequencia } }));
  }, []);
  const voltarABase = useCallback(tipo => {
    const base = bases.current[tipo];
    setFocos(f => ({ ...f, [tipo]: base ? { ...base, n: ++sequencia } : null }));
  }, []);

  // Tela cheia (duplo toque no aparelho): o app ocupa o celular de quem visita, na tela em que estava.
  // O voltar do Android fecha (uma entrada no histórico), como num app de verdade.
  // Abre crescendo a partir da tela do aparelho e fecha encolhendo de volta até ela, já na tela em que a pessoa
  // estava. Enquanto aberta, o palco fica pausado (não se refaz quando o navegador entra e sai da tela cheia).
  const [telaCheia, setTelaCheia] = useState(null);   // { src, origem }: endereço do app e o retângulo de onde cresce
  const [appCheioPronto, setAppCheioPronto] = useState(false);
  const cheia = useRef({ aberta: false, fechando: false, scroll: 0, tipo: null });
  const fundoCheio = useRef(null), barraCheia = useRef(null), caixaCheia = useRef(null), appCheio = useRef(null);
  const abrirTelaCheia = useCallback(tipo => {
    const c = cheia.current, ap = motor.current.aparelhos?.[tipo];
    // cada aparelho abre em tela cheia só no aparelho do mesmo tipo: o celular num celular, o tablet num tablet
    if (c.aberta || !ap || tipo !== aparelhoDoVisitante()) return;
    // O normal: a própria tela do aparelho vai para a tela cheia do navegador, com o mesmo app (abre na hora, na
    // mesma tela e com o mesmo mapa, sem outra cópia do app pesando na memória e nos contextos WebGL)
    if (document.fullscreenEnabled && ap.telaEl.requestFullscreen) {
      // onde a tela do app está na página: ao fechar, ela encolhe até aqui antes de sair da tela cheia
      Object.assign(c, { aberta: true, fechando: false, scroll: window.scrollY, tipo, modo: 'aparelho',
                         origem: ap.iframe.getBoundingClientRect(), alturaAntes: window.innerHeight });
      motor.current.palco.pausar();
      ap.telaEl.requestFullscreen({ navigationUI: 'hide' })
        .then(() => ap.mensagem('escala', 1))   // em tela cheia o app desenha 1:1, no tamanho real da tela
        .catch(() => {
          Object.assign(c, { aberta: false, modo: null });
          motor.current.palco.retomar();
          abrirCopia(tipo);
        });
      return;
    }
    abrirCopia(tipo);
  }, []);
  // Reserva (navegador sem tela cheia de elemento, como o Safari do iPhone): uma cópia do app por cima da página
  const abrirCopia = useCallback(tipo => {
    const c = cheia.current, ap = motor.current.aparelhos[tipo];
    ap.mensagem('guardar', true);
    let rota = '';
    try { rota = ap.iframe.contentWindow.location.hash; } catch { /* carregando */ }
    const dpr = Math.min(3, window.devicePixelRatio || 1);
    const versao = document.querySelector('meta[name="versao-app"]')?.content;
    Object.assign(c, { aberta: true, fechando: false, scroll: window.scrollY, tipo, modo: 'copia' });
    motor.current.palco.pausar();
    // o outro aparelho fica escondido: libera o app dele para o da tela cheia não passar do limite de contextos
    // WebGL do celular (passando, o navegador apaga o mapa deste aparelho); volta quando a pessoa chegar nele
    clearTimeout(motor.current.tabletDepois);
    motor.current.aparelhos[tipo === 'celular' ? 'tablet' : 'celular'].descarregar();
    document.documentElement.classList.add('travado');
    try { history.pushState({ telaCheia: true }, ''); } catch { /* sem histórico */ }
    setAppCheioPronto(false);
    setTelaCheia({ src: `${ENDERECO_APP}?dpr=${dpr}&escala=1${versao ? `&v=${versao}` : ''}${rota}`, origem: ap.iframe.getBoundingClientRect() });
  }, []);
  useLayoutEffect(() => {
    if (!telaCheia) return;
    const caixa = caixaCheia.current, ms = 420, curva = 'cubic-bezier(.2,.8,.2,1)';
    caixa.animate([{ transform: transformarPara(caixa, telaCheia.origem), borderRadius: '22px' }, { transform: 'none', borderRadius: '0px' }],
      { duration: ms, easing: curva });
    [fundoCheio.current, barraCheia.current].forEach(el => el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: ms, easing: curva }));
    // tela cheia do navegador (some a barra de endereço) só depois de crescer: o redimensionar não briga com o movimento
    const t = setTimeout(() => document.documentElement.requestFullscreen?.({ navigationUI: 'hide' }).catch(() => {}), ms);
    const reserva = setTimeout(() => setAppCheioPronto(true), 6000);
    return () => { clearTimeout(t); clearTimeout(reserva); };
  }, [telaCheia]);
  const fecharTelaCheia = useCallback(async () => {
    const c = cheia.current, ap = motor.current.aparelhos?.[c.tipo];
    if (!c.aberta || c.fechando || !ap) return;
    c.fechando = true;
    if (c.modo === 'aparelho') {
      const coluna = ap.sistemaEl.querySelector('.coluna');
      let encolhida = null;
      if (document.fullscreenElement === ap.telaEl) {
        // Fechar: a tela encolhe ainda na tela cheia (o app parado, o movimento fica liso) até o lugar do aparelho;
        // a barra do navegador volta em cima, então o lugar desce o quanto a janela cresceu ao entrar
        const o = c.origem, b = coluna.getBoundingClientRect(), desce = window.innerHeight - c.alturaAntes;
        const curva = 'cubic-bezier(.4,0,.2,1)';
        ap.telaEl.querySelector('.barra-cheia').animate([{ opacity: 1 }, { opacity: 0 }], { duration: 180, fill: 'forwards' });
        encolhida = coluna.animate([
          { transform: 'none', borderRadius: '0px' },
          { transform: `translate(${o.left - b.left}px, ${o.top + desce - b.top}px) scale(${o.width / b.width}, ${o.height / b.height})`, borderRadius: '18px' },
        ], { duration: 420, easing: curva, fill: 'forwards' });
        await encolhida.finished.catch(() => {});
      }
      // o app volta à escala do aparelho junto com a saída da tela cheia: reorganiza uma vez só
      ap.mensagem('escala', ap.k);
      if (document.fullscreenElement) await document.exitFullscreen?.().catch(() => {});
      motor.current.palco.retomar();
      window.scrollTo(0, c.scroll);
      if (encolhida) {
        encolhida.cancel();
        ap.telaEl.querySelectorAll('.barra-cheia').forEach(el => el.getAnimations().forEach(a => a.cancel()));
        Object.assign(c, { aberta: false, fechando: false, modo: null });
        return;
      }
      // saiu pelo navegador (voltar do Android, Esc): encolhe já na página, do tamanho da tela até o aparelho
      await new Promise(r => requestAnimationFrame(r));
      const sis = ap.sistemaEl, base = sis.style.transform, R = sis.getBoundingClientRect(), e = R.width / sis.offsetWidth;
      if (R.width > 0 && e > 0) {
        const vw = window.innerWidth, vh = window.innerHeight;
        const de = `${base} translate(${(vw / 2 - (R.left + R.width / 2)) / e}px, ${(vh / 2 - (R.top + R.height / 2)) / e}px) scale(${vw / R.width}, ${vh / R.height})`;
        ap.telaEl.style.overflow = 'visible';
        // o corpo do aparelho (camada WebGL, por cima) some enquanto a tela encolhe e volta em volta dela
        document.querySelector('.camada-gl')?.animate([{ opacity: 0 }, { opacity: 0, offset: 0.55 }, { opacity: 1 }], { duration: 520 });
        await sis.animate([{ transform: de }, { transform: base }], { duration: 480, easing: 'cubic-bezier(.4,0,.2,1)' }).finished.catch(() => {});
        ap.telaEl.style.overflow = '';
      }
      Object.assign(c, { aberta: false, fechando: false, modo: null });
      return;
    }
    barraCheia.current?.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 200, fill: 'forwards' });
    // o aparelho do site passa para a tela em que a pessoa estava na tela cheia
    try {
      const rota = appCheio.current.contentWindow.location.hash;
      if (rota && ap.iframe.contentWindow.location.hash !== rota) ap.iframe.contentWindow.location.hash = rota;
    } catch { /* carregando */ }
    if (document.fullscreenElement) {
      await document.exitFullscreen?.().catch(() => {});
      await new Promise(r => {
        const t = setTimeout(r, 350);
        window.addEventListener('resize', () => { clearTimeout(t); setTimeout(r, 120); }, { once: true });
      });
    }
    motor.current.palco.retomar();
    window.scrollTo(0, c.scroll);
    // o mapa deste aparelho ficou escondido: redesenha antes de a tela encolher até ele
    ap.mensagem('reavivar', true);
    for (let i = 0; i < 3; i++) await new Promise(r => requestAnimationFrame(r));
    const caixa = caixaCheia.current, ms = 460, curva = 'cubic-bezier(.4,0,.2,1)';
    if (caixa) {
      const fim = caixa.animate([{ transform: 'none', borderRadius: '0px' }, { transform: transformarPara(caixa, ap.iframe.getBoundingClientRect()), borderRadius: '22px' }],
        { duration: ms, easing: curva, fill: 'forwards' });
      fundoCheio.current?.animate([{ opacity: 1 }, { opacity: 0 }], { duration: ms * 0.8, easing: curva, fill: 'forwards' });
      await fim.finished.catch(() => {});
      // já no lugar e na mesma tela: some por cima do aparelho
      await caixa.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 180, fill: 'forwards' }).finished.catch(() => {});
    }
    setTelaCheia(null);
    Object.assign(c, { aberta: false, fechando: false });
    // o outro aparelho, liberado ao abrir, volta a carregar já (fica pronto antes de a pessoa chegar nele)
    TIPOS.forEach(t => motor.current.garantir?.(t));
    if (!motor.current.trava?.tipo) document.documentElement.classList.remove('travado');
  }, []);
  useEffect(() => {
    // O voltar do Android primeiro volta as telas do app (cada navegação no iframe entra no histórico) e, na
    // entrada criada ao abrir, fecha. "Fechar", Esc e sair da tela cheia do navegador fecham direto.
    const voltou = () => fecharTelaCheia();
    const saiu = () => { if (!document.fullscreenElement) fecharTelaCheia(); };
    const tecla = e => { if (e.key === 'Escape') fecharTelaCheia(); };
    window.addEventListener('gasprice-fechar-cheia', fecharTelaCheia);
    window.addEventListener('popstate', voltou);
    document.addEventListener('fullscreenchange', saiu);
    window.addEventListener('keydown', tecla);
    return () => {
      window.removeEventListener('gasprice-fechar-cheia', fecharTelaCheia);
      window.removeEventListener('popstate', voltou);
      document.removeEventListener('fullscreenchange', saiu);
      window.removeEventListener('keydown', tecla);
    };
  }, [fecharTelaCheia]);

  useEffect(() => {
    const medir = () => setLargura(window.innerWidth);
    window.addEventListener('resize', medir);
    return () => window.removeEventListener('resize', medir);
  }, []);

  // Palco, aparelhos e o laço que faz cada aparelho perseguir a pose-alvo com amortecimento
  useEffect(() => {
    const sujo = { valor: true };
    const palco = new Palco(caixa.current, {
      aoRedimensionar: () => {
        sujo.valor = true;
        ALTURA = caixa.current?.clientHeight || ALTURA;
        setAltura(ALTURA);
      },
    });
    const aparelhos = {};
    for (const tipo of TIPOS) {
      aparelhos[tipo] = new Aparelho(palco, tipo, { enderecoApp: ENDERECO_APP });
    }
    motor.current = { palco, aparelhos };
    const inicial = alvos(progresso(), palco.largura, palco.altura, giros.current);
    const atual = {};
    for (const tipo of TIPOS) {
      atual[tipo] = { ...inicial[tipo], rc: inicial[tipo].rz };
      aparelhos[tipo].aplicar(atual[tipo], true);
    }
    palco.desenhar();
    // O celular carrega primeiro; o tablet logo depois, para os dois apps não disputarem o início
    const escalas = () => escalasSecao(palco.largura, palco.altura);
    // escala do aparelho parado na sua seção, na orientação dada: é nela que o app desenha (nítido, 1:1)
    const escalaParado = (tipo, rz) => deFrente(tipo, rz, palco.largura, palco.altura).s;
    aparelhos.celular.carregar(escalas().celular);
    // os dois apps carregam juntos (o celular sai um instante antes, para o pedido dele ir primeiro)
    const tabletDepois = setTimeout(() => motor.current.carregarTablet(), 150);
    motor.current.tabletDepois = tabletDepois;
    // carrega o app do aparelho se ainda não está (ou foi liberado pela tela cheia), na escala da sua pose atual
    motor.current.garantir = tipo => {
      if (!aparelhos[tipo].carregado) aparelhos[tipo].carregar(escalaParado(tipo, atual[tipo].rc));
    };
    motor.current.carregarTablet = () => {
      clearTimeout(tabletDepois);
      motor.current.garantir('tablet');
    };
    const relogio = setInterval(() => TIPOS.forEach(t => aparelhos[t].marcarHora()), 15000);

    // Trava da rolagem. "liberado": a pessoa destravou nesta passagem; volta a travar só depois de sair da faixa
    const trava = { tipo: null, liberado: { celular: false, tablet: false } };
    const comMouse = () => window.matchMedia('(pointer: fine)').matches;
    const travar = tipo => {
      trava.tipo = tipo;
      document.documentElement.classList.add('travado');
      // centraliza no aparelho (a rolagem programada continua valendo com a página travada)
      window.scrollTo({ top: (tipo === 'celular' ? P_CEL : P_TAB) * ALTURA, behavior: 'smooth' });
      aparelhos[tipo].mensagem('travar', true);
      setTravado(tipo);
    };
    const destravar = () => {
      const tipo = trava.tipo;
      if (!tipo) return;
      trava.tipo = null;
      trava.liberado[tipo] = true;
      document.documentElement.classList.remove('travado');
      aparelhos[tipo].mensagem('travar', false);
      setTravado(null);
    };
    // Clique fora do aparelho destrava (os controles sob ele, como Girar, não contam)
    const aoClicar = ev => {
      const tipo = trava.tipo;
      if (!tipo || ev.target.closest?.('nav[aria-label="Aparelho"]')) return;
      const r = aparelhos[tipo].telaEl.getBoundingClientRect(), m = 24;
      if (ev.clientX >= r.left - m && ev.clientX <= r.right + m && ev.clientY >= r.top - m && ev.clientY <= r.bottom + m) return;
      destravar();
    };
    window.addEventListener('pointerdown', aoClicar, true);
    motor.current.trava = trava;
    motor.current.destravar = destravar;

    const parado = { celular: true, tablet: true };
    let ultimo = performance.now(), ultP = -1, ultPresenca = -1, ultX = -1, id;
    const passo = agora => {
      const dt = Math.min(0.05, (agora - ultimo) / 1000);
      ultimo = agora;
      const p = progresso();
      // Fora da sua seção, o aparelho volta à orientação natural: nunca fica "preso" na última forma
      if (giros.current.celular && (p < CEL[0] - 0.2 || p > CEL[1] + 0.2)) giros.current.celular = false;
      if (giros.current.tablet && p < TAB[0] - 0.2) giros.current.tablet = false;
      const alvo = alvos(p, palco.largura, palco.altura, giros.current);
      // Ao entrar na faixa de um aparelho, trava (uma vez por passagem)
      const faixa = p >= CEL[0] && p <= CEL[1] ? 'celular' : p >= TAB[0] ? 'tablet' : null;
      TIPOS.forEach(t => { if (faixa !== t) trava.liberado[t] = false; });
      if (faixa && !trava.tipo && !trava.liberado[faixa] && comMouse()) travar(faixa);
      if (trava.tipo) {
        const b = alvo[trava.tipo], tam = tamanhoNaTela(trava.tipo, b.s);
        const alturaAparelho = Math.abs(Math.sin(b.rz)) > 0.5 ? tam.w : tam.h;
        const y = Math.round(b.y - alturaAparelho / 2), x = Math.round(b.x);
        setAviso(v => (v && Math.abs(v.x - x) < 1 && Math.abs(v.y - y) < 1 ? v : { x, y }));
      }
      if (sujo.valor) {
        TIPOS.forEach(t => {
          if (aparelhos[t].carregado) aparelhos[t].fixarEscala(escalaParado(t, atual[t].rc));
        });
      }
      // A coreografia é a experiência: anima sempre, mesmo com "movimento reduzido" no sistema
      const k = 1 - Math.exp(-dt * 6.5);
      let desenhar = sujo.valor;
      for (const tipo of TIPOS) {
        const a = atual[tipo], b = alvo[tipo], ap = aparelhos[tipo];
        let dPx = 0, dAng = 0, passoAplicado = 0;
        const mover = c => {
          const d = (b[c] - a[c]) * k;
          a[c] += d;
          passoAplicado = Math.max(passoAplicado, Math.abs(d));
          return Math.abs(b[c] - a[c]);
        };
        for (const c of ['x', 'y', 'z']) dPx = Math.max(dPx, mover(c));
        mover('s');
        for (const c of ['rz', 'inclX', 'inclY']) dAng = Math.max(dAng, mover(c));
        // Rotação como no Android: o corpo gira levando o app; quando chega, o app apaga, assume a nova
        // orientação e acende (sem fundo preto nem tela se reajustando à vista)
        if (!ap.virando && Math.abs(b.rz - a.rz) < 0.04 && Math.abs(b.rz - a.rc) > 0.001) ap.virarConteudo(a, b.rz, escalaParado(tipo, b.rz));
        dAng = Math.max(dAng, Math.abs(b.rz - a.rc), Math.abs(b.s - a.s) * 4);
        const mexendo = dPx > 0.35 || dAng > 0.0012 || passoAplicado > 0.05 || ap.virando;
        if (mexendo) {
          ap.movimento(true, a);
          ap.aplicar(a);
          parado[tipo] = false;
          desenhar = true;
        } else if (!parado[tipo] || sujo.valor) {
          Object.assign(a, b, { rc: b.rz });
          if (!parado[tipo]) ap.movimento(false, a);
          else ap.aplicar(a, true);
          parado[tipo] = true;
          desenhar = true;
        }
      }
      sujo.valor = false;
      if (desenhar) palco.desenhar();

      if (Math.abs(p - ultP) > 0.0004 || desenhar) {
        ultP = p;
        textos.current.forEach((el, i) => {
          if (!el) return;
          const v = visivel(p, TEXTOS[i].faixa);
          el.style.opacity = v;
          el.style.transform = `translateY(${(1 - v) * 20}px)`;
          el.style.visibility = v > 0.002 ? 'visible' : 'hidden';
        });
        if (dica.current) dica.current.style.opacity = 1 - suave(p / 0.3);
        const novoAtivo = p < CEL[0] - 0.3 ? null : p < (CEL[1] + TAB[0]) / 2 ? 'celular' : 'tablet';
        if (novoAtivo !== ativoRef.current) {
          ativoRef.current = novoAtivo;
          setAtivo(novoAtivo);
          if (novoAtivo === 'tablet') motor.current.carregarTablet();
          else if (novoAtivo) motor.current.garantir(novoAtivo);
        }
        // Controles e guia aparecem inteiros em toda a faixa da seção e somem nas transições
        const pres = novoAtivo === 'celular'
          ? Math.min(suave((p - (CEL[0] - 0.3)) / 0.3), 1 - suave((p - CEL[1]) / 0.3))
          : novoAtivo === 'tablet' ? suave((p - (TAB[0] - 0.3)) / 0.3) : 0;
        const presLim = Math.round(limitar(pres) * 50) / 50;
        if (presLim !== ultPresenca) { ultPresenca = presLim; setPresenca(presLim); }
        // os controles ficam sob o aparelho da seção
        if (novoAtivo) {
          const x = Math.round(alvo[novoAtivo].x);
          if (Math.abs(x - ultX) > 1) { ultX = x; setXControles(x); }
        }
      }
      // O app só recebe toque com o aparelho parado, de frente e na sua seção
      aparelhos.celular.interativo(parado.celular && p >= CEL[0] && p <= CEL[1]);
      aparelhos.tablet.interativo(parado.tablet && p >= TAB[0]);
      id = requestAnimationFrame(passo);
    };
    id = requestAnimationFrame(passo);
    return () => {
      cancelAnimationFrame(id);
      clearTimeout(tabletDepois);
      clearInterval(relogio);
      window.removeEventListener('pointerdown', aoClicar, true);
      document.documentElement.classList.remove('travado');
      palco.destruir();
    };
  }, []);

  // Mensagens dos apps (app/lib/servicos/monitor_demo.dart): só dos dois iframes e da origem do app
  useEffect(() => {
    const ouvir = ev => {
      const aps = motor.current.aparelhos;
      if (!aps || ev.origin !== ORIGEM_APP) return;
      // o app da tela cheia avisou que desenhou a primeira tela: aparece
      if (appCheio.current && ev.source === appCheio.current.contentWindow) {
        if (typeof ev.data === 'string' || ev.data?.tipo === 'mapaPronto') setAppCheioPronto(true);
        return;
      }
      const tipo = TIPOS.find(t => ev.source === aps[t].iframe.contentWindow);
      if (!tipo) return;
      const r = ev.data;
      // O aparelho mostra o app quando o mapa dele está desenhado (sem a fase de tela branca)
      if (r && typeof r === 'object' && r.fonte === 'gasprice-app' && r.tipo === 'mapaPronto') {
        aps[tipo].revelar();
        return;
      }
      // Roda do mouse sobre o aparelho (sem clique no app): rola a página
      if (r && typeof r === 'object' && r.fonte === 'gasprice-app' && r.tipo === 'rolar' && Number.isFinite(r.dy)) {
        // com a página travada, a roda não a move (o app ainda não sabia da trava: avisa de novo)
        if (motor.current.trava?.tipo) aps[tipo].mensagem('travar', motor.current.trava.tipo === tipo);
        else window.scrollBy(0, Math.max(-600, Math.min(600, r.dy)));
        return;
      }
      if (r && typeof r === 'object' && r.fonte === 'gasprice-app' && r.tipo === 'telaCheia') {
        abrirTelaCheia(tipo);
        return;
      }
      if (typeof ev.data !== 'string') return;
      let d;
      try { d = JSON.parse(ev.data); } catch { return; }
      if (!d || d.fonte !== 'gasprice') return;
      // o app já desenhou; se a tela dele não tiver mapa (ou o mapa demorar), aparece assim mesmo
      aps[tipo].revelarEm(6000);
      if (d.tipo === 'tela' && typeof d.nome === 'string') {
        const mudou = telas.current[tipo] !== d.nome;
        telas.current[tipo] = d.nome;
        // a primeira tela (o mapa, ao carregar) não substitui o resumo; as seguintes, sim
        if (mudou && ativoRef.current === tipo) focar(tipo, { tipo: 'tela', nome: d.nome });
      } else if (d.tipo === 'toque' && typeof d.rotulo === 'string' && ativoRef.current === tipo) {
        const foco = focoDoToque(d.rotulo, telas.current[tipo]);
        if (foco) focar(tipo, foco);
      } else if (d.tipo === 'retorno' && ativoRef.current === tipo) {
        voltarABase(tipo);
      }
    };
    window.addEventListener('message', ouvir);
    const reserva = setTimeout(() => TIPOS.forEach(t => motor.current.aparelhos?.[t].revelar()), 12000);
    return () => { window.removeEventListener('message', ouvir); clearTimeout(reserva); };
  }, [focar, voltarABase, abrirTelaCheia]);

  // No celular, ao chegar a cada aparelho (uma vez): avisa do duplo toque
  const [dicaCheia, setDicaCheia] = useState(false);
  const viuDica = useRef({});
  useEffect(() => {
    if (!ativo || presenca < 0.95 || viuDica.current[ativo] || ativo !== aparelhoDoVisitante()) return;
    viuDica.current[ativo] = true;
    setDicaCheia(true);
  }, [ativo, presenca]);
  useEffect(() => {
    if (!dicaCheia) return;
    const t = setTimeout(() => setDicaCheia(false), 4000);
    return () => clearTimeout(t);
  }, [dicaCheia]);

  // os botões de navegação destravam e levam à seção (lá o aparelho trava de novo, ao chegar)
  const irPara = p => {
    motor.current.destravar?.();
    window.scrollTo({ top: p * ALTURA, behavior: 'smooth' });
  };

  function girar() {
    if (!ativo) return;
    giros.current[ativo] = !giros.current[ativo];
  }

  const nomeAparelho = ativo ? `${ativo === 'celular' ? 'Celular' : 'Tablet'} · ${APARELHOS[ativo].nome}` : '';
  const controles = presenca > 0.95;
  const botao = 'flex items-center gap-2 rounded-full px-4 py-2.5 text-[14px] font-medium text-asfalto-300 transition-colors hover:text-white focus-visible:outline-2 focus-visible:outline-marca-claro';

  return (
    <>
      <div className="fundo-palco" aria-hidden="true" />
      <div ref={caixa} className="palco3d" />

      <header className="fixed inset-x-0 top-0 z-40 border-b border-white/[0.05] bg-asfalto-950/70 backdrop-blur-xl">
        <div className="mx-auto flex h-[52px] max-w-[1500px] items-center justify-between px-5 md:px-8">
          <button type="button" onClick={() => irPara(0)} className="flex items-center gap-2.5">
            <svg viewBox="0 0 40 40" className="h-7 w-7" aria-hidden="true">
              <rect width="40" height="40" rx="10" fill="#2C3E57" />
              <path d="M13 29V12.5A2.5 2.5 0 0 1 15.5 10h7A2.5 2.5 0 0 1 25 12.5V29M11 29h16M15 14h8v5h-8z" fill="none" stroke="#fff" strokeWidth="2" strokeLinejoin="round" />
              <path d="M25 17h2a2 2 0 0 1 2 2v6a1.5 1.5 0 0 0 3 0v-8l-3-3" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            <span className="text-[17px] font-semibold tracking-[-0.01em]">GasPrice</span>
          </button>
          <nav className="flex items-center gap-1 text-[13px]" aria-label="Seções">
            <button type="button" onClick={() => irPara(P_CEL)} className={`rounded-full px-3 py-1.5 ${ativo === 'celular' ? 'text-white' : 'text-asfalto-400 hover:text-white'}`}>Celular</button>
            <button type="button" onClick={() => irPara(P_TAB)} className={`rounded-full px-3 py-1.5 ${ativo === 'tablet' ? 'text-white' : 'text-asfalto-400 hover:text-white'}`}>Tablet</button>
          </nav>
        </div>
      </header>

      {/* espaço de rolagem da página */}
      <div className="pointer-events-none" style={{ height: (FIM + 1) * altura }} aria-hidden="true" />

      {TEXTOS.map((t, i) => (
        <section key={t.titulo} ref={el => { textos.current[i] = el; }} className="cena inset-x-0 top-[86px] px-6 text-center">
          {t.olho && <p className="text-[13px] font-medium uppercase tracking-[0.28em] text-marca-claro">{t.olho}</p>}
          {/* todos os títulos no mesmo tamanho, contido: o aparelho é o protagonista */}
          {t.h1
            ? <h1 className="titulo mx-auto mt-3 max-w-[18ch] text-[clamp(34px,4.4vw,64px)]">{t.titulo}</h1>
            : <h2 className="titulo mx-auto max-w-[18ch] whitespace-pre-line text-[clamp(34px,4.4vw,64px)]">{t.titulo}</h2>}
          {/* largura que deixa os três subtítulos em duas linhas equilibradas, do mesmo tamanho */}
          <p className="mx-auto mt-4 max-w-[44ch] text-balance text-[clamp(16px,1.4vw,20px)] text-asfalto-300">{t.sub}</p>
        </section>
      ))}

      {/* aviso da trava, acima do aparelho */}
      {travado && aviso && (
        <p role="status" key={travado} style={{ left: aviso.x, top: Math.max(62, aviso.y - 34) }}
           className="surgir pointer-events-none fixed z-30 flex -translate-x-1/2 items-center gap-2 whitespace-nowrap text-[13px] text-asfalto-300">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
            <rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" />
          </svg>
          Clique fora do aparelho para destravar a rolagem
        </p>
      )}

      {dicaCheia && controles && (
        <p role="status" key={ativo}
           className="surgir pointer-events-none fixed left-1/2 top-[9px] z-50 -translate-x-1/2 whitespace-nowrap rounded-full border border-white/[0.08] bg-asfalto-900/95 px-4 py-2 text-[13px] text-asfalto-100 shadow-[0_20px_40px_-15px_rgba(0,0,0,.8)]">
          Toque duas vezes no aparelho para tela cheia
        </p>
      )}

      {telaCheia && (
        <div role="dialog" aria-modal="true" aria-label="GasPrice em tela cheia" className="fixed inset-0 z-[60]">
          <div ref={fundoCheio} className="absolute inset-0 bg-asfalto-950" />
          <div ref={barraCheia} className="absolute inset-x-0 top-0 flex h-11 items-center justify-between px-4 text-[13px] text-asfalto-300">
            <span>GasPrice · demonstração</span>
            <button type="button" onClick={fecharTelaCheia}
                    className="flex items-center gap-1.5 rounded-full px-3 py-1.5 font-medium text-white focus-visible:outline-2 focus-visible:outline-marca-claro">
              Fechar
              <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" /></svg>
            </button>
          </div>
          <div ref={caixaCheia} className="caixa-cheia absolute inset-x-0 bottom-0 top-11 overflow-hidden">
            <iframe ref={appCheio} src={telaCheia.src} title="GasPrice"
                    className={`block h-full w-full border-0 transition-opacity duration-300 ${appCheioPronto ? 'opacity-100' : 'opacity-0'}`} />
          </div>
        </div>
      )}

      {/* controles sob o aparelho da seção */}
      <nav aria-label="Aparelho" style={{ opacity: Math.max(presenca, 0.002), pointerEvents: controles ? 'auto' : 'none', left: xControles ?? '50%' }}
           className="fixed bottom-5 z-30 flex -translate-x-1/2 items-center gap-1 rounded-full border border-white/[0.08] bg-asfalto-900/95 p-1 shadow-[0_20px_40px_-15px_rgba(0,0,0,.8)]">
        {ativo === 'tablet' && (
          <button type="button" onClick={() => irPara(P_CEL)} className={botao}>
            <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M10 3L5 8l5 5" fill="none" stroke="currentColor" strokeWidth="1.6" /></svg>
            Celular
          </button>
        )}
        <button type="button" onClick={girar} className={`${botao} text-white`} aria-label="Girar o aparelho">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.48 2.52c3.27 1.55 5.61 4.72 5.97 8.48h1.5C23.44 4.84 18.29 0 12 0l-.66.03 3.81 3.81 1.33-1.32zm-6.25-.77c-.59-.59-1.54-.59-2.12 0L1.75 8.11c-.59.59-.59 1.54 0 2.12l12.02 12.02c.59.59 1.54.59 2.12 0l6.36-6.36c.59-.59.59-1.54 0-2.12L10.23 1.75zm4.6 19.44L2.81 9.17l6.36-6.36 12.02 12.02-6.36 6.36zm-7.31.29C4.25 19.94 1.91 16.76 1.55 13H.05C.56 19.16 5.71 24 12 24l.66-.03-3.81-3.81-1.33 1.32z" /></svg>
          Girar
        </button>
        {ativo === 'celular' && (
          <button type="button" onClick={() => irPara(P_TAB)} className={botao}>
            Tablet
            <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M6 3l5 5-5 5" fill="none" stroke="currentColor" strokeWidth="1.6" /></svg>
          </button>
        )}
        {!lateral && (
          <button type="button" onClick={() => setGuiaAberto(g => !g)} className={botao} aria-label="Guia da tela" aria-expanded={guiaAberto}>
            Guia
          </button>
        )}
      </nav>

      {ativo && (
        <Guia aparelho={ativo} nomeAparelho={nomeAparelho} foco={focos[ativo]}
              visivel={presenca} lateral={lateral} aberto={guiaAberto} aoFechar={() => setGuiaAberto(false)} />
      )}

      {/* na primeira tela: a página continua para baixo */}
      <div ref={dica} aria-hidden="true"
           className="pointer-events-none fixed inset-x-0 bottom-5 z-10 flex flex-col items-center gap-1 text-[12px] tracking-[0.08em] text-asfalto-400 max-md:bottom-11">
        <span className="toque:hidden">Role para explorar</span>
        <span className="hidden toque:inline">Deslize para explorar</span>
        <svg width="14" height="14" viewBox="0 0 16 16" className="dica-seta" aria-hidden="true">
          <path d="M3 6l5 5 5-5" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </div>

      {/* com que o app foi feito: o que um recrutador de TI procura primeiro */}
      <footer style={{ opacity: 1 - presenca }}
              className="pointer-events-none fixed bottom-3 left-8 z-10 text-[11px] uppercase tracking-[0.2em] text-asfalto-400 max-md:inset-x-0 max-md:left-0 max-md:text-center max-md:text-[10px] max-md:tracking-[0.12em]">
        <span className="max-md:hidden">Projeto acadêmico · </span>Dados fictícios
      </footer>
    </>
  );
}
