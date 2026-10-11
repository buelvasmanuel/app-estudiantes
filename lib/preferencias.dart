import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tema/temas.dart';

/// Preferencias guardadas en el dispositivo (también en la web, donde
/// `shared_preferences` usa `localStorage`). Nada secreto: el refresh token
/// va en `AlmacenRefresh`.
abstract class Preferencias {
  String? texto(String clave);
  bool? booleano(String clave);
  Future<void> guardarTexto(String clave, String valor);
  Future<void> guardarBooleano(String clave, bool valor);

  static const claveTema = 'tema';
  static const claveSonidos = 'sonidos';
  static const claveTutorial = 'tutorial_visto';
}

class PreferenciasDispositivo implements Preferencias {
  PreferenciasDispositivo._(this._prefs);

  final SharedPreferencesWithCache _prefs;

  /// Se abre una vez en `main()`, antes de la app: después todo se lee al
  /// instante (sin parpadeo de tema al arrancar).
  static Future<PreferenciasDispositivo> abrir() async =>
      PreferenciasDispositivo._(
        await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(
            allowList: {
              Preferencias.claveTema,
              Preferencias.claveSonidos,
              Preferencias.claveTutorial,
            },
          ),
        ),
      );

  @override
  String? texto(String clave) => _prefs.getString(clave);

  @override
  bool? booleano(String clave) => _prefs.getBool(clave);

  @override
  Future<void> guardarTexto(String clave, String valor) =>
      _prefs.setString(clave, valor);

  @override
  Future<void> guardarBooleano(String clave, bool valor) =>
      _prefs.setBool(clave, valor);
}

/// Para los tests (y como respaldo si el almacenamiento falla).
class PreferenciasEnMemoria implements Preferencias {
  PreferenciasEnMemoria([Map<String, Object>? iniciales])
    : valores = {...?iniciales};

  final Map<String, Object> valores;

  @override
  String? texto(String clave) => valores[clave] as String?;

  @override
  bool? booleano(String clave) => valores[clave] as bool?;

  @override
  Future<void> guardarTexto(String clave, String valor) async =>
      valores[clave] = valor;

  @override
  Future<void> guardarBooleano(String clave, bool valor) async =>
      valores[clave] = valor;
}

/// Se inyecta en `main()` (y en los tests) con `overrideWithValue`.
final preferenciasProvider = Provider<Preferencias>(
  (ref) => PreferenciasEnMemoria(),
);

/// El tema del juego. La primera vez sigue al sistema (oscuro → Noche,
/// claro → Expediente); en cuanto el jugador elige, se recuerda.
class TemaNotifier extends Notifier<TemaJuego> {
  @override
  TemaJuego build() {
    final guardado = ref
        .watch(preferenciasProvider)
        .texto(Preferencias.claveTema);
    return TemaJuego.values.where((t) => t.name == guardado).firstOrNull ??
        TemaJuego.delSistema(
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
        );
  }

  void elegir(TemaJuego tema) {
    state = tema;
    ref
        .read(preferenciasProvider)
        .guardarTexto(Preferencias.claveTema, tema.name);
  }

  void alternar() =>
      elegir(state == TemaJuego.noche ? TemaJuego.expediente : TemaJuego.noche);
}

final temaProvider = NotifierProvider<TemaNotifier, TemaJuego>(
  TemaNotifier.new,
);

/// Sonidos: apagados por defecto en web y móvil.
class SonidosNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(preferenciasProvider).booleano(Preferencias.claveSonidos) ??
      false;

  void activar(bool activos) {
    state = activos;
    ref
        .read(preferenciasProvider)
        .guardarBooleano(Preferencias.claveSonidos, activos);
  }
}

final sonidosActivosProvider = NotifierProvider<SonidosNotifier, bool>(
  SonidosNotifier.new,
);

/// El tutorial del búho se ve una vez por dispositivo.
class TutorialNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(preferenciasProvider).booleano(Preferencias.claveTutorial) ??
      false;

  void marcar(bool visto) {
    state = visto;
    ref
        .read(preferenciasProvider)
        .guardarBooleano(Preferencias.claveTutorial, visto);
  }
}

final tutorialVistoProvider = NotifierProvider<TutorialNotifier, bool>(
  TutorialNotifier.new,
);
