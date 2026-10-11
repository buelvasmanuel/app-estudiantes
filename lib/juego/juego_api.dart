import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/json_utils.dart';
import '../providers.dart';
import '../services/api_service.dart';
import 'modelo.dart';

/// Endpoints de docs/CONTRATO_JUEGO.md y `POST /usuarios/lote`. Todos
/// requieren sesión: pasan por el interceptor.
class JuegoApi {
  const JuegoApi(this._api);

  final ApiService _api;

  Future<List<CasoJuegoResumen>> casos() async =>
      _api.parsear(await _api.get('/juego/casos'), CasoJuegoResumen.lista);

  Future<CasoJuego> caso(String codigo) async => _api.parsear(
    await _api.get('/juego/casos/${Uri.encodeComponent(codigo)}'),
    CasoJuego.fromJson,
  );

  Future<RespuestaCaso> responder(String codigo, String respuesta) async =>
      _api.parsear(
        await _api.post(
          '/juego/casos/${Uri.encodeComponent(codigo)}/responder',
          {'respuesta': respuesta},
        ),
        RespuestaCaso.fromJson,
      );

  Future<Progreso> progreso() async =>
      _api.parsear(await _api.get('/juego/progreso'), Progreso.fromJson);

  Future<Ranking> ranking(PeriodoRanking periodo) async => _api.parsear(
    await _api.get('/juego/ranking?periodo=${periodo.name}'),
    Ranking.fromJson,
  );

  Future<List<Jugador>> jugadores() async => _api.parsear(
    await _api.get('/juego/jugadores'),
    (json) => comoLista(json).map(Jugador.fromJson).toList(),
  );

  /// Crea de 1 a 40 cuentas de jugador; todas o ninguna.
  Future<List<CuentaCreada>> crearLote(List<String> aliases) async =>
      _api.parsear(
        await _api.post('/usuarios/lote', {'aliases': aliases}),
        (json) =>
            comoLista(comoMapa(json, 'lote')['cuentas'])
                .map(CuentaCreada.fromJson)
                .toList(),
      );
}

final juegoApiProvider = Provider<JuegoApi>(
  (ref) => JuegoApi(ref.watch(apiServiceProvider)),
);

// Lo que depende del usuario se rehace al cambiar de sesión (otro jugador).
// Sin sesión no se pide nada: la API respondería 401.
void _idUsuario(Ref ref) {
  if (ref.watch(usuarioIdProvider) == null) {
    throw const ApiException('Inicia sesión para jugar.', statusCode: 401);
  }
}

final casosJuegoProvider = FutureProvider<List<CasoJuegoResumen>>((ref) {
  _idUsuario(ref);
  return ref.watch(juegoApiProvider).casos();
});

final casoJuegoProvider = FutureProvider.family<CasoJuego, String>((
  ref,
  codigo,
) {
  _idUsuario(ref);
  return ref.watch(juegoApiProvider).caso(codigo);
});

final progresoProvider = FutureProvider<Progreso>((ref) {
  _idUsuario(ref);
  return ref.watch(juegoApiProvider).progreso();
});

final rankingProvider = FutureProvider.family<Ranking, PeriodoRanking>((
  ref,
  periodo,
) {
  _idUsuario(ref);
  return ref.watch(juegoApiProvider).ranking(periodo);
});

final jugadoresProvider = FutureProvider<List<Jugador>>((ref) {
  _idUsuario(ref);
  return ref.watch(juegoApiProvider).jugadores();
});

/// Tras ganar (o intentar ganar) XP: lo que muestra el progreso queda viejo.
void progresoCambiado(WidgetRef ref) {
  ref
    ..invalidate(progresoProvider)
    ..invalidate(rankingProvider)
    ..invalidate(casosJuegoProvider);
}
