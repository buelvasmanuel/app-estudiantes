import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../laboratorio/apariencia.dart';
import '../laboratorio/modelo.dart';
import '../laboratorio/providers.dart';
import '../laboratorio/textos.dart';
import '../providers.dart';
import '../router.dart';
import '../theme.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/menu_cuenta.dart';

/// Pestaña "Laboratorio": la lista de estudiantes que se pueden rescatar.
class LaboratorioScreen extends ConsumerWidget {
  const LaboratorioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(casosProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laboratorio'),
        actions: const [MenuCuenta()],
      ),
      body: switch (estado) {
        AsyncValue(value: final ListaCasos lista) => _Lista(lista: lista),
        AsyncValue(:final error?) => ErrorVista(
          error: error,
          onReintentar: () => ref.invalidate(casosProvider),
        ),
        _ => CargandoVista(
          mensaje: 'Preparando los casos…',
          despertando: ref.watch(apiServiceProvider).despertando,
        ),
      },
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.lista});

  final ListaCasos lista;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final apariencia = ref.watch(aparienciaLaboratorioProvider);
    final casos = lista.casos;

    void abrir(CasoResumen c) => context.go(Rutas.rescate(c.estudianteId));

    return RefreshIndicator(
      onRefresh: () => ref.refresh(casosProvider.future),
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
                    apariencia.buho(animo: AnimoBuho.atento),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Card.filled(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Estos estudiantes están en riesgo según el '
                            'modelo. Con ${lista.presupuesto} fichas de '
                            'intervención, ¿puedes bajar su riesgo estimado '
                            'de ${porcentaje(lista.objetivo)}?',
                            style: tema.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: casos.isEmpty
                      ? null
                      : () => abrir(casos[math.Random().nextInt(casos.length)]),
                  icon: const Icon(Icons.casino_outlined),
                  label: const Text('Caso al azar'),
                ),
                const SizedBox(height: 16),
                if (casos.isEmpty)
                  const VaciaVista(
                    mensaje: 'Ahora mismo no hay casos que rescatar.',
                    icono: Icons.verified_outlined,
                  )
                else
                  Text(
                    '${casos.length} casos, del más grave al más leve',
                    style: tema.textTheme.labelLarge,
                  ),
                for (final c in casos)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        '${c.nombre.characters.first}'
                        '${c.apellido.characters.first}',
                      ),
                    ),
                    title: Text(c.nombreCompleto),
                    subtitle: Text('${c.carrera} · ${c.semestre}.º semestre'),
                    trailing: _Riesgo(probabilidad: c.probabilidad),
                    onTap: () => abrir(c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Riesgo extends StatelessWidget {
  const _Riesgo({required this.probabilidad});

  final double probabilidad;

  @override
  Widget build(BuildContext context) {
    final estado = ColoresEstado.of(context);
    return Semantics(
      container: true,
      label: 'Riesgo estimado ${porcentaje(probabilidad)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: estado.riesgoContenedor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          porcentaje(probabilidad),
          style: TextStyle(
            color: estado.onRiesgoContenedor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
