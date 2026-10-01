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
        'A localização deste posto ainda não é conhecida. Se você está nele, toque em "Estou neste posto" para ajudar a localizá-lo. Depois disso o envio de preço fica liberado.',
      );
    }
    if (alvo.distancia_m > raio) {
      const km = raio >= 1000 ? `${raio / 1000} km` : `${raio} m`;
      return erro(422, `Você precisa estar a até ${km} do posto para enviar preços. Distância atual: ${
        Math.round(alvo.distancia_m)
      } m.${raio > 300 ? " A localização deste posto é aproximada." : ""}`);
    }

    // Limite diário de envios
    const desde24h = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    const { count: enviosDia } = await admin.from("envios")
      .select("id", { count: "exact", head: true }).eq("usuario_id", usuario.id).gte("criado_em", desde24h);
    if ((enviosDia ?? 0) >= par.envios_por_dia) {
      return erro(429, `Você atingiu o limite de ${par.envios_por_dia} envios em 24 horas. Tente mais tarde.`);
    }

    // Mesmo posto e combustível: um envio a cada 6 h por usuário
    const desdeIntervalo = new Date(Date.now() - par.intervalo_mesmo_item_h * 3600 * 1000).toISOString();
    const { data: recentes } = await admin.from("envio_itens").select("produto_id")
      .eq("usuario_id", usuario.id).eq("posto_id", envio.posto_id).gte("criado_em", desdeIntervalo);
    const repetidos = new Set((recentes ?? []).map((r) => r.produto_id));
    const aceitos = itens.filter((i) => !repetidos.has(i.produto_id));
    if (aceitos.length === 0) {
      return erro(429, `Você já enviou esses preços para este posto nas últimas ${par.intervalo_mesmo_item_h} horas.`);
    }

    // Referência para detectar envio suspeito
    const { data: atuais } = await admin.from("precos_atuais").select("produto_id, preco, fonte")
      .eq("posto_id", envio.posto_id);
    const referencia = new Map((atuais ?? []).map((a) => [a.produto_id, Number(a.preco)]));

    const { data: novoEnvio, error: eEnvio } = await admin.from("envios").insert({
      usuario_id: usuario.id,
      posto_id: envio.posto_id,
      posicao: `SRID=4326;POINT(${envio.longitude} ${envio.latitude})`,
      distancia_m: Math.round(alvo.distancia_m),
      ocr_texto: envio.ocr_texto,
      ocr_duracao_ms: envio.ocr_duracao_ms,
      app_versao: envio.app_versao,
    }).select("id").single();
    if (eEnvio) throw eEnvio;

    const linhas = aceitos.map((i) => {
      const motivo = motivoRevisao(
        i.preco, referencia.get(i.produto_id) ?? null, par.desvio_revisao,
        Number(perfil.confiabilidade), par.confiabilidade_min,
      );
      return {
        envio_id: novoEnvio.id,
        posto_id: envio.posto_id,
        produto_id: i.produto_id,
        usuario_id: usuario.id,
        preco: i.preco,
        preco_lido: i.preco_lido,
        confianca_ocr: i.confianca_ocr,
        em_revisao: motivo !== null,
        motivo_revisao: motivo,
      };
    });
    const { data: inseridos, error: eItens } = await admin.from("envio_itens").insert(linhas).select("id, produto_id");
    if (eItens) throw eItens;

    for (const i of aceitos) {
      const { error: eCons } = await admin.rpc("consolidar_preco", { p_posto: envio.posto_id, p_produto: i.produto_id });
      if (eCons) throw eCons;
    }

    const ids = (inseridos ?? []).map((i) => i.id);
    const { data: finais } = await admin.from("envio_itens")
      .select("id, produto_id, preco, status, em_revisao, motivo_revisao").in("id", ids);

    const confirmados = (finais ?? []).filter((f) => f.status === "confirmado").length;
    return resposta(200, {
      envio_id: novoEnvio.id,
      itens: finais,
      ignorados: itens.filter((i) => repetidos.has(i.produto_id)).map((i) => i.produto_id),
      mensagem: confirmados > 0
        ? `${confirmados} preço(s) confirmado(s) com outros usuários. Seus pontos já foram creditados.`
        : "Preços recebidos. Você ganha pontos quando outra pessoa confirmar o mesmo valor em até 24 horas.",
    });
  } catch (e) {
    console.error(e);
    return erro(500, "Não foi possível registrar o envio agora. Tente de novo em instantes.");
  }
});
