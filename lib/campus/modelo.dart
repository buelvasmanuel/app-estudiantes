import '../models/estudiante.dart';

/// Un edificio del campus: una carrera. Cada piso es un semestre y cada
/// ventana, un estudiante.
class Edificio {
  Edificio._(this.carrera, this.pisos);

  /// Agrupa [estudiantes] (todos de [carrera]) por semestre, ordenados por
  /// id dentro de cada piso: el orden real, sin agrupar los que están en
  /// riesgo (no se inventa ningún patrón).
  factory Edificio.desde(String carrera, Iterable<Estudiante> estudiantes) {
    final pisos = List.generate(Campus.semestres, (_) => <Estudiante>[]);
    for (final e in estudiantes) {
      pisos[(e.semestre - 1).clamp(0, Campus.semestres - 1)].add(e);
    }
    for (final piso in pisos) {
      piso.sort((a, b) => a.id.compareTo(b.id));
    }
    return Edificio._(carrera, pisos);
  }

  final String carrera;

  /// `pisos[0]` es el 1.er semestre (abajo); `pisos[9]`, el 10.º (arriba).
  final List<List<Estudiante>> pisos;

  late final int total = pisos.fold(0, (s, p) => s + p.length);
  late final int enRiesgo = pisos.fold(
    0,
    (s, p) => s + p.where((e) => e.enRiesgo).length,
  );

  /// Ventanas por piso: las del piso más lleno de esta carrera.
  late final int ancho = pisos.fold(1, (m, p) => p.length > m ? p.length : m);

  double get porcentajeRiesgo => total == 0 ? 0 : 100 * enRiesgo / total;

  double get promedioMedio => total == 0
      ? 0
      : pisos.expand((p) => p).fold<double>(0, (s, e) => s + e.promedio) /
            total;

  /// Estudiantes por semestre, de 1.º a 10.º.
  List<int> get porSemestre => [for (final p in pisos) p.length];
}

/// Todos los edificios, de más a menos estudiantes (empate: por nombre).
class Campus {
  Campus._(this.edificios);

  factory Campus.desde(List<Estudiante> estudiantes) {
    final porCarrera = <String, List<Estudiante>>{};
    for (final e in estudiantes) {
      (porCarrera[e.carrera] ??= []).add(e);
    }
    final edificios =
        [
          for (final MapEntry(:key, :value) in porCarrera.entries)
            Edificio.desde(key, value),
        ]..sort((a, b) {
          final porTotal = b.total.compareTo(a.total);
          return porTotal != 0 ? porTotal : a.carrera.compareTo(b.carrera);
        });
    return Campus._(edificios);
  }

  /// Todos los edificios tienen 10 pisos (semestres 1 a 10, como valida la
  /// API): así los pisos quedan alineados y se comparan de un vistazo.
  static const semestres = 10;

  final List<Edificio> edificios;

  late final int total = edificios.fold(0, (s, e) => s + e.total);
  late final int enRiesgo = edificios.fold(0, (s, e) => s + e.enRiesgo);

  Edificio? edificioDe(Estudiante estudiante) =>
      edificios.where((e) => e.carrera == estudiante.carrera).firstOrNull;
}
