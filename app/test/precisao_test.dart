import 'package:flutter_test/flutter_test.dart';
import 'package:gasprice/modelos/modelos.dart';

void main() {
  test('precisão vem do texto do servidor; sem texto vale exata', () {
    expect(PrecisaoLocalizacao.deTexto('exata'), PrecisaoLocalizacao.exata);
    expect(PrecisaoLocalizacao.deTexto('rua'), PrecisaoLocalizacao.rua);
    expect(PrecisaoLocalizacao.deTexto('cep_rua'), PrecisaoLocalizacao.cepRua);
    expect(PrecisaoLocalizacao.deTexto('cep_cidade'), PrecisaoLocalizacao.cepCidade);
    expect(PrecisaoLocalizacao.deTexto('municipio'), PrecisaoLocalizacao.municipio);
    expect(PrecisaoLocalizacao.deTexto('nenhuma'), PrecisaoLocalizacao.nenhuma);
    expect(PrecisaoLocalizacao.deTexto(null), PrecisaoLocalizacao.exata);
  });

  test('o que cada precisão permite', () {
    const casos = {
      PrecisaoLocalizacao.exata: (noMapa: true, aproximada: false, raio: 300),
      PrecisaoLocalizacao.rua: (noMapa: true, aproximada: true, raio: 1000),
      PrecisaoLocalizacao.cepRua: (noMapa: true, aproximada: true, raio: 1000),
      PrecisaoLocalizacao.cepCidade: (noMapa: false, aproximada: false, raio: null),
      PrecisaoLocalizacao.municipio: (noMapa: false, aproximada: false, raio: null),
      PrecisaoLocalizacao.nenhuma: (noMapa: false, aproximada: false, raio: null),
    };
    casos.forEach((p, esperado) {
      expect(p.noMapa, esperado.noMapa, reason: '$p noMapa');
      expect(p.aproximada, esperado.aproximada, reason: '$p aproximada');
      expect(p.raioEnvioM(), esperado.raio, reason: '$p raio');
      expect(p.aceitaEnvio, esperado.raio != null, reason: '$p aceitaEnvio');
    });
  });

  test('o raio pode vir de parâmetros do servidor', () {
    expect(PrecisaoLocalizacao.rua.raioEnvioM(aproximadoM: 2000), 2000);
    expect(PrecisaoLocalizacao.exata.raioEnvioM(exataM: 250), 250);
  });

  test('posto lido do JSON carrega precisão, raio e posição informada', () {
    final d = PostoDetalhe.deJson({
      'id': 7,
      'nome': 'POSTO TESTE LTDA',
      'municipio': 'Fortaleza',
      'uf': 'CE',
      'precisao': 'rua',
      'raio_envio_m': 1000,
      'posicao_informada': true,
      'precos': [],
    });
    expect(d.resumo.precisao, PrecisaoLocalizacao.rua);
    expect(d.raioEnvioM, 1000);
    expect(d.posicaoInformada, true);
    expect(d.resumo.comDistancia(2).precisao, PrecisaoLocalizacao.rua, reason: 'a cópia com distância mantém a precisão');
  });

  test('posto sem raio no JSON (CEP da cidade) não aceita envio', () {
    final d = PostoDetalhe.deJson({
      'id': 8,
      'nome': 'POSTO B',
      'municipio': 'Itaitinga',
      'uf': 'CE',
      'precisao': 'cep_cidade',
      'raio_envio_m': null,
      'precos': [],
    });
    expect(d.raioEnvioM, isNull);
    expect(d.resumo.precisao.aceitaEnvio, false);
  });
}
