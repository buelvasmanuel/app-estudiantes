// Tipos del juego (casos, progreso, insignias, ranking), tal como los define
// docs/CONTRATO_JUEGO.md (repo api-tienda).
import '../models/json_utils.dart';

DateTime? _fecha(Map<String, Object?> m, String clave) {
  final v = m[clave];
  return v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

String? _textoOpcional(Map<String, Object?> m, String clave) {
  final v = m[clave];
  return v is String ? v : null;
}

/// `InsigniaOut`. [obtenidaEn] es `null` si aún no se tiene.
class Insignia {
  const Insignia({
    required this.codigo,
    required this.nombre,
    required this.descripcion,
    this.obtenidaEn,
  });

  final String codigo;
  final String nombre;
  final String descripcion;
  final DateTime? obtenidaEn;

  bool get obtenida => obtenidaEn != null;

  factory Insignia.fromJson(Object? json) {
    final m = comoMapa(json, 'insignia');
    return Insignia(
      codigo: leerString(m, 'codigo'),
      nombre: leerString(m, 'nombre'),
      descripcion: leerString(m, 'descripcion'),
      obtenidaEn: _fecha(m, 'obtenida_en'),
    );
  }

  static List<Insignia> lista(Object? json) =>
      json == null ? const [] : comoLista(json).map(Insignia.fromJson).toList();
}

/// `ProgresoResumenOut`: viene en cada respuesta que da XP.
class ProgresoResumen {
  const ProgresoResumen({
    required this.xp,
    required this.nivel,
    required this.subioDeNivel,
  });

  final int xp;
  final String nivel;
  final bool subioDeNivel;

  factory ProgresoResumen.fromJson(Object? json) {
    final m = comoMapa(json, 'progreso');
    return ProgresoResumen(
      xp: leerInt(m, 'xp'),
      nivel: leerString(m, 'nivel'),
      subioDeNivel: leerBool(m, 'subio_de_nivel'),
    );
  }
}

/// Lo que se gana con una acción (responder un caso, resolver un rescate).
class Recompensa {
  const Recompensa({
    required this.xpGanada,
    required this.insigniasNuevas,
    required this.progreso,
  });

  final int xpGanada;
  final List<Insignia> insigniasNuevas;
  final ProgresoResumen progreso;

  /// Hay algo que celebrar: insignia nueva o subida de nivel.
  bool get hayCelebracion =>
      insigniasNuevas.isNotEmpty || progreso.subioDeNivel;

  /// `null` si la respuesta no trae progreso (servidor anterior a la v1.1).
  static Recompensa? desde(Map<String, Object?> m) {
    if (m['progreso'] == null) return null;
    return Recompensa(
      xpGanada: leerInt(m, 'xp_ganada'),
      insigniasNuevas: Insignia.lista(m['insignias_nuevas']),
      progreso: ProgresoResumen.fromJson(m['progreso']),
    );
  }
}

enum NivelCaso {
  novato('Novato'),
  investigador('Investigador'),
  experto('Experto');

  const NivelCaso(this.nombre);
  final String nombre;

  static NivelCaso desde(String texto) => switch (texto) {
    'novato' => novato,
    'investigador' => investigador,
    'experto' => experto,
    _ => throw FormatException('Nivel de caso desconocido', texto),
  };
}

/// Un caso de la lista (`GET /juego/casos`).
class CasoJuegoResumen {
  const CasoJuegoResumen({
    required this.codigo,
    required this.nivel,
    required this.titulo,
    required this.xp,
    required this.resuelto,
    required this.intentos,
    required this.xpGanada,
  });

  final String codigo;
  final NivelCaso nivel;
  final String titulo;
  final int xp;
  final bool resuelto;
  final int intentos;
  final int xpGanada;

  factory CasoJuegoResumen.fromJson(Object? json) {
    final m = comoMapa(json, 'caso');
    return CasoJuegoResumen(
      codigo: leerString(m, 'codigo'),
      nivel: NivelCaso.desde(leerString(m, 'nivel')),
      titulo: leerString(m, 'titulo'),
      xp: leerInt(m, 'xp'),
      resuelto: leerBool(m, 'resuelto'),
      intentos: leerInt(m, 'intentos'),
      xpGanada: leerInt(m, 'xp_ganada'),
    );
  }

  static List<CasoJuegoResumen> lista(Object? json) =>
      comoLista(comoMapa(json, 'lista de casos')['casos'])
          .map(CasoJuegoResumen.fromJson)
          .toList();
}

class Opcion {
  const Opcion({required this.valor, required this.texto});

  /// Lo que se envía al responder.
  final String valor;

  /// Lo que se muestra.
  final String texto;

  factory Opcion.fromJson(Object? json) {
    final m = comoMapa(json, 'opción');
    return Opcion(valor: leerString(m, 'valor'), texto: leerString(m, 'texto'));
  }
}

/// `GET /juego/casos/{codigo}`. No trae la respuesta ni la pista.
class CasoJuego {
  const CasoJuego({
    required this.codigo,
    required this.nivel,
    required this.titulo,
    required this.enunciado,
    required this.opciones,
    required this.grafica,
    required this.xp,
    required this.resuelto,
    required this.intentos,
  });

  final String codigo;
  final NivelCaso nivel;
  final String titulo;
  final String enunciado;
  final List<Opcion> opciones;

  /// Ruta de la estadística que ayuda (`/estudiantes/estadisticas/…`).
  final String? grafica;
  final int xp;
  final bool resuelto;
  final int intentos;

  factory CasoJuego.fromJson(Object? json) {
    final m = comoMapa(json, 'caso');
    return CasoJuego(
      codigo: leerString(m, 'codigo'),
      nivel: NivelCaso.desde(leerString(m, 'nivel')),
      titulo: leerString(m, 'titulo'),
      enunciado: leerString(m, 'enunciado'),
      opciones: comoLista(m['opciones']).map(Opcion.fromJson).toList(),
      grafica: _textoOpcional(m, 'grafica'),
      xp: leerInt(m, 'xp'),
      resuelto: leerBool(m, 'resuelto'),
      intentos: leerInt(m, 'intentos'),
    );
  }
}

/// `POST /juego/casos/{codigo}/responder`: lo decide el servidor.
class RespuestaCaso {
  const RespuestaCaso({
    required this.correcto,
    required this.dato,
    required this.explicacion,
    required this.pista,
    required this.intento,
    required this.recompensa,
  });

  final bool correcto;

  /// El valor real de la opción elegida (o `null` si revelaría la respuesta).
  final String? dato;

  /// Solo si acierta.
  final String? explicacion;

  /// Solo si falla.
  final String? pista;
  final int intento;
  final Recompensa recompensa;

  factory RespuestaCaso.fromJson(Object? json) {
    final m = comoMapa(json, 'respuesta');
    return RespuestaCaso(
      correcto: leerBool(m, 'correcto'),
      dato: _textoOpcional(m, 'dato'),
      explicacion: _textoOpcional(m, 'explicacion'),
      pista: _textoOpcional(m, 'pista'),
      intento: leerInt(m, 'intento'),
      recompensa:
          Recompensa.desde(m) ??
          (throw const FormatException('Falta "progreso"')),
    );
  }
}

class NivelJugador {
  const NivelJugador({
    required this.numero,
    required this.nombre,
    required this.xpDesde,
  });

  final int numero;
  final String nombre;
  final int xpDesde;

  factory NivelJugador.fromJson(Object? json) {
    final m = comoMapa(json, 'nivel');
    return NivelJugador(
      numero: leerInt(m, 'numero'),
      nombre: leerString(m, 'nombre'),
      xpDesde: leerInt(m, 'xp_desde'),
    );
  }
}

/// `GET /juego/progreso`: el perfil del detective.
class Progreso {
  const Progreso({
    required this.alias,
    required this.xp,
    required this.nivel,
    required this.siguienteNivel,
    required this.rachaDias,
    required this.casosResueltos,
    required this.casosTotal,
    required this.rescatesLogrados,
    required this.estrellasTotales,
    required this.insignias,
  });

  final String alias;
  final int xp;
  final NivelJugador nivel;

  /// `null` en el último nivel.
  final NivelJugador? siguienteNivel;
  final int rachaDias;
  final int casosResueltos;
  final int casosTotal;
  final int rescatesLogrados;
  final int estrellasTotales;

  /// El catálogo entero, obtenidas o no.
  final List<Insignia> insignias;

  /// Avance dentro del nivel actual (0-1); 1 en el último nivel.
  double get avanceNivel {
    final siguiente = siguienteNivel;
    if (siguiente == null) return 1;
    final tramo = siguiente.xpDesde - nivel.xpDesde;
    return tramo <= 0 ? 1 : ((xp - nivel.xpDesde) / tramo).clamp(0, 1);
  }

  factory Progreso.fromJson(Object? json) {
    final m = comoMapa(json, 'progreso');
    return Progreso(
      alias: leerString(m, 'alias'),
      xp: leerInt(m, 'xp'),
      nivel: NivelJugador.fromJson(m['nivel']),
      siguienteNivel: m['siguiente_nivel'] == null
          ? null
          : NivelJugador.fromJson(m['siguiente_nivel']),
      rachaDias: leerInt(m, 'racha_dias'),
      casosResueltos: leerInt(m, 'casos_resueltos'),
      casosTotal: leerInt(m, 'casos_total'),
      rescatesLogrados: leerInt(m, 'rescates_logrados'),
      estrellasTotales: leerInt(m, 'estrellas_totales'),
      insignias: Insignia.lista(m['insignias']),
    );
  }
}

enum PeriodoRanking {
  semana,
  siempre;

  String get nombre => switch (this) {
    semana => 'Esta semana',
    siempre => 'Histórico',
  };
}

class Puesto {
  const Puesto({
    required this.posicion,
    required this.alias,
    required this.xp,
    required this.nivel,
    required this.soyYo,
  });

  final int posicion;
  final String alias;
  final int xp;
  final String nivel;
  final bool soyYo;

  factory Puesto.fromJson(Object? json) {
    final m = comoMapa(json, 'puesto');
    return Puesto(
      posicion: leerInt(m, 'posicion'),
      alias: leerString(m, 'alias'),
      xp: leerInt(m, 'xp'),
      nivel: leerString(m, 'nivel'),
      soyYo: leerBool(m, 'soy_yo'),
    );
  }
}

/// `GET /juego/ranking`.
class Ranking {
  const Ranking({
    required this.periodo,
    required this.desde,
    required this.jugadores,
    required this.miPosicion,
    required this.miXp,
  });

  final PeriodoRanking periodo;
  final DateTime? desde;

  /// Top 20.
  final List<Puesto> jugadores;

  /// Posición propia aunque no esté en el top 20 (`null` si no puntúa).
  final int? miPosicion;
  final int? miXp;

  factory Ranking.fromJson(Object? json) {
    final m = comoMapa(json, 'ranking');
    final yo = m['yo'] == null ? null : comoMapa(m['yo'], 'mi puesto');
    return Ranking(
      periodo: leerString(m, 'periodo') == 'siempre'
          ? PeriodoRanking.siempre
          : PeriodoRanking.semana,
      desde: _fecha(m, 'desde'),
      jugadores: comoLista(m['jugadores']).map(Puesto.fromJson).toList(),
      miPosicion: yo == null ? null : leerInt(yo, 'posicion'),
      miXp: yo == null ? null : leerInt(yo, 'xp'),
    );
  }
}

/// `GET /juego/jugadores` (docente/admin).
class Jugador {
  const Jugador({
    required this.id,
    required this.alias,
    required this.activo,
    required this.xp,
    required this.nivel,
    required this.casosResueltos,
    required this.rescatesLogrados,
    required this.insignias,
    required this.ultimaActividad,
  });

  final int id;
  final String alias;
  final bool activo;
  final int xp;
  final String nivel;
  final int casosResueltos;
  final int rescatesLogrados;
  final int insignias;
  final DateTime? ultimaActividad;

  factory Jugador.fromJson(Object? json) {
    final m = comoMapa(json, 'jugador');
    return Jugador(
      id: leerInt(m, 'id'),
      alias: leerString(m, 'alias'),
      activo: leerBool(m, 'activo'),
      xp: leerInt(m, 'xp'),
      nivel: leerString(m, 'nivel'),
      casosResueltos: leerInt(m, 'casos_resueltos'),
      rescatesLogrados: leerInt(m, 'rescates_logrados'),
      insignias: leerInt(m, 'insignias'),
      ultimaActividad: _fecha(m, 'ultima_actividad'),
    );
  }
}

/// Una cuenta creada por el docente (`POST /usuarios/lote`). La contraseña
/// solo existe en esta respuesta.
class CuentaCreada {
  const CuentaCreada({
    required this.id,
    required this.alias,
    required this.password,
  });

  final int id;
  final String alias;
  final String password;

  factory CuentaCreada.fromJson(Object? json) {
    final m = comoMapa(json, 'cuenta');
    return CuentaCreada(
      id: leerInt(m, 'id'),
      alias: leerString(m, 'alias'),
      password: leerString(m, 'password'),
    );
  }
}
