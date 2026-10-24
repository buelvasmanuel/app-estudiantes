import 'package:flutter/material.dart';

/// Título de una barra superior que, si no cabe (360 px con «Actualizar», el
/// chip de nivel y el avatar, o la letra ancha de Expediente), se reduce un
/// poco en vez de cortarse («Laborator…»).
class TituloBarra extends StatelessWidget {
  const TituloBarra(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: Text(texto, maxLines: 1),
  );
}
