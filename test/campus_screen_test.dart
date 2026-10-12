import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/campus_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_falsa.dart';
import 'support/app_de_prueba.dart';

/// El juego dibuja en cada fotograma: aquí nunca se usa pumpAndSettle.
Future<void> _avanzar(WidgetTester tester, [int ms = 300]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<CampusVistaState> _abrir(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = apiFalsa({'/estudiantes/': estudiantesJson});
  await tester.pumpWidget(appDePrueba(api, inicial: Rutas.campus));
  await _avanzar(tester, 100);
  return tester.state<CampusVistaState>(find.byType(CampusVista));
}

void main() {
  testWidgets('leyenda con las cifras y lista de edificios (mayor primero)', (
    tester,
  ) async {
    await _abrir(tester);
    expect(find.text('En riesgo 1'), findsOneWidget);
    expect(find.text('Sin riesgo 1'), findsOneWidget);
    // Empate a 1 estudiante: por nombre.
    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((c) => (c.label as Text).data)
        .toList();
    expect(chips, ['Medicina · 1/1', 'Psicología · 0/1']);
  });

  testWidgets('las ventanas se encienden en ~1,2 s y un toque lo salta', (
    tester,
  ) async {
    final campus = await _abrir(tester);
    final c = campus.controlador;
    expect(c.animacionTerminada, isFalse);
    await _avanzar(tester, 1300);
    expect(c.animacionTerminada, isTrue);

    c.encendido = 0.2;
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('lienzo-campus'))),
    );
    await tester.pump();
    expect(c.animacionTerminada, isTrue);
  });

  testWidgets('con "reducir movimiento" todo aparece ya encendido', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final campus = await _abrir(tester);
    expect(campus.controlador.reducirMovimiento, isTrue);
    expect(campus.controlador.animacionTerminada, isTrue);

    // El panel aparece sin transición.
    await tester.tap(find.text('Medicina · 1/1'));
    await tester.pump();
    expect(find.text('1 estudiante'), findsOneWidget);
  });

  testWidgets('tocar un edificio en el mapa abre su expediente', (
    tester,
  ) async {
    final campus = await _abrir(tester);
    final c = campus.controlador;
    final medicina = c.campus.edificios.first;
    final origen = tester.getTopLeft(find.byKey(const Key('lienzo-campus')));
    await tester.tapAt(
      origen +
          c.vista.aPantalla(c.disposicion!.cuerpos[medicina]!.center, c.tamano),
    );
    await _avanzar(tester);
    expect(find.textContaining('En riesgo: 1 (100\u00A0%)'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar'));
    await _avanzar(tester, 600);
    expect(find.textContaining('En riesgo: 1'), findsNothing);
  });

  testWidgets('"Ver estudiantes" abre la lista filtrada por esa carrera', (
    tester,
  ) async {
    await _abrir(tester);
    await tester.tap(find.text('Medicina · 1/1'));
    await _avanzar(tester);
    await tester.tap(find.text('Ver estudiantes'));
    await _avanzar(tester, 600);

    expect(find.text('Carrera: Medicina'), findsOneWidget);
    expect(find.text('Esperanza Torres'), findsOneWidget);
    expect(find.text('Jorge Rodríguez'), findsNothing);

    // Quitar el filtro muestra a todos.
    await tester.tap(find.byTooltip('Quitar el filtro de carrera'));
    await _avanzar(tester, 600);
    expect(find.text('Jorge Rodríguez'), findsOneWidget);
  });

  testWidgets('buscar un estudiante lo señala y muestra su ficha', (
    tester,
  ) async {
    final campus = await _abrir(tester);
    await tester.tap(find.byTooltip('Buscar estudiante'));
    await _avanzar(tester, 600);
    await tester.enterText(find.byType(TextField).last, 'esperanza');
    await _avanzar(tester);
    await tester.tap(find.text('Esperanza Torres').last);
    await _avanzar(tester, 600);

    expect(campus.controlador.estudianteSeleccionado?.id, 2);
    expect(find.text('Ver ficha'), findsOneWidget);
    expect(find.text('En riesgo académico'), findsOneWidget);
  });

  testWidgets('en otra pestaña el juego se pausa', (tester) async {
    final campus = await _abrir(tester);
    expect(campus.juego.paused, isFalse);
    await tester.tap(find.text('Datos'));
    await _avanzar(tester, 600);
    expect(campus.juego.paused, isTrue);
    await tester.tap(find.text('Campus'));
    await _avanzar(tester);
    expect(campus.juego.paused, isFalse);
  });
}
