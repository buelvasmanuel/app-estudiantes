import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/sesion.dart';
import 'almacen_refresh.dart';
import 'api_service.dart';

enum EstadoSesion {
  /// Al arrancar: comprobando si hay un refresh guardado y si sigue valiendo.
  restaurando,
  sinSesion,
  conSesion,
}

/// La sesión del usuario: login, registro, logout y renovación de tokens.
///
/// Implementa el §6 de `docs/CONTRATO_AUTH.md` (repo `api-tienda`):
///
/// - Es un [InterceptorApi]: añade `Authorization: Bearer <access>` a cada
///   petición, renueva el access si le queda menos de [margen], y ante un 401
///   de token renueva y repite la petición una sola vez.
/// - **Un solo refresh en curso**: si varias peticiones necesitan renovar a la
///   vez, todas esperan al mismo `Future`. Con refresh tokens rotativos, dos
///   renovaciones en paralelo con el mismo token se tomarían por un robo.
/// - Guarda el refresh nuevo ANTES de usar el access nuevo.
///
/// Es un [ChangeNotifier]: el router lo escucha para llevar al login cuando
/// la sesión se cierra.
class GestorSesion extends InterceptorApi with ChangeNotifier {
  GestorSesion({
    required this._api,
    required this._almacen,
    DateTime Function()? ahora,
    Tokens? tokens,
  }) : _ahora = ahora ?? DateTime.now,
       _tokens = tokens,
       _estado = tokens == null
           ? EstadoSesion.restaurando
           : EstadoSesion.conSesion;

  final ApiService _api;
  final AlmacenRefresh _almacen;
  final DateTime Function() _ahora;

  Tokens? _tokens;
  EstadoSesion _estado;
  ApiException? _errorAlRestaurar;
  String? _aviso;
  Future<void>? _renovacion;

  /// Cambia cada vez que la sesión se cierra. Una renovación que empezó antes
  /// de cerrar no debe volver a abrirla al terminar.
  int _generacion = 0;

  /// Si al access le queda menos que esto, se renueva antes de enviar.
  static const margen = Duration(seconds: 60);

  /// `/auth/*` puede despertar a Render: siempre 60 s.
  static const limiteAuth = Config.timeoutArranque;

  /// Errores 401 que se arreglan renovando el access (§2 del contrato).
  static const _codigosRenovables = {
    'no_autenticado',
    'token_expirado',
    'token_invalido',
    'sesion_cerrada',
  };

  static const avisoRevocada =
      'Tu sesión se cerró por seguridad. Vuelve a iniciar sesión.';
  static const avisoCaducada = 'Tu sesión caducó. Vuelve a iniciar sesión.';
  static const avisoNoValida =
      'Tu sesión ya no es válida. Vuelve a iniciar sesión.';
  static const avisoTodas = 'Cerraste la sesión en todos los dispositivos.';

  EstadoSesion get estado => _estado;
  Usuario? get usuario => _tokens?.usuario;

  /// Si al arrancar no se pudo comprobar la sesión (sin red, servidor caído).
  /// Los tokens se conservan: basta con [restaurar] de nuevo.
  ApiException? get errorAlRestaurar => _errorAlRestaurar;

  /// Por qué se cerró la sesión, para mostrarlo en la pantalla de login.
  String? get aviso => _aviso;

  // --- Acciones del usuario --------------------------------------------------

  /// Recupera la sesión guardada (móvil y escritorio) al arrancar.
  Future<void> restaurar() async {
    _cambiar(EstadoSesion.restaurando, error: null);
    final refresh = await _almacen.leer();
    if (refresh == null) {
      _cambiar(EstadoSesion.sinSesion);
      return;
    }
    try {
      await _renovar();
    } on ApiException catch (e) {
      // Si la API rechazó el refresh, _renovar ya cerró la sesión. Si no hubo
      // respuesta, se queda en "restaurando" con el error y Reintentar.
      if (_estado == EstadoSesion.restaurando) {
        _cambiar(EstadoSesion.restaurando, error: e);
      }
    }
  }

  Future<void> iniciarSesion(String alias, String password) =>
      _entrar('/auth/login', {'alias': alias, 'password': password});

  Future<void> registrarse(String alias, String password) =>
      _entrar('/auth/registro', {'alias': alias, 'password': password});

  /// Cierra esta sesión. Los tokens locales se borran siempre, aunque la API
  /// no responda (§6, "Cerrar sesión").
  Future<void> cerrarSesion() async {
    final refresh = _tokens?.refresh ?? await _almacen.leer();
    await _cerrarLocal();
    if (refresh == null) return;
    try {
      await _api.enviar(
        PeticionApi(
          'POST',
          '/auth/logout',
          cuerpo: {'refresh_token': refresh},
          conInterceptores: false,
          limite: limiteAuth,
        ),
      );
    } on ApiException {
      // Sin red o servidor caído: la sesión caducará sola en el servidor.
    }
  }

  /// Cierra todas las sesiones del usuario. Si falla, la sesión local se
  /// conserva para poder reintentarlo (las demás seguirían abiertas).
  Future<void> cerrarTodas() async {
    await _api.enviar(
      PeticionApi('POST', '/auth/logout-todo', limite: limiteAuth),
    );
    await _cerrarLocal(aviso: avisoTodas);
  }

  // --- Interceptor -----------------------------------------------------------

  @override
  Future<void> antesDeEnviar(PeticionApi peticion) async {
    // Si otra petición está renovando, se espera: el access actual va a
    // dejar de ser el bueno.
    final enCurso = _renovacion;
    if (enCurso != null) await enCurso;

    final tokens = _tokens;
    if (tokens != null &&
        !_ahora().isBefore(tokens.accessCaduca.subtract(margen))) {
      await _renovar();
    }
    final access = _tokens?.access;
    if (access == null) {
      peticion.cabeceras.remove('Authorization');
    } else {
      peticion.cabeceras['Authorization'] = 'Bearer $access';
    }
  }

  @override
  Future<bool> reintentar(PeticionApi peticion, ApiException error) async {
    if (error.statusCode != 401 ||
        !_codigosRenovables.contains(error.codigo) ||
        _tokens == null) {
      return false;
    }
    if (peticion.intento > 1) {
      // Recién renovado y vuelve a dar 401: no hay nada más que hacer.
      await _cerrarLocal(aviso: avisoNoValida);
      return false;
    }
    // Si mientras tanto otra petición ya renovó, basta con repetir.
    if (peticion.cabeceras['Authorization'] != 'Bearer ${_tokens!.access}') {
      return true;
    }
    await _renovar();
    return true;
  }

  // --- Detalles internos -----------------------------------------------------

  /// Single-flight: una sola renovación a la vez; el resto espera a esa.
  Future<void> _renovar() =>
      _renovacion ??= _hacerRenovacion().whenComplete(() => _renovacion = null);

  Future<void> _hacerRenovacion() async {
    final generacion = _generacion;
    final refresh = _tokens?.refresh ?? await _almacen.leer();
    if (refresh == null) {
      await _cerrarLocal();
      throw const ApiException(
        'Inicia sesión para continuar.',
        statusCode: 401,
        codigo: 'refresh_invalido',
      );
    }
    // Sin respuesta (red, timeout): se reintenta el MISMO refresh hasta 2
    // veces más. La API lo acepta repetido durante 30 s (§5).
    for (var intento = 1; ; intento++) {
      final enviado = _ahora();
      try {
        final json = await _api.enviar(
          PeticionApi(
            'POST',
            '/auth/refresh',
            cuerpo: {'refresh_token': refresh},
            conInterceptores: false,
            limite: limiteAuth,
          ),
        );
        if (generacion != _generacion) {
          throw const ApiException('La sesión se cerró.', statusCode: 401);
        }
        await _aplicar(json, enviado);
        return;
      } on ApiException catch (e) {
        if (generacion != _generacion) rethrow;
        if (e.sinConexion) {
          if (intento < 3) continue;
          rethrow; // sin red: se conservan los tokens
        }
        final aviso = switch ((e.statusCode, e.codigo)) {
          (401, 'sesion_revocada') => avisoRevocada,
          (401, _) => avisoCaducada,
          (403, 'cuenta_desactivada') => e.mensaje,
          _ => null, // 429, 5xx: no se cierra la sesión
        };
        if (aviso != null) await _cerrarLocal(aviso: aviso);
        rethrow;
      }
    }
  }

  Future<void> _entrar(String ruta, Map<String, Object?> cuerpo) async {
    final enviado = _ahora();
    final json = await _api.enviar(
      PeticionApi(
        'POST',
        ruta,
        cuerpo: cuerpo,
        conInterceptores: false,
        limite: limiteAuth,
      ),
    );
    await _aplicar(json, enviado);
  }

  /// [enviado]: la caducidad se cuenta desde que se pidió el token (no desde
  /// que llegó), para quedar del lado seguro.
  Future<void> _aplicar(Object? json, DateTime enviado) async {
    final tokens = _api.parsear(
      json,
      (j) => Tokens.fromJson(j, recibido: enviado),
    );
    await _almacen.guardar(tokens.refresh); // primero el refresh (§6)
    _tokens = tokens;
    _aviso = null;
    _cambiar(EstadoSesion.conSesion);
  }

  Future<void> _cerrarLocal({String? aviso}) async {
    _generacion++;
    _tokens = null;
    _aviso = aviso;
    await _almacen.borrar();
    _cambiar(EstadoSesion.sinSesion);
  }

  void _cambiar(EstadoSesion estado, {ApiException? error}) {
    _estado = estado;
    _errorAlRestaurar = error;
    // Una petición puede terminar después de cerrar la app (o el test).
    if (!_desechado) notifyListeners();
  }

  bool _desechado = false;

  @override
  void dispose() {
    _desechado = true;
    super.dispose();
  }
}
