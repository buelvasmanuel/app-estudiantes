import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/estadistica.dart';
import 'models/estudiante.dart';
import 'models/prediccion.dart';
import 'services/api_service.dart';

/// El único [ApiService] de la app. Los tests lo sustituyen con
/// `apiServiceProvider.overrideWithValue(apiFalsa(...))`.
final apiServiceProvider = Provider<ApiService>((ref) {
  final api = ApiService();
  ref.onDispose(api.cerrar);
  return api;
});

/// Sin reintentos automáticos.
///
/// Riverpod 3 reintenta por defecto los providers que fallan. Aquí no
/// conviene: una petición en frío ya espera hasta 60 s, y los errores se
/// muestran con un botón "Reintentar" que decide el usuario. Se pasa a
/// `ProviderScope(retry: sinReintentos)`.
Duration? sinReintentos(int intentos, Object error) => null;

/// `GET /estudiantes/`. No se descarta al salir de la pestaña: la lista se
/// conserva hasta que el usuario pide actualizar.
final estudiantesProvider = FutureProvider<List<Estudiante>>(
  (ref) => ref.watch(apiServiceProvider).obtenerEstudiantes(),
);

/// `GET /estudiantes/estadisticas/{tipo}`, uno por tipo: volver a una
/// estadística ya vista es instantáneo y no repite la petición.
final estadisticaProvider =
    FutureProvider.family<List<Estadistica>, TipoEstadistica>(
      (ref, tipo) => ref.watch(apiServiceProvider).obtenerEstadistica(tipo),
    );

/// `GET /prediccion/metricas` (incluye las carreras del desplegable).
final metricasProvider = FutureProvider<MetricasModelo>(
  (ref) => ref.watch(apiServiceProvider).obtenerMetricas(),
);
