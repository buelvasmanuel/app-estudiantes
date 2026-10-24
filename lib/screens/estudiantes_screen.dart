import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/estudiante.dart';
import '../providers.dart';
import '../router.dart';
import '../services/api_service.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/menu_cuenta.dart';
import '../widgets/promedio_badge.dart';
import '../widgets/titulo_barra.dart';

/// Pestaña 1: listado de estudiantes con buscador, filtro y pull-to-refresh.
class EstudiantesScreen extends ConsumerStatefulWidget {
  const EstudiantesScreen({super.key, this.carrera, this.pestanas});

  /// El selector de la pestaña Datos (`SelectorDatos`), si va dentro de ella.
  final PreferredSizeWidget? pestanas;

  /// Si no es `null`, solo se muestran los de esa carrera (llega desde el
  /// expediente de un edificio del Campus).
  final String? carrera;

  @override
  ConsumerState<EstudiantesScreen> createState() => _EstudiantesScreenState();
}

class _EstudiantesScreenState extends ConsumerState<EstudiantesScreen> {
  // Los datos (cargando / error / lista) los guarda estudiantesProvider; aquí
  // solo queda el estado de la interfaz.
  String _busqueda = '';
  bool _soloRiesgo = false;

  Future<void> _actualizar() async {
    try {
      ref.invalidate(estudiantesProvider);
      await ref.read(estudiantesProvider.future);
    } on ApiException catch (e) {
      // Tras un await la pantalla pudo cerrarse: comprobar `mounted` antes
      // de usar el context.
      if (!mounted) return;
      // Si ya había datos, no los tapamos con el error (el provider conserva
      // la lista anterior): basta con avisar.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  List<Estudiante> _filtrar(List<Estudiante> estudiantes) {
    final consulta = normalizar(_busqueda.trim());
    return [
      for (final e in estudiantes)
        if ((!_soloRiesgo || e.enRiesgo) &&
            (consulta.isEmpty || e.textoBusqueda.contains(consulta)))
          e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(estudiantesProvider);
    final estudiantes = estado.value;
    return Scaffold(
      appBar: AppBar(
        title: const TituloBarra('Estudiantes'),
        bottom: widget.pestanas,
        actions: [
          if (estudiantes != null)
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _actualizar,
              icon: const Icon(Icons.refresh_rounded),
            ),
          const MenuCuenta(),
        ],
      ),
      body: switch (estado) {
        AsyncValue(value: final List<Estudiante> lista) => _contenido(lista),
        AsyncValue(:final error?) => ErrorVista(
          error: error,
          onReintentar: () => ref.invalidate(estudiantesProvider),
        ),
        _ => CargandoVista(
          mensaje: 'Cargando estudiantes…',
          despertando: ref.watch(apiServiceProvider).despertando,
        ),
      },
    );
  }

  Widget _contenido(List<Estudiante> lista) {
    final carrera = widget.carrera;
    final todos = carrera == null
        ? lista
        : [
            for (final e in lista)
              if (e.carrera == carrera) e,
          ];
    final filtrados = _filtrar(todos);
    final enRiesgo = todos.where((e) => e.enRiesgo).length;

    return AnchoMaximo(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              hintText: 'Nombre, carrera o ciudad',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (texto) => setState(() => _busqueda = texto),
            ),
          ),
          if (carrera != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: const Icon(Icons.school_outlined, size: 18),
                  label: Text('Carrera: $carrera'),
                  deleteButtonTooltipMessage: 'Quitar el filtro de carrera',
                  onDeleted: () => context.go(Rutas.estudiantes),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  label: Text('En riesgo ($enRiesgo)'),
                  avatar: _soloRiesgo
                      ? null
                      : const Icon(Icons.warning_amber_rounded, size: 18),
                  selected: _soloRiesgo,
                  onSelected: (v) => setState(() => _soloRiesgo = v),
                ),
                const Spacer(),
                Text(
                  '${filtrados.length} de ${todos.length}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            // RefreshIndicator necesita un hijo desplazable. Con
            // AlwaysScrollableScrollPhysics se puede tirar hacia abajo
            // aunque la lista sea corta o esté vacía.
            child: RefreshIndicator(
              onRefresh: _actualizar,
              child: filtrados.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        VaciaVista(
                          mensaje: todos.isEmpty
                              ? 'No hay estudiantes en la base de datos.\n'
                                    'Carga datos con: python -m scripts.seed_estudiantes'
                              : 'Ningún estudiante coincide con la búsqueda.',
                          icono: todos.isEmpty
                              ? Icons.inbox_outlined
                              : Icons.search_off_rounded,
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: filtrados.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (context, i) =>
                          _EstudianteTile(estudiante: filtrados[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstudianteTile extends StatelessWidget {
  const _EstudianteTile({required this.estudiante});

  final Estudiante estudiante;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Hero(
        tag: 'avatar-${estudiante.id}',
        child: EstudianteAvatar(estudiante: estudiante),
      ),
      title: Text(estudiante.nombreCompleto),
      subtitle: Text(
        '${estudiante.carrera} · Semestre ${estudiante.semestre}',
        // Dos líneas: con letra grande, una sola se cortaba.
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PromedioBadge(estudiante: estudiante),
      onTap: () =>
          context.push(Rutas.estudiante(estudiante.id), extra: estudiante),
    );
  }
}
