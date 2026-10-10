import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/estudiante.dart';

/// Error "amigable" de la API: [mensaje] está pensado para mostrarse tal cual
/// en pantalla.
class ApiException implements Exception {
  const ApiException(this.mensaje, {this.statusCode});

  final String mensaje;

  /// Código HTTP (404, 422, 503...) o `null` si ni siquiera hubo respuesta.
  final int? statusCode;

  bool get sinConexion => statusCode == null;

  @override
  String toString() => mensaje;
}

/// Único punto de la app que habla con la API.
///
/// Recibe el `http.Client` por el constructor para que los tests puedan
/// pasarle un `MockClient` y simular respuestas sin red.
class ApiService {
  ApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? Config.apiUrl;

  final http.Client _client;
  final String baseUrl;

  // --- Endpoints -------------------------------------------------------------

  Future<List<Estudiante>> obtenerEstudiantes() async =>
      parsear(await get('/estudiantes/'), Estudiante.listaFromJson);

  // --- Peticiones genéricas -------------------------------------------------

  Future<Object?> get(String ruta) =>
      _enviar(() => _client.get(Uri.parse('$baseUrl$ruta')));

  Future<Object?> post(String ruta, Map<String, Object?> cuerpo) => _enviar(
    () => _client.post(
      Uri.parse('$baseUrl$ruta'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(cuerpo),
    ),
  );

  /// Convierte el JSON en modelos. Si el formato no es el esperado, lo
  /// transforma en un [ApiException] con un mensaje claro.
  T parsear<T>(Object? json, T Function(Object? json) convertir) {
    try {
      return convertir(json);
    } on FormatException catch (e) {
      throw ApiException(
        'La API respondió con un formato inesperado (${e.message}). '
        '¿Es la versión correcta de la API?',
      );
    }
  }

  void cerrar() => _client.close();

  // --- Detalles internos ----------------------------------------------------

  Future<Object?> _enviar(Future<http.Response> Function() peticion) async {
    final http.Response respuesta;
    try {
      respuesta = await peticion().timeout(Config.timeout);
    } on TimeoutException {
      throw ApiException(
        'La API no respondió en ${Config.timeout.inSeconds} s ($baseUrl). '
        'Comprueba que uvicorn está corriendo y que la dirección es correcta.',
      );
    } on http.ClientException {
      // En Linux/Android, http convierte el SocketException ("conexión
      // rechazada") en ClientException; en web, también llega así.
      throw ApiException(
        'No se pudo conectar con la API en $baseUrl.\n'
        '¿Está corriendo? uvicorn app.main:app --reload --host 0.0.0.0',
      );
    }

    final ok = respuesta.statusCode >= 200 && respuesta.statusCode < 300;
    final Object? datos;
    try {
      // FastAPI no indica "charset" en el Content-Type; decodificamos los
      // bytes como UTF-8 a mano para que "Ingeniería" no salga "IngenierÃ­a".
      datos = respuesta.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(respuesta.bodyBytes));
    } on FormatException {
      if (ok) {
        throw const ApiException('La API respondió algo que no es JSON.');
      }
      throw ApiException(
        'Error ${respuesta.statusCode} de la API.',
        statusCode: respuesta.statusCode,
      );
    }

    if (ok) return datos;
    throw ApiException(
      _mensajeDeError(respuesta.statusCode, datos),
      statusCode: respuesta.statusCode,
    );
  }

  /// FastAPI envía los errores como `{"detail": ...}`, y `detail` puede ser:
  /// - un texto: `"Modelo no entrenado..."` (503, 404)
  /// - un objeto propio: `{"mensaje": "...", "carreras_validas": [...]}`
  /// - la lista de errores de validación de Pydantic: `[{"msg": "..."}]` (422)
  static String _mensajeDeError(int status, Object? datos) {
    final detalle = datos is Map<String, Object?> ? datos['detail'] : null;
    final String? texto = switch (detalle) {
      final String s => s,
      {'mensaje': final String m} => m,
      final List<Object?> errores =>
        errores
            .map((e) => e is Map<String, Object?> ? e['msg'] : null)
            .whereType<String>()
            .join('\n'),
      _ => null,
    };
    final explicacion = switch (status) {
      404 => 'No encontrado',
      422 => 'Datos no válidos',
      503 => 'Servicio no disponible',
      >= 500 => 'Error interno de la API',
      _ => 'Error',
    };
    return texto == null || texto.isEmpty
        ? '$explicacion ($status).'
        : '$explicacion ($status): $texto';
  }
}
