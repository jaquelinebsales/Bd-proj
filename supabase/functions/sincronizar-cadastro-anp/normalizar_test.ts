import { assertEquals } from "jsr:@std/assert@1";
import { normalizarRegistro, produtoId } from "./normalizar.ts";

// Registro real devolvido pela API em 29/09/2026 (Auto Posto Camila, Brasiléia/AC)
const real = {
  codigoSIMP: "1038690", autorizacao: "PR/AC0167611", razaoSocial: "AUTO POSTO CAMILA LTDA",
  cnpj: "05938540000134", endereco: "AVENIDA JOSE RUI LINO,  500", complemento: "", bairro: "RAIMUNDO CHAAR",
  cep: "69932000", uf: "AC", municipio: "BRASILEIA", distribuidora: "VIBRA",
  produtos: [
    { produto: "ETANOL HIDRATADO COMUM", tancagem: 15, qtdeBicos: 2 },
    { produto: "GASOLINA C COMUM", tancagem: 15, qtdeBicos: 4 },
    { produto: "GASOLINA C COMUM ADITIVADA", tancagem: 15, qtdeBicos: 2 },
    { produto: "ÓLEO DIESEL B S10 - ADITIVADO", tancagem: 15, qtdeBicos: 1 },
    { produto: "ÓLEO DIESEL B S10 - COMUM", tancagem: 30, qtdeBicos: 3 },
    { produto: "ÓLEO DIESEL B S500 - ADITIVADO", tancagem: 15, qtdeBicos: 6 },
  ],
  latitude: "-11.01242728", longitude: "-68.74156143", validacao: "Posição Geográfica não validada",
};

Deno.test("normaliza registro real da API", () => {
  const n = normalizarRegistro(real)!;
  assertEquals(n.cnpj, "05938540000134");
  assertEquals(n.endereco, "AVENIDA JOSE RUI LINO, 500");
  assertEquals(n.complemento, null);
  assertEquals(n.lat, -11.01242728);
  assertEquals(n.validada, false);
  const bicos = Object.fromEntries(n.produtos.map((p) => [p.produto_id, p.bicos]));
  assertEquals(bicos, { 1: 4, 2: 2, 3: 2, 4: 6, 5: 4 });
});

Deno.test("descarta coordenada fora do Brasil", () => {
  const n = normalizarRegistro({ ...real, latitude: "0", longitude: "0" })!;
  assertEquals(n.lat, null);
  assertEquals(n.lon, null);
});

Deno.test("mapeia nomes de produto", () => {
  assertEquals(produtoId("GÁS NATURAL VEICULAR"), 6);
  assertEquals(produtoId("GASOLINA C PREMIUM"), null);
  assertEquals(produtoId("ETANOL HIDRATADO ADITIVADO"), 3);
  assertEquals(produtoId("ÓLEO DIESEL B S500 - COMUM"), 4);
});

Deno.test("recusa registro sem CNPJ", () => {
  assertEquals(normalizarRegistro({ ...real, cnpj: "" }), null);
});
