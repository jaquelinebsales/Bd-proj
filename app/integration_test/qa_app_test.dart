// QA do app no Android (emulador ou celular), tela por tela e botão por botão, contra o servidor real.
// Roda pelo testes_android/executar.py, que cria a conta de teste, concede as permissões, tira as capturas
// e grava o resultado na planilha da auditoria. Não envia preço nem posição de posto: esses dados ficariam
// no histórico real mesmo depois de apagar a conta. A avaliação de teste é publicada e apagada pelo próprio app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:gasprice/main.dart' as app;
import 'package:gasprice/servicos/preferencias.dart';
import 'package:gasprice/widgets/comuns.dart';
import 'package:gasprice/widgets/seletor_produto.dart';
import 'package:gasprice/widgets/seletor_raio.dart';

import 'qa_apoio.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('QA completo do app', timeout: const Timeout(Duration(minutes: 40)), (t) async {
    final qa = Qa(t);
    if (qaEmail.isEmpty || qaSenha.isEmpty || qaSenhaNova.isEmpty) {
      fail('Rode pelo testes_android/executar.py: faltam QA_EMAIL, QA_SENHA e QA_SENHA_NOVA.');
    }
    await qa.adb('conceder_permissoes');
    await app.main();

    await _boasVindas(qa);
    await _navegacao(qa);
    await _mapa(qa);
    final postoId = await _busca(qa);
    await _postoVisitante(qa, postoId);
    await _favoritosVisitante(qa);
    await _cadastro(qa);
    await _entrar(qa);
    await _perfil(qa);
    await _postoLogado(qa, postoId);
    await _favoritosLogado(qa);
    await _sairEEntrarDeNovo(qa);
    await _excluirConta(qa);

    // ignore: avoid_print
    print('QA_FIM:${qa.falhas}');
  });
}

// ------------------------------------------------------------------ boas-vindas e navegação
Future<void> _boasVindas(Qa qa) async {
  await qa.caso(
    modulo: 'Boas-vindas',
    tela: 'Boas-vindas',
    tipo: 'Instalação · primeira abertura',
    cenario: 'App instalado do zero abre a tela de boas-vindas',
    passos: 'Instalar o APK; abrir o app',
    esperado: 'Primeira página "Preço de combustível perto de você" com os botões Pular e Continuar',
    severidade: critica,
    corpo: () async {
      await qa.esperar(find.text('Preço de combustível perto de você'), limite: const Duration(seconds: 40));
      confirmar(qa.existe(find.text('Pular')), 'Botão Pular não apareceu');
      return 'Boas-vindas na primeira página, com Pular e Continuar';
    },
  );
  await qa.caso(
    modulo: 'Boas-vindas',
    tela: 'Boas-vindas',
    tipo: 'Funcional · botão',
    cenario: 'Continuar passa pelas três páginas',
    passos: 'Tocar em Continuar duas vezes',
    esperado: 'Páginas "Uma foto atualiza para todos" e "Você sabe de onde vem cada preço"; o botão vira "Permitir localização e começar"',
    corpo: () async {
      await qa.tocar(find.widgetWithText(FilledButton, 'Continuar'));
      await qa.esperar(find.text('Uma foto atualiza para todos'));
      await qa.tocar(find.widgetWithText(FilledButton, 'Continuar'));
      await qa.esperar(find.text('Você sabe de onde vem cada preço'));
      await qa.esperar(find.widgetWithText(FilledButton, 'Permitir localização e começar'));
      return 'As três páginas aparecem na ordem';
    },
  );
  await qa.caso(
    modulo: 'Boas-vindas',
    tela: 'Boas-vindas → Mapa',
    tipo: 'Permissão · localização',
    cenario: 'Permitir localização e começar abre o mapa na posição do aparelho',
    precondicoes: 'Localização concedida (executar.py); GPS do emulador em São Paulo',
    passos: 'Tocar em "Permitir localização e começar"',
    esperado: 'Mapa abre com a barra "Buscar posto ou endereço", sem aviso de erro',
    severidade: critica,
    corpo: () async {
      await qa.tocar(find.widgetWithText(FilledButton, 'Permitir localização e começar'));
      await qa.esperar(find.text('Buscar posto ou endereço'), limite: const Duration(seconds: 30));
      return 'Mapa aberto';
    },
  );
}

Finder _aba(String nome) => find.descendant(of: find.byType(NavigationBar), matching: find.text(nome));

Future<void> _navegacao(Qa qa) async {
  for (final (aba, marca) in [
    ('Buscar', find.byType(SearchBar)),
    ('Favoritos', find.widgetWithText(AppBar, 'Favoritos')),
    ('Perfil', find.text('Contribua com a sua cidade')),
    ('Mapa', find.text('Buscar posto ou endereço')),
  ]) {
    await qa.caso(
      modulo: 'Navegação',
      tela: 'Barra inferior',
      tipo: 'Funcional · navegação',
      cenario: 'Aba $aba abre a tela certa',
      passos: 'Tocar em $aba na barra inferior',
      esperado: 'Tela de $aba aparece',
      capturar: aba != 'Mapa',
      corpo: () async {
        await qa.tocar(_aba(aba));
        await qa.esperar(marca);
        return 'Tela de $aba aberta';
      },
    );
  }
}

// ------------------------------------------------------------------ mapa
Future<void> _mapa(Qa qa) async {
  final t = qa.t;
  await qa.irPara('/');
  await qa.caso(
    modulo: 'Mapa',
    tela: 'Mapa',
    tipo: 'Funcional · carga',
    cenario: 'Mapa carrega os postos da região sem erro',
    precondicoes: 'Servidor no ar; GPS em São Paulo',
    passos: 'Abrir o mapa e esperar a carga',
    esperado: 'Indicador de carga some em até 30 s; nenhum aviso "Não foi possível..."',
    severidade: critica,
    corpo: () async {
      await qa.aguardar(const Duration(seconds: 3));
      final carga = find.descendant(of: find.byType(InkWell), matching: find.byType(CircularProgressIndicator));
      await qa.esperarSumir(carga, limite: const Duration(seconds: 30), oque: 'indicador de carga do mapa');
      await qa.aguardar(const Duration(seconds: 3));
      final erro = find.textContaining('Não foi possível');
      confirmar(!qa.existe(erro), 'Aviso na tela: ${qa.existe(erro) ? t.widget<Text>(erro.first).data : ''}');
      confirmar(!qa.existe(find.text('Aproxime o mapa para ver os postos e preços.')), 'Mapa abriu afastado demais');
      return 'Carga concluída sem aviso de erro';
    },
  );

  var abriuFolha = false;
  await qa.caso(
    modulo: 'Mapa',
    tela: 'Mapa · pino',
    tipo: 'Funcional · toque',
    cenario: 'Tocar num pino abre a folha do posto',
    passos: 'Tocar nos pinos próximos ao centro do mapa até um deles responder',
    esperado: 'Folha inferior com nome, endereço, preço e os botões Atualizar e Ver detalhes',
    severidade: alta,
    corpo: () async {
      final tam = qa.tela;
      final pontos = <Offset>[
        for (var y = tam.height * 0.38; y < tam.height * 0.70; y += 44)
          for (var x = tam.width * 0.15; x < tam.width * 0.85; x += 52) Offset(x, y),
      ];
      for (final p in pontos) {
        await t.tapAt(p);
        await qa.aguardar(const Duration(milliseconds: 500));
        if (qa.existe(find.text('Ver detalhes'))) {
          abriuFolha = true;
          return 'Folha aberta com toque do Flutter em (${p.dx.round()}, ${p.dy.round()})';
        }
      }
      // Alguns aparelhos só repassam ao mapa nativo um toque de verdade: tenta pelo adb
      final dpr = t.view.devicePixelRatio;
      for (final p in pontos.take(16)) {
        await qa.adb('tap:${(p.dx * dpr).round()}:${(p.dy * dpr).round()}', espera: const Duration(milliseconds: 1500));
        if (qa.existe(find.text('Ver detalhes'))) {
          abriuFolha = true;
          return 'Folha aberta com toque do adb em (${p.dx.round()}, ${p.dy.round()})';
        }
      }
      throw Falha('Nenhum dos ${pontos.length} toques perto do centro abriu a folha de um posto');
    },
  );

  if (abriuFolha) {
    await qa.caso(
      modulo: 'Mapa',
      tela: 'Mapa · folha do posto',
      tipo: 'Funcional · gesto',
      cenario: 'Arrastar a folha para cima mostra todos os preços do posto',
      passos: 'Arrastar a folha pela parte de cima até o alto da tela',
      esperado: 'Folha expandida com a seção "Preços" (um preço por combustível)',
      severidade: alta,
      corpo: () async {
        final nome = find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Text)).first;
        await t.timedDrag(nome, const Offset(0, -500), const Duration(milliseconds: 600));
        await qa.aguardar(const Duration(milliseconds: 800));
        await qa.esperar(find.text('Preços'), limite: const Duration(seconds: 4), oque: 'seção Preços da folha expandida');
        return 'Folha expandida com a lista de preços';
      },
    );
    await qa.caso(
      modulo: 'Mapa',
      tela: 'Mapa · folha do posto',
      tipo: 'Funcional · botão',
      cenario: 'Botão fechar (×) recolhe a folha',
      passos: 'Tocar no × da folha',
      esperado: 'Folha some e o mapa fica livre',
      capturar: false,
      corpo: () async {
        await qa.tocar(find.byTooltip('Fechar'));
        await qa.esperarSumir(find.text('Ver detalhes'), limite: const Duration(seconds: 5));
        return 'Folha fechada';
      },
    );
    await qa.caso(
      modulo: 'Mapa',
      tela: 'Mapa · folha do posto',
      tipo: 'Funcional · botão',
      cenario: 'Ver detalhes abre a página do posto',
      passos: 'Abrir de novo a folha de um posto; tocar em Ver detalhes',
      esperado: 'Página do posto com Preços, Histórico, Avaliações e Dados do posto',
      severidade: alta,
      corpo: () async {
        final tam = qa.tela;
        for (var y = tam.height * 0.38; y < tam.height * 0.70 && !qa.existe(find.text('Ver detalhes')); y += 44) {
          for (var x = tam.width * 0.15; x < tam.width * 0.85 && !qa.existe(find.text('Ver detalhes')); x += 52) {
            await t.tapAt(Offset(x, y));
            await qa.aguardar(const Duration(milliseconds: 500));
          }
        }
        await qa.tocar(find.text('Ver detalhes'));
        await qa.achar(find.text('Dados do posto'));
        await qa.voltar();
        await qa.esperar(find.text('Buscar posto ou endereço'));
        return 'Página do posto aberta e voltou ao mapa';
      },
    );
  }

  await qa.caso(
    modulo: 'Mapa',
    tela: 'Mapa · combustível',
    tipo: 'Funcional · multisseleção',
    cenario: 'Lista de combustíveis abre abaixo do botão e continua aberta ao marcar vários',
    passos: 'Tocar no seletor de combustível; marcar Etanol e Diesel S10 sem reabrir',
    esperado: 'Lista abaixo do botão, aberta após cada toque; o botão mostra "3 combustíveis"',
    severidade: alta,
    corpo: () async {
      Preferencias.produto.value = {1};
      await t.pump();
      final botao = find.byType(SeletorProduto);
      await qa.tocar(botao);
      await qa.esperar(find.text('Etanol'));
      final baseBotao = t.getBottomLeft(botao).dy;
      final topoLista = t.getTopLeft(find.text('GNV')).dy;
      confirmar(t.getTopLeft(find.text('Etanol')).dy > baseBotao, 'A lista abriu por cima do botão');
      await qa.tocar(find.text('Etanol'));
      confirmar(qa.existe(find.text('Diesel S10')), 'A lista fechou depois do primeiro toque');
      await qa.tocar(find.text('Diesel S10'));
      confirmar(qa.existe(find.text('GNV')), 'A lista fechou depois do segundo toque');
      confirmar(Preferencias.produto.value.length == 3, 'Selecionados: ${Preferencias.produto.value}');
      await qa.esperar(find.descendant(of: botao, matching: find.text('3 combustíveis')));
      return 'Lista abaixo do botão (topo em ${topoLista.round()} > base ${baseBotao.round()}); 3 marcados sem reabrir';
    },
  );
  await qa.caso(
    modulo: 'Mapa',
    tela: 'Mapa · combustível',
    tipo: 'Funcional · fechar',
    cenario: 'Tocar fora da lista de combustíveis fecha a lista',
    passos: 'Com a lista aberta, tocar no mapa fora dela',
    esperado: 'Lista some; seleção continua com 3 combustíveis',
    capturar: false,
    corpo: () async {
      await t.tapAt(Offset(qa.tela.width - 20, qa.tela.height * 0.6));
      await qa.esperarSumir(find.text('Diesel S500'), limite: const Duration(seconds: 3));
      confirmar(Preferencias.produto.value.length == 3, 'Seleção mudou ao fechar: ${Preferencias.produto.value}');
      return 'Lista fechada, 3 combustíveis mantidos';
    },
  );
  await qa.caso(
    modulo: 'Mapa',
    tela: 'Mapa · combustível',
    tipo: 'Regra · mínimo de um',
    cenario: 'Não dá para desmarcar o último combustível',
    passos: 'Abrir a lista; desmarcar até sobrar um; tentar desmarcar o último',
    esperado: 'O último continua marcado',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.byType(SeletorProduto));
      await qa.tocar(find.text('Etanol'));
      await qa.tocar(find.text('Diesel S10'));
      await qa.tocar(find.text('Gasolina comum').last);
      confirmar(Preferencias.produto.value.length == 1, 'Ficou ${Preferencias.produto.value}');
      await qa.tocar(find.byType(SeletorProduto));
      return 'Seleção final ${Preferencias.produto.value}';
    },
  );
  await qa.caso(
    modulo: 'Mapa',
    tela: 'Mapa · distância',
    tipo: 'Funcional · filtro',
    cenario: 'Escolher "Até 5 km" desenha o raio e limita os postos',
    passos: 'Tocar no seletor de distância; escolher Até 5 km',
    esperado: 'Botão mostra "5 km"; o menu abre abaixo do botão',
    corpo: () async {
      final botao = find.byType(SeletorRaio);
      await qa.tocar(botao);
      await qa.esperar(find.text('Até 5 km'));
      confirmar(t.getTopLeft(find.text('Até 5 km')).dy > t.getTopLeft(botao).dy, 'Menu abriu por cima do botão');
      await qa.tocar(find.text('Até 5 km'));
      await qa.esperar(find.descendant(of: botao, matching: find.text('5 km')));
      await qa.aguardar(const Duration(seconds: 3));
      confirmar(Preferencias.raioKm.value == 5, 'Raio salvo: ${Preferencias.raioKm.value}');
      return 'Raio de 5 km aplicado';
    },
  );
  await qa.caso(
    modulo: 'Mapa',
    tela: 'Mapa · distância',
    tipo: 'Funcional · filtro',
    cenario: 'Voltar para "Qualquer distância" remove o raio',
    passos: 'Seletor de distância → Qualquer distância',
    esperado: 'Botão mostra "Qualquer"',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.byType(SeletorRaio));
      await qa.tocar(find.text('Qualquer distância'));
      await qa.esperar(find.descendant(of: find.byType(SeletorRaio), matching: find.text('Qualquer')));
      confirmar(Preferencias.raioKm.value == null, 'Raio continuou ${Preferencias.raioKm.value}');
      return 'Raio removido';
    },
  );
  await qa.caso(
    modulo: 'Mapa',
    tela: 'Mapa',
    tipo: 'Funcional · botão',
    cenario: 'Botão "Minha localização" centraliza sem erro',
    passos: 'Tocar no botão de localização',
    esperado: 'Nenhuma mensagem de localização desligada ou negada',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.byTooltip('Minha localização'));
      await qa.aguardar(const Duration(seconds: 2));
      final m = qa.mensagemAtual();
      confirmar(m == null, 'Mensagem: $m');
      return 'Centralizou sem mensagem';
    },
  );
  await qa.caso(
    modulo: 'Mapa',
    tela: 'Mapa',
    tipo: 'Funcional · botão',
    cenario: 'Barra "Buscar posto ou endereço" leva à aba Buscar',
    passos: 'Tocar na barra de busca do mapa',
    esperado: 'Aba Buscar com o campo de texto',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.text('Buscar posto ou endereço'));
      await qa.esperar(find.byType(SearchBar));
      return 'Abriu a aba Buscar (a barra do mapa não busca no próprio mapa)';
    },
  );
}

// ------------------------------------------------------------------ busca
List<CartaoPosto> _cartoes(Qa qa) => qa.t.widgetList<CartaoPosto>(find.byType(CartaoPosto)).toList();

Future<int> _busca(Qa qa) async {
  final t = qa.t;
  var postoId = 0;
  await qa.irPara('/buscar');
  await qa.caso(
    modulo: 'Busca',
    tela: 'Buscar',
    tipo: 'Funcional · carga',
    cenario: 'Busca abre com os postos perto do aparelho',
    passos: 'Abrir a aba Buscar sem digitar',
    esperado: 'Lista de postos e a contagem "N postos em até 20 km"',
    severidade: alta,
    corpo: () async {
      await qa.esperar(find.byType(CartaoPosto), limite: const Duration(seconds: 30));
      final c = _cartoes(qa);
      final comPreco = c.where((x) => x.posto.preco(x.produtoId) != null).toList();
      postoId = (comPreco.isNotEmpty ? comPreco.first : c.first).posto.id;
      return '${c.length} cartões construídos; ${comPreco.length} com preço; posto usado nos testes: $postoId';
    },
  );
  await qa.caso(
    modulo: 'Busca',
    tela: 'Buscar',
    tipo: 'Funcional · texto',
    cenario: 'Busca por texto encontra postos',
    passos: 'Digitar "Paulista" no campo de busca',
    entrada: 'Paulista',
    esperado: 'Contagem "N postos encontrados" com N > 0',
    corpo: () async {
      await qa.escrever(find.descendant(of: find.byType(SearchBar), matching: find.byType(TextField)), 'Paulista');
      await qa.esperar(find.textContaining('postos encontrados'), limite: const Duration(seconds: 20));
      await qa.esperarSumir(find.text('Buscando…'), limite: const Duration(seconds: 20));
      final texto = t.widget<Text>(find.textContaining('postos encontrados')).data!;
      confirmar(!texto.startsWith('0 '), texto);
      return texto;
    },
  );
  await qa.caso(
    modulo: 'Busca',
    tela: 'Buscar',
    tipo: 'Funcional · botão',
    cenario: 'Botão limpar (×) apaga o texto e volta aos postos próximos',
    passos: 'Tocar no × do campo',
    esperado: 'Campo vazio; contagem volta a "postos em até"',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.byTooltip('Limpar'));
      await qa.esperar(find.textContaining('postos em até'), limite: const Duration(seconds: 20));
      return 'Texto limpo';
    },
  );
  await qa.caso(
    modulo: 'Busca',
    tela: 'Buscar · ordenar',
    tipo: 'Funcional · ordenação',
    cenario: 'Ordenar por menor preço deixa a lista em ordem crescente',
    passos: 'Ordenar → Menor preço',
    esperado: 'Preços dos cartões em ordem crescente; postos sem preço no fim',
    severidade: alta,
    corpo: () async {
      await qa.esperarSumir(find.text('Buscando…'));
      await qa.tocar(find.byTooltip('Ordenar'));
      await qa.tocar(find.text('Menor preço').last);
      await qa.aguardar(const Duration(milliseconds: 800));
      final precos = _cartoes(qa).map((c) => c.posto.preco(c.produtoId)?.preco).toList();
      var semPreco = false;
      for (var i = 0; i < precos.length; i++) {
        if (precos[i] == null) {
          semPreco = true;
        } else {
          confirmar(!semPreco, 'Posto com preço depois de posto sem preço (posição $i)');
          if (i > 0 && precos[i - 1] != null) confirmar(precos[i - 1]! <= precos[i]!, 'Fora de ordem: $precos');
        }
      }
      return 'Ordem conferida em ${precos.length} cartões: ${precos.take(6).join(', ')}…';
    },
  );
  await qa.caso(
    modulo: 'Busca',
    tela: 'Buscar · ordenar',
    tipo: 'Funcional · ordenação',
    cenario: 'Ordenar por mais próximos deixa a lista em distância crescente',
    passos: 'Ordenar → Mais próximos',
    esperado: 'Distâncias em ordem crescente',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.byTooltip('Ordenar'));
      await qa.tocar(find.text('Mais próximos').last);
      await qa.aguardar(const Duration(milliseconds: 800));
      final d = _cartoes(qa).map((c) => c.posto.distanciaKm ?? double.infinity).toList();
      for (var i = 1; i < d.length; i++) {
        confirmar(d[i - 1] <= d[i], 'Fora de ordem: ${d.take(10).toList()}');
      }
      return 'Distâncias crescentes: ${d.take(5).map((x) => x.toStringAsFixed(2)).join(', ')}…';
    },
  );
  await qa.caso(
    modulo: 'Busca',
    tela: 'Buscar · filtros',
    tipo: 'Funcional · filtro',
    cenario: 'Filtros de distância e avaliação mínima são aplicados à lista',
    passos: 'Filtros → Até 5 km → 4,0+ → Aplicar',
    esperado: 'Selo do botão Filtros com 2; todos os cartões a até 5 km e com nota 4 ou mais',
    severidade: alta,
    corpo: () async {
      await qa.tocar(find.byTooltip('Filtros'));
      await qa.esperar(find.text('Faixa de preço'));
      await qa.tocar(find.widgetWithText(ChoiceChip, 'Até 5 km'));
      await qa.tocar(find.widgetWithText(ChoiceChip, '4,0+'));
      await qa.tocar(find.widgetWithText(FilledButton, 'Aplicar'));
      await qa.aguardar(const Duration(seconds: 2));
      await qa.esperarSumir(find.text('Buscando…'), limite: const Duration(seconds: 20));
      await qa.esperar(find.descendant(of: find.byType(Badge), matching: find.text('2')));
      final c = _cartoes(qa);
      for (final x in c) {
        confirmar((x.posto.distanciaKm ?? 99) <= 5, '${x.posto.nome} a ${x.posto.distanciaKm} km');
        confirmar((x.posto.notaMedia ?? 0) >= 4, '${x.posto.nome} com nota ${x.posto.notaMedia}');
      }
      return c.isEmpty ? 'Filtros aplicados; nenhum posto atende (estado vazio exibido)' : '${c.length} cartões, todos dentro dos filtros';
    },
  );
  await qa.caso(
    modulo: 'Busca',
    tela: 'Buscar · filtros',
    tipo: 'Integração · mapa',
    cenario: 'Distância escolhida nos filtros da busca vale também no mapa',
    passos: 'Depois de aplicar Até 5 km na busca, conferir o seletor de distância',
    esperado: 'Preferência de raio = 5 km (o mapa usa a mesma)',
    capturar: false,
    corpo: () async {
      confirmar(Preferencias.raioKm.value == 5, 'Raio compartilhado: ${Preferencias.raioKm.value}');
      return 'Raio de 5 km compartilhado com o mapa';
    },
  );
  await qa.caso(
    modulo: 'Busca',
    tela: 'Buscar · filtros',
    tipo: 'Funcional · botão',
    cenario: 'Limpar filtros tira o selo e volta à lista completa',
    passos: 'Filtros → Limpar',
    esperado: 'Sem selo no botão Filtros; raio volta para qualquer distância',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.byTooltip('Filtros'));
      await qa.tocar(find.widgetWithText(OutlinedButton, 'Limpar'));
      await qa.aguardar(const Duration(seconds: 2));
      final selo = t.widgetList<Badge>(find.byType(Badge)).where((b) => b.isLabelVisible).length;
      confirmar(selo == 0, 'Selo continua visível');
      confirmar(Preferencias.raioKm.value == null, 'Raio continuou ${Preferencias.raioKm.value}');
      return 'Filtros limpos';
    },
  );
  await qa.caso(
    modulo: 'Busca',
    tela: 'Buscar',
    tipo: 'Funcional · toque',
    cenario: 'Tocar num cartão abre a página do posto',
    passos: 'Tocar no primeiro cartão da lista',
    esperado: 'Página do posto aberta',
    capturar: false,
    corpo: () async {
      await qa.esperar(find.byType(CartaoPosto), limite: const Duration(seconds: 20));
      await qa.tocar(find.byType(CartaoPosto));
      await qa.achar(find.text('Dados do posto'));
      await qa.voltar();
      return 'Abriu e voltou';
    },
  );
  return postoId;
}

// ------------------------------------------------------------------ posto sem conta
Future<void> _postoVisitante(Qa qa, int postoId) async {
  final t = qa.t;
  await qa.irPara('/posto/$postoId');
  await qa.caso(
    modulo: 'Posto',
    tela: 'Posto',
    tipo: 'Funcional · carga',
    cenario: 'Página do posto mostra preços, histórico, avaliações e dados cadastrais',
    passos: 'Abrir /posto/$postoId',
    esperado: 'Seções Preços, Histórico de preços, Avaliações e Dados do posto com CNPJ formatado',
    severidade: alta,
    corpo: () async {
      await qa.esperar(find.text('Preços'), limite: const Duration(seconds: 25));
      await qa.achar(find.text('CNPJ'));
      final cnpj = find.textContaining(RegExp(r'^\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}$'));
      confirmar(qa.existe(cnpj), 'CNPJ sem a máscara 00.000.000/0000-00');
      return 'Todas as seções; CNPJ ${t.widget<Text>(cnpj.first).data}';
    },
  );
  await qa.irPara('/posto/$postoId');
  await qa.caso(
    modulo: 'Posto',
    tela: 'Posto',
    tipo: 'Funcional · botão',
    cenario: 'Coração salva o posto nos favoritos sem conta',
    passos: 'Tocar no coração do topo',
    esperado: 'Mensagem "Posto salvo nos favoritos."; o ícone fica preenchido',
    corpo: () async {
      await qa.tocar(find.byTooltip('Salvar nos favoritos'), limite: const Duration(seconds: 25));
      final m = await qa.esperarMensagem('favoritos');
      await qa.esperar(find.byTooltip('Remover dos favoritos'));
      return m;
    },
  );
  await qa.caso(
    modulo: 'Posto',
    tela: 'Posto · contribuições',
    tipo: 'Funcional · toque',
    cenario: 'Tocar num preço abre a folha de contribuições',
    passos: 'Tocar na primeira linha de preço',
    esperado: 'Folha "Contribuições" com o bloco DADO OFICIAL (Pesquisa ANP)',
    corpo: () async {
      await qa.tocar(find.byType(LinhaPreco));
      await qa.esperar(find.text('Contribuições'));
      await qa.achar(find.text('DADO OFICIAL'));
      return 'Folha de contribuições aberta';
    },
  );
  await qa.voltar();
  await qa.caso(
    modulo: 'Posto',
    tela: 'Histórico de preços',
    tipo: 'Funcional · botão',
    cenario: 'Ver completo abre o histórico; trocar combustível e período recarrega o gráfico',
    passos: 'Histórico de preços → Ver completo → Etanol → 1 ano',
    esperado: 'Tela Histórico de preços sem erro depois de cada troca',
    corpo: () async {
      await qa.tocar(find.text('Ver completo'));
      await qa.esperar(find.widgetWithText(AppBar, 'Histórico de preços'));
      await qa.tocar(find.widgetWithText(ChoiceChip, 'Etanol'));
      await qa.tocar(find.text('1 ano'));
      await qa.esperarSumir(find.byType(CircularProgressIndicator), limite: const Duration(seconds: 20));
      confirmar(!qa.existe(find.text('Não foi possível carregar')), 'Erro ao carregar o histórico');
      final resumo = find.textContaining('registros da ANP');
      return qa.existe(resumo) ? t.widget<Text>(resumo).data! : 'Gráfico carregado, sem registros no período';
    },
  );
  await qa.voltar();
  await qa.caso(
    modulo: 'Posto',
    tela: 'Avaliações',
    tipo: 'Funcional · botão',
    cenario: 'Ver todas abre as avaliações e a ordem "Mais úteis" recarrega a lista',
    passos: 'Avaliações → Ver todas → Mais úteis',
    esperado: 'Lista de avaliações ou "Nenhuma avaliação ainda", sem erro',
    corpo: () async {
      await qa.tocar(find.text('Ver todas'));
      await qa.esperar(find.text('Mais recentes'));
      await qa.tocar(find.text('Mais úteis'));
      await qa.aguardar(const Duration(seconds: 2));
      confirmar(!qa.existe(find.text('Não foi possível carregar')), 'Erro ao carregar avaliações');
      return qa.existe(find.text('Nenhuma avaliação ainda')) ? 'Sem avaliações (estado vazio)' : 'Lista carregada';
    },
  );
  await qa.caso(
    modulo: 'Posto',
    tela: 'Avaliações',
    tipo: 'Regra · login',
    cenario: 'Avaliar sem conta pede para entrar',
    passos: 'Na tela de avaliações, tocar em Avaliar',
    esperado: 'Folha "Entre para continuar" com Entrar e Criar conta',
    corpo: () async {
      await qa.tocar(find.byType(FloatingActionButton));
      await qa.esperar(find.text('Entre para continuar'));
      return 'Pediu login';
    },
  );
  await qa.voltar();
  await qa.voltar();
  await qa.caso(
    modulo: 'Posto',
    tela: 'Posto',
    tipo: 'Integração · app externo',
    cenario: 'Como chegar abre o aplicativo de mapas',
    passos: 'Tocar em Como chegar; voltar ao app',
    esperado: 'Abre o Google Maps ou o navegador; sem a mensagem "Não foi possível abrir o aplicativo de mapas."',
    corpo: () async {
      await qa.adb('voltar_app_em:6', espera: Duration.zero);
      await qa.tocar(find.text('Como chegar'));
      await qa.aguardar(const Duration(seconds: 8));
      final m = qa.mensagemAtual();
      confirmar(m == null || !m.contains('Não foi possível'), 'Mensagem: $m');
      return 'App de mapas aberto e o gasprice voltou';
    },
  );
  await qa.irPara('/posto/$postoId');
  await qa.caso(
    modulo: 'Posto',
    tela: 'Posto',
    tipo: 'Regra · login',
    cenario: 'Atualizar preços sem conta pede para entrar',
    passos: 'Tocar em Atualizar preços',
    esperado: 'Folha "Entre para continuar" (ou, em posto sem localização, o pedido para confirmar o local)',
    severidade: alta,
    corpo: () async {
      await qa.tocar(find.text('Atualizar preços'), limite: const Duration(seconds: 25));
      await qa.aguardar(const Duration(seconds: 1));
      if (qa.existe(find.text('Localização desconhecida'))) {
        await qa.tocar(find.text('Agora não'));
        return 'Posto sem posição: mostrou o pedido para confirmar o local';
      }
      await qa.esperar(find.text('Entre para continuar'));
      return 'Pediu login';
    },
  );
  await qa.caso(
    modulo: 'Posto',
    tela: 'Entre para continuar',
    tipo: 'Funcional · botão',
    cenario: 'Entrar, na folha de login, abre a tela Entrar',
    passos: 'Na folha "Entre para continuar", tocar em Entrar',
    esperado: 'Tela Entrar com e-mail, senha e "Esqueci minha senha"',
    capturar: false,
    corpo: () async {
      if (!qa.existe(find.text('Entre para continuar'))) {
        await qa.tocar(find.text('Avaliar'));
        await qa.esperar(find.text('Entre para continuar'));
      }
      await qa.tocar(find.widgetWithText(FilledButton, 'Entrar'));
      await qa.esperar(find.text('Esqueci minha senha'));
      return 'Tela Entrar aberta';
    },
  );
}

Future<void> _favoritosVisitante(Qa qa) async {
  await qa.irPara('/favoritos');
  await qa.caso(
    modulo: 'Favoritos',
    tela: 'Favoritos',
    tipo: 'Funcional · sem conta',
    cenario: 'Favorito salvo sem conta aparece na aba Favoritos',
    passos: 'Abrir a aba Favoritos',
    esperado: 'Aviso "Favoritos salvos só neste aparelho" e o cartão do posto salvo',
    corpo: () async {
      await qa.esperar(find.text('Favoritos salvos só neste aparelho'));
      await qa.esperar(find.byType(CartaoPosto), limite: const Duration(seconds: 20));
      return '${_cartoes(qa).length} favorito(s)';
    },
  );
}

// ------------------------------------------------------------------ conta
Finder _campo(String rotulo) => find.widgetWithText(TextFormField, rotulo);

Future<void> _cadastro(Qa qa) async {
  final t = qa.t;
  await qa.irPara('/cadastro');
  await qa.caso(
    modulo: 'Conta',
    tela: 'Criar conta',
    tipo: 'Validação · campos vazios',
    cenario: 'Criar conta com o formulário vazio mostra os erros de cada campo',
    passos: 'Tocar em Criar conta sem preencher nada',
    esperado: '"Informe seu nome.", "Informe seu e-mail." e a regra de senha',
    corpo: () async {
      await qa.tocar(find.widgetWithText(FilledButton, 'Criar conta'));
      await qa.achar(find.text('Informe seu nome.'));
      await qa.achar(find.text('Informe seu e-mail.'));
      await qa.achar(find.textContaining('A senha precisa ter pelo menos 8'));
      return 'Os três erros aparecem';
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Criar conta',
    tipo: 'Validação · formato',
    cenario: 'E-mail inválido, senha fraca e confirmação diferente são recusados no app',
    passos: 'Preencher e-mail "abc", senha "abc123" e confirmação "outra"; tocar em Criar conta',
    entrada: 'abc / abc123 / outra',
    esperado: '"E-mail inválido.", regra de senha e "As senhas não conferem."',
    corpo: () async {
      await qa.escrever(_campo('Nome'), 'Qa');
      await qa.escrever(_campo('E-mail'), 'abc');
      await qa.escrever(_campo('Senha'), 'abc123');
      await qa.escrever(_campo('Confirme a senha'), 'outra');
      await qa.tocar(find.widgetWithText(FilledButton, 'Criar conta'));
      await qa.achar(find.text('E-mail inválido.'));
      await qa.achar(find.textContaining('A senha precisa ter pelo menos 8'));
      await qa.achar(find.text('As senhas não conferem.'));
      return 'Os três erros aparecem';
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Criar conta',
    tipo: 'Funcional · campos novos',
    cenario: 'Gênero, sobrenome e data de nascimento funcionam',
    passos: 'Sobrenome "Teste"; Gênero → Feminino; Data de nascimento → OK; remover a data',
    esperado: 'Feminino selecionado; data no formato dd/mm/aaaa; o × apaga a data',
    corpo: () async {
      await qa.escrever(_campo('Sobrenome (opcional)'), 'Teste');
      await qa.tocar(find.text('Feminino'));
      final seg = t.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
      confirmar(seg.selected.contains('F'), 'Gênero selecionado: ${seg.selected}');
      await qa.tocar(_campo('Data de nascimento (opcional)'));
      await qa.esperar(find.byType(DatePickerDialog));
      await qa.tocar(find.text('OK'));
      final data = find.textContaining(RegExp(r'^\d{2}/\d{2}/\d{4}$'));
      await qa.esperar(data);
      final valor = t.widget<Text>(data.first).data;
      await qa.tocar(find.byTooltip('Remover data'));
      confirmar(!qa.existe(data), 'A data não foi removida');
      return 'Gênero F; data escolhida $valor e removida';
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Criar conta',
    tipo: 'Regra · termos',
    cenario: 'Sem aceitar os termos a conta não é criada',
    passos: 'Preencher tudo certo sem marcar os termos; tocar em Criar conta',
    entrada: 'qa.naocriar@auditoria.gasprice.test',
    esperado: 'Mensagem pedindo para aceitar os termos; continua na tela',
    corpo: () async {
      await qa.escrever(_campo('E-mail'), 'qa.naocriar@auditoria.gasprice.test');
      await qa.escrever(_campo('Senha'), qaSenha);
      await qa.escrever(_campo('Confirme a senha'), qaSenha);
      await qa.tocar(find.widgetWithText(FilledButton, 'Criar conta'));
      return qa.esperarMensagem('aceite os termos');
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Criar conta',
    tipo: 'Funcional · link',
    cenario: 'Ler os termos abre a página Sobre',
    passos: 'Tocar em Ler os termos; voltar',
    esperado: 'Página "Sobre os dados e privacidade" com Termos de uso',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.text('Ler os termos'));
      await qa.esperar(find.text('De onde vêm os preços'));
      await qa.achar(find.text('Termos de uso'));
      await qa.voltar();
      await qa.esperar(find.widgetWithText(FilledButton, 'Criar conta'));
      return 'Abriu e voltou ao cadastro';
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Criar conta',
    tipo: 'Funcional · link',
    cenario: '"Já tem conta? Entrar" troca para a tela Entrar',
    passos: 'Tocar em Entrar no rodapé',
    esperado: 'Tela Entrar',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.widgetWithText(TextButton, 'Entrar'));
      await qa.esperar(find.text('Esqueci minha senha'));
      return 'Tela Entrar aberta';
    },
  );
}

Future<void> _entrar(Qa qa) async {
  await qa.irPara('/entrar');
  await qa.caso(
    modulo: 'Conta',
    tela: 'Entrar',
    tipo: 'Validação · campos vazios',
    cenario: 'Entrar sem preencher mostra os erros',
    passos: 'Tocar em Entrar com os campos vazios',
    esperado: '"Informe seu e-mail." e "Informe sua senha."',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.widgetWithText(FilledButton, 'Entrar'));
      await qa.esperar(find.text('Informe seu e-mail.'));
      await qa.esperar(find.text('Informe sua senha.'));
      return 'Os dois erros aparecem';
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Entrar',
    tipo: 'Funcional · botão',
    cenario: 'Olho do campo de senha mostra e esconde a senha',
    passos: 'Tocar em Mostrar senha; depois em Ocultar senha',
    esperado: 'O botão alterna entre "Mostrar senha" e "Ocultar senha"',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.byTooltip('Mostrar senha'));
      await qa.esperar(find.byTooltip('Ocultar senha'));
      await qa.tocar(find.byTooltip('Ocultar senha'));
      await qa.esperar(find.byTooltip('Mostrar senha'));
      return 'Alterna nos dois sentidos';
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Entrar',
    tipo: 'Funcional · negativo',
    cenario: 'Senha errada é recusada com mensagem clara',
    passos: 'Entrar com o e-mail da conta de teste e senha errada',
    entrada: '$qaEmail / senha errada',
    esperado: '"E-mail ou senha incorretos."',
    severidade: alta,
    corpo: () async {
      await qa.escrever(_campo('E-mail'), qaEmail);
      await qa.escrever(_campo('Senha'), 'Errada!123');
      await qa.tocar(find.widgetWithText(FilledButton, 'Entrar'));
      return qa.esperarMensagem('incorretos', limite: const Duration(seconds: 25));
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Recuperar senha',
    tipo: 'Validação · campo vazio',
    cenario: 'Esqueci minha senha abre a recuperação e exige e-mail',
    passos: 'Tocar em Esqueci minha senha; tocar em Enviar link sem e-mail',
    esperado: 'Tela Recuperar senha com "Informe seu e-mail."',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.text('Esqueci minha senha'));
      await qa.esperar(find.text('Recuperar senha'));
      await qa.tocar(find.widgetWithText(FilledButton, 'Enviar link'));
      await qa.esperar(find.text('Informe seu e-mail.'));
      await qa.voltar();
      return 'Validação ok (o link de e-mail fica para o roteiro manual)';
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Entrar',
    tipo: 'Funcional · positivo',
    cenario: 'Entrar com a conta de teste',
    precondicoes: 'Conta criada e confirmada pelo executar.py',
    passos: 'Preencher e-mail e senha corretos; tocar em Entrar',
    entrada: qaEmail,
    esperado: 'Mensagem "Bem-vindo de volta!" e o perfil logado',
    severidade: critica,
    corpo: () async {
      await qa.escrever(_campo('Senha'), qaSenha);
      await qa.tocar(find.widgetWithText(FilledButton, 'Entrar'));
      final m = await qa.esperarMensagem('Bem-vindo', limite: const Duration(seconds: 25));
      await qa.esperar(find.text('Sair da conta'), limite: const Duration(seconds: 20));
      return m;
    },
  );
}

Future<void> _perfil(Qa qa) async {
  await qa.irPara('/perfil');
  await qa.caso(
    modulo: 'Perfil',
    tela: 'Perfil',
    tipo: 'Regressão · nome',
    cenario: 'Perfil mostra o nome da pessoa, não o começo do e-mail',
    precondicoes: 'Conta criada com o nome "$qaNome"',
    passos: 'Abrir o perfil',
    esperado: 'Título com "$qaNome" e o e-mail embaixo',
    severidade: alta,
    corpo: () async {
      await qa.esperar(find.text(qaNome), limite: const Duration(seconds: 20));
      confirmar(!qa.existe(find.text(qaEmail.split('@').first)), 'Aparece o começo do e-mail como nome');
      return 'Nome "$qaNome" exibido';
    },
  );
  for (final (rotulo, titulo) in [('pontos', 'Meus pontos'), ('no ranking', 'Ranking da comunidade')]) {
    await qa.caso(
      modulo: 'Perfil',
      tela: titulo,
      tipo: 'Funcional · botão',
      cenario: 'Cartão "$rotulo" abre $titulo',
      passos: 'Tocar no cartão $rotulo',
      esperado: 'Tela $titulo carregada sem erro',
      corpo: () async {
        await qa.tocar(find.text(rotulo));
        await qa.esperar(find.widgetWithText(AppBar, titulo));
        await qa.aguardar(const Duration(seconds: 2));
        confirmar(!qa.existe(find.text('Não foi possível carregar')), 'Erro ao carregar');
        await qa.voltar();
        return '$titulo aberta';
      },
    );
  }
  await qa.caso(
    modulo: 'Perfil',
    tela: 'Alterar dados',
    tipo: 'Funcional · positivo',
    cenario: 'Alterar o nome no perfil',
    passos: 'Alterar dados → Nome "$qaNome Editado" → Salvar',
    entrada: '$qaNome Editado',
    esperado: 'Mensagem "Dados salvos." e o novo nome no perfil',
    severidade: alta,
    corpo: () async {
      await qa.tocar(find.text('Alterar dados'));
      await qa.esperar(find.widgetWithText(AppBar, 'Alterar dados'));
      await qa.escrever(_campo('Nome'), '$qaNome Editado');
      await qa.tocar(find.widgetWithText(FilledButton, 'Salvar'));
      final m = await qa.esperarMensagem('Dados salvos');
      await qa.esperar(find.text('$qaNome Editado'), limite: const Duration(seconds: 15));
      return m;
    },
  );
  await qa.caso(
    modulo: 'Perfil',
    tela: 'Alterar senha',
    tipo: 'Funcional · negativo',
    cenario: 'Alterar senha com a senha atual errada é recusado',
    passos: 'Alterar senha → senha atual errada → nova senha válida → Salvar',
    esperado: '"A senha atual está incorreta."',
    corpo: () async {
      await qa.tocar(find.text('Alterar senha'));
      await qa.escrever(_campo('Senha atual'), 'Errada!123');
      await qa.escrever(_campo('Nova senha'), qaSenhaNova);
      await qa.escrever(_campo('Confirme a nova senha'), qaSenhaNova);
      await qa.tocar(find.widgetWithText(FilledButton, 'Salvar nova senha'));
      return qa.esperarMensagem('incorreta', limite: const Duration(seconds: 25));
    },
  );
  await qa.caso(
    modulo: 'Perfil',
    tela: 'Alterar senha',
    tipo: 'Funcional · positivo',
    cenario: 'Alterar senha com a senha atual certa',
    passos: 'Senha atual correta → Salvar nova senha',
    esperado: 'Mensagem "Senha alterada." e volta ao perfil',
    severidade: alta,
    corpo: () async {
      await qa.escrever(_campo('Senha atual'), qaSenha);
      await qa.tocar(find.widgetWithText(FilledButton, 'Salvar nova senha'));
      final m = await qa.esperarMensagem('Senha alterada', limite: const Duration(seconds: 25));
      await qa.esperar(find.text('Sair da conta'));
      return m;
    },
  );
  await qa.caso(
    modulo: 'Perfil',
    tela: 'Notificações',
    tipo: 'Funcional · botão',
    cenario: 'Notificações abre a lista e o atalho de preferências',
    passos: 'Notificações → ícone de preferências → voltar',
    esperado: 'Lista ou "Nenhum aviso"; o atalho abre Alterar dados',
    corpo: () async {
      await qa.tocar(find.text('Notificações'));
      await qa.esperar(find.widgetWithText(AppBar, 'Notificações'));
      await qa.aguardar(const Duration(seconds: 2));
      confirmar(!qa.existe(find.text('Não foi possível carregar')), 'Erro ao carregar notificações');
      await qa.tocar(find.byTooltip('Preferências de aviso'));
      await qa.esperar(find.widgetWithText(AppBar, 'Alterar dados'));
      await qa.voltar();
      await qa.voltar();
      return 'Notificações e atalho funcionando';
    },
  );
  await qa.caso(
    modulo: 'Perfil',
    tela: 'Sobre',
    tipo: 'Funcional · botão',
    cenario: 'Sobre os dados e privacidade abre a página Sobre',
    passos: 'Tocar em Sobre os dados e privacidade',
    esperado: 'Seções de origem dos preços, cores, privacidade e termos',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.text('Sobre os dados e privacidade'));
      await qa.esperar(find.text('De onde vêm os preços'));
      await qa.achar(find.textContaining('gasprice '));
      await qa.voltar();
      return 'Página Sobre completa';
    },
  );
}

// ------------------------------------------------------------------ posto com conta
Future<void> _postoLogado(Qa qa, int postoId) async {
  await qa.irPara('/posto/$postoId');
  await qa.caso(
    modulo: 'Posto',
    tela: 'Avaliar posto',
    tipo: 'Validação',
    cenario: 'Publicar avaliação sem nota ou com comentário curto é recusado',
    passos: 'Avaliar → Publicar sem nota; depois 4 estrelas e comentário "ab"',
    esperado: '"Escolha uma nota de 0 a 5 estrelas." e "O comentário precisa ter pelo menos 3 letras."',
    corpo: () async {
      await qa.tocar(find.widgetWithText(OutlinedButton, 'Avaliar'), limite: const Duration(seconds: 25));
      await qa.esperar(find.widgetWithText(AppBar, 'Avaliar posto'));
      await qa.tocar(find.widgetWithText(FilledButton, 'Publicar avaliação'));
      await qa.esperarMensagem('Escolha uma nota');
      await qa.tocar(find.byTooltip('4 estrelas'));
      await qa.esperar(find.text('Bom'));
      await qa.escrever(find.byType(TextField), 'ab');
      await qa.tocar(find.widgetWithText(FilledButton, 'Publicar avaliação'));
      return qa.esperarMensagem('pelo menos 3 letras');
    },
  );
  await qa.caso(
    modulo: 'Posto',
    tela: 'Avaliar posto',
    tipo: 'Funcional · positivo',
    cenario: 'Publicar uma avaliação',
    passos: 'Comentário válido → Publicar avaliação',
    entrada: '4 estrelas; "Teste automatizado de QA, pode ignorar."',
    esperado: 'Mensagem "Avaliação publicada."; o botão do posto vira "Editar avaliação"',
    severidade: alta,
    corpo: () async {
      await qa.escrever(find.byType(TextField), 'Teste automatizado de QA, pode ignorar.');
      await qa.tocar(find.widgetWithText(FilledButton, 'Publicar avaliação'));
      final m = await qa.esperarMensagem('Avaliação publicada', limite: const Duration(seconds: 25));
      await qa.esperar(find.text('Editar avaliação'), limite: const Duration(seconds: 25));
      return m;
    },
  );
  await qa.caso(
    modulo: 'Posto',
    tela: 'Editar avaliação',
    tipo: 'Funcional · botão',
    cenario: 'Apagar a própria avaliação',
    passos: 'Editar avaliação → lixeira → Apagar',
    esperado: 'Volta ao posto e o botão volta a ser "Avaliar"',
    severidade: alta,
    corpo: () async {
      await qa.tocar(find.text('Editar avaliação'));
      await qa.tocar(find.byTooltip('Apagar avaliação'), limite: const Duration(seconds: 25));
      await qa.esperar(find.text('Apagar sua avaliação?'));
      await qa.tocar(find.widgetWithText(FilledButton, 'Apagar'));
      await qa.esperar(find.widgetWithText(OutlinedButton, 'Avaliar'), limite: const Duration(seconds: 25));
      return 'Avaliação apagada';
    },
  );
  await qa.caso(
    modulo: 'Envio por foto',
    tela: 'Atualizar preços',
    tipo: 'Funcional · com conta',
    cenario: 'Atualizar preços com conta abre as instruções da foto',
    passos: 'Tocar em Atualizar preços',
    esperado: '"Fotografe o painel de preços" com o raio de envio e o botão Abrir câmera ativo',
    severidade: alta,
    corpo: () async {
      await qa.tocar(find.text('Atualizar preços'));
      await qa.aguardar(const Duration(seconds: 1));
      if (qa.existe(find.text('Localização desconhecida'))) {
        await qa.tocar(find.text('Estou neste posto'));
        await qa.esperar(find.text('Informar a posição deste posto'));
        await qa.voltar();
        return 'Posto sem posição: abriu "Estou neste posto" (sem enviar)';
      }
      await qa.esperar(find.text('Fotografe o painel de preços'));
      await qa.esperar(find.textContaining('No posto, a até'));
      final botao = find.widgetWithText(FilledButton, 'Abrir câmera');
      await qa.esperar(botao);
      confirmar(qa.t.widget<FilledButton>(botao).onPressed != null, 'Abrir câmera desativado');
      return 'Instruções e botão Abrir câmera ativos';
    },
  );
  await qa.caso(
    modulo: 'Envio por foto',
    tela: 'Atualizar preços',
    tipo: 'Funcional · câmera',
    cenario: 'Fotografar o painel e enviar os preços lidos',
    passos: 'Abrir câmera → fotografar um painel → conferir → Enviar preços',
    esperado: 'Preços lidos da foto; envio aceito a até 300 m do posto',
    severidade: critica,
    capturar: false,
    corpo: () async => throw NaoTestado(
        'Exige câmera com um painel real e estar no posto; o envio ficaria no histórico real. Fica no roteiro manual (aba Android manual).'),
  );
}

Future<void> _favoritosLogado(Qa qa) async {
  await qa.irPara('/favoritos');
  await qa.caso(
    modulo: 'Favoritos',
    tela: 'Favoritos',
    tipo: 'Integração · conta',
    cenario: 'Favorito salvo antes de entrar passa para a conta',
    passos: 'Entrar na conta; abrir Favoritos',
    esperado: 'O posto salvo sem conta aparece, com o sino de avisos',
    severidade: alta,
    corpo: () async {
      await qa.esperar(find.byType(CartaoPosto), limite: const Duration(seconds: 20));
      await qa.esperar(find.byTooltip('Desligar avisos de preço'));
      return '${_cartoes(qa).length} favorito(s) na conta';
    },
  );
  await qa.caso(
    modulo: 'Favoritos',
    tela: 'Favoritos',
    tipo: 'Funcional · botão',
    cenario: 'Sino desliga e liga os avisos de preço do posto',
    passos: 'Tocar no sino; tocar de novo',
    esperado: '"Avisos desligados para este posto." e depois "Você será avisado quando o preço mudar."',
    capturar: false,
    corpo: () async {
      await qa.tocar(find.byTooltip('Desligar avisos de preço'));
      await qa.esperarMensagem('Avisos desligados');
      await qa.tocar(find.byTooltip('Ligar avisos de preço'), limite: const Duration(seconds: 20));
      return qa.esperarMensagem('Você será avisado');
    },
  );
}

Future<void> _sairEEntrarDeNovo(Qa qa) async {
  await qa.irPara('/perfil');
  await qa.caso(
    modulo: 'Conta',
    tela: 'Perfil',
    tipo: 'Funcional · botão',
    cenario: 'Sair da conta volta ao perfil de visitante',
    passos: 'Perfil → Sair da conta',
    esperado: '"Você saiu da conta." e a tela "Contribua com a sua cidade"',
    severidade: alta,
    corpo: () async {
      await qa.tocar(find.text('Sair da conta'));
      final m = await qa.esperarMensagem('saiu da conta');
      await qa.esperar(find.text('Contribua com a sua cidade'));
      return m;
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Entrar',
    tipo: 'Funcional · positivo',
    cenario: 'Entrar com a senha nova depois de alterá-la',
    passos: 'Perfil → Entrar → e-mail e senha nova',
    esperado: '"Bem-vindo de volta!"',
    severidade: alta,
    corpo: () async {
      await qa.tocar(find.widgetWithText(OutlinedButton, 'Entrar'));
      await qa.escrever(_campo('E-mail'), qaEmail);
      await qa.escrever(_campo('Senha'), qaSenhaNova);
      await qa.tocar(find.widgetWithText(FilledButton, 'Entrar'));
      return qa.esperarMensagem('Bem-vindo', limite: const Duration(seconds: 25));
    },
  );
}

Future<void> _excluirConta(Qa qa) async {
  await qa.irPara('/perfil');
  await qa.caso(
    modulo: 'Conta',
    tela: 'Excluir conta',
    tipo: 'Regra · confirmação',
    cenario: 'Excluir conta só libera o botão depois de digitar EXCLUIR',
    passos: 'Perfil → Excluir minha conta; olhar o botão; digitar EXCLUIR',
    esperado: 'Botão "Excluir conta" desativado até digitar EXCLUIR',
    corpo: () async {
      await qa.tocar(find.text('Excluir minha conta'), limite: const Duration(seconds: 20));
      final botao = find.widgetWithText(FilledButton, 'Excluir conta');
      await qa.esperar(botao);
      confirmar(qa.t.widget<FilledButton>(botao).onPressed == null, 'Botão ativo antes de digitar');
      await qa.escrever(find.widgetWithText(TextField, 'Digite EXCLUIR para confirmar'), 'excluir');
      confirmar(qa.t.widget<FilledButton>(botao).onPressed != null, 'Botão continuou desativado');
      return 'Botão liberado só depois de digitar';
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Excluir conta',
    tipo: 'Funcional · positivo',
    cenario: 'Excluir a conta de teste pelo app',
    passos: 'Tocar em Excluir conta',
    esperado: '"Conta excluída." e o app volta ao mapa sem conta',
    severidade: alta,
    corpo: () async {
      await qa.tocar(find.widgetWithText(FilledButton, 'Excluir conta'));
      final m = await qa.esperarMensagem('Conta excluída', limite: const Duration(seconds: 30));
      await qa.esperar(find.text('Buscar posto ou endereço'));
      return m;
    },
  );
  await qa.caso(
    modulo: 'Conta',
    tela: 'Entrar',
    tipo: 'Funcional · negativo',
    cenario: 'Conta excluída não entra mais',
    passos: 'Entrar com o e-mail e a senha da conta excluída',
    esperado: '"E-mail ou senha incorretos."',
    corpo: () async {
      await qa.irPara('/entrar');
      await qa.escrever(_campo('E-mail'), qaEmail);
      await qa.escrever(_campo('Senha'), qaSenhaNova);
      await qa.tocar(find.widgetWithText(FilledButton, 'Entrar'));
      return qa.esperarMensagem('incorretos', limite: const Duration(seconds: 25));
    },
  );
}
