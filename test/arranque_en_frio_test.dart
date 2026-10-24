import 'package:app_estudiantes/services/api_service.dart';
import 'package:app_estudiantes/widgets/estado_vistas.dart';
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
}
