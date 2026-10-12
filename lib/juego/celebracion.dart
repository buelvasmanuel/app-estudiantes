import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sonidos.dart';

import 'modelo.dart';
import '../formato.dart';

/// Celebra una subida de nivel o insignias nuevas, si las hay.
///
/// Es la animación protagonista del momento (PROPUESTA §2.4): el emblema
/// aparece en ≤ 1,2 s, un toque la salta y con "reducir movimiento" sale ya
/// quieto. El texto nunca se anima. Quien la llama no debe animar nada más a
/// la vez.
Future<void> celebrar(BuildContext context, Recompensa recompensa) async {
  if (!recompensa.hayCelebracion) return;
  final quieto = MediaQuery.disableAnimationsOf(context);
  ProviderScope.containerOf(context)
      .read(sonidosProvider)
      .tocar(Sonido.celebracion);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar celebración',
    transitionDuration: quieto
        ? Duration.zero
        : const Duration(milliseconds: 200),
    transitionBuilder: (context, animacion, _, hijo) =>
        FadeTransition(opacity: animacion, child: hijo),
    pageBuilder: (context, _, _) =>
        Center(child: CelebracionVista(recompensa: recompensa)),
  );
}

class CelebracionVista extends StatefulWidget {
  const CelebracionVista({super.key, required this.recompensa});

  final Recompensa recompensa;

  static const duracion = Duration(milliseconds: 1200);

  @override
  State<CelebracionVista> createState() => _CelebracionVistaState();
}

class _CelebracionVistaState extends State<CelebracionVista>
    with SingleTickerProviderStateMixin {
  late final _animacion = AnimationController(
    vsync: this,
    duration: CelebracionVista.duracion,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
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
    final tema = Theme.of(context);
    final r = widget.recompensa;
    final subio = r.progreso.subioDeNivel;
    final titulo = subio
        ? '¡Ahora eres ${r.progreso.nivel}!'
        : r.insigniasNuevas.length == 1
        ? '¡Insignia nueva!'
        : '¡${r.insigniasNuevas.length} insignias nuevas!';

    return Semantics(
      container: true,
      liveRegion: true,
      label: titulo,
      child: GestureDetector(
        // Un toque salta la animación (el botón cierra).
        onTap: () => _animacion.value = 1,
        child: Material(
          color: tema.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 120,
                    child: AnimatedBuilder(
                      animation: _animacion,
                      builder: (context, _) => CustomPaint(
                        painter: _PintorDestello(
                          progreso: _animacion.value,
                          color: tema.colorScheme.tertiary,
                        ),
                        child: Center(
                          child: Transform.scale(
                            scale: Curves.elasticOut.transform(
                              (_animacion.value * 1.4).clamp(0, 1),
                            ),
                            child: Icon(
                              subio
                                  ? Icons.workspace_premium_rounded
                                  : Icons.military_tech_rounded,
                              size: 72,
                              color: tema.colorScheme.tertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: tema.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '+${r.xpGanada} XP · ${formatoEntero(r.progreso.xp)} XP en total',
                    style: tema.textTheme.titleMedium?.copyWith(
                      color: tema.colorScheme.primary,
                    ),
                  ),
                  for (final i in r.insigniasNuevas)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.military_tech_outlined,
                        color: tema.colorScheme.tertiary,
                      ),
                      title: Text(i.nombre),
                      subtitle: Text(i.descripcion),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('¡Seguir!'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rayos que se abren alrededor del emblema y se desvanecen.
class _PintorDestello extends CustomPainter {
  _PintorDestello({required this.progreso, required this.color});

  final double progreso;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progreso <= 0 || progreso >= 1) return;
    final centro = size.center(Offset.zero);
    final radio = size.shortestSide / 2;
    final pintura = Paint()
      ..color = color.withValues(alpha: (1 - progreso) * 0.8)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final angulo = i * math.pi / 6;
      final dir = Offset(math.cos(angulo), math.sin(angulo));
      canvas.drawLine(
        centro + dir * radio * (0.35 + 0.5 * progreso),
        centro + dir * radio * (0.5 + 0.5 * progreso),
        pintura,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorDestello old) =>
      old.progreso != progreso || old.color != color;
}
