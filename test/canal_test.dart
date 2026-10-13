import 'package:app_estudiantes/duelo/canal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/duelo_jugador_falso.dart';
import 'support/ws_falso.dart';

/// Los tiempos (ping, esperas) corren en el reloj simulado de testWidgets:
/// `tester.pump(duración)` los adelanta sin esperar de verdad.
void main() {
  late ServidorWsFalso ws;
  late List<String> avisos;
  late List<EstadoCanal> estados;
  late List<bool> tokensForzados;
  late int reconectados;

  CanalDuelo canal() {
    ws = ServidorWsFalso();
    avisos = [];
    estados = [];
    tokensForzados = [];
    reconectados = 0;
    var n = 0;
    return CanalDuelo(
      idDuelo: 'abc',
      apiUrl: 'https://api.test',
      token: ({bool forzar = false}) async {
        tokensForzados.add(forzar);
        return 'access-${++n}';
      },
      conector: ws.conectar,
      onAviso: (tipo, _) => avisos.add(tipo),
      onEstado: estados.add,
      onReconectado: () => reconectados++,
    );
  }

  Map<String, Object?> listo() => {
    'tipo': 'listo',
    'duelo': dueloJugadorJson(),
  };

  test('la URL es wss://…/duelos/{id}/ws, sin token', () {
    expect(
      CanalDuelo.urlWebSocket('https://api.test', 'abc').toString(),
      'wss://api.test/duelos/abc/ws',
    );
    expect(
      CanalDuelo.urlWebSocket('http://127.0.0.1:8001', 'abc').toString(),
      'ws://127.0.0.1:8001/duelos/abc/ws',
    );
  });

  testWidgets('se autentica con el primer mensaje y avisa de cada cambio', (
    tester,
  ) async {
    final c = canal()..abrir();
    await tester.pump();
    final conexion = ws.ultima;
    expect(conexion.url.toString(), 'wss://api.test/duelos/abc/ws');
    expect(conexion.enviados.first, {'tipo': 'auth', 'token': 'access-1'});
    expect(c.estado, EstadoCanal.conectando);

    conexion.recibir(listo());
    await tester.pump();
    expect(c.estado, EstadoCanal.conectado);
    for (final tipo in [
      'emparejado',
      'ronda_resuelta',
      'rival_desconectado',
      'rival_conectado',
      'terminado',
    ]) {
      conexion.recibir({'tipo': tipo, 'duelo': dueloJugadorJson()});
    }
    // Lo que no se entiende no rompe nada.
    conexion
      ..recibir({'tipo': 'pong'})
      ..recibir({'tipo': 'ronda_resuelta', 'duelo': 'basura'});
    await tester.pump();
    expect(avisos, [
      'listo',
      'emparejado',
      'ronda_resuelta',
      'rival_desconectado',
      'rival_conectado',
      'terminado',
    ]);
    await c.cerrar();
  });

  testWidgets('manda ping cada 25 s', (tester) async {
    final c = canal()..abrir();
    await tester.pump();
    ws.ultima.recibir(listo());
    await tester.pump(const Duration(seconds: 24));
    expect(ws.ultima.tiposEnviados, ['auth']);
    await tester.pump(const Duration(seconds: 1));
    expect(ws.ultima.tiposEnviados, ['auth', 'ping']);
    await tester.pump(const Duration(seconds: 50));
    expect(ws.ultima.tiposEnviados, ['auth', 'ping', 'ping', 'ping']);
    await c.cerrar();
  });

  testWidgets(
    'mensaje "error" 4401: cierra al momento, renueva el token y reconecta '
    '(sin esperar el código de cierre)',
    (tester) async {
      final c = canal()..abrir();
      await tester.pump();
      final primera = ws.ultima;
      primera.recibir({
        'tipo': 'error',
        'codigo': 4401,
        'motivo': 'token_invalido',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1)); // reintento inmediato
      // La app cerró ella: el cierre de la API (que puede no llegar) ya no
      // hace falta.
      expect(primera.cerrada, isTrue);
      expect(ws.conexiones, hasLength(2));
      expect(tokensForzados, [false, true]);
      expect(ws.ultima.enviados.first, {'tipo': 'auth', 'token': 'access-2'});

      // Un segundo 4401 seguido ya no es inmediato: con espera.
      ws.ultima.recibir({'tipo': 'error', 'codigo': 4401, 'motivo': 'x'});
      await tester.pump();
      expect(ws.conexiones, hasLength(2));
      await tester.pump(const Duration(seconds: 1));
      expect(ws.conexiones, hasLength(3));
      await c.cerrar();
    },
  );

  for (final codigo in [4403, 4404]) {
    testWidgets('mensaje "error" $codigo: no se reconecta (solo REST)', (
      tester,
    ) async {
      final c = canal()..abrir();
      await tester.pump();
      ws.ultima.recibir({'tipo': 'error', 'codigo': codigo, 'motivo': 'x'});
      await tester.pump();
      expect(ws.ultima.cerrada, isTrue);
      expect(c.estado, EstadoCanal.descartado);
      await tester.pump(const Duration(minutes: 5));
      expect(ws.conexiones, hasLength(1));
      await c.cerrar();
    });
  }

  testWidgets(
    'mensaje "error" 4429 (demasiadas conexiones, contrato 2.3): reconecta '
    'con espera creciente, nunca en bucle',
    (tester) async {
      final c = canal()..abrir();
      await tester.pump();
      for (final espera in [1, 2, 4]) {
        ws.ultima.recibir({
          'tipo': 'error',
          'codigo': 4429,
          'motivo': 'demasiadas_conexiones',
        });
        await tester.pump();
        final antes = ws.conexiones.length;
        expect(c.proximaEspera, Duration(seconds: espera));
        await tester.pump(
          Duration(seconds: espera) - const Duration(milliseconds: 1),
        );
        expect(ws.conexiones, hasLength(antes)); // aún no
        await tester.pump(const Duration(milliseconds: 1));
        expect(ws.conexiones, hasLength(antes + 1));
      }
      await c.cerrar();
    },
  );

  testWidgets('cierre con 4404 sin mensaje previo: tampoco reconecta', (
    tester,
  ) async {
    final c = canal()..abrir();
    await tester.pump();
    ws.ultima.caer(4404);
    await tester.pump(const Duration(minutes: 1));
    expect(c.estado, EstadoCanal.descartado);
    expect(ws.conexiones, hasLength(1));
    await c.cerrar();
  });

  testWidgets(
    'caída (1006, 4408 o sin código): espera creciente 1, 2, 4… hasta 30 s; '
    'al volver, resincroniza',
    (tester) async {
      final c = canal()..abrir();
      await tester.pump();
      ws.ultima.recibir(listo());
      await tester.pump();
      expect(reconectados, 0);

      final esperas = <Duration?>[];
      for (var i = 0; i < 7; i++) {
        ws.ultima.caer(i == 0 ? 4408 : (i.isEven ? 1006 : null));
        await tester.pump();
        expect(c.estado, EstadoCanal.reconectando);
        esperas.add(c.proximaEspera);
        await tester.pump(c.proximaEspera!);
      }
      expect(esperas.map((e) => e!.inSeconds), [1, 2, 4, 8, 16, 30, 30]);

      // Vuelve: "listo" reinicia la espera y pide resincronizar.
      ws.ultima.recibir(listo());
      await tester.pump();
      expect(c.estado, EstadoCanal.conectado);
      expect(reconectados, 1);
      ws.ultima.caer(1006);
      await tester.pump();
      expect(c.proximaEspera, const Duration(seconds: 1));
      await c.cerrar();
    },
  );

  testWidgets('si no se puede conectar, lo reintenta con espera', (
    tester,
  ) async {
    final c = canal();
    ws.falla = true;
    c.abrir();
    await tester.pump();
    expect(c.estado, EstadoCanal.reconectando);
    expect(c.proximaEspera, const Duration(seconds: 1));
    ws.falla = false;
    await tester.pump(const Duration(seconds: 1));
    expect(ws.conexiones, hasLength(1));
    await c.cerrar();
  });

  testWidgets('cerrar() lo para todo: ni pings ni reconexiones', (
    tester,
  ) async {
    final c = canal()..abrir();
    await tester.pump();
    final conexion = ws.ultima..recibir(listo());
    await tester.pump();
    await c.cerrar();
    expect(conexion.cerrada, isTrue);
    await tester.pump(const Duration(minutes: 2));
    expect(conexion.tiposEnviados, ['auth']);
    expect(ws.conexiones, hasLength(1));
  });
}
