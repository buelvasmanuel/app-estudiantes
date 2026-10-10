import 'json_utils.dart';

/// Un punto de una estadística: `{"etiqueta": "Medicina", "valor": 30}`.
///
/// [valor] es `num` porque los conteos llegan como int (30) y los promedios
/// y porcentajes como double (3.46, 33.33).
class Estadistica {
  const Estadistica({required this.etiqueta, required this.valor});

  final String etiqueta;
  final num valor;

  factory Estadistica.fromJson(Object? json) {
    final m = comoMapa(json, 'estadística');
    return Estadistica(
      etiqueta: leerString(m, 'etiqueta'),
      valor: leerNum(m, 'valor'),
    );
  }

  static List<Estadistica> listaFromJson(Object? json) =>
      comoLista(json).map(Estadistica.fromJson).toList();
}

/// Qué mide cada estadística, para saber cómo formatear su valor.
enum Unidad { conteo, promedio, porcentaje }

/// Los 6 tipos de `GET /estudiantes/estadisticas/{tipo}`.
enum TipoEstadistica {
  porCarrera(
    ruta: 'por-carrera',
    nombre: 'Estudiantes por carrera',
    descripcion: 'Cantidad de estudiantes inscritos en cada carrera.',
    ejeX: 'Carrera',
    grupo: 'carrera',
    unidad: Unidad.conteo,
  ),
  porEdad(
    ruta: 'por-edad',
    nombre: 'Estudiantes por edad',
    descripcion: 'Cuántos estudiantes hay de cada edad.',
    ejeX: 'Edad (años)',
    grupo: 'edad',
    unidad: Unidad.conteo,
  ),
  porSemestre(
    ruta: 'por-semestre',
    nombre: 'Estudiantes por semestre',
    descripcion: 'Cuántos estudiantes cursan cada semestre.',
    ejeX: 'Semestre',
    grupo: 'semestre',
    unidad: Unidad.conteo,
  ),
  porCiudad(
    ruta: 'por-ciudad',
    nombre: 'Estudiantes por ciudad',
    descripcion: 'Las 10 ciudades con más estudiantes.',
    ejeX: 'Ciudad',
    grupo: 'ciudad',
    unidad: Unidad.conteo,
  ),
  promedioPorCarrera(
    ruta: 'promedio-por-carrera',
    nombre: 'Promedio por carrera',
    descripcion:
        'Promedio de notas (0 a 5) de cada carrera. La línea roja '
        'discontinua marca el umbral de riesgo (3.0).',
    ejeX: 'Carrera',
    grupo: 'carrera',
    unidad: Unidad.promedio,
  ),
  riesgoPorCarrera(
    ruta: 'riesgo-por-carrera',
    nombre: 'Riesgo por carrera',
    descripcion: 'Porcentaje de estudiantes con promedio menor que 3.0.',
    ejeX: 'Carrera',
    grupo: 'carrera',
    unidad: Unidad.porcentaje,
  );

  const TipoEstadistica({
    required this.ruta,
    required this.nombre,
    required this.descripcion,
    required this.ejeX,
    required this.grupo,
    required this.unidad,
  });

  final String ruta;
  final String nombre;
  final String descripcion;
  final String ejeX;

  /// Cada barra es una... ("carrera", "edad"...). Para textos del resumen.
  final String grupo;
  final Unidad unidad;

  /// Etiqueta legible fuera de la gráfica: "20" → "edad 20".
  String describir(String etiqueta) =>
      num.tryParse(etiqueta) == null ? etiqueta : '$grupo $etiqueta';

  /// Texto del valor que se pinta encima de cada barra.
  String formatear(num valor) => switch (unidad) {
    Unidad.conteo => valor.round().toString(),
    Unidad.promedio => valor.toStringAsFixed(2),
    Unidad.porcentaje => '${valor.toStringAsFixed(1)}%',
  };

  /// Techo del eje Y. Se deja aire (~20 %) para que quepa el valor encima
  /// de la barra más alta. Los promedios van en la escala fija 0-5.
  double maximoEjeY(Iterable<num> valores) {
    if (unidad == Unidad.promedio) return 5.4;
    final maximo = valores.fold<num>(0, (a, b) => b > a ? b : a).toDouble();
    if (maximo <= 0) return 1;
    final conAire = maximo * 1.2;
    return unidad == Unidad.porcentaje && conAire > 100 ? 100 : conAire;
  }
}
