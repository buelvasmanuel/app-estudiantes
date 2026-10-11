import 'package:flutter/material.dart';

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

  /// Tema Noche: rojo y verde luminosos sobre azul noche.
  static const noche = ColoresEstado(
    riesgo: Color(0xFFFF7B7B),
    onRiesgo: Color(0xFF3A0000),
    riesgoContenedor: Color(0xFF5C1A1F),
    onRiesgoContenedor: Color(0xFFFFD9D9),
    ok: Color(0xFF6EE7A8),
    onOk: Color(0xFF00331A),
    okContenedor: Color(0xFF114D33),
    onOkContenedor: Color(0xFFC8FFE2),
  );

  /// Tema Expediente: tinta roja y verde sobre papel.
  static const expediente = ColoresEstado(
    riesgo: Color(0xFFB3261E),
    onRiesgo: Colors.white,
    riesgoContenedor: Color(0xFFF8D7D2),
    onRiesgoContenedor: Color(0xFF5C0F0A),
    ok: Color(0xFF2E7D32),
    onOk: Colors.white,
    okContenedor: Color(0xFFD5EDD3),
    onOkContenedor: Color(0xFF10391A),
  );

  static ColoresEstado of(BuildContext context) =>
      Theme.of(context).extension<ColoresEstado>() ?? expediente;

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
