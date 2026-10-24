import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/estadistica.dart';
import '../models/estudiante.dart';
import '../models/prediccion.dart';

/// Error "amigable" de la API: [mensaje] está pensado para mostrarse tal cual
/// en pantalla.
class ApiException implements Exception {
  const ApiException(
    this.mensaje, {
    this.statusCode,
    this.codigo,
    this.reintentarEn,
    this.esTimeout = false,
    this.detalle,
  });

  final String mensaje;

  /// Código HTTP (404, 422, 503...) o `null` si ni siquiera hubo respuesta.
  final int? statusCode;

  /// Código de error de la API (`detail.codigo`: `token_expirado`,
  /// `credenciales_invalidas`...). La app decide por él, nunca por el texto.
  final String? codigo;

  /// Cabecera `Retry-After` de un 429: cuánto esperar antes de reintentar.
  final Duration? reintentarEn;

  /// El `detail` de un error con código, entero: algunos traen datos extra
  /// (`aliases` en un 409 de `/usuarios/lote`, `opciones` en un 422...).
  final Map<String, Object?>? detalle;

  /// `true` si no hubo respuesta porque se agotó el tiempo de espera (la API
  /// pudo recibir y procesar la petición); `false` si la conexión falló.
  final bool esTimeout;

  bool get sinConexion => statusCode == null;

  @override
  String toString() => mensaje;
}

/// Una petición a la API antes de enviarse. Los interceptores pueden cambiar
/// sus [cabeceras] (p. ej. añadir `Authorization`).
class PeticionApi {
  PeticionApi(
    this.metodo,
    this.ruta, {
    this.cuerpo,
    Map<String, String>? cabeceras,
    this.conInterceptores = true,
    this.limite,
    this.conCredenciales = false,
  }) : cabeceras = {...?cabeceras};

  /// `GET`, `POST`, `PUT`, `PATCH` o `DELETE`.
  final String metodo;

  /// Ruta desde la URL base, con la barra inicial: `/estudiantes/`.
  final String ruta;

  /// Se envía como JSON. `null` = sin cuerpo.
  final Object? cuerpo;

  final Map<String, String> cabeceras;

  /// `false` para saltarse los interceptores. Lo necesita, por ejemplo, la
  /// propia petición que renueva el token: si pasara por el interceptor de
  /// sesión, este intentaría renovarlo otra vez.
  final bool conInterceptores;

  /// Tiempo máximo de espera propio. `null` = el normal (8 s, o 60 s si el
  /// servidor puede estar dormido). Con una API en `localhost`, `127.x` o
  /// `10.0.2.2` siempre es el normal.
  final Duration? limite;

  /// En la web, enviar las cookies (`withCredentials`): el refresh en cookie
  /// (CONTRATO_AUTH §6.3). Fuera de la web no cambia nada.
  final bool conCredenciales;

  /// 1 la primera vez, 2 si se está repitiendo. Lo actualiza [ApiService].
  int intento = 1;

  @override
  String toString() => '$metodo $ruta';
}

/// Lógica común a todas las peticiones (por ejemplo, la sesión).
///
/// Se registra en [ApiService.interceptores] y se ejecuta en orden.
abstract class InterceptorApi {
  const InterceptorApi();

  /// Se llama antes de enviar [peticion], también antes de repetirla.
  Future<void> antesDeEnviar(PeticionApi peticion) async {}

  /// Se llama cada vez que [peticion] termina con [error]. Si es el primer
  /// intento (`peticion.intento == 1`), devolver `true` la repite: sirve para
  /// renovar un token caducado y volver a intentarlo. Una petición se repite
  /// como máximo una vez, aunque varios interceptores lo pidan; en el segundo
  /// intento el valor devuelto se ignora (pero el interceptor se entera).
  Future<bool> reintentar(PeticionApi peticion, ApiException error) async =>
      false;
}

/// Único punto de la app que habla con la API.
///
/// Recibe el `http.Client` por el constructor para que los tests puedan
/// pasarle un `MockClient` y simular respuestas sin red.
class ApiService {
  ApiService({
    http.Client? client,
    this._clienteConCredenciales,
    String? baseUrl,
    List<InterceptorApi>? interceptores,
  }) : _client = client ?? http.Client(),
       baseUrl = baseUrl ?? Config.apiUrl,
       interceptores = [...?interceptores];

  final http.Client _client;

  /// Para las peticiones [PeticionApi.conCredenciales] (solo web; si es
  /// `null`, se usa el normal).
  final http.Client? _clienteConCredenciales;
  final String baseUrl;

  /// Se pueden añadir después de crear el servicio (el de la sesión necesita
  /// el propio [ApiService] para renovar el token).
  final List<InterceptorApi> interceptores;

  /// `true` mientras el servidor está tardando en arrancar (Render free).
  /// Las pantallas de carga lo escuchan para mostrar un aviso.
  final ValueNotifier<bool> despertando = ValueNotifier(false);

  DateTime? _ultimaRespuesta;
  int _peticionesEnFrio = 0;

  /// El servidor puede estar dormido si nunca respondió o si lleva mucho
  /// tiempo sin hacerlo.
  bool get _enFrio {
    final ultima = _ultimaRespuesta;
    return ultima == null ||
        DateTime.now().difference(ultima) > Config.inactividadParaDormir;
  }

  /// Las direcciones de la red local nunca "se duermen": solo cambia el
  /// consejo que se da cuando fallan.
  bool get _esLocal =>
      RegExp(r'//(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)')
          .hasMatch(baseUrl);

  /// `localhost`, `127.x` o `10.0.2.2` (el PC visto desde el emulador de
  /// Android): solo existen en este equipo o en el emulador. No hay nada que
  /// despertar: si no responden, la API no está corriendo o la app corre en
  /// otro aparato (p. ej. un celular real lanzado sin `API_URL`).
  bool get _soloEsteEquipo {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    return host == 'localhost' || host == '10.0.2.2' || host.startsWith('127.');
  }

  String get _consejo {
    if (_soloEsteEquipo) {
      final donde = Uri.tryParse(baseUrl)?.host == '10.0.2.2'
          ? 'solo funciona en el emulador de Android (es el PC visto desde '
                'el emulador)'
          : 'solo funciona en este mismo equipo';
      return 'Esa dirección es local: $donde. Si la app corre ahí, comprueba que la '
          'API está corriendo (uvicorn app.main:app --reload --host 0.0.0.0). '
          'En un celular real, lanza la app con la dirección de la API:\n'
          'flutter run --dart-define=API_URL=http://<IP del PC>:8000\n'
          '(o la URL de la API en Render).';
    }
    return _esLocal
        ? '¿Está corriendo? uvicorn app.main:app --reload --host 0.0.0.0'
        : 'Comprueba tu conexión a internet.';
  }

  // --- Endpoints -------------------------------------------------------------

  Future<List<Estudiante>> obtenerEstudiantes() async =>
      parsear(await get('/estudiantes/'), Estudiante.listaFromJson);

  Future<List<Estadistica>> obtenerEstadistica(TipoEstadistica tipo) async =>
      parsear(
        await get('/estudiantes/estadisticas/${tipo.ruta}'),
        Estadistica.listaFromJson,
      );

  Future<MetricasModelo> obtenerMetricas() async =>
      parsear(await get('/prediccion/metricas'), MetricasModelo.fromJson);

  Future<ResultadoPrediccion> predecirRiesgo(EntradaPrediccion entrada) async =>
      parsear(
        await post('/prediccion/riesgo', entrada.toJson()),
        ResultadoPrediccion.fromJson,
      );

  // --- Peticiones genéricas -------------------------------------------------

  Future<Object?> get(String ruta) => enviar(PeticionApi('GET', ruta));

  Future<Object?> post(String ruta, Object? cuerpo) =>
      enviar(PeticionApi('POST', ruta, cuerpo: cuerpo));

  Future<Object?> put(String ruta, Object? cuerpo) =>
      enviar(PeticionApi('PUT', ruta, cuerpo: cuerpo));

  Future<Object?> patch(String ruta, Object? cuerpo) =>
      enviar(PeticionApi('PATCH', ruta, cuerpo: cuerpo));

  Future<Object?> delete(String ruta) => enviar(PeticionApi('DELETE', ruta));

  /// Envía [peticion] pasando por los [interceptores] (salvo que
  /// `conInterceptores` sea `false`) y devuelve el JSON decodificado.
  Future<Object?> enviar(PeticionApi peticion) async {
    final activos = peticion.conInterceptores
        ? List.of(interceptores) // copia: la lista puede cambiar mientras
        : const <InterceptorApi>[];
    for (peticion.intento = 1; ; peticion.intento++) {
      for (final i in activos) {
        await i.antesDeEnviar(peticion);
      }
      try {
        return await _enviar(peticion);
      } on ApiException catch (error) {
        var repetir = false;
        for (final i in activos) {
          // Se consulta a todos (no se corta en el primero que dice "sí"):
          // cada uno puede necesitar reaccionar al error.
          if (await i.reintentar(peticion, error)) repetir = true;
        }
        if (!repetir || peticion.intento > 1) rethrow;
      }
    }
  }

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

  void cerrar() {
    despertando.dispose();
    _client.close();
    _clienteConCredenciales?.close();
  }

  // --- Detalles internos ----------------------------------------------------

  Future<Object?> _enviar(PeticionApi peticion) async {
    // Una dirección de este equipo no se duerme: sin aviso de «despertando»
    // y con el tiempo de espera normal.
    final enFrio = _enFrio && !_soloEsteEquipo;
    // Los límites largos (p. ej. los 60 s de `/auth/*`) son para esperar a
    // que Render despierte; en este equipo, el normal.
    final limite = _soloEsteEquipo
        ? Config.timeout
        : peticion.limite ?? (enFrio ? Config.timeoutArranque : Config.timeout);
    Timer? aviso;
    if (enFrio) {
      _peticionesEnFrio++;
      aviso = Timer(Config.avisoDespertar, () => despertando.value = true);
    }

    final http.Response respuesta;
    try {
      respuesta = await _hacer(peticion).timeout(limite);
    } on TimeoutException {
      throw ApiException(
        'La API no respondió en ${limite.inSeconds} s ($baseUrl). '
        '${_soloEsteEquipo
            ? _consejo
            : _esLocal
            ? 'Comprueba que uvicorn está corriendo y que la dirección es correcta.'
            : 'El servidor puede estar caído; inténtalo de nuevo en un momento.'}',
        esTimeout: true,
      );
    } on http.ClientException {
      // En Linux/Android, http convierte el SocketException ("conexión
      // rechazada") en ClientException; en web, también llega así.
      throw ApiException(
        'No se pudo conectar con la API en $baseUrl.\n$_consejo',
      );
    } finally {
      if (enFrio) {
        aviso?.cancel();
        _peticionesEnFrio--;
        if (_peticionesEnFrio == 0) despertando.value = false;
      }
    }
    // Cualquier respuesta HTTP (aunque sea un error 4xx/5xx) indica que el
    // servidor ya está despierto.
    _ultimaRespuesta = DateTime.now();

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
    final detalle = datos is Map<String, Object?> ? datos['detail'] : null;
    final segundos = int.tryParse(respuesta.headers['retry-after'] ?? '');
    throw switch (detalle) {
      // Errores con código (autenticación): el mensaje de la API está pensado
      // para mostrarse tal cual, sin "Error (401):" delante.
      {'codigo': final String codigo, 'mensaje': final String mensaje} =>
        ApiException(
          mensaje,
          statusCode: respuesta.statusCode,
          codigo: codigo,
          reintentarEn: segundos == null ? null : Duration(seconds: segundos),
          detalle: detalle as Map<String, Object?>,
        ),
      _ => ApiException(
        _mensajeDeError(respuesta.statusCode, datos),
        statusCode: respuesta.statusCode,
        reintentarEn: segundos == null ? null : Duration(seconds: segundos),
      ),
    };
  }

  /// Una petición HTTP nueva en cada intento: un `http.Request` no se puede
  /// enviar dos veces.
  Future<http.Response> _hacer(PeticionApi peticion) async {
    final request = http.Request(
      peticion.metodo,
      Uri.parse('$baseUrl${peticion.ruta}'),
    )..headers.addAll(peticion.cabeceras);
    if (peticion.cuerpo != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(peticion.cuerpo);
    }
    final cliente = peticion.conCredenciales
        ? _clienteConCredenciales ?? _client
        : _client;
    return http.Response.fromStream(await cliente.send(request));
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
      401 => 'No autorizado',
      403 => 'Sin permiso',
      404 => 'No encontrado',
      409 => 'Conflicto',
      422 => 'Datos no válidos',
      429 => 'Demasiadas peticiones',
      503 => 'Servicio no disponible',
      >= 500 => 'Error interno de la API',
      _ => 'Error',
    };
    return texto == null || texto.isEmpty
        ? '$explicacion ($status).'
        : '$explicacion ($status): $texto';
  }
}
