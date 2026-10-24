// Revisión de calidad: recorre todas las pantallas con la API real, como un
// usuario nuevo, y en cada una guarda una captura y anota los textos cortados
// (con «…») y los desbordamientos.
//
//   flutter test integration_test/revision_real_test.dart -d linux \
//     --dart-define=TEMA=noche --dart-define=ANCHO=360 --dart-define=ALTO=640 \
//     --dart-define=ESCALA=1.0 --dart-define=API_URL=https://… \
//     --dart-define=ALIAS=… --dart-define=PASSWORD=… \
//     --dart-define=REVISION_DIR=$HOME/Imágenes/revision
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_estudiantes/main.dart';
import 'package:app_estudiantes/preferencias.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/acceso_screen.dart';
import 'package:app_estudiantes/screens/tutorial_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_real.dart';
import 'app_real_test.dart' show esperarA;

const _dir = String.fromEnvironment('REVISION_DIR', defaultValue: 'revision');
const _ancho = int.fromEnvironment('ANCHO', defaultValue: 360);
const _alto = int.fromEnvironment('ALTO', defaultValue: 640);
const _escala = String.fromEnvironment('ESCALA', defaultValue: '1.0');
const _alias = String.fromEnvironment('ALIAS');
const _password = String.fromEnvironment('PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final clave = GlobalKey();
  final tema = temaDePrueba.name;
  final carpeta = '$_dir/${tema}_${_ancho}x${_alto}_x$_escala';
  final problemas = <String>[];
  var pantalla = 'inicio';

  Future<void> esperar(WidgetTester tester, [int ms = 800]) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: ms)),
    );
    await tester.pump();
  }

  /// Textos que no caben (cortados con «…» o con líneas de más).
  void revisarTextos(WidgetTester tester) {
    for (final e in find.byType(RichText).evaluate()) {
      final r = e.renderObject;
      if (r is RenderParagraph && r.didExceedMaxLines) {
        final t = r.text.toPlainText().replaceAll('\n', ' ');
        problemas.add(
          '$pantalla: texto cortado «${t.length > 70 ? '${t.substring(0, 70)}…' : t}»',
        );
      }
    }
  }

  Future<void> capturar(WidgetTester tester, String nombre) async {
    pantalla = nombre;
    await esperar(tester, 600);
    revisarTextos(tester);
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 1.5);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
    });
    final f = File('$carpeta/$nombre.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes!);
  }

  testWidgets('revisión de todas las pantallas', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(_ancho.toDouble(), _alto.toDouble());
    tester.platformDispatcher.textScaleFactorTestValue = double.parse(_escala);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final anterior = FlutterError.onError;
    FlutterError.onError = (d) {
      final linea = d.exceptionAsString().split('\n').first;
      problemas.add('$pantalla: $linea');
    };

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: clave,
          child: appConLogin(
            inicial: Rutas.campus,
            preferencias: PreferenciasEnMemoria({
              Preferencias.claveTema: tema,
              Preferencias.claveTutorial: false,
            }),
          ),
        ),
      );
      GoRouterSimple ir() => GoRouterSimple(
        ProviderScope.containerOf(tester.element(find.byType(EstudiantesApp)))
            .read(routerProvider),
      );

      // --- Acceso ---
      await esperarA(tester, find.byType(AccesoScreen));
      await capturar(tester, '01_login');
      await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
      await esperar(tester);
      await capturar(tester, '02_registro');
      await tester.tap(find.text('¿Ya tienes cuenta? Inicia sesión'));
      await esperar(tester);
      await tester.enterText(find.byKey(const Key('alias')), _alias);
      await tester.enterText(find.byKey(const Key('password')), _password);
      await tester.tap(find.text('Entrar'));

      // --- Tutorial ---
      await esperarA(tester, find.byType(TutorialScreen));
      for (var i = 0; i < TutorialScreen.pasos; i++) {
        await capturar(tester, '0${4 + i}_tutorial_${i + 1}');
        if (i < TutorialScreen.pasos - 1) {
          await tester.tap(find.text('Siguiente'));
          await esperar(tester);
        }
      }
      await tester.tap(find.text('¡A investigar!'));

      // --- Pestañas y pantallas ---
      Future<void> visitar(
        String ruta,
        String nombre, {
        Finder? hasta,
        int ms = 2500,
      }) async {
        pantalla = nombre;
        ir().go(ruta);
        if (hasta != null) {
          await esperarA(tester, hasta);
        }
        await esperar(tester, ms);
        await capturar(tester, nombre);
      }

      await visitar(Rutas.campus, '10_campus', ms: 4000);
      await visitar(Rutas.casos, '11_casos', hasta: find.text('¿Un duelo?'));
      await visitar(Rutas.casoJuego('carrera_mas_estudiantes'), '12_caso');
      await visitar(
        Rutas.duelo,
        '13_duelo_elegir',
        hasta: find.text('¿Contra quién?'),
      );
      await visitar(
        Rutas.dueloMaquina,
        '14_duelo_maquina',
        hasta: find.byKey(const Key('fase-duelo')),
      );
      await visitar(Rutas.laboratorio, '15_laboratorio', ms: 3500);
      final caso = find.textContaining('fichas');
      if (caso.evaluate().isNotEmpty) {
        await tester.tap(caso.first);
        await esperar(tester, 3500);
        await capturar(tester, '16_rescate');
      }
      await visitar(
        Rutas.estudiantes,
        '17_estudiantes',
        hasta: find.byType(ListTile),
      );
      await tester.tap(find.byType(ListTile).first);
      await esperar(tester, 1500);
      await capturar(tester, '18_estudiante');
      await visitar(Rutas.graficas, '19_graficas', ms: 3500);
      await visitar(Rutas.prediccion, '20_prediccion', ms: 3500);
      final predecir = find.text('Predecir');
      if (predecir.evaluate().isNotEmpty) {
        await tester.ensureVisible(predecir);
        await tester.tap(predecir);
        await esperar(tester, 3000);
        await capturar(tester, '21_prediccion_resultado');
      }
      await visitar(Rutas.perfil, '22_perfil', ms: 3000);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await esperar(tester);
      await capturar(tester, '23_perfil_final');
      await tester.tap(find.text('Ranking'));
      await esperar(tester, 2500);
      await capturar(tester, '24_ranking');
      await tester.tap(find.byTooltip('Cuenta'));
      await esperar(tester);
      await capturar(tester, '25_menu_cuenta');
    } catch (e) {
      // ignore: avoid_print
      print('FALLO en «$pantalla»: $e');
      try {
        await capturar(tester, 'zz_fallo');
      } on Object {
        // sin captura
      }
      rethrow;
    } finally {
      FlutterError.onError = anterior;
    }
    final informe = File('$carpeta/problemas.txt');
    await informe.writeAsString(
      problemas.isEmpty
          ? 'Sin problemas detectados.\n'
          : '${problemas.toSet().join('\n')}\n',
    );
    // ignore: avoid_print
    print(
      'PROBLEMAS (${problemas.toSet().length}):\n${problemas.toSet().join('\n')}',
    );
  });
}

/// Solo lo que hace falta del router.
class GoRouterSimple {
  GoRouterSimple(this._router);
  final dynamic _router;
  void go(String ruta) => _router.go(ruta);
}
