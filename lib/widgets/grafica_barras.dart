import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/estadistica.dart';
import '../models/estudiante.dart';
import '../theme.dart';
import '../formato.dart';

/// Cómo se dibujan las etiquetas del eje X según el espacio disponible.
enum _ModoEtiquetas {
  /// Horizontales, hasta 2 renglones (caben sin partir palabras).
  horizontales,

  /// Inclinadas 45° (textos largos en pantallas estrechas).
  inclinadas,

  /// Cortas ("18", "3") pero tantas que no caben: la gráfica se desplaza.
  conScroll,
}

/// Gráfica de barras de una estadística, con el valor encima de cada barra.
///
/// Mide las etiquetas con un TextPainter y elige la mejor forma de mostrarlas
/// para que siempre se lean, tanto en un celular como en el escritorio.
class GraficaBarras extends StatefulWidget {
  const GraficaBarras({super.key, required this.datos, required this.tipo});

  final List<Estadistica> datos;
  final TipoEstadistica tipo;

  @override
  State<GraficaBarras> createState() => _GraficaBarrasState();
}

class _GraficaBarrasState extends State<GraficaBarras> {
  // El Scrollbar siempre visible necesita el MISMO controller que su
  // SingleChildScrollView para saber qué posición dibujar.
  final _scroll = ScrollController();

  List<Estadistica> get datos => widget.datos;
  TipoEstadistica get tipo => widget.tipo;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static const double _anchoEjeY = 44;
  static const double _minimoPorBarra = 30;
  static const double _maxAnchoEtiqueta = 150;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estiloEtiqueta = tema.textTheme.labelSmall!.copyWith(
      color: tema.colorScheme.onSurfaceVariant,
    );
    final escala = MediaQuery.textScalerOf(context);

    // Ancho real de cada texto con la fuente que se va a usar.
    double medir(String texto) {
      final painter = TextPainter(
        text: TextSpan(text: texto, style: estiloEtiqueta),
        textDirection: TextDirection.ltr,
        textScaler: escala,
      )..layout();
      final ancho = painter.width;
      painter.dispose();
      return ancho;
    }

    final anchoPalabraMayor = datos
        .expand((d) => d.etiqueta.split(' '))
        .map(medir)
        .fold<double>(0, math.max);
    final anchoEtiquetaMayor = math.min(
      datos.map((d) => medir(d.etiqueta)).fold<double>(0, math.max),
      _maxAnchoEtiqueta,
    );

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, restricciones) {
              final hueco =
                  (restricciones.maxWidth - _anchoEjeY) / datos.length;
              final modo = hueco >= anchoPalabraMayor + 10
                  ? _ModoEtiquetas.horizontales
                  : anchoEtiquetaMayor <= 24
                  ? _ModoEtiquetas.conScroll
                  : _ModoEtiquetas.inclinadas;

              final anchoPorBarra = modo == _ModoEtiquetas.conScroll
                  ? math.max(hueco, _minimoPorBarra)
                  : hueco;
              final grafica = _grafica(
                context,
                modo: modo,
                anchoPorBarra: anchoPorBarra,
                anchoEtiqueta: anchoEtiquetaMayor,
                estiloEtiqueta: estiloEtiqueta,
              );

              if (modo != _ModoEtiquetas.conScroll ||
                  hueco >= _minimoPorBarra) {
                return grafica;
              }
              return Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _anchoEjeY + datos.length * anchoPorBarra,
                    child: grafica,
                  ),
                ),
              );
            },
          ),
        ),
        // El nombre del eje va fuera de la gráfica para que no se desplace
        // (ni se corte) cuando hay scroll horizontal.
        Padding(
          padding: const EdgeInsets.only(top: 4, left: _anchoEjeY),
          child: Text(tipo.ejeX, style: tema.textTheme.labelMedium),
        ),
      ],
    );
  }

  Widget _grafica(
    BuildContext context, {
    required _ModoEtiquetas modo,
    required double anchoPorBarra,
    required double anchoEtiqueta,
    required TextStyle estiloEtiqueta,
  }) {
    final tema = Theme.of(context);
    final colores = ColoresEstado.of(context);
    final maxY = tipo.maximoEjeY(datos.map((d) => d.valor));
    final intervalo = _intervaloBonito(maxY);
    final altoLinea = (estiloEtiqueta.fontSize ?? 11) * 1.4;

    Color colorBarra(Estadistica d) => switch (tipo.unidad) {
      Unidad.porcentaje => colores.riesgo,
      Unidad.promedio when d.valor < Estudiante.umbralRiesgo => colores.riesgo,
      _ => tema.colorScheme.primary,
    };

    final altoEtiquetasX = switch (modo) {
      _ModoEtiquetas.horizontales => altoLinea * 2 + 8,
      _ModoEtiquetas.conScroll => altoLinea + 8,
      // Un texto de ancho w inclinado 45° ocupa ~0.71·w de alto.
      _ModoEtiquetas.inclinadas => (anchoEtiqueta + altoLinea) * 0.71 + 10,
    };

    return BarChart(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        // Truco para mostrar SIEMPRE el valor encima de la barra: usamos el
        // tooltip de fl_chart, transparente y sin padding, y lo dejamos fijo
        // con `showingTooltipIndicators` (más abajo). El toque se desactiva
        // para que no aparezca y desaparezca al tocar.
        barTouchData: BarTouchData(
          enabled: false,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 4,
            fitInsideVertically: true,
            getTooltipItem: (grupo, _, _, _) => BarTooltipItem(
              tipo.formatear(datos[grupo.x].valor),
              // Con barras estrechas (celular) el valor va más pequeño
              // para que "19.4%" y "18.2%" no se toquen.
              (anchoPorBarra < 50
                      ? tema.textTheme.labelSmall!
                      : tema.textTheme.labelMedium!)
                  .copyWith(
                    fontWeight: FontWeight.w700,
                    color: tema.colorScheme.onSurface,
                  ),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _anchoEjeY,
              interval: intervalo,
              getTitlesWidget: (valor, meta) {
                // El techo del eje no suele ser un número "redondo": no se
                // rotula (y así tampoco se corta por arriba).
                if (valor == meta.max) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    _numeroEje(valor, tipo.unidad),
                    style: estiloEtiqueta,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: altoEtiquetasX,
              getTitlesWidget: (valor, meta) {
                final i = valor.toInt();
                if (i < 0 || i >= datos.length) return const SizedBox.shrink();
                final texto = datos[i].etiqueta;
                if (modo == _ModoEtiquetas.inclinadas) {
                  // Un "ancla" de 1 px centrada bajo la barra; el texto se
                  // apoya en ella por su esquina superior derecha y se gira
                  // 45° sobre ese punto: así termina justo bajo su barra.
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: SizedBox(
                      width: 1,
                      height: altoLinea,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: 0,
                            right: 0,
                            width: anchoEtiqueta,
                            child: Transform.rotate(
                              angle: -math.pi / 4,
                              alignment: Alignment.topRight,
                              child: Text(
                                texto,
                                style: estiloEtiqueta,
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: SizedBox(
                    width: anchoPorBarra - 4,
                    child: Text(
                      texto,
                      style: estiloEtiqueta,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: intervalo,
          getDrawingHorizontalLine: (_) => FlLine(
            color: tema.colorScheme.outlineVariant,
            strokeWidth: 1,
            dashArray: const [4, 4],
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(bottom: BorderSide(color: tema.colorScheme.outline)),
        ),
        // En "promedio por carrera" se marca el umbral de riesgo.
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (tipo.unidad == Unidad.promedio)
              HorizontalLine(
                y: Estudiante.umbralRiesgo,
                color: colores.riesgo,
                strokeWidth: 1.5,
                dashArray: const [6, 4],
              ),
          ],
        ),
        barGroups: [
          for (var i = 0; i < datos.length; i++)
            BarChartGroupData(
              x: i,
              showingTooltipIndicators: const [0],
              barRods: [
                BarChartRodData(
                  toY: datos[i].valor.toDouble(),
                  width: math.min(anchoPorBarra * 0.6, 36),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      colorBarra(datos[i]).withValues(alpha: 0.7),
                      colorBarra(datos[i]),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Un intervalo "redondo" (1, 2, 2.5, 5, 10, 20...) para ~6 líneas.
  static double _intervaloBonito(double maximo) {
    final bruto = maximo / 6;
    final magnitud = math.pow(10, (math.log(bruto) / math.ln10).floor());
    for (final paso in [1, 2, 2.5, 5, 10]) {
      final candidato = paso * magnitud;
      if (candidato >= bruto) return candidato.toDouble();
    }
    return (10 * magnitud).toDouble();
  }

  static String _numeroEje(double valor, Unidad unidad) => switch (unidad) {
    Unidad.promedio => formatoDecimal(valor, 1),
    Unidad.porcentaje => formatoPorcentaje(valor),
    Unidad.conteo => formatoEntero(valor),
  };
}
