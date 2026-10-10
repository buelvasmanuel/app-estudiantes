// Genera capturas PNG de la app con datos REALES de la API (para el README).
//
//   flutter test integration_test/capturas_test.dart -d linux \
//     --dart-define=CAPTURAS_DIR=$PWD/docs/capturas
//
// La app se renderiza a tamaño de celular (412×915) dentro de un
// RepaintBoundary y se guarda con toImage(): no captura tu escritorio.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_estudiantes/main.dart';
import 'package:app_estudiantes/models/estadistica.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_real_test.dart' show esperarA;

const _dir = String.fromEnvironment('CAPTURAS_DIR', defaultValue: 'capturas');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final clave = GlobalKey();

  Future<void> capturar(WidgetTester tester, String nombre) async {
    await tester.pumpAndSettle();
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final imagen = await boundary.toImage(pixelRatio: 2);
      final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    });
    final archivo = File('$_dir/$nombre.png');
    await archivo.parent.create(recursive: true);
    await archivo.writeAsBytes(bytes!);
    // ignore: avoid_print
    print('Captura: ${archivo.path}');
  }

  Future<void> elegirGrafica(WidgetTester tester, TipoEstadistica tipo) async {
    await tester.tap(find.byType(DropdownMenu<TipoEstadistica>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tipo.nombre).last);
    await esperarA(tester, find.byType(BarChart));
  }

  testWidgets('capturas', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: EstudiantesApp(api: ApiService()),
      ),
    );

    await esperarA(tester, find.byType(ListTile));
    await capturar(tester, '1_estudiantes');

    await tester.tap(find.byType(ListTile).at(1));
    await capturar(tester, '2_detalle');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gráficas'));
    await esperarA(tester, find.byType(BarChart));
    await capturar(tester, '3_grafica_por_carrera');
    for (final tipo in [
      TipoEstadistica.porEdad,
      TipoEstadistica.porCiudad,
      TipoEstadistica.promedioPorCarrera,
      TipoEstadistica.riesgoPorCarrera,
    ]) {
      await elegirGrafica(tester, tipo);
      await capturar(tester, '3_grafica_${tipo.ruta.replaceAll('-', '_')}');
    }
  });
}
