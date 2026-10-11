import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/api_service.dart';

enum _Opcion { cerrar, cerrarTodas }

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

    return PopupMenuButton<_Opcion>(
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
  }
}
