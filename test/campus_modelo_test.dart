import 'dart:ui';

import 'package:app_estudiantes/campus/disposicion.dart';
import 'package:app_estudiantes/campus/modelo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/estudiantes_de_prueba.dart';

void main() {
  group('Campus', () {
    test('un edificio por carrera, de más a menos estudiantes', () {
      final campus = Campus.desde([
        est('Medicina', 1),
        est('Derecho', 1),
        est('Derecho', 2),
        est('Arquitectura', 3),
        est('Arquitectura', 4),
      ]);
      expect(
        campus.edificios.map((e) => e.carrera),
        ['Arquitectura', 'Derecho', 'Medicina'], // empate: por nombre
      );
      expect(campus.total, 5);
    });

    test('pisos = semestres; ventanas por id; ancho = piso más lleno', () {
      final campus = Campus.desde([
        est('Derecho', 2, id: 30),
        est('Derecho', 2, id: 10, promedio: 2.5),
        est('Derecho', 2, id: 20),
        est('Derecho', 10, id: 40),
      ]);
      final d = campus.edificios.single;
      expect(d.pisos, hasLength(10));
      expect(d.pisos[1].map((e) => e.id), [10, 20, 30]);
      expect(d.pisos[9].map((e) => e.id), [40]);
      expect(d.porSemestre, [0, 3, 0, 0, 0, 0, 0, 0, 0, 1]);
      expect(d.ancho, 3);
      expect(d.enRiesgo, 1);
      expect(d.porcentajeRiesgo, 25);
    });
  });

  group('Disposicion', () {
    final campus = Campus.desde([
      for (var i = 0; i < 11; i++) est('Derecho', 2),
      est('Derecho', 1),
      est('Medicina', 1),
      est('Psicología', 5),
    ]);

    test('el 1.er semestre abajo y el 10.º arriba; ventanas sin solaparse', () {
      final d = Disposicion.calcular(campus, 3);
      final derecho = campus.edificios.first;
      final s1 = d.ventanas[derecho.pisos[0].first.id]!;
      final s2 = d.ventanas[derecho.pisos[1].first.id]!;
      expect(s1.top, greaterThan(s2.top));
      final rects = d.ventanas.values.toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
      // Todas las ventanas dentro de la fachada de su edificio.
      for (final edificio in campus.edificios) {
        for (final e in edificio.pisos.expand((p) => p)) {
          expect(
            d.cuerpos[edificio]!
                    .inflate(0.01)
                    .contains(d.ventanas[e.id]!.topLeft) &&
                d.cuerpos[edificio]!
                    .inflate(0.01)
                    .contains(d.ventanas[e.id]!.bottomRight),
            isTrue,
          );
        }
      }
    });

    test('en un celular vertical elige más filas que en horizontal', () {
      final vertical = Disposicion.ajustada(campus, const Size(412, 500));
      final horizontal = Disposicion.ajustada(campus, const Size(900, 350));
      expect(vertical.columnas, lessThan(horizontal.columnas));
    });

    test('tocar: con poco zoom, el edificio; con mucho, la ventana', () {
      final d = Disposicion.calcular(campus, 3);
      final derecho = campus.edificios.first;
      final alumno = derecho.pisos[1][4];
      final centro = d.ventanas[alumno.id]!.center;

      expect(
        d.objetivoEn(centro, 1),
        isA<ObjetivoEdificio>().having((o) => o.edificio, 'edificio', derecho),
      );
      expect(
        d.objetivoEn(centro, 2),
        isA<ObjetivoEstudiante>().having(
          (o) => o.estudiante,
          'estudiante',
          alumno,
        ),
      );
      // Fuera de cualquier edificio: nada.
      expect(
        d.objetivoEn(d.limites.bottomRight + const Offset(50, 50), 2),
        isNull,
      );
    });
  });

  group('Vista', () {
    const tamano = Size(400, 600);

    test('pantalla → mundo → pantalla es la identidad', () {
      const v = Vista(centro: Offset(100, 50), zoom: 2.5);
      const p = Offset(37, 420);
      expect(v.aPantalla(v.aMundo(p, tamano), tamano), p);
    });

    test('encuadrar deja la zona entera dentro de la pantalla', () {
      const zona = Rect.fromLTWH(0, 0, 800, 300);
      final v = Vista.encuadrar(zona, tamano);
      final arribaIzq = v.aPantalla(zona.topLeft, tamano);
      final abajoDer = v.aPantalla(zona.bottomRight, tamano);
      expect(arribaIzq.dx, greaterThanOrEqualTo(0));
      expect(abajoDer.dx, lessThanOrEqualTo(tamano.width));
      expect(arribaIzq.dy, greaterThanOrEqualTo(0));
      expect(abajoDer.dy, lessThanOrEqualTo(tamano.height));
    });

    test('el zoom con foco deja quieto el punto del foco', () {
      const v = Vista(centro: Offset(10, 10), zoom: 1);
      const foco = Offset(300, 100);
      final antes = v.aMundo(foco, tamano);
      final despues = v.conZoom(3, foco, tamano);
      expect((despues.aMundo(foco, tamano) - antes).distance, lessThan(1e-9));
      expect(despues.zoom, 3);
    });
  });
}
