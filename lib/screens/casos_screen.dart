import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../juego/juego_api.dart';
import '../juego/modelo.dart';
import '../laboratorio/apariencia.dart';
import '../providers.dart';
import '../router.dart';
import '../theme.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/menu_cuenta.dart';

/// Pestaña "Casos": preguntas que se resuelven mirando los datos.
class CasosScreen extends ConsumerWidget {
  const CasosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(casosJuegoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Casos'), actions: const [MenuCuenta()]),
      body: switch (estado) {
        AsyncValue(value: final List<CasoJuegoResumen> casos) => _Lista(
          casos: casos,
        ),
        AsyncValue(:final error?) => ErrorVista(
          error: error,
          onReintentar: () => ref.invalidate(casosJuegoProvider),
        ),
        _ => CargandoVista(
          mensaje: 'Abriendo el archivo de casos…',
          despertando: ref.watch(apiServiceProvider).despertando,
        ),
      },
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.casos});

  final List<CasoJuegoResumen> casos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final apariencia = ref.watch(aparienciaLaboratorioProvider);
    final resueltos = casos.where((c) => c.resuelto).length;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(casosJuegoProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AnchoMaximo(
            ancho: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    apariencia.buho(
                      animo: resueltos == casos.length && casos.isNotEmpty
                          ? AnimoBuho.contento
                          : AnimoBuho.atento,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Card.filled(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Cada caso se resuelve mirando los datos reales '
                            'del campus. La primera vez que aciertes ganas '
                            'XP (más si aciertas al primer intento).',
                            style: tema.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '$resueltos de ${casos.length} resueltos',
                  style: tema.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: casos.isEmpty ? 0 : resueltos / casos.length,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                for (final nivel in NivelCaso.values)
                  ..._seccion(context, nivel, [
                    for (final c in casos)
                      if (c.nivel == nivel) c,
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _seccion(
    BuildContext context,
    NivelCaso nivel,
    List<CasoJuegoResumen> casos,
  ) {
    if (casos.isEmpty) return const [];
    final tema = Theme.of(context);
    final ok = ColoresEstado.of(context).ok;
    return [
      const SizedBox(height: 16),
      Text(
        '${nivel.nombre} · ${casos.first.xp} XP',
        style: tema.textTheme.titleSmall?.copyWith(
          color: tema.colorScheme.primary,
        ),
      ),
      for (final c in casos)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            c.resuelto ? Icons.check_circle : Icons.search,
            color: c.resuelto ? ok : tema.colorScheme.onSurfaceVariant,
          ),
          title: Text(c.titulo),
          subtitle: Text(
            c.resuelto
                ? 'Resuelto · +${c.xpGanada} XP'
                : c.intentos == 0
                ? 'Sin abrir · ${c.xp} XP'
                : '${c.intentos} ${c.intentos == 1 ? 'intento' : 'intentos'}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(Rutas.casoJuego(c.codigo)),
        ),
    ];
  }
}
