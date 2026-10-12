// Un duelo entero contra el Búho Máquina en la API real, y sus capturas.
//
//   flutter test integration_test/duelo_real_test.dart -d linux \
//     --dart-define=TEMA=noche \
//     --dart-define=API_URL=https://… \
//     --dart-define=ALIAS=… --dart-define=PASSWORD=… \
//     --dart-define=CAPTURAS_DIR=$PWD/docs/capturas
//
// Si hay un duelo a medias lo retoma; si no, empieza uno. Juega siempre el
// atributo con el percentil más alto. Sin CAPTURAS_DIR no guarda imágenes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_estudiantes/duelo/cartas.dart';
import 'package:app_estudiantes/juego/celebracion.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/duelo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_real.dart';
import 'app_real_test.dart' show esperarA;

const _dir = String.fromEnvironment('CAPTURAS_DIR');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final clave = GlobalKey();
  final tema = temaDePrueba.name;
  final hechas = <String>{};

  Future<void> capturar(WidgetTester tester, String nombre) async {
    await tester.pumpAndSettle();
    if (_dir.isEmpty || !hechas.add(nombre)) return;
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final imagen = await boundary.toImage(pixelRatio: 2);
      final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    });
    final archivo = File('$_dir/$tema/$nombre.png');
    await archivo.parent.create(recursive: true);
    await archivo.writeAsBytes(bytes!);
    // ignore: avoid_print
    print('Captura: ${archivo.path}');
  }

  String texto(String clave) =>
      (find.byKey(Key(clave)).evaluate().single.widget as Text).data!;

  String marcador() =>
      (find.byKey(const Key('marcador')).evaluate().single.widget as Text)
          .textSpan!
          .toPlainText();

  testWidgets('un duelo contra la máquina en la API real', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    final tokens = (await tester.runAsync(sesionReal))!;
    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: appReal(tokens: tokens, inicial: Rutas.casos),
      ),
    );

    // La tarjeta "¿Un duelo?", arriba en Casos.
    await esperarA(tester, find.byKey(const Key('tarjeta-duelo')));
    await capturar(tester, '16_duelo_tarjeta');
    await tester.tap(find.byKey(const Key('tarjeta-duelo')));
    await esperarA(tester, find.byKey(const Key('fase-duelo')));
    // ignore: avoid_print
    print('Al abrir: ${texto('fase-duelo')} · ${marcador()}');

    final explicaciones = <String>[];
    for (var paso = 0; paso < 20; paso++) {
      await tester.pumpAndSettle();
      // La celebración va encima del resultado: primero ella.
      if (find.byType(CelebracionVista).evaluate().isNotEmpty) {
        await capturar(tester, '21_duelo_insignia');
        await tester.tap(find.text('¡Seguir!'));
        continue;
      }
      if (find.byKey(const Key('resultado-duelo')).evaluate().isNotEmpty) {
        break;
      }
      if (find.byKey(const Key('continuar-duelo')).evaluate().isNotEmpty) {
        await capturar(tester, '18_duelo_revelado');
        explicaciones.add(
          (find
                      .descendant(
                        of: find.byKey(const Key('explicacion-duelo')),
                        matching: find.byKey(const Key('frase-buho')),
                      )
                      .evaluate()
                      .single
                      .widget
                  as Text)
              .data!,
        );
        await tester.tap(find.byKey(const Key('continuar-duelo')));
        continue;
      }
      final rival = find.byKey(const Key('ver-jugada-rival'));
      if (rival.evaluate().isNotEmpty) {
        await capturar(tester, '19_duelo_turno_rival');
        await tester.tap(rival);
      } else {
        await capturar(tester, '17_duelo_tu_turno');
        // El atributo con el percentil más alto de mi carta.
        final filas = tester
            .widgetList<FilaAtributo>(
              find.descendant(
                of: find.byKey(const Key('mi-carta')),
                matching: find.byType(FilaAtributo),
              ),
            )
            .toList();
        filas.sort((a, b) => b.valor.percentil.compareTo(a.valor.percentil));
        await tester.tap(find.byKey(Key('atributo-${filas.first.codigo}')));
      }
      await esperarA(
        tester,
        find.byKey(const Key('continuar-duelo')).hitTestable(),
      );
    }

    expect(find.byKey(const Key('resultado-duelo')), findsOneWidget);
    expect(explicaciones, isNotEmpty);
    for (final e in explicaciones) {
      expect(e, contains('percentil'));
    }
    await capturar(tester, '20_duelo_resultado');
    // ignore: avoid_print
    print(
      'Resultado: ${texto('resultado-duelo')} · ${marcador()} · '
      '${texto('xp-duelo')} · ${texto('xp-hoy')}\n'
      'Explicaciones:\n${explicaciones.join('\n')}',
    );
    expect(find.byType(DueloScreen), findsOneWidget);
  });
}
