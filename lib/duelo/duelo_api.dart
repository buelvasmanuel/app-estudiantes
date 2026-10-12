import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/api_service.dart';
import 'modelo.dart';

/// Endpoints de docs/CONTRATO_DUELO.md. Todos requieren sesión: pasan por el
/// interceptor.
class DueloApi {
  const DueloApi(this._api, {this.esperas = esperasPorDefecto});

  final ApiService _api;

  /// Cuánto esperar antes de cada reintento de una jugada que no llegó.
  final List<Duration> esperas;

  static const esperasPorDefecto = [Duration(seconds: 1), Duration(seconds: 2)];

  /// Errores tras los que el estado del cliente quedó viejo: se pide de
  /// nuevo el duelo y se sigue desde ahí (§6.5).
  static const _resincronizar = {
    'ronda_incorrecta',
    'no_es_tu_turno',
    'tiempo_agotado',
    'duelo_terminado',
  };

  /// El duelo contra la máquina que estaba a medias, si hay uno.
  Future<String?> enJuegoContraMaquina() async {
    final lista = _api.parsear(
      await _api.get('/duelos?estado=en_juego'),
      DueloResumen.lista,
    );
    return lista
        .where((d) => d.modo == ModoDuelo.maquina && !d.estado.acabado)
        .firstOrNull
        ?.id;
  }

  /// Empieza uno nuevo contra la máquina (si había otro, el servidor lo da
  /// por abandonado).
  Future<Duelo> crear() async => _api.parsear(
    await _api.post('/duelos', {'modo': 'maquina'}),
    Duelo.fromJson,
  );

  Future<Duelo> duelo(String id) async => _api.parsear(
    await _api.get('/duelos/${Uri.encodeComponent(id)}'),
    Duelo.fromJson,
  );

  /// Al abrir: retoma el duelo a medias o empieza uno (§6.1).
  Future<Duelo> abrir() async => switch (await enJuegoContraMaquina()) {
    final id? => duelo(id),
    null => crear(),
  };

  /// Juega [atributo] en [ronda] (`null`: que juegue el rival).
  ///
  /// Repetir la misma jugada es seguro (el servidor no la juega dos veces):
  /// ante un fallo de red o un 5xx se reintenta igual; si sigue fallando, o
  /// si el servidor dice que el cliente va por detrás (409), se devuelve el
  /// estado actual del duelo. Quien llama sabe si la jugada entró viendo si
  /// apareció la ronda en `rondas`.
  Future<Duelo> jugar(String id, int ronda, String? atributo) async {
    for (var intento = 0; ; intento++) {
      try {
        return _api.parsear<Duelo>(
          await _api.post('/duelos/${Uri.encodeComponent(id)}/jugadas', {
            'ronda': ronda,
            'atributo': atributo,
          }),
          Duelo.fromJson,
        );
      } on ApiException catch (e) {
        final transitorio = e.sinConexion || (e.statusCode ?? 0) >= 500;
        if (transitorio && intento < esperas.length) {
          await Future<void>.delayed(esperas[intento]);
          continue;
        }
        if (transitorio || _resincronizar.contains(e.codigo)) {
          return await duelo(id);
        }
        rethrow;
      }
    }
  }

  Future<Duelo> abandonar(String id) async => _api.parsear(
    await _api.post('/duelos/${Uri.encodeComponent(id)}/abandonar', null),
    Duelo.fromJson,
  );
}

final dueloApiProvider = Provider<DueloApi>(
  (ref) => DueloApi(ref.watch(apiServiceProvider)),
);
