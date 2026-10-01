// Validação pura do corpo do envio. Sem acesso a rede ou banco, para ser testável.

export interface Produto {
  id: number;
  nome: string;
  preco_min: number;
  preco_max: number;
}

export interface ItemRecebido {
  produto_id: number;
  preco: number;
  preco_lido?: number | null;
  confianca?: number | null;
}

export interface CorpoEnvio {
  posto_id: number;
  latitude: number;
  longitude: number;
  itens: ItemRecebido[];
  ocr_texto?: string | null;
  ocr_duracao_ms?: number | null;
  app_versao?: string | null;
}

export interface ItemValido {
  produto_id: number;
  preco: number;
  preco_lido: number | null;
  confianca_ocr: number | null;
}

export type Resultado<T> = { ok: true; valor: T } | { ok: false; mensagem: string };

const numero = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const arred3 = (v: number) => Math.round(v * 1000) / 1000;

export function validarCorpo(corpo: unknown, produtos: Produto[]): Resultado<{ envio: CorpoEnvio; itens: ItemValido[] }> {
  if (!corpo || typeof corpo !== "object") return { ok: false, mensagem: "Corpo da requisição inválido." };
  const c = corpo as Record<string, unknown>;

  if (!Number.isInteger(c.posto_id) || (c.posto_id as number) <= 0) {
    return { ok: false, mensagem: "Posto não informado." };
  }
  if (!numero(c.latitude) || !numero(c.longitude) || Math.abs(c.latitude) > 90 || Math.abs(c.longitude) > 180) {
    return { ok: false, mensagem: "Localização do aparelho inválida. Ative o GPS e tente de novo." };
  }
  if (!Array.isArray(c.itens) || c.itens.length === 0) {
    return { ok: false, mensagem: "Informe pelo menos um preço." };
  }
  if (c.itens.length > produtos.length) {
    return { ok: false, mensagem: "Há mais preços do que combustíveis existentes." };
  }

  const vistos = new Set<number>();
  const itens: ItemValido[] = [];
  for (const bruto of c.itens as unknown[]) {
    const i = (bruto ?? {}) as Record<string, unknown>;
    const produto = produtos.find((p) => p.id === i.produto_id);
    if (!produto) return { ok: false, mensagem: "Combustível desconhecido no envio." };
    if (vistos.has(produto.id)) return { ok: false, mensagem: `${produto.nome} aparece mais de uma vez.` };
    vistos.add(produto.id);
    if (!numero(i.preco)) return { ok: false, mensagem: `Preço de ${produto.nome} inválido.` };
    const preco = arred3(i.preco);
    if (preco < produto.preco_min || preco > produto.preco_max) {
      return {
        ok: false,
        mensagem: `O preço de ${produto.nome} precisa estar entre R$ ${produto.preco_min.toFixed(2)} e R$ ${
          produto.preco_max.toFixed(2)
        }.`,
      };
    }
    const lido = numero(i.preco_lido) ? arred3(i.preco_lido) : null;
    const conf = numero(i.confianca) ? Math.min(1, Math.max(0, i.confianca)) : null;
    itens.push({ produto_id: produto.id, preco, preco_lido: lido, confianca_ocr: conf });
  }

  const texto = typeof c.ocr_texto === "string" ? c.ocr_texto.slice(0, 2000) : null;
  const duracao = Number.isInteger(c.ocr_duracao_ms) ? (c.ocr_duracao_ms as number) : null;
  const versao = typeof c.app_versao === "string" ? c.app_versao.slice(0, 20) : null;

  return {
    ok: true,
    valor: {
      envio: {
        posto_id: c.posto_id as number,
        latitude: c.latitude as number,
        longitude: c.longitude as number,
        itens: c.itens as ItemRecebido[],
        ocr_texto: texto,
        ocr_duracao_ms: duracao,
        app_versao: versao,
      },
      itens,
    },
  };
}

/** Envio entra em revisão (exige mais confirmações) se destoar da referência ou se o usuário tiver baixa confiabilidade. */
export function motivoRevisao(
  preco: number,
  referencia: number | null,
  desvioMax: number,
  confiabilidade: number,
  confiabilidadeMin: number,
): string | null {
  if (confiabilidade < confiabilidadeMin) return "Usuário com baixa confiabilidade";
  if (referencia && referencia > 0) {
    const desvio = Math.abs(preco - referencia) / referencia;
    if (desvio > desvioMax) {
      return `Diferença de ${(desvio * 100).toFixed(0)}% para o preço de referência (R$ ${referencia.toFixed(2)})`;
    }
  }
  return null;
}
