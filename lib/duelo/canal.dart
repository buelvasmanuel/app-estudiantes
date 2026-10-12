import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import 'modelo.dart';

/// Una conexión WebSocket abierta. Interfaz para poder simularla en tests.
abstract class ConexionWs {
  Stream<Object?> get mensajes;
  void enviar(String texto);
  Future<void> cerrar([int? codigo]);

  /// El código de cierre, si llegó (detrás de Render/Cloudflare no siempre).
  int? get codigoCierre;
}

/// Abre una conexión a [url]. Lanza si no se puede.
typedef ConectorWs = Future<ConexionWs> Function(Uri url);

/// El conector real (`web_socket_channel`: el mismo código en web y móvil).
Future<ConexionWs> conectarWs(Uri url) async {
  final canal = WebSocketChannel.connect(url);
  await canal.ready;
  return _ConexionReal(canal);
}

class _ConexionReal implements ConexionWs {
  _ConexionReal(this._canal);

  final WebSocketChannel _canal;

  @override
  Stream<Object?> get mensajes => _canal.stream;

  @override
  void enviar(String texto) => _canal.sink.add(texto);

  @override
  Future<void> cerrar([int? codigo]) => _canal.sink.close(codigo);

  @override
  int? get codigoCierre => _canal.closeCode;
}

enum EstadoCanal {
  /// Abriendo la conexión o esperando `listo`.
  conectando,

  /// Autenticado: llegan los avisos.
  conectado,

  /// Se cayó; se volverá a intentar (con espera creciente).
  reconectando,

  /// No se volverá a intentar (4403/4404 o sin sesión): solo REST.
  descartado,
}

/// Los avisos del duelo por WebSocket (CONTRATO_DUELO 2.1 §8).
///
/// Solo avisa: todo lo que cambia el duelo va por REST. Mientras no esté
/// [EstadoCanal.conectado], quien lo usa debe consultar el duelo por REST
/// (`GET /duelos/{id}` cada 3 s), así que la partida sigue aunque el
/// WebSocket no funcione.
///
/// - Primer mensaje: `{"tipo": "auth", "token": …}` (sin token en la URL).
/// - `{"tipo": "ping"}` cada [intervaloPing].
/// - Ante un mensaje `error`, actúa en ese momento y cierra él la conexión:
///   detrás del proxy el código de cierre no siempre llega.
/// - Se reconecta con espera creciente (1, 2, 4… hasta [esperaMaxima]) y,
///   al volver, llama a [onReconectado] para resincronizar por REST.
class CanalDuelo {
  CanalDuelo({
    required this.idDuelo,
    required String apiUrl,
    required this.token,
    required this.onAviso,
    this.onEstado,
    this.onReconectado,
    this.conector = conectarWs,
  }) : url = urlWebSocket(apiUrl, idDuelo);

  final String idDuelo;
  final Uri url;

  /// Un access vigente; con `forzar`, renovado (tras un 4401).
  final Future<String?> Function({bool forzar}) token;

  /// Cada aviso con su `DueloOut` (`listo`, `emparejado`, `ronda_resuelta`,
  /// `terminado`, `rival_conectado`, `rival_desconectado`).
  final void Function(String tipo, Duelo duelo) onAviso;
  final void Function(EstadoCanal estado)? onEstado;
  final void Function()? onReconectado;
  final ConectorWs conector;

  static const intervaloPing = Duration(seconds: 25);
  static const esperaMaxima = Duration(seconds: 30);

  /// `https://api…` → `wss://api…/duelos/{id}/ws`.
  static Uri urlWebSocket(String apiUrl, String idDuelo) {
    final base = Uri.parse(apiUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/duelos/${Uri.encodeComponent(idDuelo)}/ws',
    );
  }

  EstadoCanal _estado = EstadoCanal.conectando;
  EstadoCanal get estado => _estado;

  ConexionWs? _conexion;
  StreamSubscription<Object?>? _suscripcion;
  Timer? _ping;
  Timer? _reintento;
  int _fallos = 0;
  int _rechazosToken = 0;
  bool _forzarToken = false;
  bool _yaConecto = false;
  bool _cerrado = false;

  /// Cada conexión tiene su número: los mensajes y cierres de una conexión
  /// vieja (ya sustituida) se ignoran.
  int _generacion = 0;

  /// Cuánto se esperará antes del próximo intento (para tests y registro).
  Duration? proximaEspera;

  void abrir() {
    if (_cerrado) return;
    _conectar();
  }

  /// Cierra para siempre (al salir de la pantalla o al terminar el duelo).
  Future<void> cerrar() async {
    _cerrado = true;
    _reintento?.cancel();
    _soltar();
  }

  Future<void> _conectar() async {
    final generacion = ++_generacion;
    _cambiar(_yaConecto ? EstadoCanal.reconectando : EstadoCanal.conectando);
    final ConexionWs conexion;
    final String? access;
    try {
      access = await token(forzar: _forzarToken);
      _forzarToken = false;
      if (_cerrado || generacion != _generacion) return;
      if (access == null) {
        _cambiar(EstadoCanal.descartado);
        return;
      }
      conexion = await conector(url);
    } on Object {
      if (!_cerrado && generacion == _generacion) _caido(null);
      return;
    }
    if (_cerrado || generacion != _generacion) {
      unawaited(conexion.cerrar());
      return;
    }
    _conexion = conexion;
    _suscripcion = conexion.mensajes.listen(
      (m) => _mensaje(generacion, m),
      onError: (Object _) => _fin(generacion),
      onDone: () => _fin(generacion),
    );
    conexion.enviar(jsonEncode({'tipo': 'auth', 'token': access}));
    _ping = Timer.periodic(intervaloPing, (_) {
      if (generacion == _generacion) {
        _conexion?.enviar(jsonEncode({'tipo': 'ping'}));
      }
    });
  }

  void _mensaje(int generacion, Object? mensaje) {
    if (_cerrado || generacion != _generacion || mensaje is! String) return;
    final Map<String, Object?> datos;
    try {
      datos = jsonDecode(mensaje) as Map<String, Object?>;
    } on Object {
      return; // un mensaje que no se entiende no rompe la partida
    }
    switch (datos['tipo']) {
      case 'pong':
        return;
      case 'error':
        // Se actúa ya: el cierre con su código puede no llegar nunca.
        final codigo = datos['codigo'];
        _soltar();
        _caido(codigo is int ? codigo : null);
        return;
      case final String tipo:
        final Duelo duelo;
        try {
          duelo = Duelo.fromJson(datos['duelo']);
        } on Object {
          return;
        }
        if (tipo == 'listo') {
          _fallos = 0;
          _rechazosToken = 0;
          proximaEspera = null;
          _cambiar(EstadoCanal.conectado);
          if (_yaConecto) onReconectado?.call();
          _yaConecto = true;
        }
        onAviso(tipo, duelo);
    }
  }

  void _fin(int generacion) {
    if (_cerrado || generacion != _generacion) return;
    final codigo = _conexion?.codigoCierre;
    _soltar();
    _caido(codigo);
  }

  /// Qué hacer según el código (tabla de §8).
  void _caido(int? codigo) {
    switch (codigo) {
      case 4403 || 4404:
        _cambiar(EstadoCanal.descartado);
      case 4401:
        // Token rechazado: renovarlo y reconectar. Si vuelve a pasar, con
        // espera (no se martillea a la API).
        _forzarToken = true;
        _programar(inmediato: _rechazosToken++ == 0);
      default: // 4408, 1000, 1001, 1006, sin código o sin red
        _programar();
    }
  }

  void _programar({bool inmediato = false}) {
    _cambiar(EstadoCanal.reconectando);
    final segundos = inmediato
        ? 0
        : math.min(1 << _fallos, esperaMaxima.inSeconds);
    if (!inmediato) _fallos = math.min(_fallos + 1, 6);
    proximaEspera = Duration(seconds: segundos);
    _reintento?.cancel();
    _reintento = Timer(proximaEspera!, _conectar);
  }

  void _soltar() {
    _generacion++;
    _ping?.cancel();
    _ping = null;
    unawaited(_suscripcion?.cancel());
    _suscripcion = null;
    unawaited(_conexion?.cerrar());
    _conexion = null;
  }

  void _cambiar(EstadoCanal estado) {
    if (_estado == estado) return;
    _estado = estado;
    onEstado?.call(estado);
  }
}
