// PROTOTIPO (Fase 6): capturas del Campus y de un caso con una identidad.
//
//   flutter test integration_test/identidad_test.dart -d linux \
//     --dart-define=IDENTIDAD=noche \
//     --dart-define=API_URL=http://127.0.0.1:8001 \
//     --dart-define=ALIAS=… --dart-define=PASSWORD=… \
//     --dart-define=CAPTURAS_DIR=/ruta/de/salida
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_estudiantes/identidad.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/campus_screen.dart';
import 'package:app_estudiantes/screens/caso_juego_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_real.dart';
import 'app_real_test.dart' show esperarA;

const _dir = String.fromEnvironment('CAPTURAS_DIR', defaultValue: 'capturas');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final clave = GlobalKey();
  final nombre = Identidad.activa.name;

  // El Campus (Flame) avanza con el tiempo real.
  Future<void> esperar(WidgetTester tester, [int ms = 600]) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: ms)),
    );
    await tester.pump();
  }

  Future<void> capturar(WidgetTester tester, String archivo) async {
    await esperar(tester);
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final imagen = await boundary.toImage(pixelRatio: 2);
      final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    });
    final f = File('$_dir/$archivo.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes!);
    // ignore: avoid_print
    print('Captura: ${f.path}');
  }

  testWidgets('capturas de la identidad', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    final tokens = (await tester.runAsync(sesionReal))!;
    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: appReal(tokens: tokens, inicial: Rutas.campus),
      ),
    );
    await esperarA(tester, find.byType(CampusVista));
    await esperar(tester, 2000); // animación de entrada
    await capturar(tester, '${nombre}_1_campus');

    // Un caso: el de la ficha de riesgo por carrera, respondido.
    await tester.tap(find.text('Casos'));
    await esperarA(tester, find.text('La facultad en apuros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('La facultad en apuros'));
    await esperarA(tester, find.textContaining('Ficha del caso'));
    await tester.pumpAndSettle();
    final opcion = find.widgetWithText(ChoiceChip, 'Medicina');
    await tester.ensureVisible(opcion);
    await tester.tap(opcion);
    await tester.pump();
    await tester.tap(find.text('Responder'));
    await esperarA(tester, find.byKey(const Key('veredicto')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('frase-buho')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CasoJuegoScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await capturar(tester, '${nombre}_2_caso');
  });
}
