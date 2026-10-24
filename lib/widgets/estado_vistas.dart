import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Indicador de carga centrado, con un texto opcional.
///
/// Si se le pasa [despertando] y se pone a `true`, cambia el mensaje para
/// explicar que el servidor (Render free) está arrancando.
class CargandoVista extends StatelessWidget {
  const CargandoVista({
    super.key,
    this.mensaje = 'Cargando…',
    this.despertando,
  });

  final String mensaje;
  final ValueListenable<bool>? despertando;

  /// Medido: tras días sin uso, Render tarda más de un minuto en responder.
  static const mensajeDespertando =
      'Despertando el servidor, puede tardar uno o dos minutos…';

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<bool>(
          valueListenable: despertando ?? const _Siempre(false),
          builder: (context, dormido, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                dormido ? mensajeDespertando : mensaje,
                style: tema.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (dormido) ...[
                const SizedBox(height: 8),
                Text(
                  'El servidor gratuito se apaga tras un rato sin uso.',
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                // Que una espera larga no parezca un cuelgue.
                const TiempoEsperando(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// «Llevas 35 s esperando», contado desde que aparece. No es una región
/// viva: el lector de pantalla no lo repite cada segundo.
class TiempoEsperando extends StatefulWidget {
  const TiempoEsperando({super.key});

  @override
  State<TiempoEsperando> createState() => _TiempoEsperandoState();
}

class _TiempoEsperandoState extends State<TiempoEsperando> {
  final _inicio = clock.now();
  late final Timer _reloj = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _reloj; // arranca el reloj
  }

  @override
  void dispose() {
    _reloj.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final s = clock.now().difference(_inicio).inSeconds;
    return Text(
      'Llevas $s s esperando',
      key: const Key('tiempo-esperando'),
      style: tema.textTheme.bodySmall?.copyWith(
        color: tema.colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// ValueListenable constante (para cuando no hay nada que escuchar).
class _Siempre implements ValueListenable<bool> {
  const _Siempre(this.value);

  @override
  final bool value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Pantalla de error con el mensaje y un botón "Reintentar".
class ErrorVista extends StatelessWidget {
  const ErrorVista({
    super.key,
    required this.error,
    required this.onReintentar,
  });

  final Object error;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final sinConexion =
        error is ApiException && (error as ApiException).sinConexion;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                sinConexion
                    ? Icons.cloud_off_rounded
                    : Icons.error_outline_rounded,
                size: 64,
                color: tema.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                sinConexion ? 'Sin conexión con la API' : 'Algo salió mal',
                style: tema.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mensaje para cuando no hay datos que mostrar.
class VaciaVista extends StatelessWidget {
  const VaciaVista({
    super.key,
    required this.mensaje,
    this.icono = Icons.inbox_outlined,
  });

  final String mensaje;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: tema.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: tema.textTheme.bodyLarge?.copyWith(
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Limita el ancho del contenido en pantallas anchas (Linux, Chrome) para
/// que no quede estirado de lado a lado.
class AnchoMaximo extends StatelessWidget {
  const AnchoMaximo({super.key, required this.child, this.ancho = 760});

  final Widget child;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ancho),
        child: child,
      ),
    );
  }
}
