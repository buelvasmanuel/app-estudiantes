// La Fase 5 de punta a punta contra una API REAL con /juego.
//
//   flutter test integration_test/juego_real_test.dart -d linux \
//     --dart-define=API_URL=http://127.0.0.1:8001 \
//     --dart-define=ALIAS=… --dart-define=PASSWORD=… \
//     --dart-define=ALIAS_DOCENTE=… --dart-define=PASSWORD_DOCENTE=… \
//     --dart-define=CAPTURAS_DIR=$PWD/docs/capturas
//
// ALIAS es un jugador; ALIAS_DOCENTE, un docente (crearlo con
// `python -m scripts.crear_usuario <alias> --rol docente` en api-tienda).
// Crea 2 cuentas de alumno con alias nuevos en cada ejecución.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_estudiantes/juego/celebracion.dart';
import 'package:app_estudiantes/laboratorio/providers.dart';
import 'package:app_estudiantes/laboratorio/rescate.dart';
import 'package:app_estudiantes/models/estadistica.dart';
import 'package:app_estudiantes/providers.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/acceso_screen.dart';
import 'package:app_estudiantes/screens/caso_juego_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_real.dart';
import 'app_real_test.dart' show esperarA;

const _alias = String.fromEnvironment('ALIAS');
const _password = String.fromEnvironment('PASSWORD');
const _aliasDocente = String.fromEnvironment('ALIAS_DOCENTE');
const _passwordDocente = String.fromEnvironment('PASSWORD_DOCENTE');
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

  Future<void> entrar(
    WidgetTester tester,
    String alias,
    String password,
  ) async {
    await esperarA(tester, find.byType(AccesoScreen));
    await tester.enterText(find.byKey(const Key('alias')), alias);
    await tester.enterText(find.byKey(const Key('password')), password);
    await tester.tap(find.text('Entrar'));
    await esperarA(tester, find.byKey(const Key('chip-nivel')));
    await tester.pumpAndSettle();
  }

  Future<void> salir(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await esperarA(tester, find.byType(AccesoScreen));
  }

  testWidgets('casos, rescate, perfil, ranking y panel del docente', (
    tester,
  ) async {
    if ([_alias, _password, _aliasDocente, _passwordDocente].contains('')) {
      fail('Faltan ALIAS, PASSWORD, ALIAS_DOCENTE o PASSWORD_DOCENTE');
    }
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: appConLogin(inicial: Rutas.casos),
      ),
    );

    // --- Jugador: lista de casos ---
    await entrar(tester, _alias, _password);
    await esperarA(tester, find.textContaining('resueltos'));
    await capturar(tester, '13_casos');

    // --- Un caso con ficha: la respuesta se deduce de la gráfica real ---
    final contenedor = ProviderScope.containerOf(
      tester.element(find.textContaining('resueltos')),
    );
    final riesgo = (await tester.runAsync(
      () => contenedor.read(
        estadisticaProvider(TipoEstadistica.riesgoPorCarrera).future,
      ),
    ))!;
    final mayor = riesgo.reduce((a, b) => b.valor > a.valor ? b : a).etiqueta;
    await tester.tap(find.text('La facultad en apuros'));
    await esperarA(tester, find.byType(CasoJuegoScreen));
    await esperarA(tester, find.textContaining('Ficha del caso'));
    await tester.pumpAndSettle();
    final opcion = find.widgetWithText(ChoiceChip, mayor);
    await tester.ensureVisible(opcion);
    await tester.tap(opcion);
    await tester.pump();
    await tester.tap(
      find.text('Responder').evaluate().isNotEmpty
          ? find.text('Responder')
          : find.text('Probar con esta'),
    );
    await esperarA(tester, find.byKey(const Key('veredicto')));
    await tester.pump(const Duration(seconds: 2));
    if (find.byType(CelebracionVista).evaluate().isNotEmpty) {
      await capturar(tester, '14_celebracion');
      await tester.tap(find.text('¡Seguir!'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('¡Correcto!'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('frase-buho')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await capturar(tester, '15_caso_resuelto');
    // ignore: avoid_print
    print('Caso resuelto: $mayor');

    // --- Un rescate óptimo (por la API de la app, con la sesión real) ---
    final resultado = await tester.runAsync(() async {
      final lab = contenedor.read(laboratorioApiProvider);
      final caso = await lab.caso((await lab.casos()).casos.first.estudianteId);
      final mapa = await lab.probabilidades(caso);
      List<int>? mejor;
      var coste = 99;
      var p = 1.0;
      for (final c in Rescate.combinaciones(caso)) {
        final pc = mapa[Rescate.claveDe(c)]!;
        final fc =
            c[0] * caso.intervenciones[0].fichas +
            c[1] * caso.intervenciones[1].fichas;
        if (pc < caso.objetivo && (fc < coste || (fc == coste && pc < p))) {
          (mejor, coste, p) = (c, fc, pc);
        }
      }
      return lab.resolver(caso.estudiante.id, [
        for (final (i, n) in mejor!.indexed)
          for (var k = 0; k < n; k++) caso.intervenciones[i].codigo,
      ]);
    });
    // ignore: avoid_print
    print(
      'Rescate: ${resultado!.estrellas} estrellas, '
      '+${resultado.recompensa?.xpGanada} XP, insignias: '
      '${resultado.recompensa?.insigniasNuevas.map((i) => i.nombre).toList()}',
    );
    expect(resultado.recompensa, isNotNull, reason: 'La API local es v1.1');

    // --- Perfil y ranking ---
    await tester.tap(find.text('Perfil'));
    await esperarA(tester, find.textContaining('Insignias ·'));
    await tester.pumpAndSettle();
    await capturar(tester, '16_perfil');
    await tester.scrollUntilVisible(
      find.textContaining('Insignias ·'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await capturar(tester, '16b_perfil_insignias');
    await tester.tap(find.text('Ranking'));
    await esperarA(tester, find.textContaining('(tú)'));
    await capturar(tester, '17_ranking');

    // --- Docente: alta en lote y jugadores ---
    await salir(tester);
    await entrar(tester, _aliasDocente, _passwordDocente);
    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Panel del docente').last); // el del menú
    await esperarA(tester, find.byKey(const Key('aliases')));
    final sello = DateTime.now().millisecondsSinceEpoch % 100000;
    await tester.enterText(
      find.byKey(const Key('aliases')),
      'Alumna_$sello\nAlumno_$sello',
    );
    await tester.pump();
    await tester.tap(find.text('Crear 2 cuentas'));
    await esperarA(tester, find.textContaining('solo se muestran ahora'));
    // Sin captura: la pantalla muestra contraseñas reales.
    expect(find.textContaining('Alumna_'), findsOneWidget);
    await tester.tap(find.text('Copiar todas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jugadores'));
    await esperarA(tester, find.text(_alias));
    await capturar(tester, '19_docente_jugadores');
    // ignore: avoid_print
    print('Docente OK: cuentas Alumna_$sello y Alumno_$sello');
  });
}
