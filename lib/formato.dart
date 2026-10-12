// Formato de números de toda la app, el de Colombia: coma decimal ("3,80"),
// punto de miles ("1.250") y un espacio no separable antes de "%" para que
// el símbolo nunca quede solo en otra línea ("33,3 %").
//
// Ninguna pantalla debe usar toStringAsFixed para mostrar un número: todo
// pasa por aquí.

const _espacioFijo = ' ';

/// [valor] con [decimales] cifras decimales: 3.8 → "3,80" (con 2).
String formatoDecimal(num valor, [int decimales = 1]) {
  final texto = valor.abs().toStringAsFixed(decimales);
  final [entera, ...resto] = texto.split('.');
  final signo = valor < 0 && texto.contains(RegExp('[1-9]')) ? '-' : '';
  final conMiles = _miles(entera);
  return resto.isEmpty ? '$signo$conMiles' : '$signo$conMiles,${resto.first}';
}

/// Entero redondeado con punto de miles: 1250.4 → "1.250".
String formatoEntero(num valor) => formatoDecimal(valor.round(), 0);

/// Un porcentaje que ya está en 0-100: 33.333 → "33,3 %" (1 decimal).
String formatoPorcentaje(num valor, [int decimales = 0]) =>
    '${formatoDecimal(valor, decimales)}$_espacioFijo%';

/// Una probabilidad o fracción en 0-1: 0.49 → "49 %".
String formatoProbabilidad(num fraccion, [int decimales = 0]) =>
    formatoPorcentaje(fraccion * 100, decimales);

/// Un promedio de notas (0-5), siempre con 2 decimales: 3.8 → "3,80".
String formatoPromedio(num valor) => formatoDecimal(valor, 2);

String _miles(String entera) {
  final grupos = <String>[];
  for (var fin = entera.length; fin > 0; fin -= 3) {
    grupos.insert(0, entera.substring(fin - 3 < 0 ? 0 : fin - 3, fin));
  }
  return grupos.join('.');
}
