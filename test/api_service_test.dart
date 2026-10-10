import 'dart:convert';

import 'package:app_estudiantes/models/json_utils.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiService _api(MockClientHandler handler) =>
    ApiService(client: MockClient(handler), baseUrl: 'http://api.test');

http.Response _json(Object? cuerpo, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(cuerpo)),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('ApiService', () {
    test('decodifica UTF-8 aunque no venga charset', () async {
      final api = _api((_) async => _json(['Ingeniería', 'Bogotá']));
      expect(await api.get('/x'), ['Ingeniería', 'Bogotá']);
    });

    test('sin conexión lanza ApiException sin statusCode', () async {
      final api = _api((_) async => throw http.ClientException('refused'));
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.sinConexion, 'sinConexion', isTrue)
              .having((e) => e.mensaje, 'mensaje', contains('http://api.test')),
        ),
      );
    });

    test('503 con detail en texto', () async {
      final api = _api(
        (_) async => _json({'detail': 'Modelo no entrenado'}, 503),
      );
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 503)
              .having(
                (e) => e.mensaje,
                'mensaje',
                contains('Modelo no entrenado'),
              ),
        ),
      );
    });

    test('422 con detail {mensaje} y con lista de Pydantic', () async {
      final propio = _api(
        (_) async => _json({
          'detail': {'mensaje': 'Carrera desconocida', 'carreras_validas': []},
        }, 422),
      );
      await expectLater(
        propio.post('/x', {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.mensaje,
            'm',
            contains('Carrera desconocida'),
          ),
        ),
      );

      final pydantic = _api(
        (_) async => _json({
          'detail': [
            {'msg': 'Input should be less than or equal to 40'},
          ],
        }, 422),
      );
      await expectLater(
        pydantic.post('/x', {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.mensaje,
            'm',
            contains('less than or equal'),
          ),
        ),
      );
    });

    test('parsear convierte FormatException en ApiException', () {
      final api = _api((_) async => _json(null));
      expect(
        () => api.parsear(
          <String, Object?>{},
          (j) => leerString(comoMapa(j), 'x'),
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('json_utils', () {
    test('leerNum acepta int, double y String', () {
      final json = <String, Object?>{'a': 3, 'b': 3.5, 'c': '3.95', 'd': 'x'};
      expect(leerNum(json, 'a'), 3);
      expect(leerNum(json, 'b'), 3.5);
      expect(leerNum(json, 'c'), 3.95);
      expect(() => leerNum(json, 'd'), throwsFormatException);
      expect(() => leerNum(json, 'falta'), throwsFormatException);
    });

    test('leerInt rechaza decimales', () {
      expect(leerInt({'a': 4.0}, 'a'), 4);
      expect(() => leerInt({'a': 4.5}, 'a'), throwsFormatException);
    });
  });
}
