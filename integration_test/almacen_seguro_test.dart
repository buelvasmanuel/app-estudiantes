// Comprueba el almacén seguro REAL de la plataforma (Keystore, libsecret,
// DPAPI). En Linux necesita libsecret y un keyring desbloqueado.
//
//   flutter test integration_test/almacen_seguro_test.dart -d linux
import 'package:app_estudiantes/services/almacen_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guarda, lee y borra el refresh token', (_) async {
    final almacen = AlmacenSeguro();
    await almacen.borrar();
    expect(await almacen.leer(), isNull);

    await almacen.guardar('refresh-de-prueba');
    expect(await almacen.leer(), 'refresh-de-prueba');

    await almacen.borrar();
    expect(await almacen.leer(), isNull);
  });
}
