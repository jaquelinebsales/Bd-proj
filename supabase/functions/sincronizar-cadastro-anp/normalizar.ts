// Converte um registro da API de Revendedores da ANP para o formato de importar_postos_anp.

export interface ProdutoApi {
  produto?: string;
  qtdeBicos?: number;
}

export interface RegistroApi {
  cnpj?: string;
  razaoSocial?: string;
  autorizacao?: string;
  endereco?: string;
  complemento?: string;
  bairro?: string;
  cep?: string;
  municipio?: string;
  distribuidora?: string;
  latitude?: string | number | null;
  longitude?: string | number | null;
  validacao?: string | null;
  produtos?: ProdutoApi[];
}

export interface PostoNormalizado {
  cnpj: string;
  razao_social: string;
  bandeira: string | null;
  endereco: string | null;
  complemento: string | null;
  bairro: string | null;
  municipio: string;
  cep: string | null;
  lat: number | null;
  lon: number | null;
  validada: boolean;
  autorizacao: string | null;
  produtos: { produto_id: number; bicos: number }[];
}

const semAcento = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase();
const limpar = (s?: string | null) => {
  const t = (s ?? "").replace(/\s+/g, " ").trim();
  return t.length ? t : null;
};

/** Mapeia o nome do produto da ANP para o id da tabela produtos. Produtos fora do catálogo retornam null. */
export function produtoId(nome: string): number | null {
  const n = semAcento(nome);
  if (n.includes("GNV") || n.includes("GAS NATURAL")) return 6;
  if (n.includes("GASOLINA")) {
    if (n.includes("PREMIUM") || n.includes("FORMULADA") || n.includes("AVIACAO")) return null;
    return n.includes("ADITIVADA") ? 2 : 1;
  }
  if (n.includes("ETANOL")) return 3;
  if (n.includes("DIESEL")) {
    if (n.includes("S10")) return 5;
    if (n.includes("S500") || n.includes("S-500")) return 4;
    return null;
  }
  return null;
}

function coordenada(v: string | number | null | undefined): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = typeof v === "number" ? v : Number(String(v).replace(",", "."));
  return Number.isFinite(n) ? n : null;
}

export function normalizarRegistro(r: RegistroApi): PostoNormalizado | null {
  const cnpj = (r.cnpj ?? "").replace(/\D/g, "").padStart(14, "0");
  const razao = limpar(r.razaoSocial);
  const municipio = limpar(r.municipio);
  if (cnpj.length !== 14 || /^0+$/.test(cnpj) || !razao || !municipio) return null;

  let lat = coordenada(r.latitude);
  let lon = coordenada(r.longitude);
  // Só aceita coordenadas dentro do território brasileiro
  if (lat === null || lon === null || lat < -34 || lat > 5.5 || lon < -74.5 || lon > -28.5 || (lat === 0 && lon === 0)) {
    lat = null;
    lon = null;
  }
  const validacao = semAcento(r.validacao ?? "");
  const validada = lat !== null && validacao.includes("VALIDADA") && !validacao.includes("NAO VALIDADA");

  const somados = new Map<number, number>();
  for (const p of r.produtos ?? []) {
    const id = produtoId(p.produto ?? "");
    if (id === null) continue;
    somados.set(id, (somados.get(id) ?? 0) + (Number(p.qtdeBicos) || 0));
  }

  const cep = (r.cep ?? "").replace(/\D/g, "");
  const bandeira = limpar(r.distribuidora);

  return {
    cnpj,
    razao_social: razao,
    bandeira: bandeira && semAcento(bandeira) !== "BANDEIRA BRANCA" ? bandeira : "Bandeira branca",
    endereco: limpar(r.endereco),
    complemento: limpar(r.complemento),
    bairro: limpar(r.bairro),
    municipio,
    cep: cep.length === 8 ? cep : null,
    lat,
    lon,
    validada,
    autorizacao: limpar(r.autorizacao),
    produtos: [...somados].map(([produto_id, bicos]) => ({ produto_id, bicos })),
  };
}
