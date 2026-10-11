import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dónde se guarda el refresh token entre una ejecución y otra.
abstract class AlmacenRefresh {
  Future<String?> leer();
  Future<void> guardar(String refresh);
  Future<void> borrar();

  /// Android, Windows, Linux: almacén seguro del sistema. Web: solo memoria.
  ///
  /// En el navegador no hay un almacén realmente seguro, y `localStorage` /
  /// `sessionStorage` se leen desde JavaScript (y `sessionStorage` se copia
  /// al duplicar una pestaña, lo que dispararía la detección de reuso). Por
  /// eso en la web recargar la página obliga a iniciar sesión de nuevo.
  factory AlmacenRefresh.dePlataforma() =>
      kIsWeb ? AlmacenEnMemoria() : AlmacenSeguro();
}

/// Keystore (Android), libsecret (Linux) o DPAPI (Windows).
class AlmacenSeguro implements AlmacenRefresh {
  AlmacenSeguro([this._almacen = const FlutterSecureStorage()]);

  final FlutterSecureStorage _almacen;
  static const _clave = 'refresh_token';

  @override
  Future<String?> leer() => _almacen.read(key: _clave);

  @override
  Future<void> guardar(String refresh) =>
      _almacen.write(key: _clave, value: refresh);

  @override
  Future<void> borrar() => _almacen.delete(key: _clave);
}

/// Se pierde al cerrar la app. Para la web y para los tests.
class AlmacenEnMemoria implements AlmacenRefresh {
  AlmacenEnMemoria([this._refresh]);

  String? _refresh;

  @override
  Future<String?> leer() async => _refresh;

  @override
  Future<void> guardar(String refresh) async => _refresh = refresh;

  @override
  Future<void> borrar() async => _refresh = null;
}
