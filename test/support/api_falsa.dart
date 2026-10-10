import 'dart:convert';

import 'package:app_estudiantes/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Respuestas de ejemplo con la MISMA forma que la API real.
const estudiantesJson = [
  {
    'id': 1,
    'nombre': 'Jorge',
    'apellido': 'Rodríguez',
    'edad': 19,
    'carrera': 'Psicología',
    'semestre': 3,
    'promedio': '3.95',
    'ciudad': 'Medellín',
    'horas_estudio': 24,
    'asistencia': 91,
  },
  {
    'id': 2,
    'nombre': 'Esperanza',
    'apellido': 'Torres',
    'edad': 17,
    'carrera': 'Medicina',
    'semestre': 2,
    'promedio': '2.79',
    'ciudad': 'Bogotá',
    'horas_estudio': 14,
    'asistencia': 74,
  },
];

http.Response respuestaJson(Object? cuerpo, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(cuerpo)),
      status,
      headers: {'content-type': 'application/json'},
    );

/// ApiService que responde según la ruta; [rutas] mapea path → cuerpo JSON.
/// Si una ruta no está, simula que la API está caída.
ApiService apiFalsa(Map<String, Object?> rutas, {List<String>? registro}) {
  return ApiService(
    baseUrl: 'http://api.test',
    client: MockClient((peticion) async {
      registro?.add('${peticion.method} ${peticion.url.path}');
      if (!rutas.containsKey(peticion.url.path)) {
        throw http.ClientException('Connection refused', peticion.url);
      }
      final cuerpo = rutas[peticion.url.path];
      return cuerpo is http.Response ? cuerpo : respuestaJson(cuerpo);
    }),
  );
}

/// Forma real de GET /prediccion/metricas (recortada).
const metricasJson = {
  'modelo': 'Regresión Logística',
  'criterio_seleccion': 'F2 medio en validación cruzada (5 particiones)',
  'entrenado': '2026-10-10T16:55:43',
  'carreras_validas': ['Derecho', 'Medicina', 'Psicología'],
  'datos': {'total': 300, 'porcentaje_en_riesgo': 18.3},
  'metricas_prueba': {
    'accuracy': 0.917,
    'precision': 0.8,
    'recall': 0.727,
    'f2': 0.741,
  },
  'importancias': {
    'horas_estudio': -1.558,
    'asistencia': -2.071,
    'semestre': -0.089,
  },
};
