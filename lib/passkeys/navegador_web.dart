import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'navegador.dart';

NavegadorPasskeys crearNavegador() => const _NavegadorWeb();

/// WebAuthn por interoperabilidad con JavaScript (CONTRATO_PASSKEYS §5): las
/// opciones JSON de la API pasan tal cual por `parse…FromJSON` y la
/// credencial vuelve con `toJSON()`.
class _NavegadorWeb extends NavegadorPasskeys {
  const _NavegadorWeb();

  static JSObject? get _pkc =>
      globalContext['PublicKeyCredential'] as JSObject?;

  @override
  bool get soportado {
    final pkc = _pkc;
    return pkc != null &&
        pkc.has('parseCreationOptionsFromJSON') &&
        pkc.has('parseRequestOptionsFromJSON');
  }

  static JSObject get _json => globalContext['JSON']! as JSObject;

  static JSAny? _aJs(Map<String, Object?> m) =>
      _json.callMethod('parse'.toJS, jsonEncode(m).toJS);

  static Map<String, Object?> _deJs(JSAny? credencial) => jsonDecode(
    (_json.callMethod(
              'stringify'.toJS,
              (credencial! as JSObject).callMethod('toJSON'.toJS),
            )!
            as JSString)
        .toDart,
  ) as Map<String, Object?>;

  /// Traduce el `DOMException` del navegador.
  static Exception _error(Object e) {
    final String nombre;
    try {
      nombre = (e as web.DOMException).name;
    } on Object {
      return PasskeyFallo('$e');
    }
    return switch (nombre) {
      // Cancelar el diálogo, no verificar la huella o PIN, o que se acabe el
      // tiempo: el navegador no distingue (a propósito, por privacidad).
      'NotAllowedError' || 'AbortError' => const PasskeyCancelada(),
      'InvalidStateError' => const PasskeyYaEnEsteDispositivo(),
      'NotSupportedError' => const PasskeyNoSoportada(),
      _ => PasskeyFallo(nombre),
    };
  }

  @override
  Future<Map<String, Object?>> crear(Map<String, Object?> opciones) async {
    if (!soportado) throw const PasskeyNoSoportada();
    try {
      final publicKey = _pkc!.callMethod(
        'parseCreationOptionsFromJSON'.toJS,
        _aJs(opciones),
      );
      final credencial = await web.window.navigator.credentials
          .create(
            (JSObject()..['publicKey'] = publicKey)
                as web.CredentialCreationOptions,
          )
          .toDart;
      return _deJs(credencial);
    } on Object catch (e) {
      throw _error(e);
    }
  }

  @override
  Future<Map<String, Object?>> obtener(Map<String, Object?> opciones) async {
    if (!soportado) throw const PasskeyNoSoportada();
    try {
      final publicKey = _pkc!.callMethod(
        'parseRequestOptionsFromJSON'.toJS,
        _aJs(opciones),
      );
      final credencial = await web.window.navigator.credentials
          .get(
            (JSObject()..['publicKey'] = publicKey)
                as web.CredentialRequestOptions,
          )
          .toDart;
      return _deJs(credencial);
    } on Object catch (e) {
      throw _error(e);
    }
  }
}
