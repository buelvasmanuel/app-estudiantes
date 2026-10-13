import 'navegador_sin_soporte.dart'
    if (dart.library.js_interop) 'navegador_web.dart'
    as plataforma;

/// Lo que el navegador hace con las passkeys (WebAuthn). Interfaz para que
/// los tests la simulen; la real solo existe en la web.
abstract class NavegadorPasskeys {
  const NavegadorPasskeys();

  /// `window.PublicKeyCredential` con `parse…FromJSON` (Chrome/Edge 129+,
  /// Firefox 119+, Safari 18.4+). Si no, no se ofrece nada de passkeys.
  bool get soportado;

  /// `navigator.credentials.create` con las opciones JSON de la API;
  /// devuelve `credential.toJSON()`.
  Future<Map<String, Object?>> crear(Map<String, Object?> opciones);

  /// `navigator.credentials.get` con las opciones JSON de la API; devuelve
  /// `credential.toJSON()`.
  Future<Map<String, Object?>> obtener(Map<String, Object?> opciones);
}

/// El de esta plataforma: en la web, el del navegador; en el APK y en el
/// escritorio, uno sin soporte.
NavegadorPasskeys navegadorDelSistema() => plataforma.crearNavegador();

/// El usuario cerró o canceló el diálogo del navegador (o no verificó su
/// huella o PIN a tiempo). No es un error: puede volver a intentarlo.
class PasskeyCancelada implements Exception {
  const PasskeyCancelada();
}

/// Este dispositivo ya guarda una passkey de esta cuenta.
class PasskeyYaEnEsteDispositivo implements Exception {
  const PasskeyYaEnEsteDispositivo();
}

/// El navegador no admite passkeys.
class PasskeyNoSoportada implements Exception {
  const PasskeyNoSoportada();
}

/// Otro fallo del navegador ([nombre]: el del `DOMException`).
class PasskeyFallo implements Exception {
  const PasskeyFallo(this.nombre);

  final String nombre;

  @override
  String toString() => 'PasskeyFallo($nombre)';
}
