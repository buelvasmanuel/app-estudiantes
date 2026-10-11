// Reglas del §6 de docs/CONTRATO_AUTH.md (repo api-tienda), una por test.
import 'package:app_estudiantes/services/almacen_refresh.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:app_estudiantes/services/sesion.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/servidor_falso.dart';

void main() {
  late ServidorFalso servidor;
  late ApiService api;
  late AlmacenEnMemoria almacen;
  late DateTime ahora;
  late GestorSesion sesion;

  setUp(() async {
    servidor = ServidorFalso(protegidas: {'/protegido': 'ok'});
    api = servidor.api();
    almacen = AlmacenEnMemoria();
    ahora = DateTime(2026, 10, 11, 12);
    sesion = GestorSesion(api: api, almacen: almacen, ahora: () => ahora);
    api.interceptores.add(sesion);
    await sesion.restaurar(); // almacén vacío → sin sesión
  });

  Future<void> entrar() async {
    await sesion.iniciarSesion('Detective_Ana', 'una frase larga');
    servidor.registro.clear();
  }

  int refrescos() =>
      servidor.registro.where((r) => r == 'POST /auth/refresh').length;

  test('sin refresh guardado arranca sin sesión', () {
    expect(sesion.estado, EstadoSesion.sinSesion);
    expect(servidor.registro, isEmpty);
  });

  test('login: guarda el refresh y envía el access en cada petición', () async {
    await entrar();
    expect(sesion.estado, EstadoSesion.conSesion);
    expect(sesion.usuario?.alias, 'Detective_Ana');
    expect(await almacen.leer(), servidor.refreshVigente);

    expect(await api.get('/protegido'), 'ok');
    expect(servidor.registro, ['GET /protegido']);
  });

  test(
    'credenciales inválidas: error de la API tal cual y sin refrescar',
    () async {
      await expectLater(
        sesion.iniciarSesion('Detective_Ana', 'otra'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.codigo, 'codigo', 'credenciales_invalidas')
              .having(
                (e) => e.mensaje,
                'mensaje',
                'Mensaje de credenciales_invalidas',
              ),
        ),
      );
      expect(refrescos(), 0);
      expect(sesion.estado, EstadoSesion.sinSesion);
    },
  );

  test('429: expone Retry-After', () async {
    servidor.limiteAlcanzado = 30;
    await expectLater(
      sesion.iniciarSesion('Detective_Ana', 'una frase larga'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.reintentarEn,
          'reintentarEn',
          const Duration(seconds: 30),
        ),
      ),
    );
  });

  test(
    'si al access le quedan menos de 60 s, renueva ANTES de enviar',
    () async {
      await entrar();
      ahora = ahora.add(const Duration(minutes: 14, seconds: 1));
      expect(await api.get('/protegido'), 'ok');
      expect(servidor.registro, ['POST /auth/refresh', 'GET /protegido']);
      // La rotación queda guardada.
      expect(await almacen.leer(), servidor.refreshVigente);
    },
  );

  test('401 token_expirado: renueva y repite una vez', () async {
    await entrar();
    servidor.caducarAccess();
    expect(await api.get('/protegido'), 'ok');
    expect(servidor.registro, [
      'GET /protegido',
      'POST /auth/refresh',
      'GET /protegido',
    ]);
  });

  test(
    'varias peticiones a la vez con el access caducado: UN solo refresh',
    () async {
      await entrar();
      servidor
        ..caducarAccess()
        ..demoraRefresh = const Duration(milliseconds: 50);
      final resultados = await Future.wait([
        for (var i = 0; i < 4; i++) api.get('/protegido'),
      ]);
      expect(resultados, everyElement('ok'));
      expect(refrescos(), 1);
      expect(sesion.estado, EstadoSesion.conSesion);
    },
  );

  test('sesión revocada: borra los tokens y avisa', () async {
    await entrar();
    servidor.revocarSesion();
    await expectLater(api.get('/protegido'), throwsA(isA<ApiException>()));
    expect(sesion.estado, EstadoSesion.sinSesion);
    expect(sesion.aviso, GestorSesion.avisoRevocada);
    expect(await almacen.leer(), isNull);
  });

  test('si vuelve a dar 401 después de renovar, cierra la sesión', () async {
    servidor.protegidas['/siempre401'] = ServidorFalso.error(
      401,
      'token_invalido',
    );
    await entrar();
    await expectLater(api.get('/siempre401'), throwsA(isA<ApiException>()));
    expect(servidor.registro, [
      'GET /siempre401',
      'POST /auth/refresh',
      'GET /siempre401',
    ]);
    expect(sesion.estado, EstadoSesion.sinSesion);
    expect(sesion.aviso, GestorSesion.avisoNoValida);
  });

  test('403 permiso_denegado no renueva', () async {
    servidor.protegidas['/admin'] = ServidorFalso.error(
      403,
      'permiso_denegado',
    );
    await entrar();
    await expectLater(
      api.get('/admin'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
    expect(refrescos(), 0);
    expect(sesion.estado, EstadoSesion.conSesion);
  });

  test(
    'refresh sin red: reintenta el mismo refresh hasta 2 veces más',
    () async {
      await entrar();
      servidor
        ..caducarAccess()
        ..fallosDeRedEnRefresh = 2;
      expect(await api.get('/protegido'), 'ok');
      expect(refrescos(), 3);
    },
  );

  test(
    'refresh sin red 3 veces: error de conexión y se conservan los tokens',
    () async {
      await entrar();
      final refresh = await almacen.leer();
      servidor
        ..caducarAccess()
        ..fallosDeRedEnRefresh = 3;
      await expectLater(
        api.get('/protegido'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.sinConexion,
            'sinConexion',
            isTrue,
          ),
        ),
      );
      expect(refrescos(), 3);
      expect(sesion.estado, EstadoSesion.conSesion);
      expect(await almacen.leer(), refresh);
    },
  );

  test('las rutas de /auth no pasan por el interceptor', () async {
    await entrar();
    servidor.caducarAccess();
    ahora = ahora.add(const Duration(hours: 1)); // access "caducado"
    await sesion.cerrarSesion();
    // Ni refresco previo ni Authorization: solo el logout.
    expect(servidor.registro, ['POST /auth/logout']);
  });

  test('cerrar sesión con un refresh en vuelo no la vuelve a abrir', () async {
    await entrar();
    servidor
      ..caducarAccess()
      ..demoraRefresh = const Duration(milliseconds: 50);
    final peticion = api.get('/protegido');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sesion.cerrarSesion();

    await expectLater(peticion, throwsA(isA<ApiException>()));
    expect(sesion.estado, EstadoSesion.sinSesion);
    expect(sesion.aviso, isNull);
    expect(await almacen.leer(), isNull);
  });

  test('cerrar sesión borra los tokens aunque no haya red', () async {
    await entrar();
    servidor.sinRed = true;
    await sesion.cerrarSesion();
    expect(sesion.estado, EstadoSesion.sinSesion);
    expect(await almacen.leer(), isNull);
  });

  test('cerrar todas: sin red conserva la sesión; con red la cierra', () async {
    await entrar();
    servidor.sinRed = true;
    await expectLater(sesion.cerrarTodas(), throwsA(isA<ApiException>()));
    expect(sesion.estado, EstadoSesion.conSesion);

    servidor.sinRed = false;
    await sesion.cerrarTodas();
    expect(sesion.estado, EstadoSesion.sinSesion);
    expect(sesion.aviso, GestorSesion.avisoTodas);
    expect(await almacen.leer(), isNull);
  });

  group('restaurar al arrancar', () {
    test('con un refresh válido guardado, entra sin pedir login', () async {
      await almacen.guardar(servidor.sesionPrevia());
      await sesion.restaurar();
      expect(sesion.estado, EstadoSesion.conSesion);
      expect(await almacen.leer(), servidor.refreshVigente);
    });

    test(
      'sin red: se queda esperando con el error y conserva el refresh',
      () async {
        final refresh = servidor.sesionPrevia();
        await almacen.guardar(refresh);
        servidor.sinRed = true;
        await sesion.restaurar();
        expect(sesion.estado, EstadoSesion.restaurando);
        expect(sesion.errorAlRestaurar?.sinConexion, isTrue);
        expect(await almacen.leer(), refresh);
      },
    );

    test('con un refresh caducado: sin sesión y con aviso', () async {
      await almacen.guardar('refresh-que-no-existe');
      await sesion.restaurar();
      expect(sesion.estado, EstadoSesion.sinSesion);
      expect(sesion.aviso, GestorSesion.avisoCaducada);
      expect(await almacen.leer(), isNull);
    });
  });

  group('refresh sin respuesta con el reloj simulado (§6, regla 5)', () {
    // testWidgets avanza el tiempo con pump: los timeouts de 60 s no se
    // esperan de verdad.
    Future<(ServidorFalso, ApiService, GestorSesion)> preparar(
      WidgetTester tester,
    ) async {
      final servidor = ServidorFalso(protegidas: {'/protegido': 'ok'});
      final api = servidor.api();
      final sesion = GestorSesion(
        api: api,
        almacen: AlmacenEnMemoria(),
        ahora: () => tester.binding.clock.now(),
      );
      api.interceptores.add(sesion);
      await sesion.restaurar();
      await sesion.iniciarSesion('Detective_Ana', 'una frase larga');
      servidor
        ..registro.clear()
        ..caducarAccess();
      return (servidor, api, sesion);
    }

    int refrescosDe(ServidorFalso s) =>
        s.registro.where((r) => r == 'POST /auth/refresh').length;

    testWidgets('tras un timeout reintenta UNA vez', (tester) async {
      final (servidor, api, sesion) = await preparar(tester);
      servidor.fallosRefresh.add(ServidorFalso.colgar);

      Object? resultado;
      api.get('/protegido').then((v) => resultado = v);
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();
      expect(resultado, 'ok');
      expect(refrescosDe(servidor), 2);
    });

    testWidgets('dos timeouts: error y se conservan los tokens', (
      tester,
    ) async {
      final (servidor, api, sesion) = await preparar(tester);
      servidor.fallosRefresh.addAll([
        ServidorFalso.colgar,
        ServidorFalso.colgar,
      ]);

      Object? error;
      api.get('/protegido').catchError((Object e) => error = e);
      await tester.pump(const Duration(seconds: 121));
      await tester.pump();
      expect(
        error,
        isA<ApiException>().having((e) => e.esTimeout, 'esTimeout', isTrue),
      );
      expect(refrescosDe(servidor), 2);
      expect(sesion.estado, EstadoSesion.conSesion);
    });

    testWidgets('ningún reintento sale más de 110 s después del primero', (
      tester,
    ) async {
      final (servidor, api, sesion) = await preparar(tester);
      // Cada intento tarda 56 s en fallar por red: intentos en 0 s y 56 s;
      // el tercero saldría a los 112 s, fuera del tope.
      servidor.fallosRefresh.addAll([
        for (var i = 0; i < 3; i++)
          ServidorFalso.redTras(const Duration(seconds: 56)),
      ]);

      Object? error;
      api.get('/protegido').catchError((Object e) => error = e);
      await tester.pump(const Duration(seconds: 113));
      await tester.pump();
      expect(error, isA<ApiException>());
      expect(refrescosDe(servidor), 2);
      expect(sesion.estado, EstadoSesion.conSesion);
    });
  });
}
