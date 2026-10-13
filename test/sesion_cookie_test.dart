import 'package:app_estudiantes/passkeys/passkeys_api.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/acceso_screen.dart';
import 'package:app_estudiantes/services/almacen_refresh.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:app_estudiantes/services/sesion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_de_prueba.dart';
import 'support/passkeys_falso.dart';
import 'support/servidor_cookie.dart';

/// Una sesión como la de la app ([web]: modo cookie), registrada como
/// interceptor de [api].
GestorSesion _sesion(
  ApiService api,
  AlmacenRefresh almacen, {
  bool web = true,
}) {
  final s = GestorSesion(api: api, almacen: almacen, modoCookie: web);
  api.interceptores.add(s);
  return s;
}

void main() {
  group('web (refresh en cookie)', () {
    test('al abrir sin cookie: refresh con {} y cabecera; 401 → login sin '
        'aviso', () async {
      final servidor = ServidorCookie();
      final sesion = _sesion(servidor.api(), AlmacenEnMemoria());
      await sesion.restaurar();
      expect(servidor.registro, [
        'cred POST /auth/refresh X-Refresh-En-Cookie {}',
      ]);
      expect(sesion.estado, EstadoSesion.sinSesion);
      expect(sesion.aviso, isNull);
      expect(sesion.errorAlRestaurar, isNull);
    });

    test('login: la API pone la cookie; nada en el almacén; al recargar la '
        'sesión sigue', () async {
      final servidor = ServidorCookie();
      final almacen = AlmacenEnMemoria();
      final sesion = _sesion(servidor.api(), almacen);
      await sesion.iniciarSesion('Detective_Ana', 'una frase larga');
      expect(
        servidor.registro.single,
        startsWith('cred POST /auth/login X-Refresh-En-Cookie '),
      );
      expect(sesion.estado, EstadoSesion.conSesion);
      expect(servidor.cookie, isNotNull);
      expect(await almacen.leer(), isNull); // no se guarda en ningún sitio

      // "Recargar la página": otra app, sin nada en memoria; la cookie sigue.
      final recargada = _sesion(servidor.api(), AlmacenEnMemoria());
      await recargada.restaurar();
      expect(recargada.estado, EstadoSesion.conSesion);
      expect(recargada.usuario?.alias, 'Detective_Ana');
      expect(
        servidor.registro.last,
        'cred POST /auth/refresh X-Refresh-En-Cookie {}',
      );
    });

    test('renovar el access también va con {} y la cookie', () async {
      final servidor = ServidorCookie();
      final sesion = _sesion(servidor.api(), AlmacenEnMemoria());
      await sesion.iniciarSesion('Detective_Ana', 'una frase larga');
      final antes = await sesion.accessVigente();
      final despues = await sesion.accessVigente(forzar: true);
      expect(despues, isNot(antes));
      expect(
        servidor.registro.last,
        'cred POST /auth/refresh X-Refresh-En-Cookie {}',
      );
    });

    test('cerrar sesión: logout con {} borra la cookie; al recargar no hay '
        'sesión (y sin aviso)', () async {
      final servidor = ServidorCookie();
      final sesion = _sesion(servidor.api(), AlmacenEnMemoria());
      await sesion.iniciarSesion('Detective_Ana', 'una frase larga');
      await sesion.cerrarSesion();
      expect(
        servidor.registro.last,
        'cred POST /auth/logout X-Refresh-En-Cookie {}',
      );
      expect(servidor.cookie, isNull);
      expect(sesion.estado, EstadoSesion.sinSesion);

      final recargada = _sesion(servidor.api(), AlmacenEnMemoria());
      await recargada.restaurar();
      expect(recargada.estado, EstadoSesion.sinSesion);
      expect(recargada.aviso, isNull);
    });

    test('login con passkey: la verificación va en modo cookie y la sesión '
        'sobrevive a recargar', () async {
      final servidor = ServidorCookie();
      final api = servidor.api();
      final sesion = _sesion(api, AlmacenEnMemoria());
      final passkeys = PasskeysApi(api, NavegadorFalso());
      await sesion.entrarConPasskey(
        () => passkeys.entrar(preparar: sesion.prepararParaSesion),
      );
      expect(sesion.estado, EstadoSesion.conSesion);
      expect(
        servidor.registro.last,
        startsWith(
          'cred POST /passkeys/login/verificacion X-Refresh-En-Cookie ',
        ),
      );
      // Las opciones no lo necesitan (público, sin cookie).
      expect(servidor.registro.first, 'normal POST /passkeys/login/opciones');
      final recargada = _sesion(servidor.api(), AlmacenEnMemoria());
      await recargada.restaurar();
      expect(recargada.estado, EstadoSesion.conSesion);
    });
  });

  group('APK y escritorio: nada cambia', () {
    test(
      'login sin cabecera ni credenciales; el refresh, en el almacén',
      () async {
        final servidor = ServidorCookie();
        final almacen = AlmacenEnMemoria();
        // Como en el APK: sin cliente con credenciales y sin modo cookie.
        final sesion = _sesion(
          servidor.api(conCredenciales: false),
          almacen,
          web: false,
        );
        await sesion.iniciarSesion('Detective_Ana', 'una frase larga');
        expect(
          servidor.registro.single,
          startsWith('normal POST /auth/login {'),
        );
        expect(
          servidor.registro.single,
          isNot(contains('X-Refresh-En-Cookie')),
        );
        expect(servidor.cookie, isNull);
        expect(await almacen.leer(), 'refresh-1');

        await sesion.accessVigente(forzar: true);
        expect(
          servidor.registro.last,
          'normal POST /auth/refresh {"refresh_token":"refresh-1"}',
        );
        await sesion.cerrarSesion();
        expect(
          servidor.registro.last,
          'normal POST /auth/logout {"refresh_token":"refresh-2"}',
        );
      },
    );

    test('al abrir sin refresh guardado no pregunta a la API', () async {
      final servidor = ServidorCookie();
      final sesion = _sesion(
        servidor.api(conCredenciales: false),
        AlmacenEnMemoria(),
        web: false,
      );
      await sesion.restaurar();
      expect(servidor.registro, isEmpty);
      expect(sesion.estado, EstadoSesion.sinSesion);
    });

    test('incluso si hubiera cliente con credenciales, sin modo cookie no se '
        'usa', () async {
      final servidor = ServidorCookie();
      final sesion = _sesion(servidor.api(), AlmacenEnMemoria(), web: false);
      await sesion.iniciarSesion('Detective_Ana', 'una frase larga');
      expect(servidor.registro.single, startsWith('normal POST /auth/login'));
    });
  });

  testWidgets('la web abre sin sesión: el login aparece sin ningún aviso', (
    tester,
  ) async {
    final servidor = ServidorCookie();
    await tester.pumpWidget(
      appDePrueba(
        servidor.api(),
        inicial: Rutas.perfil,
        conSesion: false,
        modoCookie: true,
        esWeb: true,
        navegador: NavegadorFalso(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccesoScreen), findsOneWidget);
    expect(servidor.registro, [
      'cred POST /auth/refresh X-Refresh-En-Cookie {}',
    ]);
    // Ni el aviso de sesión caducada ni ningún error.
    expect(find.text(GestorSesion.avisoCaducada), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets('la web con cookie abre ya dentro', (tester) async {
    final servidor = ServidorCookie();
    final previa = _sesion(servidor.api(), AlmacenEnMemoria());
    await previa.iniciarSesion('Detective_Ana', 'una frase larga');
    servidor.registro.clear();
    await tester.pumpWidget(
      appDePrueba(
        servidor.api(),
        inicial: Rutas.perfil,
        conSesion: false,
        modoCookie: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      servidor.registro.first,
      'cred POST /auth/refresh X-Refresh-En-Cookie {}',
    );
    expect(find.byType(AccesoScreen), findsNothing);
  });
}
