import 'json_utils.dart';

/// Datos que se envían a `POST /prediccion/riesgo`.
///
/// No lleva el promedio: es justo lo que el modelo intenta anticipar.
class EntradaPrediccion {
  const EntradaPrediccion({
    required this.horasEstudio,
    required this.asistencia,
    required this.semestre,
    required this.edad,
    required this.carrera,
  });

  final int horasEstudio;
  final int asistencia;
  final int semestre;
  final int edad;
  final String carrera;

  /// Las claves van en snake_case, como las espera la API (Python).
  Map<String, Object?> toJson() => {
    'horas_estudio': horasEstudio,
    'asistencia': asistencia,
    'semestre': semestre,
    'edad': edad,
    'carrera': carrera,
  };

  @override
  bool operator ==(Object other) =>
      other is EntradaPrediccion &&
      other.horasEstudio == horasEstudio &&
      other.asistencia == asistencia &&
      other.semestre == semestre &&
      other.edad == edad &&
      other.carrera == carrera;

  @override
  int get hashCode =>
      Object.hash(horasEstudio, asistencia, semestre, edad, carrera);
}

/// Respuesta: `{"en_riesgo": true, "probabilidad": 0.98, "modelo": "..."}`.
class ResultadoPrediccion {
  const ResultadoPrediccion({
    required this.enRiesgo,
    required this.probabilidad,
    required this.modelo,
  });

  final bool enRiesgo;

  /// Entre 0 y 1. Es `num`: la API puede mandar 1 (int) o 0.98 (double).
  final num probabilidad;
  final String modelo;

  factory ResultadoPrediccion.fromJson(Object? json) {
    final m = comoMapa(json, 'resultado de predicción');
    return ResultadoPrediccion(
      enRiesgo: leerBool(m, 'en_riesgo'),
      probabilidad: leerNum(m, 'probabilidad'),
      modelo: leerString(m, 'modelo'),
    );
  }

  /// Probabilidad en porcentaje entero: 0.98 → 98.
  int get porcentaje => (probabilidad * 100).round().clamp(0, 100);
}

/// Lo que devuelve `GET /prediccion/metricas` y nos interesa mostrar.
///
/// Solo `modelo` y `carreras_validas` son obligatorios: el resto es
/// informativo y, si falta, la pantalla simplemente no lo muestra.
class MetricasModelo {
  const MetricasModelo({
    required this.modelo,
    required this.carrerasValidas,
    this.criterio,
    this.entrenado,
    this.totalDatos,
    this.porcentajeEnRiesgo,
    this.accuracy,
    this.precision,
    this.recall,
    this.f2,
    this.variablesInfluyentes = const [],
  });

  final String modelo;
  final List<String> carrerasValidas;
  final String? criterio;
  final DateTime? entrenado;
  final int? totalDatos;
  final num? porcentajeEnRiesgo;
  final num? accuracy;
  final num? precision;
  final num? recall;
  final num? f2;

  /// Nombres de las variables ordenadas de más a menos influyente.
  final List<String> variablesInfluyentes;

  factory MetricasModelo.fromJson(Object? json) {
    final m = comoMapa(json, 'métricas');
    final carreras = comoLista(m['carreras_validas'], 'lista de carreras')
        .map((c) => c is String ? c : throw FormatException('Carrera', c))
        .toList();

    final datos = m['datos'] is Map<String, Object?>
        ? m['datos']! as Map<String, Object?>
        : const <String, Object?>{};
    final prueba = m['metricas_prueba'] is Map<String, Object?>
        ? m['metricas_prueba']! as Map<String, Object?>
        : const <String, Object?>{};

    // "importancias": {"asistencia": -2.07, "horas_estudio": -1.56, ...}
    // El signo indica la dirección; lo que importa para ordenar es el tamaño.
    final importancias = m['importancias'] is Map<String, Object?>
        ? (m['importancias']! as Map<String, Object?>).entries
              .where((e) => e.value is num)
              .toList()
        : <MapEntry<String, Object?>>[];
    importancias.sort(
      (a, b) => (b.value! as num).abs().compareTo((a.value! as num).abs()),
    );

    final entrenado = m['entrenado'];
    return MetricasModelo(
      modelo: leerString(m, 'modelo'),
      carrerasValidas: carreras,
      criterio: m['criterio_seleccion'] is String
          ? m['criterio_seleccion']! as String
          : null,
      entrenado: entrenado is String ? DateTime.tryParse(entrenado) : null,
      totalDatos: leerNumOpcional(datos, 'total')?.toInt(),
      porcentajeEnRiesgo: leerNumOpcional(datos, 'porcentaje_en_riesgo'),
      accuracy: leerNumOpcional(prueba, 'accuracy'),
      precision: leerNumOpcional(prueba, 'precision'),
      recall: leerNumOpcional(prueba, 'recall'),
      f2: leerNumOpcional(prueba, 'f2'),
      variablesInfluyentes: [for (final e in importancias) e.key],
    );
  }
}
