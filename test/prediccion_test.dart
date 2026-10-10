import 'package:app_estudiantes/models/prediccion.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_falsa.dart';

void main() {
  group('ResultadoPrediccion.fromJson', () {
    test('probabilidad como double', () {
      final r = ResultadoPrediccion.fromJson({
        'en_riesgo': true,
        'probabilidad': 0.98,
        'modelo': 'Regresión Logística',
      });
      expect(r.enRiesgo, isTrue);
      expect(r.probabilidad, 0.98);
      expect(r.porcentaje, 98);
      expect(r.modelo, 'Regresión Logística');
    });

    test('probabilidad como int (0 o 1)', () {
      final r = ResultadoPrediccion.fromJson({
        'en_riesgo': false,
        'probabilidad': 0,
        'modelo': 'Árbol',
      });
      expect(r.probabilidad, isA<int>());
      expect(r.porcentaje, 0);
      expect(
        ResultadoPrediccion.fromJson({
          'en_riesgo': true,
          'probabilidad': 1,
          'modelo': 'x',
        }).porcentaje,
        100,
      );
    });

    test('en_riesgo que no es bool → FormatException', () {
      expect(
        () => ResultadoPrediccion.fromJson({
          'en_riesgo': 'si',
          'probabilidad': 0.5,
          'modelo': 'x',
        }),
        throwsFormatException,
      );
    });
  });

  test('EntradaPrediccion.toJson usa las claves de la API', () {
    const entrada = EntradaPrediccion(
      horasEstudio: 6,
      asistencia: 70,
      semestre: 2,
      edad: 18,
      carrera: 'Medicina',
    );
    expect(entrada.toJson(), {
      'horas_estudio': 6,
      'asistencia': 70,
      'semestre': 2,
      'edad': 18,
      'carrera': 'Medicina',
    });
    expect(
      entrada,
      const EntradaPrediccion(
        horasEstudio: 6,
        asistencia: 70,
        semestre: 2,
        edad: 18,
        carrera: 'Medicina',
      ),
    );
  });

  group('MetricasModelo.fromJson', () {
    test('lee carreras, métricas y ordena las variables por influencia', () {
      final m = MetricasModelo.fromJson(metricasJson);
      expect(m.modelo, 'Regresión Logística');
      expect(m.carrerasValidas, ['Derecho', 'Medicina', 'Psicología']);
      expect(m.totalDatos, 300);
      expect(m.recall, 0.727);
      expect(m.entrenado, DateTime(2026, 10, 10, 16, 55, 43));
      expect(m.variablesInfluyentes, [
        'asistencia',
        'horas_estudio',
        'semestre',
      ]);
    });

    test('solo modelo y carreras son obligatorios', () {
      final m = MetricasModelo.fromJson({
        'modelo': 'X',
        'carreras_validas': ['A'],
      });
      expect(m.carrerasValidas, ['A']);
      expect(m.recall, isNull);
      expect(m.variablesInfluyentes, isEmpty);
      expect(
        () => MetricasModelo.fromJson({'modelo': 'X'}),
        throwsFormatException,
      );
    });
  });
}
