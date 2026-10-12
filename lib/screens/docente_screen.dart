import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../juego/juego_api.dart';
import '../juego/lote.dart';
import '../juego/modelo.dart';
import '../models/sesion.dart';
import '../providers.dart';
import '../services/api_service.dart';
import '../widgets/estado_vistas.dart';
import '../formato.dart';

/// Panel del docente: crear cuentas para la clase y ver a los jugadores.
/// Solo para los roles docente y admin (la API también lo exige).
class DocenteScreen extends ConsumerWidget {
  const DocenteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(usuarioIdProvider);
    final rol = ref.read(sesionProvider).usuario?.rol;
    if (rol != Rol.docente && rol != Rol.admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Panel del docente')),
        body: const VaciaVista(
          mensaje: 'Este panel es solo para docentes.',
          icono: Icons.lock_outline,
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel del docente'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Crear cuentas'),
              Tab(text: 'Jugadores'),
            ],
          ),
        ),
        body: const TabBarView(children: [_CrearCuentas(), _Jugadores()]),
      ),
    );
  }
}

class _CrearCuentas extends ConsumerStatefulWidget {
  const _CrearCuentas();

  @override
  ConsumerState<_CrearCuentas> createState() => _CrearCuentasState();
}

class _CrearCuentasState extends ConsumerState<_CrearCuentas> {
  final _texto = TextEditingController();
  ListaAliases _lista = ListaAliases.desde('');
  bool _enviando = false;
  ApiException? _error;
  List<CuentaCreada>? _cuentas;
  bool _copiadas = false;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (!_lista.enviable || _enviando) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final cuentas = await ref
          .read(juegoApiProvider)
          .crearLote(_lista.validos);
      if (!mounted) return;
      setState(() {
        _cuentas = cuentas;
        _copiadas = false;
        _texto.clear();
        _lista = ListaAliases.desde('');
      });
      ref.invalidate(jugadoresProvider);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _copiar(List<CuentaCreada> cuentas) async {
    await Clipboard.setData(
      ClipboardData(
        text: [
          'alias\tcontraseña',
          for (final c in cuentas) '${c.alias}\t${c.password}',
        ].join('\n'),
      ),
    );
    if (!mounted) return;
    setState(() => _copiadas = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiadas: pégalas en una hoja de cálculo.'),
      ),
    );
  }

  /// Antes de perder las contraseñas (solo existen en esta pantalla).
  Future<bool> _confirmarSalida() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir sin copiar las contraseñas?'),
        content: const Text(
          'No se pueden volver a ver. Si sales, habrá que cambiarlas una a '
          'una.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Quedarme'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    return salir ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cuentas = _cuentas;
    return PopScope(
      canPop: cuentas == null || _copiadas,
      onPopInvokedWithResult: (salio, _) async {
        if (salio) return;
        if (await _confirmarSalida() && context.mounted) {
          setState(() => _copiadas = true);
          Navigator.of(context).pop();
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          AnchoMaximo(
            ancho: 640,
            child: cuentas == null ? _formulario() : _resultado(cuentas),
          ),
        ],
      ),
    );
  }

  Widget _formulario() {
    final tema = Theme.of(context);
    final l = _lista;
    final error = _error;
    final enUso = switch (error?.detalle?['aliases']) {
      final List<Object?> a => a.whereType<String>().toList(),
      _ => const <String>[],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Escribe o pega los alias de tus estudiantes (uno por línea, o '
          'separados por comas). Se crean como jugadores con una contraseña '
          'generada que podrán cambiar después.',
          style: tema.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('aliases'),
          controller: _texto,
          minLines: 6,
          maxLines: 12,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Alias',
            hintText: 'Ana_Gomez\nLuis_P\nDetective_07',
            alignLabelWithHint: true,
          ),
          onChanged: (t) => setState(() {
            _lista = ListaAliases.desde(t);
            _error = null;
          }),
        ),
        const SizedBox(height: 8),
        Text(
          '${l.validos.length} de $maximoLote como máximo',
          style: tema.textTheme.labelLarge?.copyWith(
            color: l.demasiados ? tema.colorScheme.error : null,
          ),
        ),
        if (l.invalidos.isNotEmpty)
          _Problema(
            'No valen (3-30 caracteres: letras sin tilde, números o _): '
            '${l.invalidos.join(', ')}',
          ),
        if (l.repetidos.isNotEmpty)
          _Problema('Repetidos: ${l.repetidos.join(', ')}'),
        if (enUso.isNotEmpty)
          _Problema(
            'Ya existen: ${enUso.join(', ')}. No se creó ninguna cuenta; '
            'cámbialos y vuelve a intentarlo.',
          )
        else if (error != null)
          _Problema(error.mensaje),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: l.enviable && !_enviando ? _crear : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: _enviando
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.group_add_outlined),
          label: Text(
            l.validos.length == 1
                ? 'Crear 1 cuenta'
                : 'Crear ${l.validos.length} cuentas',
          ),
        ),
      ],
    );
  }

  Widget _resultado(List<CuentaCreada> cuentas) {
    final tema = Theme.of(context);
    final mono = tema.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.filled(
          color: tema.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: tema.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Las contraseñas solo se muestran ahora. Cópialas o '
                    'apúntalas antes de salir de esta pantalla.',
                    style: TextStyle(color: tema.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${cuentas.length} ${cuentas.length == 1 ? 'cuenta creada' : 'cuentas creadas'}',
          style: tema.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final c in cuentas)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(c.alias),
            trailing: SelectableText(c.password, style: mono),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _copiar(cuentas),
          icon: const Icon(Icons.copy_all_outlined),
          label: const Text('Copiar todas'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            if (_copiadas || await _confirmarSalida()) {
              setState(() => _cuentas = null);
            }
          },
          child: const Text('Crear más cuentas'),
        ),
      ],
    );
  }
}

class _Problema extends StatelessWidget {
  const _Problema(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      texto,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class _Jugadores extends ConsumerWidget {
  const _Jugadores();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(jugadoresProvider);
    return switch (estado) {
      AsyncValue(value: final List<Jugador> jugadores) => RefreshIndicator(
        onRefresh: () => ref.refresh(jugadoresProvider.future),
        child: jugadores.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 48),
                  VaciaVista(
                    mensaje: 'Todavía no hay jugadores.',
                    icono: Icons.group_outlined,
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: jugadores.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) =>
                    _FilaJugador(jugador: jugadores[i]),
              ),
      ),
      AsyncValue(:final error?) => ErrorVista(
        error: error,
        onReintentar: () => ref.invalidate(jugadoresProvider),
      ),
      _ => const CargandoVista(mensaje: 'Cargando jugadores…'),
    };
  }
}

class _FilaJugador extends StatelessWidget {
  const _FilaJugador({required this.jugador});

  final Jugador jugador;

  @override
  Widget build(BuildContext context) {
    final j = jugador;
    final tema = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        child: Text(j.alias.characters.first.toUpperCase()),
      ),
      title: Text(j.activo ? j.alias : '${j.alias} (desactivado)'),
      subtitle: Text(
        '${j.nivel} · ${_cuenta(j.casosResueltos, 'caso', 'casos')} · '
        '${_cuenta(j.rescatesLogrados, 'rescate', 'rescates')} · '
        '${_cuenta(j.insignias, 'insignia', 'insignias')}\n'
        '${_actividad(j.ultimaActividad)}',
      ),
      isThreeLine: true,
      trailing: Text(
        '${formatoEntero(j.xp)} XP',
        style: tema.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static String _cuenta(int n, String uno, String varios) =>
      '$n ${n == 1 ? uno : varios}';

  static String _actividad(DateTime? d) {
    if (d == null) return 'Aún no ha jugado';
    final dias = DateTime.now().difference(d).inDays;
    return switch (dias) {
      0 => 'Jugó hoy',
      1 => 'Jugó ayer',
      _ => 'Jugó hace $dias días',
    };
  }
}
