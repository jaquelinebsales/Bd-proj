// Exclui a conta do usuário logado (LGPD). Avaliações, favoritos, pontos e perfil são apagados.
// Os preços enviados continuam no histórico, sem vínculo com a pessoa.
import { cabecalhosCors, clienteAdmin, erro, resposta, usuarioDaRequisicao } from "../_shared/comum.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cabecalhosCors });
  if (req.method !== "POST") return erro(405, "Use POST.");

  const admin = clienteAdmin();
  const usuario = await usuarioDaRequisicao(req, admin);
  if (!usuario) return erro(401, "Entre na sua conta para excluí-la.");

  const { data: arquivos } = await admin.storage.from("avatares").list(usuario.id);
  if (arquivos && arquivos.length > 0) {
    await admin.storage.from("avatares").remove(arquivos.map((a) => `${usuario.id}/${a.name}`));
  }

  const { error } = await admin.auth.admin.deleteUser(usuario.id);
  if (error) {
    console.error(error);
    return erro(500, "Não foi possível excluir a conta agora. Tente de novo em instantes.");
  }
  return resposta(200, { mensagem: "Conta excluída." });
});
