import 'navegador.dart';

/// En el APK y en el escritorio no hay passkeys (por ahora, solo web).
NavegadorPasskeys crearNavegador() => const _SinSoporte();

class _SinSoporte extends NavegadorPasskeys {
  const _SinSoporte();

  @override
  bool get soportado => false;

  @override
  Future<Map<String, Object?>> crear(Map<String, Object?> opciones) =>
      throw const PasskeyNoSoportada();

  @override
  Future<Map<String, Object?>> obtener(Map<String, Object?> opciones) =>
      throw const PasskeyNoSoportada();
}
