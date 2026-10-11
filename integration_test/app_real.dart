// La app completa contra la API real (la de --dart-define=API_URL), con una
// sesión real de la cuenta de prueba (--dart-define=ALIAS y PASSWORD).
//
// Antes se usaba una sesión simulada, pero ya no vale: la barra superior pide
// el progreso del jugador (autenticado) y con un token falso la API responde
// 401 y la app, con razón, cierra la sesión.
import 'package:app_estudiantes/config.dart';
import 'package:app_estudiantes/main.dart';
import 'package:app_estudiantes/models/sesion.dart';
import 'package:app_estudiantes/preferencias.dart';
import 'package:app_estudiantes/providers.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/services/almacen_refresh.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:app_estudiantes/tema/temas.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _alias = String.fromEnvironment('ALIAS');
const _password = String.fromEnvironment('PASSWORD');

/// Tema de las capturas: --dart-define=TEMA=noche|expediente (por defecto,
/// Expediente).
const _tema = String.fromEnvironment('TEMA', defaultValue: 'expediente');

TemaJuego get temaDePrueba =>
    TemaJuego.values.firstWhere((t) => t.name == _tema);

/// Tutorial ya visto y el tema de las capturas (no se tocan las
/// preferencias reales del equipo).
Preferencias preferenciasDePrueba() => PreferenciasEnMemoria({
  Preferencias.claveTutorial: true,
  Preferencias.claveTema: temaDePrueba.name,
});

/// `POST /auth/login` con la cuenta de prueba. Llamarla dentro de
/// `tester.runAsync` (hace una petición de red de verdad).
Future<Tokens> sesionReal() async {
  if (_alias.isEmpty || _password.isEmpty) {
    throw StateError('Faltan --dart-define=ALIAS y --dart-define=PASSWORD');
  }
  final api = ApiService();
  try {
    final enviado = DateTime.now();
    final json = await api.enviar(
      PeticionApi(
        'POST',
        '/auth/login',
        cuerpo: {'alias': _alias, 'password': _password},
        conInterceptores: false,
        limite: Config.timeoutArranque,
      ),
    );
    return Tokens.fromJson(json, recibido: enviado);
  } finally {
    api.cerrar();
  }
}

/// La app ya con la sesión de [tokens] (ver [sesionReal]), en [inicial].
Widget appReal({required Tokens tokens, String inicial = Rutas.campus}) =>
    ProviderScope(
      retry: sinReintentos,
      overrides: [
        preferenciasProvider.overrideWithValue(preferenciasDePrueba()),
        almacenRefreshProvider.overrideWithValue(AlmacenEnMemoria()),
        sesionProvider.overrideWith((ref) => crearSesion(ref, tokens: tokens)),
        routerProvider.overrideWith(
          (ref) => crearRouterDesde(ref, inicial: inicial),
        ),
      ],
      child: const EstudiantesApp(),
    );

/// La app completa contra la API real, SIN sesión: hay que entrar por la
/// pantalla de login. Empieza en [inicial] (tras el login vuelve ahí).
///
/// [preferencias]: por defecto, tutorial visto y el tema de --dart-define=TEMA.
Widget appConLogin({required String inicial, Preferencias? preferencias}) =>
    ProviderScope(
      retry: sinReintentos,
      overrides: [
        preferenciasProvider.overrideWithValue(
          preferencias ?? preferenciasDePrueba(),
        ),
        almacenRefreshProvider.overrideWithValue(AlmacenEnMemoria()),
        routerProvider.overrideWith(
          (ref) => crearRouterDesde(ref, inicial: inicial),
        ),
      ],
      child: const EstudiantesApp(),
    );
