import 'package:flutter/material.dart';

import '../theme.dart';
import 'modelo.dart';
import 'textos.dart';

/// El "¿por qué?": cuánto pesó cada variable en la estimación, con el aviso
/// del modelo siempre visible. Sin animaciones: es para leer.
class ExplicacionVista extends StatelessWidget {
  const ExplicacionVista({super.key, required this.explicacion});

  final Explicacion explicacion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final comparacion = comparacionPesos(explicacion);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('¿Por qué?', style: tema.textTheme.titleMedium),
        if (comparacion != null) ...[
          const SizedBox(height: 4),
          Text(comparacion, style: tema.textTheme.bodyMedium),
        ],
        const SizedBox(height: 12),
        for (final a in explicacion.aportes) _FilaAporte(aporte: a),
        const SizedBox(height: 8),
        Text(
          'Comparado con el estudiante medio de los datos, cuyo riesgo '
          'estimado es ${porcentaje(explicacion.probabilidadBase)}.',
          style: tema.textTheme.bodySmall?.copyWith(
            color: tema.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        AvisoModelo(texto: explicacion.aviso),
      ],
    );
  }
}

class _FilaAporte extends StatelessWidget {
  const _FilaAporte({required this.aporte});

  final Aporte aporte;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estado = ColoresEstado.of(context);
    final a = aporte;
    final (color, sentido) = switch (a.efecto) {
      Efecto.sube => (estado.riesgo, 'sube el riesgo'),
      Efecto.baja => (estado.ok, 'lo baja'),
      Efecto.neutro => (tema.colorScheme.outline, 'no influye'),
    };
    final nombre = nombreVariable(a.variable);
    final valor = valorVariable(a.variable, a.valor);
    final pct = (a.peso * 100).round();
    return Semantics(
      container: true,
      label:
          '$nombre, $valor: $sentido, $pct % del peso total'
          '${esAccionable(a.variable) ? '' : ', no se puede cambiar en el juego'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: nombre,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: ' · $valor'),
                      ],
                    ),
                    style: tema.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '$sentido · $pct\u00A0%',
                  style: tema.textTheme.labelMedium?.copyWith(color: color),
                ),
              ],
            ),
            if (!esAccionable(a.variable))
              Text(
                'No se puede cambiar en el juego',
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: a.peso.clamp(0, 1),
                minHeight: 8,
                color: color,
                backgroundColor: tema.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El aviso del modelo (estimación, correlación y no causalidad).
class AvisoModelo extends StatelessWidget {
  const AvisoModelo({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: tema.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(texto, style: tema.textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}
