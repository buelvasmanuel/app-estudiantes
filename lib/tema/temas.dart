import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Los dos temas del juego (Fase 6). No hay un claro/oscuro genérico: el
/// jugador elige entre Noche y Expediente (menú de la cuenta, Perfil o el
/// final del tutorial) y se recuerda en el dispositivo.
enum TemaJuego {
  /// Campus nocturno: Fredoka + Nunito, ámbar, cian y lavanda.
  noche('Noche', Icons.nightlight_round),

  /// Expediente de detective: papel y tinta, Courier Prime + Atkinson
  /// Hyperlegible, sellos.
  expediente('Expediente', Icons.folder_outlined);

  const TemaJuego(this.nombre, this.icono);

  final String nombre;
  final IconData icono;

  ThemeData get datos => switch (this) {
    noche => _temas.noche,
    expediente => _temas.expediente,
  };

  /// La primera vez: oscuro → Noche, claro → Expediente.
  static TemaJuego delSistema(Brightness brillo) =>
      brillo == Brightness.dark ? noche : expediente;
}

// Se construyen una sola vez.
final _temas = (noche: _temaNoche(), expediente: _temaExpediente());

enum FondoCampus { liso, noche, papel }

/// Lo que la identidad cambia y Material no cubre.
@immutable
class EstiloJuego extends ThemeExtension<EstiloJuego> {
  const EstiloJuego({
    this.fondoCampus = FondoCampus.liso,
    this.ventanasConBrillo = false,
    this.sellos = false,
    this.contornoTinta = false,
  });

  final FondoCampus fondoCampus;

  /// Las ventanas encendidas brillan un poco (noche).
  final bool ventanasConBrillo;

  /// Sellos de expediente ("RESUELTO") en los casos.
  final bool sellos;

  /// Edificios con contorno de tinta marcado (papel).
  final bool contornoTinta;

  static EstiloJuego of(BuildContext context) =>
      Theme.of(context).extension<EstiloJuego>() ?? const EstiloJuego();

  @override
  EstiloJuego copyWith() => this;

  @override
  EstiloJuego lerp(EstiloJuego? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

// --- Opción A: Campus de noche ----------------------------------------------

const _nocheFondo = Color(0xFF151A33);
const _nocheAmbar = Color(0xFFFFC857);
const _nocheCian = Color(0xFF7FDBFF);
const _nocheLavanda = Color(0xFFC3A6FF);
const _nocheTexto = Color(0xFFEEF0FF);
const _nocheTextoSuave = Color(0xFFB7BCD9);

ThemeData _temaNoche() {
  const esquema = ColorScheme(
    brightness: Brightness.dark,
    primary: _nocheAmbar,
    onPrimary: Color(0xFF2B1D00),
    primaryContainer: Color(0xFF4A3A00),
    onPrimaryContainer: Color(0xFFFFE6A6),
    secondary: _nocheCian,
    onSecondary: Color(0xFF00202B),
    secondaryContainer: Color(0xFF12394A),
    onSecondaryContainer: Color(0xFFC9F1FF),
    tertiary: _nocheLavanda,
    onTertiary: Color(0xFF241447),
    tertiaryContainer: Color(0xFF3B2D66),
    onTertiaryContainer: Color(0xFFE6DAFF),
    error: Color(0xFFFF8A80),
    onError: Color(0xFF3A0000),
    surface: _nocheFondo,
    onSurface: _nocheTexto,
    onSurfaceVariant: _nocheTextoSuave,
    surfaceContainerLowest: Color(0xFF10142A),
    surfaceContainerLow: Color(0xFF1A1F3B),
    surfaceContainer: Color(0xFF20264A),
    surfaceContainerHigh: Color(0xFF272E57),
    surfaceContainerHighest: Color(0xFF303865),
    outline: Color(0xFF6B73A3),
    outlineVariant: Color(0xFF3A416B),
  );
  return _base(
    esquema,
    titulos: 'Fredoka',
    cuerpo: 'Nunito',
    estado: ColoresEstado.noche,
    estilo: const EstiloJuego(
      fondoCampus: FondoCampus.noche,
      ventanasConBrillo: true,
    ),
    radio: 20,
  );
}

// --- Opción B: Expediente de detective --------------------------------------

ThemeData _temaExpediente() {
  const esquema = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF1F4E8C), // tinta azul
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFD6E4F7),
    onPrimaryContainer: Color(0xFF0B2545),
    secondary: Color(0xFF8A5A00), // mostaza de carpeta
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFF6E3B4),
    onSecondaryContainer: Color(0xFF3D2A00),
    tertiary: Color(0xFF6E4396), // lacre
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFEADCF7),
    onTertiaryContainer: Color(0xFF2A0E45),
    error: Color(0xFFB3261E),
    onError: Colors.white,
    surface: Color(0xFFF4EBD6), // papel
    onSurface: Color(0xFF2A2622), // tinta
    onSurfaceVariant: Color(0xFF5E554A),
    surfaceContainerLowest: Color(0xFFFFFBF2),
    surfaceContainerLow: Color(0xFFFBF4E3),
    surfaceContainer: Color(0xFFF7EEDA),
    surfaceContainerHigh: Color(0xFFEFE3C8),
    surfaceContainerHighest: Color(0xFFE8D9B8),
    outline: Color(0xFF8C7B62),
    outlineVariant: Color(0xFFCDBB9A),
  );
  return _base(
    esquema,
    titulos: 'CourierPrime',
    cuerpo: 'AtkinsonHyperlegible',
    estado: ColoresEstado.expediente,
    estilo: const EstiloJuego(
      fondoCampus: FondoCampus.papel,
      sellos: true,
      contornoTinta: true,
    ),
    radio: 6,
  );
}

ThemeData _base(
  ColorScheme esquema, {
  required String titulos,
  required String cuerpo,
  required ColoresEstado estado,
  required EstiloJuego estilo,
  required double radio,
}) {
  final base = ThemeData(colorScheme: esquema, fontFamily: cuerpo);
  final t = base.textTheme;
  TextStyle? titulo(TextStyle? s, FontWeight peso) =>
      s?.copyWith(fontFamily: titulos, fontWeight: peso);
  return base.copyWith(
    scaffoldBackgroundColor: esquema.surface,
    textTheme: t.copyWith(
      displaySmall: titulo(t.displaySmall, FontWeight.w700),
      headlineLarge: titulo(t.headlineLarge, FontWeight.w700),
      headlineMedium: titulo(t.headlineMedium, FontWeight.w700),
      headlineSmall: titulo(t.headlineSmall, FontWeight.w700),
      titleLarge: titulo(t.titleLarge, FontWeight.w600),
      titleMedium: titulo(t.titleMedium, FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: esquema.surface,
      titleTextStyle: titulo(
        t.titleLarge,
        FontWeight.w700,
      )?.copyWith(color: esquema.onSurface, fontSize: 24),
    ),
    extensions: [estado, estilo],
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radio)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(math.min(radio, 12)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

/// Fondo del Campus detrás del juego (estático: nada se mueve "porque sí").
class PintorFondoCampus extends CustomPainter {
  const PintorFondoCampus(this.fondo, this.esquema, {this.conLuna = true});

  final FondoCampus fondo;
  final ColorScheme esquema;

  /// Sin luna donde haya botones en la esquina superior derecha.
  final bool conLuna;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    switch (fondo) {
      case FondoCampus.liso:
        canvas.drawRect(rect, Paint()..color = esquema.surface);
      case FondoCampus.noche:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A0E22), Color(0xFF1B2350), Color(0xFF241F4A)],
            ).createShader(rect),
        );
        // Estrellas fijas (misma semilla: siempre en el mismo sitio).
        final azar = math.Random(7);
        for (var i = 0; i < 70; i++) {
          final p = Offset(
            azar.nextDouble() * size.width,
            azar.nextDouble() * size.height * 0.8,
          );
          canvas.drawCircle(
            p,
            azar.nextDouble() * 1.2 + 0.4,
            Paint()
              ..color = Colors.white.withValues(
                alpha: azar.nextDouble() * 0.5 + 0.2,
              ),
          );
        }
        // Luna creciente.
        if (!conLuna) return;
        final luna = Offset(size.width - 48, 40);
        canvas
          ..drawCircle(luna, 18, Paint()..color = const Color(0xFFFFF1C1))
          ..drawCircle(
            luna + const Offset(8, -5),
            16,
            Paint()..color = const Color(0xFF0E1330),
          );
      case FondoCampus.papel:
        canvas.drawRect(rect, Paint()..color = esquema.surface);
        // Cuadrícula de plano, muy suave.
        final linea = Paint()
          ..color = esquema.primary.withValues(alpha: 0.07)
          ..strokeWidth = 1;
        for (var x = 0.0; x < size.width; x += 24) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), linea);
        }
        for (var y = 0.0; y < size.height; y += 24) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linea);
        }
    }
  }

  @override
  bool shouldRepaint(PintorFondoCampus old) =>
      old.fondo != fondo || old.esquema != esquema || old.conLuna != conLuna;
}

/// Sello de expediente (solo en la identidad "expediente").
class Sello extends StatelessWidget {
  const Sello({super.key, required this.texto, required this.color});

  final String texto;
  final Color color;

  /// Giro del sello (radianes). Quien lo coloca debe dejarle margen: girado
  /// ocupa más alto que su caja (ver caso_juego_screen).
  static const angulo = -0.12;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angulo,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: 'CourierPrime',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          letterSpacing: 2,
          color: color,
        ),
      ),
    ),
  );
}
