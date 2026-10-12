// Tipos del duelo de cartas, tal como los define docs/CONTRATO_DUELO.md
// (repo api-tienda). El cliente nunca calcula quién gana ni la XP: todo
// viene del servidor.
import 'package:flutter/material.dart';

import '../formato.dart';
import '../juego/modelo.dart';
import '../models/json_utils.dart';

/// Los dos lados del duelo, siempre desde el punto de vista de quien pregunta.
enum Lado {
  yo,
  rival;

  static Lado desde(String texto) => switch (texto) {
    'yo' => yo,
    'rival' => rival,
    _ => throw FormatException('Lado desconocido', texto),
  };
}

enum GanadorRonda {
  yo,
  rival,
  empate;

  static GanadorRonda desde(String texto) => switch (texto) {
    'yo' => yo,
    'rival' => rival,
    'empate' => empate,
    _ => throw FormatException('Ganador desconocido', texto),
  };
}

enum EstadoDuelo {
  /// v2: buscando rival.
  esperando,
  enJuego,
  terminado,
  abandonado;

  bool get acabado => this == terminado || this == abandonado;

  static EstadoDuelo desde(String texto) => switch (texto) {
    'esperando' => esperando,
    'en_juego' => enJuego,
    'terminado' => terminado,
    'abandonado' => abandonado,
    _ => throw FormatException('Estado de duelo desconocido', texto),
  };
}

enum ResultadoDuelo {
  victoria,
  derrota,
  empate;

  static ResultadoDuelo? desde(Object? texto) => switch (texto) {
    null => null,
    'victoria' => victoria,
    'derrota' => derrota,
    'empate' => empate,
    _ => throw FormatException('Resultado desconocido', texto),
  };
}

/// Contra la máquina (v1) o contra otro jugador (v2).
enum ModoDuelo {
  maquina,
  jugador;

  static ModoDuelo desde(String texto) => switch (texto) {
    'maquina' => maquina,
    'jugador' => jugador,
    _ => throw FormatException('Modo de duelo desconocido', texto),
  };
}

/// Los cuatro atributos de §2, en el orden del contrato.
abstract final class Atributos {
  static const promedio = 'promedio';
  static const asistencia = 'asistencia';
  static const horasEstudio = 'horas_estudio';
  static const semestre = 'semestre';

  static const orden = [promedio, asistencia, horasEstudio, semestre];

  /// Nombre por si la API no lo trae (lo normal es usar `atributos`).
  static String nombre(String codigo) => switch (codigo) {
    promedio => 'Promedio',
    asistencia => 'Asistencia',
    horasEstudio => 'Horas de estudio',
    semestre => 'Semestre',
    _ => codigo,
  };

  static IconData icono(String codigo) => switch (codigo) {
    promedio => Icons.star_outline_rounded,
    asistencia => Icons.event_available_outlined,
    horasEstudio => Icons.menu_book_outlined,
    semestre => Icons.calendar_month_outlined,
    _ => Icons.help_outline,
  };

  /// "3,80", "92 %", "14 h", "3.º".
  static String valor(String codigo, num valor) => switch (codigo) {
    promedio => formatoPromedio(valor),
    asistencia => formatoPorcentaje(valor),
    horasEstudio => '${_numero(valor)} h',
    semestre => '${_numero(valor)}.º',
    _ => _numero(valor),
  };

  static String _numero(num v) =>
      v == v.roundToDouble() ? formatoEntero(v) : formatoDecimal(v);
}

/// Un valor de la carta y su percentil (0-100) entre todos los estudiantes.
class ValorAtributo {
  const ValorAtributo({required this.valor, required this.percentil});

  final num valor;
  final int percentil;

  factory ValorAtributo.fromJson(Object? json) {
    final m = comoMapa(json, 'atributo de la carta');
    return ValorAtributo(
      valor: leerNum(m, 'valor'),
      percentil: leerInt(m, 'percentil'),
    );
  }
}

/// `CartaOut`: un estudiante real con sus 4 atributos.
class Carta {
  const Carta({
    required this.estudianteId,
    required this.nombre,
    required this.apellido,
    required this.carrera,
    required this.atributos,
  });

  final int estudianteId;
  final String nombre;
  final String apellido;
  final String carrera;
  final Map<String, ValorAtributo> atributos;

  String get nombreCompleto => '$nombre $apellido';

  String get iniciales =>
      '${nombre.characters.firstOrNull ?? ''}'
              '${apellido.characters.firstOrNull ?? ''}'
          .toUpperCase();

  factory Carta.fromJson(Object? json) {
    final m = comoMapa(json, 'carta');
    return Carta(
      estudianteId: leerInt(m, 'estudiante_id'),
      nombre: leerString(m, 'nombre'),
      apellido: leerString(m, 'apellido'),
      carrera: leerString(m, 'carrera'),
      atributos: {
        for (final MapEntry(:key, :value) in comoMapa(
          m['atributos'],
          'atributos',
        ).entries)
          key: ValorAtributo.fromJson(value),
      },
    );
  }
}

/// `RondaOut`: una ronda ya resuelta, con las dos cartas a la vista.
class Ronda {
  const Ronda({
    required this.numero,
    required this.elegidoPor,
    required this.atributo,
    required this.miCarta,
    required this.cartaRival,
    required this.ganador,
    required this.explicacion,
    this.porTiempo = false,
  });

  final int numero;
  final Lado elegidoPor;

  /// `null` si la ronda se perdió por tiempo (v2).
  final String? atributo;
  final Carta miCarta;
  final Carta cartaRival;
  final GanadorRonda ganador;

  /// El texto del búho, tal cual lo manda la API.
  final String explicacion;

  /// v2: a quien le tocaba elegir se le acabó el turno (`motivo: "tiempo"`).
  final bool porTiempo;

  factory Ronda.fromJson(Object? json) {
    final m = comoMapa(json, 'ronda');
    final atributo = m['atributo'];
    return Ronda(
      numero: leerInt(m, 'numero'),
      elegidoPor: Lado.desde(leerString(m, 'elegido_por')),
      atributo: atributo is String ? atributo : null,
      miCarta: Carta.fromJson(m['mi_carta']),
      cartaRival: Carta.fromJson(m['carta_rival']),
      ganador: GanadorRonda.desde(leerString(m, 'ganador')),
      explicacion: leerString(m, 'explicacion'),
      porTiempo: m['motivo'] == 'tiempo',
    );
  }
}

/// Un atributo explicado (`atributos` de `DueloOut`).
class InfoAtributo {
  const InfoAtributo({
    required this.codigo,
    required this.nombre,
    required this.unidad,
    required this.descripcion,
  });

  final String codigo;
  final String nombre;
  final String unidad;
  final String descripcion;

  factory InfoAtributo.fromJson(Object? json) {
    final m = comoMapa(json, 'atributo');
    return InfoAtributo(
      codigo: leerString(m, 'codigo'),
      nombre: leerString(m, 'nombre'),
      unidad: leerString(m, 'unidad'),
      descripcion: leerString(m, 'descripcion'),
    );
  }
}

/// `DueloOut`.
class Duelo {
  const Duelo({
    required this.id,
    required this.modo,
    required this.estado,
    required this.aliasRival,
    required this.rondasTotal,
    required this.ronda,
    required this.turno,
    required this.marcadorYo,
    required this.marcadorRival,
    required this.miCarta,
    required this.rondas,
    required this.resultado,
    required this.xpGanada,
    required this.duelosConXpHoy,
    required this.maximoDuelosConXp,
    required this.atributos,
    this.expiraTurnoEn,
    this.rivalEnLinea,
    this.actualizadoEn,
    this.recompensa,
  });

  final String id;
  final ModoDuelo modo;
  final EstadoDuelo estado;

  /// `null` mientras se busca rival (v2).
  final String? aliasRival;
  final int rondasTotal;

  /// La ronda que toca jugar; `null` si terminó.
  final int? ronda;

  /// `null` si terminó.
  final Lado? turno;
  final int marcadorYo;
  final int marcadorRival;

  /// La carta que toca jugar ahora; `null` si terminó.
  final Carta? miCarta;
  final List<Ronda> rondas;
  final ResultadoDuelo? resultado;
  final int xpGanada;
  final int duelosConXpHoy;
  final int maximoDuelosConXp;
  final List<InfoAtributo> atributos;

  /// v2: hasta cuándo puede elegir quien tiene el turno (o hasta cuándo se
  /// busca rival). `null` contra la máquina.
  final DateTime? expiraTurnoEn;

  /// v2: si el rival tiene abierto el duelo. `null` contra la máquina.
  final bool? rivalEnLinea;

  /// Para no pisar un estado nuevo con una respuesta vieja (REST y
  /// WebSocket pueden llegar en cualquier orden).
  final DateTime? actualizadoEn;

  /// Solo en la respuesta de la jugada que termina el duelo.
  final Recompensa? recompensa;

  bool get contraMaquina => modo == ModoDuelo.maquina;

  /// Sigue vivo: buscando rival o jugando.
  bool get activo =>
      estado == EstadoDuelo.esperando || estado == EstadoDuelo.enJuego;

  /// Este estado es anterior a [otro]: no debe sustituirlo (REST y
  /// WebSocket pueden llegar en cualquier orden).
  bool esMasViejoQue(Duelo otro) {
    final a = actualizadoEn, b = otro.actualizadoEn;
    if (a != null && b != null) return a.isBefore(b);
    return rondas.length < otro.rondas.length;
  }

  /// Lo que se puede jugar ahora mismo: hay ronda y el duelo sigue.
  bool get enJuego => estado == EstadoDuelo.enJuego && ronda != null;

  String nombreAtributo(String codigo) =>
      atributos.where((a) => a.codigo == codigo).firstOrNull?.nombre ??
      Atributos.nombre(codigo);

  /// Los atributos en el orden de la API (o el del contrato, si no los trae).
  List<String> get codigosAtributos => atributos.isEmpty
      ? Atributos.orden
      : [for (final a in atributos) a.codigo];

  factory Duelo.fromJson(Object? json) {
    final m = comoMapa(json, 'duelo');
    final rival = comoMapa(m['rival'], 'rival');
    final marcador = comoMapa(m['marcador'], 'marcador');
    final hoy = comoMapa(m['duelos_con_xp_hoy'], 'duelos con XP hoy');
    final turno = m['turno'];
    final expira = m['expira_turno_en'];
    final enLinea = m['rival_en_linea'];
    return Duelo(
      id: leerString(m, 'id'),
      modo: ModoDuelo.desde(leerString(m, 'modo')),
      estado: EstadoDuelo.desde(leerString(m, 'estado')),
      aliasRival: rival['alias'] is String ? rival['alias']! as String : null,
      rondasTotal: leerInt(m, 'rondas_total'),
      ronda: m['ronda'] == null ? null : leerInt(m, 'ronda'),
      turno: turno is String ? Lado.desde(turno) : null,
      marcadorYo: leerInt(marcador, 'yo'),
      marcadorRival: leerInt(marcador, 'rival'),
      miCarta: m['mi_carta'] == null ? null : Carta.fromJson(m['mi_carta']),
      rondas: comoLista(m['rondas']).map(Ronda.fromJson).toList(),
      resultado: ResultadoDuelo.desde(m['resultado']),
      xpGanada: leerInt(m, 'xp_ganada'),
      duelosConXpHoy: leerInt(hoy, 'jugados'),
      maximoDuelosConXp: leerInt(hoy, 'maximo'),
      atributos: m['atributos'] == null
          ? const []
          : comoLista(m['atributos']).map(InfoAtributo.fromJson).toList(),
      expiraTurnoEn: expira is String
          ? DateTime.tryParse(expira)?.toLocal()
          : null,
      rivalEnLinea: enLinea is bool ? enLinea : null,
      actualizadoEn: m['actualizado_en'] is String
          ? DateTime.tryParse(m['actualizado_en']! as String)
          : null,
      recompensa: Recompensa.desde(m),
    );
  }
}

/// `DueloResumenOut` (`GET /duelos?estado=…`): solo lo que hace falta para
/// retomar un duelo.
class DueloResumen {
  const DueloResumen({
    required this.id,
    required this.modo,
    required this.estado,
  });

  final String id;
  final ModoDuelo modo;
  final EstadoDuelo estado;

  factory DueloResumen.fromJson(Object? json) {
    final m = comoMapa(json, 'duelo');
    return DueloResumen(
      id: leerString(m, 'id'),
      modo: ModoDuelo.desde(leerString(m, 'modo')),
      estado: EstadoDuelo.desde(leerString(m, 'estado')),
    );
  }

  static List<DueloResumen> lista(Object? json) =>
      comoLista(comoMapa(json, 'lista de duelos')['duelos'])
          .map(DueloResumen.fromJson)
          .toList();
}

/// Duelos con XP que lleva hoy el jugador en un modo (`{jugados, maximo}`).
class XpHoy {
  const XpHoy({required this.jugados, required this.maximo});

  final int jugados;
  final int maximo;

  static XpHoy? desde(Object? json) {
    if (json is! Map<String, Object?>) return null;
    try {
      return XpHoy(
        jugados: leerInt(json, 'jugados'),
        maximo: leerInt(json, 'maximo'),
      );
    } on FormatException {
      return null;
    }
  }

  /// `xp_hoy` de `GET /duelos` (petición al backend; puede no venir).
  static Map<ModoDuelo, XpHoy> deLista(Object? json) {
    final m = json is Map<String, Object?> ? json['xp_hoy'] : null;
    if (m is! Map<String, Object?>) return const {};
    return {for (final modo in ModoDuelo.values) modo: ?desde(m[modo.name])};
  }
}
