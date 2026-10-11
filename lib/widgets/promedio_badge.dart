import 'package:flutter/material.dart';

import '../models/estudiante.dart';
import '../theme.dart';
import '../formato.dart';

/// Pastilla con el promedio: roja si está en riesgo (< 3.0), verde si no.
///
/// Además del color lleva un icono, para quien no distingue bien rojo/verde.
class PromedioBadge extends StatelessWidget {
  const PromedioBadge({
    super.key,
    required this.estudiante,
    this.grande = false,
  });

  final Estudiante estudiante;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final c = ColoresEstado.of(context);
    final riesgo = estudiante.enRiesgo;
    final fondo = riesgo ? c.riesgoContenedor : c.okContenedor;
    final texto = riesgo ? c.onRiesgoContenedor : c.onOkContenedor;
    final estilo =
        (grande
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.labelLarge)
            ?.copyWith(color: texto, fontWeight: FontWeight.w700);

    return Semantics(
      label:
          'Promedio ${formatoPromedio(estudiante.promedio)}'
          '${riesgo ? ', en riesgo' : ''}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: grande ? 14 : 10,
          vertical: grande ? 8 : 4,
        ),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              riesgo ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              size: grande ? 20 : 16,
              color: texto,
            ),
            const SizedBox(width: 4),
            Text(formatoPromedio(estudiante.promedio), style: estilo),
          ],
        ),
      ),
    );
  }
}

/// Avatar circular con las iniciales, del color del estado del estudiante.
class EstudianteAvatar extends StatelessWidget {
  const EstudianteAvatar({
    super.key,
    required this.estudiante,
    this.radio = 22,
  });

  final Estudiante estudiante;
  final double radio;

  @override
  Widget build(BuildContext context) {
    final c = ColoresEstado.of(context);
    final riesgo = estudiante.enRiesgo;
    return CircleAvatar(
      radius: radio,
      backgroundColor: riesgo ? c.riesgoContenedor : c.okContenedor,
      foregroundColor: riesgo ? c.onRiesgoContenedor : c.onOkContenedor,
      child: Text(
        estudiante.iniciales,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: radio * 0.75),
      ),
    );
  }
}
