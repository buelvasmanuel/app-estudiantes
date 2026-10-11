import 'dart:convert';

import 'package:app_estudiantes/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_falsa.dart';

const avisoModelo =
    'Estimación de un modelo estadístico entrenado con datos simulados. '
    'Muestra asociaciones (correlación), no causas.';

/// `ExplicacionOut` del ejemplo del contrato (§2).
Map<String, Object?> explicacionJson({double probabilidad = 0.8123}) => {
  'probabilidad': probabilidad,
  'en_riesgo': probabilidad >= 0.5,
  'base': {'probabilidad': 0.1557, 'logit': -1.6912},
  'logit': 1.4652,
  'aportes': [
    {
      'variable': 'asistencia',
      'valor': 58,
      'aporte': 1.9071,
      'peso': 0.5634,
      'efecto': 'sube',
    },
    {
      'variable': 'horas_estudio',
      'valor': 6,
      'aporte': 0.8102,
      'peso': 0.2393,
      'efecto': 'sube',
    },
    {
      'variable': 'carrera',
      'valor': 'Medicina',
      'aporte': 0.3820,
      'peso': 0.1128,
      'efecto': 'sube',
    },
    {
      'variable': 'edad',
      'valor': 19,
      'aporte': 0.1974,
      'peso': 0.0583,
      'efecto': 'sube',
    },
    {
      'variable': 'semestre',
      'valor': 2,
      'aporte': -0.0886,
      'peso': 0.0262,
      'efecto': 'baja',
    },
  ],
  'modelo': {'nombre': 'Regresión Logística (juego)', 'version': '2026-10-11'},
  'aviso': avisoModelo,
};

/// `GET /laboratorio/casos/17` del ejemplo del contrato (§4.3).
Map<String, Object?> casoJson({int asistencia = 58}) => {
  'estudiante': {
    'id': 17,
    'nombre': 'Ana',
    'apellido': 'Gómez',
    'edad': 19,
    'carrera': 'Medicina',
    'semestre': 2,
    'horas_estudio': 6,
    'asistencia': asistencia,
  },
  'probabilidad': 0.8123,
  'presupuesto': 5,
  'objetivo': 0.5,
  'intervenciones': [
    {
      'codigo': 'estudio',
      'nombre': 'Plan de estudio',
      'fichas': 1,
      'variable': 'horas_estudio',
      'incremento': 2,
      'tope': 40,
      'efecto': '+2 h de estudio por semana',
    },
    {
      'codigo': 'tutoria',
      'nombre': 'Tutoría',
      'fichas': 2,
      'variable': 'asistencia',
      'incremento': 10,
      'tope': 100,
      'efecto': '+10 puntos de asistencia',
    },
  ],
  'explicacion': explicacionJson(),
  'aviso': avisoModelo,
};

/// Probabilidad simulada: baja 3 puntos por cada hora y 2 por cada punto de
/// asistencia respecto a Ana (6 h, 58 %). Con ella, lo óptimo son 2 tutorías
/// (4 fichas → 41 %): 1 tutoría + 1 estudio (3 fichas) se queda en 55 %.
double probabilidadSimulada(int horas, int asistencia) =>
    (0.8123 - 0.03 * (horas - 6) - 0.02 * (asistencia - 58)).clamp(0.01, 0.99);

/// API simulada del Laboratorio. [registro] guarda `MÉTODO ruta`.
ApiService laboratorioFalso({List<String>? registro, bool sinCasos = false}) =>
    ApiService(
      baseUrl: 'http://api.test',
      client: MockClient((peticion) async {
        final ruta = peticion.url.path;
        registro?.add('${peticion.method} $ruta');
        final cuerpo = peticion.body.isEmpty
            ? const <String, Object?>{}
            : jsonDecode(peticion.body) as Map<String, Object?>;
        switch (ruta) {
          case '/laboratorio/casos':
            return respuestaJson({
              'casos': sinCasos
                  ? <Object?>[]
                  : [
                      {
                        'estudiante_id': 17,
                        'nombre': 'Ana',
                        'apellido': 'Gómez',
                        'carrera': 'Medicina',
                        'semestre': 2,
                        'probabilidad': 0.8123,
                      },
                    ],
              'presupuesto': 5,
              'objetivo': 0.5,
            });
          case '/laboratorio/casos/17':
            return respuestaJson(casoJson());
          case '/prediccion/riesgo/lote':
            final entradas = (cuerpo['entradas']! as List<Object?>)
                .cast<Map<String, Object?>>();
            return respuestaJson({
              'resultados': [
                for (final e in entradas)
                  {
                    'probabilidad': probabilidadSimulada(
                      e['horas_estudio']! as int,
                      e['asistencia']! as int,
                    ),
                    'en_riesgo': false,
                  },
              ],
              'modelo': {'nombre': 'x', 'version': 'y'},
              'aviso': avisoModelo,
            });
          case '/laboratorio/casos/17/resolver':
            final codigos = (cuerpo['intervenciones']! as List<Object?>)
                .cast<String>();
            final e = codigos.where((c) => c == 'estudio').length;
            final t = codigos.where((c) => c == 'tutoria').length;
            final fichas = e + 2 * t;
            final horas = (6 + 2 * e).clamp(0, 40);
            final asistencia = (58 + 10 * t).clamp(0, 100);
            final p = probabilidadSimulada(horas, asistencia);
            final logrado = p < 0.5;
            const optimas = 4;
            return respuestaJson({
              'logrado': logrado,
              'estrellas': !logrado
                  ? 0
                  : fichas <= optimas
                  ? 3
                  : fichas == optimas + 1
                  ? 2
                  : 1,
              'fichas_usadas': fichas,
              'fichas_optimas': optimas,
              'probabilidad_inicial': 0.8123,
              'probabilidad_final': p,
              'estado_final': {
                'horas_estudio': horas,
                'asistencia': asistencia,
              },
              'solucion_optima': {
                'estudio': 0,
                'tutoria': 2,
                'fichas': 4,
                'probabilidad': probabilidadSimulada(6, 78),
              },
              'explicacion_final': explicacionJson(probabilidad: p),
              'aviso': avisoModelo,
            });
        }
        throw http.ClientException('Connection refused', peticion.url);
      }),
    );
