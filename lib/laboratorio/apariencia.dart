import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';

/// Estado de ánimo del búho guía.
enum AnimoBuho { atento, pensando, preocupado, contento, celebrando }

/// Cómo se dibujan el búho y el medidor de riesgo.
///
/// Las pantallas solo usan esta interfaz: para cambiar a animaciones de Rive
/// (Fase 7) basta con otra implementación en [aparienciaLaboratorioProvider].
/// Quien implemente debe respetar "reducir movimiento"
/// (`MediaQuery.disableAnimationsOf`) y no animar nunca el texto.
abstract class AparienciaLaboratorio {
  const AparienciaLaboratorio();

  /// Medidor del riesgo estimado. [probabilidad] y [objetivo] entre 0 y 1.
  Widget medidor({required double probabilidad, required double objetivo});

  /// El búho, con la expresión de [animo].
  Widget buho({required AnimoBuho animo, double tamano = 64});
}

final aparienciaLaboratorioProvider = Provider<AparienciaLaboratorio>(
  (ref) => const AparienciaFlutter(),
);

/// Búho y medidor dibujados con CustomPainter.
class AparienciaFlutter extends AparienciaLaboratorio {
  const AparienciaFlutter();

  @override
  Widget medidor({required double probabilidad, required double objetivo}) =>
      MedidorRiesgo(probabilidad: probabilidad, objetivo: objetivo);

  @override
  Widget buho({required AnimoBuho animo, double tamano = 64}) =>
      Buho(animo: animo, tamano: tamano);
}

// --- Medidor ------------------------------------------------------------------

/// Semicírculo de 0 a 100 %: verde por debajo del objetivo, rojo por encima.
/// Solo la aguja se mueve (400 ms); la cifra cambia al instante.
class MedidorRiesgo extends StatelessWidget {
  const MedidorRiesgo({
    super.key,
    required this.probabilidad,
    required this.objetivo,
  });

  final double probabilidad;
  final double objetivo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estado = ColoresEstado.of(context);
    final porcentaje = (probabilidad * 100).round();
    final enRiesgo = probabilidad >= objetivo;
    return Semantics(
      container: true,
      label:
          'Riesgo estimado por el modelo: $porcentaje %. '
          'El objetivo es bajarlo de ${(objetivo * 100).round()} %.',
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 2,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: probabilidad),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (context, aguja, _) => CustomPaint(
            painter: _PintorMedidor(
              aguja: aguja,
              objetivo: objetivo,
              ok: estado.ok,
              riesgo: estado.riesgo,
              colorAguja: tema.colorScheme.onSurface,
              fondo: tema.colorScheme.surfaceContainerHighest,
            ),
            child: Align(
              alignment: const Alignment(0, 0.95),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$porcentaje\u00A0%',
                    key: const Key('porcentaje-medidor'),
                    style: tema.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: enRiesgo ? estado.riesgo : estado.ok,
                    ),
                  ),
                  Text(
                    'riesgo según el modelo',
                    style: tema.textTheme.labelSmall?.copyWith(
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
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

class _PintorMedidor extends CustomPainter {
  _PintorMedidor({
    required this.aguja,
    required this.objetivo,
    required this.ok,
    required this.riesgo,
    required this.colorAguja,
    required this.fondo,
  });

  final double aguja;
  final double objetivo;
  final Color ok;
  final Color riesgo;
  final Color colorAguja;
  final Color fondo;

  @override
  void paint(Canvas canvas, Size size) {
    final grosor = size.height * 0.16;
    final centro = Offset(size.width / 2, size.height - 4);
    final radio = math.min(size.width / 2, size.height) - grosor / 2 - 4;
    final rect = Rect.fromCircle(center: centro, radius: radio);
    Paint arco(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..color = c;

    // 0 % a la izquierda (π) y 100 % a la derecha (2π).
    canvas
      ..drawArc(rect, math.pi, math.pi, false, arco(fondo))
      ..drawArc(
        rect,
        math.pi,
        math.pi * objetivo,
        false,
        arco(ok.withValues(alpha: 0.55)),
      )
      ..drawArc(
        rect,
        math.pi + math.pi * objetivo,
        math.pi * (1 - objetivo),
        false,
        arco(riesgo.withValues(alpha: 0.55)),
      );

    // Marca del objetivo.
    final angObjetivo = math.pi + math.pi * objetivo;
    final dirObjetivo = Offset(math.cos(angObjetivo), math.sin(angObjetivo));
    canvas.drawLine(
      centro + dirObjetivo * (radio - grosor / 2 - 2),
      centro + dirObjetivo * (radio + grosor / 2 + 2),
      Paint()
        ..color = colorAguja
        ..strokeWidth = 2,
    );

    // Aguja.
    final ang = math.pi + math.pi * aguja.clamp(0, 1);
    final punta = centro + Offset(math.cos(ang), math.sin(ang)) * (radio - 6);
    final pintura = Paint()
      ..color = colorAguja
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      centro + Offset(math.cos(ang), math.sin(ang)) * radio * 0.45,
      punta,
      pintura,
    );
  }

  @override
  bool shouldRepaint(_PintorMedidor old) =>
      old.aguja != aguja ||
      old.objetivo != objetivo ||
      old.ok != ok ||
      old.riesgo != riesgo ||
      old.colorAguja != colorAguja ||
      old.fondo != fondo;
}

// --- Búho ---------------------------------------------------------------------

/// El búho guía. Cambia de expresión con un fundido corto (150 ms; ninguno
/// con "reducir movimiento"): no es la animación protagonista.
class Buho extends StatelessWidget {
  const Buho({super.key, required this.animo, this.tamano = 64});

  final AnimoBuho animo;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'Búho guía (${animo.name})',
      image: true,
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        child: CustomPaint(
          key: ValueKey(animo),
          size: Size.square(tamano),
          painter: _PintorBuho(
            animo: animo,
            plumas: Color.lerp(c.primary, const Color(0xFF8D6E63), 0.6)!,
            barriga: Color.lerp(c.primaryContainer, Colors.white, 0.3)!,
            ojo: Colors.white,
            pupila: const Color(0xFF212121),
            pico: const Color(0xFFF2A33A),
          ),
        ),
      ),
    );
  }
}

class _PintorBuho extends CustomPainter {
  _PintorBuho({
    required this.animo,
    required this.plumas,
    required this.barriga,
    required this.ojo,
    required this.pupila,
    required this.pico,
  });

  final AnimoBuho animo;
  final Color plumas;
  final Color barriga;
  final Color ojo;
  final Color pupila;
  final Color pico;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    Paint relleno(Color c) => Paint()..color = c;

    // Orejas (penachos).
    final orejas = Path()
      ..moveTo(w * 0.18, h * 0.32)
      ..lineTo(w * 0.22, h * 0.06)
      ..lineTo(w * 0.40, h * 0.24)
      ..moveTo(w * 0.82, h * 0.32)
      ..lineTo(w * 0.78, h * 0.06)
      ..lineTo(w * 0.60, h * 0.24);
    canvas.drawPath(orejas, relleno(plumas));

    // Alas: levantadas al celebrar.
    final arriba = animo == AnimoBuho.celebrando;
    for (final lado in [-1.0, 1.0]) {
      final x = w / 2 + lado * w * 0.40;
      canvas.save();
      canvas.translate(x, h * 0.62);
      canvas.rotate(lado * (arriba ? -0.9 : 0.15));
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: w * 0.18, height: h * 0.40),
        relleno(Color.lerp(plumas, Colors.black, 0.15)!),
      );
      canvas.restore();
    }

    // Cuerpo y barriga.
    canvas
      ..drawOval(
        Rect.fromLTWH(w * 0.14, h * 0.14, w * 0.72, h * 0.84),
        relleno(plumas),
      )
      ..drawOval(
        Rect.fromLTWH(w * 0.30, h * 0.52, w * 0.40, h * 0.42),
        relleno(barriga),
      );

    // Ojos.
    final radioOjo = w * 0.15;
    final ojos = [Offset(w * 0.36, h * 0.40), Offset(w * 0.64, h * 0.40)];
    final felices =
        animo == AnimoBuho.contento || animo == AnimoBuho.celebrando;
    for (final (i, centro) in ojos.indexed) {
      canvas.drawCircle(centro, radioOjo, relleno(ojo));
      if (felices) {
        // Ojos cerrados de alegría: ^ ^
        canvas.drawArc(
          Rect.fromCircle(
            center: centro + Offset(0, radioOjo * 0.3),
            radius: radioOjo * 0.55,
          ),
          math.pi * 1.1,
          math.pi * 0.8,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.035
            ..strokeCap = StrokeCap.round
            ..color = pupila,
        );
        continue;
      }
      final mira = animo == AnimoBuho.pensando
          ? Offset(radioOjo * 0.3, -radioOjo * 0.35)
          : Offset.zero;
      canvas.drawCircle(centro + mira, radioOjo * 0.48, relleno(pupila));
      canvas.drawCircle(
        centro + mira + Offset(-radioOjo * 0.15, -radioOjo * 0.18),
        radioOjo * 0.13,
        relleno(ojo),
      );
      // Cejas: de preocupación (subidas por el centro) o de duda (una sola).
      final ceja = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.04
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(plumas, Colors.black, 0.45)!;
      final y = centro.dy - radioOjo * 1.25;
      if (animo == AnimoBuho.preocupado) {
        final interior = i == 0 ? radioOjo * 0.8 : -radioOjo * 0.8;
        canvas.drawLine(
          Offset(centro.dx - interior, y + radioOjo * 0.25),
          Offset(centro.dx + interior, y - radioOjo * 0.15),
          ceja,
        );
      } else if (animo == AnimoBuho.pensando && i == 1) {
        canvas.drawLine(
          Offset(centro.dx - radioOjo * 0.8, y - radioOjo * 0.1),
          Offset(centro.dx + radioOjo * 0.8, y - radioOjo * 0.3),
          ceja,
        );
      }
    }

    // Pico.
    final picoPath = Path()
      ..moveTo(w * 0.45, h * 0.52)
      ..lineTo(w * 0.55, h * 0.52)
      ..lineTo(w * 0.50, h * 0.62)
      ..close();
    canvas.drawPath(picoPath, relleno(pico));
  }

  @override
  bool shouldRepaint(_PintorBuho old) =>
      old.animo != animo || old.plumas != plumas || old.barriga != barriga;
}
