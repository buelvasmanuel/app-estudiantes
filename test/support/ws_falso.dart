import 'dart:async';
import 'dart:convert';

import 'package:app_estudiantes/duelo/canal.dart';

/// Una conexión WebSocket simulada: el test le hace llegar mensajes o la
/// cierra, y ve lo que envió la app.
class ConexionFalsa implements ConexionWs {
  ConexionFalsa(this.url);

  final Uri url;
  final _entrada = StreamController<Object?>();
  final enviados = <Map<String, Object?>>[];
  bool cerrada = false;

  @override
  int? codigoCierre;

  @override
  Stream<Object?> get mensajes => _entrada.stream;

  @override
  void enviar(String texto) =>
      enviados.add(jsonDecode(texto) as Map<String, Object?>);

  @override
  Future<void> cerrar([int? codigo]) async {
    cerrada = true;
    if (!_entrada.isClosed) await _entrada.close();
  }

  /// Llega un mensaje de la API.
  void recibir(Map<String, Object?> mensaje) {
    if (!_entrada.isClosed) _entrada.add(jsonEncode(mensaje));
  }

  /// La API (o la red) cierra la conexión, con o sin código.
  void caer([int? codigo]) {
    codigoCierre = codigo;
    if (!_entrada.isClosed) _entrada.close();
  }

  /// Tipos de lo que envió la app ("auth", "ping"…).
  List<Object?> get tiposEnviados => [for (final m in enviados) m['tipo']];
}

/// El "servidor" de WebSockets: cada conexión que abre la app queda en
/// [conexiones]. Con [falla], no se puede conectar (red que lo bloquea).
class ServidorWsFalso {
  final conexiones = <ConexionFalsa>[];
  bool falla = false;

  ConexionFalsa get ultima => conexiones.last;

  Future<ConexionWs> conectar(Uri url) async {
    if (falla) throw StateError('WebSocket bloqueado');
    final c = ConexionFalsa(url);
    conexiones.add(c);
    return c;
  }
}
