import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/prediccion.dart';
import '../providers.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/menu_cuenta.dart';
import '../formato.dart';

/// Pestaña 3: formulario que pide al modelo de la API si un estudiante con
/// esos datos estaría en riesgo académico.
class PrediccionScreen extends ConsumerStatefulWidget {
  const PrediccionScreen({super.key, this.pestanas});

  /// El selector de la pestaña Datos (`SelectorDatos`), si va dentro de ella.
  final PreferredSizeWidget? pestanas;

  @override
  ConsumerState<PrediccionScreen> createState() => _PrediccionScreenState();
}

class _PrediccionScreenState extends ConsumerState<PrediccionScreen> {
  // Las métricas (/prediccion/metricas, con las carreras del desplegable) las
  // guarda metricasProvider; aquí queda el formulario y la predicción.

  // --- Formulario (valores iniciales: un estudiante "típico") ---
  String? _carrera;
  double _horasEstudio = 14;
  double _asistencia = 82;
  double _semestre = 3;
  double _edad = 20;

  // --- Predicción ---
  bool _prediciendo = false;
  ResultadoPrediccion? _resultado;
  EntradaPrediccion? _entradaDelResultado;
  ApiException? _errorPrediccion;

  EntradaPrediccion? get _entrada {
    final carrera = _carrera;
    if (carrera == null) return null;
    return EntradaPrediccion(
      horasEstudio: _horasEstudio.round(),
      asistencia: _asistencia.round(),
      semestre: _semestre.round(),
      edad: _edad.round(),
      carrera: carrera,
    );
  }

  Future<void> _predecir() async {
    final entrada = _entrada;
    if (entrada == null || _prediciendo) return;
    setState(() {
      _prediciendo = true;
      _errorPrediccion = null;
    });
    try {
      final resultado = await ref
          .read(apiServiceProvider)
          .predecirRiesgo(entrada);
      if (!mounted) return;
      setState(() {
        _resultado = resultado;
        _entradaDelResultado = entrada;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorPrediccion = e);
    } finally {
      if (mounted) setState(() => _prediciendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si al recargar las métricas la carrera elegida ya no existe en el
    // modelo, se descarta.
    ref.listen(metricasProvider, (_, siguiente) {
      final carreras = siguiente.value?.carrerasValidas;
      if (carreras != null && !carreras.contains(_carrera)) {
        setState(() => _carrera = null);
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Predicción'),
        bottom: widget.pestanas,
        actions: const [MenuCuenta()],
      ),
      body: switch (ref.watch(metricasProvider)) {
        AsyncValue(value: final MetricasModelo m) => _contenido(m),
        AsyncValue(:final error?) => ErrorVista(
          error: error,
          onReintentar: () => ref.invalidate(metricasProvider),
        ),
        _ => CargandoVista(
          mensaje: 'Cargando el modelo…',
          despertando: ref.watch(apiServiceProvider).despertando,
        ),
      },
    );
  }

  Widget _contenido(MetricasModelo metricas) {
    final tema = Theme.of(context);
    final entrada = _entrada;
    // El resultado mostrado corresponde a otros datos si el usuario movió
    // algo después de predecir.
    final desactualizado =
        _resultado != null && entrada != _entradaDelResultado;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AnchoMaximo(
          ancho: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Datos del estudiante',
                        style: tema.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      DropdownMenu<String>(
                        initialSelection: _carrera,
                        expandedInsets: EdgeInsets.zero,
                        requestFocusOnTap: false,
                        label: const Text('Carrera'),
                        hintText: 'Elige una carrera',
                        leadingIcon: const Icon(Icons.school_outlined),
                        onSelected: (c) => setState(() => _carrera = c),
                        dropdownMenuEntries: [
                          for (final c in metricas.carrerasValidas)
                            DropdownMenuEntry(value: c, label: c),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _CampoSlider(
                        icono: Icons.menu_book_outlined,
                        etiqueta: 'Horas de estudio por semana',
                        valor: _horasEstudio,
                        min: 0,
                        max: 40,
                        formato: (v) => '${v.round()} h',
                        onChanged: (v) => setState(() => _horasEstudio = v),
                      ),
                      _CampoSlider(
                        icono: Icons.event_available_outlined,
                        etiqueta: 'Asistencia',
                        valor: _asistencia,
                        min: 0,
                        max: 100,
                        formato: (v) => formatoPorcentaje(v),
                        onChanged: (v) => setState(() => _asistencia = v),
                      ),
                      _CampoSlider(
                        icono: Icons.calendar_month_outlined,
                        etiqueta: 'Semestre',
                        valor: _semestre,
                        min: 1,
                        max: 10,
                        formato: (v) => '${v.round()}º',
                        onChanged: (v) => setState(() => _semestre = v),
                      ),
                      _CampoSlider(
                        icono: Icons.cake_outlined,
                        etiqueta: 'Edad',
                        valor: _edad,
                        min: 16,
                        max: 35,
                        formato: (v) => '${v.round()} años',
                        onChanged: (v) => setState(() => _edad = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: entrada == null || _prediciendo ? null : _predecir,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: _prediciendo
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.psychology_alt_outlined),
                label: ValueListenableBuilder<bool>(
                  valueListenable: ref.watch(apiServiceProvider).despertando,
                  builder: (context, dormido, _) => Text(
                    entrada == null
                        ? 'Elige una carrera para predecir'
                        : !_prediciendo
                        ? 'Predecir'
                        : dormido
                        ? 'Despertando el servidor…'
                        : 'Prediciendo…',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: switch ((_resultado, _errorPrediccion)) {
                  (_, final ApiException e) => _ErrorPrediccion(
                    key: const ValueKey('error'),
                    error: e,
                  ),
                  (final ResultadoPrediccion r, null) => _ResultadoCard(
                    key: ValueKey(r),
                    resultado: r,
                    desactualizado: desactualizado,
                  ),
                  (null, null) => const SizedBox.shrink(),
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Indicador orientativo del modelo, no un diagnóstico',
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SobreElModelo(metricas: metricas),
            ],
          ),
        ),
      ],
    );
  }
}

/// Un slider con icono, nombre y valor actual.
class _CampoSlider extends StatelessWidget {
  const _CampoSlider({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    required this.min,
    required this.max,
    required this.formato,
    required this.onChanged,
  });

  final IconData icono;
  final String etiqueta;
  final double valor;
  final double min;
  final double max;
  final String Function(double) formato;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icono, size: 20, color: tema.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(etiqueta)),
              Text(
                formato(valor),
                style: tema.textTheme.titleSmall?.copyWith(
                  color: tema.colorScheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: valor,
            min: min,
            max: max,
            // Una división por cada entero: el slider "salta" de 1 en 1.
            divisions: (max - min).round(),
            label: formato(valor),
            semanticFormatterCallback: formato,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Resultado en rojo (en riesgo) o verde (sin riesgo) con la probabilidad.
class _ResultadoCard extends StatelessWidget {
  const _ResultadoCard({
    super.key,
    required this.resultado,
    required this.desactualizado,
  });

  final ResultadoPrediccion resultado;
  final bool desactualizado;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final c = ColoresEstado.of(context);
    final riesgo = resultado.enRiesgo;
    final fondo = riesgo ? c.riesgoContenedor : c.okContenedor;
    final texto = riesgo ? c.onRiesgoContenedor : c.onOkContenedor;
    final acento = riesgo ? c.riesgo : c.ok;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: desactualizado ? 0.55 : 1,
      child: Card(
        color: fondo,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    riesgo
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: texto,
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          riesgo
                              ? 'En riesgo académico'
                              : 'Sin riesgo académico',
                          style: tema.textTheme.titleLarge?.copyWith(
                            color: texto,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Modelo: ${resultado.modelo}',
                          style: tema.textTheme.bodySmall?.copyWith(
                            color: texto,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatoPorcentaje(resultado.porcentaje),
                        key: const Key('probabilidad'),
                        style: tema.textTheme.headlineMedium?.copyWith(
                          color: texto,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'prob. de riesgo',
                        style: tema.textTheme.labelSmall?.copyWith(
                          color: texto,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: resultado.probabilidad.toDouble().clamp(0, 1),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
                color: acento,
                backgroundColor: texto.withValues(alpha: 0.15),
              ),
              if (desactualizado) ...[
                const SizedBox(height: 12),
                Text(
                  'Cambiaste los datos: pulsa Predecir para actualizar.',
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: texto,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorPrediccion extends StatelessWidget {
  const _ErrorPrediccion({super.key, required this.error});

  final ApiException error;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      elevation: 0,
      color: tema.colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(
          error.sinConexion ? Icons.cloud_off_rounded : Icons.error_outline,
          color: tema.colorScheme.onErrorContainer,
        ),
        title: Text(
          error.sinConexion ? 'Sin conexión con la API' : 'No se pudo predecir',
          style: TextStyle(color: tema.colorScheme.onErrorContainer),
        ),
        subtitle: Text(
          error.mensaje,
          style: TextStyle(color: tema.colorScheme.onErrorContainer),
        ),
      ),
    );
  }
}

/// Métricas del modelo: ayudan a explicar en clase qué tan fiable es.
class _SobreElModelo extends StatelessWidget {
  const _SobreElModelo({required this.metricas});

  final MetricasModelo metricas;

  static String _pct(num? v) => v == null ? '–' : formatoProbabilidad(v);

  static String _nombreVariable(String v) => switch (v) {
    'horas_estudio' => 'horas de estudio',
    _ => v.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final m = metricas;
    final entrenado = m.entrenado;

    final indicadores = [
      (
        'Recall',
        _pct(m.recall),
        'De los que SÍ están en riesgo, cuántos detecta',
      ),
      (
        'Precision',
        _pct(m.precision),
        'De los que marca en riesgo, cuántos lo están',
      ),
      ('Accuracy', _pct(m.accuracy), 'Aciertos totales'),
      (
        'F2',
        m.f2 == null ? '–' : formatoDecimal(m.f2!, 2),
        'Equilibrio, pesando más el recall',
      ),
    ];

    return Card.outlined(
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        leading: const Icon(Icons.insights_outlined),
        title: const Text('Sobre el modelo'),
        subtitle: Text(m.modelo),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (m.totalDatos != null || entrenado != null)
            Text(
              [
                if (m.totalDatos != null)
                  'Entrenado con ${m.totalDatos} estudiantes'
                      '${m.porcentajeEnRiesgo == null ? '' : ' '
                                '(${formatoPorcentaje(m.porcentajeEnRiesgo!, 1)} en riesgo)'}',
                if (entrenado != null)
                  'el ${entrenado.day}/${entrenado.month}/${entrenado.year}',
              ].join(' '),
              style: tema.textTheme.bodyMedium,
            ),
          const SizedBox(height: 12),
          Text(
            'Resultados en el conjunto de prueba',
            style: tema.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, restricciones) {
              const separacion = 8.0;
              final columnas = restricciones.maxWidth >= 520 ? 4 : 2;
              final ancho =
                  (restricciones.maxWidth - separacion * (columnas - 1)) /
                  columnas;
              return Wrap(
                spacing: separacion,
                runSpacing: separacion,
                children: [
                  for (final (nombre, valor, ayuda) in indicadores)
                    SizedBox(
                      width: ancho,
                      child: Tooltip(
                        message: ayuda,
                        child: Card.filled(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nombre, style: tema.textTheme.labelMedium),
                                Text(
                                  valor,
                                  style: tema.textTheme.titleLarge?.copyWith(
                                    color: tema.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  ayuda,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: tema.colorScheme.onSurfaceVariant,
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
          ),
          if (m.variablesInfluyentes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Variables más influyentes', style: tema.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, v) in m.variablesInfluyentes.take(4).indexed)
                  Chip(
                    avatar: CircleAvatar(child: Text('${i + 1}')),
                    label: Text(_nombreVariable(v)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Se prioriza el recall: no detectar a un estudiante en riesgo '
            'cuesta más que ofrecer una tutoría de más. Por eso el modelo se '
            'entrenó con clases balanceadas y sus probabilidades tienden a '
            'salir altas: sirven para ordenar, no como un porcentaje literal.',
            style: tema.textTheme.bodySmall?.copyWith(
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
