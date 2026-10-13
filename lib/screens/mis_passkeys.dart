import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../formato.dart';
import '../passkeys/modelo.dart';
import '../passkeys/navegador.dart';
import '../passkeys/passkeys_api.dart';
import '../services/api_service.dart';
import '../widgets/estado_vistas.dart';

/// Textos que comparten el login y el perfil.
abstract final class MisPasskeysTextos {
  static const sinSoporte =
      'Tu navegador no admite passkeys; usa Chrome, Edge, Firefox o Safari '
      'recientes.';
  static const cancelada =
      'No se creó la passkey. Puedes intentarlo de nuevo cuando quieras.';
  static const yaEnEsteDispositivo =
      'Este dispositivo ya guarda una passkey de tu cuenta.';
  static const creada =
      'Passkey creada. La próxima vez puedes entrar con ella.';
}

/// «Mis passkeys» en el Perfil (solo web): crear, ver y borrar. En el APK y
/// en el escritorio no aparece.
class MisPasskeys extends ConsumerStatefulWidget {
  const MisPasskeys({super.key});

  @override
  ConsumerState<MisPasskeys> createState() => _MisPasskeysState();
}

class _MisPasskeysState extends ConsumerState<MisPasskeys> {
  bool _creando = false;

  /// Aviso neutro (cancelar no es un error) o de error.
  ({String texto, bool error})? _aviso;

  Future<void> _crear() async {
    final nombre = await _pedirNombre();
    if (nombre == null || !mounted) return;
    setState(() {
      _creando = true;
      _aviso = null;
    });
    try {
      await ref.read(passkeysApiProvider).crear(nombre: nombre);
      ref.invalidate(misPasskeysProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text(MisPasskeysTextos.creada)),
          );
      }
    } on PasskeyCancelada {
      _avisar(MisPasskeysTextos.cancelada);
    } on PasskeyYaEnEsteDispositivo {
      _avisar(MisPasskeysTextos.yaEnEsteDispositivo);
    } on PasskeyNoSoportada {
      _avisar(MisPasskeysTextos.sinSoporte);
    } on PasskeyFallo catch (e) {
      _avisar(
        'El navegador no pudo crear la passkey (${e.nombre}).',
        error: true,
      );
    } on ApiException catch (e) {
      switch (e.codigo) {
        case 'passkey_repetida':
          _avisar(MisPasskeysTextos.yaEnEsteDispositivo);
        case 'reto_invalido':
          _avisar('La solicitud caducó. Inténtalo de nuevo.', error: true);
        default:
          _avisar(e.mensaje, error: true);
      }
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  void _avisar(String texto, {bool error = false}) {
    if (mounted) setState(() => _aviso = (texto: texto, error: error));
  }

  Future<String?> _pedirNombre() => showDialog<String>(
    context: context,
    builder: (_) => const _DialogoNombre(),
  );

  Future<void> _borrar(Passkey p) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Borrar «${p.nombre}»?'),
        content: const Text(
          'Ya no podrás entrar con ella. Tu contraseña sigue igual. (El '
          'navegador puede seguir mostrándola: bórrala también en su gestor '
          'de contraseñas.)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirmar-borrar-passkey'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (si != true || !mounted) return;
    try {
      await ref.read(passkeysApiProvider).borrar(p.id);
    } on ApiException catch (e) {
      // Ya no existía: se refresca la lista igual.
      if (e.codigo != 'passkey_no_encontrada') _avisar(e.mensaje, error: true);
    }
    ref.invalidate(misPasskeysProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(esWebProvider)) return const SizedBox.shrink();
    final tema = Theme.of(context);
    final soportado = ref.watch(navegadorPasskeysProvider).soportado;
    final aviso = _aviso;
    return Column(
      key: const Key('mis-passkeys'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text('Mis passkeys', style: tema.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Entra sin contraseña con la huella, la cara o el PIN de tu '
          'dispositivo. Tu contraseña sigue sirviendo.',
          style: tema.textTheme.bodyMedium?.copyWith(
            color: tema.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (!soportado)
          const _Nota(
            key: Key('passkeys-sin-soporte'),
            texto: MisPasskeysTextos.sinSoporte,
            icono: Icons.info_outline,
          )
        else ...[
          switch (ref.watch(misPasskeysProvider)) {
            AsyncValue(value: final List<Passkey> lista) when lista.isEmpty =>
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Aún no tienes passkeys.'),
              ),
            AsyncValue(value: final List<Passkey> lista) => Column(
              children: [for (final p in lista) _Fila(p, () => _borrar(p))],
            ),
            AsyncValue(:final error?) => ErrorVista(
              error: error,
              onReintentar: () => ref.invalidate(misPasskeysProvider),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
          if (aviso != null) ...[
            const SizedBox(height: 8),
            _Nota(
              key: const Key('aviso-passkeys'),
              texto: aviso.texto,
              icono: aviso.error ? Icons.error_outline : Icons.info_outline,
              error: aviso.error,
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('crear-passkey'),
            onPressed: _creando ? null : _crear,
            icon: _creando
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.fingerprint),
            label: const Text('Crear passkey'),
          ),
        ],
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(this.passkey, this.onBorrar);

  final Passkey passkey;
  final VoidCallback onBorrar;

  @override
  Widget build(BuildContext context) {
    final p = passkey;
    final creada = p.creadaEn;
    final uso = p.ultimoUso;
    return ListTile(
      key: Key('passkey-${p.id}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.key_outlined),
      title: Text(p.nombre),
      subtitle: Text(
        [
          if (creada != null) 'Creada el ${formatoFecha(creada)}',
          uso == null ? 'sin usar aún' : 'último uso: ${formatoFecha(uso)}',
          if (p.sincronizada) 'sincronizada entre tus dispositivos',
        ].join(' · '),
      ),
      trailing: IconButton(
        key: Key('borrar-passkey-${p.id}'),
        tooltip: 'Borrar «${p.nombre}»',
        onPressed: onBorrar,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

/// Recuadro de aviso: neutro (información) o de error.
class _Nota extends StatelessWidget {
  const _Nota({
    super.key,
    required this.texto,
    required this.icono,
    this.error = false,
  });

  final String texto;
  final IconData icono;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final fondo = error ? c.errorContainer : c.secondaryContainer;
    final texto2 = error ? c.onErrorContainer : c.onSecondaryContainer;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Card.filled(
        margin: EdgeInsets.zero,
        color: fondo,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icono, color: texto2),
              const SizedBox(width: 12),
              Expanded(
                child: Text(texto, style: TextStyle(color: texto2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pide el nombre de la passkey. El diálogo es dueño de su controlador: se
/// libera cuando el diálogo desaparece, no antes (la animación de cierre aún
/// lo usa).
class _DialogoNombre extends StatefulWidget {
  const _DialogoNombre();

  @override
  State<_DialogoNombre> createState() => _DialogoNombreState();
}

class _DialogoNombreState extends State<_DialogoNombre> {
  final _nombre = TextEditingController(text: 'Este dispositivo');

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nueva passkey'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ponle un nombre para reconocerla (por ejemplo, «Portátil de '
          'casa»). Después el navegador te pedirá tu huella, tu cara o tu '
          'PIN.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('nombre-passkey'),
          controller: _nombre,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('confirmar-nombre-passkey'),
        onPressed: () => Navigator.of(context).pop(_nombre.text),
        child: const Text('Crear'),
      ),
    ],
  );
}
