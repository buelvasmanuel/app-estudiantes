import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../laboratorio/apariencia.dart';
import '../preferencias.dart';
import '../tema/temas.dart';
import '../theme.dart';

/// El tutorial del búho: la primera vez (por dispositivo), 4 pasos, se puede
/// saltar. En el último se elige el tema y si suenan los efectos.
class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  static const pasos = 4;

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  final _paginas = PageController();
  int _paso = 0;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  void _ir(int paso) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _paginas.jumpToPage(paso);
    } else {
      _paginas.animateToPage(
        paso,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Termina (o salta): se recuerda el tema que se ve ahora y no vuelve a
  /// salir. El router lleva a donde iba el jugador.
  void _terminar() {
    final tema = ref.read(temaProvider);
    ref.read(temaProvider.notifier).elegir(tema);
    ref.read(tutorialVistoProvider.notifier).marcar(true);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ultimo = _paso == TutorialScreen.pasos - 1;
    return Scaffold(
      body: CustomPaint(
        painter: PintorFondoCampus(
          EstiloJuego.of(context).fondoCampus,
          tema.colorScheme,
          conLuna: false, // ahí está "Saltar"
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _terminar,
                  child: const Text('Saltar'),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _paginas,
                  onPageChanged: (p) => setState(() => _paso = p),
                  children: const [
                    _Paso(
                      animo: AnimoBuho.atento,
                      titulo: '¡Hola, detective!',
                      texto:
                          'Soy el búho y te acompaño en el campus. Aquí los '
                          'datos son pistas: cada número cuenta una historia.',
                    ),
                    _Paso(
                      animo: AnimoBuho.pensando,
                      titulo: 'El campus',
                      texto:
                          'Cada edificio es una carrera y cada piso, un '
                          'semestre. Cada ventana es un estudiante: roja y '
                          'con una raya si está en riesgo, verde si no.',
                      extra: _LeyendaVentanas(),
                    ),
                    _Paso(
                      animo: AnimoBuho.contento,
                      titulo: 'Casos y rescates',
                      texto:
                          'Resuelve Casos mirando las gráficas y rescata '
                          'estudiantes en el Laboratorio. Así ganas XP, subes '
                          'de nivel y consigues insignias.',
                    ),
                    _Paso(
                      animo: AnimoBuho.atento,
                      titulo: 'Una última pista',
                      texto:
                          'El modelo estima, no adivina: muestra '
                          'correlaciones, no causas. Úsalo para hacerte '
                          'preguntas, no para sacar conclusiones.',
                      extra: _Eleccion(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Row(
                  children: [
                    Semantics(
                      container: true,
                      label: 'Paso ${_paso + 1} de ${TutorialScreen.pasos}',
                      excludeSemantics: true,
                      child: Row(
                        children: [
                          for (var i = 0; i < TutorialScreen.pasos; i++)
                            Container(
                              width: i == _paso ? 20 : 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: i == _paso
                                    ? tema.colorScheme.primary
                                    : tema.colorScheme.outline,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: ultimo ? _terminar : () => _ir(_paso + 1),
                      child: Text(ultimo ? '¡A investigar!' : 'Siguiente'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Paso extends ConsumerWidget {
  const _Paso({
    required this.animo,
    required this.titulo,
    required this.texto,
    this.extra,
  });

  final AnimoBuho animo;
  final String titulo;
  final String texto;
  final Widget? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    // Centrado en vertical si cabe; con texto grande, se desplaza.
    return LayoutBuilder(
      builder: (context, restricciones) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: restricciones.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ref
                      .watch(aparienciaLaboratorioProvider)
                      .buho(animo: animo, tamano: 120),
                  const SizedBox(height: 16),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: tema.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Card.filled(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(texto, style: tema.textTheme.bodyLarge),
                    ),
                  ),
                  if (extra case final e?) ...[const SizedBox(height: 20), e],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Las tres ventanas, como en el Campus.
class _LeyendaVentanas extends StatelessWidget {
  const _LeyendaVentanas();

  @override
  Widget build(BuildContext context) {
    final c = ColoresEstado.of(context);
    final esquema = Theme.of(context).colorScheme;
    Widget ventana(Color color, String texto, {bool raya = false}) => Column(
      children: [
        CustomPaint(
          size: const Size(28, 36),
          painter: _Ventana(color, raya ? c.onRiesgo : null, esquema.outline),
        ),
        const SizedBox(height: 6),
        Text(texto),
      ],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ventana(c.riesgo, 'En riesgo', raya: true),
        ventana(c.ok, 'Sin riesgo'),
        ventana(esquema.surfaceContainerHigh, 'Vacía'),
      ],
    );
  }
}

class _Ventana extends CustomPainter {
  _Ventana(this.color, this.raya, this.borde);

  final Color color;
  final Color? raya;
  final Color borde;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas
      ..drawRect(r, Paint()..color = color)
      ..drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = borde,
      );
    if (raya case final c?) {
      canvas.drawLine(
        r.bottomLeft + const Offset(5, -5),
        r.topRight + const Offset(-5, 5),
        Paint()
          ..color = c
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_Ventana old) =>
      old.color != color || old.raya != raya || old.borde != borde;
}

/// Último paso: tema (se aplica al instante, como vista previa) y sonidos.
class _Eleccion extends ConsumerWidget {
  const _Eleccion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elegido = ref.watch(temaProvider);
    final sonidos = ref.watch(sonidosActivosProvider);
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Elige tu estilo', style: tema.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final t in TemaJuego.values) ...[
              Expanded(
                child: _TarjetaTema(
                  tema: t,
                  elegido: t == elegido,
                  onTap: () => ref.read(temaProvider.notifier).elegir(t),
                ),
              ),
              if (t != TemaJuego.values.last) const SizedBox(width: 12),
            ],
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('tutorial-sonidos'),
          contentPadding: EdgeInsets.zero,
          title: const Text('¿Activar sonidos?'),
          subtitle: const Text('Puedes cambiarlo en tu Perfil'),
          value: sonidos,
          onChanged: ref.read(sonidosActivosProvider.notifier).activar,
        ),
      ],
    );
  }
}

/// Muestra de un tema con sus propios colores y letra.
class _TarjetaTema extends StatelessWidget {
  const _TarjetaTema({
    required this.tema,
    required this.elegido,
    required this.onTap,
  });

  final TemaJuego tema;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final propio = tema.datos;
    final c = propio.colorScheme;
    final estado = propio.extension<ColoresEstado>()!;
    final actual = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      button: true,
      selected: elegido,
      label: 'Tema ${tema.nombre}',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: elegido ? actual.primary : actual.outline,
            width: elegido ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('tutorial-tema-${tema.name}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  'Aa',
                  style: propio.textTheme.headlineMedium?.copyWith(
                    color: c.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final color in [c.primary, estado.ok, estado.riesgo])
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: color,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // Se reduce si no cabe (texto grande, pantalla estrecha).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tema.icono, size: 18, color: c.onSurface),
                      const SizedBox(width: 4),
                      Text(
                        tema.nombre,
                        style: propio.textTheme.titleSmall?.copyWith(
                          color: c.onSurface,
                        ),
                      ),
                      if (elegido) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check_circle, size: 18, color: c.primary),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
