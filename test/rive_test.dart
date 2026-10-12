import 'dart:io' as io;

import 'package:app_estudiantes/laboratorio/apariencia.dart';
import 'package:app_estudiantes/laboratorio/apariencia_rive.dart';
import 'package:app_estudiantes/tema/temas.dart';
import 'package:app_estudiantes/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart' as rive;

/// Un AssetBundle con solo [archivos] (ruta → bytes).
class _Bundle extends CachingAssetBundle {
  _Bundle(this.archivos);

  final Map<String, List<int>> archivos;

  @override
  Future<ByteData> load(String key) async {
    final bytes = archivos[key];
    if (bytes == null) throw FlutterError('No existe $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

final _rating = io.File('test/fixtures/rive/rating.riv').readAsBytesSync();

void main() {
  group('valores para el view model (CONTRATO_RIVE)', () {
    for (final tema in TemaJuego.values) {
      test(
        'búho (${tema.name}): las propiedades del contrato, con su tipo',
        () {
          final v = valoresBuho(tema.datos, AnimoBuho.contento, quieto: true);
          expect(v.keys.toSet(), ContratoRive.buho.propiedades.keys.toSet());
          expect(v['animo'], 'contento');
          expect(v['quieto'], isTrue);
          for (final color in ['plumas', 'barriga', 'ojo', 'pupila', 'pico']) {
            expect(v[color], isA<Color>(), reason: color);
          }
        },
      );

      test('medidor (${tema.name}): porcentajes 0-100 y colores del tema', () {
        final estado = tema.datos.extension<ColoresEstado>()!;
        final v = valoresMedidor(
          tema.datos,
          estado,
          probabilidad: 0.493,
          objetivo: 0.5,
          quieto: false,
        );
        expect(v.keys.toSet(), ContratoRive.medidor.propiedades.keys.toSet());
        expect(v['probabilidad'], closeTo(49.3, 1e-9));
        expect(v['objetivo'], 50.0);
        expect(v['ok'], estado.ok);
        expect(v['riesgo'], estado.riesgo);
        expect(
          valoresMedidor(
            tema.datos,
            estado,
            probabilidad: 1.2,
            objetivo: 0.5,
            quieto: false,
          )['probabilidad'],
          100.0,
        );
      });
    }

    test('cada tipo de valor coincide con el del contrato', () {
      Object tipoDe(Object v) => switch (v) {
        String() => rive.DataType.enumType,
        bool() => rive.DataType.boolean,
        double() => rive.DataType.number,
        Color() => rive.DataType.color,
        _ => v.runtimeType,
      };
      final tema = TemaJuego.noche.datos;
      final buho = valoresBuho(tema, AnimoBuho.atento, quieto: false);
      final medidor = valoresMedidor(
        tema,
        tema.extension<ColoresEstado>()!,
        probabilidad: 0.2,
        objetivo: 0.5,
        quieto: false,
      );
      for (final (valores, contrato) in [
        (buho, ContratoRive.buho),
        (medidor, ContratoRive.medidor),
      ]) {
        for (final MapEntry(:key, :value) in valores.entries) {
          expect(tipoDe(value), contrato.propiedades[key], reason: key);
        }
      }
    });
  });

  group('archivos .riv', () {
    testWidgets('un .riv que no cumple: el validador dice qué falta', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final archivo = await rive.File.decode(
          Uint8List.fromList(_rating),
          riveFactory: rive.Factory.flutter,
        );
        expect(archivo, isNotNull);
        expect(ContratoRive.buho.problemas(archivo!), [
          'Buho: falta el artboard «Buho»',
        ]);
        expect(ContratoRive.medidor.problemas(archivo), [
          'Medidor: falta el artboard «Medidor»',
        ]);
        archivo.dispose();
      });
    });

    testWidgets('sin archivos o que no cumplen: null (se usa Flutter)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        expect(await cargarRive(ContratoRive.buho, _Bundle({})), isNull);
        final bundle = _Bundle({
          ContratoRive.buho.ruta: _rating,
          ContratoRive.medidor.ruta: [1, 2, 3], // ni siquiera es un .riv
        });
        expect(await cargarRive(ContratoRive.buho, bundle), isNull);
        expect(await cargarRive(ContratoRive.medidor, bundle), isNull);
      });
    });
  });

  testWidgets('sin .riv en assets/rive, la app usa el búho y el medidor de '
      'Flutter', (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: TemaJuego.noche.datos,
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              final a = r.watch(aparienciaLaboratorioProvider);
              return Column(
                children: [
                  a.buho(animo: AnimoBuho.pensando),
                  SizedBox(
                    width: 300,
                    child: a.medidor(probabilidad: 0.6, objetivo: 0.5),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.runAsync(() => ref.read(archivosRiveProvider.future));
    await tester.pump();
    expect(ref.read(archivosRiveProvider).value?.vacio, isTrue);
    expect(ref.read(aparienciaLaboratorioProvider), isA<AparienciaFlutter>());
    expect(find.byType(Buho), findsOneWidget);
    expect(find.byType(MedidorRiesgo), findsOneWidget);
  });

  testWidgets('con solo uno de los dos .riv, el otro sigue en Flutter', (
    tester,
  ) async {
    // Sin archivos válidos en el test, se comprueba el reparto: lo que es
    // null se delega en Flutter.
    const apariencia = AparienciaRive(ArchivosRive());
    await tester.pumpWidget(
      MaterialApp(
        theme: TemaJuego.expediente.datos,
        home: Column(
          children: [
            apariencia.buho(animo: AnimoBuho.contento),
            SizedBox(
              width: 300,
              child: apariencia.medidor(probabilidad: 0.4, objetivo: 0.5),
            ),
          ],
        ),
      ),
    );
    expect(find.byType(Buho), findsOneWidget);
    expect(find.byType(MedidorRiesgo), findsOneWidget);
    expect(find.byKey(const Key('porcentaje-medidor')), findsOneWidget);
  });
}
