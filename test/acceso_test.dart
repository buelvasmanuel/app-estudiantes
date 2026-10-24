import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/screens/acceso_screen.dart';
import 'package:app_estudiantes/screens/estudiante_detalle_screen.dart';
import 'package:app_estudiantes/services/almacen_refresh.dart';
import 'package:app_estudiantes/services/sesion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/api_falsa.dart';
import 'support/app_de_prueba.dart';
import 'support/servidor_falso.dart';

ServidorFalso _servidor() =>
    ServidorFalso(publicas: {'/estudiantes/': estudiantesJson});

Future<void> _escribir(WidgetTester tester, String campo, String texto) =>
    tester.enterText(find.byKey(Key(campo)), texto);

Future<void> _entrar(
  WidgetTester tester, {
  String password = 'una frase larga',
}) async {
  await _escribir(tester, 'alias', 'Detective_Ana');
  await _escribir(tester, 'password', password);
  await tester.tap(find.text('Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin sesión lleva al login; al entrar, a la lista', (
    tester,
  ) async {
    final servidor = _servidor();
    await tester.pumpWidget(appDePrueba(servidor.api(), conSesion: false));
    await tester.pumpAndSettle();

    expect(find.byType(AccesoScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(servidor.registro, isEmpty); // no se pidió nada sin sesión

    await _entrar(tester);
    expect(find.text('Jorge Rodríguez'), findsOneWidget);
    expect(sinProgreso(servidor.registro), [
      'POST /auth/login',
      'GET /estudiantes/',
    ]);
  });

  testWidgets('credenciales inválidas: muestra el mensaje de la API', (
    tester,
  ) async {
    final servidor = _servidor();
    await tester.pumpWidget(appDePrueba(servidor.api(), conSesion: false));
    await tester.pumpAndSettle();

    await _entrar(tester, password: 'equivocada');
    expect(find.text('Mensaje de credenciales_invalidas'), findsOneWidget);
    expect(find.byType(AccesoScreen), findsOneWidget);
  });

  testWidgets('429: el botón muestra la cuenta atrás', (tester) async {
    final servidor = _servidor()..limiteAlcanzado = 30;
    await tester.pumpWidget(appDePrueba(servidor.api(), conSesion: false));
    await tester.pumpAndSettle();

    await _entrar(tester);
    expect(find.text('Espera 30 s'), findsOneWidget);
    final boton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(boton.onPressed, isNull);
    // El aviso lleva la misma cuenta atrás que el botón…
    expect(
      find.text(
        'Demasiados intentos. Espera 30 s antes de volver a intentarlo.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Espera 20 s'), findsOneWidget);
    expect(
      find.text(
        'Demasiados intentos. Espera 20 s antes de volver a intentarlo.',
      ),
      findsOneWidget,
    );
    // …y al terminar desaparece (no se queda un «27 s» viejo).
    await tester.pump(const Duration(seconds: 21));
    expect(find.textContaining('Demasiados intentos'), findsNothing);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('registro con una contraseña común (422 password_comun): el '
      'aviso va junto al campo y se quita al escribir otra', (tester) async {
    final servidor = _servidor();
    await tester.pumpWidget(appDePrueba(servidor.api(), conSesion: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pumpAndSettle();
    await _escribir(tester, 'alias', 'Nuevo_Detective');
    await _escribir(tester, 'password', 'Universidad1');
    await _escribir(tester, 'repetida', 'Universidad1');
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();

    const aviso =
        'Esa contraseña es demasiado común y se adivina enseguida: elige otra';
    final campo = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('password')),
        matching: find.byType(TextField),
      ),
    );
    expect(campo.decoration?.errorText, aviso);
    // Junto al campo, no en el recuadro de errores generales.
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byType(AccesoScreen), findsOneWidget);

    await _escribir(tester, 'password', 'mi lupa favorita');
    await tester.pumpAndSettle(); // el error se va con un fundido corto
    expect(find.text(aviso), findsNothing);
  });

  testWidgets('registro: valida antes de enviar y después entra', (
    tester,
  ) async {
    final servidor = _servidor();
    await tester.pumpWidget(appDePrueba(servidor.api(), conSesion: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pumpAndSettle();

    await _escribir(tester, 'alias', 'Nuevo_Detective');
    await _escribir(tester, 'password', 'corta');
    await _escribir(tester, 'repetida', 'corta');
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Al menos 10 caracteres'), findsOneWidget);
    expect(servidor.registro, isEmpty);

    await _escribir(tester, 'password', 'nuevo_detective');
    await _escribir(tester, 'repetida', 'nuevo_detective');
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('No puede ser igual al alias'), findsOneWidget);

    await _escribir(tester, 'password', 'mi lupa favorita');
    await _escribir(tester, 'repetida', 'mi lupa favorita');
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
    expect(sinProgreso(servidor.registro).first, 'POST /auth/registro');
    expect(find.text('Jorge Rodríguez'), findsOneWidget);
  });

  testWidgets('enlace directo al registro sin sesión: abre el registro', (
    tester,
  ) async {
    await tester.pumpWidget(
      appDePrueba(_servidor().api(), conSesion: false, inicial: Rutas.registro),
    );
    await tester.pumpAndSettle();
    expect(find.text('Crear cuenta'), findsOneWidget);
  });

  testWidgets('enlace a un estudiante sin sesión: login y luego el detalle', (
    tester,
  ) async {
    final servidor = _servidor();
    await tester.pumpWidget(
      appDePrueba(
        servidor.api(),
        conSesion: false,
        inicial: Rutas.estudiante(2),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccesoScreen), findsOneWidget);

    await _entrar(tester);
    expect(find.byType(EstudianteDetalleScreen), findsOneWidget);
    expect(find.text('Esperanza Torres'), findsWidgets);
  });

  testWidgets('con un refresh guardado entra sin pedir login', (tester) async {
    final servidor = _servidor();
    final almacen = AlmacenEnMemoria(servidor.sesionPrevia());
    await tester.pumpWidget(
      appDePrueba(servidor.api(), conSesion: false, almacen: almacen),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccesoScreen), findsNothing);
    expect(find.text('Jorge Rodríguez'), findsOneWidget);
  });

  testWidgets('sin red al recuperar la sesión: error y Reintentar', (
    tester,
  ) async {
    final servidor = _servidor()..sinRed = true;
    final almacen = AlmacenEnMemoria(servidor.sesionPrevia());
    await tester.pumpWidget(
      appDePrueba(servidor.api(), conSesion: false, almacen: almacen),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sin conexión con la API'), findsOneWidget);

    servidor.sinRed = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Jorge Rodríguez'), findsOneWidget);
  });

  testWidgets('cerrar sesión desde el menú vuelve al login', (tester) async {
    final servidor = _servidor();
    final almacen = AlmacenEnMemoria();
    await tester.pumpWidget(
      appDePrueba(servidor.api(), conSesion: false, almacen: almacen),
    );
    await tester.pumpAndSettle();
    await _entrar(tester);

    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Detective_Ana'), findsOneWidget);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(find.byType(AccesoScreen), findsOneWidget);
    expect(sinProgreso(servidor.registro).last, 'POST /auth/logout');
    expect(await almacen.leer(), isNull);
  });

  testWidgets('si la sesión se revoca mientras se usa, login con aviso', (
    tester,
  ) async {
    final servidor = _servidor();
    await tester.pumpWidget(appDePrueba(servidor.api(), conSesion: false));
    await tester.pumpAndSettle();
    await _entrar(tester);

    // Un endpoint protegido nos da 401 y el refresh ya no vale.
    servidor
      ..protegidas['/estudiantes/'] = estudiantesJson
      ..publicas.remove('/estudiantes/')
      ..revocarSesion();
    // Deslizar hacia abajo para actualizar la lista.
    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccesoScreen), findsOneWidget);
    expect(find.text(GestorSesion.avisoRevocada), findsOneWidget);
  });
}
