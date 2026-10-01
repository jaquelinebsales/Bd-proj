// "Estou neste posto": registra a posição de quem está no posto, sem enviar preço.
// Duas pessoas diferentes a até 150 m uma da outra confirmam a posição do posto.
import { cabecalhosCors, clienteAdmin, erro, parametros, resposta, usuarioDaRequisicao } from "../_shared/comum.ts";
import { mensagemDoMotivo, validarCorpo } from "./validacao.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cabecalhosCors });
  if (req.method !== "POST") return erro(405, "Use POST.");

  try {
    const admin = clienteAdmin();
    const usuario = await usuarioDaRequisicao(req, admin);
    if (!usuario) return erro(401, "Entre na sua conta para informar a posição do posto.");
    if (!usuario.email_confirmed_at) return erro(403, "Confirme seu e-mail antes de informar a posição de um posto.");

    const { data: perfil, error: ePerfil } = await admin
      .from("perfis").select("id, banido, bloqueado_ate").eq("id", usuario.id).single();
    if (ePerfil || !perfil) return erro(403, "Perfil não encontrado.");
    if (perfil.banido) return erro(403, "Sua conta não pode informar posições.");
    if (perfil.bloqueado_ate && new Date(perfil.bloqueado_ate) > new Date()) {
      return erro(403, "Suas contribuições estão pausadas no momento.");
    }

    const par = await parametros(admin);
    const validado = validarCorpo(await req.json().catch(() => null), par.precisao_gps_max_m ?? 100);
    if (!validado.ok) return erro(422, validado.mensagem);
    const c = validado.valor;

    const { data, error } = await admin.rpc("registrar_correcao_posicao", {
      p_usuario: usuario.id, p_posto: c.posto_id, p_lat: c.latitude, p_lon: c.longitude,
    });
    if (error) throw error;
    if (!data?.ok) {
      const m = mensagemDoMotivo(String(data?.motivo ?? ""), {
        posicoes_por_dia: par.posicoes_por_dia ?? 10,
        distancia_max_correcao_km: par.distancia_max_correcao_km ?? 100,
      });
      return erro(m.status, m.mensagem);
    }

    const confirmada = data.status === "confirmada";
    return resposta(200, {
      status: data.status,
      mensagem: confirmada
        ? `Posição confirmada por ${data.usuarios} pessoas. Este posto agora aparece no mapa e aceita envio de preço. Você ganhou ${
          par.pontos_posicao ?? 5
        } pontos.`
        : "Obrigado! Quando outra pessoa que esteja neste posto também informar a posição, ela será confirmada e você ganha pontos.",
    });
  } catch (e) {
    console.error(e);
    return erro(500, "Não foi possível registrar a posição agora. Tente de novo em instantes.");
  }
});
