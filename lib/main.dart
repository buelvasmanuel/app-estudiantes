import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'identidad.dart';
import 'providers.dart';
import 'router.dart';

void main() {
  runApp(const ProviderScope(retry: sinReintentos, child: EstudiantesApp()));
}

class EstudiantesApp extends ConsumerWidget {
  const EstudiantesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final temas = Identidad.activa.temas;
    return MaterialApp.router(
      title: 'Estudiantes',
      debugShowCheckedModeBanner: false,
      theme: temas.claro,
      darkTheme: temas.oscuro,
      themeMode: temas.modo,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
