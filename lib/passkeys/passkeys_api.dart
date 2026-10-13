import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/api_service.dart';
import 'modelo.dart';
import 'navegador.dart';

/// docs/CONTRATO_PASSKEYS.md (api-tienda): registrar, entrar, listar y
/// borrar passkeys. Solo web.
class PasskeysApi {
  const PasskeysApi(this._api, this._navegador);

  final ApiService _api;
  final NavegadorPasskeys _navegador;

  /// Crea una passkey en este dispositivo y la registra (con sesión).
  Future<Passkey> crear({String? nombre}) async {
    final o = _api.parsear(
      await _api.post('/passkeys/registro/opciones', null),
      opcionesPasskey,
    );
    final credencial = await _navegador.crear(o.opciones);
    return _api.parsear(
      await _api.post('/passkeys/registro/verificacion', {
        'reto_id': o.retoId,
        'credencial': credencial,
        if (nombre != null && nombre.trim().isNotEmpty) 'nombre': nombre.trim(),
      }),
      Passkey.fromJson,
    );
  }

  Future<List<Passkey>> listar() async =>
      _api.parsear(await _api.get('/passkeys'), Passkey.lista);

  Future<void> borrar(int id) => _api.delete('/passkeys/$id');

  /// Entrar sin sesión: el navegador ofrece las passkeys de este dominio y
  /// devuelve el `TokensOut` (lo aplica la sesión). Endpoints públicos: sin
  /// interceptor. [preparar] añade lo del modo cookie a la verificación
  /// (CONTRATO_PASSKEYS v1.1, CONTRATO_AUTH §6.3).
  Future<Object?> entrar({
    PeticionApi Function(PeticionApi peticion)? preparar,
  }) async {
    final o = _api.parsear(
      await _api.enviar(
        PeticionApi(
          'POST',
          '/passkeys/login/opciones',
          conInterceptores: false,
        ),
      ),
      opcionesPasskey,
    );
    final credencial = await _navegador.obtener(o.opciones);
    final verificacion = PeticionApi(
      'POST',
      '/passkeys/login/verificacion',
      cuerpo: {'reto_id': o.retoId, 'credencial': credencial},
      conInterceptores: false,
    );
    return _api.enviar(preparar?.call(verificacion) ?? verificacion);
  }
}

/// `true` solo en la web: en el APK y en el escritorio no hay passkeys.
final esWebProvider = Provider<bool>((ref) => kIsWeb);

final navegadorPasskeysProvider = Provider<NavegadorPasskeys>(
  (ref) => navegadorDelSistema(),
);

/// Se ofrecen passkeys: web y navegador compatible.
final passkeysDisponiblesProvider = Provider<bool>(
  (ref) =>
      ref.watch(esWebProvider) &&
      ref.watch(navegadorPasskeysProvider).soportado,
);

final passkeysApiProvider = Provider<PasskeysApi>(
  (ref) => PasskeysApi(
    ref.watch(apiServiceProvider),
    ref.watch(navegadorPasskeysProvider),
  ),
);

/// Las passkeys del jugador (se rehacen al cambiar de cuenta).
final misPasskeysProvider = FutureProvider<List<Passkey>>((ref) {
  if (ref.watch(usuarioIdProvider) == null) {
    throw const ApiException('Inicia sesión para ver tus passkeys.');
  }
  return ref.watch(passkeysApiProvider).listar();
});
