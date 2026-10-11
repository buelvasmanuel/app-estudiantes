import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/estudiante.dart';
import 'providers.dart';
import 'screens/estudiante_detalle_screen.dart';
import 'screens/estudiantes_screen.dart';
import 'screens/graficas_screen.dart';
import 'screens/prediccion_screen.dart';
import 'widgets/estado_vistas.dart';

/// Rutas de la app. En la web van detrás de `#` (`/#/graficas`): GitHub Pages
/// no sabe reescribir rutas, y con `#` recargar la página siempre funciona.
abstract final class Rutas {
  static const estudiantes = '/estudiantes';
  static const graficas = '/graficas';
  static const prediccion = '/prediccion';

  static String estudiante(int id) => '$estudiantes/$id';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = crearRouter();
  ref.onDispose(router.dispose);
  return router;
});

/// Una rama por pestaña. `StatefulShellRoute.indexedStack` conserva cada
/// pestaña al cambiar (como el IndexedStack de antes), pero solo construye
/// una rama la primera vez que se visita: al arrancar se pide únicamente lo
/// de la pestaña visible.
GoRouter crearRouter({String inicial = Rutas.estudiantes}) {
  final raiz = GlobalKey<NavigatorState>(debugLabel: 'raiz');
  return GoRouter(
    navigatorKey: raiz,
    initialLocation: inicial,
    routes: [
      GoRoute(path: '/', redirect: (_, _) => Rutas.estudiantes),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => InicioPage(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.estudiantes,
                builder: (_, _) => const EstudiantesScreen(),
                routes: [
                  // El detalle tapa la barra de pestañas: va en el Navigator raíz.
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: raiz,
                    builder: (_, state) => switch (state.extra) {
                      final Estudiante e => EstudianteDetalleScreen(
                        estudiante: e,
                      ),
                      _ => _DetallePorId(
                        id: int.tryParse(state.pathParameters['id'] ?? ''),
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
                builder: (_, _) => const GraficasScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.prediccion,
                builder: (_, _) => const PrediccionScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Estructura principal: una NavigationBar con 3 pestañas.
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
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Estudiantes',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Gráficas',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'Predicción',
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
