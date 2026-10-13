import 'dart:convert';

import 'package:app_estudiantes/passkeys/navegador.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'juego_falso.dart';
import 'servidor_falso.dart';

/// Un navegador simulado: [soportado] y qué pasa al crear u obtener (una
/// credencial o una excepción como [PasskeyCancelada]).
class NavegadorFalso extends NavegadorPasskeys {
  NavegadorFalso({this.soportado = true});

  @override
  final bool soportado;

  /// Lo próximo que pasará (null: devuelve una credencial).
  Exception? fallo;

  /// Opciones recibidas, en orden.
  final opciones = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> crear(Map<String, Object?> o) async {
    opciones.add(o);
    if (fallo case final f?) throw f;
    return {
      'id': 'cred-nueva',
      'type': 'public-key',
      'response': {'attestationObject': 'ao', 'clientDataJSON': 'cd'},
    };
  }

  @override
  Future<Map<String, Object?>> obtener(Map<String, Object?> o) async {
    opciones.add(o);
    if (fallo case final f?) throw f;
    return {
      'id': 'cred-1',
      'type': 'public-key',
      'response': {'signature': 'sig', 'clientDataJSON': 'cd'},
    };
  }
}

Map<String, Object?> passkeyJson(
  int id,
  String nombre, {
  String? ultimoUso,
  bool sincronizada = true,
}) => {
  'id': id,
  'nombre': nombre,
  'creada_en': '2026-10-12T15:00:00Z',
  'ultimo_uso': ultimoUso,
  'sincronizada': sincronizada,
};

/// API simulada de CONTRATO_PASSKEYS (más el login con contraseña y el resto
/// del juego de [JuegoFalso]).
class PasskeysFalso {
  final juego = JuegoFalso();

  /// `MÉTODO ruta cuerpo` de las peticiones de auth y passkeys.
  final registro = <String>[];

  final passkeys = <Map<String, Object?>>[
    passkeyJson(1, 'Portátil de casa', ultimoUso: '2026-10-13T08:00:00Z'),
  ];

  /// Código de error que darán las verificaciones (login o registro).
  String? falloVerificacion;

  int _retos = 0;
  int _ids = 1;

  ApiService api() =>
      ApiService(baseUrl: 'http://api.test', client: MockClient(_atender));

  Future<http.Response> _atender(http.Request p) async {
    final ruta = p.url.path;
    if (!ruta.startsWith('/auth') && !ruta.startsWith('/passkeys')) {
      return juego.atender(p);
    }
    registro.add('${p.method} $ruta${p.body.isEmpty ? '' : ' ${p.body}'}');
    final cuerpo = p.body.isEmpty || p.body == 'null'
        ? const <String, Object?>{}
        : jsonDecode(p.body) as Map<String, Object?>;
    final conSesion = (p.headers['Authorization'] ?? '').startsWith('Bearer ');
    switch ((p.method, ruta)) {
      case ('POST', '/auth/login'):
        return cuerpo['password'] == 'una frase larga'
            ? _tokens()
            : ServidorFalso.error(401, 'credenciales_invalidas');
      case ('POST', '/auth/logout'):
        return http.Response('', 204);
      case ('POST', '/passkeys/login/opciones'):
        return ServidorFalso.json({
          'reto_id': 'reto-${++_retos}',
          'opciones': {
            'rpId': 'buelvasmanuel.github.io',
            'challenge': 'desafio',
            'timeout': 60000,
            'userVerification': 'required',
            'allowCredentials': <Object>[],
          },
        });
      case ('POST', '/passkeys/login/verificacion'):
        if (falloVerificacion case final c?) {
          return ServidorFalso.error(c == 'cuenta_desactivada' ? 403 : 401, c);
        }
        return _tokens();
    }
    if (!conSesion) return ServidorFalso.error(401, 'no_autenticado');
    switch ((p.method, ruta)) {
      case ('POST', '/passkeys/registro/opciones'):
        return ServidorFalso.json({
          'reto_id': 'reto-${++_retos}',
          'opciones': {
            'rp': {'id': 'buelvasmanuel.github.io', 'name': 'Estudiantes'},
            'user': {'id': 'u7', 'name': 'Detective_Ana'},
            'challenge': 'desafio',
            'excludeCredentials': <Object>[],
          },
        });
      case ('POST', '/passkeys/registro/verificacion'):
        if (falloVerificacion case final c?) {
          return ServidorFalso.error(c == 'passkey_repetida' ? 409 : 422, c);
        }
        final nueva = passkeyJson(
          ++_ids,
          (cuerpo['nombre'] as String?) ?? 'Passkey',
          sincronizada: false,
        );
        passkeys.insert(0, nueva);
        return ServidorFalso.json(nueva, 201);
      case ('GET', '/passkeys'):
        return ServidorFalso.json(passkeys);
    }
    if (p.method == 'DELETE' && ruta.startsWith('/passkeys/')) {
      final id = int.parse(ruta.split('/').last);
      final antes = passkeys.length;
      passkeys.removeWhere((k) => k['id'] == id);
      return passkeys.length < antes
          ? http.Response('', 204)
          : ServidorFalso.error(404, 'passkey_no_encontrada');
    }
    throw http.ClientException('Ruta no simulada', p.url);
  }

  http.Response _tokens() => ServidorFalso.json({
    'access_token': 'v4.local.access',
    'token_type': 'bearer',
    'expires_in': 900,
    'refresh_token': 'refresh-1',
    'refresh_expires_in': 1209600,
    'usuario': {'id': 7, 'alias': 'Detective_Ana', 'rol': 'jugador'},
  });
}
