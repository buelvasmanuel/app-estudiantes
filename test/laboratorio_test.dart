import 'package:app_estudiantes/laboratorio/laboratorio_api.dart';
import 'package:app_estudiantes/laboratorio/modelo.dart';
import 'package:app_estudiantes/laboratorio/rescate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/laboratorio_falso.dart';

void main() {
  group('modelo (ejemplos del contrato)', () {
    test('caso: estudiante, catálogo y explicación', () {
      final caso = Caso.fromJson(casoJson());
      expect(caso.estudiante.nombreCompleto, 'Ana Gómez');
      expect(caso.presupuesto, 5);
      expect(caso.intervenciones.map((i) => (i.codigo, i.fichas)), [
        ('estudio', 1),
        ('tutoria', 2),
      ]);
      final aportes = caso.explicacion.aportes;
      expect(aportes.first.variable, 'asistencia');
      expect(aportes.first.efecto, Efecto.sube);
      expect(aportes[2].valor, 'Medicina');
      expect(aportes.last.efecto, Efecto.baja);
      expect(caso.explicacion.aviso, contains('correlación'));
    });

    test('la solución óptima separa conteos de fichas y probabilidad', () {
      final s = SolucionOptima.fromJson({
        'estudio': 1,
        'tutoria': 1,
        'fichas': 3,
        'probabilidad': 0.489,
      });
      expect(s.porIntervencion, {'estudio': 1, 'tutoria': 1});
      expect(s.fichas, 3);
    });
  });

  group('Rescate', () {
    final caso = Caso.fromJson(casoJson());
    final estudio = caso.intervenciones[0];
    final tutoria = caso.intervenciones[1];

    test('aplica, cuenta fichas y deshace en orden', () {
      final r = Rescate(caso).con(tutoria).con(estudio);
      expect(r.fichasUsadas, 3);
      expect(r.valor('asistencia'), 68);
      expect(r.valor('horas_estudio'), 8);
      expect(r.codigos, ['tutoria', 'estudio']);
      expect(r.deshacer().codigos, ['tutoria']);
      expect(r.reiniciar().fichasUsadas, 0);
    });

    test('no deja pasar del presupuesto', () {
      final r = Rescate(caso).con(tutoria).con(tutoria).con(estudio);
      expect(r.fichasRestantes, 0);
      expect(r.sePuedeAplicar(estudio), isFalse);
      expect(r.con(estudio), same(r));
    });

    test('respeta el tope: asistencia 95 + tutoría = 100, y después nada', () {
      final casi = Caso.fromJson(casoJson(asistencia: 95));
      final r = Rescate(casi).con(casi.intervenciones[1]);
      expect(r.valor('asistencia'), 100);
      expect(r.enTope(casi.intervenciones[1]), isTrue);
      expect(r.sePuedeAplicar(casi.intervenciones[1]), isFalse);
    });

    test('con 5 fichas y el catálogo del contrato hay 12 combinaciones', () {
      final combinaciones = Rescate.combinaciones(caso);
      expect(combinaciones, hasLength(12));
      for (final c in combinaciones) {
        expect(c[0] * 1 + c[1] * 2, lessThanOrEqualTo(5));
      }
    });
  });

  group('LaboratorioApi', () {
    test('pide todas las combinaciones en UNA petición', () async {
      final registro = <String>[];
      final api = LaboratorioApi(laboratorioFalso(registro: registro));
      final caso = await api.caso(17);
      final mapa = await api.probabilidades(caso);
      expect(mapa, hasLength(12));
      expect(mapa['0,0'], closeTo(0.8123, 1e-9));
      expect(mapa['0,2'], closeTo(0.4123, 1e-9)); // 2 tutorías
      expect(registro.where((r) => r.contains('/lote')), hasLength(1));
    });

    test('resolver devuelve lo que decide el servidor', () async {
      final api = LaboratorioApi(laboratorioFalso());
      final r = await api.resolver(17, ['tutoria', 'tutoria']);
      expect(r.logrado, isTrue);
      expect(r.estrellas, 3);
      expect(r.solucionOptima.porIntervencion, {'estudio': 0, 'tutoria': 2});
    });
  });
}
