// Capturas del README en un tema (412×915, datos reales de la API).
//
//   flutter test integration_test/capturas_test.dart -d linux \
//     --dart-define=TEMA=noche \
//     --dart-define=API_URL=http://127.0.0.1:8001 \
//     --dart-define=ALIAS=… --dart-define=PASSWORD=… \
//     --dart-define=CAPTURAS_DIR=$PWD/docs/capturas
//
// Las guarda en CAPTURAS_DIR/<tema>/. Recorre: acceso, tutorial, campus,
// casos, laboratorio, datos y perfil. La cuenta debe tener algún caso y
// algún rescate hechos para que el perfil tenga insignias.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_estudiantes/laboratorio/providers.dart';
import 'package:app_estudiantes/laboratorio/rescate.dart';
import 'package:app_estudiantes/preferencias.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/acceso_screen.dart';
import 'package:app_estudiantes/screens/campus_screen.dart';
import 'package:app_estudiantes/screens/caso_juego_screen.dart';
import 'package:app_estudiantes/screens/rescate_screen.dart';
import 'package:app_estudiantes/screens/tutorial_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_real.dart';
import 'app_real_test.dart' show esperarA;

const _dir = String.fromEnvironment('CAPTURAS_DIR', defaultValue: 'capturas');
const _alias = String.fromEnvironment('ALIAS');
const _password = String.fromEnvironment('PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final clave = GlobalKey();
  final tema = temaDePrueba.name;

  // El Campus (Flame) solo avanza con el tiempo real.
  Future<void> esperar(WidgetTester tester, [int ms = 600]) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(Duration(milliseconds: ms)),
    );
    await tester.pump();
  }

  Future<void> capturar(
    WidgetTester tester,
    String nombre, {
    bool asentar = true,
  }) async {
    if (asentar) await tester.pumpAndSettle();
    await esperar(tester, 300);
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

  Future<void> desplazarHasta(WidgetTester tester, Finder f) =>
      tester.scrollUntilVisible(
        f,
        250,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );

  testWidgets('capturas del tema', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    // Como un dispositivo nuevo: sin tutorial visto, con el tema elegido.
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

    // --- Acceso y tutorial ---
    await esperarA(tester, find.byType(AccesoScreen));
    await capturar(tester, '01_acceso');
    await tester.enterText(find.byKey(const Key('alias')), _alias);
    await tester.enterText(find.byKey(const Key('password')), _password);
    await tester.tap(find.text('Entrar'));
    await esperarA(tester, find.byType(TutorialScreen));
    await capturar(tester, '02_tutorial');
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
    }
    await capturar(tester, '03_tutorial_eleccion');
    await tester.tap(find.text('¡A investigar!'));

    // --- Campus ---
    await esperarA(tester, find.byType(CampusVista));
    await esperar(tester, 2000); // ventanas encendidas
    await capturar(tester, '04_campus', asentar: false);

    // --- Casos ---
    await tester.tap(find.text('Casos'));
    await esperarA(tester, find.text('La facultad en apuros'));
    await capturar(tester, '05_casos');
    await tester.tap(find.text('La facultad en apuros'));
    await esperarA(tester, find.textContaining('Ficha del caso'));
    await tester.pumpAndSettle();
    final opcion = find.byKey(const Key('opcion-Medicina'));
    await tester.ensureVisible(opcion);
    await tester.tap(opcion);
    await tester.pump();
    await tester.tap(find.text('Responder'));
    await esperarA(tester, find.byKey(const Key('veredicto')));
    await tester.pumpAndSettle();
    if (find.text('¡Seguir!').evaluate().isNotEmpty) {
      await tester.tap(find.text('¡Seguir!'));
      await tester.pumpAndSettle();
    }
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
    await capturar(tester, '06_caso_resuelto');

    // --- Laboratorio: el rescate óptimo del caso más grave ---
    await tester.tap(find.text('Laboratorio'));
    await esperarA(tester, find.text('Caso al azar'));
    await capturar(tester, '07_laboratorio');
    final contenedor = ProviderScope.containerOf(
      tester.element(find.text('Caso al azar')),
    );
    final lista = (await tester.runAsync(
      () => contenedor.read(casosProvider.future),
    ))!;
    final primero = lista.casos.first;
    await tester.tap(find.text(primero.nombreCompleto).first);
    await esperarA(tester, find.text('Confirmar rescate'));
    final (caso, mapa) = (await tester.runAsync(
      () async => (
        await contenedor.read(casoProvider(primero.estudianteId).future),
        await contenedor.read(
          probabilidadesProvider(primero.estudianteId).future,
        ),
      ),
    ))!;
    await tester.pumpAndSettle();
    List<int>? optima;
    var coste = 99;
    var p = 1.0;
    for (final c in Rescate.combinaciones(caso)) {
      final pc = mapa[Rescate.claveDe(c)]!;
      final fc = [
        for (final (i, n) in c.indexed) n * caso.intervenciones[i].fichas,
      ].fold(0, (a, b) => a + b);
      if (pc < caso.objetivo && (fc < coste || (fc == coste && pc < p))) {
        (optima, coste, p) = (c, fc, pc);
      }
    }
    for (final (i, n) in optima!.indexed) {
      for (var k = 0; k < n; k++) {
        await tester.tap(
          find.textContaining('${caso.intervenciones[i].nombre} ·'),
        );
        await tester.pumpAndSettle();
      }
    }
    await capturar(tester, '08_rescate');
    await tester.tap(find.text('Confirmar rescate'));
    await esperarA(tester, find.byType(Estrellas));
    await tester.pumpAndSettle();
    if (find.text('¡Seguir!').evaluate().isNotEmpty) {
      await tester.tap(find.text('¡Seguir!'));
      await tester.pumpAndSettle();
    }
    await capturar(tester, '09_resultado');

    // --- Datos ---
    await tester.tap(find.text('Datos'));
    await esperarA(tester, find.byType(ListTile));
    await capturar(tester, '10_datos_estudiantes');
    await tester.tap(find.text('Gráficas'));
    await esperarA(tester, find.byType(BarChart));
    await capturar(tester, '11_datos_graficas');
    await tester.tap(find.text('Predicción'));
    await esperarA(tester, find.text('Elige una carrera para predecir'));
    await capturar(tester, '12_datos_prediccion');

    // --- Perfil ---
    await tester.tap(find.text('Perfil'));
    await esperarA(tester, find.textContaining('Insignias ·'));
    await capturar(tester, '13_perfil');
    await desplazarHasta(tester, find.textContaining('Insignias ·'));
    await capturar(tester, '14_perfil_insignias');
    await tester.tap(find.text('Ranking'));
    await esperarA(tester, find.textContaining('(tú)'));
    await capturar(tester, '15_ranking');
  });
}
