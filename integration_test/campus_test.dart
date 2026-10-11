// El Campus con los datos REALES de la API, a tamaño de celular (412×915).
// Comprueba que se dibujan los 300 estudiantes y guarda capturas.
//
//   flutter test integration_test/campus_test.dart -d linux \
//     --dart-define=API_URL=https://api-tienda-wjac.onrender.com \
//     --dart-define=CAPTURAS_DIR=$PWD/docs/capturas
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_estudiantes/campus/disposicion.dart';
import 'package:app_estudiantes/screens/campus_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_real_test.dart' show esperarA;
import 'app_real.dart';

const _dir = String.fromEnvironment('CAPTURAS_DIR', defaultValue: 'capturas');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final clave = GlobalKey();

  // El juego dibuja en cada fotograma: pumpAndSettle no terminaría nunca.
  // Y el bucle de Flame avanza con el tiempo REAL, no con el de pump.
  Future<void> esperar(
    WidgetTester tester, [
    Duration tiempo = const Duration(milliseconds: 500),
  ]) async {
    await tester.pump(); // el juego se carga y arranca su bucle en un fotograma
    await tester.runAsync(() => Future<void>.delayed(tiempo));
    await tester.pump();
  }

  Future<void> capturar(WidgetTester tester, String nombre) async {
    await esperar(tester);
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

  testWidgets('campus con datos reales', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: appReal(inicial: '/campus'),
      ),
    );
    await esperarA(
      tester,
      find.byType(CampusVista),
      maximo: const Duration(seconds: 75),
    );
    // La animación de entrada dura 1,2 s.
    await esperar(tester, const Duration(seconds: 2));

    final estado = tester.state<CampusVistaState>(find.byType(CampusVista));
    final c = estado.controlador;
    final campus = c.campus;
    // ignore: avoid_print
    print(
      'Campus: ${campus.edificios.length} edificios, ${campus.total} '
      'estudiantes, ${campus.enRiesgo} en riesgo, '
      '${c.disposicion!.columnas} columnas, zoom ${c.vista.zoom.toStringAsFixed(2)}',
    );
    expect(c.disposicion!.ventanas, hasLength(campus.total));
    expect(c.animacionTerminada, isTrue);
    await capturar(tester, '7_campus');

    // Expediente del edificio más grande, elegido desde la lista accesible.
    final mayor = campus.edificios.first;
    await tester.tap(find.textContaining('${mayor.carrera} ·'));
    await esperar(tester);
    expect(find.text('${mayor.total} estudiantes'), findsOneWidget);
    await capturar(tester, '8_campus_expediente');

    // Tocar una ventana (con ese zoom ya se pueden tocar).
    final alumno = mayor.pisos[1].first;
    final enMundo = c.disposicion!.ventanas[alumno.id]!.center;
    final caja = tester.getTopLeft(find.byKey(const Key('lienzo-campus')));
    expect(
      c.vista.zoom * Medidas.ventanaAncho,
      greaterThanOrEqualTo(Medidas.ventanaTocableMin),
    );
    await tester.tapAt(caja + c.vista.aPantalla(enMundo, c.tamano));
    await esperar(tester);
    expect(find.text(alumno.nombreCompleto), findsOneWidget);
    await capturar(tester, '9_campus_estudiante');
  });
}
