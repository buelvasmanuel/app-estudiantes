import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/estudiante.dart';
import 'disposicion.dart';
import 'modelo.dart';

/// Estado del campus compartido entre la interfaz (widgets de Flutter) y el
/// dibujo (Flame).
///
/// Notifica solo lo que cambia la interfaz (selección, filtro). La cámara y
/// las animaciones las lee el juego en cada fotograma, sin notificar: mover
/// el mapa no reconstruye ningún widget.
class ControladorCampus extends ChangeNotifier {
  ControladorCampus(this.campus);

  final Campus campus;

  Disposicion? _disposicion;
  Size _tamano = Size.zero;
  Vista _vista = const Vista(centro: Offset.zero, zoom: 1);
  double _zoomMin = 0.05;

  /// Lo que hay que mantener encuadrado si el lienzo cambia de alto (al
  /// abrir o cerrar el panel inferior). `null` si el usuario movió el mapa.
  Rect? _encuadre;

  Objetivo? _seleccion;
  bool _soloRiesgo = false;

  /// "Reducir movimiento" del sistema: sin animación de entrada ni fundidos.
  bool reducirMovimiento = false;

  /// Progreso de la animación de entrada (0 → 1): las ventanas se encienden
  /// piso a piso. Lo avanza el juego.
  double encendido = 0;

  /// Duración de la animación de entrada.
  static const duracionEncendido = 1.2;

  /// Duración del fundido del filtro "Solo en riesgo".
  static const duracionFundido = 0.2;

  Disposicion? get disposicion => _disposicion;
  Size get tamano => _tamano;
  Vista get vista => _vista;
  Objetivo? get seleccion => _seleccion;
  bool get soloRiesgo => _soloRiesgo;

  Edificio? get edificioSeleccionado => switch (_seleccion) {
    ObjetivoEdificio(:final edificio) => edificio,
    ObjetivoEstudiante(:final edificio) => edificio,
    null => null,
  };

  Estudiante? get estudianteSeleccionado => switch (_seleccion) {
    ObjetivoEstudiante(:final estudiante) => estudiante,
    _ => null,
  };

  bool get animacionTerminada => encendido >= 1;

  /// El lienzo cambió de tamaño.
  ///
  /// La rejilla (cuántas columnas) solo se recalcula si cambia el ANCHO
  /// (girar el celular, redimensionar la ventana). Si solo cambia el alto,
  /// porque se abre o se cierra el panel inferior, los edificios no se mueven
  /// de sitio: se vuelve a encuadrar lo que estaba encuadrado.
  void ajustarA(Size tamano) {
    if (tamano == _tamano || tamano.isEmpty) return;
    final mismoAncho = _disposicion != null && tamano.width == _tamano.width;
    _tamano = tamano;
    if (!mismoAncho) {
      _disposicion = Disposicion.ajustada(campus, tamano);
      _encuadre = _disposicion!.limites;
    }
    final d = _disposicion!;
    _zoomMin = Vista.encuadrar(d.limites, tamano).zoom * 0.8;
    final encuadre = _encuadre;
    _vista = encuadre != null
        ? Vista.encuadrar(encuadre, tamano, margen: _margenDe(encuadre, d))
        : _vista.limitada(d.limites);
  }

  double _margenDe(Rect encuadre, Disposicion d) =>
      encuadre == d.limites ? 12 : 24;

  // --- Cámara ---------------------------------------------------------------

  void encuadrarTodo() {
    final d = _disposicion;
    if (d == null) return;
    _encuadre = d.limites;
    _vista = Vista.encuadrar(d.limites, _tamano);
  }

  /// Zoom por pasos (botones, rueda del ratón): nunca animado.
  void acercar([Offset? foco]) => _zoomPor(1.5, foco);
  void alejar([Offset? foco]) => _zoomPor(1 / 1.5, foco);

  void _zoomPor(double factor, Offset? foco) =>
      zoomA(_vista.zoom * factor, foco ?? _tamano.center(Offset.zero));

  void zoomA(double zoom, Offset foco) {
    final d = _disposicion;
    if (d == null) return;
    _encuadre = null;
    _vista = _vista
        .conZoom(zoom, foco, _tamano, minimo: _zoomMin)
        .limitada(d.limites);
  }

  void desplazar(Offset deltaPantalla) {
    final d = _disposicion;
    if (d == null || deltaPantalla == Offset.zero) return;
    _encuadre = null;
    _vista = _vista.desplazada(deltaPantalla).limitada(d.limites);
  }

  // --- Selección ------------------------------------------------------------

  /// Un toque en el lienzo. Cualquier toque salta la animación de entrada.
  void tocar(Offset pantalla) {
    encendido = 1;
    final d = _disposicion;
    if (d == null) return;
    _seleccion = d.objetivoEn(_vista.aMundo(pantalla, _tamano), _vista.zoom);
    notifyListeners();
  }

  /// Desde la lista de edificios (accesible): selecciona y lo encuadra.
  void seleccionarEdificio(Edificio edificio) {
    encendido = 1;
    _seleccion = ObjetivoEdificio(edificio);
    final d = _disposicion;
    if (d != null) {
      _encuadre = d.zonaDe(edificio);
      _vista = Vista.encuadrar(_encuadre!, _tamano, margen: 24);
    }
    notifyListeners();
  }

  /// Desde el buscador: selecciona al estudiante y acerca la cámara a su
  /// ventana, lo bastante para que se pueda tocar. Sin vuelos: salta.
  void seleccionarEstudiante(Estudiante estudiante) {
    final edificio = campus.edificioDe(estudiante);
    if (edificio == null) return;
    encendido = 1;
    _seleccion = ObjetivoEstudiante(estudiante, edificio);
    final d = _disposicion;
    final ventana = d?.ventanas[estudiante.id];
    if (d != null && ventana != null) {
      final zoom = math.max(
        _vista.zoom,
        2 * Medidas.ventanaTocableMin / Medidas.ventanaAncho,
      );
      _encuadre = null;
      _vista = Vista(centro: ventana.center, zoom: zoom).limitada(d.limites);
    }
    notifyListeners();
  }

  void cerrarSeleccion() {
    _seleccion = null;
    notifyListeners();
  }

  void alternarSoloRiesgo() {
    _soloRiesgo = !_soloRiesgo;
    notifyListeners();
  }
}
