import 'package:flutter_test/flutter_test.dart';
import 'package:uninorte_extensiones/core/theme.dart';

void main() {
  test('el tema usa la paleta institucional', () {
    final tema = UniNorteTheme.lightTheme;
    expect(tema.colorScheme.primary, UniNorteColors.azulMarino);
    expect(tema.colorScheme.secondary, UniNorteColors.dorado);
  });
}