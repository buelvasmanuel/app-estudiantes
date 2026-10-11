// El Laboratorio de punta a punta contra una API REAL con /laboratorio.
//
//   flutter test integration_test/laboratorio_real_test.dart -d linux \
//     --dart-define=API_URL=http://127.0.0.1:8001 \
//     --dart-define=ALIAS=Prueba_Frontend_1 --dart-define=PASSWORD='…' \
//     --dart-define=CAPTURAS_DIR=$PWD/docs/capturas
//
// Si la cuenta no existe, la crea.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_estudiantes/laboratorio/providers.dart';
import 'package:app_estudiantes/laboratorio/rescate.dart';
import 'package:app_estudiantes/main.dart';
import 'package:app_estudiantes/providers.dart';
import 'package:app_estudiantes/screens/acceso_screen.dart';
import 'package:app_estudiantes/screens/rescate_screen.dart';
import 'package:app_estudiantes/services/almacen_refresh.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:app_estudiantes/services/sesion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_real_test.dart' show esperarA;

const _alias = String.fromEnvironment('ALIAS');
const _password = String.fromEnvironment('PASSWORD');
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

  testWidgets('rescate óptimo con la API real', (tester) async {
    if (_alias.isEmpty || _password.isEmpty) {
      fail('Faltan --dart-define=ALIAS y --dart-define=PASSWORD');
    }
    // La cuenta: se crea si no existe.
    await tester.runAsync(() async {
      final api = ApiService();
      final sesion = GestorSesion(api: api, almacen: AlmacenEnMemoria());
      try {
        await sesion.registrarse(_alias, _password);
      } on ApiException catch (e) {
        if (e.codigo != 'alias_en_uso') rethrow;
      }
      api.cerrar();
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: ProviderScope(
          retry: sinReintentos,
          overrides: [
            almacenRefreshProvider.overrideWithValue(AlmacenEnMemoria()),
          ],
          child: const EstudiantesApp(),
        ),
      ),
    );
    await esperarA(tester, find.byType(AccesoScreen));
    await tester.enterText(find.byKey(const Key('alias')), _alias);
    await tester.enterText(find.byKey(const Key('password')), _password);
    await tester.tap(find.text('Entrar'));
    await esperarA(tester, find.text('Laboratorio'));

    await tester.tap(find.text('Laboratorio'));
    await esperarA(tester, find.text('Caso al azar'));
    await tester.pump(const Duration(milliseconds: 500));
    final contenedor = ProviderScope.containerOf(
      tester.element(find.text('Caso al azar')),
    );
    final lista = await tester.runAsync(
      () => contenedor.read(casosProvider.future),
    );
    // ignore: avoid_print
    print('Casos: ${lista!.casos.length}');
    expect(lista.casos, isNotEmpty);
    await capturar(tester, '10_laboratorio');

    // El caso más grave.
    final primero = lista.casos.first;
    await tester.tap(find.text(primero.nombreCompleto).first);
    await esperarA(tester, find.text('Confirmar rescate'));
    final id = primero.estudianteId;
    final (caso, mapa) = (await tester.runAsync(
      () async => (
        await contenedor.read(casoProvider(id).future),
        await contenedor.read(probabilidadesProvider(id).future),
      ),
    ))!;
    await tester.pumpAndSettle();

    // Óptimo del §4.1: menos fichas; a igualdad, menor probabilidad.
    List<int>? optima;
    var costeOptimo = 1 << 30;
    var pOptima = 1.0;
    for (final c in Rescate.combinaciones(caso)) {
      final p = mapa[Rescate.claveDe(c)]!;
      if (p >= caso.objetivo) continue;
      final coste = [
        for (final (i, n) in c.indexed) n * caso.intervenciones[i].fichas,
      ].fold(0, (a, b) => a + b);
      if (coste < costeOptimo || (coste == costeOptimo && p < pOptima)) {
        (optima, costeOptimo, pOptima) = (c, coste, p);
      }
    }
    expect(
      optima,
      isNotNull,
      reason: 'El contrato dice que todo caso es resoluble',
    );
    // ignore: avoid_print
    print(
      'Caso ${caso.estudiante.nombreCompleto}: '
      '${(caso.probabilidad * 100).round()} % → óptimo $optima '
      '($costeOptimo fichas, ${(pOptima * 100).round()} %)',
    );

    for (final (i, n) in optima!.indexed) {
      for (var k = 0; k < n; k++) {
        await tester.tap(
          find.textContaining('${caso.intervenciones[i].nombre} ·'),
        );
        await tester.pumpAndSettle();
      }
    }
    await capturar(tester, '11_rescate');

    await tester.tap(find.text('Confirmar rescate'));
    await esperarA(tester, find.byType(Estrellas));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('¡Rescatado!'), findsOneWidget);
    expect(find.textContaining('Lo mínimo era $costeOptimo'), findsOneWidget);
    final semantica = tester.ensureSemantics();
    expect(find.bySemanticsLabel('3 de 3 estrellas'), findsOneWidget);
    semantica.dispose();
    // ignore: avoid_print
    print('Resultado: 3 estrellas, óptimo del servidor = del cliente');
    await capturar(tester, '12_resultado');
  });
}
