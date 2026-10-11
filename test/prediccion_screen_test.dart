import 'dart:convert';

import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:app_estudiantes/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'support/api_falsa.dart';
import 'support/app_de_prueba.dart';

Future<void> _abrir(WidgetTester tester, ApiService api) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(appDePrueba(api, inicial: Rutas.prediccion));
  await tester.pumpAndSettle();
}

Future<void> _elegirCarrera(WidgetTester tester, String carrera) async {
  await tester.tap(find.byType(DropdownMenu<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(carrera).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('carga las carreras, envía el formulario y muestra el riesgo', (
    tester,
  ) async {
    Map<String, Object?>? enviado;
    final api = ApiService(
      baseUrl: 'http://api.test',
      client: MockClient((peticion) async {
        if (peticion.url.path == '/prediccion/metricas') {
          return respuestaJson(metricasJson);
        }
        enviado = jsonDecode(peticion.body) as Map<String, Object?>;
        return respuestaJson({
          'en_riesgo': true,
          'probabilidad': 0.98,
          'modelo': 'Regresión Logística',
        });
      }),
    );
    await _abrir(tester, api);

    // Sin carrera, el botón está desactivado.
    expect(find.text('Elige una carrera para predecir'), findsOneWidget);
    expect(find.text('Recall'), findsOneWidget); // métricas del modelo

    await _elegirCarrera(tester, 'Medicina');
    await tester.tap(find.text('Predecir'));
    await tester.pumpAndSettle();

    expect(enviado, {
      'horas_estudio': 14,
      'asistencia': 82,
      'semestre': 3,
      'edad': 20,
      'carrera': 'Medicina',
    });
    expect(find.text('En riesgo académico'), findsOneWidget);
    expect(find.text('98\u00A0%'), findsOneWidget);
    expect(
      find.text('Indicador orientativo del modelo, no un diagnóstico'),
      findsOneWidget,
    );

    // El color de la tarjeta es el de "riesgo" del tema.
    final tarjeta = tester.widget<Card>(
      find.ancestor(
        of: find.text('En riesgo académico'),
        matching: find.byType(Card),
      ),
    );
    expect(tarjeta.color, ColoresEstado.expediente.riesgoContenedor);

    // Mover un slider marca el resultado como desactualizado.
    await tester.drag(find.byType(Slider).first, const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cambiaste los datos'), findsOneWidget);
  });

  testWidgets('sin riesgo se muestra en verde', (tester) async {
    final api = apiFalsa({
      '/prediccion/metricas': metricasJson,
      '/prediccion/riesgo': {
        'en_riesgo': false,
        'probabilidad': 0.12,
        'modelo': 'Regresión Logística',
      },
    });
    await _abrir(tester, api);
    await _elegirCarrera(tester, 'Derecho');
    await tester.tap(find.text('Predecir'));
    await tester.pumpAndSettle();

    expect(find.text('Sin riesgo académico'), findsOneWidget);
    expect(find.text('12\u00A0%'), findsOneWidget);
    final tarjeta = tester.widget<Card>(
      find.ancestor(
        of: find.text('Sin riesgo académico'),
        matching: find.byType(Card),
      ),
    );
    expect(tarjeta.color, ColoresEstado.expediente.okContenedor);
  });

  testWidgets('modelo sin entrenar (503) muestra el mensaje y Reintentar', (
    tester,
  ) async {
    final api = apiFalsa({
      '/prediccion/metricas': respuestaJson({
        'detail':
            'Modelo no entrenado. Ejecuta: python -m scripts.entrenar_modelo',
      }, 503),
    });
    await _abrir(tester, api);
    expect(
      find.textContaining('python -m scripts.entrenar_modelo'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
