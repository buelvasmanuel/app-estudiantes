import 'package:app_estudiantes/laboratorio/apariencia.dart';
import 'package:app_estudiantes/laboratorio/modelo.dart';
import 'package:app_estudiantes/laboratorio/textos.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/rescate_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_de_prueba.dart';
import 'support/laboratorio_falso.dart';

String _porcentaje(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('porcentaje-medidor'))).data!;

String _fraseBuho(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('frase-buho'))).data!;

Future<void> _abrirCaso(WidgetTester tester, List<String> registro) async {
  tester.view.physicalSize = const Size(412, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    appDePrueba(
      laboratorioFalso(registro: registro),
      inicial: Rutas.laboratorio,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ana Gómez'));
  await tester.pumpAndSettle();
}

Future<void> _aplicar(WidgetTester tester, String nombre) async {
  await tester.tap(find.textContaining('$nombre ·'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('la lista muestra los casos y el riesgo estimado', (
    tester,
  ) async {
    final registro = <String>[];
    await _abrirCaso(tester, registro);
    expect(registro.first, 'GET /laboratorio/casos');
    expect(find.byType(RescateScreen), findsOneWidget);
    expect(_porcentaje(tester), '81\u00A0%');
    expect(_fraseBuho(tester), startsWith('Según el modelo'));
    // El aviso del modelo está siempre a la vista.
    expect(find.textContaining('correlación'), findsOneWidget);
  });

  testWidgets('jugar: el medidor sigue las fichas sin pedir nada más', (
    tester,
  ) async {
    final registro = <String>[];
    await _abrirCaso(tester, registro);

    await _aplicar(tester, 'Tutoría');
    expect(_porcentaje(tester), '61\u00A0%');
    expect(find.text('Quedan 3 de 5'), findsOneWidget);
    expect(_fraseBuho(tester), contains('Aún por encima de 50\u00A0%'));

    await _aplicar(tester, 'Tutoría');
    expect(_porcentaje(tester), '41\u00A0%');
    expect(
      _fraseBuho(tester),
      startsWith('Según el modelo bajaría a 41\u00A0%'),
    );
    // Queda 1 ficha: la tutoría (2) ya no cabe; el plan de estudio (1) sí.
    expect(find.text('No te quedan fichas suficientes'), findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(_porcentaje(tester), '61\u00A0%');

    // Todas las probabilidades llegaron en UNA petición al principio.
    expect(registro.where((r) => r.endsWith('/lote')), hasLength(1));
    expect(registro.where((r) => r.contains('resolver')), isEmpty);
  });

  testWidgets('confirmar muestra lo que decide el servidor', (tester) async {
    final semantica = tester.ensureSemantics();
    final registro = <String>[];
    await _abrirCaso(tester, registro);
    await _aplicar(tester, 'Tutoría');
    await _aplicar(tester, 'Tutoría');
    await tester.tap(find.text('Confirmar rescate'));
    await tester.pumpAndSettle();

    expect(registro.last, 'POST /laboratorio/casos/17/resolver');
    expect(find.text('¡Rescatado!'), findsOneWidget);
    expect(find.bySemanticsLabel('3 de 3 estrellas'), findsOneWidget);
    semantica.dispose();
    expect(find.textContaining('Lo mínimo era 4'), findsOneWidget);
    expect(find.text('¿Por qué?'), findsOneWidget);
    expect(
      find.text(
        'Según el modelo, la asistencia pesó 2,4 veces más que las horas '
        'de estudio.',
      ),
      findsOneWidget,
    );
    expect(_fraseBuho(tester), contains('no qué las causa'));
    expect(find.textContaining('correlación'), findsWidgets);

    await tester.tap(find.text('Intentar de nuevo'));
    await tester.pumpAndSettle();
    expect(_porcentaje(tester), '81\u00A0%');
    expect(find.text('Quedan 5 de 5'), findsOneWidget);
  });

  testWidgets('con "reducir movimiento" las estrellas no se animan', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _abrirCaso(tester, []);
    await _aplicar(tester, 'Tutoría');
    await _aplicar(tester, 'Tutoría');
    await tester.tap(find.text('Confirmar rescate'));
    await tester.pump(); // respuesta del servidor
    await tester.pump(); // un solo fotograma: ya deben estar completas
    final escalas = tester
        .widgetList<ScaleTransition>(
          find.descendant(
            of: find.byType(Estrellas),
            matching: find.byType(ScaleTransition),
          ),
        )
        .map((s) => s.scale.value);
    expect(escalas, everyElement(1.0));
  });

  group('textos', () {
    final caso = Caso.fromJson(casoJson());

    test('el búho siempre habla de lo que estima el modelo', () {
      for (final p in [null, 0.7, 0.4]) {
        final b = buhoDuranteRescate(
          caso: caso,
          fichasUsadas: p == null ? 0 : 2,
          probabilidad: p,
        );
        expect(b.frase, startsWith('Según el modelo'));
      }
    });

    test('al empezar señala la palanca que más pesa', () {
      final b = buhoDuranteRescate(
        caso: caso,
        fichasUsadas: 0,
        probabilidad: null,
      );
      expect(b.animo, AnimoBuho.atento);
      expect(b.frase, contains('asistencia (58\u00A0%)'));
    });
  });
}
