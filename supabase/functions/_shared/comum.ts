import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

export const cabecalhosCors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function resposta(status: number, corpo: unknown): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...cabecalhosCors, "Content-Type": "application/json; charset=utf-8" },
  });
}

export function erro(status: number, mensagem: string, detalhes?: unknown): Response {
  return resposta(status, { erro: mensagem, detalhes });
}

function variavel(...nomes: string[]): string {
  for (const n of nomes) {
    const v = Deno.env.get(n);
    if (v) return v;
  }
  throw new Error(`Variável de ambiente ausente: ${nomes.join(" ou ")}`);
}

/**
 * Chave de servidor. Projetos novos do Supabase usam chaves secretas (sb_secret_...),
 * expostas às Edge Functions em SUPABASE_SECRET_KEYS (JSON). Projetos antigos usam
 * a service_role em SUPABASE_SERVICE_ROLE_KEY. Aceita os dois formatos.
 */
export function chaveServidor(): string {
  const legado = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legado) return legado;
  const novas = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (novas) {
    try {
      const mapa = JSON.parse(novas) as Record<string, unknown>;
      const valor = mapa["default"] ?? Object.values(mapa)[0];
      if (typeof valor === "string" && valor) return valor;
    } catch {
      // formato inesperado: tenta a variável manual abaixo
    }
  }
  return variavel("GASPRICE_SECRET_KEY");
}

/**
 * Schema das tabelas do app: public no Supabase da nuvem; no servidor próprio cada sistema tem o seu
 * (combustivel), informado em GASPRICE_SCHEMA.
 */
export function schemaDoApp(): string {
  const s = Deno.env.get("GASPRICE_SCHEMA") || "public";
  if (!/^[a-z_][a-z0-9_]*$/.test(s)) throw new Error(`GASPRICE_SCHEMA inválido: ${s}`);
  return s;
}

/** Cliente com privilégio de servidor. Nunca expor ao app. */
export function clienteAdmin(): SupabaseClient {
  // O schema só é conhecido em tempo de execução; o tipo genérico do cliente fica como o de antes
  return createClient(variavel("SUPABASE_URL"), chaveServidor(), {
    auth: { persistSession: false, autoRefreshToken: false },
    db: { schema: schemaDoApp() },
  }) as unknown as SupabaseClient;
}

/** Usuário dono do token enviado pelo app, ou null. */
export async function usuarioDaRequisicao(req: Request, admin: SupabaseClient) {
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data?.user) return null;
  return data.user;
}

export async function parametros(admin: SupabaseClient): Promise<Record<string, number>> {
  const { data, error } = await admin.from("parametros").select("chave, valor");
  if (error) throw error;
  return Object.fromEntries((data ?? []).map((p) => [p.chave, Number(p.valor)]));
}
