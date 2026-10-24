import 'package:flutter/material.dart';

import '../models/estudiante.dart';
import '../theme.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/promedio_badge.dart';
import '../formato.dart';
import '../widgets/titulo_barra.dart';

/// Detalle de un estudiante. Usa los datos que ya trajo el listado, así que
/// no necesita otra petición a la API.
class EstudianteDetalleScreen extends StatelessWidget {
  const EstudianteDetalleScreen({super.key, required this.estudiante});

  final Estudiante estudiante;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = ColoresEstado.of(context);
    final e = estudiante;

    return Scaffold(
      appBar: AppBar(title: TituloBarra(e.nombreCompleto)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AnchoMaximo(
          ancho: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Cabecera ---
              Card.filled(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Hero(
                        tag: 'avatar-${e.id}',
                        child: EstudianteAvatar(estudiante: e, radio: 40),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        e.nombreCompleto,
                        style: tema.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        e.carrera,
                        style: tema.textTheme.titleMedium?.copyWith(
                          color: tema.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PromedioBadge(estudiante: e, grande: true),
                      const SizedBox(height: 8),
                      Text(
                        e.enRiesgo
                            ? 'En riesgo académico (promedio < '
                                  '${formatoDecimal(Estudiante.umbralRiesgo)})'
                            : 'Sin riesgo académico',
                        style: tema.textTheme.bodyMedium?.copyWith(
                          color: e.enRiesgo ? colores.riesgo : colores.ok,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // --- Datos personales ---
              _Seccion(
                titulo: 'Datos',
                children: [
                  _Dato(Icons.badge_outlined, 'ID', '${e.id}'),
                  _Dato(Icons.cake_outlined, 'Edad', '${e.edad} años'),
                  _Dato(Icons.location_city_outlined, 'Ciudad', e.ciudad),
                  _Dato(Icons.school_outlined, 'Semestre', '${e.semestre}º'),
                ],
              ),
              const SizedBox(height: 16),

              // --- Rendimiento ---
              _Seccion(
                titulo: 'Rendimiento',
                children: [
                  _Barra(
                    icono: Icons.grade_outlined,
                    etiqueta: 'Promedio',
                    valor: formatoPromedio(e.promedio),
                    progreso: e.promedio / 5,
                    color: e.enRiesgo ? colores.riesgo : colores.ok,
                  ),
                  _Barra(
                    icono: Icons.menu_book_outlined,
                    etiqueta: 'Horas de estudio / semana',
                    valor: '${e.horasEstudio} h',
                    progreso: e.horasEstudio / 40,
                    color: tema.colorScheme.primary,
                  ),
                  _Barra(
                    icono: Icons.event_available_outlined,
                    etiqueta: 'Asistencia',
                    valor: formatoPorcentaje(e.asistencia),
                    progreso: e.asistencia / 100,
                    color: tema.colorScheme.tertiary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.children});

  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                titulo,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.etiqueta, this.valor);

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icono),
      title: Text(etiqueta),
      trailing: Text(valor, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    required this.progreso,
    required this.color,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;
  final double progreso;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Icon(icono, color: tema.colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(etiqueta)),
                    Text(valor, style: tema.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progreso.clamp(0, 1),
                  color: color,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
