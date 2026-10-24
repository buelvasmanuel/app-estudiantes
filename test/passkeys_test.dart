import 'package:app_estudiantes/formato.dart';
import 'package:app_estudiantes/passkeys/modelo.dart';
import 'package:app_estudiantes/passkeys/navegador.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/acceso_screen.dart';
import 'package:app_estudiantes/screens/mis_passkeys.dart';
import 'package:app_estudiantes/screens/perfil_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_de_prueba.dart';
import 'support/passkeys_falso.dart';

Future<void> _abrir(
  WidgetTester tester,
  PasskeysFalso s, {
  required String ruta,
  bool conSesion = true,
  bool esWeb = true,
  NavegadorFalso? navegador,
}) async {
  tester.view.physicalSize = const Size(412, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    appDePrueba(
      s.api(),
      inicial: ruta,
      conSesion: conSesion,
      esWeb: esWeb,
      navegador: navegador ?? NavegadorFalso(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Abre «Crear passkey», escribe la contraseña ([password]) y, si se da,
/// el [nombre]; y confirma.
Future<void> _crearPasskey(
  WidgetTester tester, {
  String password = PasskeysFalso.password,
  String? nombre,
}) async {
  await tester.ensureVisible(find.byKey(const Key('crear-passkey')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('crear-passkey')));
  await tester.pumpAndSettle();
  if (nombre != null) {
    await tester.enterText(find.byKey(const Key('nombre-passkey')), nombre);
  }
  await tester.enterText(find.byKey(const Key('password-passkey')), password);
  await tester.pump();
  await tester.tap(find.byKey(const Key('confirmar-nombre-passkey')));
  await tester.pumpAndSettle();
}

/// Lo que se pidió a /passkeys y /auth, sin cuerpo.
List<String> _rutas(PasskeysFalso s) =>
    s.registro.map((r) => r.split(' ').take(2).join(' ')).toList();

void main() {
  group('modelo y formato', () {
    test('PasskeyOut', () {
      final p = Passkey.fromJson(passkeyJson(3, 'Portátil de casa'));
      expect(p.id, 3);
      expect(p.nombre, 'Portátil de casa');
      expect(p.creadaEn, isNotNull);
      expect(p.ultimoUso, isNull);
      expect(p.sincronizada, isTrue);
    });

    test('fecha como en Colombia: día/mes/año', () {
      expect(formatoFecha(DateTime(2026, 10, 3)), '03/10/2026');
    });
  });

  group('login', () {
    testWidgets('"Entrar con passkey": opciones, navegador y verificación; '
        'entra', (tester) async {
      final s = PasskeysFalso();
      final navegador = NavegadorFalso();
      await _abrir(
        tester,
        s,
        ruta: Rutas.perfil,
        conSesion: false,
        navegador: navegador,
      );
      expect(find.byType(AccesoScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('entrar-passkey')));
      await tester.pumpAndSettle();

      expect(_rutas(s).take(2), [
        'POST /passkeys/login/opciones',
        'POST /passkeys/login/verificacion',
      ]);
      // Las opciones de la API pasan tal cual al navegador.
      expect(navegador.opciones.single['rpId'], 'buelvasmanuel.github.io');
      // Y la credencial vuelve a la API con su reto.
      expect(s.registro[1], contains('"reto_id":"reto-1"'));
      expect(s.registro[1], contains('"credencial":{"id":"cred-1"'));
      expect(find.byType(AccesoScreen), findsNothing);
      expect(find.byType(PerfilScreen), findsOneWidget);
    });

    testWidgets('cancelar no es un error: aviso neutro y sigue en el login', (
      tester,
    ) async {
      final s = PasskeysFalso();
      final navegador = NavegadorFalso()..fallo = const PasskeyCancelada();
      await _abrir(
        tester,
        s,
        ruta: Rutas.perfil,
        conSesion: false,
        navegador: navegador,
      );
      await tester.tap(find.byKey(const Key('entrar-passkey')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No se usó ninguna passkey. Puedes intentarlo de nuevo o entrar con '
          'tu contraseña.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('aviso-passkey')),
          matching: find.byIcon(Icons.info_outline),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(_rutas(s), ['POST /passkeys/login/opciones']);
      expect(find.byType(AccesoScreen), findsOneWidget);
    });

    testWidgets('passkey borrada (401 passkey_invalida): lo explica', (
      tester,
    ) async {
      final s = PasskeysFalso()..falloVerificacion = 'passkey_invalida';
      await _abrir(tester, s, ruta: Rutas.perfil, conSesion: false);
      await tester.tap(find.byKey(const Key('entrar-passkey')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Esa passkey ya no sirve para entrar (quizá la borraste). Entra con '
          'tu contraseña.',
        ),
        findsOneWidget,
      );
      expect(find.byType(AccesoScreen), findsOneWidget);
    });

    testWidgets('en el APK y en el escritorio no hay botón', (tester) async {
      await _abrir(
        tester,
        PasskeysFalso(),
        ruta: Rutas.perfil,
        conSesion: false,
        esWeb: false,
      );
      expect(find.byType(AccesoScreen), findsOneWidget);
      expect(find.byKey(const Key('entrar-passkey')), findsNothing);
    });

    testWidgets('en la web sin soporte tampoco', (tester) async {
      await _abrir(
        tester,
        PasskeysFalso(),
        ruta: Rutas.perfil,
        conSesion: false,
        navegador: NavegadorFalso(soportado: false),
      );
      expect(find.byKey(const Key('entrar-passkey')), findsNothing);
    });

    testWidgets('en el registro no aparece', (tester) async {
      await _abrir(
        tester,
        PasskeysFalso(),
        ruta: Rutas.perfil,
        conSesion: false,
      );
      expect(find.byKey(const Key('entrar-passkey')), findsOneWidget);
      await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
      await tester.pumpAndSettle();
      expect(find.text('Crear cuenta'), findsOneWidget);
      expect(find.byKey(const Key('entrar-passkey')), findsNothing);
    });
  });

  group('Mis passkeys (perfil)', () {
    testWidgets('lista con fecha, último uso y sincronizada', (tester) async {
      await _abrir(tester, PasskeysFalso(), ruta: Rutas.perfil);
      expect(find.text('Mis passkeys'), findsOneWidget);
      expect(find.text('Portátil de casa'), findsOneWidget);
      expect(
        find.text(
          'Creada el 12/10/2026 · último uso: 13/10/2026 · sincronizada entre '
          'tus dispositivos',
        ),
        findsOneWidget,
      );
    });

    testWidgets('crear: nombre, navegador y registro; aparece en la lista', (
      tester,
    ) async {
      final s = PasskeysFalso();
      final navegador = NavegadorFalso();
      await _abrir(tester, s, ruta: Rutas.perfil, navegador: navegador);
      await _crearPasskey(tester, nombre: 'Celular de Ana');

      // v2: la contraseña va en las opciones (no en la verificación).
      expect(
        s.registro.firstWhere((r) => r.contains('/registro/opciones')),
        contains('{"password_actual":"una frase larga"}'),
      );
      expect(
        _rutas(s),
        containsAllInOrder([
          'POST /passkeys/registro/opciones',
          'POST /passkeys/registro/verificacion',
          'GET /passkeys',
        ]),
      );
      final verificacion = s.registro.firstWhere(
        (r) => r.contains('/registro/verificacion'),
      );
      expect(verificacion, contains('"nombre":"Celular de Ana"'));
      expect(verificacion, contains('"credencial":{"id":"cred-nueva"'));
      expect(
        (navegador.opciones.single['rp']! as Map)['id'],
        'buelvasmanuel.github.io',
      );
      expect(find.text('Celular de Ana'), findsOneWidget);
      expect(find.text(MisPasskeysTextos.creada), findsOneWidget);
    });

    testWidgets('cancelar al crear: aviso que no suena a error', (
      tester,
    ) async {
      final s = PasskeysFalso();
      await _abrir(
        tester,
        s,
        ruta: Rutas.perfil,
        navegador: NavegadorFalso()..fallo = const PasskeyCancelada(),
      );
      await _crearPasskey(tester);
      expect(
        find.text(
          'No se creó la passkey. Puedes intentarlo de nuevo cuando quieras.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('aviso-passkeys')),
          matching: find.byIcon(Icons.info_outline),
        ),
        findsOneWidget,
      );
      expect(s.registro.any((r) => r.contains('verificacion')), isFalse);
    });

    testWidgets('este dispositivo ya tiene una: lo dice', (tester) async {
      await _abrir(
        tester,
        PasskeysFalso(),
        ruta: Rutas.perfil,
        navegador: NavegadorFalso()..fallo = const PasskeyYaEnEsteDispositivo(),
      );
      await _crearPasskey(tester);
      expect(find.text(MisPasskeysTextos.yaEnEsteDispositivo), findsOneWidget);
    });

    testWidgets('sin contraseña no se puede pulsar «Crear»', (tester) async {
      await _abrir(tester, PasskeysFalso(), ruta: Rutas.perfil);
      await tester.tap(find.byKey(const Key('crear-passkey')));
      await tester.pumpAndSettle();
      final crear = tester.widget<FilledButton>(
        find.byKey(const Key('confirmar-nombre-passkey')),
      );
      expect(crear.onPressed, isNull);
    });

    testWidgets('contraseña equivocada (403): lo dice y no llama al '
        'navegador', (tester) async {
      final s = PasskeysFalso();
      final navegador = NavegadorFalso();
      await _abrir(tester, s, ruta: Rutas.perfil, navegador: navegador);
      await _crearPasskey(tester, password: 'otra cosa');
      expect(find.text(MisPasskeysTextos.passwordIncorrecta), findsOneWidget);
      expect(navegador.opciones, isEmpty);
    });

    testWidgets('con 10 passkeys (409): explica el máximo', (tester) async {
      final s = PasskeysFalso();
      s.passkeys.addAll([
        for (var i = 2; i <= 10; i++) passkeyJson(i, 'Passkey $i'),
      ]);
      await _abrir(tester, s, ruta: Rutas.perfil);
      await _crearPasskey(tester);
      expect(find.text(MisPasskeysTextos.demasiadas), findsOneWidget);
    });

    testWidgets('borrar pide confirmación y la quita', (tester) async {
      final s = PasskeysFalso();
      await _abrir(tester, s, ruta: Rutas.perfil);
      await tester.tap(find.byKey(const Key('borrar-passkey-1')));
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar «Portátil de casa»?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmar-borrar-passkey')));
      await tester.pumpAndSettle();
      expect(_rutas(s), contains('DELETE /passkeys/1'));
      expect(find.text('Portátil de casa'), findsNothing);
      expect(find.text('Aún no tienes passkeys.'), findsOneWidget);
    });

    testWidgets('navegador sin soporte: explica por qué y no ofrece crear', (
      tester,
    ) async {
      final s = PasskeysFalso();
      await _abrir(
        tester,
        s,
        ruta: Rutas.perfil,
        navegador: NavegadorFalso(soportado: false),
      );
      expect(
        find.text(
          'Tu navegador no admite passkeys; usa Chrome, Edge, Firefox o '
          'Safari recientes.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('crear-passkey')), findsNothing);
      expect(s.registro, isEmpty); // ni siquiera pide la lista
    });

    testWidgets('en el APK y en el escritorio no aparece', (tester) async {
      final s = PasskeysFalso();
      await _abrir(tester, s, ruta: Rutas.perfil, esWeb: false);
      expect(find.byKey(const Key('mis-passkeys')), findsNothing);
      expect(find.text('Mis passkeys'), findsNothing);
      expect(s.registro, isEmpty);
    });
  });
}
