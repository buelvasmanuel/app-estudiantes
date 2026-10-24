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
    this.modoCookie = false,
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

  /// Web: el refresh vive en una cookie HttpOnly de la API (CONTRATO_AUTH
  /// §6.3). Las peticiones de sesión llevan `X-Refresh-En-Cookie: 1` y
  /// credenciales; `/auth/refresh` y `/auth/logout` van con `{}`. En el APK y
  /// el escritorio es `false` y nada cambia.
  final bool modoCookie;

  /// Al arrancar en modo cookie: un `401 refresh_invalido` solo significa
  /// que no había sesión (no se avisa de nada).
  bool _arrancando = false;

  /// La petición [p], preparada para el modo cookie si toca.
  PeticionApi _deSesion(
    String metodo,
    String ruta, {
    Object? cuerpo,
    bool conInterceptores = false,
  }) => PeticionApi(
    metodo,
    ruta,
    cuerpo: cuerpo,
    conInterceptores: conInterceptores,
    limite: limiteAuth,
    conCredenciales: modoCookie,
    cabeceras: {if (modoCookie) 'X-Refresh-En-Cookie': '1'},
  );

  /// Las cabeceras y credenciales del modo cookie, para peticiones de sesión
  /// que se arman fuera (el login con passkey).
  PeticionApi prepararParaSesion(PeticionApi p) => PeticionApi(
    p.metodo,
    p.ruta,
    cuerpo: p.cuerpo,
    cabeceras: {...p.cabeceras, if (modoCookie) 'X-Refresh-En-Cookie': '1'},
    conInterceptores: p.conInterceptores,
    limite: p.limite,
    conCredenciales: modoCookie,
  );

  /// Si al access le queda menos que esto, se renueva antes de enviar.
  static const margen = Duration(seconds: 60);

  /// Tope para reintentar un refresh sin respuesta, contado desde el primer
  /// intento: la API acepta el mismo refresh durante 120 s (§5).
  static const ultimoReintento = Duration(seconds: 110);

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
    // En la web con cookie no se sabe si hay sesión hasta preguntar: el
    // refresh no se ve desde la app.
    if (!modoCookie) {
      final refresh = await _almacen.leer();
      if (refresh == null) {
        _cambiar(EstadoSesion.sinSesion);
        return;
      }
    }
    _arrancando = true;
    try {
      await _renovar();
    } on ApiException catch (e) {
      // Si la API rechazó el refresh, _renovar ya cerró la sesión. Si no hubo
      // respuesta, se queda en "restaurando" con el error y Reintentar.
      if (_estado == EstadoSesion.restaurando) {
        _cambiar(EstadoSesion.restaurando, error: e);
      }
    } finally {
      _arrancando = false;
    }
  }

  Future<void> iniciarSesion(String alias, String password) =>
      _entrar('/auth/login', {'alias': alias, 'password': password});

  /// Entrar con una passkey (CONTRATO_PASSKEYS §3): [tokens] hace el baile
  /// con el navegador y devuelve el `TokensOut`, que se guarda y renueva
  /// igual que el del login con contraseña.
  Future<void> entrarConPasskey(Future<Object?> Function() tokens) async {
    final enviado = _ahora();
    final json = await tokens();
    _soltarRestauracion();
    await _aplicar(json, enviado);
  }

  /// Se entró a mano (contraseña o passkey) mientras se comprobaba la sesión
  /// guardada (el login se muestra mientras el servidor despierta): esa
  /// comprobación ya no cuenta. Si su respuesta llega después, se ignora (no
  /// cierra la sesión nueva) y las peticiones nuevas no la esperan.
  void _soltarRestauracion() {
    if (_renovacion == null) return;
    _generacion++;
    _renovacion = null;
  }

  Future<void> registrarse(String alias, String password) =>
      _entrar('/auth/registro', {'alias': alias, 'password': password});

  /// Cierra esta sesión. Los tokens locales se borran siempre, aunque la API
  /// no responda (§6, "Cerrar sesión").
  Future<void> cerrarSesion() async {
    final refresh = _tokens?.refresh ?? await _almacen.leer();
    await _cerrarLocal();
    // En modo cookie se envía `{}`: la API cierra la sesión de la cookie y la
    // borra (la app no puede).
    if (refresh == null && !modoCookie) return;
    try {
      await _api.enviar(
        _deSesion('POST', '/auth/logout', cuerpo: {'refresh_token': ?refresh}),
      );
    } on ApiException {
      // Sin red o servidor caído: la sesión caducará sola en el servidor.
    }
  }

  /// Cierra todas las sesiones del usuario. Si falla, la sesión local se
  /// conserva para poder reintentarlo (las demás seguirían abiertas).
  Future<void> cerrarTodas() async {
    await _api.enviar(
      _deSesion('POST', '/auth/logout-todo', conInterceptores: true),
    );
    await _cerrarLocal(aviso: avisoTodas);
  }

  /// Un access válido para lo que no pasa por el interceptor (el WebSocket
  /// del duelo, CONTRATO_DUELO §8). Lo renueva si le queda poco o si
  /// [forzar] (la API lo rechazó con 4401). `null` sin sesión.
  Future<String?> accessVigente({bool forzar = false}) async {
    final enCurso = _renovacion;
    if (enCurso != null) await enCurso;
    final tokens = _tokens;
    if (tokens != null &&
        (forzar || !_ahora().isBefore(tokens.accessCaduca.subtract(margen)))) {
      await _renovar();
    }
    return _tokens?.access;
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
  Future<void> _renovar() {
    final enCurso = _renovacion;
    if (enCurso != null) return enCurso;
    late final Future<void> esta;
    esta = _hacerRenovacion().whenComplete(() {
      // Solo si sigue siendo la vigente (pudo soltarse al entrar a mano).
      if (identical(_renovacion, esta)) _renovacion = null;
    });
    return _renovacion = esta;
  }

  Future<void> _hacerRenovacion() async {
    final generacion = _generacion;
    final refresh = _tokens?.refresh ?? await _almacen.leer();
    if (refresh == null && !modoCookie) {
      await _cerrarLocal();
      throw const ApiException(
        'Inicia sesión para continuar.',
        statusCode: 401,
        codigo: 'refresh_invalido',
      );
    }
    // Sin respuesta se reintenta con el MISMO refresh (§6, regla 5): una vez
    // más tras un timeout (el servidor ya estará despierto) y hasta 2 veces
    // tras un error de red inmediato. La API lo acepta repetido durante 120 s
    // (§5), así que ningún reintento sale pasados [ultimoReintento].
    final inicio = _ahora();
    var reintentosTimeout = 0;
    var reintentosRed = 0;
    while (true) {
      final enviado = _ahora();
      try {
        final json = await _api.enviar(
          _deSesion(
            'POST',
            '/auth/refresh',
            // Modo cookie: `{}` (la API lee la cookie).
            cuerpo: {'refresh_token': ?refresh},
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
          final quedan = e.esTimeout
              ? reintentosTimeout++ < 1
              : reintentosRed++ < 2;
          final aTiempo =
              _ahora().difference(inicio) <= GestorSesion.ultimoReintento;
          if (quedan && aTiempo) continue;
          rethrow; // sin respuesta: se conservan los tokens
        }
        final aviso = switch ((e.statusCode, e.codigo)) {
          // Al abrir la web: no había sesión (ni cookie). No es un error.
          (401, 'refresh_invalido') when _arrancando && modoCookie => '',
          (401, 'sesion_revocada') => avisoRevocada,
          (401, _) => avisoCaducada,
          (403, 'cuenta_desactivada') => e.mensaje,
          _ => null, // 429, 5xx: no se cierra la sesión
        };
        if (aviso != null) {
          await _cerrarLocal(aviso: aviso.isEmpty ? null : aviso);
        }
        rethrow;
      }
    }
  }

  Future<void> _entrar(String ruta, Map<String, Object?> cuerpo) async {
    final enviado = _ahora();
    final json = await _api.enviar(_deSesion('POST', ruta, cuerpo: cuerpo));
    _soltarRestauracion();
    await _aplicar(json, enviado);
  }

  /// [enviado]: la caducidad se cuenta desde que se pidió el token (no desde
  /// que llegó), para quedar del lado seguro.
  Future<void> _aplicar(Object? json, DateTime enviado) async {
    final tokens = _api.parsear(
      json,
      (j) => Tokens.fromJson(j, recibido: enviado),
    );
    // Primero el refresh (§6). En modo cookie no hay nada que guardar: va en
    // la cookie HttpOnly (y no debe guardarse en ningún sitio, §6.3).
    if (tokens.refresh case final refresh? when !modoCookie) {
      await _almacen.guardar(refresh);
    }
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
