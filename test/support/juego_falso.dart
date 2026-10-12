import 'dart:convert';

import 'package:app_estudiantes/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_falsa.dart';
import 'servidor_falso.dart';

Map<String, Object?> insigniaJson(
  String codigo,
  String nombre, {
  bool obtenida = false,
}) => {
  'codigo': codigo,
  'nombre': nombre,
  'descripcion': 'Descripción de $nombre.',
  'obtenida_en': obtenida ? '2026-10-11T18:04:05.123456Z' : null,
};

/// API simulada del juego (docs/CONTRATO_JUEGO.md). Estado mínimo: el XP
/// sube al acertar `carrera_mas_riesgo` (respuesta correcta: Medicina), que
/// además da la insignia "Primera pista".
class JuegoFalso {
  final registro = <String>[];
  int xp = 130;
  bool resuelto = false;
  int intentos = 0;
  final aliasesExistentes = {'ana_01'};

  ApiService api() =>
      ApiService(baseUrl: 'http://api.test', client: MockClient(atender));

  Future<http.Response> atender(http.Request p) async {
    final ruta = p.url.path;
    registro.add(
      '${p.method} ${p.url.path}${p.url.hasQuery ? '?${p.url.query}' : ''}',
    );
    final cuerpo = p.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(p.body) as Map<String, Object?>;
    switch (ruta) {
      case '/juego/progreso':
        return respuestaJson(_progreso());
      case '/juego/casos':
        return respuestaJson({
          'casos': [
            _resumen(
              'carrera_mas_estudiantes',
              'novato',
              'El edificio más lleno',
              20,
              true,
              1,
              20,
            ),
            _resumen(
              'carrera_mas_riesgo',
              'investigador',
              'La facultad en apuros',
              40,
              resuelto,
              intentos,
              resuelto ? 40 : 0,
            ),
            _resumen(
              'edad_y_riesgo',
              'experto',
              '¿La edad importa?',
              60,
              false,
              0,
              0,
            ),
          ],
        });
      case '/juego/casos/carrera_mas_riesgo':
        return respuestaJson({
          'codigo': 'carrera_mas_riesgo',
          'nivel': 'investigador',
          'titulo': 'La facultad en apuros',
          'enunciado': '¿Qué carrera tiene el mayor porcentaje de estudiantes en riesgo?',
          'opciones': [
            {'valor': 'Derecho', 'texto': 'Derecho'},
            {'valor': 'Medicina', 'texto': 'Medicina'},
          ],
          'grafica': '/estudiantes/estadisticas/riesgo-por-carrera',
          'xp': 40,
          'resuelto': resuelto,
          'intentos': intentos,
        });
      case '/estudiantes/estadisticas/riesgo-por-carrera':
        return respuestaJson([
          {'etiqueta': 'Medicina', 'valor': 33.33},
          {'etiqueta': 'Derecho', 'valor': 26.53},
        ]);
      case '/juego/casos/carrera_mas_riesgo/responder':
        intentos++;
        final correcto = cuerpo['respuesta'] == 'Medicina';
        final primeraVez = correcto && !resuelto;
        final ganada = primeraVez ? (intentos == 1 ? 40 : 20) : 0;
        if (correcto) resuelto = true;
        final nivelAntes = _nivel(xp).nombre;
        xp += ganada;
        return respuestaJson({
          'correcto': correcto,
          'xp_ganada': ganada,
          'dato': correcto
              ? 'Medicina: 33,33 % de sus estudiantes está en riesgo.'
              : 'Derecho: 26,53 % de sus estudiantes está en riesgo.',
          'explicacion': correcto
              ? 'Medicina tiene el porcentaje más alto.'
              : null,
          'pista': correcto ? null : 'Cuenta el porcentaje, no el número.',
          'intento': intentos,
          'insignias_nuevas': [
            if (primeraVez)
              insigniaJson('primera_pista', 'Primera pista', obtenida: true),
          ],
          'progreso': {
            'xp': xp,
            'nivel': _nivel(xp).nombre,
            'subio_de_nivel': _nivel(xp).nombre != nivelAntes,
          },
        });
      case '/juego/ranking':
        final semana = p.url.queryParameters['periodo'] != 'siempre';
        return respuestaJson({
          'periodo': semana ? 'semana' : 'siempre',
          'desde': semana ? '2026-10-06T05:00:00.000000Z' : null,
          'jugadores': [
            {
              'posicion': 1,
              'alias': 'Detective_Luz',
              'xp': semana ? 310 : 900,
              'nivel': 'Inspector',
              'soy_yo': false,
            },
            {
              'posicion': 2,
              'alias': 'Detective_Ana',
              'xp': xp,
              'nivel': _nivel(xp).nombre,
              'soy_yo': true,
            },
          ],
          'yo': {'posicion': 2, 'xp': xp},
        });
      case '/juego/jugadores':
        return respuestaJson([
          {
            'id': 7,
            'alias': 'Detective_Ana',
            'activo': true,
            'xp': xp,
            'nivel': 'Novato',
            'casos_resueltos': 1,
            'rescates_logrados': 0,
            'insignias': 1,
            'ultima_actividad': null,
          },
        ]);
      case '/usuarios/lote':
        final aliases = (cuerpo['aliases']! as List<Object?>).cast<String>();
        final chocan = aliases
            .where((a) => aliasesExistentes.contains(a.toLowerCase()))
            .toList();
        if (chocan.isNotEmpty) {
          return ServidorFalso.json({
            'detail': {
              'codigo': 'alias_en_uso',
              'mensaje':
                  'Algunos alias ya están en uso; no se creó ninguna cuenta',
              'aliases': chocan,
            },
          }, 409);
        }
        return ServidorFalso.json({
          'cuentas': [
            for (final (i, a) in aliases.indexed)
              {'id': 100 + i, 'alias': a, 'password': 'k7mq-x3hp-9tf$i'},
          ],
        }, 201);
    }
    throw http.ClientException('Connection refused', p.url);
  }

  ({int numero, String nombre, int desde}) _nivel(int xp) => xp >= 400
      ? (numero: 3, nombre: 'Inspector', desde: 400)
      : xp >= 150
      ? (numero: 2, nombre: 'Investigador', desde: 150)
      : (numero: 1, nombre: 'Novato', desde: 0);

  Map<String, Object?> _progreso() {
    final n = _nivel(xp);
    final siguiente = switch (n.numero) {
      1 => {'numero': 2, 'nombre': 'Investigador', 'xp_desde': 150},
      2 => {'numero': 3, 'nombre': 'Inspector', 'xp_desde': 400},
      _ => {'numero': 4, 'nombre': 'Jefe de datos', 'xp_desde': 800},
    };
    return {
      'alias': 'Detective_Ana',
      'xp': xp,
      'nivel': {'numero': n.numero, 'nombre': n.nombre, 'xp_desde': n.desde},
      'siguiente_nivel': siguiente,
      'racha_dias': 2,
      'casos_resueltos': resuelto ? 2 : 1,
      'casos_total': 9,
      'rescates_logrados': 3,
      'estrellas_totales': 7,
      'insignias': [
        insigniaJson('primera_pista', 'Primera pista', obtenida: true),
        insigniaJson('primer_rescate', 'Primer rescate', obtenida: true),
        insigniaJson('rescatista', 'Rescatista'),
      ],
    };
  }

  static Map<String, Object?> _resumen(
    String codigo,
    String nivel,
    String titulo,
    int xp,
    bool resuelto,
    int intentos,
    int ganada,
  ) => {
    'codigo': codigo,
    'nivel': nivel,
    'titulo': titulo,
    'xp': xp,
    'resuelto': resuelto,
    'intentos': intentos,
    'xp_ganada': ganada,
  };
}
