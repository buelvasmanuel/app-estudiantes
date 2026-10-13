import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/estadistica.dart';
import 'models/estudiante.dart';
import 'models/prediccion.dart';
import 'models/sesion.dart';
import 'services/almacen_refresh.dart';
import 'services/api_service.dart';
import 'services/cliente_credenciales.dart';
import 'services/sesion.dart';

/// El único [ApiService] de la app. Los tests lo sustituyen con
/// `apiServiceProvider.overrideWithValue(apiFalsa(...))`.
final apiServiceProvider = Provider<ApiService>((ref) {
  final api = ApiService(clienteConCredenciales: clienteConCredenciales());
  ref.onDispose(api.cerrar);
  return api;
});

/// Dónde se guarda el refresh token (seguro en móvil/escritorio, memoria en
/// la web).
final almacenRefreshProvider = Provider<AlmacenRefresh>(
  (ref) => AlmacenRefresh.dePlataforma(),
);

/// Refresh en cookie (CONTRATO_AUTH §6.3): solo en la web. El APK y el
/// escritorio siguen con el refresh en el almacén seguro.
final modoCookieProvider = Provider<bool>((ref) => kIsWeb);

/// La sesión del usuario. Se registra como interceptor del [ApiService] y, si
/// no se le pasan [Tokens], intenta recuperar la sesión guardada.
final sesionProvider = Provider<GestorSesion>((ref) => crearSesion(ref));

/// Lo usan [sesionProvider] y los tests (con [tokens] = sesión ya iniciada).
GestorSesion crearSesion(Ref ref, {Tokens? tokens}) {
  final api = ref.watch(apiServiceProvider);
  final sesion = GestorSesion(
    api: api,
    almacen: ref.watch(almacenRefreshProvider),
    tokens: tokens,
    modoCookie: ref.watch(modoCookieProvider),
  );
  api.interceptores.add(sesion);
  ref.onDispose(() {
    api.interceptores.remove(sesion);
    sesion.dispose();
  });
  if (sesion.estado == EstadoSesion.restaurando) sesion.restaurar();
  return sesion;
}

/// Id del usuario con sesión (o `null`). Cambia al entrar, salir o cambiar
/// de cuenta; no con cada renovación de tokens (es un número, no el objeto).
/// Lo que depende del jugador (progreso, ranking...) lo vigila para
/// rehacerse con otra cuenta.
final usuarioIdProvider = Provider<int?>((ref) {
  final sesion = ref.watch(sesionProvider);
  void cambio() => ref.invalidateSelf();
  sesion.addListener(cambio);
  ref.onDispose(() => sesion.removeListener(cambio));
  return sesion.usuario?.id;
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
