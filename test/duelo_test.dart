import 'package:app_estudiantes/duelo/cartas.dart';
import 'package:app_estudiantes/duelo/modelo.dart';
import 'package:app_estudiantes/juego/celebracion.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/duelo_screen.dart';
import 'package:app_estudiantes/tema/temas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_de_prueba.dart';
import 'support/duelo_falso.dart';

Future<void> _abrir(
  WidgetTester tester,
  DueloFalso servidor, {
  String ruta = Rutas.duelo,
  TemaJuego tema = TemaJuego.expediente,
}) async {
  tester.view.physicalSize = const Size(412, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    appDePrueba(servidor.api(), inicial: ruta, tema: tema),
  );
  await tester.pumpAndSettle();
}

/// Las peticiones al duelo (sin las del resto del juego).
List<String> _peticiones(DueloFalso s) =>
    s.registro.map((r) => r.split(' ').take(2).join(' ')).toList();

Future<void> _elegir(WidgetTester tester, String atributo) async {
  await tester.tap(find.byKey(Key('atributo-$atributo')));
  await tester.pumpAndSettle();
}

Future<void> _verJugadaRival(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('ver-jugada-rival')));
  await tester.pumpAndSettle();
}

Future<void> _continuar(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('continuar-duelo')));
  await tester.pumpAndSettle();
}

String _texto(WidgetTester tester, String clave) =>
    tester.widget<Text>(find.byKey(Key(clave))).data!;

String _marcador(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('marcador')))
    .textSpan!
    .toPlainText();

Map<String, Object?> _dueloJson({
  String modo = 'maquina',
  String estado = 'en_juego',
  String? alias = 'Búho Máquina',
  String? turno = 'yo',
  String? expira,
  bool? enLinea,
}) => {
  'id': 'abc',
  'modo': modo,
  'estado': estado,
  'rival': {'tipo': modo, 'alias': alias},
  'rondas_total': 5,
  'ronda': 2,
  'turno': turno,
  'marcador': {'yo': 1, 'rival': 0},
  'mi_carta': mazoYo.first,
  'rondas': [
    {
      'numero': 1,
      'elegido_por': 'yo',
      'atributo': 'asistencia',
      'mi_carta': mazoYo.first,
      'carta_rival': mazoMaquina.first,
      'ganador': 'yo',
      'explicacion': 'Ganaste con asistencia.',
    },
  ],
  'resultado': null,
  'xp_ganada': 0,
  'duelos_con_xp_hoy': {'jugados': 1, 'maximo': 3},
  'atributos': <Object?>[],
  'expira_turno_en': expira,
  'rival_en_linea': enLinea,
  'creado_en': '2026-10-11T18:00:00Z',
  'actualizado_en': '2026-10-11T18:01:00Z',
};

void main() {
  group('modelo', () {
    test('lee DueloOut, también los campos de la v2', () {
      final d = Duelo.fromJson(
        _dueloJson(
          modo: 'jugador',
          alias: 'Laura_P',
          turno: 'rival',
          expira: '2026-10-11T18:02:00Z',
          enLinea: false,
        ),
      );
      expect(d.modo, ModoDuelo.jugador);
      expect(d.contraMaquina, isFalse);
      expect(d.aliasRival, 'Laura_P');
      expect(d.turno, Lado.rival);
      expect(d.ronda, 2);
      expect(d.miCarta!.atributos['promedio']!.valor, 3.8);
      expect(d.rondas.single.ganador, GanadorRonda.yo);
      expect(d.rondas.single.porTiempo, isFalse);
      expect(d.expiraTurnoEn, isNotNull);
      expect(d.rivalEnLinea, isFalse);
      expect(d.recompensa, isNull);
      // Sin `atributos`, el orden del contrato.
      expect(d.codigosAtributos, Atributos.orden);
    });

    test('v2: ronda perdida por tiempo y rival aún por llegar', () {
      final json = _dueloJson(modo: 'jugador', alias: null, estado: 'esperando')
        ..['rondas'] = [
          {
            ...(_dueloJson()['rondas']! as List).first as Map<String, Object?>,
            'atributo': null,
            'motivo': 'tiempo',
            'ganador': 'rival',
          },
        ];
      final d = Duelo.fromJson(json);
      expect(d.estado, EstadoDuelo.esperando);
      expect(d.aliasRival, isNull);
      expect(d.rondas.single.atributo, isNull);
      expect(d.rondas.single.porTiempo, isTrue);
    });

    test('valores de las cartas con el formato de Colombia', () {
      expect(Atributos.valor('promedio', 3.8), '3,80');
      expect(Atributos.valor('asistencia', 92), '92 %');
      expect(Atributos.valor('horas_estudio', 14), '14 h');
      expect(Atributos.valor('horas_estudio', 7.5), '7,5 h');
      expect(Atributos.valor('semestre', 3), '3.º');
    });
  });

  testWidgets('"¿Un duelo?" va primero en Casos y empieza un duelo', (
    tester,
  ) async {
    final s = DueloFalso();
    await _abrir(tester, s, ruta: Rutas.casos);

    final tarjeta = find.byKey(const Key('tarjeta-duelo'));
    expect(tarjeta, findsOneWidget);
    expect(find.text('¿Un duelo?'), findsOneWidget);
    // Está encima del resto de la pestaña.
    expect(
      tester.getTopLeft(tarjeta).dy,
      lessThan(tester.getTopLeft(find.textContaining('resueltos')).dy),
    );

    await tester.tap(tarjeta);
    await tester.pumpAndSettle();

    expect(_peticiones(s), ['GET /duelos?estado=en_juego', 'POST /duelos']);
    expect(s.registro.last, contains('{"modo":"maquina"}'));
    expect(_marcador(tester), 'Tú 0 — 0 Búho Máquina');
    expect(_texto(tester, 'fase-duelo'), 'Ronda 1 de 5 · tu turno');
    expect(_texto(tester, 'xp-hoy'), 'XP hoy: 0 de 3 duelos');
    expect(find.byKey(const Key('carta-rival-boca-abajo')), findsOneWidget);
    expect(find.text('Búho Máquina · carta boca abajo'), findsOneWidget);
    // La carta propia, con coma decimal y percentiles.
    expect(find.text('3,80'), findsOneWidget);
    expect(find.text('92 %'), findsOneWidget);
    expect(find.text('percentil 81'), findsOneWidget);
    expect(find.byKey(const Key('cuenta-atras')), findsNothing);
  });

  testWidgets('desde el Perfil también se llega al duelo', (tester) async {
    final s = DueloFalso();
    await _abrir(tester, s, ruta: Rutas.perfil);
    await tester.tap(find.byKey(const Key('tarjeta-duelo')));
    await tester.pumpAndSettle();
    expect(find.byType(DueloScreen), findsOneWidget);
  });

  testWidgets('al abrir, retoma el duelo a medias en vez de crear otro', (
    tester,
  ) async {
    final s = DueloFalso(enJuegoAlAbrir: true);
    await _abrir(tester, s);
    expect(_peticiones(s), [
      'GET /duelos?estado=en_juego',
      'GET /duelos/duelo1${'0' * 26}',
    ]);
    expect(find.byKey(const Key('mi-carta')), findsOneWidget);
  });

  testWidgets('un duelo entero: gira la carta, el búho explica, se celebra', (
    tester,
  ) async {
    final s = DueloFalso();
    await _abrir(tester, s);

    // Ronda 1, mi turno: asistencia (92 % contra 70 %).
    await _elegir(tester, 'asistencia');
    expect(s.registro.last, contains('{"ronda":1,"atributo":"asistencia"}'));
    expect(_texto(tester, 'fase-duelo'), 'Ronda 1 de 5 · resuelta');
    expect(_marcador(tester), 'Tú 1 — 0 Búho Máquina');
    expect(find.byKey(const Key('carta-rival')), findsOneWidget);
    expect(find.text('Esperanza Torres'), findsOneWidget);
    expect(find.text('70 %'), findsOneWidget);
    // El texto del búho es el de la API, tal cual.
    expect(
      find.text(
        'Ganaste con asistencia: tu carta tiene 92 y la del rival, 70. '
        '(ronda 1)',
      ),
      findsOneWidget,
    );
    // Expediente: sellos en las dos cartas.
    expect(find.widgetWithText(Sello, 'GANA'), findsOneWidget);
    expect(find.widgetWithText(Sello, 'PIERDE'), findsOneWidget);
    // Ya no se puede elegir.
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    // Ronda 2: turno de la máquina.
    await _continuar(tester);
    expect(_texto(tester, 'fase-duelo'), 'Ronda 2 de 5 · turno del rival');
    expect(find.byKey(const Key('carta-rival-boca-abajo')), findsOneWidget);
    expect(find.byKey(const Key('atributo-promedio')), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing); // no elijo yo
    await _verJugadaRival(tester);
    expect(s.registro.last, contains('{"ronda":2,"atributo":null}'));
    expect(_marcador(tester), 'Tú 1 — 1 Búho Máquina');

    await _continuar(tester);
    await _elegir(tester, 'promedio'); // 3,00 contra 2,50
    await _continuar(tester);
    await _verJugadaRival(tester);
    await _continuar(tester);
    await _elegir(tester, 'promedio');
    expect(_marcador(tester), 'Tú 3 — 2 Búho Máquina');
    expect(find.text('Ver resultado'), findsOneWidget);

    // Al ver el resultado se celebra la insignia "Duelista".
    await _continuar(tester);
    expect(find.byType(CelebracionVista), findsOneWidget);
    expect(find.text('Duelista'), findsOneWidget);
    await tester.tap(find.text('¡Seguir!'));
    await tester.pumpAndSettle();

    expect(_texto(tester, 'resultado-duelo'), '¡Victoria!');
    expect(_texto(tester, 'xp-duelo'), '+30 XP');
    expect(s.jugadasAplicadas, 5);
    // El progreso se vuelve a pedir (XP nueva en el chip).
    expect(
      s.juego.registro.where((r) => r == 'GET /juego/progreso').length,
      greaterThan(1),
    );

    // Otro duelo: uno nuevo, sin preguntar por el anterior.
    await tester.tap(find.byKey(const Key('otro-duelo')));
    await tester.pumpAndSettle();
    expect(_peticiones(s).last, 'POST /duelos');
    expect(_texto(tester, 'fase-duelo'), 'Ronda 1 de 5 · tu turno');
  });

  testWidgets('el giro de la carta rival dura ≤ 400 ms', (tester) async {
    expect(
      CartaRival.duracionGiro,
      lessThanOrEqualTo(const Duration(milliseconds: 400)),
    );
    final s = DueloFalso();
    await _abrir(tester, s);
    await tester.tap(find.byKey(const Key('atributo-asistencia')));
    // Llega la respuesta; la carta empieza boca abajo y gira.
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('carta-rival-boca-abajo')), findsOneWidget);
    // A mitad del giro, aún de espaldas (de canto).
    await tester.pump(CartaRival.duracionGiro ~/ 3);
    expect(find.byKey(const Key('carta-rival-boca-abajo')), findsOneWidget);
    await tester.pump(CartaRival.duracionGiro);
    expect(find.byKey(const Key('carta-rival')), findsOneWidget);
  });

  testWidgets('con "reducir movimiento", la carta sale ya girada', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final s = DueloFalso();
    await _abrir(tester, s);
    await tester.tap(find.byKey(const Key('atributo-asistencia')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('carta-rival')), findsOneWidget);
    expect(find.byKey(const Key('carta-rival-boca-abajo')), findsNothing);
  });

  testWidgets('tema Noche: sin sellos, el resultado se dice con palabras', (
    tester,
  ) async {
    final s = DueloFalso();
    await _abrir(tester, s, tema: TemaJuego.noche);
    await _elegir(tester, 'asistencia');
    expect(find.byType(Sello), findsNothing);
    expect(find.text('TU CARTA · GANA'), findsOneWidget);
    expect(find.text('BÚHO MÁQUINA · PIERDE'), findsOneWidget);
  });

  group('jugadas que no llegan', () {
    testWidgets('fallo de red: se reintenta la misma jugada', (tester) async {
      final s = DueloFalso()..fallosRed = 1;
      await _abrir(tester, s);
      await tester.tap(find.byKey(const Key('atributo-asistencia')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      final jugadas = s.registro.where((r) => r.contains('/jugadas')).toList();
      expect(jugadas, hasLength(2));
      expect(jugadas.toSet(), hasLength(1)); // la misma
      expect(s.jugadasAplicadas, 1);
      expect(_texto(tester, 'fase-duelo'), 'Ronda 1 de 5 · resuelta');
    });

    testWidgets('si sigue fallando, se pide el duelo y se puede reintentar', (
      tester,
    ) async {
      final s = DueloFalso()..fallos503 = 3;
      await _abrir(tester, s);
      await tester.tap(find.byKey(const Key('atributo-asistencia')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(_peticiones(s).sublist(2), [
        'POST /duelos/duelo1${'0' * 26}/jugadas',
        'POST /duelos/duelo1${'0' * 26}/jugadas',
        'POST /duelos/duelo1${'0' * 26}/jugadas',
        'GET /duelos/duelo1${'0' * 26}',
      ]);
      expect(
        _texto(tester, 'aviso-jugada'),
        'No se pudo enviar la jugada. Inténtalo otra vez.',
      );
      expect(_texto(tester, 'fase-duelo'), 'Ronda 1 de 5 · tu turno');

      await tester.tap(find.byKey(const Key('reintentar-jugada')));
      await tester.pumpAndSettle();
      expect(s.registro.last, contains('{"ronda":1,"atributo":"asistencia"}'));
      expect(_texto(tester, 'fase-duelo'), 'Ronda 1 de 5 · resuelta');
      expect(find.byKey(const Key('aviso-jugada')), findsNothing);
    });

    testWidgets('409 ronda_incorrecta: se pide el duelo y se sigue', (
      tester,
    ) async {
      final s = DueloFalso()..proximo409 = 'ronda_incorrecta';
      await _abrir(tester, s);
      await _elegir(tester, 'asistencia');
      expect(_peticiones(s).last, 'GET /duelos/duelo1${'0' * 26}');
      // El cliente no inventa nada: sigue en lo que dice el servidor.
      expect(_texto(tester, 'fase-duelo'), 'Ronda 1 de 5 · tu turno');
      expect(find.byKey(const Key('atributo-asistencia')), findsOneWidget);
    });
  });

  testWidgets('abandonar pide confirmación y cuenta como derrota sin XP', (
    tester,
  ) async {
    final s = DueloFalso();
    await _abrir(tester, s);
    await tester.tap(find.byKey(const Key('abandonar-duelo')));
    await tester.pumpAndSettle();
    expect(find.text('¿Abandonar el duelo?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmar-abandono')));
    await tester.pumpAndSettle();
    expect(_peticiones(s).last, 'POST /duelos/duelo1${'0' * 26}/abandonar');
    expect(_texto(tester, 'resultado-duelo'), 'Duelo abandonado');
    expect(_texto(tester, 'xp-duelo'), 'Abandonar no da XP.');
    expect(find.byKey(const Key('abandonar-duelo')), findsNothing);
  });

  testWidgets('con los 3 duelos con XP de hoy hechos, lo dice', (tester) async {
    final s = DueloFalso(duelosConXpHoy: 3, yaEsDuelista: true);
    await _abrir(tester, s);
    for (final paso in [
      () => _elegir(tester, 'asistencia'),
      () => _verJugadaRival(tester),
      () => _elegir(tester, 'promedio'),
      () => _verJugadaRival(tester),
      () => _elegir(tester, 'promedio'),
    ]) {
      await paso();
      await _continuar(tester);
    }
    // Sin insignia nueva no hay celebración.
    expect(find.byType(CelebracionVista), findsNothing);
    expect(
      _texto(tester, 'xp-duelo'),
      'Hoy ya jugaste 3 duelos con XP: este no suma, pero sí cuenta como '
      'práctica.',
    );
  });

  group('sitio para la v2', () {
    Widget enApp(Widget hijo) => MaterialApp(
      theme: TemaJuego.noche.datos,
      home: Scaffold(body: hijo),
    );

    testWidgets('"Esperando a…" no parece un botón ni se puede pulsar', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await tester.pumpWidget(enApp(const EsperandoRival(alias: 'Laura_P')));
      final espera = find.byKey(const Key('esperando-rival'));
      expect(find.text('Esperando a Laura_P…'), findsOneWidget);
      // Indicador de progreso, y nada pulsable.
      expect(
        find.descendant(
          of: espera,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Esperando a Laura_P')),
        isSemantics(label: 'Esperando a Laura_P', isLiveRegion: true),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Esperando a Laura_P'))
            .flagsCollection
            .isButton,
        isFalse,
      );
      semantica.dispose();
    });

    testWidgets('el marcador enseña el alias, la cuenta atrás y la conexión', (
      tester,
    ) async {
      final ahora = DateTime.now();
      final d = Duelo.fromJson(
        _dueloJson(
          modo: 'jugador',
          alias: 'Laura_P',
          turno: 'rival',
          expira: ahora
              .add(const Duration(seconds: 38, milliseconds: 500))
              .toUtc()
              .toIso8601String(),
          enLinea: false,
        ),
      );
      await tester.pumpWidget(enApp(MarcadorDuelo(duelo: d)));
      expect(_marcador(tester), 'Tú 1 — 0 Laura_P');
      expect(find.text('0:38'), findsOneWidget);
      expect(find.text('Laura_P se desconectó'), findsOneWidget);
      expect(CuentaAtras.texto(const Duration(seconds: 75)), '1:15');
      expect(CuentaAtras.texto(const Duration(seconds: -3)), '0:00');
    });
  });
}
