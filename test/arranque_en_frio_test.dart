import 'package:app_estudiantes/services/almacen_refresh.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:app_estudiantes/widgets/estado_vistas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/api_falsa.dart';
import 'support/app_de_prueba.dart';

/// API que tarda [demora] en responder (simula Render despertando).
ApiService _apiLenta(Duration Function() demora) => ApiService(
  baseUrl: 'https://mi-api.onrender.com',
  client: MockClient((_) async {
    await Future<void>.delayed(demora());
    return respuestaJson(estudiantesJson);
  }),
);

void main() {
  // testWidgets usa un reloj falso: los 40 s "pasan" al instante.
  testWidgets('primera petición lenta: aviso a los 3 s y datos a los 40 s', (
    tester,
  ) async {
    final api = _apiLenta(() => const Duration(seconds: 40));
    await tester.pumpWidget(appDePrueba(api));

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Cargando estudiantes…'), findsOneWidget);
    expect(find.text(CargandoVista.mensajeDespertando), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text(CargandoVista.mensajeDespertando), findsOneWidget);
    expect(api.despertando.value, isTrue);
    // Cuenta cuánto se lleva esperando (que no parezca colgado).
    expect(find.text('Llevas 0 s esperando'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Llevas 10 s esperando'), findsOneWidget);

    // 40 s > 8 s del timeout normal: no falla porque en frío espera 60 s.
    await tester.pump(const Duration(seconds: 27));
    await tester.pumpAndSettle();
    expect(find.text('Jorge Rodríguez'), findsOneWidget);
    expect(api.despertando.value, isFalse);
  });

  testWidgets('más de 60 s en frío: error claro con Reintentar', (
    tester,
  ) async {
    final api = _apiLenta(() => const Duration(seconds: 90));
    await tester.pumpWidget(appDePrueba(api));
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    expect(find.textContaining('no respondió en 60 s'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(api.despertando.value, isFalse);
    await tester.pump(const Duration(seconds: 30)); // deja terminar el mock
  });

  testWidgets('ya despierto, el timeout vuelve a ser de 8 s', (tester) async {
    // Responde al instante la 1ª vez y tarda 20 s la 2ª.
    var llamadas = 0;
    final api = ApiService(
      baseUrl: 'https://mi-api.onrender.com',
      client: MockClient((_) async {
        llamadas++;
        if (llamadas > 1) {
          await Future<void>.delayed(const Duration(seconds: 20));
        }
        return http.Response('[]', 200);
      }),
    );
    await api.get('/x');

    Object? error;
    api.get('/x').catchError((Object e) => error = e);
    await tester.pump(const Duration(seconds: 9));
    expect(
      error,
      isA<ApiException>().having(
        (e) => e.mensaje,
        'mensaje',
        allOf(contains('8 s'), contains('inténtalo de nuevo')),
      ),
    );
    await tester.pump(const Duration(seconds: 15)); // deja terminar el mock
  });

  test('API local responde rápido: nunca muestra el aviso', () async {
    final api = apiFalsa({'/x': <Object?>[]});
    await api.get('/x');
    expect(api.despertando.value, isFalse);
  });

  group('API en una dirección local (celular real sin API_URL)', () {
    /// Como un celular real con la URL por defecto del emulador: nadie
    /// responde en 10.0.2.2 y la conexión se queda colgada.
    ApiService colgada(String url) => ApiService(
      baseUrl: url,
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(minutes: 1));
        return http.Response('[]', 200);
      }),
    );

    testWidgets('10.0.2.2 colgada: sin «despertando», error a los 8 s que '
        'explica la dirección y API_URL', (tester) async {
      final api = colgada('http://10.0.2.2:8000');
      await tester.pumpWidget(appDePrueba(api));
      await tester.pump(const Duration(seconds: 4));
      expect(api.despertando.value, isFalse);
      expect(find.text(CargandoVista.mensajeDespertando), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('Reintentar'), findsOneWidget);
      expect(
        find.textContaining('solo funciona en el emulador de Android'),
        findsOneWidget,
      );
      expect(
        find.textContaining('flutter run --dart-define=API_URL='),
        findsOneWidget,
      );
      expect(find.textContaining('despert'), findsNothing);
      await tester.pump(const Duration(minutes: 1)); // deja terminar el mock
    });

    test('127.0.0.1 rechaza la conexión: explica que es este equipo', () async {
      final api = ApiService(
        baseUrl: 'http://127.0.0.1:8000',
        client: MockClient(
          (_) async => throw http.ClientException('rechazada'),
        ),
      );
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.mensaje,
            'mensaje',
            allOf(
              contains('solo funciona en este mismo equipo'),
              contains('uvicorn'),
              contains('flutter run --dart-define=API_URL='),
            ),
          ),
        ),
      );
    });

    testWidgets('con una sesión guardada: el login no dice «despertando»', (
      tester,
    ) async {
      final api = colgada('http://10.0.2.2:8000');
      await tester.pumpWidget(
        appDePrueba(
          api,
          conSesion: false,
          almacen: AlmacenEnMemoria('refresh-guardado'),
        ),
      );
      for (var s = 0; s < 30; s++) {
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const Key('aviso-despertando')), findsNothing);
        expect(find.textContaining('Despertando'), findsNothing);
      }
      expect(find.textContaining('solo funciona en el emulador'), findsWidgets);
      await tester.pump(const Duration(minutes: 2)); // deja terminar el mock
    });

    testWidgets('entrar sin sesión: «Entrando…» y a los 8 s el error junto '
        'al formulario (nada de «despertando»)', (tester) async {
      final api = colgada('http://10.0.2.2:8000');
      await tester.pumpWidget(appDePrueba(api, conSesion: false));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('alias')), 'Detective_Ana');
      await tester.enterText(
        find.byKey(const Key('password')),
        'una frase larga',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Entrando…'), findsOneWidget);
      expect(find.textContaining('Despertando'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.textContaining('no respondió en 8 s'), findsOneWidget);
      expect(
        find.textContaining('solo funciona en el emulador de Android'),
        findsOneWidget,
      );
      await tester.pump(const Duration(minutes: 1)); // deja terminar el mock
    });

    test('la dirección de un PC en la wifi no cambia de consejo', () async {
      final api = ApiService(
        baseUrl: 'http://192.168.1.50:8000',
        client: MockClient(
          (_) async => throw http.ClientException('rechazada'),
        ),
      );
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.mensaje,
            'mensaje',
            allOf(contains('¿Está corriendo?'), isNot(contains('API_URL'))),
          ),
        ),
      );
    });
  });
}
