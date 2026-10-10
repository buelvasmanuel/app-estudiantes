import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'theme.dart';

void main() {
  runApp(EstudiantesApp(api: ApiService()));
}

class EstudiantesApp extends StatelessWidget {
  const EstudiantesApp({super.key, required this.api});

  final ApiService api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Estudiantes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro,
      darkTheme: AppTheme.oscuro,
      home: InicioPage(api: api),
    );
  }
}

/// Estructura principal: una NavigationBar con 3 pestañas.
class InicioPage extends StatefulWidget {
  const InicioPage({super.key, required this.api});

  final ApiService api;

  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  int _pestana = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack mantiene vivas las 3 pantallas: al cambiar de pestaña no
      // se pierde lo que había (scroll, búsqueda, formulario...) ni se vuelve
      // a pedir todo a la API.
      body: IndexedStack(
        index: _pestana,
        children: const [
          _Proximamente(titulo: 'Estudiantes'),
          _Proximamente(titulo: 'Gráficas'),
          _Proximamente(titulo: 'Predicción'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: (i) => setState(() => _pestana = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Estudiantes',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Gráficas',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'Predicción',
          ),
        ],
      ),
    );
  }
}

class _Proximamente extends StatelessWidget {
  const _Proximamente({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: const Center(child: Text('Próximamente')),
    );
  }
}
