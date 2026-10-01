// Sincroniza o cadastro de postos com a API de Revendedores da ANP, uma UF por chamada.
// Chamada pelo pg_cron (cabeçalho x-cron-secret) ou manualmente com {"uf": "CE"}.
import { cabecalhosCors, clienteAdmin, erro, resposta } from "../_shared/comum.ts";
import { normalizarRegistro, PostoNormalizado, RegistroApi } from "./normalizar.ts";

const API = "https://revendedoresapi.anp.gov.br/v1/combustivel";
const UFS = [
  "AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG", "MS", "MT", "PA",
  "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR", "RS", "SC", "SE", "SP", "TO",
];
const LOTE = 1000;

async function buscarPagina(uf: string, pagina: number) {
  const url = `${API}?uf=${uf}&numeropagina=${pagina}`;
  for (let tentativa = 1; tentativa <= 3; tentativa++) {
    const r = await fetch(url, { headers: { Accept: "application/json" } });
    if (r.ok) {
      const j = await r.json();
      return {
        registros: (j.data ?? []) as RegistroApi[],
        totalPaginas: Number(j.searchPageFilter?.totalPagina ?? 1),
      };
    }
    await new Promise((ok) => setTimeout(ok, 2000 * tentativa));
  }
  throw new Error(`API da ANP indisponível para ${uf}, página ${pagina}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cabecalhosCors });

  const segredo = Deno.env.get("CRON_SECRET");
  if (!segredo || req.headers.get("x-cron-secret") !== segredo) return erro(401, "Não autorizado.");

  const admin = clienteAdmin();
  const corpo = await req.json().catch(() => ({}));
  let uf: string | undefined = typeof corpo?.uf === "string" ? corpo.uf.toUpperCase() : undefined;

  if (!uf) {
    // Próxima UF: a que está há mais tempo sem sincronizar (e não sincronizou nos últimos 6 dias)
    const { data } = await admin.from("sincronizacoes_anp").select("uf, executado_em");
    const quando = new Map((data ?? []).map((d) => [d.uf, d.executado_em ? new Date(d.executado_em).getTime() : 0]));
    const limite = Date.now() - 6 * 24 * 3600 * 1000;
    uf = UFS.filter((u) => (quando.get(u) ?? 0) < limite).sort((a, b) => (quando.get(a) ?? 0) - (quando.get(b) ?? 0))[0];
    if (!uf) return resposta(200, { mensagem: "Todas as UFs estão atualizadas." });
  }
  if (!UFS.includes(uf)) return erro(422, "UF inválida.");

  try {
    const postos: PostoNormalizado[] = [];
    const primeira = await buscarPagina(uf, 1);
    const paginas = [primeira];
    for (let p = 2; p <= primeira.totalPaginas; p++) paginas.push(await buscarPagina(uf, p));
    for (const pg of paginas) {
      for (const r of pg.registros) {
        const n = normalizarRegistro(r);
        if (n) postos.push(n);
      }
    }
    if (postos.length === 0) throw new Error(`A API não retornou postos para ${uf}`);

    let total = 0;
    for (let i = 0; i < postos.length; i += LOTE) {
      const lote = postos.slice(i, i + LOTE);
      const ultimo = i + LOTE >= postos.length;
      const { data, error } = await admin.rpc("importar_postos_anp", {
        p_uf: uf, p_registros: lote, p_completo: ultimo,
      });
      if (error) throw error;
      total += Number(data ?? 0);
    }
    return resposta(200, { uf, postos: total, sem_coordenada: postos.filter((p) => p.lat === null).length });
  } catch (e) {
    console.error(e);
    await admin.from("sincronizacoes_anp").upsert({ uf, erro: String(e).slice(0, 500) });
    return erro(502, `Falha ao sincronizar ${uf}.`, String(e));
  }
});
