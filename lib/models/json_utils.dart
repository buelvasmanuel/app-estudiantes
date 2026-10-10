// Funciones para leer JSON de forma segura.
//
// `jsonDecode` devuelve `Object?`: un número puede llegar como `int` (49) o
// como `double` (3.5), y algunos campos llegan como texto (el promedio es un
// Decimal en Python y Pydantic lo envía como "3.95"). Si hiciéramos
// `json['promedio'] as double`, la app se rompería con un TypeError poco claro.
// Estas funciones aceptan esas variantes y, si el dato no sirve, lanzan una
// FormatException que dice QUÉ campo falló.

Map<String, Object?> comoMapa(Object? valor, [String contexto = 'objeto']) {
  if (valor is Map<String, Object?>) return valor;
  throw FormatException('Se esperaba un $contexto JSON', valor);
}

List<Object?> comoLista(Object? valor, [String contexto = 'lista']) {
  if (valor is List<Object?>) return valor;
  throw FormatException('Se esperaba una $contexto JSON', valor);
}

/// Lee un número que puede venir como `int`, `double` o `String` ("3.95").
num leerNum(Map<String, Object?> json, String clave) {
  final valor = json[clave];
  if (valor is num) return valor;
  if (valor is String) {
    final numero = num.tryParse(valor.trim());
    if (numero != null) return numero;
  }
  throw FormatException('Campo "$clave": se esperaba un número', valor);
}

/// Como [leerNum], pero devuelve `null` si el campo no existe o no es número.
num? leerNumOpcional(Map<String, Object?> json, String clave) {
  final valor = json[clave];
  if (valor is num) return valor;
  if (valor is String) return num.tryParse(valor.trim());
  return null;
}

int leerInt(Map<String, Object?> json, String clave) {
  final numero = leerNum(json, clave);
  if (numero == numero.roundToDouble()) return numero.toInt();
  throw FormatException('Campo "$clave": se esperaba un entero', numero);
}

String leerString(Map<String, Object?> json, String clave) {
  final valor = json[clave];
  if (valor is String) return valor;
  throw FormatException('Campo "$clave": se esperaba un texto', valor);
}

bool leerBool(Map<String, Object?> json, String clave) {
  final valor = json[clave];
  if (valor is bool) return valor;
  throw FormatException('Campo "$clave": se esperaba true/false', valor);
}
