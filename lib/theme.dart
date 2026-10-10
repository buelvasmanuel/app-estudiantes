import 'package:flutter/material.dart';

/// Tema Material 3 de la app (claro y oscuro a partir de un color semilla).
abstract final class AppTheme {
  static const Color _semilla = Color(0xFF3F51B5); // índigo "académico"

  static ThemeData get claro => _tema(Brightness.light);
  static ThemeData get oscuro => _tema(Brightness.dark);

  static ThemeData _tema(Brightness brillo) {
    final colores = ColorScheme.fromSeed(
      seedColor: _semilla,
      brightness: brillo,
    );
    return ThemeData(
      colorScheme: colores,
      extensions: [
        brillo == Brightness.light ? ColoresEstado.claro : ColoresEstado.oscuro,
      ],
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}

/// Colores con significado (riesgo / sin riesgo) que el ColorScheme no trae:
/// `error` existe, pero no hay un "verde de éxito". Con un ThemeExtension los
/// tenemos en ambos temas y se leen con `ColoresEstado.of(context)`.
@immutable
class ColoresEstado extends ThemeExtension<ColoresEstado> {
  const ColoresEstado({
    required this.riesgo,
    required this.onRiesgo,
    required this.riesgoContenedor,
    required this.onRiesgoContenedor,
    required this.ok,
    required this.onOk,
    required this.okContenedor,
    required this.onOkContenedor,
  });

  final Color riesgo;
  final Color onRiesgo;
  final Color riesgoContenedor;
  final Color onRiesgoContenedor;
  final Color ok;
  final Color onOk;
  final Color okContenedor;
  final Color onOkContenedor;

  static const claro = ColoresEstado(
    riesgo: Color(0xFFBA1A1A),
    onRiesgo: Colors.white,
    riesgoContenedor: Color(0xFFFFDAD6),
    onRiesgoContenedor: Color(0xFF410002),
    ok: Color(0xFF1B6D2F),
    onOk: Colors.white,
    okContenedor: Color(0xFFA6F4AC),
    onOkContenedor: Color(0xFF002107),
  );

  static const oscuro = ColoresEstado(
    riesgo: Color(0xFFFFB4AB),
    onRiesgo: Color(0xFF690005),
    riesgoContenedor: Color(0xFF93000A),
    onRiesgoContenedor: Color(0xFFFFDAD6),
    ok: Color(0xFF8BD892),
    onOk: Color(0xFF00390F),
    okContenedor: Color(0xFF00531A),
    onOkContenedor: Color(0xFFA6F4AC),
  );

  static ColoresEstado of(BuildContext context) =>
      Theme.of(context).extension<ColoresEstado>() ?? claro;

  @override
  ColoresEstado copyWith({
    Color? riesgo,
    Color? onRiesgo,
    Color? riesgoContenedor,
    Color? onRiesgoContenedor,
    Color? ok,
    Color? onOk,
    Color? okContenedor,
    Color? onOkContenedor,
  }) => ColoresEstado(
    riesgo: riesgo ?? this.riesgo,
    onRiesgo: onRiesgo ?? this.onRiesgo,
    riesgoContenedor: riesgoContenedor ?? this.riesgoContenedor,
    onRiesgoContenedor: onRiesgoContenedor ?? this.onRiesgoContenedor,
    ok: ok ?? this.ok,
    onOk: onOk ?? this.onOk,
    okContenedor: okContenedor ?? this.okContenedor,
    onOkContenedor: onOkContenedor ?? this.onOkContenedor,
  );

  @override
  ColoresEstado lerp(ColoresEstado? other, double t) {
    if (other == null) return this;
    return ColoresEstado(
      riesgo: Color.lerp(riesgo, other.riesgo, t)!,
      onRiesgo: Color.lerp(onRiesgo, other.onRiesgo, t)!,
      riesgoContenedor: Color.lerp(
        riesgoContenedor,
        other.riesgoContenedor,
        t,
      )!,
      onRiesgoContenedor: Color.lerp(
        onRiesgoContenedor,
        other.onRiesgoContenedor,
        t,
      )!,
      ok: Color.lerp(ok, other.ok, t)!,
      onOk: Color.lerp(onOk, other.onOk, t)!,
      okContenedor: Color.lerp(okContenedor, other.okContenedor, t)!,
      onOkContenedor: Color.lerp(onOkContenedor, other.onOkContenedor, t)!,
    );
  }
}
