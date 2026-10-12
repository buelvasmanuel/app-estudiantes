// Un duelo entre dos jugadores en la API real (CONTRATO_DUELO 2.1/2.2).
//
//   flutter test integration_test/duelo_jugador_real_test.dart -d linux \
//     --dart-define=TEMA=noche \
//     --dart-define=API_URL=https://… \
//     --dart-define=ALIAS=… --dart-define=PASSWORD=…        (A: la app)
//     --dart-define=ALIAS_B=… --dart-define=PASSWORD_B=…    (B: el test)
//     --dart-define=CAPTURAS_DIR=$PWD/docs/capturas \
//     --dart-define=REVISION_DIR=$HOME/Imágenes/v2_real
//
// A juega con la app; B lo maneja el test por REST y con su propio
// WebSocket. Recorre: A busca rival, B se une (A recibe "emparejado" por
// WebSocket y empieza), A juega la ronda 1, B la 2 (llega por WebSocket), A
// deja vencer la 3 (cuenta atrás → GET → ronda por tiempo), B se desconecta
// en la 4 y abandona (A gana por abandono con 3 rondas resueltas: con XP).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_estudiantes/config.dart';
import 'package:app_estudiantes/duelo/canal.dart';
import 'package:app_estudiantes/duelo/cartas.dart';
import 'package:app_estudiantes/models/sesion.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/duelo_screen.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_real.dart';
import 'app_real_test.dart' show esperarA;

const _dirCapturas = String.fromEnvironment('CAPTURAS_DIR');
const _dirRevision = String.fromEnvironment('REVISION_DIR');
const _aliasB = String.fromEnvironment('ALIAS_B');
const _passwordB = String.fromEnvironment('PASSWORD_B');

/// El jugador B, manejado desde el test (REST + su propio WebSocket).
class _JugadorB {
  _JugadorB(this.api, this.access);

  final ApiService api;
  final String access;
  WebSocket? ws;
  final avisos = <String>[];

  static Future<_JugadorB> entrar() async {
    final api = ApiService();
    final enviado = DateTime.now();
    final tokens = Tokens.fromJson(
      await api.enviar(
        PeticionApi(
          'POST',
          '/auth/login',
          cuerpo: {'alias': _aliasB, 'password': _passwordB},
          conInterceptores: false,
          limite: Config.timeoutArranque,
        ),
      ),
      recibido: enviado,
    );
    return _JugadorB(api, tokens.access);
  }

  Future<Map<String, Object?>> _pedir(
    String metodo,
    String ruta, [
    Object? cuerpo,
  ]) async =>
      (await api.enviar(
            PeticionApi(metodo, ruta, cuerpo: cuerpo)
              ..cabeceras['Authorization'] = 'Bearer $access',
          ))!
          as Map<String, Object?>;

  Future<Map<String, Object?>> buscar() =>
      _pedir('POST', '/duelos', {'modo': 'jugador'});
  Future<Map<String, Object?>> duelo(String id) => _pedir('GET', '/duelos/$id');
  Future<Map<String, Object?>> jugar(String id, int ronda, String a) =>
      _pedir('POST', '/duelos/$id/jugadas', {'ronda': ronda, 'atributo': a});
  Future<Map<String, Object?>> abandonar(String id) =>
      _pedir('POST', '/duelos/$id/abandonar');

  /// Abre su WebSocket: auth en el primer mensaje y espera "listo".
  Future<void> conectar(String id) async {
    final url = CanalDuelo.urlWebSocket(Config.apiUrl, id);
    final socket = await WebSocket.connect(url.toString());
    ws = socket;
    final listo = Completer<void>();
    socket.listen((m) {
      final tipo = (jsonDecode(m as String) as Map)['tipo'] as String;
      avisos.add(tipo);
      if (tipo == 'listo' && !listo.isCompleted) listo.complete();
    });
    socket.add(jsonEncode({'tipo': 'auth', 'token': access}));
    await listo.future.timeout(const Duration(seconds: 30));
  }

  Future<void> desconectar() async => ws?.close(1000);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final clave = GlobalKey();
  final tema = temaDePrueba.name;

  Future<void> capturar(
    WidgetTester tester,
    String nombre, {
    bool readme = true,
  }) async {
    await tester.pump(const Duration(milliseconds: 400));
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = (await tester.runAsync(() async {
      final imagen = await boundary.toImage(pixelRatio: 2);
      final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    }))!;
    for (final (dir, si) in [(_dirCapturas, readme), (_dirRevision, true)]) {
      if (dir.isEmpty || !si) continue;
      final archivo = File('$dir/$tema/$nombre.png');
      await archivo.parent.create(recursive: true);
      await archivo.writeAsBytes(bytes);
      // ignore: avoid_print
      print('Captura: ${archivo.path}');
    }
  }

  String texto(String clave) =>
      (find.byKey(Key(clave)).evaluate().single.widget as Text).data!;

  EstadoCanal? canalDeLaApp(WidgetTester tester) =>
      (tester.state(find.byType(DueloScreen)) as dynamic).estadoCanal
          as EstadoCanal?;

  Future<T> red<T>(WidgetTester tester, Future<T> Function() f) async =>
      (await tester.runAsync(f)) as T;

  /// Espera a [f] y dice cuánto tardó (de verdad, no en el reloj del test).
  Future<Duration> cronometrar(WidgetTester tester, Finder f) async {
    final inicio = DateTime.now();
    await esperarA(tester, f, maximo: const Duration(seconds: 20));
    return DateTime.now().difference(inicio);
  }

  testWidgets('un duelo entre dos jugadores en la API real', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    final tokensA = (await tester.runAsync(sesionReal))!;
    final b = await red(tester, _JugadorB.entrar);

    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: appReal(tokens: tokensA, inicial: Rutas.duelo),
      ),
    );
    // Entrada: cada modo con su XP de hoy (v2.2).
    await esperarA(tester, find.textContaining('XP hoy:'));
    await capturar(tester, '22_duelo_elegir_rival');

    // --- A busca rival ---
    await tester.tap(find.byKey(const Key('elegir-jugador')));
    await esperarA(tester, find.text('Buscando a otro detective…'));
    await esperarA(
      tester,
      find.byWidgetPredicate(
        (_) => canalDeLaApp(tester) == EstadoCanal.conectado,
      ),
    );
    await capturar(tester, '23_duelo_buscando');

    // --- B se une: A recibe "emparejado" por el WebSocket ---
    final unido = await red(tester, b.buscar);
    final id = unido['id']! as String;
    expect(unido['estado'], 'en_juego', reason: 'B debía emparejarse con A');
    await red(tester, () => b.conectar(id));
    final tEmparejado = await cronometrar(
      tester,
      find.byKey(const Key('aviso-emparejado')),
    );
    // ignore: avoid_print
    print('Emparejado en la app en ${tEmparejado.inMilliseconds} ms');
    expect(texto('fase-duelo'), 'Ronda 1 de 5 · tu turno');
    expect(canalDeLaApp(tester), EstadoCanal.conectado);
    await capturar(tester, '24_duelo_emparejado');

    // Lo mismo a 360×640 (solo para revisar): los 4 atributos a la vista.
    tester.view.physicalSize = const Size(360, 640);
    await tester.pump(const Duration(milliseconds: 300));
    await capturar(tester, '360x640_tu_turno', readme: false);
    final abajo = tester
        .getRect(
          find
              .descendant(
                of: find.byType(DueloScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .bottom;
    expect(
      tester.getRect(find.byKey(const Key('atributo-semestre'))).bottom,
      lessThanOrEqualTo(abajo),
    );
    tester.view.physicalSize = const Size(412, 915);
    await tester.pump(const Duration(milliseconds: 300));

    // --- Ronda 1: A elige su mejor percentil ---
    final filas =
        tester
            .widgetList<FilaAtributo>(
              find.descendant(
                of: find.byKey(const Key('mi-carta')),
                matching: find.byType(FilaAtributo),
              ),
            )
            .toList()
          ..sort((x, y) => y.valor.percentil.compareTo(x.valor.percentil));
    await tester.tap(find.byKey(Key('atributo-${filas.first.codigo}')));
    await esperarA(tester, find.byKey(const Key('continuar-duelo')));
    await tester.pump(CartaRival.duracionGiro);
    await capturar(tester, '25_duelo_ronda_revelada');
    await tester.tap(find.byKey(const Key('continuar-duelo')));
    await esperarA(tester, find.byKey(const Key('esperando-rival')));
    await capturar(tester, '26_duelo_turno_rival');

    // --- Ronda 2: juega B; a A le llega por el WebSocket ---
    final antes = await red(tester, () => b.duelo(id));
    final cartaB = antes['mi_carta']! as Map<String, Object?>;
    final atributosB =
        (cartaB['atributos']! as Map<String, Object?>).entries.toList()..sort(
          (x, y) => ((y.value! as Map)['percentil'] as int).compareTo(
            (x.value! as Map)['percentil'] as int,
          ),
        );
    await red(tester, () => b.jugar(id, 2, atributosB.first.key));
    final tRonda = await cronometrar(
      tester,
      find.text('Ronda 2 de 5 · resuelta'),
    );
    // ignore: avoid_print
    print('Jugada del rival en la app en ${tRonda.inMilliseconds} ms');
    // Por WebSocket llega enseguida; sondeando serían hasta 3 s.
    expect(tRonda, lessThan(const Duration(milliseconds: 2500)));
    await tester.pump(CartaRival.duracionGiro);
    await tester.tap(find.byKey(const Key('continuar-duelo')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(texto('fase-duelo'), 'Ronda 3 de 5 · tu turno');

    // --- Ronda 3: A deja vencer su turno (45 s) ---
    await esperarA(
      tester,
      find.text(
        '¡Se acaba tu tiempo! Si no eliges, la ronda es para '
        '$_aliasB.',
      ),
      maximo: const Duration(seconds: 50),
    );
    await capturar(tester, '27_duelo_cuenta_atras');
    await esperarA(
      tester,
      find.byKey(const Key('aviso-tiempo')),
      maximo: const Duration(seconds: 30),
    );
    await tester.pump(CartaRival.duracionGiro);
    final explicacion =
        (find
                    .descendant(
                      of: find.byKey(const Key('explicacion-duelo')),
                      matching: find.byKey(const Key('frase-buho')),
                    )
                    .evaluate()
                    .single
                    .widget
                as Text)
            .data!;
    // ignore: avoid_print
    print('Ronda por tiempo: "$explicacion"');
    expect(explicacion, startsWith('Se te acabó el tiempo'));
    await capturar(tester, '28_duelo_ronda_por_tiempo');
    await tester.tap(find.byKey(const Key('continuar-duelo')));
    await tester.pump(const Duration(milliseconds: 300));

    // --- Ronda 4 (turno de B): B se desconecta y luego abandona ---
    await esperarA(tester, find.byKey(const Key('esperando-rival')));
    await red(tester, b.desconectar);
    await esperarA(tester, find.byKey(const Key('rival-desconectado')));
    await capturar(tester, '29_duelo_rival_desconectado');
    final fin = await red(tester, () => b.abandonar(id));
    expect(fin['estado'], 'abandonado');
    await esperarA(tester, find.byKey(const Key('resultado-duelo')));
    await tester.pump(const Duration(milliseconds: 300));
    // ignore: avoid_print
    print(
      'Fin: ${texto('resultado-duelo')} · ${texto('motivo-fin')} · '
      '${texto('xp-duelo')}',
    );
    expect(texto('resultado-duelo'), '¡Victoria!');
    expect(texto('motivo-fin'), '$_aliasB abandonó en la ronda 4.');
    await capturar(tester, '30_duelo_abandono_rival');
    // ignore: avoid_print
    print('Avisos que recibió B: ${b.avisos}');
  });
}
