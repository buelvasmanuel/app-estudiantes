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

  group('peticiones e interceptores', () {
    test('cada método envía su verbo; el cuerpo va como JSON', () async {
      final vistas = <String>[];
      final api = _api((p) async {
        vistas.add(
          '${p.method} ${p.url.path} ${p.headers['content-type']} '
          '${p.body}',
        );
        return _json(null, 204);
      });
      await api.put('/e/1', {'a': 1});
      await api.patch('/e/1', {'b': 'ñ'});
      await api.delete('/e/1');
      expect(vistas, [
        'PUT /e/1 application/json {"a":1}',
        'PATCH /e/1 application/json {"b":"ñ"}',
        'DELETE /e/1 null ',
      ]);
    });

    test('un interceptor añade cabeceras a cada petición', () async {
      final cabeceras = <String?>[];
      final api = _api((p) async {
        cabeceras.add(p.headers['Authorization']);
        return _json([]);
      });
      api.interceptores.add(_Interceptor(token: () => 'abc'));
      await api.get('/x');
      await api.enviar(PeticionApi('GET', '/x', conInterceptores: false));
      expect(cabeceras, ['Bearer abc', null]);
    });

    test(
      'si el interceptor lo pide, repite UNA vez con cabeceras nuevas',
      () async {
        var token = 'viejo';
        final recibidos = <String?>[];
        final api = _api((p) async {
          recibidos.add(p.headers['Authorization']);
          return p.headers['Authorization'] == 'Bearer nuevo'
              ? _json({'ok': true})
              : _json({'detail': 'Token caducado'}, 401);
        });
        final interceptor = _Interceptor(
          token: () => token,
          alFallar: (e) async {
            if (e.statusCode != 401) return false;
            token = 'nuevo'; // "renueva" la sesión
            return true;
          },
        );
        api.interceptores.add(interceptor);

        expect(await api.post('/x', {'a': 1}), {'ok': true});
        expect(recibidos, ['Bearer viejo', 'Bearer nuevo']);
      },
    );

    test('no repite en bucle aunque el interceptor siempre lo pida', () async {
      var llamadas = 0;
      final api = _api((_) async {
        llamadas++;
        return _json({'detail': 'No autorizado'}, 401);
      });
      api.interceptores.add(_Interceptor(alFallar: (_) async => true));
      await expectLater(
        api.get('/x'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      expect(llamadas, 2);
    });

    test('un error en antesDeEnviar se propaga sin llegar a la red', () async {
      var llamadas = 0;
      final api = _api((_) async {
        llamadas++;
        return _json([]);
      });
      api.interceptores.add(
        _Interceptor(token: () => throw const ApiException('Sesión caducada')),
      );
      await expectLater(api.get('/x'), throwsA(isA<ApiException>()));
      expect(llamadas, 0);
    });
  });
}

class _Interceptor extends InterceptorApi {
  _Interceptor({this.token, this.alFallar});

  final String Function()? token;
  final Future<bool> Function(ApiException error)? alFallar;

  @override
  Future<void> antesDeEnviar(PeticionApi peticion) async {
    final t = token?.call();
    if (t != null) peticion.cabeceras['Authorization'] = 'Bearer $t';
  }

  @override
  Future<bool> reintentar(PeticionApi peticion, ApiException error) async =>
      await alFallar?.call(error) ?? false;
}
