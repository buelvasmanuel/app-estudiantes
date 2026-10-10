// Prueba de extremo a extremo contra la API REAL (no simulada).
//
// Requiere la API corriendo:  uvicorn app.main:app --reload --host 0.0.0.0
// Ejecutar:                    flutter test integration_test -d linux
import 'package:app_estudiantes/main.dart';
import 'package:app_estudiantes/models/estadistica.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Espera (con red real) hasta que aparezca [finder] o pase [maximo].
Future<void> esperarA(
  WidgetTester tester,
  Finder finder, {
  Duration maximo = const Duration(seconds: 15),
}) async {
  final limite = DateTime.now().add(maximo);
  while (DateTime.now().isBefore(limite)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('No apareció a tiempo: $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('las pestañas cargan datos de la API real', (tester) async {
    await tester.pumpWidget(EstudiantesApp(api: ApiService()));

    // --- Estudiantes ---
    await esperarA(tester, find.byType(ListTile));
    expect(find.text('Sin conexión con la API'), findsNothing);
    expect(find.textContaining(RegExp(r'^En riesgo \(\d+\)$')), findsOneWidget);
    // ignore: avoid_print
    print(
      'Estudiantes OK: ${find.byType(ListTile).evaluate().length} filas visibles',
    );

    // --- Gráficas: los 6 tipos ---
    await tester.tap(find.text('Gráficas'));
    await esperarA(tester, find.byType(BarChart));
    for (final tipo in TipoEstadistica.values) {
      await tester.tap(find.byType(DropdownMenu<TipoEstadistica>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tipo.nombre).last);
      await esperarA(tester, find.byType(BarChart));
      expect(find.text('Reintentar'), findsNothing, reason: tipo.ruta);
      // ignore: avoid_print
      print('Gráfica ${tipo.ruta} OK');
    }
  });
}
