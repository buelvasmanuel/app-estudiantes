import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/tema/temas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_de_prueba.dart';
import 'support/fuentes_reales.dart';
import 'support/juego_falso.dart';

Future<NavigationDestinationLabelBehavior?> _etiquetas(
  WidgetTester tester, {
  required double ancho,
  required double escala,
  required TemaJuego tema,
}) async {
  await tester.runAsync(cargarFuentesReales);
  tester.view.physicalSize = Size(ancho, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    appDePrueba(JuegoFalso().api(), inicial: Rutas.casos, tema: tema),
  );
  await tester.pumpAndSettle();
  return tester.widget<NavigationBar>(find.byType(NavigationBar)).labelBehavior;
}

void main() {
  for (final tema in TemaJuego.values) {
    testWidgets('360 px con letra normal (${tema.name}): todas las etiquetas', (
      tester,
    ) async {
      expect(
        await _etiquetas(tester, ancho: 360, escala: 1.0, tema: tema),
        NavigationDestinationLabelBehavior.alwaysShow,
      );
    });

    testWidgets(
      '360 px con letra al 130 % (${tema.name}): solo la elegida (antes '
      '«Laboratorio» se partía en dos líneas)',
      (tester) async {
        expect(
          await _etiquetas(tester, ancho: 360, escala: 1.3, tema: tema),
          NavigationDestinationLabelBehavior.onlyShowSelected,
        );
      },
    );
  }
}
