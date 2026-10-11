// Autenticación de extremo a extremo contra la API REAL (CONTRATO_AUTH.md).
//
// Crea una cuenta de prueba: el alias y la contraseña se pasan al ejecutar
// (no se guardan en el repo).
//
//   flutter test integration_test/auth_real_test.dart -d linux \
//     --dart-define=API_URL=https://api-tienda-wjac.onrender.com \
//     --dart-define=ALIAS=Prueba_Frontend_1 \
//     --dart-define=PASSWORD='una contraseña larga'
import 'package:app_estudiantes/main.dart';
import 'package:app_estudiantes/preferencias.dart';
import 'package:app_estudiantes/providers.dart';
import 'package:app_estudiantes/screens/acceso_screen.dart';
import 'package:app_estudiantes/screens/campus_screen.dart';
import 'package:app_estudiantes/services/almacen_refresh.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:app_estudiantes/services/sesion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_real.dart';
import 'app_real_test.dart' show esperarA;

const _alias = String.fromEnvironment('ALIAS');
const _password = String.fromEnvironment('PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (_alias.isEmpty || _password.isEmpty) {
      fail('Faltan --dart-define=ALIAS y --dart-define=PASSWORD');
    }
  });

  test('registro, refresh, logout, login y cerrar todas', () async {
    final api = ApiService();
    final almacen = AlmacenEnMemoria();
    var adelanto = Duration.zero; // para "envejecer" el access
    final sesion = GestorSesion(
      api: api,
      almacen: almacen,
      ahora: () => DateTime.now().add(adelanto),
    );
    api.interceptores.add(sesion);
    await sesion.restaurar();
    expect(sesion.estado, EstadoSesion.sinSesion);

    // Registro: crea la cuenta e inicia sesión.
    await sesion.registrarse(_alias, _password);
    expect(sesion.estado, EstadoSesion.conSesion);
    expect(sesion.usuario?.alias, _alias);
    final refresh1 = await almacen.leer();
    expect(await api.get('/auth/yo'), containsPair('alias', _alias));
    // ignore: avoid_print
    print(
      'Registro OK: ${sesion.usuario?.alias} (${sesion.usuario?.rol.name})',
    );

    // Con el access a punto de caducar, renueva ANTES de la petición.
    adelanto = const Duration(minutes: 14, seconds: 30);
    expect(await api.get('/auth/yo'), containsPair('alias', _alias));
    final refresh2 = await almacen.leer();
    expect(refresh2, isNot(refresh1));
    // ignore: avoid_print
    print('Refresh OK: el refresh rotó');

    // Sesiones abiertas: la actual está marcada.
    final sesiones = await api.get('/auth/sesiones');
    expect(sesiones, isA<List<Object?>>());
    expect(
      (sesiones! as List<Object?>).whereType<Map<String, Object?>>().where(
        (s) => s['actual'] == true,
      ),
      hasLength(1),
    );

    // Logout: los tokens locales se borran y el refresh deja de valer.
    await sesion.cerrarSesion();
    expect(sesion.estado, EstadoSesion.sinSesion);
    expect(await almacen.leer(), isNull);
    await expectLater(
      api.enviar(
        PeticionApi(
          'POST',
          '/auth/refresh',
          cuerpo: {'refresh_token': refresh2},
          conInterceptores: false,
        ),
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 401)
            .having(
              (e) => e.codigo,
              'codigo',
              anyOf('sesion_revocada', 'refresh_invalido'),
            ),
      ),
    );
    // ignore: avoid_print
    print('Logout OK: el refresh anterior ya no vale');

    // Errores esperados.
    await expectLater(
      sesion.registrarse(_alias.toLowerCase(), _password),
      throwsA(
        isA<ApiException>().having((e) => e.codigo, 'codigo', 'alias_en_uso'),
      ),
    );
    await expectLater(
      sesion.iniciarSesion(_alias, '$_password-mal'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.codigo,
          'codigo',
          'credenciales_invalidas',
        ),
      ),
    );

    // Login y "cerrar todas".
    adelanto = Duration.zero;
    await sesion.iniciarSesion(_alias, _password);
    expect(sesion.estado, EstadoSesion.conSesion);
    await sesion.cerrarTodas();
    expect(sesion.estado, EstadoSesion.sinSesion);
    expect(sesion.aviso, GestorSesion.avisoTodas);
    // ignore: avoid_print
    print('Login y cerrar todas OK');
    api.cerrar();
  });

  testWidgets('la app real: login por pantalla, campus y cerrar sesión', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: sinReintentos,
        overrides: [
          preferenciasProvider.overrideWithValue(preferenciasDePrueba()),
          almacenRefreshProvider.overrideWithValue(AlmacenEnMemoria()),
        ],
        child: const EstudiantesApp(),
      ),
    );
    await esperarA(tester, find.byType(AccesoScreen));

    await tester.enterText(find.byKey(const Key('alias')), _alias);
    await tester.enterText(find.byKey(const Key('password')), _password);
    await tester.tap(find.text('Entrar'));
    await esperarA(
      tester,
      find.byType(CampusVista),
      maximo: const Duration(seconds: 75),
    );
    // ignore: avoid_print
    print('Pantallas OK: login → campus');

    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(_alias), findsOneWidget);
    await tester.tap(find.text('Cerrar sesión'));
    await esperarA(tester, find.byType(AccesoScreen));
    // ignore: avoid_print
    print('Pantallas OK: cerrar sesión → login');
  });
}
