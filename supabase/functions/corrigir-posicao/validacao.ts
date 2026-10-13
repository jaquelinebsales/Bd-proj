// Validação pura do corpo de "Estou neste posto". Sem rede nem banco, para ser testável.

export interface CorpoPosicao {
  posto_id: number;
  latitude: number;
  longitude: number;
  precisao_gps_m: number | null;
}

export type Resultado<T> = { ok: true; valor: T } | { ok: false; mensagem: string };

const numero = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);

export function validarCorpo(corpo: unknown, precisaoMaxima: number): Resultado<CorpoPosicao> {
  if (!corpo || typeof corpo !== "object") return { ok: false, mensagem: "Corpo da requisição inválido." };
  const c = corpo as Record<string, unknown>;
  if (!Number.isInteger(c.posto_id) || (c.posto_id as number) <= 0) return { ok: false, mensagem: "Posto não informado." };
  if (!numero(c.latitude) || !numero(c.longitude) || Math.abs(c.latitude) > 90 || Math.abs(c.longitude) > 180) {
    return { ok: false, mensagem: "Localização do aparelho inválida. Ative o GPS e tente de novo." };
  }
  // Dentro do Brasil, com folga para as ilhas
  if (c.latitude < -34 || c.latitude > 5.5 || c.longitude < -74.5 || c.longitude > -28.5) {
    return { ok: false, mensagem: "A localização está fora do Brasil." };
  }
  const gps = numero(c.precisao_gps_m) ? c.precisao_gps_m : null;
  if (gps === null || gps <= 0) {
    return { ok: false, mensagem: "Não consegui medir a precisão do GPS. Abra o app ao ar livre e tente de novo." };
  }
  if (gps > precisaoMaxima) {
    return {
      ok: false,
      mensagem: `O GPS está impreciso (${Math.round(gps)} m). Aguarde alguns segundos, de preferência ao ar livre, e tente de novo.`,
    };
  }
  return {
    ok: true,
    valor: { posto_id: c.posto_id as number, latitude: c.latitude, longitude: c.longitude, precisao_gps_m: gps },
  };
}

/** Traduz o motivo devolvido pelo banco em mensagem para o usuário e código HTTP. */
export function mensagemDoMotivo(motivo: string, par: { posicoes_por_dia: number; distancia_max_correcao_km: number }): {
  status: number;
  mensagem: string;
} {
  switch (motivo) {
    case "posto_inexistente":
      return { status: 404, mensagem: "Posto não encontrado." };
    case "posicao_confirmada":
      return { status: 409, mensagem: "A posição deste posto já está confirmada. Obrigado!" };
    case "limite_diario":
      return { status: 429, mensagem: `Você já informou ${par.posicoes_por_dia} posições nas últimas 24 horas. Tente amanhã.` };
    case "longe_do_posto":
      return {
        status: 422,
        mensagem: `A sua localização está a mais de ${par.distancia_max_correcao_km} km da posição deste posto. Confira se você está no posto certo.`,
      };
    default:
      return { status: 422, mensagem: "Não foi possível registrar a posição." };
  }
}
