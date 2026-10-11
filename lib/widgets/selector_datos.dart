import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Selector de la pestaña "Datos": Estudiantes · Gráficas · Predicción.
///
/// Va en la barra superior de esas tres pantallas (`AppBar.bottom`). Cada
/// una es una rama de un `StatefulShellRoute` anidado, así que al cambiar
/// conservan su estado (búsqueda, estadística elegida, formulario).
class SelectorDatos extends StatelessWidget implements PreferredSizeWidget {
  const SelectorDatos({super.key});

  static const _opciones = [
    (Icons.people_outline, 'Estudiantes'),
    (Icons.bar_chart_outlined, 'Gráficas'),
    (Icons.psychology_outlined, 'Predicción'),
  ];

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          for (final (i, (icono, texto)) in _opciones.indexed)
            ButtonSegment(
              value: i,
              icon: Icon(icono, size: 18),
              label: FittedBox(fit: BoxFit.scaleDown, child: Text(texto)),
            ),
        ],
        selected: {shell.currentIndex},
        onSelectionChanged: (s) => shell.goBranch(s.first),
      ),
    );
  }
}
