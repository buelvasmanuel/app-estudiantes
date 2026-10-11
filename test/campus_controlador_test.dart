import 'dart:ui';

import 'package:app_estudiantes/campus/controlador.dart';
import 'package:app_estudiantes/campus/disposicion.dart';
import 'package:app_estudiantes/campus/modelo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/estudiantes_de_prueba.dart';

void main() {
  late ControladorCampus c;

  setUp(() {
    c = ControladorCampus(
      Campus.desde([
        for (var i = 0; i < 11; i++) est('Derecho', 2),
        for (var i = 0; i < 5; i++) est('Medicina', 3, promedio: 2),
        est('Psicología', 5),
        est('Arquitectura', 1),
      ]),
    )..ajustarA(const Size(412, 500));
  });

  bool visibleEntera(Rect zona) {
    final arribaIzq = c.vista.aPantalla(zona.topLeft, c.tamano);
    final abajoDer = c.vista.aPantalla(zona.bottomRight, c.tamano);
    return (Offset.zero & c.tamano).inflate(0.5).contains(arribaIzq) &&
        (Offset.zero & c.tamano).inflate(0.5).contains(abajoDer);
  }

  test('al empezar se ve el campus entero', () {
    expect(visibleEntera(c.disposicion!.limites), isTrue);
  });

  test('si solo cambia el alto (panel), la rejilla no cambia y el edificio '
      'elegido sigue encuadrado', () {
    final derecho = c.campus.edificios.first;
    final disposicion = c.disposicion;
    c.seleccionarEdificio(derecho);

    c.ajustarA(const Size(412, 260)); // se abre el panel inferior
    expect(c.disposicion, same(disposicion));
    expect(visibleEntera(c.disposicion!.zonaDe(derecho)), isTrue);
  });

  test('si cambia el ancho (girar el celular), se recalcula la rejilla', () {
    final antes = c.disposicion!.columnas;
    c.ajustarA(const Size(900, 380));
    expect(c.disposicion!.columnas, isNot(antes));
    expect(visibleEntera(c.disposicion!.limites), isTrue);
  });

  test('tocar salta la animación de entrada y selecciona', () {
    c.encendido = 0.3;
    final derecho = c.campus.edificios.first;
    final centro = c.vista.aPantalla(
      c.disposicion!.cuerpos[derecho]!.center,
      c.tamano,
    );
    c.tocar(centro);
    expect(c.encendido, 1);
    expect(c.edificioSeleccionado, derecho);
  });

  test('buscar un estudiante acerca hasta poder tocar su ventana', () {
    final alumno = c.campus.edificios.first.pisos[1][5];
    c.seleccionarEstudiante(alumno);
    expect(c.estudianteSeleccionado, alumno);
    expect(
      c.vista.zoom * Medidas.ventanaAncho,
      greaterThanOrEqualTo(Medidas.ventanaTocableMin),
    );
    final ventana = c.vista.aPantalla(
      c.disposicion!.ventanas[alumno.id]!.center,
      c.tamano,
    );
    c.tocar(ventana);
    expect(c.estudianteSeleccionado, alumno);
  });

  test('el zoom no se sale de sus límites', () {
    for (var i = 0; i < 20; i++) {
      c.alejar();
    }
    final minimo = c.vista.zoom;
    expect(minimo, greaterThan(0));
    for (var i = 0; i < 20; i++) {
      c.acercar();
    }
    expect(c.vista.zoom, Vista.zoomMax);
  });

  test('solo en riesgo y cerrar notifican a la interfaz', () {
    var avisos = 0;
    c.addListener(() => avisos++);
    c
      ..alternarSoloRiesgo()
      ..seleccionarEdificio(c.campus.edificios.first)
      ..cerrarSeleccion();
    expect(c.soloRiesgo, isTrue);
    expect(c.seleccion, isNull);
    expect(avisos, 3);
  });
}
