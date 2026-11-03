import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/validation/validators.dart';

void main() {
  group('normalize', () {
    test('quita espacios al inicio y al final', () {
      expect(Validators.normalize('  hola  '), 'hola');
      expect(Validators.normalize(null), '');
      expect(Validators.normalize('   '), '');
    });
  });

  group('required', () {
    final validate = Validators.required('El título');

    test('rechaza vacío, nulo y solo espacios', () {
      expect(validate(null), 'El título es obligatorio.');
      expect(validate(''), 'El título es obligatorio.');
      expect(validate('   '), 'El título es obligatorio.');
    });

    test('acepta texto', () => expect(validate('Ruido'), isNull));
  });

  group('longitud', () {
    test('maxLength cuenta el texto ya recortado', () {
      final validate = Validators.maxLength(5, 'El código');
      expect(validate('12345'), isNull);
      expect(validate('  12345  '), isNull);
      expect(validate('123456'), 'El código no puede superar los 5 caracteres.');
    });

    test('minLength ignora el vacío (lo cubre required)', () {
      final validate = Validators.minLength(3, 'El título');
      expect(validate(''), isNull);
      expect(validate('ab'), 'El título debe tener al menos 3 caracteres.');
      expect(validate('abc'), isNull);
    });
  });

  group('números sin negativos', () {
    final decimal = Validators.nonNegativeNumber('El costo');
    final entero = Validators.nonNegativeInteger('La cantidad');

    test('decimal acepta coma y punto', () {
      expect(decimal('12,50'), isNull);
      expect(decimal('12.50'), isNull);
      expect(decimal('0'), isNull);
    });

    test('decimal rechaza negativos y texto', () {
      expect(decimal('-1'), 'El costo no puede ser negativo.');
      expect(decimal('abc'), 'El costo debe ser un número.');
      expect(decimal('NaN'), 'El costo debe ser un número.');
      expect(decimal('Infinity'), 'El costo debe ser un número.');
    });

    test('vacío es válido: lo decide required', () {
      expect(decimal(''), isNull);
      expect(entero(null), isNull);
    });

    test('entero rechaza decimales y negativos', () {
      expect(entero('3'), isNull);
      expect(entero('3.5'), 'La cantidad debe ser un número entero.');
      expect(entero('-2'), 'La cantidad no puede ser negativo.');
    });
  });

  group('all', () {
    test('devuelve el primer error y respeta el orden', () {
      final validate = Validators.all([Validators.required('El título'), Validators.minLength(5, 'El título')]);
      expect(validate(''), 'El título es obligatorio.');
      expect(validate('abc'), 'El título debe tener al menos 5 caracteres.');
      expect(validate('abcde'), isNull);
    });
  });

  group('fechas', () {
    final jan = DateTime(2026, 1, 10);
    final feb = DateTime(2026, 2, 10);

    test('el rango debe ser coherente', () {
      expect(Validators.dateRange(jan, feb), isNull);
      expect(Validators.dateRange(jan, jan), isNull);
      expect(Validators.dateRange(feb, jan), 'La fecha final no puede ser anterior a la inicial.');
    });

    test('si falta una fecha no hay nada que comparar', () {
      expect(Validators.dateRange(null, jan), isNull);
      expect(Validators.dateRange(jan, null), isNull);
    });

    test('no admite fechas futuras', () {
      final now = DateTime(2026, 6, 1);
      expect(Validators.notInFuture(DateTime(2026, 5, 31), now: now), isNull);
      expect(Validators.notInFuture(DateTime(2026, 6, 2), now: now, field: 'La compra'), 'La compra no puede estar en el futuro.');
      expect(Validators.notInFuture(null, now: now), isNull);
    });
  });

  group('adjuntos', () {
    String? check(String name, int size) => Validators.attachment(
          fileName: name,
          sizeBytes: size,
          allowedExtensions: {'jpg', 'png', 'pdf'},
          maxBytes: 10 * 1024 * 1024,
        );

    test('acepta extensión permitida sin importar mayúsculas', () {
      expect(check('foto.JPG', 1024), isNull);
      expect(check('informe.pdf', 5 * 1024 * 1024), isNull);
    });

    test('rechaza extensión no permitida o ausente', () {
      expect(check('virus.exe', 1024), 'Tipo de archivo no permitido. Usa: jpg, pdf, png.');
      expect(check('sinextension', 1024), contains('Tipo de archivo no permitido'));
    });

    test('rechaza vacío y demasiado grande', () {
      expect(check('a.png', 0), 'El archivo está vacío.');
      expect(check('a.png', 10 * 1024 * 1024 + 1), 'El archivo supera el máximo de 10 MB.');
      expect(check('a.png', 10 * 1024 * 1024), isNull);
    });
  });
}
