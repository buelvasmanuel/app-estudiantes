import 'package:flutter/material.dart';

import 'screens/estudiantes_screen.dart';
import 'screens/graficas_screen.dart';
import 'screens/prediccion_screen.dart';
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
        children: [
          EstudiantesScreen(api: widget.api),
          GraficasScreen(api: widget.api),
          PrediccionScreen(api: widget.api),
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
