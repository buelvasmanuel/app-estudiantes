// Textos del Laboratorio. Todo lo que dice el búho habla de lo que ESTIMA el
// modelo ("según el modelo…"): son asociaciones en los datos, no causas.
import 'apariencia.dart';
import 'modelo.dart';

/// Nombre legible de una variable del modelo.
String nombreVariable(String variable) => switch (variable) {
  'horas_estudio' => 'Horas de estudio',
  'asistencia' => 'Asistencia',
  'semestre' => 'Semestre',
  'edad' => 'Edad',
  'carrera' => 'Carrera',
  _ => variable,
};

/// Valor con su unidad: "6 h", "58 %", "19 años", "2.º", "Medicina".
String valorVariable(String variable, Object valor) => switch (variable) {
  'horas_estudio' => '$valor h',
  'asistencia' => '$valor\u00A0%',
  'edad' => '$valor años',
  'semestre' => '$valor.º',
  _ => '$valor',
};

/// Variables que el juego permite cambiar con fichas. Las demás (edad,
/// semestre, carrera) influyen en la estimación pero no son "palancas".
bool esAccionable(String variable) =>
    variable == 'horas_estudio' || variable == 'asistencia';

/// "49 %" con espacio no separable: el "%" nunca queda solo en otra línea.
String porcentaje(double p) => '${(p * 100).round()}\u00A0%';

/// "la asistencia", "las horas de estudio"... y si va en plural.
({String texto, bool plural}) conArticulo(String variable) =>
    switch (variable) {
      'horas_estudio' => (texto: 'las horas de estudio', plural: true),
      'asistencia' => (texto: 'la asistencia', plural: false),
      'semestre' => (texto: 'el semestre', plural: false),
      'edad' => (texto: 'la edad', plural: false),
      'carrera' => (texto: 'la carrera', plural: false),
      _ => (texto: variable, plural: false),
    };

/// Número con coma decimal: 2.4 → "2,4".
String decimal(double x) => x.toStringAsFixed(1).replaceAll('.', ',');

/// "Según el modelo, la asistencia pesó 2,4 veces más que las horas de
/// estudio." Compara las dos variables con más peso.
String? comparacionPesos(Explicacion e) {
  if (e.aportes.length < 2) return null;
  final [primero, segundo, ...] = e.aportes;
  if (segundo.peso <= 0) return null;
  final veces = primero.peso / segundo.peso;
  final a = conArticulo(primero.variable);
  final b = conArticulo(segundo.variable).texto;
  if (veces < 1.15) {
    return 'Según el modelo, ${a.texto} y $b pesaron casi lo mismo.';
  }
  final peso = a.plural ? 'pesaron' : 'pesó';
  return 'Según el modelo, ${a.texto} $peso ${decimal(veces)} veces más '
      'que $b.';
}

/// Lo que dice el búho mientras se juega.
({AnimoBuho animo, String frase}) buhoDuranteRescate({
  required Caso caso,
  required int fichasUsadas,
  required double? probabilidad,
}) {
  if (fichasUsadas == 0 || probabilidad == null) {
    final palanca = caso.explicacion.aportes
        .where((a) => esAccionable(a.variable) && a.efecto == Efecto.sube)
        .firstOrNull;
    return (
      animo: AnimoBuho.atento,
      frase: palanca == null
          ? 'Según el modelo, su riesgo es de ${porcentaje(caso.probabilidad)}. '
                'Tienes ${caso.presupuesto} fichas.'
          : 'Según el modelo, lo que más empuja su riesgo es la '
                '${nombreVariable(palanca.variable).toLowerCase()} '
                '(${valorVariable(palanca.variable, palanca.valor)}). '
                'Tienes ${caso.presupuesto} fichas.',
    );
  }
  if (probabilidad < caso.objetivo) {
    return (
      animo: AnimoBuho.contento,
      frase:
          'Según el modelo bajaría a ${porcentaje(probabilidad)}. '
          'Puedes confirmar el rescate… o buscar una forma más barata.',
    );
  }
  return (
    animo: AnimoBuho.pensando,
    frase:
        'Según el modelo, ahora estaría en ${porcentaje(probabilidad)}. '
        'Aún por encima de ${porcentaje(caso.objetivo)}.',
  );
}

/// Lo que dice el búho al ver el resultado. Siempre recuerda que es una
/// estimación: correlación, no causalidad.
({AnimoBuho animo, String frase}) buhoResultado(ResultadoRescate r) {
  const cautela =
      ' Recuerda: el modelo ve qué cosas suelen ir juntas en los datos '
      '(correlación), no qué las causa.';
  if (!r.logrado) {
    return (
      animo: AnimoBuho.preocupado,
      frase:
          'Según el modelo seguiría en riesgo (${porcentaje(r.probabilidadFinal)}). '
          'Prueba otra combinación.$cautela',
    );
  }
  if (r.estrellas == 3) {
    return (
      animo: AnimoBuho.celebrando,
      frase: '¡Rescate perfecto! Lo lograste con las fichas justas.$cautela',
    );
  }
  return (
    animo: AnimoBuho.contento,
    frase:
        '¡Rescatado! Se podía con ${r.fichasOptimas} '
        '${r.fichasOptimas == 1 ? 'ficha' : 'fichas'}.$cautela',
  );
}

/// "1 plan de estudio y 2 tutorías", con los nombres del catálogo.
String describirSolucion(SolucionOptima s, List<Intervencion> catalogo) {
  final partes = [
    for (final i in catalogo)
      if ((s.porIntervencion[i.codigo] ?? 0) > 0)
        '${s.porIntervencion[i.codigo]} × ${i.nombre.toLowerCase()}',
  ];
  return partes.isEmpty ? 'ninguna intervención' : partes.join(' + ');
}
