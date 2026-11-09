import 'package:flutter/material.dart';

import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Error del rango [from]–[to], o `null` si es válido. Cada extremo es opcional, pero si están
/// los dos, «desde» no puede ser posterior a «hasta». Ninguno puede ser futuro.
String? validateDateRange(DateTime? from, DateTime? to, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final limit = DateTime(now.year, now.month, now.day);
  if (from == null && to == null) return 'Elige al menos una fecha.';
  if ((from != null && from.isAfter(limit)) || (to != null && to.isAfter(limit))) return 'Las fechas no pueden ser futuras.';
  if (from != null && to != null && from.isAfter(to)) return 'La fecha «Desde» no puede ser posterior a «Hasta».';
  return null;
}

/// Diálogo pequeño con dos fechas (desde y hasta), cada una con el calendario del sistema.
/// Devuelve el rango (`start` y `end` a las 00:00; un extremo vacío se completa con el otro) o
/// `null` si se cancela.
Future<DateTimeRange?> showDateRangeDialog(BuildContext context, {DateTimeRange? initial}) =>
    showDialog<DateTimeRange>(context: context, builder: (_) => _DateRangeDialog(initial: initial));

class _DateRangeDialog extends StatefulWidget {
  const _DateRangeDialog({required this.initial});
  final DateTimeRange? initial;

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  late DateTime? _from = widget.initial?.start;
  late DateTime? _to = widget.initial?.end;
  String? _error;

  Future<DateTime?> _pick(DateTime? current, String help) {
    final today = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? DateTime(today.year, today.month, today.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: help,
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
  }

  Future<void> _pickFrom() async {
    final picked = await _pick(_from, 'Desde');
    if (picked != null) setState(() { _from = picked; _error = null; });
  }

  Future<void> _pickTo() async {
    final picked = await _pick(_to, 'Hasta');
    if (picked != null) setState(() { _to = picked; _error = null; });
  }

  void _apply() {
    final error = validateDateRange(_from, _to);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final start = _from ?? _to!;
    final end = _to ?? _from!;
    Navigator.pop(context, DateTimeRange(start: start, end: end));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rango de fechas'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _DateTile(label: 'Desde', value: _from, onTap: _pickFrom),
            const SizedBox(height: AppSpacing.sm),
            _DateTile(label: 'Hasta', value: _to, onTap: _pickTo),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _apply, child: const Text('Aplicar')),
        ],
      );
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$label: ${value == null ? 'sin elegir' : formatDate(value!)}',
        excludeSemantics: true,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
          child: Row(children: [
            const Icon(Icons.calendar_month_rounded, size: 20, color: AppColors.steel),
            const SizedBox(width: AppSpacing.sm),
            Text('$label: ', style: const TextStyle(color: AppColors.slate)),
            Expanded(child: Text(value == null ? 'Elegir' : formatDate(value!), overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700))),
          ]),
        ),
      );
}
