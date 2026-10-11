import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preferencias.dart';

/// Sonidos cortos del juego (CC0, ver assets/sonidos/LICENCIA.txt).
enum Sonido {
  acierto('sonidos/acierto.mp3'),
  pista('sonidos/pista.mp3'),
  ficha('sonidos/ficha.mp3'),
  rescate('sonidos/rescate.mp3'),
  celebracion('sonidos/celebracion.mp3');

  const Sonido(this.recurso);

  /// Ruta dentro de `assets/` (como la espera `AssetSource`).
  final String recurso;
}

/// Quién reproduce de verdad. Los tests usan uno que solo anota.
abstract class Reproductor {
  Future<void> reproducir(Sonido sonido);
}

class ReproductorAudio implements Reproductor {
  final _jugadores = <Sonido, AudioPlayer>{};

  @override
  Future<void> reproducir(Sonido sonido) async {
    try {
      final jugador = _jugadores[sonido] ??= AudioPlayer()
        ..setReleaseMode(ReleaseMode.stop);
      await jugador.stop();
      await jugador.play(AssetSource(sonido.recurso), volume: 0.6);
    } on Object catch (e) {
      // El sonido es opcional: nunca debe romper el juego.
      debugPrint('Sonido ${sonido.name} no disponible: $e');
    }
  }

  void liberar() {
    for (final j in _jugadores.values) {
      j.dispose();
    }
    _jugadores.clear();
  }
}

final reproductorProvider = Provider<Reproductor>((ref) {
  final r = ReproductorAudio();
  ref.onDispose(r.liberar);
  return r;
});

/// Suena solo si el jugador activó los sonidos (Perfil o tutorial).
class Sonidos {
  const Sonidos(this._ref);

  final Ref _ref;

  void tocar(Sonido sonido) {
    if (_ref.read(sonidosActivosProvider)) {
      _ref.read(reproductorProvider).reproducir(sonido);
    }
  }
}

final sonidosProvider = Provider<Sonidos>(Sonidos.new);
