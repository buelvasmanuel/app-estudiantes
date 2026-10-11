import '../screens/acceso_screen.dart' show ReglasAcceso;

/// Máximo de cuentas por petición a `POST /usuarios/lote`.
const maximoLote = 40;

/// Una lista de alias escrita o pegada por el docente, ya revisada.
class ListaAliases {
  const ListaAliases({
    required this.validos,
    required this.invalidos,
    required this.repetidos,
  });

  /// Separa por saltos de línea, comas, punto y coma o espacios (así vale
  /// pegar una columna de una hoja de cálculo) y revisa cada alias con las
  /// reglas del contrato: 3-30 caracteres `[A-Za-z0-9_]`, sin repetir
  /// (sin distinguir mayúsculas, como la API).
  factory ListaAliases.desde(String texto) {
    final validos = <String>[];
    final invalidos = <String>[];
    final repetidos = <String>[];
    final vistos = <String>{};
    for (final alias in texto.split(RegExp(r'[\s,;]+'))) {
      if (alias.isEmpty) continue;
      if (!ReglasAcceso.alias.hasMatch(alias)) {
        invalidos.add(alias);
      } else if (!vistos.add(alias.toLowerCase())) {
        repetidos.add(alias);
      } else {
        validos.add(alias);
      }
    }
    return ListaAliases(
      validos: validos,
      invalidos: invalidos,
      repetidos: repetidos,
    );
  }

  final List<String> validos;
  final List<String> invalidos;
  final List<String> repetidos;

  bool get demasiados => validos.length > maximoLote;

  /// Se puede enviar: hay alias, todos válidos, sin repetir y caben.
  bool get enviable =>
      validos.isNotEmpty &&
      invalidos.isEmpty &&
      repetidos.isEmpty &&
      !demasiados;
}
