import 'package:app_estudiantes/juego/celebracion.dart';
import 'package:app_estudiantes/juego/lote.dart';
import 'package:app_estudiantes/juego/modelo.dart';
import 'package:app_estudiantes/laboratorio/modelo.dart';
import 'package:app_estudiantes/models/sesion.dart';
import 'package:app_estudiantes/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_de_prueba.dart';
import 'support/juego_falso.dart';
import 'support/laboratorio_falso.dart';

Future<void> _abrir(
  WidgetTester tester,
  JuegoFalso juego,
  String ruta, {
  Rol rol = Rol.jugador,
}) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(appDePrueba(juego.api(), inicial: ruta, rol: rol));
  await tester.pumpAndSettle();
}

void main() {
  group('modelo', () {
    test('progreso: avance dentro del nivel y último nivel', () {
      final p = Progreso.fromJson({
        'alias': 'A',
        'xp': 230,
        'nivel': {'numero': 2, 'nombre': 'Investigador', 'xp_desde': 150},
        'siguiente_nivel': {
          'numero': 3,
          'nombre': 'Inspector',
          'xp_desde': 400,
        },
        'racha_dias': 0,
        'casos_resueltos': 0,
        'casos_total': 9,
        'rescates_logrados': 0,
        'estrellas_totales': 0,
        'insignias': <Object?>[],
      });
      expect(p.avanceNivel, closeTo(80 / 250, 1e-9));
    });

    test('un resultado de rescate v1 (sin progreso) sigue funcionando', () {
      final r = ResultadoRescate.fromJson({
        'logrado': true,
        'estrellas': 3,
        'fichas_usadas': 4,
        'fichas_optimas': 4,
        'probabilidad_inicial': 0.8,
        'probabilidad_final': 0.4,
        'solucion_optima': {
          'estudio': 0,
          'tutoria': 2,
          'fichas': 4,
          'probabilidad': 0.4,
        },
        'explicacion_final': explicacionJson(probabilidad: 0.4),
        'aviso': avisoModelo,
      });
      expect(r.recompensa, isNull);
      expect(r.recordEstrellas, isNull);
    });
  });

  group('ListaAliases', () {
    test(
      'separa por líneas, comas y espacios; detecta inválidos y repetidos',
      () {
        final l = ListaAliases.desde('Ana_01, luis\nPedro  José,ana_01\nyo');
        expect(l.validos, ['Ana_01', 'luis', 'Pedro']);
        expect(l.invalidos, ['José', 'yo']);
        expect(l.repetidos, ['ana_01']);
        expect(l.enviable, isFalse);
      },
    );

    test('más de 40 no se puede enviar', () {
      final l = ListaAliases.desde(
        [for (var i = 0; i < 41; i++) 'alumno_$i'].join('\n'),
      );
      expect(l.validos, hasLength(41));
      expect(l.demasiados, isTrue);
      expect(l.enviable, isFalse);
    });
  });

  testWidgets('el chip de nivel está en la barra y lleva al perfil', (
    tester,
  ) async {
    final juego = JuegoFalso();
    await _abrir(tester, juego, Rutas.casos);
    expect(find.text('Nv 1 · 130 XP'), findsOneWidget);
    await tester.tap(find.byKey(const Key('chip-nivel')));
    await tester.pumpAndSettle();
    expect(find.text('Detective_Ana'), findsWidgets);
    expect(
      find.textContaining('te faltan 20 para Investigador'),
      findsOneWidget,
    );
  });

  testWidgets('casos agrupados por nivel con su estado', (tester) async {
    await _abrir(tester, JuegoFalso(), Rutas.casos);
    expect(find.text('1 de 3 resueltos'), findsOneWidget);
    expect(find.text('Novato · 20 XP'), findsOneWidget);
    expect(find.text('Investigador · 40 XP'), findsOneWidget);
    expect(find.text('Resuelto · +20 XP'), findsOneWidget);
  });

  testWidgets('responder: pista al fallar; al acertar, XP, insignia y '
      'celebración', (tester) async {
    final juego = JuegoFalso();
    await _abrir(tester, juego, Rutas.casoJuego('carrera_mas_riesgo'));
    expect(find.textContaining('Ficha del caso'), findsOneWidget);

    await tester.tap(find.text('Derecho').last);
    await tester.pump();
    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();
    expect(find.text('No es Derecho'), findsOneWidget);
    expect(find.textContaining('26,53 %'), findsOneWidget); // el dato real
    expect(
      find.text('Pista: Cuenta el porcentaje, no el número.'),
      findsOneWidget,
    );
    expect(find.byType(CelebracionVista), findsNothing);

    await tester.tap(find.text('Medicina').last);
    await tester.pump();
    await tester.tap(find.text('Probar con esta'));
    await tester.pumpAndSettle();
    // Insignia nueva (primera vez): celebración, que se cierra con un botón.
    expect(find.byType(CelebracionVista), findsOneWidget);
    // 130 + 20 = 150 XP: además sube a Investigador.
    expect(find.text('¡Ahora eres Investigador!'), findsOneWidget);
    expect(find.text('Primera pista'), findsOneWidget);
    await tester.tap(find.text('¡Seguir!'));
    await tester.pumpAndSettle();

    // Segundo intento: 20 XP (la mitad), que decide el servidor.
    expect(find.text('¡Correcto! +20 XP'), findsOneWidget);
    expect(find.text('Medicina tiene el porcentaje más alto.'), findsOneWidget);
    expect(
      find.text('Nv 1 · 150 XP'),
      findsNothing,
    ); // 130 + 20 = 150 → nivel 2
    expect(find.text('Nv 2 · 150 XP'), findsOneWidget);
    // Al abrir y tras cada respuesta (también un fallo cuenta para la racha).
    expect(
      juego.registro.where((r) => r.endsWith('/juego/progreso')),
      hasLength(3),
    );
  });

  testWidgets('celebración con "reducir movimiento": quieta desde el '
      'principio', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CelebracionVista(
            recompensa: Recompensa(
              xpGanada: 40,
              insigniasNuevas: [],
              progreso: ProgresoResumen(
                xp: 160,
                nivel: 'Investigador',
                subioDeNivel: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // un solo fotograma
    expect(find.text('¡Ahora eres Investigador!'), findsOneWidget);
    final escala = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byIcon(Icons.workspace_premium_rounded),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(escala.transform.getMaxScaleOnAxis(), closeTo(1, 1e-6));
  });

  testWidgets('perfil: insignias obtenidas y pendientes; ranking con "tú"', (
    tester,
  ) async {
    final juego = JuegoFalso();
    await _abrir(tester, juego, Rutas.perfil);
    expect(find.text('Insignias · 2 de 3'), findsOneWidget);
    expect(find.text('Rescatista'), findsOneWidget);

    await tester.tap(find.text('Ranking'));
    await tester.pumpAndSettle();
    expect(find.text('Detective_Ana (tú)'), findsOneWidget);
    expect(find.text('310 XP'), findsOneWidget);
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.text('900 XP'), findsOneWidget);
    expect(juego.registro, contains('GET /juego/ranking?periodo=siempre'));
  });

  testWidgets('el panel del docente no es para jugadores', (tester) async {
    await _abrir(tester, JuegoFalso(), Rutas.docente);
    expect(find.text('Este panel es solo para docentes.'), findsOneWidget);
  });

  testWidgets('docente: crea cuentas y avisa de los alias que ya existen', (
    tester,
  ) async {
    final juego = JuegoFalso();
    await _abrir(tester, juego, Rutas.docente, rol: Rol.docente);

    await tester.enterText(find.byKey(const Key('aliases')), 'Ana_01\nLuis_02');
    await tester.pump();
    expect(find.text('Crear 2 cuentas'), findsOneWidget);
    await tester.tap(find.text('Crear 2 cuentas'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ya existen: Ana_01'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('aliases')),
      'Luis_02, Eva_03, mal alias!',
    );
    await tester.pump();
    expect(find.textContaining('No valen'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('aliases')), 'Luis_02, Eva_03');
    await tester.pump();
    await tester.tap(find.text('Crear 2 cuentas'));
    await tester.pumpAndSettle();
    expect(find.textContaining('solo se muestran ahora'), findsOneWidget);
    expect(find.text('k7mq-x3hp-9tf0'), findsOneWidget);
    expect(find.text('Eva_03'), findsOneWidget);

    await tester.tap(find.text('Jugadores'));
    await tester.pumpAndSettle();
    expect(find.text('Detective_Ana'), findsOneWidget);
    expect(find.textContaining('Aún no ha jugado'), findsOneWidget);
  });

  testWidgets('rescate v1.1: XP e insignia al terminar, con celebración y '
      'estrellas quietas', (tester) async {
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      appDePrueba(
        laboratorioFalso(conProgreso: true),
        inicial: Rutas.rescate(17),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.textContaining('Tutoría ·'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Confirmar rescate'));
    await tester.pumpAndSettle();
    expect(find.byType(CelebracionVista), findsOneWidget);
    expect(find.text('¡Ahora eres Investigador!'), findsOneWidget);
    await tester.tap(find.text('¡Seguir!'));
    await tester.pumpAndSettle();
    expect(find.text('+30 XP · 160 XP en total'), findsOneWidget);
    expect(find.text('Insignia nueva: Rescate perfecto'), findsOneWidget);
  });
}
