import { assertEquals } from "jsr:@std/assert@1";
import { mensagemDoMotivo, validarCorpo } from "./validacao.ts";

const ok = { posto_id: 5, latitude: -3.76, longitude: -38.54, precisao_gps_m: 12 };

Deno.test("aceita posição válida com GPS preciso", () => {
  const r = validarCorpo(ok, 100);
  assertEquals(r.ok, true);
});

Deno.test("recusa GPS impreciso", () => {
  const r = validarCorpo({ ...ok, precisao_gps_m: 450 }, 100);
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.mensagem.includes("impreciso"), true);
});

Deno.test("recusa quando a precisão do GPS não foi enviada", () => {
  assertEquals(validarCorpo({ ...ok, precisao_gps_m: null }, 100).ok, false);
  assertEquals(validarCorpo({ ...ok, precisao_gps_m: 0 }, 100).ok, false);
});

Deno.test("recusa posição fora do Brasil", () => {
  assertEquals(validarCorpo({ ...ok, latitude: 40.7, longitude: -74.0 }, 100).ok, false);
});

Deno.test("recusa posto ausente e corpo inválido", () => {
  assertEquals(validarCorpo({ ...ok, posto_id: 0 }, 100).ok, false);
  assertEquals(validarCorpo(null, 100).ok, false);
});

Deno.test("mensagens dos motivos do banco", () => {
  const par = { posicoes_por_dia: 10, distancia_max_correcao_km: 100 };
  assertEquals(mensagemDoMotivo("limite_diario", par).status, 429);
  assertEquals(mensagemDoMotivo("posicao_confirmada", par).status, 409);
  assertEquals(mensagemDoMotivo("longe_do_posto", par).mensagem.includes("100 km"), true);
  assertEquals(mensagemDoMotivo("qualquer", par).status, 422);
});
