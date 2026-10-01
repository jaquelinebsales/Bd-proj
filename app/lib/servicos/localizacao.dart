import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config.dart';

enum EstadoLocalizacao { desconhecido, permitida, negada, negadaSempre, desligada }

/// Localização do aparelho, pedida só com autorização do usuário.
class Localizacao extends ChangeNotifier {
  Localizacao._();
  static final instancia = Localizacao._();

  Position? atual;
  EstadoLocalizacao estado = EstadoLocalizacao.desconhecido;

  /// Pede permissão (se preciso) e obtém a posição. Retorna null se não for possível.
  Future<Position?> obter({bool pedirPermissao = true, bool precisa = false}) async {
    if (Config.demo) {
      // Modo demonstração: ao lado do Posto Vale Verde, em Fortaleza
      estado = EstadoLocalizacao.permitida;
      atual = Position(
        latitude: -3.7627, longitude: -38.5399, timestamp: DateTime.now(), accuracy: 10, altitude: 0,
        altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
      );
      notifyListeners();
      return atual;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        estado = EstadoLocalizacao.desligada;
        notifyListeners();
        return null;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && pedirPermissao) p = await Geolocator.requestPermission();
      if (p == LocationPermission.deniedForever) {
        estado = EstadoLocalizacao.negadaSempre;
        notifyListeners();
        return null;
      }
      if (p == LocationPermission.denied) {
        estado = EstadoLocalizacao.negada;
        notifyListeners();
        return null;
      }
      estado = EstadoLocalizacao.permitida;
      atual = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: precisa ? LocationAccuracy.best : LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        ),
      );
      notifyListeners();
      return atual;
    } catch (_) {
      return atual;
    }
  }

  Future<void> abrirConfiguracoes() async {
    if (estado == EstadoLocalizacao.desligada) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  /// Distância em km até um ponto, se a posição for conhecida.
  double? distanciaKm(double? lat, double? lon) {
    if (atual == null || lat == null || lon == null) return null;
    return Geolocator.distanceBetween(atual!.latitude, atual!.longitude, lat, lon) / 1000;
  }
}
