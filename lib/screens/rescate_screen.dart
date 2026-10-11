import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../juego/celebracion.dart';
import '../juego/juego_api.dart';
import '../juego/modelo.dart';
import '../laboratorio/apariencia.dart';
import '../laboratorio/explicacion_vista.dart';
import '../laboratorio/modelo.dart';
import '../laboratorio/providers.dart';
import '../laboratorio/rescate.dart';
import '../laboratorio/textos.dart';
import '../providers.dart';
import '../router.dart';
import '../services/api_service.dart';
import '../sonidos.dart';
import '../theme.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/menu_cuenta.dart';
import '../formato.dart';

/// Un caso del Laboratorio: aplicar fichas, ver el medidor y confirmar.
class RescateScreen extends ConsumerStatefulWidget {
  const RescateScreen({super.key, required this.estudianteId});

  final int estudianteId;

  @override
  ConsumerState<RescateScreen> createState() => _RescateScreenState();
}

class _RescateScreenState extends ConsumerState<RescateScreen> {
  Rescate? _rescate;
  ResultadoRescate? _resultado;
  bool _resolviendo = false;
  ApiException? _errorResolver;

  Future<void> _confirmar(Rescate rescate) async {
    setState(() {
      _resolviendo = true;
      _errorResolver = null;
    });
    try {
      final r = await ref
          .read(laboratorioApiProvider)
          .resolver(widget.estudianteId, rescate.codigos);
      if (!mounted) return;
      setState(() => _resultado = r);
      if (r.logrado) ref.read(sonidosProvider).tocar(Sonido.rescate);
      if (r.recompensa case final recompensa?) {
        progresoCambiado(ref);
        await celebrar(context, recompensa);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorResolver = e);
    } finally {
      if (mounted) setState(() => _resolviendo = false);
    }
  }

  void _otraVez() => setState(() {
    _rescate = _rescate?.reiniciar();
    _resultado = null;
  });

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(casoProvider(widget.estudianteId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rescate'),
        actions: const [MenuCuenta()],
      ),
      body: switch (estado) {
        AsyncValue(value: final Caso caso) => switch (_resultado) {
          final r? => _VistaResultado(
            caso: caso,
            resultado: r,
            onOtraVez: _otraVez,
          ),
          null => _juego(caso),
        },
        AsyncValue(:final error?) => ErrorVista(
          error: error,
          onReintentar: () => ref.invalidate(casoProvider(widget.estudianteId)),
        ),
        _ => CargandoVista(
          mensaje: 'Abriendo el caso…',
          despertando: ref.watch(apiServiceProvider).despertando,
        ),
      },
    );
  }

  Widget _juego(Caso caso) {
    final tema = Theme.of(context);
    final rescate = _rescate ??= Rescate(caso);
    final apariencia = ref.watch(aparienciaLaboratorioProvider);
    final probabilidades = ref.watch(
      probabilidadesProvider(widget.estudianteId),
    );
    final probabilidad = rescate.fichasUsadas == 0
        ? caso.probabilidad
        : probabilidades.value?[rescate.clave];
    final buho = buhoDuranteRescate(
      caso: caso,
      fichasUsadas: rescate.fichasUsadas,
      probabilidad: probabilidad,
    );
    final e = caso.estudiante;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AnchoMaximo(
          ancho: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(e.nombreCompleto, style: tema.textTheme.titleLarge),
              Text(
                '${e.carrera} · ${e.semestre}.º semestre · ${e.edad} años',
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: apariencia.medidor(
                  probabilidad: probabilidad ?? caso.probabilidad,
                  objetivo: caso.objetivo,
                ),
              ),
              if (probabilidades.hasError) ...[
                const SizedBox(height: 8),
                _AvisoMedidor(
                  onReintentar: () => ref.invalidate(
                    probabilidadesProvider(widget.estudianteId),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _Bocadillo(
                buho: apariencia.buho(animo: buho.animo),
                frase: buho.frase,
              ),
              const SizedBox(height: 16),
              for (final variable in ['horas_estudio', 'asistencia'])
                _Cambio(
                  variable: variable,
                  antes: variable == 'horas_estudio'
                      ? e.horasEstudio
                      : e.asistencia,
                  ahora: rescate.valor(variable),
                ),
              const SizedBox(height: 12),
              _Fichas(usadas: rescate.fichasUsadas, total: caso.presupuesto),
              const SizedBox(height: 12),
              for (final i in caso.intervenciones)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _BotonIntervencion(
                    intervencion: i,
                    motivo: rescate.enTope(i)
                        ? 'Ya está al máximo (${i.tope})'
                        : i.fichas > rescate.fichasRestantes
                        ? 'No te quedan fichas suficientes'
                        : null,
                    onPressed: () {
                      ref.read(sonidosProvider).tocar(Sonido.ficha);
                      setState(() => _rescate = rescate.con(i));
                    },
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: rescate.aplicadas.isEmpty
                        ? null
                        : () => setState(() => _rescate = rescate.deshacer()),
                    icon: const Icon(Icons.undo),
                    label: const Text('Deshacer'),
                  ),
                  TextButton.icon(
                    onPressed: rescate.aplicadas.isEmpty
                        ? null
                        : () => setState(() => _rescate = rescate.reiniciar()),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Empezar de nuevo'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: rescate.aplicadas.isEmpty || _resolviendo
                    ? null
                    : () => _confirmar(rescate),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: _resolviendo
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.health_and_safety_outlined),
                label: const Text('Confirmar rescate'),
              ),
              if (_errorResolver case final error?) ...[
                const SizedBox(height: 8),
                Text(
                  error.mensaje,
                  style: TextStyle(color: tema.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              AvisoModelo(texto: caso.aviso),
            ],
          ),
        ),
      ],
    );
  }
}

/// El búho con su frase al lado (el texto no se anima).
class _Bocadillo extends StatelessWidget {
  const _Bocadillo({required this.buho, required this.frase});

  final Widget buho;
  final String frase;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buho,
        const SizedBox(width: 12),
        Expanded(
          child: Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                frase,
                key: const Key('frase-buho'),
                style: tema.textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Cambio extends StatelessWidget {
  const _Cambio({
    required this.variable,
    required this.antes,
    required this.ahora,
  });

  final String variable;
  final int antes;
  final int ahora;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cambia = ahora != antes;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(nombreVariable(variable))),
          Text(valorVariable(variable, antes)),
          if (cambia) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.arrow_forward, size: 16),
            ),
            Text(
              valorVariable(variable, ahora),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: tema.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fichas extends StatelessWidget {
  const _Fichas({required this.usadas, required this.total});

  final int usadas;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Fichas: has usado $usadas de $total',
      excludeSemantics: true,
      child: Row(
        children: [
          Text('Fichas', style: tema.textTheme.labelLarge),
          const SizedBox(width: 12),
          for (var i = 0; i < total; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                i < usadas ? Icons.circle : Icons.circle_outlined,
                size: 18,
                color: tema.colorScheme.primary,
              ),
            ),
          const SizedBox(width: 10),
          // Flexible: con texto grande o pantallas estrechas pasa a 2 líneas
          // en vez de desbordar.
          Expanded(
            child: Text(
              'Quedan ${total - usadas} de $total',
              textAlign: TextAlign.end,
              style: tema.textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonIntervencion extends StatelessWidget {
  const _BotonIntervencion({
    required this.intervencion,
    required this.motivo,
    required this.onPressed,
  });

  final Intervencion intervencion;

  /// Por qué no se puede aplicar, o `null` si se puede.
  final String? motivo;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final i = intervencion;
    final fichas = '${i.fichas} ${i.fichas == 1 ? 'ficha' : 'fichas'}';
    return OutlinedButton(
      onPressed: motivo == null ? onPressed : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(
            i.variable == 'asistencia'
                ? Icons.co_present_outlined
                : Icons.menu_book_outlined,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i.nombre} · $fichas'),
                Text(
                  motivo ?? i.efecto,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoMedidor extends StatelessWidget {
  const _AvisoMedidor({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Text(
          'No se pudo calcular el medidor; puedes confirmar igualmente.',
        ),
      ),
      TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
    ],
  );
}

/// El resultado que decidió el servidor: estrellas, cifras y el "¿por qué?".
class _VistaResultado extends ConsumerWidget {
  const _VistaResultado({
    required this.caso,
    required this.resultado,
    required this.onOtraVez,
  });

  final Caso caso;
  final ResultadoRescate resultado;
  final VoidCallback onOtraVez;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final estado = ColoresEstado.of(context);
    final r = resultado;
    final apariencia = ref.watch(aparienciaLaboratorioProvider);
    final buho = buhoResultado(r);
    final fichas = r.fichasUsadas == 1 ? 'ficha' : 'fichas';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AnchoMaximo(
          ancho: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Si hay celebración (insignia, nivel), ella es la animación
              // protagonista: las estrellas aparecen quietas.
              Estrellas(
                cantidad: r.estrellas,
                animar: !(r.recompensa?.hayCelebracion ?? false),
              ),
              const SizedBox(height: 8),
              Text(
                r.logrado ? '¡Rescatado!' : 'Sigue en riesgo',
                textAlign: TextAlign.center,
                style: tema.textTheme.headlineSmall?.copyWith(
                  color: r.logrado ? estado.ok : estado.riesgo,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Riesgo estimado: ${formatoProbabilidad(r.probabilidadInicial)} → '
                '${formatoProbabilidad(r.probabilidadFinal)}',
                textAlign: TextAlign.center,
                style: tema.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Usaste ${r.fichasUsadas} $fichas. Lo mínimo era '
                '${r.fichasOptimas}: '
                '${describirSolucion(r.solucionOptima, caso.intervenciones)} '
                '(${formatoProbabilidad(r.solucionOptima.probabilidad)}).',
                textAlign: TextAlign.center,
                style: tema.textTheme.bodyMedium,
              ),
              if (r.recompensa case final recompensa?) ...[
                const SizedBox(height: 12),
                _Recompensa(recompensa: recompensa, record: r.recordEstrellas),
              ],
              const SizedBox(height: 16),
              _Bocadillo(
                buho: apariencia.buho(animo: buho.animo),
                frase: buho.frase,
              ),
              const SizedBox(height: 16),
              ExplicacionVista(explicacion: r.explicacionFinal),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onOtraVez,
                icon: const Icon(Icons.replay),
                label: const Text('Intentar de nuevo'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.go(Rutas.laboratorio),
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Otro caso'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Las estrellas del resultado: la animación protagonista de esta pantalla
/// (aparecen una tras otra en < 1 s; un toque la salta; nada con "reducir
/// movimiento").
class Estrellas extends StatefulWidget {
  const Estrellas({super.key, required this.cantidad, this.animar = true});

  final int cantidad;

  /// `false` cuando otra animación (la celebración) es la protagonista.
  final bool animar;

  @override
  State<Estrellas> createState() => _EstrellasState();
}

class _EstrellasState extends State<Estrellas>
    with SingleTickerProviderStateMixin {
  late final _animacion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || !widget.animar) {
      _animacion.value = 1;
    } else if (_animacion.status == AnimationStatus.dismissed) {
      _animacion.forward();
    }
  }

  @override
  void dispose() {
    _animacion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Semantics(
      container: true,
      label: '${widget.cantidad} de 3 estrellas',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _animacion.value = 1,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              ScaleTransition(
                scale: CurvedAnimation(
                  parent: _animacion,
                  curve: Interval(
                    i / 4,
                    i / 4 + 0.5,
                    curve: Curves.easeOutBack,
                  ),
                ),
                child: Icon(
                  i < widget.cantidad
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 56,
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// XP del rescate (la decide el servidor: 10 por cada estrella que mejora
/// el récord con este estudiante).
class _Recompensa extends StatelessWidget {
  const _Recompensa({required this.recompensa, required this.record});

  final Recompensa recompensa;
  final int? record;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final r = recompensa;
    final xp = r.xpGanada;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: tema.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    xp > 0
                        ? '+$xp XP · ${r.progreso.xp} XP en total'
                        : 'Sin XP: no mejoras tu récord'
                              '${record == null ? '' : ' ($record ${record == 1 ? 'estrella' : 'estrellas'})'}'
                              ' con este estudiante.',
                    key: const Key('xp-rescate'),
                    style: tema.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            for (final i in r.insigniasNuevas)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.military_tech_rounded,
                      color: tema.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Insignia nueva: ${i.nombre}')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
