import '../models/prediccion.dart';
import 'modelo.dart';

/// Un intento de rescate en curso: qué intervenciones se han aplicado y en
/// qué orden (para poder deshacer). Inmutable.
///
/// Aplica las reglas del §4.1 del contrato en local, con los `incremento` y
/// `tope` del catálogo. Solo sirve para mover el medidor: el resultado que
/// cuenta (estrellas, probabilidad final) lo calcula el servidor.
class Rescate {
  const Rescate(this.caso, [this.aplicadas = const []]);

  final Caso caso;
  final List<Intervencion> aplicadas;

  int get fichasUsadas => aplicadas.fold(0, (s, i) => s + i.fichas);
  int get fichasRestantes => caso.presupuesto - fichasUsadas;

  /// Veces que se ha aplicado cada intervención, en el orden del catálogo.
  List<int> get conteos => [
    for (final i in caso.intervenciones)
      aplicadas.where((a) => a.codigo == i.codigo).length,
  ];

  /// Valor actual de [variable] (`horas_estudio` o `asistencia`).
  int valor(String variable) => _valorCon(caso, variable, conteos);

  /// Ya está en el tope: aplicarla costaría fichas sin efecto (§4.1).
  bool enTope(Intervencion i) => valor(i.variable) >= i.tope;

  bool sePuedeAplicar(Intervencion i) =>
      i.fichas <= fichasRestantes && !enTope(i);

  Rescate con(Intervencion i) =>
      sePuedeAplicar(i) ? Rescate(caso, [...aplicadas, i]) : this;

  Rescate deshacer() => aplicadas.isEmpty
      ? this
      : Rescate(caso, aplicadas.sublist(0, aplicadas.length - 1));

  Rescate reiniciar() => Rescate(caso);

  /// Lo que se envía a `…/resolver`.
  List<String> get codigos => [for (final i in aplicadas) i.codigo];

  String get clave => claveDe(conteos);

  static String claveDe(List<int> conteos) => conteos.join(',');

  /// Todas las combinaciones que caben en el presupuesto (con 5 fichas y el
  /// catálogo del contrato, 12). Se piden de una vez a
  /// `POST /prediccion/riesgo/lote` para que el medidor no espere a la red.
  static List<List<int>> combinaciones(Caso caso) {
    final resultado = <List<int>>[];
    void probar(int indice, List<int> actual, int gastado) {
      if (indice == caso.intervenciones.length) {
        resultado.add(List.of(actual));
        return;
      }
      final coste = caso.intervenciones[indice].fichas;
      for (var n = 0; gastado + n * coste <= caso.presupuesto; n++) {
        actual.add(n);
        probar(indice + 1, actual, gastado + n * coste);
        actual.removeLast();
        if (coste <= 0) break; // por si acaso: nunca un bucle infinito
      }
    }

    probar(0, [], 0);
    return resultado;
  }

  /// La entrada del modelo tras aplicar [conteos] (con los topes).
  static EntradaPrediccion entradaPara(Caso caso, List<int> conteos) =>
      caso.estudiante.entrada(
        horasEstudio: _valorCon(caso, 'horas_estudio', conteos),
        asistencia: _valorCon(caso, 'asistencia', conteos),
      );

  static int _valorCon(Caso caso, String variable, List<int> conteos) {
    final e = caso.estudiante;
    var valor = switch (variable) {
      'horas_estudio' => e.horasEstudio,
      'asistencia' => e.asistencia,
      _ => throw ArgumentError.value(variable, 'variable'),
    };
    for (final (k, i) in caso.intervenciones.indexed) {
      if (i.variable != variable) continue;
      for (var n = 0; n < conteos[k]; n++) {
        valor = valor + i.incremento > i.tope ? i.tope : valor + i.incremento;
      }
    }
    return valor;
  }
}
