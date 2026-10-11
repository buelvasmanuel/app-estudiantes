import 'package:app_estudiantes/main.dart';
import 'package:app_estudiantes/models/sesion.dart';
import 'package:app_estudiantes/preferencias.dart';
import 'package:app_estudiantes/providers.dart';
import 'package:app_estudiantes/router.dart';
import 'package:app_estudiantes/services/almacen_refresh.dart';
import 'package:app_estudiantes/services/api_service.dart';
import 'package:app_estudiantes/sonidos.dart';
import 'package:app_estudiantes/tema/temas.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Una sesión ya iniciada que no caduca durante el test.
Tokens tokensDePrueba({Rol rol = Rol.jugador}) => Tokens(
  access: 'access-de-prueba',
  accessCaduca: DateTime.now().add(const Duration(hours: 1)),
  refresh: 'refresh-de-prueba',
  usuario: Usuario(id: 1, alias: 'Detective_Ana', rol: rol),
);

/// La app completa (router, pestañas, tema) con [api] en lugar de la real,
/// empezando en la ruta [inicial].
///
/// Por defecto ya hay sesión iniciada. Con `conSesion: false` la app arranca
/// como al abrirla: lee el refresh de [almacen] (vacío = pantalla de login).
///
/// [preferencias]: por defecto, tutorial ya visto y tema [tema] (Expediente).
/// [reproductor]: por defecto, uno que no suena.
Widget appDePrueba(
  ApiService api, {
  String inicial = Rutas.estudiantes,
  bool conSesion = true,
  AlmacenRefresh? almacen,
  Rol rol = Rol.jugador,
  TemaJuego tema = TemaJuego.expediente,
  Preferencias? preferencias,
  Reproductor? reproductor,
}) => ProviderScope(
  retry: sinReintentos,
  overrides: [
    preferenciasProvider.overrideWithValue(
      preferencias ??
          PreferenciasEnMemoria({
            Preferencias.claveTutorial: true,
            Preferencias.claveTema: tema.name,
          }),
    ),
    reproductorProvider.overrideWithValue(reproductor ?? ReproductorMudo()),
    apiServiceProvider.overrideWithValue(api),
    almacenRefreshProvider.overrideWithValue(almacen ?? AlmacenEnMemoria()),
    if (conSesion)
      sesionProvider.overrideWith(
        (ref) => crearSesion(ref, tokens: tokensDePrueba(rol: rol)),
      ),
    routerProvider.overrideWith(
      (ref) => crearRouterDesde(ref, inicial: inicial),
    ),
  ],
  child: const EstudiantesApp(),
);

/// Anota lo que habría sonado (y no suena).
class ReproductorMudo implements Reproductor {
  final sonados = <Sonido>[];

  @override
  Future<void> reproducir(Sonido sonido) async => sonados.add(sonido);
}
