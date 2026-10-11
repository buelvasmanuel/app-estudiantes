import 'dart:convert';

import 'package:app_estudiantes/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// API simulada que se comporta como `docs/CONTRATO_AUTH.md` (repo
/// `api-tienda`), con una sola sesión a la vez para simplificar.
///
/// - [publicas]: ruta → JSON, sin autenticación.
/// - [protegidas]: ruta → JSON (o `http.Response`), exigen un access válido.
class ServidorFalso {
  ServidorFalso({
    Map<String, Object?>? publicas,
    Map<String, Object?>? protegidas,
  }) : publicas = {...?publicas},
       protegidas = {...?protegidas};

  final Map<String, Object?> publicas;
  final Map<String, Object?> protegidas;

  /// `'POST /auth/refresh'`, `'GET /protegido'`... en orden de llegada.
  final registro = <String>[];

  final usuarios = <String, String>{'Detective_Ana': 'una frase larga'};

  /// Simula que no hay red: toda petición falla sin respuesta.
  bool sinRed = false;

  /// Cuántos `POST /auth/refresh` seguidos fallarán por red.
  int fallosDeRedEnRefresh = 0;

  /// Lo que tarda en llegar la respuesta de `POST /auth/refresh` (el
  /// servidor ya ha rotado el token).
  Duration demoraRefresh = Duration.zero;

  /// Si no es `null`, login y registro responden 429 con este Retry-After.
  int? limiteAlcanzado;

  final _accessValidos = <String>{};
  String? refreshVigente;
  final _refreshUsados = <String>{};
  int _contador = 0;

  ApiService api() =>
      ApiService(baseUrl: 'http://api.test', client: MockClient(_atender));

  /// El access deja de valer en el servidor (caducado o clave cambiada).
  void caducarAccess() => _accessValidos.clear();

  /// Un admin (o la detección de reuso) cierra la sesión.
  void revocarSesion() {
    if (refreshVigente case final r?) _refreshUsados.add(r);
    refreshVigente = null;
    _accessValidos.clear();
  }

  /// Emite una sesión sin pasar por el login (como si viniera de antes).
  String sesionPrevia() {
    final refresh = 'refresh-${++_contador}';
    refreshVigente = refresh;
    return refresh;
  }

  Future<http.Response> _atender(http.Request peticion) async {
    final ruta = peticion.url.path;
    registro.add('${peticion.method} $ruta');
    if (sinRed) throw http.ClientException('Sin red', peticion.url);
    final cuerpo = peticion.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(peticion.body) as Map<String, Object?>;

    switch (ruta) {
      case '/auth/login' || '/auth/registro' when limiteAlcanzado != null:
        return error(429, 'demasiados_intentos', retryAfter: limiteAlcanzado);
      case '/auth/login':
        final alias = cuerpo['alias'];
        if (usuarios[alias] != cuerpo['password']) {
          return error(401, 'credenciales_invalidas');
        }
        return _emitir(alias! as String);
      case '/auth/registro':
        final alias = cuerpo['alias']! as String;
        if (usuarios.keys.any((u) => u.toLowerCase() == alias.toLowerCase())) {
          return error(409, 'alias_en_uso');
        }
        usuarios[alias] = cuerpo['password']! as String;
        return _emitir(alias, status: 201);
      case '/auth/refresh':
        if (fallosDeRedEnRefresh > 0) {
          fallosDeRedEnRefresh--;
          throw http.ClientException('Sin red', peticion.url);
        }
        final refresh = cuerpo['refresh_token'];
        if (refresh != null && refresh == refreshVigente) {
          _refreshUsados.add(refresh as String);
          final respuesta = _emitir('Detective_Ana');
          // Ya rotó en el servidor; la respuesta tarda en llegar.
          await Future<void>.delayed(demoraRefresh);
          return respuesta;
        }
        if (_refreshUsados.contains(refresh)) {
          revocarSesion(); // reuso: se cierra la sesión entera
          return error(401, 'sesion_revocada');
        }
        return error(401, 'refresh_invalido');
      case '/auth/logout':
        if (cuerpo['refresh_token'] == refreshVigente) revocarSesion();
        return http.Response('', 204);
      case '/auth/logout-todo':
        if (!_autenticada(peticion)) return error(401, 'token_expirado');
        revocarSesion();
        return http.Response('', 204);
    }

    if (protegidas.containsKey(ruta)) {
      if (peticion.headers['Authorization'] == null) {
        return error(401, 'no_autenticado');
      }
      if (!_autenticada(peticion)) return error(401, 'token_expirado');
      return _responder(protegidas[ruta]);
    }
    if (publicas.containsKey(ruta)) return _responder(publicas[ruta]);
    throw http.ClientException('Connection refused', peticion.url);
  }

  bool _autenticada(http.Request peticion) {
    final cabecera = peticion.headers['Authorization'] ?? '';
    return cabecera.startsWith('Bearer ') &&
        _accessValidos.contains(cabecera.substring(7));
  }

  http.Response _emitir(String alias, {int status = 200}) {
    final n = ++_contador;
    final access = 'v4.local.access-$n';
    final refresh = 'refresh-$n';
    _accessValidos.add(access);
    refreshVigente = refresh;
    return json({
      'access_token': access,
      'token_type': 'bearer',
      'expires_in': 900,
      'refresh_token': refresh,
      'refresh_expires_in': 1209600,
      'usuario': {'id': 7, 'alias': alias, 'rol': 'jugador'},
    }, status);
  }

  static http.Response _responder(Object? cuerpo) =>
      cuerpo is http.Response ? cuerpo : json(cuerpo);

  static http.Response json(
    Object? cuerpo, [
    int status = 200,
    Map<String, String> cabeceras = const {},
  ]) => http.Response.bytes(
    utf8.encode(jsonEncode(cuerpo)),
    status,
    headers: {'content-type': 'application/json', ...cabeceras},
  );

  /// Un error con el formato del contrato (§2).
  static http.Response error(int status, String codigo, {int? retryAfter}) =>
      json(
        {
          'detail': {'codigo': codigo, 'mensaje': 'Mensaje de $codigo'},
        },
        status,
        {
          if (status == 401) 'www-authenticate': 'Bearer',
          if (retryAfter != null) 'retry-after': '$retryAfter',
        },
      );
}
