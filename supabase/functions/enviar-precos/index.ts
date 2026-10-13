// Recebe os preços lidos da foto do painel (a foto fica no celular) e registra
// uma proposta de atualização. Toda validação é repetida aqui no servidor.
import { cabecalhosCors, clienteAdmin, erro, parametros, resposta, usuarioDaRequisicao } from "../_shared/comum.ts";
import { motivoRevisao, Produto, raioParaPrecisao, validarCorpo } from "./validacao.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cabecalhosCors });
  if (req.method !== "POST") return erro(405, "Use POST.");

  try {
    const admin = clienteAdmin();
    const usuario = await usuarioDaRequisicao(req, admin);
    if (!usuario) return erro(401, "Entre na sua conta para enviar preços.");
    if (!usuario.email_confirmed_at) return erro(403, "Confirme seu e-mail antes de enviar preços.");

    const { data: perfil, error: ePerfil } = await admin
      .from("perfis").select("id, banido, bloqueado_ate, confiabilidade").eq("id", usuario.id).single();
    if (ePerfil || !perfil) return erro(403, "Perfil não encontrado.");
    if (perfil.banido) return erro(403, "Sua conta não pode enviar preços.");
    if (perfil.bloqueado_ate && new Date(perfil.bloqueado_ate) > new Date()) {
      const ate = new Date(perfil.bloqueado_ate).toLocaleDateString("pt-BR");
      return erro(403, `Seus envios estão pausados até ${ate} porque vários preços foram contrariados por outros usuários.`);
    }

    const { data: produtos, error: eProd } = await admin.from("produtos").select("id, nome, preco_min, preco_max");
    if (eProd) throw eProd;
    const prods: Produto[] = (produtos ?? []).map((p) => ({
      id: p.id, nome: p.nome, preco_min: Number(p.preco_min), preco_max: Number(p.preco_max),
    }));

    const validado = validarCorpo(await req.json().catch(() => null), prods);
    if (!validado.ok) return erro(422, validado.mensagem);
    const { envio, itens } = validado.valor;
    const par = await parametros(admin);

    // Distância até o posto e precisão da posição dele
    const { data: dadosAlvo, error: eDist } = await admin.rpc("distancia_e_precisao", {
      p_posto: envio.posto_id, p_lat: envio.latitude, p_lon: envio.longitude,
    });
    if (eDist) throw eDist;
    const alvo = Array.isArray(dadosAlvo) ? dadosAlvo[0] : dadosAlvo;
    if (!alvo) return erro(404, "Posto não encontrado.");
    const raio = raioParaPrecisao(alvo.precisao, par as { raio_envio_m: number; raio_envio_aproximado_m: number });
    if (raio === null || alvo.distancia_m === null) {
      return erro(
        422,
        'Para enviar preços deste posto, toque em "Estou neste posto" quando estiver nele. Depois disso o envio fica liberado.',
      );
    }
    if (alvo.distancia_m > raio) {
      const km = raio >= 1000 ? `${raio / 1000} km` : `${raio} m`;
      return erro(422, `Você precisa estar a até ${km} do posto para enviar preços. Distância atual: ${
        Math.round(alvo.distancia_m)
      } m.`);
    }

    // Referência para detectar envio suspeito
    const { data: atuais } = await admin.from("precos_atuais").select("produto_id, preco, fonte")
      .eq("posto_id", envio.posto_id);
    const referencia = new Map((atuais ?? []).map((a) => [a.produto_id, Number(a.preco)]));
    const linhas = itens.map((i) => {
      const motivo = motivoRevisao(
        i.preco, referencia.get(i.produto_id) ?? null, par.desvio_revisao,
        Number(perfil.confiabilidade), par.confiabilidade_min,
      );
      return { ...i, em_revisao: motivo !== null, motivo_revisao: motivo };
    });

    // Limites, gravação e consenso numa só transação no banco, um envio por vez para cada usuário:
    // requisições simultâneas não furam o limite diário nem a regra de 6 h.
    const { data: r, error: eReg } = await admin.rpc("registrar_envio", {
      p_usuario: usuario.id,
      p_posto: envio.posto_id,
      p_lat: envio.latitude,
      p_lon: envio.longitude,
      p_distancia_m: Math.round(alvo.distancia_m),
      p_itens: linhas,
      p_ocr_texto: envio.ocr_texto,
      p_ocr_duracao_ms: envio.ocr_duracao_ms,
      p_app_versao: envio.app_versao,
    });
    if (eReg) throw eReg;
    if (!r?.ok) {
      return r?.motivo === "limite_diario"
        ? erro(429, `Você atingiu o limite de ${par.envios_por_dia} envios em 24 horas. Tente mais tarde.`)
        : erro(429, `Você já enviou esses preços para este posto nas últimas ${par.intervalo_mesmo_item_h} horas.`);
    }

    const finais = (r.itens ?? []) as { status: string }[];
    const confirmados = finais.filter((f) => f.status === "confirmado").length;
    return resposta(200, {
      envio_id: r.envio_id,
      itens: finais,
      ignorados: r.ignorados ?? [],
      mensagem: confirmados > 0
        ? `${confirmados} preço(s) confirmado(s) com outros usuários. Seus pontos já foram creditados.`
        : "Preços recebidos. Você ganha pontos quando outra pessoa confirmar o mesmo valor em até 24 horas.",
    });
  } catch (e) {
    console.error(e);
    return erro(500, "Não foi possível registrar o envio agora. Tente de novo em instantes.");
  }
});
