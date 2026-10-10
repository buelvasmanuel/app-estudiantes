import 'json_utils.dart';

/// Un estudiante tal como lo devuelve `GET /estudiantes/`.
class Estudiante {
  const Estudiante({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.edad,
    required this.carrera,
    required this.semestre,
    required this.promedio,
    required this.ciudad,
    required this.horasEstudio,
    required this.asistencia,
  });

  /// Por debajo de este promedio el estudiante está en riesgo académico
  /// (el mismo umbral que usa la API para entrenar el modelo).
  static const double umbralRiesgo = 3.0;

  final int id;
  final String nombre;
  final String apellido;
  final int edad;
  final String carrera;
  final int semestre;
  final double promedio;
  final String ciudad;
  final int horasEstudio;
  final int asistencia;

  /// La API envía `promedio` como texto ("3.95") porque en Python es un
  /// Decimal; [leerNum] acepta tanto "3.95" como 3.95.
  factory Estudiante.fromJson(Object? json) {
    final m = comoMapa(json, 'estudiante');
    return Estudiante(
      id: leerInt(m, 'id'),
      nombre: leerString(m, 'nombre'),
      apellido: leerString(m, 'apellido'),
      edad: leerInt(m, 'edad'),
      carrera: leerString(m, 'carrera'),
      semestre: leerInt(m, 'semestre'),
      promedio: leerNum(m, 'promedio').toDouble(),
      ciudad: leerString(m, 'ciudad'),
      horasEstudio: leerInt(m, 'horas_estudio'),
      asistencia: leerInt(m, 'asistencia'),
    );
  }

  static List<Estudiante> listaFromJson(Object? json) =>
      comoLista(json).map(Estudiante.fromJson).toList();

  String get nombreCompleto => '$nombre $apellido';

  String get iniciales =>
      '${nombre.isEmpty ? '' : nombre[0]}${apellido.isEmpty ? '' : apellido[0]}'
          .toUpperCase();

  bool get enRiesgo => promedio < umbralRiesgo;

  /// Texto en el que busca el buscador (sin tildes ni mayúsculas).
  String get textoBusqueda => normalizar('$nombre $apellido $carrera $ciudad');
}

/// Quita tildes y pasa a minúsculas: así "jose" encuentra a "José".
String normalizar(String texto) {
  const con = 'áéíóúüñ';
  const sin = 'aeiouun';
  final buffer = StringBuffer();
  for (final letra in texto.toLowerCase().split('')) {
    final i = con.indexOf(letra);
    buffer.write(i == -1 ? letra : sin[i]);
  }
  return buffer.toString();
}
