import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' as rive;

import '../formato.dart';
import '../theme.dart';
import 'apariencia.dart';

/// Lo que pide docs/CONTRATO_RIVE.md a cada archivo: artboard, máquina de
/// estados y propiedades del view model (con su tipo).
class ContratoRive {
  const ContratoRive({
    required this.ruta,
    required this.artboard,
    required this.maquina,
    required this.propiedades,
  });

  final String ruta;
  final String artboard;
  final String maquina;
  final Map<String, rive.DataType> propiedades;

  static const buho = ContratoRive(
    ruta: 'assets/rive/buho.riv',
    artboard: 'Buho',
    maquina: 'Buho',
    propiedades: {
      'animo': rive.DataType.enumType,
      'quieto': rive.DataType.boolean,
      'plumas': rive.DataType.color,
      'barriga': rive.DataType.color,
      'ojo': rive.DataType.color,
      'pupila': rive.DataType.color,
      'pico': rive.DataType.color,
    },
  );

  static const medidor = ContratoRive(
    ruta: 'assets/rive/medidor.riv',
    artboard: 'Medidor',
    maquina: 'Medidor',
    propiedades: {
      'probabilidad': rive.DataType.number,
      'objetivo': rive.DataType.number,
      'quieto': rive.DataType.boolean,
      'ok': rive.DataType.color,
      'riesgo': rive.DataType.color,
      'aguja': rive.DataType.color,
      'fondo': rive.DataType.color,
    },
  );

  static String _tipo(rive.DataType t) => switch (t) {
    rive.DataType.enumType => 'enum',
    rive.DataType.boolean => 'boolean',
    rive.DataType.color => 'color',
    rive.DataType.number => 'number',
    _ => t.name,
  };

  /// Qué no cumple [archivo] (vacío: cumple), en español.
  List<String> problemas(rive.File archivo) {
    final ab = archivo.artboard(artboard);
    if (ab == null) return ['$artboard: falta el artboard «$artboard»'];
    final problemas = <String>[];
    if (ab.stateMachine(maquina) == null) {
      problemas.add('$artboard: falta la máquina de estados «$maquina»');
    }
    final vm = archivo.defaultArtboardViewModel(ab);
    if (vm == null) {
      ab.dispose();
      return [...problemas, '$artboard: no tiene un view model asignado'];
    }
    final tipos = {for (final p in vm.properties) p.name: p.type};
    for (final MapEntry(key: nombre, value: tipo) in propiedades.entries) {
      final real = tipos[nombre];
      if (real == null) {
        problemas.add(
          '$artboard: falta la propiedad «$nombre» (${_tipo(tipo)})',
        );
      } else if (real != tipo) {
        problemas.add(
          '$artboard: «$nombre» es ${_tipo(real)}, debe ser ${_tipo(tipo)}',
        );
      }
    }
    // El enum no expone sus valores: se prueban uno a uno.
    if (tipos['animo'] == rive.DataType.enumType &&
        propiedades.containsKey('animo')) {
      final instancia = vm.createDefaultInstance() ?? vm.createInstance();
      final animo = instancia?.enumerator('animo');
      for (final a in AnimoBuho.values) {
        animo?.value = a.name;
        if (animo?.value != a.name) {
          problemas.add(
            '$artboard: al enum «animo» le falta el valor «${a.name}»',
          );
        }
      }
      instancia?.dispose();
    }
    vm.dispose();
    ab.dispose();
    return problemas;
  }
}

/// Los `.riv` que cumplen el contrato (`null`: ese elemento se dibuja con
/// Flutter).
class ArchivosRive {
  const ArchivosRive({this.buho, this.medidor});

  final rive.File? buho;
  final rive.File? medidor;

  bool get vacio => buho == null && medidor == null;
}

/// Carga [contrato.ruta] si existe y cumple el contrato.
Future<rive.File?> cargarRive(ContratoRive contrato, AssetBundle bundle) async {
  final ByteData datos;
  try {
    datos = await bundle.load(contrato.ruta);
  } on Object {
    return null; // aún no se entregó: se usa el de Flutter
  }
  try {
    final archivo = await rive.File.decode(
      datos.buffer.asUint8List(),
      riveFactory: rive.Factory.flutter,
    );
    if (archivo == null) return null;
    final problemas = contrato.problemas(archivo);
    if (problemas.isNotEmpty) {
      debugPrint(
        'Rive (${contrato.ruta}) no cumple el contrato:\n'
        '${problemas.join('\n')}',
      );
      archivo.dispose();
      return null;
    }
    return archivo;
  } on Object catch (e) {
    debugPrint('Rive (${contrato.ruta}) no se pudo abrir: $e');
    return null;
  }
}

/// Los dos archivos, cargados una vez al arrancar.
final archivosRiveProvider = FutureProvider<ArchivosRive>((ref) async {
  final archivos = ArchivosRive(
    buho: await cargarRive(ContratoRive.buho, rootBundle),
    medidor: await cargarRive(ContratoRive.medidor, rootBundle),
  );
  ref.onDispose(() {
    archivos.buho?.dispose();
    archivos.medidor?.dispose();
  });
  return archivos;
});

/// Valores del view model del búho (docs/CONTRATO_RIVE.md §2), con los
/// colores del tema: los mismos que el búho dibujado en Flutter.
Map<String, Object> valoresBuho(
  ThemeData tema,
  AnimoBuho animo, {
  required bool quieto,
}) {
  final c = tema.colorScheme;
  return {
    'animo': animo.name,
    'quieto': quieto,
    'plumas': Color.lerp(c.primary, const Color(0xFF8D6E63), 0.6)!,
    'barriga': Color.lerp(c.primaryContainer, Colors.white, 0.3)!,
    'ojo': Colors.white,
    'pupila': const Color(0xFF212121),
    'pico': const Color(0xFFF2A33A),
  };
}

/// Valores del view model del medidor (§3): porcentajes 0-100 y colores del
/// tema.
Map<String, Object> valoresMedidor(
  ThemeData tema,
  ColoresEstado estado, {
  required double probabilidad,
  required double objetivo,
  required bool quieto,
}) => {
  'probabilidad': (probabilidad * 100).clamp(0, 100).toDouble(),
  'objetivo': (objetivo * 100).clamp(0, 100).toDouble(),
  'quieto': quieto,
  'ok': estado.ok,
  'riesgo': estado.riesgo,
  'aguja': tema.colorScheme.onSurface,
  'fondo': tema.colorScheme.surfaceContainerHighest,
};

/// Búho y medidor en Rive cuando están sus `.riv`; lo que falte, en
/// Flutter.
class AparienciaRive extends AparienciaLaboratorio {
  const AparienciaRive(this.archivos);

  final ArchivosRive archivos;

  @override
  Widget buho({required AnimoBuho animo, double tamano = 64}) =>
      switch (archivos.buho) {
        final archivo? => Semantics(
          container: true,
          label: 'Búho guía (${animo.name})',
          excludeSemantics: true,
          child: SizedBox.square(
            dimension: tamano,
            child: _VistaRive(
              key: const ValueKey('buho-rive'),
              archivo: archivo,
              contrato: ContratoRive.buho,
              valores: (context) => valoresBuho(
                Theme.of(context),
                animo,
                quieto: MediaQuery.disableAnimationsOf(context),
              ),
            ),
          ),
        ),
        null => const AparienciaFlutter().buho(animo: animo, tamano: tamano),
      };

  @override
  Widget medidor({
    required double probabilidad,
    required double objetivo,
  }) => switch (archivos.medidor) {
    final archivo? => Builder(
      builder: (context) => Semantics(
        container: true,
        label:
            'Riesgo estimado por el modelo: '
            '${formatoProbabilidad(probabilidad)}. '
            'El objetivo es bajarlo de ${formatoProbabilidad(objetivo)}.',
        excludeSemantics: true,
        child: AspectRatio(
          aspectRatio: 2,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _VistaRive(
                key: const ValueKey('medidor-rive'),
                archivo: archivo,
                contrato: ContratoRive.medidor,
                valores: (context) => valoresMedidor(
                  Theme.of(context),
                  ColoresEstado.of(context),
                  probabilidad: probabilidad,
                  objetivo: objetivo,
                  quieto: MediaQuery.disableAnimationsOf(context),
                ),
              ),
              // El texto lo pone la app (no se anima; lo lee el lector).
              LeyendaMedidor(probabilidad: probabilidad, objetivo: objetivo),
            ],
          ),
        ),
      ),
    ),
    null => const AparienciaFlutter().medidor(
      probabilidad: probabilidad,
      objetivo: objetivo,
    ),
  };
}

/// Un artboard de Rive con su máquina de estados y su view model. Cada vez
/// que cambian los [valores] (o el tema), se los pasa al view model.
class _VistaRive extends StatefulWidget {
  const _VistaRive({
    super.key,
    required this.archivo,
    required this.contrato,
    required this.valores,
  });

  final rive.File archivo;
  final ContratoRive contrato;
  final Map<String, Object> Function(BuildContext context) valores;

  @override
  State<_VistaRive> createState() => _VistaRiveState();
}

class _VistaRiveState extends State<_VistaRive> {
  late final rive.RiveWidgetController _controlador = rive.RiveWidgetController(
    widget.archivo,
    artboardSelector: rive.ArtboardSelector.byName(widget.contrato.artboard),
    stateMachineSelector: rive.StateMachineSelector.byName(
      widget.contrato.maquina,
    ),
  );
  late final rive.ViewModelInstance _vm = _controlador.dataBind(
    rive.DataBind.auto(),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _aplicar();
  }

  @override
  void didUpdateWidget(_VistaRive viejo) {
    super.didUpdateWidget(viejo);
    _aplicar();
  }

  void _aplicar() {
    for (final MapEntry(key: nombre, value: valor)
        in widget.valores(context).entries) {
      switch (valor) {
        case final String v:
          _vm.enumerator(nombre)?.value = v;
        case final bool v:
          _vm.boolean(nombre)?.value = v;
        case final double v:
          _vm.number(nombre)?.value = v;
        case final Color v:
          _vm.color(nombre)?.value = v;
      }
    }
  }

  @override
  void dispose() {
    _vm.dispose();
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      rive.RiveWidget(controller: _controlador, fit: rive.Fit.contain);
}
