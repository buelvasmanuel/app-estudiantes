import 'package:app_estudiantes/models/estadistica.dart';
import 'package:app_estudiantes/screens/graficas_screen.dart';
import 'package:app_estudiantes/theme.dart';
import 'package:app_estudiantes/widgets/grafica_barras.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_falsa.dart';

void main() {
  testWidgets('carga por-carrera, cambia de tipo y usa la caché', (
    tester,
  ) async {
    final registro = <String>[];
    final api = apiFalsa({
      '/estudiantes/estadisticas/por-carrera': [
        {'etiqueta': 'Derecho', 'valor': 49},
        {'etiqueta': 'Medicina', 'valor': 30},
      ],
      '/estudiantes/estadisticas/riesgo-por-carrera': [
        {'etiqueta': 'Medicina', 'valor': 33.33},
      ],
    }, registro: registro);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.claro,
        home: GraficasScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GraficaBarras), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('Derecho'), findsWidgets); // eje X y resumen
    expect(find.text('79'), findsOneWidget); // total en el resumen

    // Cambiar a "Riesgo por carrera" con el DropdownMenu.
    await tester.tap(find.byType(DropdownMenu<TipoEstadistica>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riesgo por carrera').last);
    await tester.pumpAndSettle();
    expect(find.text('33.3%'), findsWidgets);

    // Volver a por-carrera no repite la petición.
    await tester.tap(find.byType(DropdownMenu<TipoEstadistica>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estudiantes por carrera').last);
    await tester.pumpAndSettle();
    expect(registro.where((r) => r.endsWith('/por-carrera')), hasLength(1));
  });

  testWidgets('error de la API en una estadística muestra Reintentar', (
    tester,
  ) async {
    final api = apiFalsa({});
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.claro,
        home: GraficasScreen(api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
