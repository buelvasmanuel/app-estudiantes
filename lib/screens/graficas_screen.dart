import 'package:flutter/material.dart';

import '../models/estadistica.dart';
import '../services/api_service.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/grafica_barras.dart';

/// Pestaña 2: estadísticas de los estudiantes en una gráfica de barras.
class GraficasScreen extends StatefulWidget {
  const GraficasScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<GraficasScreen> createState() => _GraficasScreenState();
}

class _GraficasScreenState extends State<GraficasScreen> {
  TipoEstadistica _tipo = TipoEstadistica.porCarrera;

  // Guardamos lo ya descargado por tipo: volver a una estadística que ya se
  // vio es instantáneo y no repite la petición.
  final Map<TipoEstadistica, List<Estadistica>> _datos = {};
  final Map<TipoEstadistica, ApiException> _errores = {};

  @override
  void initState() {
    super.initState();
    _cargar(_tipo);
  }

  Future<void> _cargar(TipoEstadistica tipo) async {
    setState(() => _errores.remove(tipo));
    try {
      final datos = await widget.api.obtenerEstadistica(tipo);
      if (!mounted) return;
      setState(() => _datos[tipo] = datos);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_datos.containsKey(tipo)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.mensaje)));
      } else {
        setState(() => _errores[tipo] = e);
      }
    }
  }

  void _seleccionar(TipoEstadistica? tipo) {
    if (tipo == null || tipo == _tipo) return;
    setState(() => _tipo = tipo);
    if (!_datos.containsKey(tipo)) _cargar(tipo);
  }

  /// Al actualizar se descarta la caché: los datos pudieron cambiar.
  Future<void> _actualizar() {
    final actual = _datos[_tipo];
    _datos.clear();
    if (actual != null) _datos[_tipo] = actual; // se ve mientras recarga
    return _cargar(_tipo);
  }

  @override
  Widget build(BuildContext context) {
    final datos = _datos[_tipo];
    final error = _errores[_tipo];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gráficas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _actualizar,
            icon: const Icon(Icons.refresh_rounded),
          ),
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
                            child: switch ((datos, error)) {
                              (null, final ApiException e) => ErrorVista(
                                error: e,
                                onReintentar: () => _cargar(_tipo),
                              ),
                              (null, null) => CargandoVista(
                                mensaje: 'Cargando estadística…',
                                despertando: widget.api.despertando,
                              ),
                              (final List<Estadistica> d, _) when d.isEmpty =>
                                const VaciaVista(
                                  mensaje:
                                      'No hay datos para esta estadística.',
                                  icono: Icons.bar_chart_outlined,
                                ),
                              (final List<Estadistica> d, _) => GraficaBarras(
                                key: ValueKey(_tipo),
                                datos: d,
                                tipo: _tipo,
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
        ('Total', '${total.round()}', 'estudiantes'),
      ('Más alto', tipo.formatear(mayor.valor), tipo.describir(mayor.etiqueta)),
      ('Más bajo', tipo.formatear(menor.valor), tipo.describir(menor.etiqueta)),
      (
        'Media',
        tipo.unidad == Unidad.conteo
            ? media.toStringAsFixed(1)
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
