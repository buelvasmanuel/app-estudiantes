import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router.dart';
import 'theme.dart';

void main() {
  runApp(const ProviderScope(retry: sinReintentos, child: EstudiantesApp()));
}

class EstudiantesApp extends ConsumerWidget {
  const EstudiantesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Estudiantes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro,
      darkTheme: AppTheme.oscuro,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
