import 'package:flutter_test/flutter_test.dart';
import 'package:gasprice/modelos/modelos.dart';
import 'package:gasprice/servicos/filtros.dart';

final agora = DateTime(2026, 9, 29, 12);

PostoResumo posto(int id, {double? preco, double? km, double? nota, Duration idade = Duration.zero, FontePreco fonte = FontePreco.comunidade}) =>
    PostoResumo(
      id: id,
      nome: 'Posto $id',
      municipio: 'Fortaleza',
      uf: 'CE',
      notaMedia: nota,
      distanciaKm: km,
      precos: preco == null
          ? const []
          : [
              PrecoAtual(
                produtoId: 1,
                preco: preco,
                fonte: fonte,
                situacao: SituacaoPreco.confirmado,
                atualizadoEm: agora.subtract(idade),
              ),
            ],
    );

void main() {
  final lista = [
    posto(1, preco: 6.19, km: 2, nota: 4.5, idade: const Duration(days: 3)),
    posto(2, preco: 5.99, km: 5, nota: 3.0, idade: const Duration(hours: 2)),
    posto(3, km: 1, nota: 5),
    posto(4, preco: 6.49, km: 12, idade: const Duration(days: 40), fonte: FontePreco.estimativa),
  ];

  test('menor preço deixa postos sem preço no fim', () {
    final r = aplicarFiltros(lista, const Filtros(ordenacao: Ordenacao.menorPreco), agora: agora);
    expect(r.map((p) => p.id), [2, 1, 4, 3]);
  });

  test('mais próximos', () {
    final r = aplicarFiltros(lista, const Filtros(), agora: agora);
    expect(r.map((p) => p.id), [3, 1, 2, 4]);
  });

  test('faixa de preço exclui postos sem preço', () {
    final r = aplicarFiltros(lista, const Filtros(precoMin: 6.0, precoMax: 6.3), agora: agora);
    expect(r.map((p) => p.id), [1]);
  });

  test('distância e avaliação mínima', () {
    final r = aplicarFiltros(lista, const Filtros(distanciaMaxKm: 5, avaliacaoMinima: 4), agora: agora);
    expect(r.map((p) => p.id), [3, 1]);
  });

  test('período da atualização ignora estimativas', () {
    final r = aplicarFiltros(lista, const Filtros(periodo: PeriodoAtualizacao.ultimos7dias), agora: agora);
    expect(r.map((p) => p.id), [1, 2]);
  });

  test('só favoritos', () {
    final r = aplicarFiltros(lista, const Filtros(soFavoritos: true), favoritos: {2, 4}, agora: agora);
    expect(r.map((p) => p.id), [2, 4]);
  });

  test('frescor segue a regra de 24 h e 7 dias', () {
    PrecoAtual p(Duration d) => PrecoAtual(
        produtoId: 1, preco: 6, fonte: FontePreco.comunidade, situacao: SituacaoPreco.confirmado, atualizadoEm: agora.subtract(d));
    expect(p(const Duration(hours: 5)).frescor(agora), Frescor.recente);
    expect(p(const Duration(days: 3)).frescor(agora), Frescor.antigo);
    expect(p(const Duration(days: 9)).frescor(agora), Frescor.semAtualizacao);
  });

  test('nome de exibição remove sufixos societários', () {
    expect(nomeExibicao('AUTO POSTO SAKAMOTO LTDA'), 'Auto Posto Sakamoto');
    expect(nomeExibicao('POSTO DE COMBUSTIVEIS DO ZE EIRELI'), 'Posto de Combustiveis do Ze');
  });
}
