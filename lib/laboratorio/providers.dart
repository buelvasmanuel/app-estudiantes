import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'laboratorio_api.dart';
import 'modelo.dart';

final laboratorioApiProvider = Provider<LaboratorioApi>(
  (ref) => LaboratorioApi(ref.watch(apiServiceProvider)),
);

/// `GET /laboratorio/casos`: todos los casos válidos, del más grave al más
/// leve.
final casosProvider = FutureProvider<ListaCasos>(
  (ref) => ref.watch(laboratorioApiProvider).casos(),
);

/// `GET /laboratorio/casos/{id}`.
final casoProvider = FutureProvider.family<Caso, int>(
  (ref, id) => ref.watch(laboratorioApiProvider).caso(id),
);

/// Probabilidad de cada combinación de intervenciones del caso (una sola
/// petición a `/prediccion/riesgo/lote`): el medidor responde al instante.
final probabilidadesProvider = FutureProvider.family<Map<String, double>, int>(
  (ref, id) async => ref
      .watch(laboratorioApiProvider)
      .probabilidades(await ref.watch(casoProvider(id).future)),
);
