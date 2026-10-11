import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../juego/celebracion.dart';
import '../juego/juego_api.dart';
import '../tema/temas.dart';
import '../juego/modelo.dart';
import '../laboratorio/apariencia.dart';
import '../models/estadistica.dart';
import '../providers.dart';
import '../router.dart';
import '../services/api_service.dart';
import '../sonidos.dart';
import '../theme.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/menu_cuenta.dart';
import '../widgets/grafica_barras.dart';

/// Un caso: enunciado, ficha (gráfica), opciones y lo que dice el servidor.
class CasoJuegoScreen extends ConsumerStatefulWidget {
  const CasoJuegoScreen({super.key, required this.codigo});

  final String codigo;

  @override
  ConsumerState<CasoJuegoScreen> createState() => _CasoJuegoScreenState();
}

class _CasoJuegoScreenState extends ConsumerState<CasoJuegoScreen> {
  String? _elegida;
  bool _enviando = false;
  RespuestaCaso? _respuesta;
  String? _respondida; // la opción a la que corresponde _respuesta
  ApiException? _error;

  Future<void> _responder() async {
    final elegida = _elegida;
    if (elegida == null || _enviando) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(juegoApiProvider)
          .responder(widget.codigo, elegida);
      if (!mounted) return;
      setState(() {
        _respuesta = r;
        _respondida = elegida;
      });
      ref
          .read(sonidosProvider)
          .tocar(r.correcto ? Sonido.acierto : Sonido.pista);
      progresoCambiado(ref);
      ref.invalidate(casoJuegoProvider(widget.codigo));
      await celebrar(context, r.recompensa);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      // Las opciones cambiaron con los datos: se vuelven a pedir.
      if (e.codigo == 'respuesta_invalida') {
        ref.invalidate(casoJuegoProvider(widget.codigo));
        setState(() => _elegida = null);
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(casoJuegoProvider(widget.codigo));
    return Scaffold(
      appBar: AppBar(title: const Text('Caso'), actions: const [MenuCuenta()]),
      body: switch (estado) {
        // skipLoadingOnRefresh: tras responder se recarga sin parpadear.
        AsyncValue(value: final CasoJuego caso) => _contenido(caso),
        AsyncValue(:final error?) => ErrorVista(
          error: error,
          onReintentar: () => ref.invalidate(casoJuegoProvider(widget.codigo)),
        ),
        _ => CargandoVista(
          mensaje: 'Abriendo el caso…',
          despertando: ref.watch(apiServiceProvider).despertando,
        ),
      },
    );
  }

  Widget _contenido(CasoJuego caso) {
    final tema = Theme.of(context);
    final respuesta = _respuesta;
    final acertado = respuesta?.correcto ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AnchoMaximo(
          ancho: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(caso.titulo, style: tema.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  Chip(
                    label: Text(caso.nivel.nombre),
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    avatar: const Icon(Icons.bolt, size: 18),
                    label: Text('${caso.xp} XP'),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (caso.resuelto)
                    Chip(
                      avatar: Icon(
                        Icons.check_circle,
                        size: 18,
                        color: ColoresEstado.of(context).ok,
                      ),
                      label: const Text('Resuelto'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(caso.enunciado, style: tema.textTheme.titleMedium),
              if (_tipoDeGrafica(caso.grafica) case final tipo?) ...[
                const SizedBox(height: 12),
                _Ficha(tipo: tipo),
              ],
              const SizedBox(height: 16),
              Text('Tu respuesta', style: tema.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in caso.opciones)
                    OpcionCaso(
                      key: Key('opcion-${o.valor}'),
                      texto: o.texto,
                      elegida: _elegida == o.valor,
                      // Ya acertado: se ve cuál era, pero no se cambia.
                      onTap: acertado
                          ? null
                          : () => setState(() => _elegida = o.valor),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (!acertado)
                FilledButton.icon(
                  onPressed: _elegida == null || _enviando ? null : _responder,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: _enviando
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    respuesta == null ? 'Responder' : 'Probar con esta',
                  ),
                ),
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                Text(
                  error.mensaje,
                  style: TextStyle(color: tema.colorScheme.error),
                ),
              ],
              if (respuesta != null) ...[
                const SizedBox(height: 16),
                _Veredicto(
                  respuesta: respuesta,
                  opcion: caso.opciones
                      .where((o) => o.valor == _respondida)
                      .firstOrNull
                      ?.texto,
                  yaResuelto:
                      caso.resuelto && respuesta.recompensa.xpGanada == 0,
                ),
              ],
              if (acertado) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context.go(Rutas.casos),
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Volver a los casos'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// `/estudiantes/estadisticas/riesgo-por-carrera` → la estadística.
  static TipoEstadistica? _tipoDeGrafica(String? ruta) {
    if (ruta == null) return null;
    final ultima = ruta.split('/').last;
    return TipoEstadistica.values.where((t) => t.ruta == ultima).firstOrNull;
  }
}

/// La gráfica que ayuda a resolver el caso (la de la pestaña Gráficas).
class _Ficha extends ConsumerWidget {
  const _Ficha({required this.tipo});

  final TipoEstadistica tipo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final estado = ref.watch(estadisticaProvider(tipo));
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  color: tema.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ficha del caso: ${tipo.nombre}',
                    style: tema.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: switch (estado) {
                AsyncValue(value: final List<Estadistica> d)
                    when d.isNotEmpty =>
                  GraficaBarras(datos: d, tipo: tipo),
                AsyncValue(:final error?) => ErrorVista(
                  error: error,
                  onReintentar: () => ref.invalidate(estadisticaProvider(tipo)),
                ),
                AsyncValue(hasValue: true) => const VaciaVista(
                  mensaje: 'Sin datos.',
                  icono: Icons.bar_chart_outlined,
                ),
                _ => const CargandoVista(mensaje: 'Cargando la ficha…'),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que decidió el servidor: correcto o no, el dato real de la opción y
/// la explicación (acierto) o la pista (fallo), dichas por el búho.
class _Veredicto extends ConsumerWidget {
  const _Veredicto({
    required this.respuesta,
    required this.opcion,
    required this.yaResuelto,
  });

  final RespuestaCaso respuesta;
  final String? opcion;
  final bool yaResuelto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final estado = ColoresEstado.of(context);
    final r = respuesta;
    final apariencia = ref.watch(aparienciaLaboratorioProvider);
    final xp = r.recompensa.xpGanada;
    final sellos = EstiloJuego.of(context).sellos;
    final tarjeta = Card.filled(
      color: r.correcto ? estado.okContenedor : estado.riesgoContenedor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // El sello va junto al título, en el mismo Wrap: si no caben en
            // una línea (pantallas estrechas), el sello baja; nunca lo tapa.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  r.correcto
                      ? '¡Correcto!${xp > 0 ? ' +$xp XP' : ''}'
                      : 'No es ${opcion ?? 'esa'}',
                  key: const Key('veredicto'),
                  style: tema.textTheme.titleLarge?.copyWith(
                    color: r.correcto
                        ? estado.onOkContenedor
                        : estado.onRiesgoContenedor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sellos && r.correcto)
                  // Margen para el giro del sello: girado ocupa más alto que
                  // su caja, y así nunca invade el título.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 6,
                    ),
                    child: Sello(
                      key: const Key('sello'),
                      texto: 'RESUELTO',
                      color: estado.ok,
                    ),
                  ),
              ],
            ),
            if (r.dato case final dato?) ...[
              const SizedBox(height: 4),
              Text(
                dato,
                style: TextStyle(
                  color: r.correcto
                      ? estado.onOkContenedor
                      : estado.onRiesgoContenedor,
                ),
              ),
            ],
            if (r.correcto && yaResuelto) ...[
              const SizedBox(height: 4),
              Text(
                'Ya lo habías resuelto: esta vez no suma XP.',
                style: TextStyle(color: estado.onOkContenedor),
              ),
            ],
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tarjeta,
        if (r.explicacion ?? r.pista case final texto?) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              apariencia.buho(
                animo: r.correcto ? AnimoBuho.contento : AnimoBuho.pensando,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      r.correcto ? texto : 'Pista: $texto',
                      key: const Key('frase-buho'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Una opción de respuesta. La elegida se distingue en los dos temas por
/// algo más que el color: borde grueso del color primario, ✓ y negrita.
/// Sigue viéndose así cuando el caso ya está resuelto (no se "apaga").
class OpcionCaso extends StatelessWidget {
  const OpcionCaso({
    super.key,
    required this.texto,
    required this.elegida,
    required this.onTap,
  });

  final String texto;
  final bool elegida;

  /// `null`: no se puede cambiar (caso ya acertado).
  final VoidCallback? onTap;

  static const grosorElegida = 2.0;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final borde = elegida
        ? BorderSide(color: c.primary, width: grosorElegida)
        : BorderSide(color: c.outline);
    final estilo = TextStyle(
      color: elegida ? c.onPrimaryContainer : c.onSurface,
      fontWeight: elegida ? FontWeight.w700 : FontWeight.w400,
    );
    final icono = elegida
        ? Icon(Icons.check, size: 18, color: c.onPrimaryContainer)
        : null;
    final fondo = elegida ? c.primaryContainer : c.surface;
    final chip = onTap == null
        ? Chip(
            avatar: icono,
            label: Text(texto),
            labelStyle: estilo,
            backgroundColor: fondo,
            side: borde,
          )
        : ChoiceChip(
            label: Text(texto),
            labelStyle: estilo,
            selected: elegida,
            showCheckmark: true,
            checkmarkColor: c.onPrimaryContainer,
            selectedColor: fondo,
            backgroundColor: fondo,
            side: borde,
            onSelected: (_) => onTap!(),
          );
    return Semantics(selected: elegida, child: chip);
  }
}
