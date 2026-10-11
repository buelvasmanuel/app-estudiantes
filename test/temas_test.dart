import 'dart:math' as math;

import 'package:app_estudiantes/campus/juego.dart';
import 'package:app_estudiantes/main.dart';
import 'package:app_estudiantes/preferencias.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/acceso_screen.dart';
import 'package:app_estudiantes/screens/caso_juego_screen.dart';
import 'package:app_estudiantes/screens/tutorial_screen.dart';
import 'package:app_estudiantes/sonidos.dart';
import 'package:app_estudiantes/tema/temas.dart';
import 'package:app_estudiantes/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_falsa.dart';
import 'support/app_de_prueba.dart';
import 'support/juego_falso.dart';
import 'support/servidor_falso.dart';

/// Contraste WCAG 2.x entre dos colores opacos.
double contraste(Color a, Color b) {
  double lum(Color c) {
    double canal(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
  }

  final (x, y) = (lum(a), lum(b));
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  group('contraste WCAG', () {
    for (final tema in TemaJuego.values) {
      final t = tema.datos;
      final c = t.colorScheme;
      final e = t.extension<ColoresEstado>()!;
      final p = PaletaCampus.de(t);
      // (descripción, color, fondo, mínimo): 4,5 texto; 3 elementos gráficos.
      final pares = <(String, Color, Color, double)>[
        ('texto', c.onSurface, c.surface, 4.5),
        ('texto secundario', c.onSurfaceVariant, c.surface, 4.5),
        ('texto en tarjetas', c.onSurface, c.surfaceContainerHighest, 4.5),
        ('texto sobre primario', c.onPrimary, c.primary, 4.5),
        (
          'texto en contenedor primario',
          c.onPrimaryContainer,
          c.primaryContainer,
          4.5,
        ),
        ('primario (botones, bordes)', c.primary, c.surface, 3),
        ('borde de la opción elegida', c.primary, c.primaryContainer, 3),
        ('texto en "correcto"', e.onOkContenedor, e.okContenedor, 4.5),
        ('texto en "en riesgo"', e.onRiesgoContenedor, e.riesgoContenedor, 4.5),
        ('ventana en riesgo / fachada', e.riesgo, p.fachada, 3),
        ('ventana sin riesgo / fachada', e.ok, p.fachada, 3),
        ('raya de riesgo / ventana', e.onRiesgo, e.riesgo, 3),
        ('borde de la leyenda / fondo', p.bordeMuestra, c.surface, 3),
        ('sello RESUELTO / su tarjeta', e.ok, e.okContenedor, 3),
        ('nombre de edificio / fondo', p.texto, c.surface, 4.5),
      ];
      for (final (nombre, color, fondo, minimo) in pares) {
        test('${tema.nombre}: $nombre ≥ $minimo', () {
          expect(contraste(color, fondo), greaterThanOrEqualTo(minimo));
        });
      }
    }
  });

  group('elegir tema', () {
    testWidgets('la primera vez sigue al sistema: oscuro → Noche', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final c = ProviderContainer(
        overrides: [
          preferenciasProvider.overrideWithValue(PreferenciasEnMemoria()),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(temaProvider), TemaJuego.noche);
    });

    testWidgets('…y claro → Expediente; lo elegido se recuerda', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final prefs = PreferenciasEnMemoria();
      final c = ProviderContainer(
        overrides: [preferenciasProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      expect(c.read(temaProvider), TemaJuego.expediente);
      c.read(temaProvider.notifier).elegir(TemaJuego.noche);
      expect(prefs.texto(Preferencias.claveTema), 'noche');

      // Otra "ejecución" con las mismas preferencias.
      final otra = ProviderContainer(
        overrides: [preferenciasProvider.overrideWithValue(prefs)],
      );
      addTearDown(otra.dispose);
      expect(otra.read(temaProvider), TemaJuego.noche);
    });

    testWidgets('el menú de la cuenta cambia de tema al instante', (
      tester,
    ) async {
      final prefs = PreferenciasEnMemoria({
        Preferencias.claveTutorial: true,
        Preferencias.claveTema: 'expediente',
      });
      await tester.pumpWidget(
        appDePrueba(
          apiFalsa({'/estudiantes/': estudiantesJson}),
          preferencias: prefs,
        ),
      );
      await tester.pumpAndSettle();
      Color fondo() =>
          Theme.of(tester.element(find.byType(Scaffold).first))
              .colorScheme
              .surface;
      expect(fondo(), TemaJuego.expediente.datos.colorScheme.surface);

      await tester.tap(find.byTooltip('Cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Tema Noche'), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-tema')));
      await tester.pumpAndSettle();
      expect(fondo(), TemaJuego.noche.datos.colorScheme.surface);
      expect(prefs.texto(Preferencias.claveTema), 'noche');
    });

    testWidgets('fundido de ≤ 300 ms, y ninguno con "reducir movimiento"', (
      tester,
    ) async {
      final api = apiFalsa({'/estudiantes/': estudiantesJson});
      await tester.pumpWidget(appDePrueba(api));
      await tester.pumpAndSettle();
      var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.themeAnimationDuration,
        lessThanOrEqualTo(const Duration(milliseconds: 300)),
      );
      expect(app.themeAnimationDuration, EstudiantesApp.fundidoTema);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(appDePrueba(api));
      await tester.pump();
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeAnimationDuration, Duration.zero);
    });

    testWidgets('el Perfil tiene el selector de tema y el de sonidos', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = PreferenciasEnMemoria({Preferencias.claveTutorial: true});
      await tester.pumpWidget(
        appDePrueba(
          JuegoFalso().api(),
          inicial: Rutas.perfil,
          preferencias: prefs,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('interruptor-sonidos')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Noche'));
      await tester.pumpAndSettle();
      expect(prefs.texto(Preferencias.claveTema), 'noche');
      // Apagados por defecto.
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('interruptor-sonidos')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('interruptor-sonidos')));
      await tester.pumpAndSettle();
      expect(prefs.booleano(Preferencias.claveSonidos), isTrue);
    });
  });

  group('tutorial', () {
    Future<PreferenciasEnMemoria> entrar(
      WidgetTester tester, {
      Map<String, Object>? prefs,
    }) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final p = PreferenciasEnMemoria(prefs);
      final servidor = ServidorFalso(
        publicas: {'/estudiantes/': estudiantesJson},
      );
      await tester.pumpWidget(
        appDePrueba(servidor.api(), conSesion: false, preferencias: p),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('alias')), 'Detective_Ana');
      await tester.enterText(
        find.byKey(const Key('password')),
        'una frase larga',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      return p;
    }

    testWidgets('la primera vez, tras entrar; "Saltar" lleva a la app', (
      tester,
    ) async {
      final p = await entrar(tester);
      expect(find.byType(TutorialScreen), findsOneWidget);
      expect(find.text('¡Hola, detective!'), findsOneWidget);
      await tester.tap(find.text('Saltar'));
      await tester.pumpAndSettle();
      expect(find.byType(TutorialScreen), findsNothing);
      expect(
        find.text('Jorge Rodríguez'),
        findsOneWidget,
      ); // volvió a /estudiantes
      expect(p.booleano(Preferencias.claveTutorial), isTrue);
      expect(
        p.texto(Preferencias.claveTema),
        isNotNull,
      ); // se recuerda el que veía
    });

    testWidgets('4 pasos; en el último se elige tema y sonidos', (
      tester,
    ) async {
      final p = await entrar(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Una última pista'), findsOneWidget);
      expect(find.textContaining('correlaciones, no causas'), findsOneWidget);
      expect(find.text('¿Activar sonidos?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tutorial-tema-noche')));
      await tester.pumpAndSettle();
      // Vista previa al instante.
      expect(
        Theme.of(tester.element(find.byType(TutorialScreen)))
            .colorScheme
            .surface,
        TemaJuego.noche.datos.colorScheme.surface,
      );
      await tester.tap(find.byKey(const Key('tutorial-sonidos')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('¡A investigar!'));
      await tester.pumpAndSettle();

      expect(find.byType(TutorialScreen), findsNothing);
      expect(p.texto(Preferencias.claveTema), 'noche');
      expect(p.booleano(Preferencias.claveSonidos), isTrue);
      expect(p.booleano(Preferencias.claveTutorial), isTrue);
    });

    testWidgets('visto una vez, no vuelve a salir', (tester) async {
      await entrar(tester, prefs: {Preferencias.claveTutorial: true});
      expect(find.byType(TutorialScreen), findsNothing);
      expect(find.byType(AccesoScreen), findsNothing);
    });
  });

  group('sonidos', () {
    Future<ReproductorMudo> responder(
      WidgetTester tester, {
      required bool activos,
    }) async {
      tester.view.physicalSize = const Size(412, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final mudo = ReproductorMudo();
      await tester.pumpWidget(
        appDePrueba(
          JuegoFalso().api(),
          inicial: Rutas.casoJuego('carrera_mas_riesgo'),
          reproductor: mudo,
          preferencias: PreferenciasEnMemoria({
            Preferencias.claveTutorial: true,
            Preferencias.claveSonidos: activos,
          }),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('opcion-Derecho')));
      await tester.pump();
      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();
      return mudo;
    }

    testWidgets('apagados por defecto: no suena nada', (tester) async {
      final mudo = await responder(tester, activos: false);
      expect(find.text('No es Derecho'), findsOneWidget);
      expect(mudo.sonados, isEmpty);
    });

    testWidgets('activados: un fallo suena a "pista"', (tester) async {
      final mudo = await responder(tester, activos: true);
      expect(mudo.sonados, [Sonido.pista]);
    });
  });

  group('caso resuelto', () {
    Future<void> resolver(
      WidgetTester tester,
      TemaJuego tema,
      double ancho,
    ) async {
      tester.view.physicalSize = Size(ancho, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        appDePrueba(
          JuegoFalso().api(),
          inicial: Rutas.casoJuego('carrera_mas_riesgo'),
          tema: tema,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('opcion-Medicina')));
      await tester.pump();
      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();
      if (find.text('¡Seguir!').evaluate().isNotEmpty) {
        await tester.tap(find.text('¡Seguir!'));
        await tester.pumpAndSettle();
      }
    }

    /// Lo que ocupa en pantalla un widget girado [angulo] radianes.
    Rect girado(Rect r, double angulo) {
      final (s, c) = (math.sin(angulo).abs(), math.cos(angulo).abs());
      return Rect.fromCenter(
        center: r.center,
        width: r.width * c + r.height * s,
        height: r.width * s + r.height * c,
      );
    }

    for (final ancho in [360.0, 412.0]) {
      testWidgets('Expediente a $ancho px: el sello no tapa el título', (
        tester,
      ) async {
        await resolver(tester, TemaJuego.expediente, ancho);
        final titulo = tester.getRect(find.byKey(const Key('veredicto')));
        final sello = girado(
          tester.getRect(find.byKey(const Key('sello'))),
          Sello.angulo,
        );
        expect(
          titulo.overlaps(sello),
          isFalse,
          reason: 'título $titulo, sello $sello',
        );
        // Y el sello no se sale de la pantalla.
        expect(sello.right, lessThanOrEqualTo(ancho));
      });
    }

    testWidgets('Noche no lleva sello', (tester) async {
      await resolver(tester, TemaJuego.noche, 412);
      expect(find.byKey(const Key('sello')), findsNothing);
    });

    for (final tema in TemaJuego.values) {
      testWidgets('${tema.nombre}: la opción elegida se distingue (borde, ✓, '
          'negrita), también ya resuelto', (tester) async {
        await resolver(tester, tema, 412);
        final c = tema.datos.colorScheme;
        Chip chipDe(String valor) => tester.widget<Chip>(
          find.descendant(
            of: find.byKey(Key('opcion-$valor')),
            matching: find.byType(Chip),
          ),
        );
        final elegida = chipDe('Medicina');
        final otra = chipDe('Derecho');
        expect(elegida.side?.color, c.primary);
        expect(elegida.side?.width, OpcionCaso.grosorElegida);
        expect(elegida.avatar, isNotNull);
        expect(elegida.labelStyle?.fontWeight, FontWeight.w700);
        expect(otra.side?.color, c.outline);
        expect(otra.avatar, isNull);
        expect(contraste(c.primary, c.surface), greaterThanOrEqualTo(3));
      });
    }
  });
}
