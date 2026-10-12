import 'dart:io';

import 'package:flutter/services.dart';

/// Carga las fuentes de la app (assets/fuentes) en el test. Sin esto, los
/// tests usan Ahem (cada letra, un cuadrado de 1 em) y las medidas de alto y
/// ancho no se parecen a las reales.
Future<void> cargarFuentesReales() async {
  const familias = {
    'Fredoka': 'fredoka',
    'Nunito': 'nunito',
    'CourierPrime': 'courierprime',
    'AtkinsonHyperlegible': 'atkinsonhyperlegible',
  };
  for (final MapEntry(key: familia, value: carpeta) in familias.entries) {
    final cargador = FontLoader(familia);
    for (final archivo in Directory('assets/fuentes/$carpeta').listSync()) {
      if (archivo.path.endsWith('.ttf')) {
        final bytes = (archivo as File).readAsBytesSync();
        cargador.addFont(
          Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
        );
      }
    }
    await cargador.load();
  }
}
