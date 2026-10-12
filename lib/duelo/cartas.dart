import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tema/temas.dart';
import '../theme.dart';
import 'modelo.dart';

/// Cómo le fue a una carta en la ronda que se está mostrando.
enum DesenlaceCarta { gana, pierde, empata }

DesenlaceCarta desenlace(GanadorRonda ganador, Lado lado) => switch (ganador) {
  GanadorRonda.empate => DesenlaceCarta.empata,
  GanadorRonda.yo =>
    lado == Lado.yo ? DesenlaceCarta.gana : DesenlaceCarta.pierde,
  GanadorRonda.rival =>
    lado == Lado.rival ? DesenlaceCarta.gana : DesenlaceCarta.pierde,
};

/// Colores de una carta según su desenlace (`null`: sin resolver).
({Color borde, Color fondo, Color texto, Color barra})? _coloresDesenlace(
  BuildContext context,
  DesenlaceCarta? d,
) {
  final c = ColoresEstado.of(context);
  final esquema = Theme.of(context).colorScheme;
  return switch (d) {
    null => null,
    DesenlaceCarta.gana => (
      borde: c.ok,
      fondo: c.okContenedor,
      texto: c.onOkContenedor,
      barra: c.ok,
    ),
    DesenlaceCarta.pierde => (
      borde: c.riesgo,
      fondo: c.riesgoContenedor,
      texto: c.onRiesgoContenedor,
      barra: c.riesgo,
    ),
    DesenlaceCarta.empata => (
      borde: esquema.outline,
      fondo: esquema.surfaceContainerHighest,
      texto: esquema.onSurface,
      barra: esquema.outline,
    ),
  };
}

String _palabra(DesenlaceCarta d) => switch (d) {
  DesenlaceCarta.gana => 'GANA',
  DesenlaceCarta.pierde => 'PIERDE',
  DesenlaceCarta.empata => 'EMPATE',
};

/// La carta del rival: boca abajo hasta que se resuelve la ronda, y entonces
/// se gira. Es la animación protagonista del duelo (PROPUESTA §2.4): dura
/// [duracionGiro], un toque la termina y con "reducir movimiento" la carta
/// aparece ya girada.
class CartaRival extends StatefulWidget {
  const CartaRival({
    super.key,
    required this.alias,
    this.carta,
    this.atributo,
    this.desenlace,
    this.nombreAtributo,
  });

  final String alias;

  /// `null`: boca abajo.
  final Carta? carta;

  /// El atributo con el que se jugó la ronda (`null` si se perdió por tiempo).
  final String? atributo;
  final DesenlaceCarta? desenlace;
  final String Function(String codigo)? nombreAtributo;

  static const duracionGiro = Duration(milliseconds: 350);

  @override
  State<CartaRival> createState() => _CartaRivalState();
}

class _CartaRivalState extends State<CartaRival>
    with SingleTickerProviderStateMixin {
  // 0 = boca abajo, 1 = boca arriba. Si nace ya revelada (al retomar o al
  // volver a la pantalla), no se gira.
  late final _giro = AnimationController(
    vsync: this,
    duration: CartaRival.duracionGiro,
    value: widget.carta == null ? 0 : 1,
  );

  @override
  void didUpdateWidget(CartaRival viejo) {
    super.didUpdateWidget(viejo);
    if (widget.carta == null) {
      _giro.value = 0;
    } else if (viejo.carta == null) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _giro.value = 1;
      } else {
        _giro.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _giro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Un toque salta el giro.
      onTap: _giro.isAnimating ? () => _giro.value = 1 : null,
      child: AnimatedBuilder(
        animation: _giro,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_giro.value);
          final deFrente = t >= 0.5 && widget.carta != null;
          final angulo = deFrente ? (t - 1) * math.pi : t * math.pi;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angulo),
            child: deFrente ? _frente(context) : _reverso(context),
          );
        },
      ),
    );
  }

  Widget _reverso(BuildContext context) {
    final tema = Theme.of(context);
    final papel = EstiloJuego.of(context).sellos;
    return Card.outlined(
      key: const Key('carta-rival-boca-abajo'),
      margin: EdgeInsets.zero,
      child: Semantics(
        container: true,
        label: 'Carta de ${widget.alias}, boca abajo',
        excludeSemantics: true,
        child: SizedBox(
          height: 116,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                papel ? Icons.folder_outlined : Icons.help_outline_rounded,
                size: 40,
                color: tema.colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.alias} · carta boca abajo',
                textAlign: TextAlign.center,
                style: tema.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _frente(BuildContext context) {
    final carta = widget.carta!;
    final atributo = widget.atributo;
    return MarcoCarta(
      key: const Key('carta-rival'),
      etiqueta: widget.alias,
      carta: carta,
      desenlace: widget.desenlace,
      filas: [
        // Del rival solo se enseña el atributo que se jugó.
        if (atributo != null && carta.atributos[atributo] != null)
          FilaAtributo(
            codigo: atributo,
            nombre:
                widget.nombreAtributo?.call(atributo) ??
                Atributos.nombre(atributo),
            valor: carta.atributos[atributo]!,
            desenlace: widget.desenlace,
          ),
      ],
    );
  }
}

/// La carta propia: los 4 atributos con su percentil. En tu turno cada fila
/// es un botón ([onElegir]); al resolverse, se resalta la que se jugó.
class CartaPropia extends StatelessWidget {
  const CartaPropia({
    super.key,
    required this.carta,
    required this.codigos,
    required this.nombreAtributo,
    this.onElegir,
    this.atributoJugado,
    this.desenlace,
  });

  final Carta carta;
  final List<String> codigos;
  final String Function(String codigo) nombreAtributo;
  final ValueChanged<String>? onElegir;
  final String? atributoJugado;
  final DesenlaceCarta? desenlace;

  @override
  Widget build(BuildContext context) {
    final elegir = onElegir;
    return MarcoCarta(
      key: const Key('mi-carta'),
      etiqueta: 'Tu carta',
      carta: carta,
      desenlace: desenlace,
      filas: [
        for (final codigo in codigos)
          if (carta.atributos[codigo] case final valor?)
            FilaAtributo(
              key: Key('atributo-$codigo'),
              codigo: codigo,
              nombre: nombreAtributo(codigo),
              valor: valor,
              desenlace: codigo == atributoJugado ? desenlace : null,
              onTap: elegir == null ? null : () => elegir(codigo),
            ),
      ],
    );
  }
}

/// El marco común de una carta boca arriba: quién es y sus filas. Con
/// desenlace, borde del color del resultado y (en Expediente) un sello.
class MarcoCarta extends StatelessWidget {
  const MarcoCarta({
    super.key,
    required this.etiqueta,
    required this.carta,
    required this.filas,
    this.desenlace,
  });

  final String etiqueta;
  final Carta carta;
  final List<Widget> filas;
  final DesenlaceCarta? desenlace;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = _coloresDesenlace(context, desenlace);
    final sellos = EstiloJuego.of(context).sellos;
    final d = desenlace;
    // Sin sellos (Noche), el resultado también se dice con palabras: el
    // color no puede ser la única pista.
    final cabecera = d == null || sellos
        ? etiqueta.toUpperCase()
        : '${etiqueta.toUpperCase()} · ${_palabra(d)}';
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(sellos ? 4 : 16),
        side: BorderSide(
          color: colores?.borde ?? tema.colorScheme.outlineVariant,
          width: colores == null ? 1 : 2.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: tema.colorScheme.secondaryContainer,
                      foregroundColor: tema.colorScheme.onSecondaryContainer,
                      child: Text(
                        carta.iniciales,
                        style: tema.textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cabecera,
                            style: tema.textTheme.labelSmall?.copyWith(
                              color: tema.colorScheme.onSurfaceVariant,
                              letterSpacing: 0.6,
                            ),
                          ),
                          Text(
                            carta.nombreCompleto,
                            style: tema.textTheme.titleMedium,
                          ),
                          Text(carta.carrera, style: tema.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                if (sellos && d != null && colores != null)
                  // Margen para el giro del sello (como en los casos).
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 4,
                    ),
                    child: Sello(texto: _palabra(d), color: colores.borde),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ...filas,
          ],
        ),
      ),
    );
  }
}

/// Un atributo: icono, nombre, barra del percentil, valor y percentil.
class FilaAtributo extends StatelessWidget {
  const FilaAtributo({
    super.key,
    required this.codigo,
    required this.nombre,
    required this.valor,
    this.desenlace,
    this.onTap,
  });

  final String codigo;
  final String nombre;
  final ValorAtributo valor;
  final DesenlaceCarta? desenlace;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colores = _coloresDesenlace(context, desenlace);
    final texto = colores?.texto ?? tema.colorScheme.onSurface;
    final suave = colores?.texto ?? tema.colorScheme.onSurfaceVariant;
    final eleccion = onTap != null;
    final valorTexto = Atributos.valor(codigo, valor.valor);
    final contenido = Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          Icon(
            Atributos.icono(codigo),
            color: colores?.texto ?? tema.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: TextStyle(color: texto)),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: valor.percentil / 100,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                  color: colores?.barra ?? tema.colorScheme.primary,
                  backgroundColor: tema.colorScheme.surfaceContainerHighest,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                valorTexto,
                style: tema.textTheme.titleMedium?.copyWith(
                  color: texto,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'percentil ${valor.percentil}',
                style: tema.textTheme.bodySmall?.copyWith(color: suave),
              ),
            ],
          ),
          SizedBox(
            width: 28,
            child: eleccion
                ? Icon(Icons.chevron_right, color: tema.colorScheme.primary)
                : null,
          ),
        ],
      ),
    );
    final d = desenlace;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Semantics(
        container: true,
        button: eleccion,
        label:
            '$nombre: $valorTexto, percentil ${valor.percentil}'
            '${d == null ? '' : '. ${_palabra(d).toLowerCase()}'}',
        hint: eleccion ? 'Jugar con $nombre' : null,
        excludeSemantics: true,
        child: Material(
          color: colores?.fondo ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: eleccion
                ? BorderSide(color: tema.colorScheme.outline)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: eleccion ? InkWell(onTap: onTap, child: contenido) : contenido,
        ),
      ),
    );
  }
}
