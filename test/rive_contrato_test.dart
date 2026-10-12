// Comprueba los .riv entregados en assets/rive/ contra docs/CONTRATO_RIVE.md.
//
//   flutter test test/rive_contrato_test.dart
//
// Si aún no están, el test se salta (la app usa el búho de Flutter).
import 'dart:io' as io;

import 'package:app_estudiantes/laboratorio/apariencia_rive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart' as rive;

void main() {
  for (final contrato in [ContratoRive.buho, ContratoRive.medidor]) {
    final archivo = io.File(contrato.ruta);
    testWidgets(
      '${contrato.ruta} cumple el contrato',
      skip: !archivo.existsSync(),
      (tester) async {
        final bytes = archivo.readAsBytesSync();
        expect(
          bytes.length,
          lessThanOrEqualTo(150 * 1024),
          reason: 'más de 150 KB',
        );
        await tester.runAsync(() async {
          final rive.File? f = await rive.File.decode(
            Uint8List.fromList(bytes),
            riveFactory: rive.Factory.flutter,
          );
          expect(f, isNotNull, reason: 'no es un .riv válido');
          expect(contrato.problemas(f!), isEmpty);
          f.dispose();
        });
      },
    );
  }
}
