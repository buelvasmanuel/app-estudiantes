// Tipos del Laboratorio de Rescate, tal como los define
// docs/CONTRATO_LABORATORIO.md (repo api-tienda).
import '../juego/modelo.dart';
import '../models/json_utils.dart';
import '../models/prediccion.dart';

/// Un caso de la lista (`GET /laboratorio/casos`).
class CasoResumen {
  const CasoResumen({
    required this.estudianteId,
    required this.nombre,
    required this.apellido,
    required this.carrera,
    required this.semestre,
    required this.probabilidad,
  });

  final int estudianteId;
  final String nombre;
  final String apellido;
  final String carrera;
  final int semestre;
  final double probabilidad;

  String get nombreCompleto => '$nombre $apellido';

  factory CasoResumen.fromJson(Object? json) {
    final m = comoMapa(json, 'caso');
    return CasoResumen(
      estudianteId: leerInt(m, 'estudiante_id'),
      nombre: leerString(m, 'nombre'),
      apellido: leerString(m, 'apellido'),
      carrera: leerString(m, 'carrera'),
      semestre: leerInt(m, 'semestre'),
      probabilidad: leerNum(m, 'probabilidad').toDouble(),
    );
  }
}

class ListaCasos {
  const ListaCasos({
    required this.casos,
    required this.presupuesto,
    required this.objetivo,
  });

  final List<CasoResumen> casos;
  final int presupuesto;
  final double objetivo;

  factory ListaCasos.fromJson(Object? json) {
    final m = comoMapa(json, 'lista de casos');
    return ListaCasos(
      casos: comoLista(m['casos']).map(CasoResumen.fromJson).toList(),
      presupuesto: leerInt(m, 'presupuesto'),
      objetivo: leerNum(m, 'objetivo').toDouble(),
    );
  }
}

/// Una intervención del catálogo (`estudio`, `tutoria`). Los costes y
/// efectos salen de la API, no del código de la app (§5).
class Intervencion {
  const Intervencion({
    required this.codigo,
    required this.nombre,
    required this.fichas,
    required this.variable,
    required this.incremento,
    required this.tope,
    required this.efecto,
  });

  final String codigo;
  final String nombre;
  final int fichas;

  /// `horas_estudio` o `asistencia`.
  final String variable;
  final int incremento;
  final int tope;

  /// Texto para el botón: "+2 h de estudio por semana".
  final String efecto;

  factory Intervencion.fromJson(Object? json) {
    final m = comoMapa(json, 'intervención');
    return Intervencion(
      codigo: leerString(m, 'codigo'),
      nombre: leerString(m, 'nombre'),
      fichas: leerInt(m, 'fichas'),
      variable: leerString(m, 'variable'),
      incremento: leerInt(m, 'incremento'),
      tope: leerInt(m, 'tope'),
      efecto: leerString(m, 'efecto'),
    );
  }
}

/// El estudiante de un caso. Sin promedio: es lo que el modelo predice.
class EstudianteCaso {
  const EstudianteCaso({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.edad,
    required this.carrera,
    required this.semestre,
    required this.horasEstudio,
    required this.asistencia,
  });

  final int id;
  final String nombre;
  final String apellido;
  final int edad;
  final String carrera;
  final int semestre;
  final int horasEstudio;
  final int asistencia;

  String get nombreCompleto => '$nombre $apellido';

  factory EstudianteCaso.fromJson(Object? json) {
    final m = comoMapa(json, 'estudiante del caso');
    return EstudianteCaso(
      id: leerInt(m, 'id'),
      nombre: leerString(m, 'nombre'),
      apellido: leerString(m, 'apellido'),
      edad: leerInt(m, 'edad'),
      carrera: leerString(m, 'carrera'),
      semestre: leerInt(m, 'semestre'),
      horasEstudio: leerInt(m, 'horas_estudio'),
      asistencia: leerInt(m, 'asistencia'),
    );
  }

  /// La entrada del modelo con [horasEstudio] y [asistencia] cambiadas.
  EntradaPrediccion entrada({
    required int horasEstudio,
    required int asistencia,
  }) => EntradaPrediccion(
    horasEstudio: horasEstudio,
    asistencia: asistencia,
    semestre: semestre,
    edad: edad,
    carrera: carrera,
  );
}

enum Efecto {
  sube,
  baja,
  neutro;

  static Efecto desde(String texto) => switch (texto) {
    'sube' => sube,
    'baja' => baja,
    _ => neutro,
  };
}

/// Cuánto empuja una variable el riesgo respecto al estudiante medio.
class Aporte {
  const Aporte({
    required this.variable,
    required this.valor,
    required this.aporte,
    required this.peso,
    required this.efecto,
  });

  final String variable;

  /// Número (horas, edad...) o texto (la carrera).
  final Object valor;

  /// En log-odds: positivo sube el riesgo.
  final double aporte;

  /// Parte del total (0-1): permite decir "pesó el doble que...".
  final double peso;
  final Efecto efecto;

  factory Aporte.fromJson(Object? json) {
    final m = comoMapa(json, 'aporte');
    final valor = m['valor'];
    return Aporte(
      variable: leerString(m, 'variable'),
      valor: valor is num || valor is String
          ? valor!
          : throw FormatException('Campo "valor"', valor),
      aporte: leerNum(m, 'aporte').toDouble(),
      peso: leerNum(m, 'peso').toDouble(),
      efecto: Efecto.desde(leerString(m, 'efecto')),
    );
  }
}

/// `ExplicacionOut`: por qué el modelo da esa probabilidad.
class Explicacion {
  const Explicacion({
    required this.probabilidad,
    required this.enRiesgo,
    required this.probabilidadBase,
    required this.aportes,
    required this.modelo,
    required this.aviso,
  });

  final double probabilidad;
  final bool enRiesgo;

  /// Riesgo del estudiante medio de los datos de entrenamiento.
  final double probabilidadBase;

  /// De mayor a menor influencia.
  final List<Aporte> aportes;
  final String modelo;

  /// "Estimación de un modelo… correlación, no causalidad". Se muestra
  /// siempre.
  final String aviso;

  factory Explicacion.fromJson(Object? json) {
    final m = comoMapa(json, 'explicación');
    final modelo = comoMapa(m['modelo'], 'modelo');
    return Explicacion(
      probabilidad: leerNum(m, 'probabilidad').toDouble(),
      enRiesgo: leerBool(m, 'en_riesgo'),
      probabilidadBase: leerNum(
        comoMapa(m['base'], 'base'),
        'probabilidad',
      ).toDouble(),
      aportes: comoLista(m['aportes']).map(Aporte.fromJson).toList(),
      modelo: leerString(modelo, 'nombre'),
      aviso: leerString(m, 'aviso'),
    );
  }
}

/// `GET /laboratorio/casos/{id}`: todo lo necesario para jugar un caso.
class Caso {
  const Caso({
    required this.estudiante,
    required this.probabilidad,
    required this.presupuesto,
    required this.objetivo,
    required this.intervenciones,
    required this.explicacion,
    required this.aviso,
  });

  final EstudianteCaso estudiante;
  final double probabilidad;
  final int presupuesto;
  final double objetivo;
  final List<Intervencion> intervenciones;
  final Explicacion explicacion;
  final String aviso;

  factory Caso.fromJson(Object? json) {
    final m = comoMapa(json, 'caso');
    return Caso(
      estudiante: EstudianteCaso.fromJson(m['estudiante']),
      probabilidad: leerNum(m, 'probabilidad').toDouble(),
      presupuesto: leerInt(m, 'presupuesto'),
      objetivo: leerNum(m, 'objetivo').toDouble(),
      intervenciones: comoLista(m['intervenciones'])
          .map(Intervencion.fromJson)
          .toList(),
      explicacion: Explicacion.fromJson(m['explicacion']),
      aviso: leerString(m, 'aviso'),
    );
  }
}

/// La mejor combinación posible, que el servidor revela tras el intento.
class SolucionOptima {
  const SolucionOptima({
    required this.porIntervencion,
    required this.fichas,
    required this.probabilidad,
  });

  /// Veces que se usa cada intervención: `{"estudio": 1, "tutoria": 1}`.
  final Map<String, int> porIntervencion;
  final int fichas;
  final double probabilidad;

  factory SolucionOptima.fromJson(Object? json) {
    final m = comoMapa(json, 'solución óptima');
    return SolucionOptima(
      porIntervencion: {
        for (final MapEntry(:key, :value) in m.entries)
          if (key != 'fichas' && key != 'probabilidad' && value is num)
            key: value.toInt(),
      },
      fichas: leerInt(m, 'fichas'),
      probabilidad: leerNum(m, 'probabilidad').toDouble(),
    );
  }
}

/// `POST /laboratorio/casos/{id}/resolver`. Las estrellas las decide el
/// servidor; la app solo las muestra.
class ResultadoRescate {
  const ResultadoRescate({
    required this.logrado,
    required this.estrellas,
    required this.fichasUsadas,
    required this.fichasOptimas,
    required this.probabilidadInicial,
    required this.probabilidadFinal,
    required this.solucionOptima,
    required this.explicacionFinal,
    required this.aviso,
    this.recordEstrellas,
    this.recompensa,
  });

  final bool logrado;
  final int estrellas;
  final int fichasUsadas;
  final int fichasOptimas;
  final double probabilidadInicial;
  final double probabilidadFinal;
  final SolucionOptima solucionOptima;
  final Explicacion explicacionFinal;
  final String aviso;

  /// v1.1: el mejor resultado del jugador con este estudiante.
  final int? recordEstrellas;

  /// v1.1: XP, insignias nuevas y progreso. `null` con un servidor v1.
  final Recompensa? recompensa;

  factory ResultadoRescate.fromJson(Object? json) {
    final m = comoMapa(json, 'resultado del rescate');
    return ResultadoRescate(
      logrado: leerBool(m, 'logrado'),
      estrellas: leerInt(m, 'estrellas'),
      fichasUsadas: leerInt(m, 'fichas_usadas'),
      fichasOptimas: leerInt(m, 'fichas_optimas'),
      probabilidadInicial: leerNum(m, 'probabilidad_inicial').toDouble(),
      probabilidadFinal: leerNum(m, 'probabilidad_final').toDouble(),
      solucionOptima: SolucionOptima.fromJson(m['solucion_optima']),
      explicacionFinal: Explicacion.fromJson(m['explicacion_final']),
      aviso: leerString(m, 'aviso'),
      recordEstrellas: leerNumOpcional(m, 'record_estrellas')?.toInt(),
      recompensa: Recompensa.desde(m),
    );
  }
}
