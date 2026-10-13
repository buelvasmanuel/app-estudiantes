import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../juego/juego_api.dart';
import '../juego/modelo.dart';
import '../models/sesion.dart';
import '../preferencias.dart';
import '../providers.dart';
import '../router.dart';
import 'casos_screen.dart';
import 'mis_passkeys.dart';
import '../tema/temas.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/menu_cuenta.dart';
import '../formato.dart';

/// Pestaña "Perfil": el detective (nivel, cifras, insignias) y el ranking.
class PerfilScreen extends ConsumerWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Perfil'),
          actions: const [MenuCuenta()],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Detective'),
              Tab(text: 'Ranking'),
            ],
          ),
        ),
        body: const TabBarView(children: [_Detective(), _RankingVista()]),
      ),
    );
  }
}

class _Detective extends ConsumerWidget {
  const _Detective();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(progresoProvider);
    return switch (estado) {
      AsyncValue(value: final Progreso p) => RefreshIndicator(
        onRefresh: () => ref.refresh(progresoProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            AnchoMaximo(
              ancho: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Cabecera(progreso: p),
                  const SizedBox(height: 16),
                  _Cifras(progreso: p),
                  const SizedBox(height: 16),
                  const TarjetaDuelo(),
                  const SizedBox(height: 24),
                  _Insignias(insignias: p.insignias),
                  const SizedBox(height: 24),
                  const AjustesJuego(),
                  // Solo en la web (dentro decide si mostrarse).
                  const MisPasskeys(),
                  if (_esDocente(ref)) ...[
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => context.push(Rutas.docente),
                      icon: const Icon(Icons.co_present_outlined),
                      label: const Text('Panel del docente'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      AsyncValue(:final error?) => ErrorVista(
        error: error,
        onReintentar: () => ref.invalidate(progresoProvider),
      ),
      _ => CargandoVista(
        mensaje: 'Abriendo tu expediente…',
        despertando: ref.watch(apiServiceProvider).despertando,
      ),
    };
  }

  static bool _esDocente(WidgetRef ref) {
    ref.watch(usuarioIdProvider);
    final rol = ref.read(sesionProvider).usuario?.rol;
    return rol == Rol.docente || rol == Rol.admin;
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.progreso});

  final Progreso progreso;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final p = progreso;
    final siguiente = p.siguienteNivel;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(
                    p.alias.characters.first.toUpperCase(),
                    style: tema.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Un alias largo se reduce en vez de partirse a mitad.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(p.alias, style: tema.textTheme.titleLarge),
                      ),
                      Text(
                        'Nivel ${p.nivel.numero} · ${p.nivel.nombre}',
                        style: tema.textTheme.titleSmall?.copyWith(
                          color: tema.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${formatoEntero(p.xp)} XP',
                  key: const Key('xp-perfil'),
                  style: tema.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Semantics(
              container: true,
              label: siguiente == null
                  ? 'Nivel máximo alcanzado'
                  : 'Te faltan ${formatoEntero(siguiente.xpDesde - p.xp)} XP para '
                        '${siguiente.nombre}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: p.avanceNivel,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    siguiente == null
                        ? '¡Nivel máximo! Eres ${p.nivel.nombre}.'
                        : '${formatoEntero(p.xp)} / ${formatoEntero(siguiente.xpDesde)} XP · te faltan '
                              '${formatoEntero(siguiente.xpDesde - p.xp)} para '
                              '${siguiente.nombre}',
                    style: tema.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cifras extends StatelessWidget {
  const _Cifras({required this.progreso});

  final Progreso progreso;

  @override
  Widget build(BuildContext context) {
    final p = progreso;
    final cifras = [
      (
        Icons.local_fire_department_outlined,
        '${p.rachaDias}',
        p.rachaDias == 1 ? 'día de racha' : 'días de racha',
      ),
      (Icons.search, '${p.casosResueltos}/${p.casosTotal}', 'casos resueltos'),
      (
        Icons.health_and_safety_outlined,
        '${p.rescatesLogrados}',
        p.rescatesLogrados == 1 ? 'rescate' : 'rescates',
      ),
      (
        Icons.star_outline_rounded,
        '${p.estrellasTotales}',
        p.estrellasTotales == 1 ? 'estrella' : 'estrellas',
      ),
    ];
    return LayoutBuilder(
      builder: (context, restricciones) {
        final columnas = restricciones.maxWidth >= 520 ? 4 : 2;
        const separacion = 12.0;
        final ancho =
            (restricciones.maxWidth - separacion * (columnas - 1)) / columnas;
        return Wrap(
          spacing: separacion,
          runSpacing: separacion,
          children: [
            for (final (icono, valor, texto) in cifras)
              SizedBox(
                width: ancho,
                child: Semantics(
                  container: true,
                  label: '$valor $texto',
                  excludeSemantics: true,
                  child: Card.outlined(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(icono),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  valor,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  texto,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Insignias extends StatelessWidget {
  const _Insignias({required this.insignias});

  final List<Insignia> insignias;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final obtenidas = insignias.where((i) => i.obtenida).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Insignias · $obtenidas de ${insignias.length}',
          style: tema.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final i in insignias)
          Semantics(
            container: true,
            label:
                '${i.nombre}: ${i.descripcion} '
                '${i.obtenida ? 'Obtenida.' : 'Aún no la tienes.'}',
            excludeSemantics: true,
            child: Opacity(
              opacity: i.obtenida ? 1 : 0.55,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: i.obtenida
                      ? tema.colorScheme.tertiaryContainer
                      : tema.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    i.obtenida
                        ? Icons.military_tech_rounded
                        : Icons.lock_outline,
                    color: i.obtenida
                        ? tema.colorScheme.onTertiaryContainer
                        : tema.colorScheme.onSurfaceVariant,
                  ),
                ),
                title: Text(i.nombre),
                subtitle: Text(
                  i.obtenida
                      ? '${i.descripcion} · ${_fecha(i.obtenidaEn!)}'
                      : i.descripcion,
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _RankingVista extends ConsumerStatefulWidget {
  const _RankingVista();

  @override
  ConsumerState<_RankingVista> createState() => _RankingVistaState();
}

class _RankingVistaState extends ConsumerState<_RankingVista> {
  PeriodoRanking _periodo = PeriodoRanking.semana;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estado = ref.watch(rankingProvider(_periodo));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        AnchoMaximo(
          ancho: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<PeriodoRanking>(
                segments: [
                  for (final p in PeriodoRanking.values)
                    ButtonSegment(value: p, label: Text(p.nombre)),
                ],
                selected: {_periodo},
                onSelectionChanged: (s) => setState(() => _periodo = s.first),
              ),
              const SizedBox(height: 8),
              Text(
                _periodo == PeriodoRanking.semana
                    ? 'XP ganada desde el lunes. Solo se muestra el alias.'
                    : 'Toda la XP. Solo se muestra el alias.',
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              switch (estado) {
                AsyncValue(value: final Ranking r) => _Tabla(ranking: r),
                AsyncValue(:final error?) => SizedBox(
                  height: 300,
                  child: ErrorVista(
                    error: error,
                    onReintentar: () =>
                        ref.invalidate(rankingProvider(_periodo)),
                  ),
                ),
                _ => const SizedBox(
                  height: 300,
                  child: CargandoVista(mensaje: 'Cargando el ranking…'),
                ),
              },
            ],
          ),
        ),
      ],
    );
  }
}

class _Tabla extends StatelessWidget {
  const _Tabla({required this.ranking});

  final Ranking ranking;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final r = ranking;
    if (r.jugadores.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 32),
        child: VaciaVista(
          mensaje: 'Nadie ha sumado XP en este periodo todavía.',
          icono: Icons.emoji_events_outlined,
        ),
      );
    }
    final estoyEnLaLista = r.jugadores.any((p) => p.soyYo);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in r.jugadores)
          Card.filled(
            color: p.soyYo
                ? tema.colorScheme.primaryContainer
                : Colors.transparent,
            margin: const EdgeInsets.symmetric(vertical: 2),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: p.posicion <= 3
                    ? tema.colorScheme.tertiaryContainer
                    : tema.colorScheme.surfaceContainerHighest,
                child: Text('${p.posicion}'),
              ),
              title: Text(p.soyYo ? '${p.alias} (tú)' : p.alias),
              subtitle: Text(p.nivel),
              trailing: Text(
                '${formatoEntero(p.xp)} XP',
                style: tema.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (!estoyEnLaLista && r.miPosicion != null) ...[
          const Divider(height: 24),
          Text(
            'Tu posición: ${r.miPosicion}.º con ${formatoEntero(r.miXp ?? 0)} XP',
            textAlign: TextAlign.center,
            style: tema.textTheme.titleSmall,
          ),
        ],
        if (r.miPosicion == null) ...[
          const SizedBox(height: 12),
          Text(
            'Aún no apareces: juega un caso o un rescate para sumar XP.',
            textAlign: TextAlign.center,
            style: tema.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// Tema, sonidos y tutorial. Se guardan en el dispositivo.
class AjustesJuego extends ConsumerWidget {
  const AjustesJuego({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = ref.watch(temaProvider);
    final sonidos = ref.watch(sonidosActivosProvider);
    final estilo = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ajustes', style: estilo.titleMedium),
        const SizedBox(height: 12),
        Text('Tema', style: estilo.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<TemaJuego>(
          key: const Key('selector-tema'),
          segments: [
            for (final t in TemaJuego.values)
              ButtonSegment(
                value: t,
                icon: Icon(t.icono),
                label: Text(t.nombre),
              ),
          ],
          selected: {tema},
          onSelectionChanged: (s) =>
              ref.read(temaProvider.notifier).elegir(s.first),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('interruptor-sonidos'),
          contentPadding: EdgeInsets.zero,
          secondary: Icon(sonidos ? Icons.volume_up : Icons.volume_off),
          title: const Text('Sonidos'),
          subtitle: const Text('Efectos cortos al acertar, rescatar o ganar'),
          value: sonidos,
          onChanged: ref.read(sonidosActivosProvider.notifier).activar,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.school_outlined),
          title: const Text('Ver el tutorial otra vez'),
          onTap: () => ref.read(tutorialVistoProvider.notifier).marcar(false),
        ),
      ],
    );
  }
}
