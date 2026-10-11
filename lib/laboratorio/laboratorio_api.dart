import '../models/json_utils.dart';
import '../models/prediccion.dart';
import '../services/api_service.dart';
import 'modelo.dart';
import 'rescate.dart';

/// Endpoints del Laboratorio (docs/CONTRATO_LABORATORIO.md). Van por el
/// mismo [ApiService], así que `/laboratorio/*` lleva el token de la sesión
/// y se renueva solo.
class LaboratorioApi {
  const LaboratorioApi(this._api);

  final ApiService _api;

  Future<ListaCasos> casos() async =>
      _api.parsear(await _api.get('/laboratorio/casos'), ListaCasos.fromJson);

  Future<Caso> caso(int estudianteId) async => _api.parsear(
    await _api.get('/laboratorio/casos/$estudianteId'),
    Caso.fromJson,
  );

  /// Probabilidad de cada entrada, en el mismo orden (máx. 50).
  Future<List<double>> lote(List<EntradaPrediccion> entradas) async =>
      _api.parsear(
        await _api.post('/prediccion/riesgo/lote', {
          'entradas': [for (final e in entradas) e.toJson()],
        }),
        (json) => [
          for (final r in comoLista(comoMapa(json, 'lote')['resultados']))
            leerNum(comoMapa(r, 'resultado'), 'probabilidad').toDouble(),
        ],
      );

  /// Probabilidad de cada combinación posible del caso, por
  /// [Rescate.claveDe]. Una sola petición.
  Future<Map<String, double>> probabilidades(Caso caso) async {
    final combinaciones = Rescate.combinaciones(caso);
    final resultados = await lote([
      for (final c in combinaciones) Rescate.entradaPara(caso, c),
    ]);
    if (resultados.length != combinaciones.length) {
      throw const ApiException(
        'La API devolvió un número de resultados distinto al pedido.',
      );
    }
    return {
      for (final (i, c) in combinaciones.indexed)
        Rescate.claveDe(c): resultados[i],
    };
  }

  Future<ResultadoRescate> resolver(
    int estudianteId,
    List<String> intervenciones,
  ) async => _api.parsear(
    await _api.post('/laboratorio/casos/$estudianteId/resolver', {
      'intervenciones': intervenciones,
    }),
    ResultadoRescate.fromJson,
  );
}
