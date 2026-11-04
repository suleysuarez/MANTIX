import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/format/formatters.dart';

void main() {
  test('formatDate y formatDateTime usan meses en español', () {
    final date = DateTime(2026, 11, 3, 9, 5);
    expect(formatDate(date), '3 nov 2026');
    expect(formatDateTime(date), '3 nov 2026, 09:05');
    expect(formatDate(DateTime(2026, 1, 31)), '31 ene 2026');
    expect(formatDate(DateTime(2026, 12, 1)), '1 dic 2026');
  });

  test('formatFileSize elige la unidad', () {
    expect(formatFileSize(0), '0 B');
    expect(formatFileSize(1023), '1023 B');
    expect(formatFileSize(2048), '2 KB');
    expect(formatFileSize(1572864), '1,5 MB');
  });
}
