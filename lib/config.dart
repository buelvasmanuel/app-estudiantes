import 'package:flutter/foundation.dart';

/// Configuración global de la app.
///
/// La URL de la API se puede fijar al compilar:
///
/// ```bash
/// flutter run --dart-define=API_URL=http://192.168.1.50:8000
/// ```
///
/// `String.fromEnvironment` se resuelve en tiempo de COMPILACIÓN (por eso es
/// `const`): si cambias el valor, hay que volver a lanzar `flutter run`; el
/// hot reload no basta.
abstract final class Config {
  static const String _apiUrlDefine = String.fromEnvironment('API_URL');

  /// Tiempo máximo de espera de cada petición antes de dar error.
  static const Duration timeout = Duration(seconds: 8);

  /// URL base de la API, sin la barra final.
  static String get apiUrl {
    final url = _apiUrlDefine.isNotEmpty ? _apiUrlDefine : _urlPorDefecto;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// - Emulador de Android: `10.0.2.2` es la dirección especial que apunta al
  ///   PC anfitrión (dentro del emulador, `127.0.0.1` es el propio emulador).
  /// - Linux, Chrome, etc.: la API está en la misma máquina.
  ///
  /// Se comprueba `kIsWeb` ANTES que la plataforma: en el navegador de un
  /// celular Android `defaultTargetPlatform` también vale `android`, pero ahí
  /// no hay emulador. (Y no usamos `dart:io` `Platform`, que no existe en web.)
  static String get _urlPorDefecto {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}
