import 'package:app_estudiantes/models/estudiante.dart';

var _id = 0;

/// Un estudiante de prueba; solo importan la carrera, el semestre y el
/// promedio.
Estudiante est(String carrera, int semestre, {double promedio = 4, int? id}) =>
    Estudiante(
      id: id ?? ++_id,
      nombre: 'N$_id',
      apellido: 'A',
      edad: 20,
      carrera: carrera,
      semestre: semestre,
      promedio: promedio,
      ciudad: 'Bogotá',
      horasEstudio: 10,
      asistencia: 90,
    );
