import '../models/json_utils.dart';

/// `PasskeyOut` (CONTRATO_PASSKEYS §2.2).
class Passkey {
  const Passkey({
    required this.id,
    required this.nombre,
    required this.creadaEn,
    required this.ultimoUso,
    required this.sincronizada,
  });

  final int id;
  final String nombre;
  final DateTime? creadaEn;
  final DateTime? ultimoUso;

  /// El proveedor la copia entre dispositivos (gestor de Google o Apple).
  final bool sincronizada;

  static DateTime? _fecha(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory Passkey.fromJson(Object? json) {
    final m = comoMapa(json, 'passkey');
    return Passkey(
      id: leerInt(m, 'id'),
      nombre: leerString(m, 'nombre'),
      creadaEn: _fecha(m['creada_en']),
      ultimoUso: _fecha(m['ultimo_uso']),
      sincronizada: m['sincronizada'] == true,
    );
  }

  static List<Passkey> lista(Object? json) =>
      comoLista(json).map(Passkey.fromJson).toList();
}

/// Las opciones de un paso de WebAuthn y su reto (de un solo uso, 5 min).
typedef OpcionesPasskey = ({String retoId, Map<String, Object?> opciones});

OpcionesPasskey opcionesPasskey(Object? json) {
  final m = comoMapa(json, 'opciones de passkey');
  return (
    retoId: leerString(m, 'reto_id'),
    opciones: comoMapa(m['opciones'], 'opciones'),
  );
}
