import 'dart:math' as math;
import 'dart:ui';

import '../models/estudiante.dart';
import 'modelo.dart';

/// Medidas del dibujo, en unidades del mundo (con zoom 1, píxeles lógicos).
abstract final class Medidas {
  static const ventanaAncho = 8.0;
  static const ventanaAlto = 10.0;
  static const separacion = 3.0;
  static const pisoAlto = ventanaAlto + 4;
  static const margenLateral = 7.0;
  static const margenSuperior = 6.0;
  static const base = 8.0;

  /// Desplazamiento de la cara lateral y el tejado (el efecto 2.5D).
  static const fondoX = 12.0;
  static const fondoY = 9.0;

  /// Espacio para el nombre y la cifra bajo cada edificio.
  static const rotulo = 36.0;
  static const hueco = 24.0;

  static const alturaCuerpo =
      margenSuperior + Campus.semestres * pisoAlto + base;

  static double anchoCuerpo(int ventanas) =>
      2 * margenLateral + ventanas * ventanaAncho + (ventanas - 1) * separacion;

  /// Por debajo de este tamaño en pantalla una ventana es difícil de tocar:
  /// el toque selecciona el edificio entero.
  static const ventanaTocableMin = 12.0;
}

/// Lo que hay en un punto del campus.
sealed class Objetivo {
  const Objetivo();
}

class ObjetivoEdificio extends Objetivo {
  const ObjetivoEdificio(this.edificio);
  final Edificio edificio;
}

class ObjetivoEstudiante extends Objetivo {
  const ObjetivoEstudiante(this.estudiante, this.edificio);
  final Estudiante estudiante;
  final Edificio edificio;
}

/// Posición de cada edificio y ventana en el mundo.
class Disposicion {
  Disposicion._(
    this.campus,
    this.columnas,
    this.celda,
    this.cuerpos,
    this.ventanas,
  );

  /// Coloca los edificios en una rejilla de [columnas], en orden (el primero,
  /// arriba a la izquierda). Todas las celdas miden igual para que los pisos
  /// queden alineados.
  factory Disposicion.calcular(Campus campus, int columnas) {
    final celda = _celda(campus);
    final cuerpos = <Edificio, Rect>{};
    final ventanas = <int, Rect>{};
    for (final (i, edificio) in campus.edificios.indexed) {
      final ancho = Medidas.anchoCuerpo(edificio.ancho);
      final x =
          (i % columnas) * celda.width +
          (celda.width - Medidas.hueco - Medidas.fondoX - ancho) / 2;
      final y = (i ~/ columnas) * celda.height + Medidas.fondoY;
      final cuerpo = Rect.fromLTWH(x, y, ancho, Medidas.alturaCuerpo);
      cuerpos[edificio] = cuerpo;
      for (final (p, piso) in edificio.pisos.indexed) {
        for (final (v, estudiante) in piso.indexed) {
          ventanas[estudiante.id] = rectVentana(cuerpo, p, v);
        }
      }
    }
    return Disposicion._(campus, columnas, celda, cuerpos, ventanas);
  }

  /// Las columnas con las que el campus entero se ve más grande en
  /// [pantalla] (en el celular en vertical suelen ser 3; en horizontal, 4-8).
  factory Disposicion.ajustada(Campus campus, Size pantalla) {
    final n = math.max(1, campus.edificios.length);
    final celda = _celda(campus);
    var mejor = 1;
    var mejorEscala = 0.0;
    for (var c = 1; c <= n; c++) {
      final filas = (n / c).ceil();
      final escala = math.min(
        pantalla.width / (c * celda.width),
        pantalla.height / (filas * celda.height),
      );
      if (escala > mejorEscala) {
        mejor = c;
        mejorEscala = escala;
      }
    }
    return Disposicion.calcular(campus, mejor);
  }

  static Size _celda(Campus campus) {
    final masAncho = campus.edificios.fold<int>(
      1,
      (m, e) => math.max(m, e.ancho),
    );
    return Size(
      Medidas.anchoCuerpo(masAncho) + Medidas.fondoX + Medidas.hueco,
      Medidas.fondoY + Medidas.alturaCuerpo + Medidas.rotulo + Medidas.hueco,
    );
  }

  /// La ventana [hueco] (0 = la de la izquierda) del piso [piso] (0 = 1.er
  /// semestre) de la fachada [cuerpo]. También las vacías.
  static Rect rectVentana(Rect cuerpo, int piso, int hueco) => Rect.fromLTWH(
    cuerpo.left +
        Medidas.margenLateral +
        hueco * (Medidas.ventanaAncho + Medidas.separacion),
    cuerpo.top +
        Medidas.margenSuperior +
        (Campus.semestres - 1 - piso) * Medidas.pisoAlto,
    Medidas.ventanaAncho,
    Medidas.ventanaAlto,
  );

  final Campus campus;
  final int columnas;

  /// Tamaño de cada celda de la rejilla (igual para todos los edificios).
  final Size celda;

  /// Fachada de cada edificio (sin la cara lateral ni el tejado).
  final Map<Edificio, Rect> cuerpos;

  /// Ventana de cada estudiante, por id.
  final Map<int, Rect> ventanas;

  /// Todo lo que ocupa un edificio: fachada, cara lateral, tejado y rótulo.
  Rect zonaDe(Edificio edificio) {
    final c = cuerpos[edificio]!;
    return Rect.fromLTRB(
      c.left,
      c.top - Medidas.fondoY,
      c.right + Medidas.fondoX,
      c.bottom + Medidas.rotulo,
    );
  }

  /// El rectángulo que contiene todo el campus.
  late final Rect limites =
      cuerpos.keys
          .map(zonaDe)
          .fold<Rect?>(null, (r, z) => r?.expandToInclude(z) ?? z) ??
      Rect.zero;

  /// Qué hay en [punto] (coordenadas del mundo) si la vista tiene [zoom].
  ///
  /// Con zoom alto se puede tocar una ventana; con el campus entero a la
  /// vista las ventanas miden unos 6 px y el toque elige el edificio.
  Objetivo? objetivoEn(Offset punto, double zoom) {
    for (final edificio in campus.edificios) {
      if (!zonaDe(edificio).contains(punto)) continue;
      if (zoom * Medidas.ventanaAncho >= Medidas.ventanaTocableMin) {
        // Margen de media separación: tocar entre dos ventanas cuenta.
        const margen = Medidas.separacion / 2;
        for (final estudiante in edificio.pisos.expand((p) => p)) {
          if (ventanas[estudiante.id]!.inflate(margen).contains(punto)) {
            return ObjetivoEstudiante(estudiante, edificio);
          }
        }
      }
      return ObjetivoEdificio(edificio);
    }
    return null;
  }
}

/// La cámara: qué punto del mundo está en el centro y con cuánto zoom.
class Vista {
  const Vista({required this.centro, required this.zoom});

  final Offset centro;
  final double zoom;

  static const zoomMax = 4.0;

  /// Convierte un punto de la pantalla (relativo al lienzo de [tamano]) al
  /// mundo.
  Offset aMundo(Offset pantalla, Size tamano) =>
      centro + (pantalla - tamano.center(Offset.zero)) / zoom;

  Offset aPantalla(Offset mundo, Size tamano) =>
      (mundo - centro) * zoom + tamano.center(Offset.zero);

  /// La vista que muestra [zona] entera, con un pequeño margen.
  static Vista encuadrar(Rect zona, Size tamano, {double margen = 12}) {
    final escala = math.min(
      (tamano.width - 2 * margen) / zona.width,
      (tamano.height - 2 * margen) / zona.height,
    );
    return Vista(
      centro: zona.center,
      zoom: escala.clamp(0.05, zoomMax).toDouble(),
    );
  }

  /// Zoom alrededor de [foco] (en pantalla): ese punto no se mueve.
  Vista conZoom(
    double nuevo,
    Offset foco,
    Size tamano, {
    double minimo = 0.05,
  }) {
    final z = nuevo.clamp(minimo, zoomMax).toDouble();
    final enMundo = aMundo(foco, tamano);
    return Vista(
      centro: enMundo - (foco - tamano.center(Offset.zero)) / z,
      zoom: z,
    );
  }

  Vista desplazada(Offset deltaPantalla) =>
      Vista(centro: centro - deltaPantalla / zoom, zoom: zoom);

  /// Mantiene el centro dentro de [limites], para no perder el campus.
  Vista limitada(Rect limites) => Vista(
    centro: Offset(
      centro.dx.clamp(limites.left, limites.right).toDouble(),
      centro.dy.clamp(limites.top, limites.bottom).toDouble(),
    ),
    zoom: zoom,
  );
}
