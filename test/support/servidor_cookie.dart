import 'dart:convert';

import 'package:app_estudiantes/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'servidor_falso.dart';

/// API simulada de CONTRATO_AUTH §6.3 (refresh en cookie). Como en el
/// navegador, la "cookie" solo existe si la petición llega con
/// `X-Refresh-En-Cookie: 1` **y** por el cliente con credenciales.
class ServidorCookie {
  /// `canal MÉTODO ruta cabecera cuerpo`, con canal `cred` (con credenciales)
  /// o `normal`.
  final registro = <String>[];

  /// El refresh que guarda el navegador en la cookie (`null`: no hay).
  String? cookie;

  /// Refresh válidos en el servidor (los de cookie y los del cuerpo).
  final _validos = <String>{};
  final _access = <String>{};
  int _n = 0;

  /// [conCredenciales]: si se monta el segundo cliente (como en la web).
  ApiService api({bool conCredenciales = true}) => ApiService(
    baseUrl: 'http://api.test',
    client: MockClient((p) => _atender(p, cred: false)),
    clienteConCredenciales: conCredenciales
        ? MockClient((p) => _atender(p, cred: true))
        : null,
  );

  Future<http.Response> _atender(http.Request p, {required bool cred}) async {
    final ruta = p.url.path;
    final enCookie = p.headers['X-Refresh-En-Cookie'] == '1';
    registro.add(
      '${cred ? 'cred' : 'normal'} ${p.method} $ruta'
      '${enCookie ? ' X-Refresh-En-Cookie' : ''}'
      '${p.body.isEmpty ? '' : ' ${p.body}'}',
    );
    final cuerpo = p.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(p.body) as Map<String, Object?>;
    // Solo con las dos cosas la cookie viaja (y se guarda).
    final usaCookie = enCookie && cred;
    switch (ruta) {
      case '/auth/login' || '/passkeys/login/verificacion':
        return _emitir(usaCookie);
      case '/passkeys/login/opciones':
        return ServidorFalso.json({
          'reto_id': 'r1',
          'opciones': {'rpId': 'buelvasmanuel.github.io', 'challenge': 'x'},
        });
      case '/auth/refresh':
        final refresh =
            cuerpo['refresh_token'] as String? ?? (usaCookie ? cookie : null);
        if (refresh == null || !_validos.remove(refresh)) {
          if (usaCookie) cookie = null; // un refresh rechazado borra la cookie
          return ServidorFalso.error(401, 'refresh_invalido');
        }
        return _emitir(usaCookie);
      case '/auth/logout':
        final refresh =
            cuerpo['refresh_token'] as String? ?? (usaCookie ? cookie : null);
        _validos.remove(refresh);
        if (usaCookie) cookie = null;
        return http.Response('', 204);
    }
    final autorizado = _access.contains(
      (p.headers['Authorization'] ?? '').replaceFirst('Bearer ', ''),
    );
    if (!autorizado) return ServidorFalso.error(401, 'token_expirado');
    return ServidorFalso.json({'ok': true});
  }

  http.Response _emitir(bool enCookie) {
    final n = ++_n;
    final refresh = 'refresh-$n';
    _validos.add(refresh);
    _access.add('access-$n');
    if (enCookie) cookie = refresh;
    return ServidorFalso.json({
      'access_token': 'access-$n',
      'token_type': 'bearer',
      'expires_in': 900,
      'refresh_token': enCookie ? null : refresh,
      'refresh_expires_in': 1209600,
      'usuario': {'id': 7, 'alias': 'Detective_Ana', 'rol': 'jugador'},
    });
  }
}
