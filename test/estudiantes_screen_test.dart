import 'package:app_estudiantes/screens/estudiante_detalle_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_falsa.dart';
import 'support/app_de_prueba.dart';

void main() {
  testWidgets('muestra la lista, el contador de riesgo y abre el detalle', (
    tester,
  ) async {
    final api = apiFalsa({'/estudiantes/': estudiantesJson});
    await tester.pumpWidget(appDePrueba(api));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('Jorge Rodríguez'), findsOneWidget);
    expect(find.text('Esperanza Torres'), findsOneWidget);
    expect(find.text('3,95'), findsOneWidget);
    expect(find.text('En riesgo (1)'), findsOneWidget);

    await tester.tap(find.text('Esperanza Torres'));
    await tester.pumpAndSettle();
    expect(find.byType(EstudianteDetalleScreen), findsOneWidget);
    expect(find.textContaining('En riesgo académico'), findsOneWidget);
  });

  testWidgets('el buscador ignora tildes y el filtro deja solo los de riesgo', (
    tester,
  ) async {
    final api = apiFalsa({'/estudiantes/': estudiantesJson});
    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(SearchBar), 'rodriguez');
    await tester.pump();
    expect(find.text('Jorge Rodríguez'), findsOneWidget);
    expect(find.text('Esperanza Torres'), findsNothing);

    await tester.enterText(find.byType(SearchBar), '');
    await tester.tap(find.text('En riesgo (1)'));
    await tester.pump();
    expect(find.text('Jorge Rodríguez'), findsNothing);
    expect(find.text('Esperanza Torres'), findsOneWidget);
  });

  testWidgets('sin API muestra el error y Reintentar vuelve a pedir', (
    tester,
  ) async {
    final rutas = <String, Object?>{};
    final registro = <String>[];
    final api = apiFalsa(rutas, registro: registro);
    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión con la API'), findsOneWidget);
    expect(find.textContaining('No se pudo conectar'), findsOneWidget);

    rutas['/estudiantes/'] = estudiantesJson; // "arrancamos" la API
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(sinProgreso(registro), hasLength(2));
    expect(find.text('Jorge Rodríguez'), findsOneWidget);
  });
}
