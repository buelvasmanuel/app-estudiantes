import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../router.dart';
import '../services/api_service.dart';
import '../tema/temas.dart';
import '../widgets/estado_vistas.dart';

enum ModoAcceso { login, registro }

/// Reglas de `docs/CONTRATO_AUTH.md` §3. Se comprueban aquí para avisar sin
/// esperar a la API, pero quien manda es la API (responde 422 si no se
/// cumplen).
abstract final class ReglasAcceso {
  static final alias = RegExp(r'^[A-Za-z0-9_]{3,30}$');
  static const passwordMin = 10;
  static const passwordMax = 128;

  static String? validarAlias(String? valor) {
    final v = valor ?? '';
    if (v.isEmpty) return 'Escribe tu alias';
    if (!alias.hasMatch(v)) {
      return 'De 3 a 30 caracteres: letras sin tilde, números o _';
    }
    return null;
  }

  static String? validarPasswordNueva(String? valor, String alias) {
    final v = valor ?? '';
    if (v.length < passwordMin) {
      return 'Al menos $passwordMin caracteres';
    }
    if (v.length > passwordMax) return 'Como mucho $passwordMax caracteres';
    if (v.toLowerCase() == alias.toLowerCase()) {
      return 'No puede ser igual al alias';
    }
    return null;
  }
}

/// Login y registro: el mismo formulario, con un campo más en el registro.
class AccesoScreen extends ConsumerStatefulWidget {
  const AccesoScreen({super.key, required this.modo, this.desde});

  final ModoAcceso modo;

  /// Ruta a la que volver después (la lleva el router en `?desde=`).
  final String? desde;

  @override
  ConsumerState<AccesoScreen> createState() => _AccesoScreenState();
}

class _AccesoScreenState extends ConsumerState<AccesoScreen> {
  final _formulario = GlobalKey<FormState>();
  final _alias = TextEditingController();
  final _password = TextEditingController();
  final _repetida = TextEditingController();

  bool _verPassword = false;
  bool _enviando = false;
  ApiException? _error;

  /// Tras un 429: hasta cuándo esperar (se muestra una cuenta atrás).
  DateTime? _bloqueadoHasta;
  Timer? _cuentaAtras;

  bool get _esRegistro => widget.modo == ModoAcceso.registro;

  @override
  void dispose() {
    _alias.dispose();
    _password.dispose();
    _repetida.dispose();
    _cuentaAtras?.cancel();
    super.dispose();
  }

  int get _segundosBloqueo {
    final hasta = _bloqueadoHasta;
    if (hasta == null) return 0;
    final restante = hasta.difference(DateTime.now());
    return restante.isNegative ? 0 : (restante.inMilliseconds / 1000).ceil();
  }

  Future<void> _enviar() async {
    if (_enviando || _segundosBloqueo > 0) return;
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    final sesion = ref.read(sesionProvider);
    try {
      if (_esRegistro) {
        await sesion.registrarse(_alias.text, _password.text);
      } else {
        await sesion.iniciarSesion(_alias.text, _password.text);
      }
      // Con sesión, el router lleva solo a la app (o a `desde`).
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      final espera = e.reintentarEn;
      if (e.statusCode == 429 && espera != null) _bloquear(espera);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _bloquear(Duration espera) {
    _bloqueadoHasta = DateTime.now().add(espera);
    _cuentaAtras?.cancel();
    _cuentaAtras = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_segundosBloqueo == 0) t.cancel();
      setState(() {});
    });
  }

  void _cambiarModo() {
    final destino = _esRegistro ? Rutas.login : Rutas.registro;
    final desde = widget.desde;
    context.go(
      desde == null
          ? destino
          : Uri(path: destino, queryParameters: {'desde': desde}).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final aviso = _esRegistro ? null : ref.watch(sesionProvider).aviso;
    final despertando = ref.watch(apiServiceProvider).despertando;
    final bloqueo = _segundosBloqueo;

    return Scaffold(
      // El fondo del tema (cielo nocturno o cuadrícula de papel), como en el
      // Campus: la primera impresión ya es la del juego.
      body: CustomPaint(
        painter: PintorFondoCampus(
          EstiloJuego.of(context).fondoCampus,
          tema.colorScheme,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AnchoMaximo(
                ancho: 420,
                child: Form(
                  key: _formulario,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.travel_explore_rounded,
                          size: 56,
                          color: tema.colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Campus Detective',
                          style: tema.textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _esRegistro
                              ? 'Crea tu cuenta de detective'
                              : 'Inicia sesión para investigar',
                          style: tema.textTheme.bodyLarge?.copyWith(
                            color: tema.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (aviso != null) ...[
                          _Mensaje(texto: aviso, icono: Icons.info_outline),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          key: const Key('alias'),
                          controller: _alias,
                          decoration: const InputDecoration(
                            labelText: 'Alias',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          autofillHints: const [AutofillHints.username],
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            // El alias no admite espacios: se evitan al escribir.
                            FilteringTextInputFormatter.deny(RegExp(r'\s')),
                          ],
                          validator: _esRegistro
                              ? ReglasAcceso.validarAlias
                              : (v) => (v ?? '').isEmpty
                                    ? 'Escribe tu alias'
                                    : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('password'),
                          controller: _password,
                          obscureText: !_verPassword,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            helperText: _esRegistro
                                ? 'Al menos ${ReglasAcceso.passwordMin} '
                                      'caracteres. Una frase es fácil de '
                                      'recordar.'
                                : null,
                            suffixIcon: IconButton(
                              tooltip: _verPassword
                                  ? 'Ocultar contraseña'
                                  : 'Mostrar contraseña',
                              onPressed: () =>
                                  setState(() => _verPassword = !_verPassword),
                              icon: Icon(
                                _verPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          autofillHints: [
                            _esRegistro
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: _esRegistro
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onFieldSubmitted: _esRegistro
                              ? null
                              : (_) => _enviar(),
                          validator: _esRegistro
                              ? (v) => ReglasAcceso.validarPasswordNueva(
                                  v,
                                  _alias.text,
                                )
                              : (v) => (v ?? '').isEmpty
                                    ? 'Escribe tu contraseña'
                                    : null,
                        ),
                        if (_esRegistro) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('repetida'),
                            controller: _repetida,
                            obscureText: !_verPassword,
                            decoration: const InputDecoration(
                              labelText: 'Repite la contraseña',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _enviar(),
                            validator: (v) => v == _password.text
                                ? null
                                : 'Las contraseñas no coinciden',
                          ),
                        ],
                        if (_error case final error?) ...[
                          const SizedBox(height: 16),
                          _Mensaje(
                            texto: error.mensaje,
                            icono: Icons.error_outline,
                            esError: true,
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _enviando || bloqueo > 0 ? null : _enviar,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          child: ValueListenableBuilder<bool>(
                            valueListenable: despertando,
                            builder: (context, dormido, _) => Text(
                              bloqueo > 0
                                  ? 'Espera $bloqueo s'
                                  : !_enviando
                                  ? (_esRegistro ? 'Crear cuenta' : 'Entrar')
                                  : dormido
                                  ? 'Despertando el servidor…'
                                  : (_esRegistro ? 'Creando…' : 'Entrando…'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _enviando ? null : _cambiarModo,
                          child: Text(
                            _esRegistro
                                ? '¿Ya tienes cuenta? Inicia sesión'
                                : '¿No tienes cuenta? Regístrate',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Recuadro con un aviso (información o error).
class _Mensaje extends StatelessWidget {
  const _Mensaje({
    required this.texto,
    required this.icono,
    this.esError = false,
  });

  final String texto;
  final IconData icono;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final fondo = esError ? colores.errorContainer : colores.secondaryContainer;
    final primerPlano = esError
        ? colores.onErrorContainer
        : colores.onSecondaryContainer;
    return Card.filled(
      color: fondo,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icono, color: primerPlano),
            const SizedBox(width: 12),
            Expanded(
              child: Text(texto, style: TextStyle(color: primerPlano)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Al arrancar, mientras se comprueba la sesión guardada.
class CargandoSesionScreen extends ConsumerWidget {
  const CargandoSesionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    final api = ref.watch(apiServiceProvider);
    return Scaffold(
      body: ListenableBuilder(
        listenable: sesion,
        builder: (context, _) => switch (sesion.errorAlRestaurar) {
          final error? => ErrorVista(
            error: error,
            onReintentar: sesion.restaurar,
          ),
          null => CargandoVista(
            mensaje: 'Recuperando tu sesión…',
            despertando: api.despertando,
          ),
        },
      ),
    );
  }
}
