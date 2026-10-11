import 'package:app_estudiantes/formato.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coma decimal y punto de miles, como en Colombia', () {
    expect(formatoDecimal(3.8, 2), '3,80');
    expect(formatoDecimal(2.45), '2,5');
    expect(formatoDecimal(1250.5, 1), '1.250,5');
    expect(formatoDecimal(-0.04), '0,0');
    expect(formatoDecimal(-1.25, 2), '-1,25');
    expect(formatoEntero(1234567.4), '1.234.567');
    expect(formatoEntero(12), '12');
    expect(formatoPromedio(3.8), '3,80');
  });

  test('el % va tras un espacio no separable', () {
    expect(formatoPorcentaje(33.333, 1), '33,3 %');
    expect(formatoPorcentaje(92), '92 %');
    expect(formatoProbabilidad(0.49), '49 %');
    expect(formatoProbabilidad(0.4925, 1), '49,3 %');
  });
}
