import 'package:app_estudiantes/main.dart';
import 'package:app_estudiantes/providers.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// La app completa (router, pestañas, tema) con [api] en lugar de la real,
/// empezando en la ruta [inicial].
Widget appDePrueba(ApiService api, {String inicial = Rutas.estudiantes}) =>
    ProviderScope(
      retry: sinReintentos,
      overrides: [
        apiServiceProvider.overrideWithValue(api),
        routerProvider.overrideWith((ref) {
          final router = crearRouter(inicial: inicial);
          ref.onDispose(router.dispose);
          return router;
        }),
      ],
      child: const EstudiantesApp(),
    );
