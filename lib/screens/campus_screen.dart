import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../campus/controlador.dart';
import '../campus/juego.dart';
import '../campus/modelo.dart';
import '../tema/temas.dart';
import '../models/estadistica.dart';
import '../models/estudiante.dart';
import '../providers.dart';
import '../router.dart';
import '../theme.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/grafica_barras.dart';
import '../widgets/menu_cuenta.dart';
import '../widgets/promedio_badge.dart';
import '../formato.dart';

/// Pestaña "Campus": cada edificio es una carrera, cada piso un semestre y
/// cada ventana un estudiante (roja si está en riesgo).
class CampusScreen extends ConsumerWidget {
  const CampusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(estudiantesProvider);
    return switch (estado) {
      // ObjectKey: si la lista se recarga, el campus se rehace desde cero.
      AsyncValue(value: final List<Estudiante> lista) when lista.isNotEmpty =>
        CampusVista(key: ObjectKey(lista), estudiantes: lista),
      AsyncValue(hasValue: true) => const _Marco(
        cuerpo: VaciaVista(
          mensaje: 'No hay estudiantes: el campus está vacío.',
          icono: Icons.location_city_outlined,
        ),
      ),
      AsyncValue(:final error?) => _Marco(
        cuerpo: ErrorVista(
          error: error,
          onReintentar: () => ref.invalidate(estudiantesProvider),
        ),
      ),
      _ => _Marco(
        cuerpo: CargandoVista(
          mensaje: 'Construyendo el campus…',
          despertando: ref.watch(apiServiceProvider).despertando,
        ),
      ),
    };
  }
}

class _Marco extends StatelessWidget {
  const _Marco({required this.cuerpo});

  final Widget cuerpo;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Campus'), actions: const [MenuCuenta()]),
    body: cuerpo,
  );
}

/// El campus con datos. Público para poder probarlo sin el router.
class CampusVista extends StatefulWidget {
  const CampusVista({super.key, required this.estudiantes});

  final List<Estudiante> estudiantes;

  @override
  State<CampusVista> createState() => CampusVistaState();
}

class CampusVistaState extends State<CampusVista> {
  late final ControladorCampus controlador = ControladorCampus(
    Campus.desde(widget.estudiantes),
  );
  CampusJuego? _juego;
  double _zoomAlEmpezar = 1;

  CampusJuego get juego => _juego!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paleta = PaletaCampus.de(Theme.of(context));
    final juego = _juego ??= CampusJuego(controlador, paleta);
    juego.paleta = paleta;
    controlador.reducirMovimiento = MediaQuery.disableAnimationsOf(context);
    // Pestaña oculta (go_router la deja montada): el juego deja de dibujar.
    if (TickerMode.valuesOf(context).enabled) {
      juego.resumeEngine();
    } else {
      juego.pauseEngine();
    }
  }

  @override
  void dispose() {
    controlador.dispose();
    super.dispose();
  }

  Duration get _transicion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus'),
        actions: [
          _Buscador(
            estudiantes: widget.estudiantes,
            onElegido: controlador.seleccionarEstudiante,
          ),
          const MenuCuenta(),
        ],
      ),
      body: ListenableBuilder(
        listenable: controlador,
        builder: (context, _) => Column(
          children: [
            _Leyenda(campus: controlador.campus),
            Expanded(child: _lienzo()),
            _ListaEdificios(controlador: controlador),
            _Controles(controlador: controlador),
            AnimatedSwitcher(
              duration: _transicion,
              transitionBuilder: (hijo, animacion) => SizeTransition(
                sizeFactor: animacion,
                alignment: Alignment.topCenter,
                child: FadeTransition(opacity: animacion, child: hijo),
              ),
              child: switch ((
                controlador.estudianteSeleccionado,
                controlador.edificioSeleccionado,
              )) {
                (final Estudiante e, _) => _FichaEstudiante(
                  key: ValueKey('estudiante-${e.id}'),
                  estudiante: e,
                  onCerrar: controlador.cerrarSeleccion,
                ),
                (null, final Edificio e) => _Expediente(
                  key: ValueKey('edificio-${e.carrera}'),
                  edificio: e,
                  onCerrar: controlador.cerrarSeleccion,
                ),
                _ => const SizedBox(width: double.infinity),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _lienzo() {
    final campus = controlador.campus;
    return LayoutBuilder(
      builder: (context, restricciones) {
        controlador.ajustarA(restricciones.biggest);
        return Listener(
          // Rueda del ratón (escritorio y web): zoom por pasos.
          onPointerSignal: (evento) {
            if (evento is PointerScrollEvent) {
              evento.scrollDelta.dy < 0
                  ? controlador.acercar(evento.localPosition)
                  : controlador.alejar(evento.localPosition);
            }
          },
          child: GestureDetector(
            key: const Key('lienzo-campus'),
            onTapUp: (d) => controlador.tocar(d.localPosition),
            onScaleStart: (_) => _zoomAlEmpezar = controlador.vista.zoom,
            onScaleUpdate: (d) {
              if (d.pointerCount > 1) {
                controlador.zoomA(_zoomAlEmpezar * d.scale, d.localFocalPoint);
              }
              controlador.desplazar(d.focalPointDelta);
            },
            child: Semantics(
              container: true,
              label:
                  'Mapa del campus: ${campus.edificios.length} edificios, '
                  '${campus.total} estudiantes, ${campus.enRiesgo} en riesgo. '
                  'Los edificios se pueden elegir en la lista de abajo.',
              child: ClipRect(
                child: CustomPaint(
                  painter: PintorFondoCampus(
                    EstiloJuego.of(context).fondoCampus,
                    Theme.of(context).colorScheme,
                  ),
                  child: GameWidget(game: juego),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Qué significa cada ventana. Texto quieto, cifras reales.
class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.campus});

  final Campus campus;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = ColoresEstado.of(context);
    final paleta = PaletaCampus.de(tema);
    final estilo = tema.textTheme.labelMedium;
    Widget muestra(Color color, {Color? raya}) =>
        _MuestraVentana(color: color, raya: raya, borde: paleta.bordeMuestra);
    Widget item(Widget muestra, String texto) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        muestra,
        const SizedBox(width: 6),
        Text(texto, style: estilo),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          item(
            muestra(colores.riesgo, raya: colores.onRiesgo),
            'En riesgo ${campus.enRiesgo}',
          ),
          item(
            muestra(colores.ok),
            'Sin riesgo ${campus.total - campus.enRiesgo}',
          ),
          // El mismo color que las ventanas vacías del mapa.
          item(muestra(paleta.vacia), 'Vacía'),
        ],
      ),
    );
  }
}

/// Una ventana de muestra para la leyenda (igual que en el mapa).
class _MuestraVentana extends StatelessWidget {
  const _MuestraVentana({required this.color, required this.borde, this.raya});

  final Color color;
  final Color borde;
  final Color? raya;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(11, 14),
    painter: _PintorMuestra(color, raya, borde),
  );
}

class _PintorMuestra extends CustomPainter {
  _PintorMuestra(this.color, this.raya, this.borde);

  final Color color;
  final Color? raya;
  final Color borde;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas
      ..drawRect(r, Paint()..color = color)
      ..drawRect(
        r.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = borde,
      );
    if (raya case final c?) {
      canvas.drawLine(
        r.bottomLeft + const Offset(2, -2),
        r.topRight + const Offset(-2, 2),
        Paint()
          ..color = c
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorMuestra old) =>
      old.color != color || old.raya != raya || old.borde != borde;
}

/// Los edificios como lista: accesible para lectores de pantalla y teclado
/// (el lienzo de Flame no lo es) y atajo para encuadrar uno.
class _ListaEdificios extends StatelessWidget {
  const _ListaEdificios({required this.controlador});

  final ControladorCampus controlador;

  @override
  Widget build(BuildContext context) {
    final seleccionado = controlador.edificioSeleccionado;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: controlador.campus.edificios.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = controlador.campus.edificios[i];
          return Semantics(
            container: true,
            label:
                '${e.carrera}: ${e.total} estudiantes, '
                '${e.enRiesgo} en riesgo',
            excludeSemantics: true,
            selected: e == seleccionado,
            button: true,
            child: ChoiceChip(
              label: Text('${e.carrera} · ${e.enRiesgo}/${e.total}'),
              selected: e == seleccionado,
              onSelected: (_) => controlador.seleccionarEdificio(e),
            ),
          );
        },
      ),
    );
  }
}

class _Controles extends StatelessWidget {
  const _Controles({required this.controlador});

  final ControladorCampus controlador;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('Solo en riesgo'),
            selected: controlador.soloRiesgo,
            onSelected: (_) => controlador.alternarSoloRiesgo(),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Alejar',
            onPressed: controlador.alejar,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            tooltip: 'Acercar',
            onPressed: controlador.acercar,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Ver todo el campus',
            onPressed: controlador.encuadrarTodo,
            icon: const Icon(Icons.fit_screen_outlined),
          ),
        ],
      ),
    );
  }
}

/// Panel inferior con fondo y botón de cerrar.
class _Panel extends StatelessWidget {
  const _Panel({required this.onCerrar, required this.children});

  final VoidCallback onCerrar;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Material(
      color: colores.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Cerrar',
                onPressed: onCerrar,
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El "expediente" de una carrera, con las cifras de su edificio.
class _Expediente extends StatelessWidget {
  const _Expediente({
    super.key,
    required this.edificio,
    required this.onCerrar,
  });

  final Edificio edificio;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final e = edificio;
    return _Panel(
      onCerrar: onCerrar,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 36),
          child: Row(
            children: [
              Icon(Icons.folder_open_outlined, color: tema.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(e.carrera, style: tema.textTheme.titleMedium),
              ),
              Text(
                e.total == 1 ? '1 estudiante' : '${e.total} estudiantes',
                style: tema.textTheme.labelLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'En riesgo: ${e.enRiesgo} (${formatoPorcentaje(e.porcentajeRiesgo)})'
          ' · Promedio medio: ${formatoPromedio(e.promedioMedio)}',
          style: tema.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text('Estudiantes por semestre', style: tema.textTheme.labelMedium),
        SizedBox(
          height: 140,
          child: GraficaBarras(
            datos: [
              for (final (i, n) in e.porSemestre.indexed)
                Estadistica(etiqueta: '${i + 1}', valor: n),
            ],
            tipo: TipoEstadistica.porSemestre,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => context.go(
                Uri(
                  path: Rutas.estudiantes,
                  queryParameters: {'carrera': e.carrera},
                ).toString(),
              ),
              icon: const Icon(Icons.people_outline),
              label: const Text('Ver estudiantes'),
            ),
            TextButton.icon(
              onPressed: () => context.go(Rutas.graficas),
              icon: const Icon(Icons.bar_chart_outlined),
              label: const Text('Ver gráficas'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Ficha breve del estudiante de una ventana.
class _FichaEstudiante extends StatelessWidget {
  const _FichaEstudiante({
    super.key,
    required this.estudiante,
    required this.onCerrar,
  });

  final Estudiante estudiante;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final e = estudiante;
    final colores = ColoresEstado.of(context);
    return _Panel(
      onCerrar: onCerrar,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 36),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: EstudianteAvatar(estudiante: e),
            title: Text(e.nombreCompleto),
            subtitle: Text('${e.carrera} · ${e.semestre}.º semestre'),
            trailing: PromedioBadge(estudiante: e),
          ),
        ),
        Row(
          children: [
            Icon(
              e.enRiesgo ? Icons.warning_amber_rounded : Icons.check_circle,
              size: 18,
              color: e.enRiesgo ? colores.riesgo : colores.ok,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                e.enRiesgo ? 'En riesgo académico' : 'Sin riesgo académico',
              ),
            ),
            FilledButton.tonal(
              onPressed: () => context.push(Rutas.estudiante(e.id), extra: e),
              child: const Text('Ver ficha'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Lupa de la barra superior: busca un estudiante y lo señala en el mapa.
class _Buscador extends StatelessWidget {
  const _Buscador({required this.estudiantes, required this.onElegido});

  final List<Estudiante> estudiantes;
  final ValueChanged<Estudiante> onElegido;

  @override
  Widget build(BuildContext context) {
    return SearchAnchor(
      viewHintText: 'Buscar estudiante, carrera o ciudad',
      builder: (context, controlador) => IconButton(
        tooltip: 'Buscar estudiante',
        onPressed: controlador.openView,
        icon: const Icon(Icons.search),
      ),
      suggestionsBuilder: (context, controlador) {
        final consulta = normalizar(controlador.text.trim());
        if (consulta.isEmpty) return const <Widget>[];
        return [
          for (final e
              in estudiantes
                  .where((e) => e.textoBusqueda.contains(consulta))
                  .take(30))
            ListTile(
              leading: EstudianteAvatar(estudiante: e),
              title: Text(e.nombreCompleto),
              subtitle: Text('${e.carrera} · ${e.semestre}.º semestre'),
              trailing: PromedioBadge(estudiante: e),
              onTap: () {
                controlador.closeView(null);
                onElegido(e);
              },
            ),
        ];
      },
    );
  }
}
