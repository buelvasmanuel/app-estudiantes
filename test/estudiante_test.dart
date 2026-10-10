import 'package:app_estudiantes/models/estudiante.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_falsa.dart';

void main() {
  group('Estudiante.fromJson', () {
    test('lee promedio cuando llega como String (Decimal de Python)', () {
      final e = Estudiante.fromJson(estudiantesJson.first);
      expect(e.promedio, 3.95);
      expect(e.nombreCompleto, 'Jorge Rodríguez');
      expect(e.horasEstudio, 24);
      expect(e.enRiesgo, isFalse);
    });

    test('lee promedio cuando llega como num (int o double)', () {
      final base = Map<String, Object?>.of(estudiantesJson.first);
      expect(Estudiante.fromJson({...base, 'promedio': 2.5}).promedio, 2.5);
      expect(Estudiante.fromJson({...base, 'promedio': 4}).promedio, 4.0);
    });

    test('enRiesgo es estricto: < 3.0', () {
      final base = Map<String, Object?>.of(estudiantesJson.first);
      expect(
        Estudiante.fromJson({...base, 'promedio': '2.99'}).enRiesgo,
        isTrue,
      );
      expect(
        Estudiante.fromJson({...base, 'promedio': '3.00'}).enRiesgo,
        isFalse,
      );
    });

    test('campo faltante → FormatException', () {
      final base = Map<String, Object?>.of(estudiantesJson.first)
        ..remove('carrera');
      expect(() => Estudiante.fromJson(base), throwsFormatException);
    });

    test('normalizar quita tildes y mayúsculas', () {
      expect(normalizar('Ingeniería Bogotá ÑU'), 'ingenieria bogota nu');
    });
  });
}
