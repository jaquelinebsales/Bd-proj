import 'package:flutter_test/flutter_test.dart';
import 'package:gasprice/servicos/parser_painel.dart';

LinhaTexto l(String t, double x, double y, {double w = 200, double h = 40}) =>
    LinhaTexto(t, esquerda: x, topo: y, direita: x + w, base: y + h);

void main() {
  test('rótulo e preço na mesma linha', () {
    final r = interpretarPainel([
      l('GASOLINA COMUM 5,99 9', 0, 0, w: 500),
      l('ETANOL 4,29', 0, 60, w: 400),
      l('DIESEL S-10 6,32', 0, 120, w: 400),
    ]);
    expect(r.de(1)!.preco, 5.999);
    expect(r.de(3)!.preco, 4.29);
    expect(r.de(5)!.preco, 6.32);
    expect(r.de(4), isNull);
  });

  test('rótulos e preços em colunas separadas', () {
    final r = interpretarPainel([
      l('GASOLINA', 0, 0),
      l('ADITIVADA', 0, 60),
      l('ETANOL', 0, 120),
      l('5.89', 400, 2, w: 120),
      l('6.09', 400, 62, w: 120),
      l('3.99', 400, 121, w: 120),
    ]);
    expect(r.de(1)!.preco, 5.89);
    expect(r.de(2)!.preco, 6.09);
    expect(r.de(3)!.preco, 3.99);
  });

  test('painel de LED sem separador decimal', () {
    final r = interpretarPainel([l('GNV', 0, 0, w: 100), l('479', 300, 0, w: 100)]);
    expect(r.de(6)!.preco, 4.79);
    expect(r.de(6)!.confianca, lessThan(0.9));
  });

  test('corrige letra O lida no lugar de zero', () {
    final r = interpretarPainel([l('ETANOL 4,1O', 0, 0, w: 300)]);
    expect(r.de(3)!.preco, 4.10);
  });

  test('ignora valores fora da faixa de combustível', () {
    final r = interpretarPainel([l('GASOLINA 59,90', 0, 0, w: 300)]);
    expect(r.de(1), isNull);
  });

  test('preço sem rótulo vira sugestão', () {
    final r = interpretarPainel([l('BEM-VINDO', 0, 0), l('6,19', 0, 300, w: 100)]);
    expect(r.leituras, isEmpty);
    expect(r.precosSemRotulo, [6.19]);
  });

  test('identifica os combustíveis pelos nomes usuais', () {
    expect(produtoDoTexto('Álcool'), 3);
    expect(produtoDoTexto('Diesel S500'), 4);
    expect(produtoDoTexto('DIESEL S10 ADITIVADO'), 5);
    expect(produtoDoTexto('Gasolina Aditivada'), 2);
    expect(produtoDoTexto('Gás Natural'), 6);
    expect(produtoDoTexto('Bem-vindo'), isNull);
  });
}
