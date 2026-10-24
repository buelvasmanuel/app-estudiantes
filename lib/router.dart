import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/estudiante.dart';
import 'preferencias.dart';
import 'providers.dart';
import 'screens/estudiante_detalle_screen.dart';
import 'screens/acceso_screen.dart';
import 'screens/campus_screen.dart';
import 'screens/caso_juego_screen.dart';
import 'screens/casos_screen.dart';
import 'screens/docente_screen.dart';
import 'screens/duelo_screen.dart';
import 'screens/elegir_rival_screen.dart';
import 'duelo/modelo.dart';
import 'screens/estudiantes_screen.dart';
import 'screens/graficas_screen.dart';
import 'screens/laboratorio_screen.dart';
import 'screens/perfil_screen.dart';
import 'screens/prediccion_screen.dart';
import 'screens/rescate_screen.dart';
import 'screens/tutorial_screen.dart';
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

  /// El tutorial del búho (la primera vez, tras entrar).
  static const tutorial = '/tutorial';

  /// El duelo de cartas (dentro de la pestaña Casos): elegir rival.
  static const duelo = '$casos/duelo';
  static const dueloMaquina = '$duelo/maquina';
  static const dueloJugador = '$duelo/jugador';

  static String estudiante(int id) => '$estudiantes/$id';
  static String rescate(int estudianteId) => '$laboratorio/$estudianteId';
  static String casoJuego(String codigo) =>
      '$casos/${Uri.encodeComponent(codigo)}';
}

final routerProvider = Provider<GoRouter>((ref) => crearRouterDesde(ref));

/// El router con la sesión y el tutorial de [ref]. Lo usan [routerProvider] y
/// los tests (con otra ruta [inicial]).
GoRouter crearRouterDesde(Ref ref, {String inicial = Rutas.campus}) {
  // El router no es un widget: el estado del tutorial le llega como
  // Listenable para que vuelva a evaluar redirect cuando cambia.
  final tutorialVisto = ValueNotifier(ref.read(tutorialVistoProvider));
  ref.listen(tutorialVistoProvider, (_, visto) => tutorialVisto.value = visto);
  final router = crearRouter(
    sesion: ref.watch(sesionProvider),
    tutorialVisto: tutorialVisto,
    inicial: inicial,
  );
  ref.onDispose(() {
    router.dispose();
    tutorialVisto.dispose();
  });
  return router;
}

/// A dónde llevar según el estado de la [sesion]. Sin sesión, todo lleva al
/// login; la ruta pedida se guarda en `?desde=` para volver a ella después.
/// Con sesión y sin haber visto el tutorial, primero el tutorial.
String? redirigir(
  GestorSesion sesion,
  GoRouterState state, {
  bool tutorialVisto = true,
}) {
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
    // Un enlace directo al registro (`/#/registro`) pasa por «cargando»
    // mientras se comprueba la sesión: sin sesión, vuelve al registro (no al
    // login).
    EstadoSesion.sinSesion
        when ruta == Rutas.cargando &&
            state.uri.queryParameters['desde'] == Rutas.registro =>
      Rutas.registro,
    EstadoSesion.sinSesion => con(
      Rutas.login,
      ruta == Rutas.cargando ? desde : pedida,
    ),
    EstadoSesion.conSesion when !tutorialVisto =>
      ruta == Rutas.tutorial
          ? null
          : con(
              Rutas.tutorial,
              enAcceso || ruta == Rutas.cargando ? desde : pedida,
            ),
    EstadoSesion.conSesion
        when enAcceso || ruta == Rutas.cargando || ruta == Rutas.tutorial =>
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
        !ruta.startsWith(Rutas.cargando) &&
        !ruta.startsWith(Rutas.tutorial)
    ? ruta
    : null;

/// Una rama por pestaña. `StatefulShellRoute.indexedStack` conserva cada
/// pestaña al cambiar (como el IndexedStack de antes), pero solo construye
/// una rama la primera vez que se visita: al arrancar se pide únicamente lo
/// de la pestaña visible.
GoRouter crearRouter({
  required GestorSesion sesion,
  ValueListenable<bool>? tutorialVisto,
  String inicial = Rutas.campus,
}) {
  final raiz = GlobalKey<NavigatorState>(debugLabel: 'raiz');
  return GoRouter(
    navigatorKey: raiz,
    initialLocation: inicial,
    // Cada cambio de sesión (login, logout, sesión revocada) o del tutorial
    // vuelve a evaluar redirect.
    refreshListenable: Listenable.merge([sesion, ?tutorialVisto]),
    redirect: (_, state) =>
        redirigir(sesion, state, tutorialVisto: tutorialVisto?.value ?? true),
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
      GoRoute(path: Rutas.tutorial, builder: (_, _) => const TutorialScreen()),
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
                  // Antes que ':codigo', que también casaría con "duelo".
                  GoRoute(
                    path: 'duelo',
                    builder: (_, _) => const ElegirRivalScreen(),
                    routes: [
                      GoRoute(
                        path: 'maquina',
                        builder: (_, _) => const DueloScreen(),
                      ),
                      GoRoute(
                        path: 'jugador',
                        builder: (_, _) =>
                            const DueloScreen(modo: ModoDuelo.jugador),
                      ),
                    ],
                  ),
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

  /// ¿Cabe la etiqueta más larga («Laboratorio») en su quinto de ancho, con
  /// la letra y la escala de texto del usuario?
  static bool _etiquetasCaben(BuildContext context) {
    final tema = Theme.of(context);
    final estilo =
        tema.navigationBarTheme.labelTextStyle?.resolve({}) ??
        tema.textTheme.labelMedium;
    final pintor = TextPainter(
      text: TextSpan(text: 'Laboratorio', style: estilo),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final ancho = pintor.width;
    pintor.dispose();
    // Cada destino deja unos 2 px a cada lado para la etiqueta.
    return ancho <= MediaQuery.sizeOf(context).width / 5 - 4;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: shell.goBranch,
        // Cinco etiquetas a ~72 px cada una: con letra grande en un celular
        // estrecho, «Laboratorio» se partía en dos líneas. Entonces solo se
        // muestra la de la pestaña elegida (las demás siguen con su icono y
        // su nombre para el lector de pantalla).
        labelBehavior: _etiquetasCaben(context)
            ? NavigationDestinationLabelBehavior.alwaysShow
            : NavigationDestinationLabelBehavior.onlyShowSelected,
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
