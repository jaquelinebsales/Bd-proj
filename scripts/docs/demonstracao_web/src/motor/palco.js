import * as THREE from 'three';
import { CSS3DRenderer, CSS3DObject } from 'three/addons/renderers/CSS3DRenderer.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

// Unidade da cena = 1 dp da tela de cada aparelho. As medidas físicas oficiais viram dp pela escala da própria tela:
// Galaxy S26 Ultra: tela de 6,9" 19,5:9 (412 × 891 dp, 73,4 mm de largura útil → 5,61 dp/mm), corpo 163,6 × 78,1 × 7,9 mm.
// Galaxy Tab S12 Ultra: tela de 14,6" 16:10 (1480 × 924 dp, 314,5 mm → 4,71 dp/mm), corpo 326,3 × 208,5 × 5,1 mm.
// giro: sentido em que o aparelho deita ao sair da orientação natural (celular em pé, tablet deitado).
const MM_CEL = 5.61, MM_TAB = 4.706;
export const APARELHOS = {
  celular: {
    nome: 'Galaxy S26 Ultra', w: 412, h: 891, bordaH: (78.1 * MM_CEL - 412) / 2, bordaV: (163.6 * MM_CEL - 891) / 2,
    espessura: 7.9 * MM_CEL, raio: 8.6 * MM_CEL, raioTela: 6.3 * MM_CEL, chanfro: 0.6 * MM_CEL,
    // traseira: 3 anéis de 11,5 mm na vertical + periscópio menor e flash ao lado; ressalto de 2,5 mm
    lentes: [[14, 15, 5.75], [14, 30.5, 5.75], [14, 46, 5.75], [29, 30.5, 4], [29, 15, 1.4]], ressalto: 2.5, mm: MM_CEL,
    giro: Math.PI / 2, status: 32, statusDeitado: 24, gestos: 20, margem: 24,
    // deitado, a câmera frontal fica à esquerda: o app recua dela como no Android (a faixa tem a cor do app, não preto)
    furoDeitado: 34,
  },
  tablet: {
    nome: 'Galaxy Tab S12 Ultra', w: 1480, h: 924, bordaH: (326.3 * MM_TAB - 1480) / 2, bordaV: (208.5 * MM_TAB - 924) / 2,
    espessura: 5.1 * MM_TAB, raio: 9.5 * MM_TAB, raioTela: 4 * MM_TAB, chanfro: 0.4 * MM_TAB,
    // traseira: 2 anéis de 8 mm na vertical; ressalto de 1 mm
    lentes: [[15, 15, 4], [15, 26, 4]], ressalto: 1, mm: MM_TAB,
    giro: -Math.PI / 2, status: 28, statusDeitado: 28, gestos: 24, margem: 28,
  },
};
const FOV = 30;
const MARGEM = 40;
// A tela do app (camada CSS) é um pouco maior que o recorte no vidro (camada WebGL): a borda visível é a do
// recorte, desenhada com antisserrilhado; a borda da camada CSS, serrilhada em perspectiva, fica escondida sob o vidro
// (2,5: folga também para o ajuste de fração de pixel da tela parada, ver achatar)
const SOBRA = 2.5;
const misturar = (a, b, e) => a + (b - a) * e;
const faixa = w => (w >= 840 ? 2 : w >= 600 ? 1 : 0);
const espera = ms => new Promise(r => setTimeout(r, ms));

function retangulo(w, h, r) {
  const s = new THREE.Shape();
  const x0 = -w / 2, x1 = w / 2, y0 = -h / 2, y1 = h / 2;
  s.moveTo(x0 + r, y0);
  s.lineTo(x1 - r, y0);
  s.absarc(x1 - r, y0 + r, r, -Math.PI / 2, 0, false);
  s.lineTo(x1, y1 - r);
  s.absarc(x1 - r, y1 - r, r, 0, Math.PI / 2, false);
  s.lineTo(x0 + r, y1);
  s.absarc(x0 + r, y1 - r, r, Math.PI / 2, Math.PI, false);
  s.lineTo(x0, y0 + r);
  s.absarc(x0 + r, y0 + r, r, Math.PI, Math.PI * 1.5, false);
  return s;
}

/** Escala para o aparelho caber numa área (em px), já com o giro do corpo; no meio do giro ele se afasta um pouco. */
export function escalaPara(tipo, rz, area) {
  const a = APARELHOS[tipo];
  const r = Math.min(1, Math.abs(rz) / (Math.PI / 2));
  const larg = a.w + 2 * a.bordaH, alt = a.h + 2 * a.bordaV;
  const vw = misturar(larg, alt, r), vh = misturar(alt, larg, r);
  return Math.min(1.1, (area.w - MARGEM) / vw, (area.h - MARGEM) / vh) * (1 - 0.14 * Math.sin(Math.PI * r));
}

export function tamanhoNaTela(tipo, s) {
  const a = APARELHOS[tipo];
  return { w: (a.w + 2 * a.bordaH) * s, h: (a.h + 2 * a.bordaV) * s };
}

const ICONES = `
  <svg width="16" height="12" viewBox="0 0 16 12"><path d="M8 11.5 15.6 3.2A11.5 11.5 0 0 0 .4 3.2Z" fill="currentColor"/></svg>
  <svg width="15" height="12" viewBox="0 0 15 12" fill="currentColor"><rect y="8" width="2.6" height="4" rx=".6"/><rect x="4" y="5.5" width="2.6" height="6.5" rx=".6"/><rect x="8" y="3" width="2.6" height="9" rx=".6"/><rect x="12" width="2.6" height="12" rx=".6"/></svg>
  <svg width="23" height="12" viewBox="0 0 23 12"><rect x=".6" y=".6" width="18.8" height="10.8" rx="2.6" fill="none" stroke="currentColor" stroke-width="1.2"/><rect x="2.4" y="2.4" width="12.4" height="7.2" rx="1.3" fill="currentColor"/><rect x="20.2" y="3.8" width="1.6" height="4.4" rx=".7" fill="currentColor"/></svg>`;
const LOGO = `<svg viewBox="0 0 40 40"><rect width="40" height="40" rx="12" fill="#2C3E57"/>
  <path d="M13 29V12.5A2.5 2.5 0 0 1 15.5 10h7A2.5 2.5 0 0 1 25 12.5V29M11 29h16M15 14h8v5h-8z" fill="none" stroke="#fff" stroke-width="2" stroke-linejoin="round"/>
  <path d="M25 17h2a2 2 0 0 1 2 2v6a1.5 1.5 0 0 0 3 0v-8l-3-3" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

/** Cena 3D compartilhada: uma camada WebGL (corpos dos aparelhos) sobre uma camada CSS3D (os apps de verdade). */
export class Palco {
  constructor(caixa, { aoRedimensionar }) {
    this.caixa = caixa;
    this.aoRedimensionar = aoRedimensionar;
    this.css = new CSS3DRenderer();
    this.css.domElement.className = 'camada-css';
    this.gl = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
    this.gl.setClearColor(0x000000, 0);
    this.gl.setPixelRatio(Math.min(window.devicePixelRatio || 1, 3));
    this.gl.outputColorSpace = THREE.SRGBColorSpace;
    this.gl.toneMapping = THREE.ACESFilmicToneMapping;
    this.gl.domElement.className = 'camada-gl';
    caixa.append(this.css.domElement, this.gl.domElement);

    this.cena = new THREE.Scene();
    const pmrem = new THREE.PMREMGenerator(this.gl);
    this.cena.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    pmrem.dispose();
    const luz = new THREE.DirectionalLight(0xf2f6ff, 1.5);
    luz.position.set(-200, 1200, 900);
    this.cena.add(luz, new THREE.AmbientLight(0xffffff, 0.12));
    this.camera = new THREE.PerspectiveCamera(FOV, 1, 1, 20000);
    this.materiais = {
      vidro: new THREE.MeshPhysicalMaterial({ color: 0x050608, roughness: 0.08, metalness: 0.1, clearcoat: 1, clearcoatRoughness: 0.03, envMapIntensity: 0.8 }),
      metal: new THREE.MeshPhysicalMaterial({ color: 0x9aa2ae, metalness: 0.95, roughness: 0.28, envMapIntensity: 1.1 }),
      costas: new THREE.MeshPhysicalMaterial({ color: 0x1d2633, metalness: 0.3, roughness: 0.45, envMapIntensity: 0.7,
                                               polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }),
      lente: new THREE.MeshPhysicalMaterial({ color: 0x0b0d12, roughness: 0.05, metalness: 0.3, clearcoat: 1 }),
      flash: new THREE.MeshPhysicalMaterial({ color: 0xd8cfb8, roughness: 0.3, metalness: 0.1 }),
      recorte: new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0, blending: THREE.NoBlending,
                                             polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 }),
    };
    this.aparelhos = [];
    this.observador = new ResizeObserver(() => this.redimensionar());
    this.observador.observe(caixa);
    this.redimensionar();
  }

  // Pausado (app em tela cheia por cima): a janela muda de tamanho ao entrar e sair da tela cheia do navegador,
  // e o palco não deve se refazer por trás; ao retomar, mede de novo se o tamanho mudou
  pausar() { this.pausado = true; }
  retomar() {
    this.pausado = false;
    if (this.pendente) { this.pendente = false; this.redimensionar(); }
  }

  redimensionar() {
    if (this.pausado) { this.pendente = true; return; }
    const w = this.caixa.clientWidth, h = this.caixa.clientHeight;
    if (!w || !h) return;
    if (w === this.largura && h === this.altura) return;
    this.largura = w;
    this.altura = h;
    this.camera.aspect = w / h;
    // Distância em que 1 unidade no plano z = 0 vale 1 px da página. Os planos de corte ficam junto da cena
    // (near alto): com near = 1 a profundidade perdia precisão à distância e o recorte "brigava" com o vidro (listras)
    const d = h / 2 / Math.tan(THREE.MathUtils.degToRad(FOV / 2));
    this.camera.position.set(0, 0, d);
    this.camera.near = d * 0.35;
    this.camera.far = d * 3;
    this.camera.updateProjectionMatrix();
    this.gl.setSize(w, h);
    this.css.setSize(w, h);
    this.aoRedimensionar?.();
  }

  desenhar() {
    this.gl.render(this.cena, this.camera);
    this.css.render(this.cena, this.camera);
    this.achatar();
  }

  // Nitidez: dentro da perspectiva do CSS3D o navegador nunca põe a tela do app no grid de pixels (filtra a imagem,
  // que fica mole). Quando todos os aparelhos estão parados e de frente, as telas saem da perspectiva e recebem uma
  // posição 2D em pixels inteiros, na escala exata em que o app desenha: 1:1 com a tela do computador. Qualquer
  // movimento ou inclinação volta ao 3D no mesmo quadro.
  achatar() {
    const camera = this.css.domElement.firstChild?.firstChild;
    if (!camera) return;
    const planos = this.aparelhos.map(ap => ap.poseNoPlano());
    const plano = planos.length > 0 && planos.every(Boolean);
    if (plano) {
      // o renderizador só reescreve o estilo da câmera quando ele muda: guarda o último que escreveu
      if (camera.style.transform !== 'none') this.estiloCamera = camera.style.transform;
      camera.style.transform = 'none';
      camera.style.transformStyle = 'flat';
      this.aparelhos.forEach((ap, i) => ap.aplicarNoPlano(planos[i]));
    } else if (this.plano) {
      camera.style.transform = this.estiloCamera;
      camera.style.transformStyle = 'preserve-3d';
      this.aparelhos.forEach(ap => ap.sairDoPlano());
    }
    this.plano = plano;
  }

  destruir() {
    this.observador.disconnect();
    this.gl.dispose();
    this.caixa.replaceChildren();
  }
}

/**
 * Um aparelho com o app de verdade na tela. pose = { x, y (centro em px da página), z (profundidade), s (escala),
 * rz (giro do corpo), rc (giro do conteúdo), inclX, inclY }. No giro, o corpo vira levando o app (rc parado);
 * quando chega, o app apaga, assume a nova orientação e acende — como a rotação do Android.
 */
export class Aparelho {
  constructor(palco, tipo, { enderecoApp, aoMedir }) {
    this.palco = palco;
    this.tipo = tipo;
    this.a = APARELHOS[tipo];
    this.aoMedir = aoMedir;
    this.enderecoApp = enderecoApp;
    this.origemApp = new URL(enderecoApp).origin;
    this.app = { w: 0, h: 0, quando: 0 };
    this.dpr = 1;
    this.k = 1;
    this.montarCorpo();
    this.montarTela();
    palco.aparelhos.push(this);
  }

  montarCorpo() {
    const a = this.a, m = this.palco.materiais;
    const W = a.w + 2 * a.bordaH, H = a.h + 2 * a.bordaV, T = a.espessura, c = a.chanfro;
    this.raiz = new THREE.Group();
    this.giro = new THREE.Group();
    this.raiz.add(this.giro);
    this.palco.cena.add(this.raiz);

    // Corpo com laterais metálicas e cantos suavizados (chanfro)
    const g = new THREE.ExtrudeGeometry(retangulo(W - 2 * c, H - 2 * c, a.raio - c),
      { depth: T - 2 * c, bevelEnabled: true, bevelThickness: c, bevelSize: c, bevelSegments: 6, curveSegments: 32 });
    g.translate(0, 0, -(T - 2 * c) / 2);
    const corpo = new THREE.Mesh(g, [m.vidro, m.metal]);
    const fundo = new THREE.Mesh(new THREE.ShapeGeometry(retangulo(W - 2 * c, H - 2 * c, a.raio - c), 32), m.costas);
    fundo.rotation.y = Math.PI;
    fundo.position.z = -T / 2 - 0.3;
    corpo.add(fundo);
    this.giro.add(corpo);

    if (this.tipo === 'tablet') {
      // câmera frontal na borda, no meio do lado comprido
      const cam = new THREE.Mesh(new THREE.CircleGeometry(1 * a.mm, 24), m.lente);
      cam.position.set(0, a.h / 2 + a.bordaV / 2, T / 2 + 0.3);
      this.giro.add(cam);
    }

    // Câmeras traseiras em mm a partir do canto superior esquerdo visto por trás (que é o lado +x do aparelho)
    const ressalto = a.ressalto * a.mm;
    for (const [mx, my, raioMm] of a.lentes) {
      const r = raioMm * a.mm;
      const x = W / 2 - mx * a.mm, y = H / 2 - my * a.mm;
      const flash = raioMm < 2;
      const aro = new THREE.Mesh(new THREE.CylinderGeometry(r, r, ressalto, 48), flash ? m.flash : m.metal);
      aro.rotation.x = Math.PI / 2;
      aro.position.set(x, y, -T / 2 - ressalto / 2);
      this.giro.add(aro);
      if (!flash) {
        const vidro = new THREE.Mesh(new THREE.CircleGeometry(r * 0.72, 48), m.lente);
        vidro.rotation.y = Math.PI;
        vidro.position.set(x, y, -T / 2 - ressalto - 0.2);
        this.giro.add(vidro);
      }
    }

    // Recorte: ali a camada WebGL fica transparente e aparece o app (camada CSS logo abaixo)
    this.recorte = new THREE.Mesh(new THREE.ShapeGeometry(retangulo(a.w - 2 * SOBRA, a.h - 2 * SOBRA, a.raioTela - SOBRA), 32), m.recorte);
    this.recorte.position.z = T / 2 + 1.5;
    this.giro.add(this.recorte);
  }

  montarTela() {
    const a = this.a;
    const tela = document.createElement('div');
    tela.className = `tela3d ${this.tipo}`;
    tela.style.width = a.w + 'px';
    tela.style.height = a.h + 'px';
    tela.style.borderRadius = a.raioTela + 'px';
    tela.innerHTML = `
      ${this.tipo === 'celular' ? '<span class="furo"></span>' : ''}
      <div class="sistema">
        <div class="coluna">
          <div class="status"><span class="hora"></span><span class="icones">${ICONES}</span></div>
          <div class="conteudo"><div class="carregando">${LOGO}</div></div>
          <div class="gestos"><span></span></div>
        </div>
      </div>`;
    this.telaEl = tela;
    this.sistemaEl = tela.querySelector('.sistema');
    this.horaEl = tela.querySelector('.hora');
    this.carregandoEl = tela.querySelector('.carregando');
    this.iframe = document.createElement('iframe');
    this.iframe.title = `GasPrice no ${this.tipo === 'celular' ? 'celular' : 'tablet'}`;
    tela.querySelector('.conteudo').append(this.iframe);
    this.telaObj = new CSS3DObject(tela);
    this.telaObj.position.z = this.a.espessura / 2 + 1.5;
    this.giro.add(this.telaObj);
    this.marcarHora();
  }

  marcarHora() {
    this.horaEl.textContent = new Date().toLocaleTimeString('pt-BR', { hour: 'numeric', minute: '2-digit' });
  }

  // Nitidez: em vez de a página reduzir a imagem do app (o que a deixa mole), o app desenha já na escala em que o
  // aparelho aparece (k, a escala da pose parada) e na densidade real da tela. Parado, cada pixel do app é um
  // pixel da tela; o layout continua o do aparelho real (app/lib/servicos/monitor_demo.dart, _Escala).
  mensagem(tipo, valor) {
    try { this.iframe.contentWindow.postMessage({ fonte: 'gasprice-moldura', tipo, valor }, this.origemApp); } catch { /* carregando */ }
  }

  fixarEscala(s) {
    const dpr = Math.min(3, window.devicePixelRatio || 1);
    if (dpr !== this.dpr) { this.dpr = dpr; this.mensagem('densidade', dpr); }
    if (Math.abs(s - this.k) < 0.0005) return;
    this.k = s;
    this.mensagem('escala', s);
    this.app = { w: 0, h: 0, quando: 0 };
  }

  carregar(s) {
    this.dpr = Math.min(3, window.devicePixelRatio || 1);
    this.k = s;
    // v = versão do app (gerar_demonstracao.py): um app novo nunca abre com arquivos antigos guardados pelo navegador
    const versao = document.querySelector('meta[name="versao-app"]')?.content;
    this.iframe.src = `${this.enderecoApp}?dpr=${this.dpr}&escala=${s}${versao ? `&v=${versao}` : ''}`;
    this.carregado = true;
  }

  // Libera o app (cada app Flutter usa 5 contextos WebGL e o navegador do celular descarta os mais antigos
  // quando passa do limite); volta a carregar quando a pessoa chegar a este aparelho
  descarregar() {
    if (!this.carregado) return;
    this.carregado = false;
    this.revelado = false;
    clearTimeout(this.esperaRevelar);
    this.esperaRevelar = null;
    this.iframe.classList.remove('pronto');
    this.carregandoEl.style.display = '';
    this.iframe.src = 'about:blank';
  }

  aplicar(q, forcarApp = false) {
    const p = this.palco, a = this.a;
    this.pose = q;
    this.raiz.position.set(q.x - p.largura / 2, p.altura / 2 - q.y, q.z);
    this.raiz.scale.setScalar(q.s);
    this.raiz.rotation.set(q.inclX, q.inclY, 0);
    this.giro.rotation.z = q.rz;
    // Conteúdo: gira ao contrário do corpo na medida de rc e troca de proporção junto (tela até a borda, sem faixa)
    const r = Math.min(1, Math.abs(q.rc) / (Math.PI / 2));
    const sw = misturar(a.w, a.h, r), sh = misturar(a.h, a.w, r);
    const status = misturar(a.status, a.statusDeitado, r);
    const s = this.sistemaEl.style;
    s.width = sw + 'px';
    s.height = sh + 'px';
    s.transform = `translate(-50%, -50%) rotate(${(q.rc * 180) / Math.PI}deg)`;
    s.setProperty('--status', status + 'px');
    s.setProperty('--gestos', a.gestos + 'px');
    s.setProperty('--margem', a.margem + 'px');
    const recuo = (a.furoDeitado || 0) * r;
    s.setProperty('--recuo', recuo + 'px');
    const w = sw - recuo, h = sh - status - a.gestos;
    this.ajustarApp(w, h, forcarApp);
    this.aoMedir?.({ w: Math.round(w), h: Math.round(h), densidade: this.dpr });
  }

  // O app só muda de tamanho de verdade (e se reorganiza) ao cruzar um limite de layout ou quando a diferença passa
  // de 12%; no meio disso a GPU ajusta a imagem dele à tela. Assim o movimento cabe em 120 fps.
  ajustarApp(w, h, forcar) {
    const a = this.app, agora = performance.now();
    const longe = !a.w || Math.abs(w - a.w) / a.w > 0.12 || Math.abs(h - a.h) / a.h > 0.12 || faixa(w) !== faixa(a.w);
    const k = this.k || 1;
    if (forcar || (longe && agora - a.quando >= 50)) {
      // o iframe tem o tamanho em que o app aparece (dp × k, em pixels inteiros); o app desenha nessa escala
      this.app = { w: Math.max(1, Math.round(w)), h: Math.max(1, Math.round(h)), quando: agora };
      this.app.pw = Math.max(1, Math.round(this.app.w * k));
      this.app.ph = Math.max(1, Math.round(this.app.h * k));
      this.iframe.style.width = this.app.pw + 'px';
      this.iframe.style.height = this.app.ph + 'px';
    }
    // a escala do aparelho (k) devolve o iframe ao tamanho da tela em dp; parado, o total na tela é 1:1
    this.iframe.style.transform = `scale(${w / this.app.pw}, ${h / this.app.ph})`;
  }

  // Segunda metade do giro, como no Android: o conteúdo apaga sobre a cor de fundo do app, troca de orientação e de
  // layout de uma vez (sem ninguém ver o reajuste) e acende já pronto. Nada de fundo preto nem tela se reajustando.
  async virarConteudo(q, rcFinal, escalaFinal) {
    this.virando = true;
    const s = this.sistemaEl.style;
    s.transition = 'opacity 0.14s ease-in';
    s.opacity = '0';
    await espera(150);
    // deitado, o aparelho aparece em outra escala: o app passa a desenhar nela enquanto está apagado
    if (escalaFinal) this.fixarEscala(escalaFinal);
    q.rc = rcFinal;
    this.aplicar(q, true);
    this.palco.desenhar();
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    await espera(90);
    s.transition = 'opacity 0.26s ease-out';
    s.opacity = '1';
    await espera(270);
    s.transition = '';
    this.virando = false;
  }

  // Parado, o app assume o tamanho exato da tela (no movimento ele só se reorganiza nos limites de layout)
  movimento(ativo, q) {
    if (ativo === this.emMovimento) return;
    this.emMovimento = ativo;
    this.telaEl.classList.toggle('movendo', ativo);
    if (!ativo && !this.virando) this.aplicar(q, true);
  }

  // Pose 2D da tela quando o aparelho está parado e de frente (só giro no próprio plano); null quando não está
  poseNoPlano() {
    if (this.emMovimento || this.virando || !this.app.pw) return null;
    const m = this.telaObj.matrixWorld.elements;
    const escala = Math.hypot(m[0], m[1], m[2]);
    if (Math.abs(m[8]) > 1e-6 * escala || Math.abs(m[9]) > 1e-6 * escala || m[10] <= 0) return null;
    const cam = this.palco.camera.position.z;
    const fator = cam / (cam - m[14]);
    let graus = (-Math.atan2(m[1], m[0]) * 180) / Math.PI;
    const reto = Math.round(graus / 90) * 90;
    if (Math.abs(graus - reto) < 0.01) graus = reto === 0 ? 0 : reto;
    const s = escala * fator;
    let sx = s, sy = s;
    // na escala em que o app desenha, a tela fica exatamente do tamanho do iframe (pixel do app = pixel da tela)
    if (Math.abs(s - this.k) < 0.01) {
      const deitado = Math.abs(Math.abs(this.pose?.rc ?? 0) - Math.PI / 2) < 0.01;
      const ex = this.app.pw / this.app.w, ey = this.app.ph / this.app.h;
      [sx, sy] = deitado ? [ey, ex] : [ex, ey];
    }
    return { x: this.palco.largura / 2 + m[12] * fator, y: this.palco.altura / 2 - m[13] * fator, graus, sx, sy };
  }

  aplicarNoPlano(p) {
    const el = this.telaEl;
    const chave = `${p.x.toFixed(3)},${p.y.toFixed(3)},${p.graus},${p.sx},${p.sy},${this.app.pw},${this.app.ph}`;
    const estilo = (dx, dy) =>
      `translate(${p.x - this.a.w / 2 + dx}px, ${p.y - this.a.h / 2 + dy}px) rotate(${p.graus}deg) scale(${p.sx}, ${p.sy})`;
    // o estilo 3D que o renderizador escreveu por último (para voltar a ele ao sair do plano)
    if (el.style.transform !== this.estiloNoPlano) this.estilo3d = el.style.transform;
    if (chave !== this.chaveNoPlano) {
      // posição inteira: mede onde o iframe caiu e corrige a fração de pixel
      el.style.transform = estilo(0, 0);
      const r = this.iframe.getBoundingClientRect(), d = window.devicePixelRatio || 1;
      this.ajusteNoPlano = [(Math.round(r.left * d) - r.left * d) / d, (Math.round(r.top * d) - r.top * d) / d];
      this.chaveNoPlano = chave;
    }
    this.estiloNoPlano = estilo(...this.ajusteNoPlano);
    el.style.transform = this.estiloNoPlano;
  }

  sairDoPlano() {
    if (!this.estiloNoPlano) return;
    this.telaEl.style.transform = this.estilo3d;
    this.estiloNoPlano = null;
    this.chaveNoPlano = null;
  }

  interativo(sim) {
    this.telaEl.classList.toggle('interativo', sim);
  }

  revelarEm(ms) {
    if (this.revelado || this.esperaRevelar) return;
    this.esperaRevelar = setTimeout(() => this.revelar(), ms);
  }

  revelar() {
    clearTimeout(this.esperaRevelar);
    this.esperaRevelar = null;
    if (this.revelado) return;
    this.revelado = true;
    this.iframe.classList.add('pronto');
    setTimeout(() => { if (this.revelado) this.carregandoEl.style.display = 'none'; }, 500);
  }
}
