import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estadistica.dart';
import '../providers.dart';
import '../services/api_service.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/menu_cuenta.dart';
import '../widgets/grafica_barras.dart';
import '../formato.dart';
import '../widgets/titulo_barra.dart';

/// Pestaña 2: estadísticas de los estudiantes en una gráfica de barras.
class GraficasScreen extends ConsumerStatefulWidget {
  const GraficasScreen({super.key, this.pestanas});

  /// El selector de la pestaña Datos (`SelectorDatos`), si va dentro de ella.
  final PreferredSizeWidget? pestanas;

  @override
  ConsumerState<GraficasScreen> createState() => _GraficasScreenState();
}

class _GraficasScreenState extends ConsumerState<GraficasScreen> {
  TipoEstadistica _tipo = TipoEstadistica.porCarrera;

  void _seleccionar(TipoEstadistica? tipo) {
    if (tipo == null || tipo == _tipo) return;
    setState(() => _tipo = tipo);
  }

  /// Al actualizar se descarta la caché de TODOS los tipos: los datos
  /// pudieron cambiar. El tipo visible conserva su gráfica mientras recarga.
  Future<void> _actualizar() async {
    ref.invalidate(estadisticaProvider);
    try {
      await ref.read(estadisticaProvider(_tipo).future);
    } on ApiException catch (e) {
      if (!mounted || !ref.read(estadisticaProvider(_tipo)).hasValue) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(estadisticaProvider(_tipo));
    final datos = estado.value;

    return Scaffold(
      appBar: AppBar(
        title: const TituloBarra('Gráficas'),
        bottom: widget.pestanas,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _actualizar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const MenuCuenta(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _actualizar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            AnchoMaximo(
              ancho: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownMenu<TipoEstadistica>(
                    initialSelection: _tipo,
                    onSelected: _seleccionar,
                    expandedInsets: EdgeInsets.zero,
                    // En escritorio el DropdownMenu permite escribir para
                    // filtrar; aquí solo queremos elegir.
                    requestFocusOnTap: false,
                    label: const Text('Estadística'),
                    leadingIcon: Icon(_icono(_tipo)),
                    dropdownMenuEntries: [
                      for (final t in TipoEstadistica.values)
                        DropdownMenuEntry(
                          value: t,
                          label: t.nombre,
                          leadingIcon: Icon(_icono(t)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card.outlined(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _tipo.nombre,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _tipo.descripcion,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 340,
                            child: switch (estado) {
                              AsyncValue(value: final List<Estadistica> d)
                                  when d.isEmpty =>
                                const VaciaVista(
                                  mensaje:
                                      'No hay datos para esta estadística.',
                                  icono: Icons.bar_chart_outlined,
                                ),
                              AsyncValue(value: final List<Estadistica> d) =>
                                GraficaBarras(
                                  key: ValueKey(_tipo),
                                  datos: d,
                                  tipo: _tipo,
                                ),
                              AsyncValue(:final error?) => ErrorVista(
                                error: error,
                                onReintentar: () =>
                                    ref.invalidate(estadisticaProvider(_tipo)),
                              ),
                              _ => CargandoVista(
                                mensaje: 'Cargando estadística…',
                                despertando: ref
                                    .watch(apiServiceProvider)
                                    .despertando,
                              ),
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (datos != null && datos.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Resumen(datos: datos, tipo: _tipo),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icono(TipoEstadistica tipo) => switch (tipo) {
    TipoEstadistica.porCarrera => Icons.school_outlined,
    TipoEstadistica.porEdad => Icons.cake_outlined,
    TipoEstadistica.porSemestre => Icons.calendar_month_outlined,
    TipoEstadistica.porCiudad => Icons.location_city_outlined,
    TipoEstadistica.promedioPorCarrera => Icons.grade_outlined,
    TipoEstadistica.riesgoPorCarrera => Icons.warning_amber_rounded,
  };
}

/// Fichas con un resumen de la estadística, en una rejilla adaptable
/// (2 columnas en el celular, 4 en pantallas anchas).
class _Resumen extends StatelessWidget {
  const _Resumen({required this.datos, required this.tipo});

  final List<Estadistica> datos;
  final TipoEstadistica tipo;

  @override
  Widget build(BuildContext context) {
    final mayor = datos.reduce((a, b) => b.valor > a.valor ? b : a);
    final menor = datos.reduce((a, b) => b.valor < a.valor ? b : a);
    final total = datos.fold<num>(0, (s, d) => s + d.valor);
    final media = total / datos.length;

    final fichas = <(String, String, String)>[
      if (tipo.unidad == Unidad.conteo)
        ('Total', formatoEntero(total), 'estudiantes'),
      ('Más alto', tipo.formatear(mayor.valor), tipo.describir(mayor.etiqueta)),
      ('Más bajo', tipo.formatear(menor.valor), tipo.describir(menor.etiqueta)),
      (
        'Media',
        tipo.unidad == Unidad.conteo
            ? formatoDecimal(media)
            : tipo.formatear(media),
        'por ${tipo.grupo}',
      ),
      if (tipo.unidad != Unidad.conteo)
        (
          'Diferencia',
          tipo.formatear(mayor.valor - menor.valor),
          'máximo − mínimo',
        ),
    ];

    return LayoutBuilder(
      builder: (context, restricciones) {
        const separacion = 12.0;
        final columnas = restricciones.maxWidth >= 600 ? 4 : 2;
        final ancho =
            (restricciones.maxWidth - separacion * (columnas - 1)) / columnas;
        return Wrap(
          spacing: separacion,
          runSpacing: separacion,
          children: [
            for (final (titulo, valor, detalle) in fichas)
              SizedBox(
                width: ancho,
                child: _Ficha(titulo: titulo, valor: valor, detalle: detalle),
              ),
          ],
        );
      },
    );
  }
}

class _Ficha extends StatelessWidget {
  const _Ficha({
    required this.titulo,
    required this.valor,
    required this.detalle,
  });

  final String titulo;
  final String valor;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: tema.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              valor,
              style: tema.textTheme.headlineSmall?.copyWith(
                color: tema.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              detalle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
