import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../identidad.dart';
import '../theme.dart';
import 'controlador.dart';
import 'disposicion.dart';
import 'modelo.dart';

/// Colores del campus, sacados del tema (claro u oscuro).
@immutable
class PaletaCampus {
  const PaletaCampus({
    required this.fondo,
    required this.fachada,
    required this.lateral,
    required this.tejado,
    required this.contorno,
    required this.seleccion,
    required this.vacia,
    required this.ok,
    required this.riesgo,
    required this.rayaRiesgo,
    required this.texto,
    required this.textoSecundario,
    this.brillo = false,
    this.grosorContorno = 1,
  });

  factory PaletaCampus.de(ThemeData tema) {
    final c = tema.colorScheme;
    final estado = tema.extension<ColoresEstado>() ?? ColoresEstado.claro;
    final estilo = tema.extension<EstiloJuego>() ?? const EstiloJuego();
    final noche = estilo.fondoCampus == FondoCampus.noche;
    final papel = estilo.fondoCampus == FondoCampus.papel;
    final fachada = noche
        ? const Color(0xFF2A3156)
        : papel
        ? c.surfaceContainerLowest
        : c.surfaceContainerHighest;
    return PaletaCampus(
      // Con fondo ilustrado, el juego deja ver el fondo de Flutter.
      fondo: estilo.fondoCampus == FondoCampus.liso
          ? c.surface
          : Colors.transparent,
      fachada: fachada,
      lateral: Color.lerp(fachada, Colors.black, papel ? 0.1 : 0.18)!,
      tejado: Color.lerp(fachada, Colors.white, papel ? 0.0 : 0.3)!,
      contorno: papel ? c.onSurface : c.outlineVariant,
      seleccion: c.primary,
      vacia: noche
          ? const Color(0xFF151A36)
          : papel
          ? c.surfaceContainerHigh
          : c.onSurface.withValues(alpha: 0.1),
      brillo: estilo.ventanasConBrillo,
      grosorContorno: estilo.contornoTinta ? 1.6 : 1,
      ok: estado.ok,
      riesgo: estado.riesgo,
      rayaRiesgo: estado.onRiesgo,
      texto: c.onSurface,
      textoSecundario: c.onSurfaceVariant,
    );
  }

  final Color fondo;
  final Color fachada;
  final Color lateral;
  final Color tejado;
  final Color contorno;
  final Color seleccion;
  final Color vacia;
  final Color ok;
  final Color riesgo;
  final Color rayaRiesgo;
  final Color texto;
  final Color textoSecundario;

  /// Las ventanas encendidas brillan (identidad "noche").
  final bool brillo;
  final double grosorContorno;

  @override
  bool operator ==(Object other) =>
      other is PaletaCampus &&
      other.fondo == fondo &&
      other.fachada == fachada &&
      other.seleccion == seleccion &&
      other.ok == ok &&
      other.riesgo == riesgo &&
      other.texto == texto &&
      other.brillo == brillo &&
      other.vacia == vacia;

  @override
  int get hashCode => Object.hash(fondo, fachada, seleccion, ok, riesgo, texto);
}

/// El juego de Flame: solo dibuja el campus que describe el [controlador].
///
/// Los gestos los recoge Flutter (CampusScreen) y cambian el controlador;
/// aquí, en cada fotograma, se copia la cámara y se avanzan las animaciones.
class CampusJuego extends FlameGame {
  CampusJuego(this.controlador, this._paleta);

  final ControladorCampus controlador;
  PaletaCampus _paleta;

  PaletaCampus get paleta => _paleta;
  set paleta(PaletaCampus valor) {
    if (valor == _paleta) return;
    _paleta = valor;
    _pintor?.paletaCambiada();
  }

  _PintorCampus? _pintor;

  @override
  Color backgroundColor() => _paleta.fondo;

  @override
  Future<void> onLoad() async {
    world.add(_pintor = _PintorCampus());
  }

  @override
  void update(double dt) {
    final vista = controlador.vista;
    camera.viewfinder
      ..position = Vector2(vista.centro.dx, vista.centro.dy)
      ..zoom = vista.zoom;
    super.update(dt);
  }

  @override
  void onRemove() {
    _pintor?.liberar();
    super.onRemove();
  }
}

class _PintorCampus extends Component with HasGameReference<CampusJuego> {
  /// Opacidad de las ventanas sin riesgo (baja con "Solo en riesgo").
  double _alfaSinRiesgo = 1;

  final _rotulos = <Edificio, (TextPainter, TextPainter)>{};
  Disposicion? _rotulosDe;

  ControladorCampus get _c => game.controlador;
  PaletaCampus get _p => game.paleta;

  void paletaCambiada() => liberar();

  void liberar() {
    for (final (nombre, cifra) in _rotulos.values) {
      nombre.dispose();
      cifra.dispose();
    }
    _rotulos.clear();
    _rotulosDe = null;
  }

  @override
  void update(double dt) {
    // Una sola animación protagonista: las ventanas se encienden piso a piso.
    _c.encendido = _c.reducirMovimiento
        ? 1
        : math.min(1, _c.encendido + dt / ControladorCampus.duracionEncendido);

    final objetivo = _c.soloRiesgo ? 0.15 : 1.0;
    if (_c.reducirMovimiento) {
      _alfaSinRiesgo = objetivo;
    } else {
      final paso = dt / ControladorCampus.duracionFundido * 0.85;
      _alfaSinRiesgo = _alfaSinRiesgo < objetivo
          ? math.min(objetivo, _alfaSinRiesgo + paso)
          : math.max(objetivo, _alfaSinRiesgo - paso);
    }
  }

  @override
  void render(Canvas canvas) {
    final d = _c.disposicion;
    if (d == null) return;
    if (!identical(_rotulosDe, d)) {
      liberar();
      _rotulosDe = d;
    }
    // Grosor constante en pantalla, sea cual sea el zoom.
    final px = 1 / _c.vista.zoom;
    final pisosEncendidos = (_c.encendido * Campus.semestres).ceil();

    for (final edificio in d.campus.edificios) {
      _edificio(canvas, d, edificio, px, pisosEncendidos);
    }
    _resaltado(canvas, d, px);
  }

  void _edificio(
    Canvas canvas,
    Disposicion d,
    Edificio edificio,
    double px,
    int pisosEncendidos,
  ) {
    final r = d.cuerpos[edificio]!;
    const fx = Medidas.fondoX;
    const fy = Medidas.fondoY;
    final contorno = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = px * _p.grosorContorno
      ..color = _p.contorno;

    final lateral = Path()
      ..moveTo(r.right, r.top)
      ..lineTo(r.right + fx, r.top - fy)
      ..lineTo(r.right + fx, r.bottom - fy)
      ..lineTo(r.right, r.bottom)
      ..close();
    final tejado = Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.left + fx, r.top - fy)
      ..lineTo(r.right + fx, r.top - fy)
      ..lineTo(r.right, r.top)
      ..close();
    canvas
      ..drawPath(lateral, Paint()..color = _p.lateral)
      ..drawPath(tejado, Paint()..color = _p.tejado)
      ..drawRect(r, Paint()..color = _p.fachada)
      ..drawPath(lateral, contorno)
      ..drawPath(tejado, contorno)
      ..drawRect(r, contorno);

    final vacia = Paint()..color = _p.vacia;
    final ok = Paint()..color = _p.ok.withValues(alpha: _alfaSinRiesgo);
    final riesgo = Paint()..color = _p.riesgo;
    // Halo de las ventanas encendidas (identidad "noche").
    final halo = _p.brillo
        ? (Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3))
        : null;
    final raya = Paint()
      ..color = _p.rayaRiesgo
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (final (p, piso) in edificio.pisos.indexed) {
      final encendido = p < pisosEncendidos;
      for (var h = 0; h < edificio.ancho; h++) {
        final v = Disposicion.rectVentana(r, p, h);
        final estudiante = h < piso.length ? piso[h] : null;
        if (estudiante == null || !encendido) {
          canvas.drawRect(v, vacia);
          continue;
        }
        if (halo != null) {
          final color = estudiante.enRiesgo
              ? _p.riesgo
              : _p.ok.withValues(alpha: _alfaSinRiesgo);
          canvas.drawRect(
            v.inflate(1.5),
            halo..color = color.withValues(alpha: color.a * 0.55),
          );
        }
        if (estudiante.enRiesgo) {
          // Franja diagonal: el riesgo se distingue también sin color.
          canvas
            ..drawRect(v, riesgo)
            ..drawLine(
              v.bottomLeft + const Offset(1.5, -1.5),
              v.topRight + const Offset(-1.5, 1.5),
              raya,
            );
        } else {
          canvas.drawRect(v, ok);
        }
      }
    }

    if (_c.edificioSeleccionado == edificio) {
      final marco = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * px
        ..color = _p.seleccion;
      canvas
        ..drawRect(r, marco)
        ..drawPath(lateral, marco)
        ..drawPath(tejado, marco);
    }

    final (nombre, cifra) = _rotulos[edificio] ??= _crearRotulos(d, edificio);
    final centro = r.center.dx + fx / 2;
    nombre.paint(canvas, Offset(centro - nombre.width / 2, r.bottom + 6));
    cifra.paint(
      canvas,
      Offset(centro - cifra.width / 2, r.bottom + 8 + nombre.height),
    );
  }

  /// El estudiante seleccionado, con un marco alrededor de su ventana.
  void _resaltado(Canvas canvas, Disposicion d, double px) {
    final estudiante = _c.estudianteSeleccionado;
    if (estudiante == null) return;
    final v = d.ventanas[estudiante.id];
    if (v == null) return;
    canvas.drawRect(
      v.inflate(2.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * px
        ..color = _p.seleccion,
    );
  }

  (TextPainter, TextPainter) _crearRotulos(Disposicion d, Edificio edificio) {
    final maximo = d.celda.width - Medidas.hueco;
    TextPainter texto(String s, TextStyle estilo) => TextPainter(
      text: TextSpan(text: s, style: estilo),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maximo);
    return (
      texto(
        edificio.carrera,
        TextStyle(color: _p.texto, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      texto(
        '${edificio.enRiesgo} de ${edificio.total} en riesgo',
        TextStyle(color: _p.textoSecundario, fontSize: 11),
      ),
    );
  }
}
