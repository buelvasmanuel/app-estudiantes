import 'package:flutter/material.dart';

import '../models/estudiante.dart';
import '../services/api_service.dart';
import '../widgets/estado_vistas.dart';
import '../widgets/promedio_badge.dart';
import 'estudiante_detalle_screen.dart';

/// Pestaña 1: listado de estudiantes con buscador, filtro y pull-to-refresh.
class EstudiantesScreen extends StatefulWidget {
  const EstudiantesScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<EstudiantesScreen> createState() => _EstudiantesScreenState();
}

class _EstudiantesScreenState extends State<EstudiantesScreen> {
  // Los tres estados de la pantalla:
  //   cargando  → _estudiantes == null && _error == null
  //   error     → _error != null (y no hay datos que mostrar)
  //   datos     → _estudiantes != null
  List<Estudiante>? _estudiantes;
  Object? _error;

  String _busqueda = '';
  bool _soloRiesgo = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final estudiantes = await widget.api.obtenerEstudiantes();
      // Tras un await la pantalla pudo cerrarse: comprobar `mounted` antes
      // de llamar a setState evita el error "setState() called after dispose".
      if (!mounted) return;
      setState(() {
        _estudiantes = estudiantes;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_estudiantes == null) {
        setState(() => _error = e);
      } else {
        // Si ya había datos (pull-to-refresh), no los tapamos con el error.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    }
  }

  void _reintentar() {
    setState(() => _error = null);
    _cargar();
  }

  List<Estudiante> get _filtrados {
    final consulta = normalizar(_busqueda.trim());
    return [
      for (final e in _estudiantes ?? const <Estudiante>[])
        if ((!_soloRiesgo || e.enRiesgo) &&
            (consulta.isEmpty || e.textoBusqueda.contains(consulta)))
          e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final estudiantes = _estudiantes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estudiantes'),
        actions: [
          if (estudiantes != null)
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: switch ((estudiantes, _error)) {
        (null, final Object error) => ErrorVista(
          error: error,
          onReintentar: _reintentar,
        ),
        (null, null) => const CargandoVista(mensaje: 'Cargando estudiantes…'),
        (final List<Estudiante> lista, _) => _contenido(lista),
      },
    );
  }

  Widget _contenido(List<Estudiante> todos) {
    final filtrados = _filtrados;
    final enRiesgo = todos.where((e) => e.enRiesgo).length;

    return AnchoMaximo(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              hintText: 'Buscar por nombre, carrera o ciudad',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (texto) => setState(() => _busqueda = texto),
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
              onRefresh: _cargar,
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PromedioBadge(estudiante: estudiante),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EstudianteDetalleScreen(estudiante: estudiante),
        ),
      ),
    );
  }
}
