import 'dart:convert';

import 'package:app_estudiantes/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_falsa.dart';
import 'juego_falso.dart';
import 'servidor_falso.dart';

/// Una carta de prueba: atributos `(valor, percentil)`.
Map<String, Object?> cartaJson(
  int id,
  String nombre,
  String apellido, {
  required (num, int) promedio,
  required (num, int) asistencia,
  required (num, int) horas,
  required (num, int) semestre,
  String carrera = 'Medicina',
}) => {
  'estudiante_id': id,
  'nombre': nombre,
  'apellido': apellido,
  'carrera': carrera,
  'atributos': {
    'promedio': {'valor': promedio.$1, 'percentil': promedio.$2},
    'asistencia': {'valor': asistencia.$1, 'percentil': asistencia.$2},
    'horas_estudio': {'valor': horas.$1, 'percentil': horas.$2},
    'semestre': {'valor': semestre.$1, 'percentil': semestre.$2},
  },
};

/// Mazo propio: Ana (ronda 1) gana con asistencia; el resto, cartas flojas.
final mazoYo = [
  cartaJson(
    17,
    'Ana',
    'Gómez',
    promedio: (3.8, 72),
    asistencia: (92, 81),
    horas: (14, 49),
    semestre: (3, 30),
  ),
  for (var i = 0; i < 4; i++)
    cartaJson(
      20 + i,
      'Carta',
      'Mía$i',
      promedio: (3.0, 40),
      asistencia: (75, 40),
      horas: (10, 40),
      semestre: (4, 40),
    ),
];

/// Mazo de la máquina: Esperanza (ronda 1) pierde en asistencia; en las
/// demás, su mejor percentil es la asistencia (90 %), que gana a 75 %.
final mazoMaquina = [
  cartaJson(
    2,
    'Esperanza',
    'Torres',
    promedio: (2.79, 20),
    asistencia: (70, 22),
    horas: (14, 49),
    semestre: (2, 15),
  ),
  for (var i = 0; i < 4; i++)
    cartaJson(
      40 + i,
      'Rival',
      'Máquina$i',
      promedio: (2.5, 10),
      asistencia: (90, 70),
      horas: (8, 20),
      semestre: (6, 60),
    ),
];

const _atributosJson = [
  {
    'codigo': 'promedio',
    'nombre': 'Promedio',
    'unidad': '0–5',
    'descripcion': 'El resultado académico.',
  },
  {
    'codigo': 'asistencia',
    'nombre': 'Asistencia',
    'unidad': '%',
    'descripcion': 'Cuánto va a clase.',
  },
  {
    'codigo': 'horas_estudio',
    'nombre': 'Horas de estudio',
    'unidad': 'h/semana',
    'descripcion': 'Cuánto estudia.',
  },
  {
    'codigo': 'semestre',
    'nombre': 'Semestre',
    'unidad': '1–10',
    'descripcion': 'Cuánto lleva en la carrera.',
  },
];

/// API simulada del duelo contra la máquina (docs/CONTRATO_DUELO.md v1),
/// con el resto del juego (progreso, casos) de [JuegoFalso].
class DueloFalso {
  DueloFalso({
    this.enJuegoAlAbrir = false,
    this.duelosConXpHoy = 0,
    this.yaEsDuelista = false,
  }) {
    if (enJuegoAlAbrir) _nuevo();
  }

  final juego = JuegoFalso();
  final registro = <String>[];

  /// Si al abrir ya hay un duelo a medias (en la ronda 1).
  final bool enJuegoAlAbrir;
  int duelosConXpHoy;

  /// La insignia "Duelista" llega solo con la primera victoria.
  bool yaEsDuelista;

  /// Las próximas N jugadas fallan sin respuesta (red) o con 503.
  int fallosRed = 0;
  int fallos503 = 0;

  /// La próxima jugada responde este 409 (una vez).
  String? proximo409;

  /// Jugadas que el servidor llegó a aplicar (las repetidas no cuentan).
  int jugadasAplicadas = 0;

  String? _id;
  int _creados = 0;
  String _estado = 'en_juego';
  int _ronda = 1;
  String _turno = 'yo';
  int _yo = 0;
  int _rival = 0;
  final _rondas = <Map<String, Object?>>[];
  String? _resultado;
  int _xp = 0;

  ApiService api() =>
      ApiService(baseUrl: 'http://api.test', client: MockClient(_atender));

  Future<http.Response> _atender(http.Request p) async {
    final ruta = p.url.path;
    if (!ruta.startsWith('/duelos')) return juego.atender(p);
    registro.add(
      '${p.method} $ruta${p.url.hasQuery ? '?${p.url.query}' : ''}'
      '${p.body.isEmpty ? '' : ' ${p.body}'}',
    );
    final cuerpo = p.body.isEmpty || p.body == 'null'
        ? const <String, Object?>{}
        : jsonDecode(p.body) as Map<String, Object?>;

    if (ruta == '/duelos' && p.method == 'GET') {
      return respuestaJson({
        'duelos': [
          if (_id != null && _estado == 'en_juego')
            {
              'id': _id,
              'modo': 'maquina',
              'estado': _estado,
              'rival': {'tipo': 'maquina', 'alias': 'Búho Máquina'},
              'marcador': {'yo': _yo, 'rival': _rival},
              'resultado': null,
              'xp_ganada': 0,
              'creado_en': '2026-10-11T18:00:00Z',
            },
        ],
      });
    }
    if (ruta == '/duelos' && p.method == 'POST') {
      _nuevo();
      return respuestaJson(_dueloJson(), 201);
    }
    final partes = ruta.split('/'); // ['', 'duelos', id, accion?]
    if (partes.length < 3 || partes[2] != _id) {
      return _error(404, 'duelo_no_encontrado', 'No existe ese duelo');
    }
    final accion = partes.length > 3 ? partes[3] : null;
    if (accion == null) return respuestaJson(_dueloJson());
    if (accion == 'abandonar') {
      if (_estado == 'terminado') {
        return _error(409, 'duelo_terminado', 'El duelo ya terminó');
      }
      _estado = 'abandonado';
      _resultado = 'derrota';
      return respuestaJson(_dueloJson());
    }
    // jugadas
    if (fallosRed > 0) {
      fallosRed--;
      throw http.ClientException('Connection reset', p.url);
    }
    if (fallos503 > 0) {
      fallos503--;
      return ServidorFalso.json({'detail': 'Servicio no disponible'}, 503);
    }
    if (proximo409 case final codigo?) {
      proximo409 = null;
      return _error(409, codigo, 'Conflicto: $codigo');
    }
    return _jugar(cuerpo['ronda']! as int, cuerpo['atributo'] as String?);
  }

  http.Response _jugar(int ronda, String? atributo) {
    // Reintento de una ronda ya resuelta con la misma jugada: el estado.
    if (ronda < _ronda || _estado != 'en_juego') {
      final hecha = ronda <= _rondas.length ? _rondas[ronda - 1] : null;
      final elegidaPorMi = hecha?['elegido_por'] == 'yo';
      if (hecha != null &&
          (elegidaPorMi ? hecha['atributo'] == atributo : atributo == null)) {
        return respuestaJson(_dueloJson());
      }
      if (_estado != 'en_juego') {
        return _error(409, 'duelo_terminado', 'El duelo ya terminó');
      }
      return _error(409, 'ronda_incorrecta', 'No es esa ronda', {
        'ronda_actual': _ronda,
      });
    }
    if (ronda != _ronda) {
      return _error(409, 'ronda_incorrecta', 'No es esa ronda', {
        'ronda_actual': _ronda,
      });
    }
    if (_turno == 'yo' && atributo == null) {
      return _error(422, 'atributo_requerido', 'Elige un atributo');
    }
    if (_turno == 'rival' && atributo != null) {
      return _error(409, 'no_es_tu_turno', 'Le toca al rival');
    }
    jugadasAplicadas++;
    final mia = mazoYo[_ronda - 1];
    final suya = mazoMaquina[_ronda - 1];
    final elegido = atributo ?? _mejorAtributo(suya);
    final vMia = _valor(mia, elegido);
    final vSuya = _valor(suya, elegido);
    final ganador = vMia > vSuya
        ? 'yo'
        : vMia < vSuya
        ? 'rival'
        : 'empate';
    if (ganador == 'yo') _yo++;
    if (ganador == 'rival') _rival++;
    _rondas.add({
      'numero': _ronda,
      'elegido_por': _turno,
      'atributo': elegido,
      'mi_carta': mia,
      'carta_rival': suya,
      'ganador': ganador,
      'explicacion':
          '${ganador == 'yo' ? 'Ganaste' : 'Perdiste'} con $elegido: tu carta '
          'tiene $vMia y la del rival, $vSuya. (ronda $_ronda)',
    });
    var terminaAhora = false;
    if (_ronda == 5) {
      _estado = 'terminado';
      _resultado = _yo > _rival
          ? 'victoria'
          : _yo < _rival
          ? 'derrota'
          : 'empate';
      if (duelosConXpHoy < 3) {
        duelosConXpHoy++;
        _xp = switch (_resultado) {
          'victoria' => 30,
          'empate' => 15,
          _ => 5,
        };
        juego.xp += _xp;
      }
      terminaAhora = true;
    } else {
      _ronda++;
      _turno = _turno == 'yo' ? 'rival' : 'yo';
    }
    final respuesta = respuestaJson(_dueloJson(terminaAhora: terminaAhora));
    if (terminaAhora && _resultado == 'victoria') yaEsDuelista = true;
    return respuesta;
  }

  void _nuevo() {
    _creados++;
    _id = 'duelo$_creados${'0' * 26}';
    _estado = 'en_juego';
    _ronda = 1;
    _turno = 'yo';
    _yo = 0;
    _rival = 0;
    _rondas.clear();
    _resultado = null;
    _xp = 0;
  }

  static num _valor(Map<String, Object?> carta, String atributo) =>
      ((carta['atributos']! as Map)[atributo] as Map)['valor'] as num;

  static String _mejorAtributo(Map<String, Object?> carta) {
    final a = carta['atributos']! as Map<String, Object?>;
    int percentil(String c) => (a[c]! as Map)['percentil'] as int;
    var mejor = 'promedio';
    for (final c in ['promedio', 'asistencia', 'horas_estudio', 'semestre']) {
      if (percentil(c) > percentil(mejor)) mejor = c;
    }
    return mejor;
  }

  Map<String, Object?> _dueloJson({bool terminaAhora = false}) {
    final sigue = _estado == 'en_juego';
    return {
      'id': _id,
      'modo': 'maquina',
      'estado': _estado,
      'rival': {'tipo': 'maquina', 'alias': 'Búho Máquina'},
      'rondas_total': 5,
      'ronda': sigue ? _ronda : null,
      'turno': sigue ? _turno : null,
      'marcador': {'yo': _yo, 'rival': _rival},
      'mi_carta': sigue ? mazoYo[_ronda - 1] : null,
      'rondas': _rondas,
      'resultado': _resultado,
      'xp_ganada': _xp,
      'duelos_con_xp_hoy': {'jugados': duelosConXpHoy, 'maximo': 3},
      'atributos': _atributosJson,
      'expira_turno_en': null,
      'rival_en_linea': null,
      'creado_en': '2026-10-11T18:00:00Z',
      'actualizado_en': '2026-10-11T18:01:00Z',
      'insignias_nuevas': [
        if (terminaAhora && _resultado == 'victoria' && !yaEsDuelista)
          insigniaJson('duelista', 'Duelista', obtenida: true),
      ],
      'progreso': terminaAhora
          ? {'xp': juego.xp, 'nivel': 'Novato', 'subio_de_nivel': false}
          : null,
    };
  }

  static http.Response _error(
    int status,
    String codigo,
    String mensaje, [
    Map<String, Object?> extra = const {},
  ]) => ServidorFalso.json({
    'detail': {'codigo': codigo, 'mensaje': mensaje, ...extra},
  }, status);
}
