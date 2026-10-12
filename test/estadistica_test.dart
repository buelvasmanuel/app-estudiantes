import 'package:app_estudiantes/models/estadistica.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Estadistica.fromJson', () {
    test('valor como int (conteo) y como double (promedio/porcentaje)', () {
      final lista = Estadistica.listaFromJson([
        {'etiqueta': 'Derecho', 'valor': 49},
        {'etiqueta': 'Arquitectura', 'valor': 3.5},
        {'etiqueta': 'Medicina', 'valor': 33.33},
      ]);
      expect(lista.map((e) => e.etiqueta), [
        'Derecho',
        'Arquitectura',
        'Medicina',
      ]);
      expect(lista[0].valor, isA<int>());
      expect(lista[0].valor, 49);
      expect(lista[1].valor, 3.5);
      expect(lista[2].valor, 33.33);
    });

    test('lista vacía y formato incorrecto', () {
      expect(Estadistica.listaFromJson(<Object?>[]), isEmpty);
      expect(() => Estadistica.listaFromJson({'x': 1}), throwsFormatException);
      expect(
        () => Estadistica.listaFromJson([
          {'etiqueta': 'A', 'valor': null},
        ]),
        throwsFormatException,
      );
    });
  });

  group('TipoEstadistica', () {
    test('hay 6 tipos con rutas de la API', () {
      expect(TipoEstadistica.values.map((t) => t.ruta), [
        'por-carrera',
        'por-edad',
        'por-semestre',
        'por-ciudad',
        'promedio-por-carrera',
        'riesgo-por-carrera',
      ]);
    });

    test('formatea según la unidad', () {
      expect(TipoEstadistica.porCarrera.formatear(49), '49');
      expect(TipoEstadistica.promedioPorCarrera.formatear(3.5), '3,50');
      expect(TipoEstadistica.riesgoPorCarrera.formatear(33.33), '33,3\u00A0%');
    });

    test('describir añade el grupo a las etiquetas numéricas', () {
      expect(TipoEstadistica.porEdad.describir('20'), 'edad 20');
      expect(TipoEstadistica.porCarrera.describir('Medicina'), 'Medicina');
    });

    test('máximo del eje Y deja aire y respeta los límites', () {
      expect(TipoEstadistica.promedioPorCarrera.maximoEjeY([3.5, 3.1]), 5.4);
      expect(
        TipoEstadistica.porCarrera.maximoEjeY([10, 50]),
        closeTo(60, 1e-9),
      );
      expect(TipoEstadistica.riesgoPorCarrera.maximoEjeY([95]), 100);
      expect(TipoEstadistica.porEdad.maximoEjeY([]), 1);
    });
  });
}
