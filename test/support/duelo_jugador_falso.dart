import 'dart:convert';

import 'package:app_estudiantes/services/api_service.dart';
import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_falsa.dart';
import 'duelo_falso.dart';
import 'juego_falso.dart';
import 'servidor_falso.dart';

int _version = 0;

/// Un `DueloOut` contra un jugador (CONTRATO_DUELO 2.1). Cada llamada lleva
/// un `actualizado_en` posterior al anterior.
Map<String, Object?> dueloJugadorJson({
  String id = 'j1',
  String estado = 'en_juego',
  String? alias = 'Laura_P',
  int? ronda = 1,
  String? turno = 'yo',
  int yo = 0,
  int rival = 0,
  List<Map<String, Object?>> rondas = const [],
  String? resultado,
  int xp = 0,
  int jugadosHoy = 1,
  DateTime? expira,
  bool sinPlazo = false,
  bool? enLinea = true,
  Map<String, Object?>? miCarta,
}) {
  final activo = estado == 'en_juego' || estado == 'esperando';
  final plazo =
      expira ??
      clock.now().add(Duration(seconds: estado == 'esperando' ? 60 : 45));
  return {
    'id': id,
    'modo': 'jugador',
    'estado': estado,
    'rival': {'tipo': 'jugador', 'alias': estado == 'esperando' ? null : alias},
    'rondas_total': 5,
    'ronda': estado == 'en_juego' ? ronda : null,
    'turno': estado == 'en_juego' ? turno : null,
    'marcador': {'yo': yo, 'rival': rival},
    'mi_carta': estado == 'en_juego' ? (miCarta ?? mazoYo.first) : null,
    'rondas': rondas,
    'resultado': resultado,
    'xp_ganada': xp,
    'duelos_con_xp_hoy': {'jugados': jugadosHoy, 'maximo': 3},
    'atributos': <Object?>[],
    'expira_turno_en': activo && !sinPlazo
        ? plazo.toUtc().toIso8601String()
        : null,
    'rival_en_linea': estado == 'esperando' ? null : enLinea,
    'creado_en': '2026-10-12T18:00:00Z',
    'actualizado_en': DateTime.utc(
      2026,
      10,
      12,
      18,
    ).add(Duration(milliseconds: ++_version)).toIso8601String(),
    'insignias_nuevas': <Object?>[],
    'progreso': null,
  };
}

/// Una ronda resuelta. Con [porTiempo], sin atributo y con la explicación
/// que da la API para ese caso.
Map<String, Object?> rondaJson(
  int numero, {
  String elegidoPor = 'yo',
  String? atributo = 'asistencia',
  String ganador = 'yo',
  bool porTiempo = false,
  String? explicacion,
}) => {
  'numero': numero,
  'elegido_por': elegidoPor,
  'atributo': porTiempo ? null : atributo,
  'mi_carta': mazoYo[(numero - 1) % mazoYo.length],
  'carta_rival': mazoMaquina[(numero - 1) % mazoMaquina.length],
  'ganador': ganador,
  'motivo': porTiempo ? 'tiempo' : 'jugada',
  'explicacion':
      explicacion ??
      (porTiempo
          ? elegidoPor == 'yo'
                ? 'Se te acabó el tiempo del turno: la ronda es para el rival.'
                : 'Al rival se le acabó el tiempo de su turno: la ronda es '
                      'para ti.'
          : 'Ganaste con $atributo: tu carta tiene 92 % y la del rival, 70 %.'),
};

/// API simulada del duelo contra un jugador. El test decide el [estado]
/// (lo que devuelven `POST /duelos` y `GET /duelos/{id}`) y lo cambia como
/// lo haría el otro jugador.
class DueloJugadorFalso {
  DueloJugadorFalso({Map<String, Object?>? inicial})
    : estado = inicial ?? dueloJugadorJson(estado: 'esperando');

  final juego = JuegoFalso();
  final registro = <String>[];
  Map<String, Object?> estado;

  /// `xp_hoy` de `GET /duelos` (v2.2); `null`: como una API anterior.
  Map<String, Object?>? xpHoy = {
    'maquina': {'jugados': 1, 'maximo': 3},
    'jugador': {'jugados': 2, 'maximo': 3},
  };

  /// `POST /duelos` responde `409 duelo_en_curso` (ya hay uno en juego).
  bool enCurso = false;

  /// Qué pasa con una jugada; por defecto, la gano y le toca al rival.
  Map<String, Object?> Function(int ronda, String? atributo)? alJugar;

  /// Qué devuelve `GET /duelos/{id}` (p. ej. el vencimiento aplicado).
  Map<String, Object?> Function()? alConsultar;

  /// Las próximas N búsquedas responden `503 emparejamiento_ocupado` (v2.4).
  int ocupado = 0;

  ApiService api() =>
      ApiService(baseUrl: 'http://api.test', client: MockClient(_atender));

  /// Peticiones al duelo, sin las del resto del juego.
  List<String> get peticiones => registro;

  int consultas(String id) =>
      registro.where((r) => r == 'GET /duelos/$id').length;

  Future<http.Response> _atender(http.Request p) async {
    final ruta = p.url.path;
    if (!ruta.startsWith('/duelos')) return juego.atender(p);
    registro.add('${p.method} $ruta${p.url.hasQuery ? '?${p.url.query}' : ''}');
    final cuerpo = p.body.isEmpty || p.body == 'null'
        ? const <String, Object?>{}
        : jsonDecode(p.body) as Map<String, Object?>;
    final id = estado['id'];
    if (ruta == '/duelos' && p.method == 'GET') {
      return respuestaJson({'duelos': <Object?>[], 'xp_hoy': ?xpHoy});
    }
    if (ruta == '/duelos' && p.method == 'POST') {
      if (ocupado > 0) {
        ocupado--;
        return ServidorFalso.error(503, 'emparejamiento_ocupado');
      }
      if (enCurso) {
        return ServidorFalso.json({
          'detail': {
            'codigo': 'duelo_en_curso',
            'mensaje': 'Ya tienes un duelo en curso',
            'duelo_id': id,
          },
        }, 409);
      }
      return respuestaJson(estado, 201);
    }
    if (ruta == '/duelos/$id' && p.method == 'GET') {
      if (alConsultar case final f?) estado = f();
      return respuestaJson(estado);
    }
    if (ruta == '/duelos/$id/abandonar') {
      estado = estado['estado'] == 'esperando'
          ? dueloJugadorJson(id: '$id', estado: 'abandonado')
          : dueloJugadorJson(
              id: '$id',
              estado: 'abandonado',
              resultado: 'derrota',
              rondas: _rondas,
            );
      return respuestaJson(estado);
    }
    if (ruta == '/duelos/$id/jugadas') {
      final ronda = cuerpo['ronda']! as int;
      final atributo = cuerpo['atributo'] as String?;
      estado =
          alJugar?.call(ronda, atributo) ??
          dueloJugadorJson(
            id: '$id',
            ronda: ronda + 1,
            turno: 'rival',
            yo: 1,
            rondas: [
              ..._rondas,
              rondaJson(ronda, atributo: atributo),
            ],
          );
      return respuestaJson(estado);
    }
    throw http.ClientException('Ruta no simulada', p.url);
  }

  List<Map<String, Object?>> get _rondas =>
      (estado['rondas']! as List).cast<Map<String, Object?>>();
}
