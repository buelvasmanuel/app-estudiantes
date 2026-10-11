import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/estudiante_detalle_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_falsa.dart';
import 'support/app_de_prueba.dart';

/// Todas las rutas que usan las 3 pestañas al abrirse.
Map<String, Object?> _rutasCompletas() => {
  '/estudiantes/': estudiantesJson,
  '/estudiantes/estadisticas/por-carrera': [
    {'etiqueta': 'Medicina', 'valor': 30},
  ],
  '/prediccion/metricas': metricasJson,
};

void main() {
  testWidgets('al arrancar solo se pide la pestaña visible; las demás al '
      'abrirlas, y una sola vez', (tester) async {
    final registro = <String>[];
    final api = apiFalsa(_rutasCompletas(), registro: registro);
    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();
    expect(registro, ['GET /estudiantes/']);

    await tester.tap(find.text('Gráficas'));
    await tester.pumpAndSettle();
    expect(registro.last, 'GET /estudiantes/estadisticas/por-carrera');

    await tester.tap(find.text('Predicción'));
    await tester.pumpAndSettle();
    expect(registro.last, 'GET /prediccion/metricas');

    await tester.tap(find.text('Estudiantes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gráficas'));
    await tester.pumpAndSettle();
    expect(registro, hasLength(3));
  });

  testWidgets('cambiar de pestaña conserva la búsqueda', (tester) async {
    final api = apiFalsa(_rutasCompletas());
    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(SearchBar), 'rodriguez');
    await tester.pump();
    await tester.tap(find.text('Gráficas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estudiantes'));
    await tester.pumpAndSettle();

    expect(find.text('rodriguez'), findsOneWidget);
    expect(find.text('Esperanza Torres'), findsNothing);
  });

  testWidgets('el detalle tapa la barra de pestañas y "atrás" vuelve a la '
      'lista', (tester) async {
    final api = apiFalsa(_rutasCompletas());
    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jorge Rodríguez'));
    await tester.pumpAndSettle();
    expect(find.byType(EstudianteDetalleScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(EstudianteDetalleScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('enlace directo a /estudiantes/2 abre el detalle', (
    tester,
  ) async {
    final api = apiFalsa(_rutasCompletas());
    await tester.pumpWidget(appDePrueba(api, inicial: Rutas.estudiante(2)));
    await tester.pumpAndSettle();

    expect(find.byType(EstudianteDetalleScreen), findsOneWidget);
    expect(find.text('Esperanza Torres'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Jorge Rodríguez'), findsOneWidget);
  });

  testWidgets('enlace directo a un estudiante que no existe', (tester) async {
    final api = apiFalsa(_rutasCompletas());
    await tester.pumpWidget(appDePrueba(api, inicial: Rutas.estudiante(99)));
    await tester.pumpAndSettle();
    expect(
      find.text('No existe un estudiante con ese número.'),
      findsOneWidget,
    );
  });

  testWidgets('si falla al actualizar, se conserva la lista y se avisa', (
    tester,
  ) async {
    final rutas = _rutasCompletas();
    final api = apiFalsa(rutas);
    await tester.pumpWidget(appDePrueba(api));
    await tester.pumpAndSettle();

    rutas.remove('/estudiantes/'); // la API "se cae"
    await tester.tap(find.byTooltip('Actualizar'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('No se pudo conectar'), findsOneWidget);
    expect(find.text('Jorge Rodríguez'), findsOneWidget);
  });
}
