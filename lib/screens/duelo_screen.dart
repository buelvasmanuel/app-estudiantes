import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

/// El duelo de cartas contra el Búho Máquina (docs/CONTRATO_DUELO.md v1).
///
/// Al abrir se retoma el duelo a medias o se empieza uno. Todo lo decide el
/// servidor; la pantalla solo enseña el estado y, tras cada jugada, gira la
/// carta del rival y deja hablar al búho con la explicación de la API.
class DueloScreen extends ConsumerStatefulWidget {
  const DueloScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _abrir(nuevo: false);
  }

  Future<void> _abrir({required bool nuevo}) async {
    setState(() {
      _duelo = null;
      _errorCarga = null;
      _vista = null;
      _avisoJugada = null;
      _pendiente = null;
    });
    try {
      final api = ref.read(dueloApiProvider);
      final duelo = nuevo ? await api.crear() : await api.abrir();
      if (mounted) setState(() => _duelo = duelo);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorCarga = e);
    }
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
      _aplicar(antes, despues);
    } on ApiException catch (e) {
      if (mounted) setState(() => _avisoJugada = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Pasa al estado [despues]. Si hay rondas nuevas, se enseña la última;
  /// si el duelo sigue igual, la jugada no llegó.
  void _aplicar(Duelo antes, Duelo despues) {
    final nueva = despues.rondas.length > antes.rondas.length
        ? despues.rondas.last
        : null;
    final igual =
        nueva == null &&
        despues.estado == antes.estado &&
        despues.ronda == antes.ronda &&
        despues.turno == antes.turno;
    setState(() {
      _duelo = despues;
      _vista = nueva;
      _pendiente = igual ? _pendiente : null;
      _avisoJugada = igual
          ? 'No se pudo enviar la jugada. Inténtalo otra vez.'
          : null;
      if (despues.recompensa case final r?) _porCelebrar = r;
    });
    if (nueva != null) {
      final sonidos = ref.read(sonidosProvider);
      switch (nueva.ganador) {
        case GanadorRonda.yo:
          sonidos.tocar(Sonido.acierto);
        case GanadorRonda.rival:
          sonidos.tocar(Sonido.pista);
        case GanadorRonda.empate:
          sonidos.tocar(Sonido.ficha);
      }
    }
    if (despues.estado.acabado) progresoCambiado(ref);
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
    final si = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Abandonar el duelo?'),
        content: const Text('Cuenta como derrota y no da XP.'),
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
      final despues = await ref.read(dueloApiProvider).abandonar(duelo.id);
      if (!mounted) return;
      setState(() {
        _duelo = despues;
        _vista = null;
      });
      progresoCambiado(ref);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.mensaje)));
      // Si ya había terminado, el estado de verdad es el del servidor.
      if (e.codigo == 'duelo_terminado') {
        final actual = await ref.read(dueloApiProvider).duelo(duelo.id);
        if (mounted) setState(() => _duelo = actual);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final duelo = _duelo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duelo'),
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
          mensaje: 'Barajando las cartas…',
          despertando: ref.watch(apiServiceProvider).despertando,
        ),
      },
    );
  }

  Widget _contenido(Duelo d) {
    final vista = _vista;
    final alias = d.aliasRival ?? 'tu rival';
    final terminado = d.estado.acabado && vista == null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AnchoMaximo(
          ancho: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MarcadorDuelo(duelo: d, rondaResuelta: vista?.numero),
              const SizedBox(height: 12),
              if (terminado)
                _Resultado(duelo: d, onOtro: () => _abrir(nuevo: true))
              else ...[
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
                ..._acciones(d, vista, alias),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _acciones(Duelo d, Ronda? vista, String alias) {
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
          // Tal cual la manda la API.
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
          animo: d.turno == Lado.yo ? AnimoBuho.atento : AnimoBuho.pensando,
          texto: _consejo(d, alias),
        ),
      ],
    ];
  }

  static String _consejo(Duelo d, String alias) {
    if (d.turno == Lado.rival) {
      return d.contraMaquina
          ? 'Ahora elige $alias: siempre juega el atributo en el que su '
                'carta tiene el percentil más alto. Tú solo puedes esperar… '
                '¡y aprender de su jugada!'
          : '$alias está eligiendo. Si no juega a tiempo, la ronda es tuya.';
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

/// Cabecera: marcador, ronda y fase, XP de hoy. Deja sitio para la v2: el
/// alias del rival (ya sale) y la cuenta atrás del turno.
class MarcadorDuelo extends StatelessWidget {
  const MarcadorDuelo({super.key, required this.duelo, this.rondaResuelta});

  final Duelo duelo;

  /// La ronda resuelta que se está enseñando, si hay una.
  final int? rondaResuelta;

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
                // v2: cuenta atrás del turno (o de la búsqueda de rival).
                // Por ahora solo se enseña lo que queda al pintar.
                if (expira != null) CuentaAtras(hasta: expira),
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
            // v2: aviso de rival desconectado.
            if (d.rivalEnLinea == false)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 16,
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${d.aliasRival ?? 'Tu rival'} se desconectó',
                      key: const Key('rival-desconectado'),
                      style: tema.textTheme.bodySmall,
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

/// v2: lo que queda de turno, "0:38". Aún no avanza sola: la v2 la hará
/// avanzar y pedirá el duelo al llegar a 0 (CONTRATO_DUELO §7.2).
class CuentaAtras extends StatelessWidget {
  const CuentaAtras({super.key, required this.hasta, this.ahora});

  final DateTime hasta;

  /// Para los tests.
  final DateTime? ahora;

  static String texto(Duration queda) {
    final s = queda.isNegative ? 0 : queda.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final queda = texto(hasta.difference(ahora ?? DateTime.now()));
    return Chip(
      key: const Key('cuenta-atras'),
      avatar: const Icon(Icons.timer_outlined, size: 18),
      label: Text(queda, semanticsLabel: 'Quedan $queda'),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// v2: el turno es del otro jugador. Es un estado de espera, no un botón:
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

/// El duelo terminó (o se abandonó): resultado, XP y qué hacer ahora.
class _Resultado extends StatelessWidget {
  const _Resultado({required this.duelo, required this.onOtro});

  final Duelo duelo;
  final VoidCallback onOtro;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estado = ColoresEstado.of(context);
    final d = duelo;
    final abandonado = d.estado == EstadoDuelo.abandonado;
    final (titulo, fondo, texto, sello) = switch (d.resultado) {
      _ when abandonado => (
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
    final xp = d.xpGanada > 0
        ? '+${d.xpGanada} XP'
        : abandonado
        ? 'Abandonar no da XP.'
        : d.duelosConXpHoy >= d.maximoDuelosConXp
        ? 'Hoy ya jugaste ${d.maximoDuelosConXp} duelos con XP: este no '
              'suma, pero sí cuenta como práctica.'
        : 'Este duelo no dio XP.';
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
          texto:
              'Cada ronda era una pregunta: ¿en qué destaca de verdad esta '
              'carta? Los percentiles te lo dicen. Y recuerda que ganar con '
              'el promedio es ganar con el resultado, no con la causa.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('otro-duelo'),
          onPressed: onOtro,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.style_outlined),
          label: const Text('Otro duelo'),
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
