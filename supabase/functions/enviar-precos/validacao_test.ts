import { assertEquals } from "jsr:@std/assert@1";
import { motivoRevisao, validarCorpo } from "./validacao.ts";

const produtos = [
  { id: 1, nome: "Gasolina comum", preco_min: 2, preco_max: 15 },
  { id: 3, nome: "Etanol", preco_min: 1.5, preco_max: 12 },
];

Deno.test("aceita envio válido e arredonda para 3 casas", () => {
  const r = validarCorpo({
    posto_id: 10, latitude: -3.8, longitude: -38.5,
    itens: [{ produto_id: 1, preco: 5.98999, preco_lido: 5.99, confianca: 0.9 }],
  }, produtos);
  assertEquals(r.ok, true);
  if (r.ok) {
    assertEquals(r.valor.itens[0].preco, 5.99);
    assertEquals(r.valor.itens[0].preco_lido, 5.99);
  }
});

Deno.test("recusa preço fora da faixa", () => {
  const r = validarCorpo({ posto_id: 1, latitude: 0, longitude: 0, itens: [{ produto_id: 3, preco: 59.9 }] }, produtos);
  assertEquals(r.ok, false);
});

Deno.test("recusa combustível repetido", () => {
  const r = validarCorpo({
    posto_id: 1, latitude: 0, longitude: 0,
    itens: [{ produto_id: 1, preco: 6 }, { produto_id: 1, preco: 6.1 }],
  }, produtos);
  assertEquals(r.ok, false);
});

Deno.test("recusa sem localização", () => {
  const r = validarCorpo({ posto_id: 1, itens: [{ produto_id: 1, preco: 6 }] }, produtos);
  assertEquals(r.ok, false);
});

Deno.test("marca revisão quando desvia mais de 20% da referência", () => {
  assertEquals(motivoRevisao(7.5, 6.0, 0.2, 0.5, 0.2) !== null, true);
  assertEquals(motivoRevisao(6.5, 6.0, 0.2, 0.5, 0.2), null);
  assertEquals(motivoRevisao(6.0, null, 0.2, 0.5, 0.2), null);
});

Deno.test("marca revisão para usuário com baixa confiabilidade", () => {
  assertEquals(motivoRevisao(6.0, 6.0, 0.2, 0.1, 0.2), "Usuário com baixa confiabilidade");
});
