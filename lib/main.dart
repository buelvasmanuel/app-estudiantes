import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preferencias.dart';
import 'providers.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Preferencias preferencias;
  try {
    preferencias = await PreferenciasDispositivo.abrir();
  } on Object {
    // Sin almacenamiento (p. ej. navegador en modo restringido): la app
    // funciona igual, solo que no recuerda el tema ni el tutorial.
    preferencias = PreferenciasEnMemoria();
  }
  runApp(
    ProviderScope(
      retry: sinReintentos,
      overrides: [preferenciasProvider.overrideWithValue(preferencias)],
      child: const EstudiantesApp(),
    ),
  );
}

class EstudiantesApp extends ConsumerWidget {
  const EstudiantesApp({super.key});

  /// Fundido al cambiar de tema (≤ 300 ms; ninguno con "reducir movimiento").
  static const fundidoTema = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = ref.watch(temaProvider).datos;
    final quieto = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return MaterialApp.router(
      title: 'Campus Detective',
      debugShowCheckedModeBanner: false,
      // Cada tema es completo (Noche es oscuro, Expediente claro): no se
      // mezcla con el claro/oscuro del sistema.
      theme: tema,
      darkTheme: tema,
      themeMode: ThemeMode.light,
      themeAnimationDuration: quieto ? Duration.zero : fundidoTema,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
