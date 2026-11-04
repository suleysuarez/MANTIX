/// Validación en el cliente. El backend es la fuente de verdad y sus 422 se muestran
/// bajo cada campo; esto solo evita viajes inútiles y da respuesta inmediata.
typedef Validator = String? Function(String? value);

abstract final class Validators {
  /// Quita espacios al inicio y al final. Todo texto se normaliza antes de enviarlo.
  static String normalize(String? value) => (value ?? '').trim();

  /// [feminine] concuerda el mensaje con un campo femenino («La descripción es obligatoria.»).
  static Validator required([String field = 'Este campo', bool feminine = false]) =>
      (value) => normalize(value).isEmpty ? '$field es obligatori${feminine ? 'a' : 'o'}.' : null;

  static Validator minLength(int min, [String field = 'Este campo']) => (value) {
        final text = normalize(value);
        if (text.isEmpty) return null; // lo cubre `required`
        return text.length < min ? '$field debe tener al menos $min caracteres.' : null;
      };

  static Validator maxLength(int max, [String field = 'Este campo']) =>
      (value) => normalize(value).length > max ? '$field no puede superar los $max caracteres.' : null;

  /// Número decimal sin negativos. Acepta coma o punto como separador.
  static Validator nonNegativeNumber([String field = 'Este campo']) => (value) {
        final text = normalize(value);
        if (text.isEmpty) return null;
        final number = double.tryParse(text.replaceAll(',', '.'));
        if (number == null || number.isNaN || number.isInfinite) return '$field debe ser un número.';
        return number < 0 ? '$field no puede ser negativo.' : null;
      };

  /// Entero sin negativos (por ejemplo, cantidades de inventario).
  static Validator nonNegativeInteger([String field = 'Este campo']) => (value) {
        final text = normalize(value);
        if (text.isEmpty) return null;
        final number = int.tryParse(text);
        if (number == null) return '$field debe ser un número entero.';
        return number < 0 ? '$field no puede ser negativo.' : null;
      };

  /// Aplica los validadores en orden y devuelve el primer error.
  static Validator all(List<Validator> validators) => (value) {
        for (final validator in validators) {
          final error = validator(value);
          if (error != null) return error;
        }
        return null;
      };

  /// Fechas coherentes: la final no puede ser anterior a la inicial.
  /// Si falta alguna de las dos no hay nada que comparar.
  static String? dateRange(DateTime? from, DateTime? to) {
    if (from == null || to == null) return null;
    return to.isBefore(from) ? 'La fecha final no puede ser anterior a la inicial.' : null;
  }

  /// La fecha no puede estar en el futuro (por ejemplo, la compra de un equipo).
  static String? notInFuture(DateTime? date, {DateTime? now, String field = 'La fecha'}) {
    if (date == null) return null;
    return date.isAfter(now ?? DateTime.now()) ? '$field no puede estar en el futuro.' : null;
  }

  /// Archivo adjunto: extensión permitida y tamaño máximo.
  static String? attachment({
    required String fileName,
    required int sizeBytes,
    required Set<String> allowedExtensions,
    required int maxBytes,
  }) {
    final dot = fileName.lastIndexOf('.');
    final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    if (!allowedExtensions.map((e) => e.toLowerCase()).contains(extension)) {
      final list = (allowedExtensions.toList()..sort()).join(', ');
      return 'Tipo de archivo no permitido. Usa: $list.';
    }
    if (sizeBytes <= 0) return 'El archivo está vacío.';
    if (sizeBytes > maxBytes) {
      final mb = (maxBytes / (1024 * 1024)).toStringAsFixed(maxBytes % (1024 * 1024) == 0 ? 0 : 1);
      return 'El archivo supera el máximo de $mb MB.';
    }
    return null;
  }
}
