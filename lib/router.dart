import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/estudiante.dart';
import 'providers.dart';
import 'screens/estudiante_detalle_screen.dart';
import 'screens/acceso_screen.dart';
import 'screens/campus_screen.dart';
import 'screens/caso_juego_screen.dart';
import 'screens/casos_screen.dart';
import 'screens/docente_screen.dart';
import 'screens/estudiantes_screen.dart';
import 'screens/graficas_screen.dart';
import 'screens/laboratorio_screen.dart';
import 'screens/perfil_screen.dart';
import 'screens/prediccion_screen.dart';
import 'screens/rescate_screen.dart';
import 'services/sesion.dart';
import 'widgets/estado_vistas.dart';
import 'widgets/selector_datos.dart';

/// Rutas de la app. En la web van detrás de `#` (`/#/graficas`): GitHub Pages
/// no sabe reescribir rutas, y con `#` recargar la página siempre funciona.
abstract final class Rutas {
  static const campus = '/campus';
  static const casos = '/casos';
  static const laboratorio = '/laboratorio';
  static const perfil = '/perfil';

  /// Panel del docente (fuera de las pestañas, a pantalla completa).
  static const docente = '/docente';
  static const estudiantes = '/estudiantes';
  static const graficas = '/graficas';
  static const prediccion = '/prediccion';
  static const login = '/login';
  static const registro = '/registro';

  /// Mientras se recupera la sesión guardada al arrancar.
  static const cargando = '/cargando';

  static String estudiante(int id) => '$estudiantes/$id';
  static String rescate(int estudianteId) => '$laboratorio/$estudianteId';
  static String casoJuego(String codigo) =>
      '$casos/${Uri.encodeComponent(codigo)}';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = crearRouter(sesion: ref.watch(sesionProvider));
  ref.onDispose(router.dispose);
  return router;
});

/// A dónde llevar según el estado de la [sesion]. Sin sesión, todo lleva al
/// login; la ruta pedida se guarda en `?desde=` para volver a ella después.
String? redirigir(GestorSesion sesion, GoRouterState state) {
  final ruta = state.matchedLocation;
  final enAcceso = ruta == Rutas.login || ruta == Rutas.registro;
  final desde = _rutaInterna(state.uri.queryParameters['desde']);
  final pedida = state.uri.toString();

  String con(String destino, String? volverA) => volverA == null
      ? destino
      : Uri(path: destino, queryParameters: {'desde': volverA}).toString();

  return switch (sesion.estado) {
    EstadoSesion.restaurando =>
      ruta == Rutas.cargando ? null : con(Rutas.cargando, pedida),
    EstadoSesion.sinSesion when enAcceso => null,
    EstadoSesion.sinSesion => con(
      Rutas.login,
      ruta == Rutas.cargando ? desde : pedida,
    ),
    EstadoSesion.conSesion when enAcceso || ruta == Rutas.cargando =>
      desde ?? Rutas.campus,
    EstadoSesion.conSesion => null,
  };
}

/// Solo rutas de la propia app (`/algo`), nunca `//otro-sitio` ni URLs
/// completas.
String? _rutaInterna(String? ruta) =>
    ruta != null &&
        ruta.startsWith('/') &&
        !ruta.startsWith('//') &&
        !ruta.startsWith(Rutas.login) &&
        !ruta.startsWith(Rutas.registro) &&
        !ruta.startsWith(Rutas.cargando)
    ? ruta
    : null;

/// Una rama por pestaña. `StatefulShellRoute.indexedStack` conserva cada
/// pestaña al cambiar (como el IndexedStack de antes), pero solo construye
/// una rama la primera vez que se visita: al arrancar se pide únicamente lo
/// de la pestaña visible.
GoRouter crearRouter({
  required GestorSesion sesion,
  String inicial = Rutas.campus,
}) {
  final raiz = GlobalKey<NavigatorState>(debugLabel: 'raiz');
  return GoRouter(
    navigatorKey: raiz,
    initialLocation: inicial,
    // Cada cambio de sesión (login, logout, sesión revocada) vuelve a
    // evaluar redirect.
    refreshListenable: sesion,
    redirect: (_, state) => redirigir(sesion, state),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => Rutas.campus),
      GoRoute(
        path: Rutas.cargando,
        builder: (_, _) => const CargandoSesionScreen(),
      ),
      GoRoute(
        path: Rutas.login,
        builder: (_, state) => AccesoScreen(
          modo: ModoAcceso.login,
          desde: state.uri.queryParameters['desde'],
        ),
      ),
      GoRoute(
        path: Rutas.registro,
        builder: (_, state) => AccesoScreen(
          modo: ModoAcceso.registro,
          desde: state.uri.queryParameters['desde'],
        ),
      ),
      GoRoute(path: Rutas.docente, builder: (_, _) => const DocenteScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => InicioPage(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.campus,
                builder: (_, _) => const CampusScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.casos,
                builder: (_, _) => const CasosScreen(),
                routes: [
                  GoRoute(
                    path: ':codigo',
                    builder: (_, state) => CasoJuegoScreen(
                      codigo: state.pathParameters['codigo'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.laboratorio,
                builder: (_, _) => const LaboratorioScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => RescateScreen(
                      // Un id que no es número no existe como caso: la API
                      // responde 404 caso_no_disponible.
                      estudianteId:
                          int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // "Datos": las tres herramientas originales, cada una en su rama
          // (conservan su estado al cambiar con el SelectorDatos).
          StatefulShellBranch(
            routes: [
              StatefulShellRoute.indexedStack(
                builder: (_, _, shellDatos) => shellDatos,
                branches: [
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: Rutas.estudiantes,
                        // ?carrera=Derecho: llega filtrada desde el Campus.
                        builder: (_, state) => EstudiantesScreen(
                          carrera: state.uri.queryParameters['carrera'],
                          pestanas: const SelectorDatos(),
                        ),
                        routes: [
                          // El detalle tapa la barra de pestañas: va en el
                          // Navigator raíz.
                          GoRoute(
                            path: ':id',
                            parentNavigatorKey: raiz,
                            builder: (_, state) => switch (state.extra) {
                              final Estudiante e => EstudianteDetalleScreen(
                                estudiante: e,
                              ),
                              _ => _DetallePorId(
                                id: int.tryParse(
                                  state.pathParameters['id'] ?? '',
                                ),
                              ),
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: Rutas.graficas,
                        builder: (_, _) =>
                            const GraficasScreen(pestanas: SelectorDatos()),
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: Rutas.prediccion,
                        builder: (_, _) =>
                            const PrediccionScreen(pestanas: SelectorDatos()),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.perfil,
                builder: (_, _) => const PerfilScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Estructura principal: una NavigationBar con 5 pestañas (Campus, Casos,
/// Laboratorio, Datos y Perfil, como en la arquitectura de la propuesta §5).
class InicioPage extends StatelessWidget {
  const InicioPage({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: shell.goBranch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_city_outlined),
            selectedIcon: Icon(Icons.location_city),
            label: 'Campus',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_search_outlined),
            selectedIcon: Icon(Icons.manage_search),
            label: 'Casos',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Laboratorio',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Datos',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

/// Detalle abierto por URL (`/#/estudiantes/12`) sin pasar por la lista: el
/// estudiante se busca en la lista (que se descarga si hace falta).
class _DetallePorId extends ConsumerWidget {
  const _DetallePorId({required this.id});

  final int? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(estudiantesProvider);
    final api = ref.watch(apiServiceProvider);
    final estudiante = estado.value?.where((e) => e.id == id).firstOrNull;
    if (estudiante != null) {
      return EstudianteDetalleScreen(estudiante: estudiante);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Estudiante')),
      body: switch (estado) {
        AsyncValue(hasValue: true) => const VaciaVista(
          mensaje: 'No existe un estudiante con ese número.',
          icono: Icons.person_off_outlined,
        ),
        AsyncValue(:final error?) => ErrorVista(
          error: error,
          onReintentar: () => ref.invalidate(estudiantesProvider),
        ),
        _ => CargandoVista(
          mensaje: 'Cargando estudiante…',
          despertando: api.despertando,
        ),
      },
    );
  }
}
