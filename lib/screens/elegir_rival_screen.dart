import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../duelo/duelo_api.dart';
import '../duelo/modelo.dart';
import '../laboratorio/apariencia.dart';
import '../router.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/menu_cuenta.dart';
import 'duelo_screen.dart';
import '../widgets/titulo_barra.dart';

/// Entrada al duelo: contra el Búho Máquina o contra otro detective. Cada
/// modo tiene su propio límite de 3 duelos con XP al día (CONTRATO_DUELO
/// §3 y §7.4), así que cada tarjeta enseña el suyo.
class ElegirRivalScreen extends ConsumerWidget {
  const ElegirRivalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    // Si la API aún no manda `xp_hoy`, se enseña solo la XP de cada
    // resultado.
    final xpHoy = ref.watch(xpHoyDuelosProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: const TituloBarra('Duelo'),
        actions: const [MenuCuenta()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AnchoMaximo(
            ancho: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('¿Contra quién?', style: tema.textTheme.headlineSmall),
                const SizedBox(height: 12),
                _Opcion(
                  key: const Key('elegir-maquina'),
                  icono: Icons.smart_toy_outlined,
                  titulo: 'Búho Máquina',
                  texto: 'Siempre está. Juega su atributo con mejor percentil.',
                  xp: _xp(xpHoy[ModoDuelo.maquina], (30, 15, 5)),
                  onTap: () => context.go(Rutas.dueloMaquina),
                ),
                _Opcion(
                  key: const Key('elegir-jugador'),
                  icono: Icons.groups_outlined,
                  titulo: 'Otro detective',
                  texto:
                      'Te emparejamos con quien esté buscando. 45 s por turno.',
                  xp: _xp(xpHoy[ModoDuelo.jugador], (40, 20, 10)),
                  onTap: () => context.go(Rutas.dueloJugador),
                ),
                const SizedBox(height: 8),
                const BurbujaBuho(
                  animo: AnimoBuho.atento,
                  texto:
                      'Contra otro detective no hay patrón fijo: puede elegir '
                      'cualquier atributo. Y si se acaba tu turno, la ronda '
                      'es suya.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _xp(XpHoy? hoy, (int, int, int) xp) {
    final reglas = 'victoria ${xp.$1} · empate ${xp.$2} · derrota ${xp.$3}';
    return hoy == null
        ? 'XP: $reglas'
        : 'XP hoy: ${hoy.jugados} de ${hoy.maximo} duelos · $reglas';
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    super.key,
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.xp,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String texto;
  final String xp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tema.colorScheme.outline),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Icon(icono, size: 36, color: tema.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: tema.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(texto),
                    const SizedBox(height: 6),
                    Text(
                      xp,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
