import 'package:app_estudiantes/duelo/cartas.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/duelo_screen.dart';
import 'package:app_estudiantes/screens/elegir_rival_screen.dart';
import 'package:app_estudiantes/tema/temas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_de_prueba.dart';
import 'support/duelo_jugador_falso.dart';
import 'support/fuentes_reales.dart';
import 'support/ws_falso.dart';

/// La pantalla tiene relojes y un indicador que no paran: en vez de
/// pumpAndSettle, se adelanta el tiempo a mano.
Future<void> _pasar(WidgetTester tester, [Duration t = Duration.zero]) async {
  await tester.pump(t);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _segundos(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await _pasar(tester);
}

Future<void> _abrir(
  WidgetTester tester,
  DueloJugadorFalso servidor, {
  ServidorWsFalso? ws,
  String ruta = Rutas.dueloJugador,
  Size tamano = const Size(412, 2000),
  TemaJuego tema = TemaJuego.expediente,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    appDePrueba(
      servidor.api(),
      inicial: ruta,
      tema: tema,
      conectorWs: ws?.conectar,
    ),
  );
  await _pasar(tester);
  await _pasar(tester);
}

/// El WebSocket conecta y la API responde "listo" con el estado actual.
Future<void> _conectarWs(
  WidgetTester tester,
  ServidorWsFalso ws,
  DueloJugadorFalso s,
) async {
  expect(ws.ultima.enviados.first['tipo'], 'auth');
  ws.ultima.recibir({'tipo': 'listo', 'duelo': s.estado});
  await _pasar(tester);
}

/// La API avisa por el WebSocket con el estado actual del servidor.
Future<void> _aviso(
  WidgetTester tester,
  ServidorWsFalso ws,
  DueloJugadorFalso s,
  String tipo,
) async {
  ws.ultima.recibir({'tipo': tipo, 'duelo': s.estado});
  await _pasar(tester);
}

String _texto(WidgetTester tester, String clave) =>
    tester.widget<Text>(find.byKey(Key(clave))).data!;

String _buho(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('consejo-duelo')),
        matching: find.byKey(const Key('frase-buho')),
      ),
    )
    .data!;

String _chip(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('cuenta-atras')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  group('elegir rival', () {
    testWidgets('cada modo con su propio XP de hoy (v2.2)', (tester) async {
      final s = DueloJugadorFalso();
      await _abrir(tester, s, ruta: Rutas.duelo);
      expect(find.byType(ElegirRivalScreen), findsOneWidget);
      expect(
        find.text(
          'XP hoy: 1 de 3 duelos · victoria 30 · empate 15 · derrota 5',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'XP hoy: 2 de 3 duelos · victoria 40 · empate 20 · derrota 10',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin xp_hoy (API anterior), solo la XP de cada resultado', (
      tester,
    ) async {
      final s = DueloJugadorFalso()..xpHoy = null;
      await _abrir(tester, s, ruta: Rutas.duelo);
      expect(
        find.text('XP: victoria 40 · empate 20 · derrota 10'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('elegir-jugador')));
      await _pasar(tester);
      expect(s.registro, contains('POST /duelos'));
      expect(find.text('Buscando a otro detective…'), findsOneWidget);
    });
  });

  group('buscando rival', () {
    testWidgets('anillo con el minuto que avanza y "Cancelar búsqueda"', (
      tester,
    ) async {
      final s = DueloJugadorFalso();
      await _abrir(tester, s);
      expect(find.text('Buscando a otro detective…'), findsOneWidget);
      expect(_texto(tester, 'cuenta-busqueda'), '1:00');
      await _segundos(tester, 3);
      expect(_texto(tester, 'cuenta-busqueda'), '0:57');

      await tester.tap(find.byKey(const Key('cancelar-busqueda')));
      await _pasar(tester);
      expect(s.registro.last, 'POST /duelos/j1/abandonar');
      expect(find.byType(ElegirRivalScreen), findsOneWidget);
      expect(find.byType(DueloScreen), findsNothing);
    });

    testWidgets('pasa el minuto sin rival: "Nadie apareció" y la máquina', (
      tester,
    ) async {
      final s = DueloJugadorFalso();
      await _abrir(tester, s);
      s.alConsultar = () => dueloJugadorJson(estado: 'abandonado');
      await _segundos(tester, 61);
      expect(s.consultas('j1'), greaterThanOrEqualTo(1));
      expect(find.text('Nadie apareció esta vez'), findsOneWidget);
      expect(find.byKey(const Key('jugar-contra-maquina')), findsOneWidget);
      expect(find.byKey(const Key('buscar-otra-vez')), findsOneWidget);
    });

    testWidgets('salir mientras se busca cancela la búsqueda', (tester) async {
      final s = DueloJugadorFalso();
      await _abrir(tester, s);
      await tester.tap(find.byType(BackButton));
      await _pasar(tester);
      expect(find.byType(DueloScreen), findsNothing);
      expect(s.registro, contains('POST /duelos/j1/abandonar'));
    });

    testWidgets('409 duelo_en_curso: retoma el que ya estaba en juego', (
      tester,
    ) async {
      final s = DueloJugadorFalso(inicial: dueloJugadorJson())..enCurso = true;
      await _abrir(tester, s);
      expect(
        s.registro,
        containsAllInOrder(['POST /duelos', 'GET /duelos/j1']),
      );
      expect(find.byKey(const Key('mi-carta')), findsOneWidget);
    });
  });

  testWidgets(
    'emparejado por WebSocket: alias, "Empiezas tú" y la cuenta atrás de 45 s '
    'avanza; con el WebSocket conectado no se sondea',
    (tester) async {
      final s = DueloJugadorFalso();
      final ws = ServidorWsFalso();
      await _abrir(tester, s, ws: ws);
      expect(ws.ultima.url.toString(), 'ws://api.test/duelos/j1/ws');
      await _conectarWs(tester, ws, s);

      s.estado = dueloJugadorJson();
      await _aviso(tester, ws, s, 'emparejado');
      expect(find.text('¡Rival encontrado: Laura_P!'), findsOneWidget);
      expect(
        find.text('Empiezas tú. 5 rondas, 45 s por turno.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('marcador')))
            .textSpan!
            .toPlainText(),
        'Tú 0 — 0 Laura_P',
      );
      expect(_chip(tester), '0:45');
      await _segundos(tester, 1);
      expect(_chip(tester), '0:44');
      await _segundos(tester, 9);
      expect(_chip(tester), '0:35');
      expect(s.consultas('j1'), 0);
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
    },
  );

  testWidgets(
    'con ≤ 10 s el reloj se pone urgente y el búho no dice segundos; el '
    'lector de pantalla solo anuncia 30 y 10 s',
    (tester) async {
      final s = DueloJugadorFalso(inicial: dueloJugadorJson());
      final ws = ServidorWsFalso();
      final semantica = tester.ensureSemantics();
      await _abrir(tester, s, ws: ws);
      await _conectarWs(tester, ws, s);
      tester.takeAnnouncements();
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);

      await _segundos(tester, 36); // quedan 9 s
      expect(_chip(tester), '0:09');
      expect(find.byIcon(Icons.timer), findsOneWidget); // urgente
      final buho = _buho(tester);
      expect(
        buho,
        '¡Se acaba tu tiempo! Si no eliges, la ronda es para Laura_P.',
      );
      expect(buho, isNot(contains(RegExp(r'\d'))));
      expect(tester.takeAnnouncements().map((a) => a.message), [
        'Quedan 30 segundos de tu turno',
        'Quedan 10 segundos de tu turno',
      ]);
      semantica.dispose();
    },
  );

  testWidgets(
    'al llegar a 0 pide el duelo; la ronda por tiempo enseña la explicación '
    'de la API',
    (tester) async {
      final s = DueloJugadorFalso(inicial: dueloJugadorJson());
      final ws = ServidorWsFalso();
      await _abrir(tester, s, ws: ws);
      await _conectarWs(tester, ws, s);
      s.alConsultar = () => dueloJugadorJson(
        ronda: 2,
        turno: 'rival',
        rival: 1,
        rondas: [
          rondaJson(1, elegidoPor: 'yo', ganador: 'rival', porTiempo: true),
        ],
      );
      await _segundos(tester, 44);
      expect(s.consultas('j1'), 0);
      await _segundos(tester, 2);
      expect(s.consultas('j1'), 1);
      expect(find.text('Se acabó tu tiempo'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('explicacion-duelo')),
                matching: find.byKey(const Key('frase-buho')),
              ),
            )
            .data,
        'Se te acabó el tiempo del turno: la ronda es para el rival.',
      );
      // No se jugó ningún atributo: ninguno resaltado en mi carta.
      final filas = tester.widgetList<FilaAtributo>(
        find.descendant(
          of: find.byKey(const Key('mi-carta')),
          matching: find.byType(FilaAtributo),
        ),
      );
      expect(filas.every((f) => f.desenlace == null), isTrue);
      expect(_texto(tester, 'fase-duelo'), 'Ronda 1 de 5 · resuelta');
    },
  );

  testWidgets(
    'turno del rival: espera no pulsable, aviso de desconexión y su jugada '
    'llega por WebSocket (gira la carta)',
    (tester) async {
      final s = DueloJugadorFalso(
        inicial: dueloJugadorJson(
          ronda: 2,
          turno: 'rival',
          yo: 1,
          rondas: [rondaJson(1)],
        ),
      );
      final ws = ServidorWsFalso();
      await _abrir(tester, s, ws: ws);
      await _conectarWs(tester, ws, s);
      expect(find.text('Esperando a Laura_P…'), findsOneWidget);
      expect(find.byKey(const Key('ver-jugada-rival')), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      s.estado = dueloJugadorJson(
        ronda: 2,
        turno: 'rival',
        yo: 1,
        rondas: [rondaJson(1)],
        enLinea: false,
      );
      await _aviso(tester, ws, s, 'rival_desconectado');
      expect(find.text('Laura_P se desconectó'), findsOneWidget);
      expect(
        _buho(tester),
        'Laura_P se desconectó. Si no vuelve antes de que acabe su turno, la '
        'ronda es tuya.',
      );

      s.estado = dueloJugadorJson(
        ronda: 3,
        yo: 1,
        rival: 1,
        rondas: [
          rondaJson(1),
          rondaJson(
            2,
            elegidoPor: 'rival',
            atributo: 'horas_estudio',
            ganador: 'rival',
            explicacion: 'El rival ganó con horas de estudio.',
          ),
        ],
      );
      await _aviso(tester, ws, s, 'ronda_resuelta');
      await _pasar(tester, CartaRival.duracionGiro);
      expect(_texto(tester, 'fase-duelo'), 'Ronda 2 de 5 · resuelta');
      expect(find.byKey(const Key('carta-rival')), findsOneWidget);
      expect(find.text('El rival ganó con horas de estudio.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('continuar-duelo')));
      await _pasar(tester);
      expect(_texto(tester, 'fase-duelo'), 'Ronda 3 de 5 · tu turno');
    },
  );

  testWidgets('mi jugada va por REST; el aviso repetido no la duplica', (
    tester,
  ) async {
    final s = DueloJugadorFalso(inicial: dueloJugadorJson());
    final ws = ServidorWsFalso();
    final sonidos = ReproductorMudo();
    await tester.pumpWidget(const SizedBox());
    tester.view.physicalSize = const Size(412, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      appDePrueba(
        s.api(),
        inicial: Rutas.dueloJugador,
        conectorWs: ws.conectar,
        reproductor: sonidos,
      ),
    );
    await _pasar(tester);
    await _pasar(tester);
    await _conectarWs(tester, ws, s);
    await tester.tap(find.byKey(const Key('atributo-asistencia')));
    await _pasar(tester, CartaRival.duracionGiro);
    expect(s.registro.last, 'POST /duelos/j1/jugadas');
    expect(_texto(tester, 'fase-duelo'), 'Ronda 1 de 5 · resuelta');
    // El WebSocket avisa de la misma ronda: no pasa nada nuevo.
    await _aviso(tester, ws, s, 'ronda_resuelta');
    expect(_texto(tester, 'fase-duelo'), 'Ronda 1 de 5 · resuelta');
    await tester.tap(find.byKey(const Key('continuar-duelo')));
    await _pasar(tester);
    expect(find.text('Esperando a Laura_P…'), findsOneWidget);
  });

  group('sin WebSocket', () {
    testWidgets('si no conecta, la partida sigue por REST cada 3 s', (
      tester,
    ) async {
      final s = DueloJugadorFalso(
        inicial: dueloJugadorJson(
          ronda: 2,
          turno: 'rival',
          yo: 1,
          rondas: [rondaJson(1)],
        ),
      );
      await _abrir(tester, s); // sin WebSocket
      expect(s.consultas('j1'), 0);
      await _segundos(tester, 3);
      expect(s.consultas('j1'), 1);
      await _segundos(tester, 3);
      expect(s.consultas('j1'), 2);

      // El rival juega: llega en la siguiente consulta.
      s.estado = dueloJugadorJson(
        ronda: 3,
        yo: 1,
        rival: 1,
        rondas: [
          rondaJson(1),
          rondaJson(2, elegidoPor: 'rival', ganador: 'rival'),
        ],
      );
      await _segundos(tester, 3);
      expect(_texto(tester, 'fase-duelo'), 'Ronda 2 de 5 · resuelta');
    });

    testWidgets('"error" 4404 del WebSocket: deja de usarlo y sondea', (
      tester,
    ) async {
      final s = DueloJugadorFalso(inicial: dueloJugadorJson());
      final ws = ServidorWsFalso();
      await _abrir(tester, s, ws: ws);
      await _conectarWs(tester, ws, s);
      ws.ultima.recibir({'tipo': 'error', 'codigo': 4404, 'motivo': 'x'});
      await _pasar(tester);
      expect(ws.ultima.cerrada, isTrue);
      await _segundos(tester, 3);
      expect(s.consultas('j1'), 1);
      await _segundos(tester, 30);
      expect(ws.conexiones, hasLength(1));
    });

    testWidgets(
      'se cae el WebSocket: sondea mientras tanto, reconecta y se resincroniza '
      'con GET; luego deja de sondear',
      (tester) async {
        final s = DueloJugadorFalso(inicial: dueloJugadorJson());
        final ws = ServidorWsFalso();
        await _abrir(tester, s, ws: ws);
        await _conectarWs(tester, ws, s);
        ws.ultima.caer(1006);
        await _pasar(tester);
        await _segundos(tester, 1); // reconecta al segundo
        expect(ws.conexiones, hasLength(2));
        final antes = s.consultas('j1');
        await _conectarWs(tester, ws, s); // "listo" de nuevo
        expect(s.consultas('j1'), antes + 1); // resincroniza
        await _segundos(tester, 9);
        expect(s.consultas('j1'), antes + 1); // ya no sondea
      },
    );
  });

  group('fin por abandono del rival', () {
    Future<void> terminar(
      WidgetTester tester, {
      required int rondas,
      required int xp,
      int jugadosHoy = 1,
    }) async {
      final hechas = [for (var i = 1; i <= rondas; i++) rondaJson(i)];
      final s = DueloJugadorFalso(
        inicial: dueloJugadorJson(
          ronda: rondas + 1,
          turno: rondas.isEven ? 'yo' : 'rival',
          yo: rondas,
          rondas: hechas,
        ),
      );
      final ws = ServidorWsFalso();
      await _abrir(tester, s, ws: ws);
      await _conectarWs(tester, ws, s);
      s.estado = dueloJugadorJson(
        estado: 'abandonado',
        resultado: 'victoria',
        yo: rondas,
        rondas: hechas,
        xp: xp,
        jugadosHoy: jugadosHoy,
      );
      await _aviso(tester, ws, s, 'terminado');
    }

    testWidgets('con 3 rondas resueltas: victoria con XP', (tester) async {
      await terminar(tester, rondas: 3, xp: 40);
      expect(_texto(tester, 'resultado-duelo'), '¡Victoria!');
      expect(_texto(tester, 'motivo-fin'), 'Laura_P abandonó en la ronda 4.');
      expect(_texto(tester, 'xp-duelo'), '+40 XP');
      expect(
        find.text(
          'Ganas por abandono. Como ya se habían resuelto al menos 3 rondas, '
          'la victoria cuenta con XP.',
        ),
        findsOneWidget,
      );
      expect(find.text('Buscar otro rival'), findsOneWidget);
      expect(find.byKey(const Key('abandonar-duelo')), findsNothing);
    });

    testWidgets('con menos de 3 rondas: victoria sin XP, y lo explica', (
      tester,
    ) async {
      // Aunque además ya lleve 3 duelos con XP hoy: la razón es una sola.
      await terminar(tester, rondas: 1, xp: 0, jugadosHoy: 3);
      expect(_texto(tester, 'resultado-duelo'), '¡Victoria!');
      expect(_texto(tester, 'xp-duelo'), 'Esta victoria no da XP.');
      expect(
        find.text(
          'Ganas por abandono, pero se resolvieron menos de 3 rondas: así, '
          'esta victoria no da XP.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con 3 rondas pero sin huecos hoy: lo dice el límite', (
      tester,
    ) async {
      await terminar(tester, rondas: 3, xp: 0, jugadosHoy: 3);
      expect(
        _texto(tester, 'xp-duelo'),
        'Hoy ya jugaste 3 duelos con XP: este no suma, pero sí cuenta como '
        'práctica.',
      );
      expect(
        find.text(
          'Ganas por abandono. Hoy ya jugaste 3 duelos con XP en este modo.',
        ),
        findsOneWidget,
      );
    });
  });

  for (final tema in TemaJuego.values) {
    testWidgets(
      '360×640 (${tema.name}): en tu turno se ven los 4 atributos sin '
      'desplazar, también con el aviso de rival encontrado',
      (tester) async {
        await tester.runAsync(cargarFuentesReales);
        final s = DueloJugadorFalso(inicial: dueloJugadorJson());
        await _abrir(tester, s, tamano: const Size(360, 640), tema: tema);
        expect(find.byKey(const Key('aviso-emparejado')), findsOneWidget);
        final visible = tester.getRect(
          find
              .descendant(
                of: find.byType(DueloScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        // El título de la barra cabe entero (con la bandera, el chip de
        // nivel y el avatar al lado).
        final titulo = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Duelo'),
          ),
        );
        expect(titulo.didExceedMaxLines, isFalse, reason: 'título cortado');
        for (final a in [
          'promedio',
          'asistencia',
          'horas_estudio',
          'semestre',
        ]) {
          final fila = tester.getRect(find.byKey(Key('atributo-$a')));
          expect(
            fila.bottom,
            lessThanOrEqualTo(visible.bottom),
            reason: '$a queda debajo del borde',
          );
        }
      },
    );
  }
}
