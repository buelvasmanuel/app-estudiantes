import 'json_utils.dart';

/// Roles de la API (`docs/CONTRATO_AUTH.md` en `api-tienda`).
enum Rol {
  jugador,
  docente,
  admin;

  static Rol desde(String texto) => switch (texto) {
    'jugador' => jugador,
    'docente' => docente,
    'admin' => admin,
    _ => throw FormatException('Rol desconocido', texto),
  };
}

/// `UsuarioOut`: `{"id": 7, "alias": "Detective_Ana", "rol": "jugador"}`.
class Usuario {
  const Usuario({required this.id, required this.alias, required this.rol});

  final int id;
  final String alias;
  final Rol rol;

  factory Usuario.fromJson(Object? json) {
    final m = comoMapa(json, 'usuario');
    return Usuario(
      id: leerInt(m, 'id'),
      alias: leerString(m, 'alias'),
      rol: Rol.desde(leerString(m, 'rol')),
    );
  }
}

/// `TokensOut`: la respuesta de registro, login, refresh y cambio de
/// contraseña.
///
/// El access token es opaco (PASETO cifrado): la app no lo decodifica. Su
/// caducidad se calcula con `expires_in` y la hora en que llegó.
class Tokens {
  const Tokens({
    required this.access,
    required this.accessCaduca,
    required this.refresh,
    required this.usuario,
  });

  final String access;
  final DateTime accessCaduca;

  /// `null` en el modo cookie de la web (CONTRATO_AUTH §6.3): el refresh
  /// queda en una cookie HttpOnly que la app no puede leer.
  final String? refresh;
  final Usuario usuario;

  /// [recibido] es la hora local en que llegó la respuesta.
  factory Tokens.fromJson(Object? json, {required DateTime recibido}) {
    final m = comoMapa(json, 'respuesta de sesión');
    return Tokens(
      access: leerString(m, 'access_token'),
      accessCaduca: recibido.add(Duration(seconds: leerInt(m, 'expires_in'))),
      refresh: m['refresh_token'] is String
          ? m['refresh_token']! as String
          : null,
      usuario: Usuario.fromJson(m['usuario']),
    );
  }
}
