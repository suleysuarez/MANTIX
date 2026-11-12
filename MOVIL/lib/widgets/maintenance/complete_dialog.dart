import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format/maintenance_format.dart';
import '../../core/theme/app_colors.dart';

/// Pide las horas reales de un servicio antes de marcarlo como hecho. Las horas son opcionales:
/// vacías valen. Devuelve el texto escrito (puede ser vacío) o `null` si se cancela.
Future<String?> showCompleteDialog(BuildContext context, {required String title}) => showDialog<String>(
      context: context,
      builder: (_) => _CompleteDialog(title: title),
    );

class _CompleteDialog extends StatefulWidget {
  const _CompleteDialog({required this.title});

  final String title;

  @override
  State<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends State<_CompleteDialog> {
  final _hours = TextEditingController();
  bool _touched = false;

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = hoursError(_hours.text);
    return AlertDialog(
      title: const Text('¿Marcar como hecho?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Se registrará el servicio «${widget.title}» y la próxima fecha avanzará un intervalo del plan.'),
          const SizedBox(height: 16),
          TextField(
            controller: _hours,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [LengthLimitingTextInputFormatter(7)],
            onChanged: (_) => setState(() => _touched = true),
            decoration: InputDecoration(labelText: 'Horas reales (opcional)', hintText: 'Ej. 1,5', prefixIcon: const Icon(Icons.timer_outlined, color: AppColors.navy), errorText: _touched ? error : null, errorMaxLines: 2),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: error == null ? () => Navigator.of(context).pop(_hours.text) : null, child: const Text('Marcar como hecho')),
      ],
    );
  }
}
