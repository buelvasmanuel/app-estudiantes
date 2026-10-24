import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../juego/juego_api.dart';
import '../models/sesion.dart';
import '../preferencias.dart';
import '../providers.dart';
import '../router.dart';
import '../services/api_service.dart';
import '../tema/temas.dart';
import '../formato.dart';

enum _Opcion { tema, perfil, docente, cerrar, cerrarTodas }

/// Botón de la cuenta (en la barra superior de cada pestaña): muestra el
/// alias y permite cerrar la sesión.
class MenuCuenta extends ConsumerWidget {
  const MenuCuenta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    final usuario = sesion.usuario;
    if (usuario == null) return const SizedBox.shrink();

    Future<void> elegir(_Opcion opcion) async {
      switch (opcion) {
        case _Opcion.tema:
          ref.read(temaProvider.notifier).alternar();
        case _Opcion.perfil:
          context.go(Rutas.perfil);
        case _Opcion.docente:
          await context.push(Rutas.docente);
        case _Opcion.cerrar:
          await sesion.cerrarSesion();
        case _Opcion.cerrarTodas:
          final confirmado = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('¿Cerrar todas las sesiones?'),
              content: const Text(
                'Se cerrará la sesión en todos tus dispositivos, también en '
                'este.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cerrar todas'),
                ),
              ],
            ),
          );
          if (confirmado != true) return;
          try {
            await sesion.cerrarTodas();
          } on ApiException catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(e.mensaje)));
          }
      }
    }

    final esDocente = usuario.rol == Rol.docente || usuario.rol == Rol.admin;
    // El tema al que se cambia (Noche ↔ Expediente).
    final otro = ref.watch(temaProvider) == TemaJuego.noche
        ? TemaJuego.expediente
        : TemaJuego.noche;
    final menu = PopupMenuButton<_Opcion>(
      tooltip: 'Cuenta',
      icon: CircleAvatar(
        radius: 16,
        child: Text(usuario.alias.substring(0, 1).toUpperCase()),
      ),
      onSelected: elegir,
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(usuario.alias),
            subtitle: Text(usuario.rol.name),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const Key('menu-tema'),
          value: _Opcion.tema,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            // Iconos y no emojis: en la web, un emoji obliga a descargar una
            // fuente de emojis aparte.
            leading: Icon(otro.icono),
            title: Text('Tema ${otro.nombre}'),
          ),
        ),
        const PopupMenuItem(
          value: _Opcion.perfil,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.badge_outlined),
            title: Text('Mi perfil'),
          ),
        ),
        if (esDocente)
          const PopupMenuItem(
            value: _Opcion.docente,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.co_present_outlined),
              title: Text('Panel del docente'),
            ),
          ),
        const PopupMenuItem(
          value: _Opcion.cerrar,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Cerrar sesión'),
          ),
        ),
        const PopupMenuItem(
          value: _Opcion.cerrarTodas,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.devices_outlined),
            title: Text('Cerrar sesión en todos los dispositivos'),
          ),
        ),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [const ChipNivel(), menu],
    );
  }
}

/// Nivel y XP del jugador, siempre a la vista. Lleva al perfil.
class ChipNivel extends ConsumerWidget {
  const ChipNivel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progreso = ref.watch(progresoProvider).value;
    // Sin datos (cargando, error, servidor sin /juego): no se muestra.
    if (progreso == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      button: true,
      label:
          'Nivel ${progreso.nivel.numero}, ${progreso.nivel.nombre}, '
          '${progreso.xp} puntos de experiencia. Abre tu perfil.',
      excludeSemantics: true,
      child: ActionChip(
        key: const Key('chip-nivel'),
        avatar: const Icon(Icons.bolt, size: 18),
        label: Text(
          'Nv ${progreso.nivel.numero} · ${formatoEntero(progreso.xp)} XP',
        ),
        onPressed: () => context.go(Rutas.perfil),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
