import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../duelo/canal.dart';
import '../duelo/cartas.dart';
import '../duelo/duelo_api.dart';
import '../duelo/modelo.dart';
import '../juego/celebracion.dart';
import '../juego/juego_api.dart';
import '../juego/modelo.dart';
import '../laboratorio/apariencia.dart';
import '../providers.dart';
import '../router.dart';
import '../services/api_service.dart';
import '../sonidos.dart';
import '../tema/temas.dart';
import '../theme.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/menu_cuenta.dart';

/// El duelo de cartas (docs/CONTRATO_DUELO.md 2.1), contra el Búho Máquina
/// o contra otro jugador.
///
/// Todo lo decide el servidor; la pantalla enseña el estado y, tras cada
/// ronda, gira la carta del rival y deja hablar al búho con la explicación de
/// la API. Contra un jugador, además:
/// - Los avisos llegan por el WebSocket ([CanalDuelo]). Si no está
///   conectado, el duelo se consulta por REST cada [intervaloSondeo]: la
///   partida sigue igual sin WebSocket.
/// - La cuenta atrás del turno avanza cada segundo; al llegar a 0 se pide el
///   duelo (eso aplica el vencimiento en el servidor, §7.2).
class DueloScreen extends ConsumerStatefulWidget {
  const DueloScreen({super.key, this.modo = ModoDuelo.maquina});

  final ModoDuelo modo;

  static const intervaloSondeo = Duration(seconds: 3);

  @override
  ConsumerState<DueloScreen> createState() => _DueloScreenState();
}

class _DueloScreenState extends ConsumerState<DueloScreen> {
  Duelo? _duelo;
  Object? _errorCarga;

  /// La ronda resuelta que se está enseñando (las dos cartas a la vista),
  /// hasta que se pulsa "Siguiente ronda".
  Ronda? _vista;
  bool _enviando = false;
  String? _avisoJugada;

  /// Lo último que se intentó jugar, para "Reintentar".
  ({int ronda, String? atributo})? _pendiente;

  /// Insignias o nivel que se celebran al ver el resultado.
  Recompensa? _porCelebrar;

  // --- Solo contra un jugador ---
  CanalDuelo? _canal;
  EstadoCanal? _estadoCanal;
  Timer? _sondeo;
  Timer? _reloj;
  bool _consultando = false;
  DateTime? _ultimaConsultaPorTiempo;

  /// Segundos que quedaban en el último tic (para anunciar 30 y 10 una vez).
  int? _segundosPrevios;
  DateTime? _expiraPrevia;

  /// Se acaba de encontrar rival: se avisa hasta la primera ronda.
  bool _emparejadoAhora = false;

  bool get _contraJugador => widget.modo == ModoDuelo.jugador;

  /// Para las pruebas contra la API real: si el WebSocket está conectado.
  EstadoCanal? get estadoCanal => _estadoCanal;

  /// En un campo: `dispose` la usa y ahí ya no se puede leer `ref`.
  late final DueloApi _api;

  @override
  void initState() {
    super.initState();
    _api = ref.read(dueloApiProvider);
    _abrir(nuevo: false);
  }

  @override
  void dispose() {
    final d = _duelo;
    // Salir mientras se busca rival cancela la búsqueda: si no, alguien
    // podría emparejarse y perder turnos esperando a quien ya no está.
    if (d != null && d.estado == EstadoDuelo.esperando) {
      unawaited(_api.abandonar(d.id).then((_) {}, onError: (_) {}));
    }
    _pararTiempoReal();
    super.dispose();
  }

  Future<void> _abrir({required bool nuevo}) async {
    _pararTiempoReal();
    setState(() {
      _duelo = null;
      _errorCarga = null;
      _vista = null;
      _avisoJugada = null;
      _pendiente = null;
      _emparejadoAhora = false;
    });
    try {
      final duelo = _contraJugador
          ? await _api.buscarRival()
          : nuevo
          ? await _api.crear()
          : await _api.abrir();
      if (!mounted) return;
      setState(() {
        _duelo = duelo;
        // Se unió a alguien que esperaba: ya hay rival.
        _emparejadoAhora =
            _contraJugador &&
            duelo.estado == EstadoDuelo.enJuego &&
            duelo.rondas.isEmpty;
      });
      _activarTiempoReal(duelo);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorCarga = e);
    }
  }

  // --- Tiempo real (contra un jugador) ---------------------------------------

  void _activarTiempoReal(Duelo d) {
    if (!_contraJugador) return;
    if (!d.activo) {
      _pararTiempoReal();
      return;
    }
    if (_canal?.idDuelo != d.id) {
      unawaited(_canal?.cerrar());
      final sesion = ref.read(sesionProvider);
      _canal = CanalDuelo(
        idDuelo: d.id,
        apiUrl: ref.read(apiServiceProvider).baseUrl,
        token: sesion.accessVigente,
        conector: ref.read(conectorWsProvider),
        onAviso: (_, duelo) => _recibir(duelo),
        onEstado: (e) {
          if (!mounted) return;
          setState(() => _estadoCanal = e);
          _ajustarSondeo();
        },
        // Al volver, se resincroniza por REST (§7.3).
        onReconectado: _consultar,
      )..abrir();
      _estadoCanal = _canal!.estado;
    }
    _reloj ??= Timer.periodic(const Duration(seconds: 1), (_) => _tic());
    _ajustarSondeo();
  }

  void _pararTiempoReal() {
    unawaited(_canal?.cerrar());
    _canal = null;
    _estadoCanal = null;
    _sondeo?.cancel();
    _sondeo = null;
    _reloj?.cancel();
    _reloj = null;
  }

  /// Sin WebSocket conectado, se consulta por REST cada 3 s.
  void _ajustarSondeo() {
    final hace =
        _contraJugador &&
        (_duelo?.activo ?? false) &&
        _estadoCanal != EstadoCanal.conectado;
    if (hace && _sondeo == null) {
      _sondeo = Timer.periodic(
        DueloScreen.intervaloSondeo,
        (_) => _consultar(),
      );
    } else if (!hace) {
      _sondeo?.cancel();
      _sondeo = null;
    }
  }

  Future<void> _consultar() async {
    final d = _duelo;
    if (d == null || _consultando || !mounted) return;
    _consultando = true;
    try {
      final nuevo = await _api.duelo(d.id);
      if (mounted) _recibir(nuevo);
    } on ApiException {
      // Sin red o servidor dormido: el sondeo o el reloj lo vuelven a pedir.
    } finally {
      _consultando = false;
    }
  }

  /// Lo que queda del plazo actual (turno o búsqueda).
  Duration? get _restante {
    final expira = _duelo?.expiraTurnoEn;
    if (expira == null || !(_duelo?.activo ?? false)) return null;
    final r = expira.difference(clock.now());
    return r.isNegative ? Duration.zero : r;
  }

  static int _segundos(Duration r) => (r.inMilliseconds / 1000).ceil();

  bool get _esMiTurno =>
      _duelo?.estado == EstadoDuelo.enJuego && _duelo?.turno == Lado.yo;

  void _tic() {
    final d = _duelo;
    final restante = _restante;
    if (!mounted || d == null || restante == null) return;
    final s = _segundos(restante);
    // El lector de pantalla no anuncia cada segundo: solo 30 y 10 s de tu
    // turno (el reloj no es una región viva).
    if (_expiraPrevia != d.expiraTurnoEn) {
      _expiraPrevia = d.expiraTurnoEn;
      _segundosPrevios = s;
    }
    final previos = _segundosPrevios ?? s;
    if (_esMiTurno && _vista == null) {
      for (final umbral in const [30, 10]) {
        if (previos > umbral && s <= umbral) {
          _anunciar('Quedan $umbral segundos de tu turno');
        }
      }
    }
    _segundosPrevios = s;
    // Llegó a 0: los dos clientes piden el duelo (aplica el vencimiento).
    // Si el servidor aún no lo dio por vencido, se repite cada 3 s.
    if (s == 0) {
      final ultima = _ultimaConsultaPorTiempo;
      final ahora = clock.now();
      if (ultima == null ||
          ahora.difference(ultima) >= DueloScreen.intervaloSondeo) {
        _ultimaConsultaPorTiempo = ahora;
        _consultar();
      }
    }
    setState(() {});
  }

  void _anunciar(String mensaje) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      mensaje,
      Directionality.of(context),
    );
  }

  // --- Recibir estados -------------------------------------------------------

  /// Un estado del servidor (respuesta REST o aviso del WebSocket). Uno más
  /// viejo que el actual se ignora; si trae rondas nuevas, se enseña la
  /// última.
  void _recibir(Duelo nuevo) {
    final actual = _duelo;
    if (!mounted || actual == null || actual.id != nuevo.id) return;
    if (nuevo.esMasViejoQue(actual)) return;
    final ronda = nuevo.rondas.length > actual.rondas.length
        ? nuevo.rondas.last
        : null;
    final emparejado =
        actual.estado == EstadoDuelo.esperando &&
        nuevo.estado == EstadoDuelo.enJuego;
    setState(() {
      _duelo = nuevo;
      if (ronda != null) _vista = ronda;
      if (emparejado) _emparejadoAhora = true;
      if (nuevo.rondas.isNotEmpty) _emparejadoAhora = false;
      if (nuevo.recompensa case final r?) _porCelebrar = r;
    });
    final sonidos = ref.read(sonidosProvider);
    if (ronda != null) {
      sonidos.tocar(switch (ronda.ganador) {
        GanadorRonda.yo => Sonido.acierto,
        GanadorRonda.rival => Sonido.pista,
        GanadorRonda.empate => Sonido.ficha,
      });
    } else if (emparejado) {
      sonidos.tocar(Sonido.ficha);
    }
    if (nuevo.estado.acabado && !actual.estado.acabado) {
      progresoCambiado(ref);
    }
    _activarTiempoReal(nuevo);
  }

  Future<void> _jugar(int ronda, String? atributo) async {
    final antes = _duelo;
    if (antes == null || _enviando) return;
    setState(() {
      _enviando = true;
      _avisoJugada = null;
      _pendiente = (ronda: ronda, atributo: atributo);
    });
    try {
      final despues = await ref
          .read(dueloApiProvider)
          .jugar(antes.id, ronda, atributo);
      if (!mounted) return;
      _recibir(despues);
      // Si el duelo sigue igual que antes de jugar, la jugada no llegó.
      final igual =
          despues.rondas.length == antes.rondas.length &&
          despues.estado == antes.estado &&
          despues.ronda == antes.ronda &&
          despues.turno == antes.turno;
      setState(() {
        if (!igual) _pendiente = null;
        _avisoJugada = igual
            ? 'No se pudo enviar la jugada. Inténtalo otra vez.'
            : null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _avisoJugada = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _continuar() async {
    setState(() => _vista = null);
    final r = _porCelebrar;
    if (r != null && (_duelo?.estado.acabado ?? false)) {
      _porCelebrar = null;
      await celebrar(context, r);
    }
  }

  Future<void> _abandonar() async {
    final duelo = _duelo;
    if (duelo == null) return;
    final alias = duelo.aliasRival ?? 'tu rival';
    final si = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Abandonar el duelo?'),
        content: Text(
          duelo.contraMaquina
              ? 'Cuenta como derrota y no da XP.'
              : 'Cuenta como derrota y no da XP. $alias gana el duelo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir jugando'),
          ),
          FilledButton(
            key: const Key('confirmar-abandono'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abandonar'),
          ),
        ],
      ),
    );
    if (si != true || !mounted) return;
    try {
      final despues = await _api.abandonar(duelo.id);
      if (!mounted) return;
      setState(() => _vista = null);
      _recibir(despues);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.mensaje)));
      // Si ya había terminado, el estado de verdad es el del servidor.
      if (e.codigo == 'duelo_terminado') await _consultar();
    }
  }

  /// Cancelar la búsqueda de rival y volver a elegir.
  Future<void> _cancelarBusqueda() async {
    final d = _duelo;
    if (d == null) return;
    _pararTiempoReal();
    try {
      await _api.abandonar(d.id);
    } on ApiException {
      // Si no llega, el servidor la cancela solo a los 60 s.
    }
    if (!mounted) return;
    _duelo = null; // que dispose no la vuelva a cancelar
    context.go(Rutas.duelo);
  }

  // --- Vista -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final duelo = _duelo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duelo'),
        // Junto a la flecha: con la bandera, el chip y el avatar, a 360 px
        // el título no cabría con el margen normal.
        titleSpacing: 0,
        actions: [
          if (duelo != null && duelo.enJuego)
            IconButton(
              key: const Key('abandonar-duelo'),
              tooltip: 'Abandonar el duelo',
              onPressed: _enviando ? null : _abandonar,
              icon: const Icon(Icons.flag_outlined),
            ),
          const MenuCuenta(),
        ],
      ),
      body: switch ((duelo, _errorCarga)) {
        (final Duelo d, _) => _contenido(d),
        (_, final Object error) => ErrorVista(
          error: error,
          onReintentar: () => _abrir(nuevo: false),
        ),
        _ => CargandoVista(
          mensaje: _contraJugador ? 'Buscando rival…' : 'Barajando las cartas…',
          despertando: ref.watch(apiServiceProvider).despertando,
        ),
      },
    );
  }

  Widget _contenido(Duelo d) {
    final vista = _vista;
    final alias = d.aliasRival ?? 'tu rival';
    if (d.estado == EstadoDuelo.esperando) {
      return BuscandoRival(
        restante: _restante ?? Duration.zero,
        onCancelar: _cancelarBusqueda,
      );
    }
    // Pasó el minuto sin rival (o se canceló): sin resultado.
    if (d.estado == EstadoDuelo.abandonado &&
        d.resultado == null &&
        !d.contraMaquina) {
      return NadieAparecio(
        onMaquina: () => context.go(Rutas.dueloMaquina),
        onOtraVez: () => _abrir(nuevo: true),
      );
    }
    final terminado = d.estado.acabado && vista == null;
    final restante = _restante;
    final urgente = restante != null && _esMiTurno && _segundos(restante) <= 10;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AnchoMaximo(
          ancho: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MarcadorDuelo(
                duelo: d,
                rondaResuelta: vista?.numero,
                restante: restante,
                urgente: urgente,
              ),
              const SizedBox(height: 12),
              if (terminado)
                _Resultado(duelo: d, onOtro: () => _abrir(nuevo: true))
              else ...[
                if (vista != null && vista.porTiempo) ...[
                  AvisoDuelo(
                    key: const Key('aviso-tiempo'),
                    icono: Icons.timer_off_outlined,
                    titulo: vista.elegidoPor == Lado.yo
                        ? 'Se acabó tu tiempo'
                        : 'A $alias se le acabó el tiempo',
                  ),
                  const SizedBox(height: 12),
                ],
                // La misma carta en las dos fases: al llegar la ronda
                // resuelta, se gira.
                CartaRival(
                  key: const Key('ranura-carta-rival'),
                  alias: alias,
                  carta: vista?.cartaRival,
                  atributo: vista?.atributo,
                  desenlace: vista == null
                      ? null
                      : desenlace(vista.ganador, Lado.rival),
                  nombreAtributo: d.nombreAtributo,
                ),
                const SizedBox(height: 12),
                if (vista != null)
                  CartaPropia(
                    carta: vista.miCarta,
                    codigos: d.codigosAtributos,
                    nombreAtributo: d.nombreAtributo,
                    atributoJugado: vista.atributo,
                    desenlace: desenlace(vista.ganador, Lado.yo),
                  )
                else if (d.miCarta case final carta?)
                  CartaPropia(
                    carta: carta,
                    codigos: d.codigosAtributos,
                    nombreAtributo: d.nombreAtributo,
                    onElegir: d.turno == Lado.yo && !_enviando
                        ? (codigo) => _jugar(d.ronda!, codigo)
                        : null,
                  ),
                const SizedBox(height: 12),
                // Debajo de la carta: así, en pantallas bajas, los 4
                // atributos se ven sin desplazar.
                if (_emparejadoAhora && vista == null && d.rondas.isEmpty) ...[
                  AvisoDuelo(
                    key: const Key('aviso-emparejado'),
                    icono: Icons.handshake_outlined,
                    titulo: '¡Rival encontrado: $alias!',
                    texto: d.turno == Lado.yo
                        ? 'Empiezas tú. ${d.rondasTotal} rondas, 45 s por turno.'
                        : 'Empieza $alias. ${d.rondasTotal} rondas, 45 s por '
                              'turno.',
                    vivo: true,
                  ),
                  const SizedBox(height: 12),
                ],
                ..._acciones(d, vista, alias, urgente: urgente),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _acciones(
    Duelo d,
    Ronda? vista,
    String alias, {
    required bool urgente,
  }) {
    final tema = Theme.of(context);
    final aviso = _avisoJugada;
    final pendiente = _pendiente;
    return [
      if (vista != null) ...[
        FilledButton.icon(
          key: const Key('continuar-duelo'),
          onPressed: _continuar,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: Icon(
            d.estado.acabado
                ? Icons.emoji_events_outlined
                : Icons.arrow_forward,
          ),
          label: Text(d.estado.acabado ? 'Ver resultado' : 'Siguiente ronda'),
        ),
        const SizedBox(height: 12),
        BurbujaBuho(
          key: const Key('explicacion-duelo'),
          animo: switch (vista.ganador) {
            GanadorRonda.yo => AnimoBuho.contento,
            GanadorRonda.rival => AnimoBuho.preocupado,
            GanadorRonda.empate => AnimoBuho.pensando,
          },
          // Tal cual la manda la API (también la de una ronda por tiempo).
          texto: vista.explicacion,
        ),
      ] else if (d.enJuego) ...[
        if (d.turno == Lado.rival) ...[
          if (d.contraMaquina)
            FilledButton.icon(
              key: const Key('ver-jugada-rival'),
              onPressed: _enviando ? null : () => _jugar(d.ronda!, null),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _enviando
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.visibility_outlined),
              label: const Text('Ver jugada del rival'),
            )
          else
            EsperandoRival(alias: alias),
          const SizedBox(height: 12),
        ] else if (_enviando) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
        ],
        if (aviso != null) ...[
          Text(
            aviso,
            key: const Key('aviso-jugada'),
            style: TextStyle(color: tema.colorScheme.error),
          ),
          if (pendiente != null && !_enviando)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('reintentar-jugada'),
                onPressed: () => _jugar(pendiente.ronda, pendiente.atributo),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ),
          const SizedBox(height: 8),
        ],
        BurbujaBuho(
          key: const Key('consejo-duelo'),
          animo: urgente
              ? AnimoBuho.preocupado
              : d.turno == Lado.yo
              ? AnimoBuho.atento
              : AnimoBuho.pensando,
          texto: _consejo(d, alias, urgente: urgente),
        ),
      ],
    ];
  }

  static String _consejo(Duelo d, String alias, {required bool urgente}) {
    if (d.turno == Lado.rival) {
      if (d.contraMaquina) {
        return 'Ahora elige $alias: siempre juega el atributo en el que su '
            'carta tiene el percentil más alto. Tú solo puedes esperar… '
            '¡y aprender de su jugada!';
      }
      return d.rivalEnLinea == false
          ? '$alias se desconectó. Si no vuelve antes de que acabe su '
                'turno, la ronda es tuya.'
          : '$alias está eligiendo. Si no juega a tiempo, la ronda es tuya.';
    }
    // Sin segundos: el número solo va en el reloj (no se queda viejo).
    if (urgente) {
      return '¡Se acaba tu tiempo! Si no eliges, la ronda es para $alias.';
    }
    final carta = d.miCarta;
    final promedio = carta?.atributos[Atributos.promedio];
    final asistencia = carta?.atributos[Atributos.asistencia];
    final ejemplo = promedio != null && asistencia != null
        ? 'No compares '
              '${Atributos.valor(Atributos.promedio, promedio.valor)} con '
              '${Atributos.valor(Atributos.asistencia, asistencia.valor)}: '
        : 'No compares valores con escalas distintas: ';
    return 'Elige en qué atributo crees que ganas. $ejemplo'
        'compara percentiles, que dicen dónde cae cada valor entre todos '
        'los estudiantes.';
  }
}

/// Cabecera: marcador, ronda y fase, XP de hoy, la cuenta atrás (contra un
/// jugador) y el aviso de rival desconectado.
class MarcadorDuelo extends StatelessWidget {
  const MarcadorDuelo({
    super.key,
    required this.duelo,
    this.rondaResuelta,
    this.restante,
    this.urgente = false,
  });

  final Duelo duelo;

  /// La ronda resuelta que se está enseñando, si hay una.
  final int? rondaResuelta;

  /// Lo que queda del turno (lo calcula la pantalla cada segundo). Si es
  /// `null` y hay plazo, se calcula al pintar.
  final Duration? restante;
  final bool urgente;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final d = duelo;
    final grande = tema.textTheme.headlineSmall?.copyWith(
      color: tema.colorScheme.primary,
      fontWeight: FontWeight.w800,
    );
    final nombre = tema.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final fase = switch ((d.estado, rondaResuelta, d.turno)) {
      (_, final int n, _) => 'Ronda $n de ${d.rondasTotal} · resuelta',
      (EstadoDuelo.esperando, _, _) => 'Buscando rival…',
      (EstadoDuelo.terminado || EstadoDuelo.abandonado, _, _) =>
        'Duelo terminado',
      (_, _, Lado.yo) => 'Ronda ${d.ronda} de ${d.rondasTotal} · tu turno',
      _ => 'Ronda ${d.ronda} de ${d.rondasTotal} · turno del rival',
    };
    final expira = d.expiraTurnoEn;
    final queda =
        restante ??
        (expira != null && d.activo ? expira.difference(clock.now()) : null);
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    container: true,
                    label:
                        'Marcador: tú ${d.marcadorYo}, '
                        '${d.aliasRival ?? 'rival'} ${d.marcadorRival}',
                    excludeSemantics: true,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        key: const Key('marcador'),
                        TextSpan(
                          children: [
                            TextSpan(text: 'Tú ', style: nombre),
                            TextSpan(text: '${d.marcadorYo}', style: grande),
                            TextSpan(text: ' — ', style: grande),
                            TextSpan(text: '${d.marcadorRival}', style: grande),
                            TextSpan(
                              text: ' ${d.aliasRival ?? '…'}',
                              style: nombre,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (queda != null && rondaResuelta == null)
                  CuentaAtras(restante: queda, urgente: urgente),
              ],
            ),
            const SizedBox(height: 2),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              children: [
                Text(fase, key: const Key('fase-duelo')),
                Text(
                  'XP hoy: ${d.duelosConXpHoy} de ${d.maximoDuelosConXp} '
                  'duelos',
                  key: const Key('xp-hoy'),
                  style: tema.textTheme.bodySmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (d.rivalEnLinea == false && d.activo)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 16,
                      color: tema.colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${d.aliasRival ?? 'Tu rival'} se desconectó',
                        key: const Key('rival-desconectado'),
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: tema.colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lo que queda de turno, "0:38". Con ≤ 10 s de tu turno ([urgente]): color
/// de riesgo, negrita y borde (no solo color). No es una región viva: el
/// lector de pantalla no lo lee cada segundo (la pantalla anuncia 30 y 10 s).
class CuentaAtras extends StatelessWidget {
  const CuentaAtras({super.key, required this.restante, this.urgente = false});

  final Duration restante;
  final bool urgente;

  static String texto(Duration queda) {
    final s = queda.isNegative ? 0 : (queda.inMilliseconds / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final queda = texto(restante);
    final c = ColoresEstado.of(context);
    return Semantics(
      container: true,
      label: 'Tiempo del turno: $queda',
      excludeSemantics: true,
      child: Chip(
        key: const Key('cuenta-atras'),
        avatar: Icon(
          urgente ? Icons.timer : Icons.timer_outlined,
          size: 18,
          color: urgente ? c.onRiesgoContenedor : null,
        ),
        label: Text(
          queda,
          style: TextStyle(
            color: urgente ? c.onRiesgoContenedor : null,
            fontWeight: urgente ? FontWeight.w800 : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        backgroundColor: urgente ? c.riesgoContenedor : null,
        side: urgente ? BorderSide(color: c.riesgo, width: 2) : null,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Franja informativa: rival encontrado, ronda resuelta por tiempo.
class AvisoDuelo extends StatelessWidget {
  const AvisoDuelo({
    super.key,
    required this.icono,
    required this.titulo,
    this.texto,
    this.vivo = false,
  });

  final IconData icono;
  final String titulo;
  final String? texto;

  /// Se anuncia al aparecer (región viva).
  final bool vivo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final c = tema.colorScheme;
    return Semantics(
      container: true,
      liveRegion: vivo,
      child: Card.filled(
        margin: EdgeInsets.zero,
        color: c.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icono, color: c.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: tema.textTheme.titleSmall?.copyWith(
                        color: c.onSecondaryContainer,
                      ),
                    ),
                    if (texto case final t?)
                      Text(t, style: TextStyle(color: c.onSecondaryContainer)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Buscando rival: anillo con lo que queda del minuto y "Cancelar búsqueda".
class BuscandoRival extends StatelessWidget {
  const BuscandoRival({
    super.key,
    required this.restante,
    required this.onCancelar,
  });

  final Duration restante;
  final VoidCallback onCancelar;

  static const espera = Duration(seconds: 60);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final c = tema.colorScheme;
    final queda = CuentaAtras.texto(restante);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      children: [
        AnchoMaximo(
          ancho: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Semantics(
                  container: true,
                  label: 'Buscando rival. Quedan $queda',
                  excludeSemantics: true,
                  child: SizedBox.square(
                    dimension: 168,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            key: const Key('anillo-busqueda'),
                            value:
                                (restante.inMilliseconds /
                                        espera.inMilliseconds)
                                    .clamp(0, 1),
                            strokeWidth: 8,
                            backgroundColor: c.surfaceContainerHighest,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_search,
                              size: 36,
                              color: c.primary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              queda,
                              key: const Key('cuenta-busqueda'),
                              style: tema.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Buscando a otro detective…',
                textAlign: TextAlign.center,
                style: tema.textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'En cuanto alguien busque duelo, los emparejamos y empiezas '
                'tú. Si en 1 minuto no aparece nadie, puedes jugar contra el '
                'Búho Máquina.',
                textAlign: TextAlign.center,
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: c.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const Key('cancelar-busqueda'),
                onPressed: onCancelar,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.close),
                label: const Text('Cancelar búsqueda'),
              ),
              const SizedBox(height: 24),
              const BurbujaBuho(
                animo: AnimoBuho.atento,
                texto:
                    'Mientras esperas: gana el valor más alto, pero el '
                    'percentil te dice si de verdad es alto entre todos los '
                    'estudiantes.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pasó el minuto sin rival.
class NadieAparecio extends StatelessWidget {
  const NadieAparecio({
    super.key,
    required this.onMaquina,
    required this.onOtraVez,
  });

  final VoidCallback onMaquina;
  final VoidCallback onOtraVez;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      children: [
        AnchoMaximo(
          ancho: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.person_off_outlined,
                size: 56,
                color: tema.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Nadie apareció esta vez',
                key: const Key('nadie-aparecio'),
                textAlign: TextAlign.center,
                style: tema.textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Puedes volver a buscar o jugar ya contra el Búho Máquina.',
                textAlign: TextAlign.center,
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('jugar-contra-maquina'),
                onPressed: onMaquina,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.smart_toy_outlined),
                label: const Text('Jugar contra el Búho Máquina'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('buscar-otra-vez'),
                onPressed: onOtraVez,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Buscar otra vez'),
              ),
              const SizedBox(height: 24),
              const BurbujaBuho(
                animo: AnimoBuho.pensando,
                texto:
                    'A veces el campus está tranquilo. El Búho Máquina '
                    'siempre tiene ganas de jugar.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// El turno es del otro jugador. Es un estado de espera, no un botón:
/// indicador de progreso, sin relleno ni toque.
class EsperandoRival extends StatelessWidget {
  const EsperandoRival({super.key, required this.alias});

  final String alias;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Esperando a $alias',
      excludeSemantics: true,
      child: Container(
        key: const Key('esperando-rival'),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tema.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Esperando a $alias…',
                style: tema.textTheme.bodyLarge?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El búho y su globo.
class BurbujaBuho extends ConsumerWidget {
  const BurbujaBuho({super.key, required this.animo, required this.texto});

  final AnimoBuho animo;
  final String texto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ref.watch(aparienciaLaboratorioProvider).buho(animo: animo),
        const SizedBox(width: 12),
        Expanded(
          child: Card.filled(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(texto, key: const Key('frase-buho')),
            ),
          ),
        ),
      ],
    );
  }
}

/// El duelo terminó (o se abandonó): resultado, XP y qué hacer ahora. La XP
/// es la que manda el servidor; el texto solo explica por qué.
class _Resultado extends StatelessWidget {
  const _Resultado({required this.duelo, required this.onOtro});

  final Duelo duelo;
  final VoidCallback onOtro;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estado = ColoresEstado.of(context);
    final d = duelo;
    final alias = d.aliasRival ?? 'Tu rival';
    final abandonado = d.estado == EstadoDuelo.abandonado;
    final ultima = d.rondas.lastOrNull;
    // Abandonar por 2 turnos propios vencidos seguidos (§7.2).
    final porTiempo = ultima != null && ultima.porTiempo;
    final ganePorAbandono =
        abandonado && d.resultado == ResultadoDuelo.victoria;
    final perdiPorAbandono =
        abandonado && d.resultado == ResultadoDuelo.derrota;
    final (titulo, fondo, texto, sello) = switch (d.resultado) {
      _ when perdiPorAbandono && d.contraMaquina => (
        'Duelo abandonado',
        tema.colorScheme.surfaceContainerHighest,
        tema.colorScheme.onSurface,
        null,
      ),
      ResultadoDuelo.victoria => (
        '¡Victoria!',
        estado.okContenedor,
        estado.onOkContenedor,
        ('GANADO', estado.ok),
      ),
      ResultadoDuelo.derrota => (
        'Derrota',
        estado.riesgoContenedor,
        estado.onRiesgoContenedor,
        ('PERDIDO', estado.riesgo),
      ),
      _ => (
        'Empate',
        tema.colorScheme.surfaceContainerHighest,
        tema.colorScheme.onSurface,
        ('EMPATE', tema.colorScheme.outline),
      ),
    };
    // Qué pasó, si no se jugaron las 5 rondas.
    final motivo = !abandonado || d.contraMaquina && !ganePorAbandono
        ? null
        : ganePorAbandono
        ? porTiempo && ultima.elegidoPor == Lado.rival
              ? 'A $alias se le acabó el tiempo en 2 turnos seguidos.'
              : '$alias abandonó en la ronda ${d.rondas.length + 1}.'
        : porTiempo && ultima.elegidoPor == Lado.yo
        ? 'Se te acabó el tiempo en 2 turnos seguidos.'
        : 'Abandonaste el duelo.';
    final xp = d.xpGanada > 0
        ? '+${d.xpGanada} XP'
        : perdiPorAbandono
        ? 'Abandonar no da XP.'
        : d.duelosConXpHoy >= d.maximoDuelosConXp
        ? 'Hoy ya jugaste ${d.maximoDuelosConXp} duelos con XP: este no '
              'suma, pero sí cuenta como práctica.'
        : 'Este duelo no dio XP.';
    final buho = ganePorAbandono
        ? d.xpGanada > 0
              ? 'Ganas por abandono. Como ya se habían resuelto al menos 3 '
                    'rondas, la victoria cuenta con XP.'
              : d.rondas.length < 3
              ? 'Ganas por abandono, pero se resolvieron menos de 3 rondas: '
                    'así, esta victoria no da XP.'
              : 'Ganas por abandono. Hoy ya jugaste '
                    '${d.maximoDuelosConXp} duelos con XP en este modo.'
        : 'Cada ronda era una pregunta: ¿en qué destaca de verdad esta '
              'carta? Los percentiles te lo dicen. Y recuerda que ganar con '
              'el promedio es ganar con el resultado, no con la causa.';
    final sellos = EstiloJuego.of(context).sellos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.filled(
          margin: EdgeInsets.zero,
          color: fondo,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      titulo,
                      key: const Key('resultado-duelo'),
                      style: tema.textTheme.headlineSmall?.copyWith(
                        color: texto,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (sellos && sello != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 6,
                        ),
                        child: Sello(texto: sello.$1, color: sello.$2),
                      ),
                  ],
                ),
                if (motivo != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.flag_outlined, size: 18, color: texto),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          motivo,
                          key: const Key('motivo-fin'),
                          style: TextStyle(color: texto),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  xp,
                  key: const Key('xp-duelo'),
                  style: tema.textTheme.titleMedium?.copyWith(color: texto),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        BurbujaBuho(
          animo: d.resultado == ResultadoDuelo.victoria
              ? AnimoBuho.contento
              : AnimoBuho.atento,
          texto: buho,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('otro-duelo'),
          onPressed: onOtro,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: Icon(
            d.contraMaquina ? Icons.style_outlined : Icons.groups_outlined,
          ),
          label: Text(d.contraMaquina ? 'Otro duelo' : 'Buscar otro rival'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.go(Rutas.casos),
          icon: const Icon(Icons.list_alt_outlined),
          label: const Text('Volver a los casos'),
        ),
      ],
    );
  }
}
