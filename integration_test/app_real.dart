// La app completa contra la API real (la de --dart-define=API_URL).
//
// Mientras la API de Render no tenga /auth, se arranca con una sesión
// simulada: los GET de estudiantes, estadísticas y predicción son públicos y
// la API ignora el token en ellos (CONTRATO_AUTH.md §4.10).
import 'package:app_estudiantes/main.dart';
import 'package:app_estudiantes/models/sesion.dart';
import 'package:app_estudiantes/providers.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/services/almacen_refresh.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Widget appReal({String inicial = Rutas.campus}) => ProviderScope(
  retry: sinReintentos,
  overrides: [
    almacenRefreshProvider.overrideWithValue(AlmacenEnMemoria()),
    sesionProvider.overrideWith(
      (ref) => crearSesion(
        ref,
        tokens: Tokens(
          access: 'sesion-simulada',
          accessCaduca: DateTime.now().add(const Duration(hours: 1)),
          refresh: 'sesion-simulada',
          usuario: const Usuario(id: 0, alias: 'Prueba', rol: Rol.jugador),
        ),
      ),
    ),
    routerProvider.overrideWith((ref) {
      final router = crearRouter(
        sesion: ref.watch(sesionProvider),
        inicial: inicial,
      );
      ref.onDispose(router.dispose);
      return router;
    }),
  ],
  child: const EstudiantesApp(),
);
