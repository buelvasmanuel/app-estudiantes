// Los sonidos se cargan y suenan de verdad en la plataforma: cada uno debe
// terminar su reproducción sin error.
//
//   flutter test integration_test/sonidos_test.dart -d linux
//
// En Linux, audioplayers usa GStreamer. Antes de reproducir, el test
// comprueba con gst-inspect-1.0 que están las piezas necesarias y, si no,
// explica qué falta:
// - plugins para leer MP3 → FALLA con el paquete que hay que instalar (es un
//   problema de la instalación, no del entorno);
// - ninguna salida de audio (servidor de integración sin sonido) → se SALTA
//   explicándolo.
import 'dart:io';

import 'package:app_estudiantes/sonidos.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Elementos de GStreamer: (alguno de estos, para qué, paquete en Arch,
/// paquete en Ubuntu/Debian).
const _decodificar = [
  (
    ['id3demux'],
    'leer la etiqueta ID3 del MP3',
    'gst-plugins-good',
    'gstreamer1.0-plugins-good',
  ),
  (
    ['mpegaudioparse'],
    'separar los fotogramas MP3',
    'gst-plugins-good',
    'gstreamer1.0-plugins-good',
  ),
  (
    ['mpg123audiodec', 'avdec_mp3'],
    'decodificar MP3',
    'gst-plugins-good',
    'gstreamer1.0-plugins-good',
  ),
  (
    ['audioconvert', 'audioresample'],
    'convertir el audio',
    'gst-plugins-base',
    'gstreamer1.0-plugins-base',
  ),
];
const _salidas = ['autoaudiosink', 'pipewiresink', 'pulsesink', 'alsasink'];

bool _hay(String elemento) =>
    Process.runSync('gst-inspect-1.0', [elemento]).exitCode == 0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Solo en Linux: en las demás plataformas no hay GStreamer que revisar.
  String? faltaDecodificar;
  String? sinSalida;
  if (Platform.isLinux) {
    final faltan = [
      for (final (alguno, para, arch, ubuntu) in _decodificar)
        if (!alguno.any(_hay)) (alguno.join(' o '), para, arch, ubuntu),
    ];
    if (faltan.isNotEmpty) {
      final arch = {for (final f in faltan) f.$3}.join(' ');
      final ubuntu = {for (final f in faltan) f.$4}.join(' ');
      faltaDecodificar =
          'Faltan plugins de GStreamer para reproducir MP3:\n'
          '${faltan.map((f) => '  - ${f.$1}: ${f.$2}').join('\n')}\n'
          'Instálalos y vuelve a compilar:\n'
          '  Arch:   sudo pacman -S $arch\n'
          '  Ubuntu: sudo apt install $ubuntu';
    }
    if (!_salidas.any(_hay)) {
      sinSalida =
          'No hay ninguna salida de audio de GStreamer '
          '(${_salidas.join(', ')}): este entorno no puede sonar. '
          'Los sonidos se prueban en un equipo con audio.';
    }
  }

  for (final sonido in Sonido.values) {
    testWidgets('suena ${sonido.name}', (tester) async {
      if (faltaDecodificar != null) fail(faltaDecodificar);
      if (sinSalida != null) {
        markTestSkipped(sinSalida);
        return;
      }
      final jugador = AudioPlayer();
      addTearDown(jugador.dispose);
      final termina = jugador.onPlayerComplete.first;
      await tester.runAsync(() async {
        await jugador.play(AssetSource(sonido.recurso), volume: 0.2);
        await termina.timeout(const Duration(seconds: 5));
      });
    });
  }
}
