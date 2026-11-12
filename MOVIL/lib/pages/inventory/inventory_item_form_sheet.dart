import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/inventory/inventory_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../models/inventory/inventory_models.dart';

class InventoryItemFormSheet extends StatefulWidget {
  const InventoryItemFormSheet({super.key});
  @override
  State<InventoryItemFormSheet> createState() => _InventoryItemFormSheetState();
}

class _InventoryItemFormSheetState extends State<InventoryItemFormSheet> {
  final _form = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _cost = TextEditingController(text: '0.00');
  final _initial = TextEditingController(text: '0');
  final _minimum = TextEditingController(text: '0');
  final _maximum = TextEditingController();
  final _location = TextEditingController();
  final _supplier = TextEditingController();
  String _category = 'spare_part';
  String _unit = 'unidad';

  @override
  void dispose() {
    for (final c in [_sku, _name, _description, _cost, _initial, _minimum, _maximum, _location, _supplier]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final min = int.parse(_minimum.text);
    final maxText = _maximum.text.trim();
    final max = maxText.isEmpty ? null : int.parse(maxText);
    if (max != null && max < min) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El stock máximo no puede ser menor que el mínimo.')));
      return;
    }
    context.read<InventoryBloc>().add(InventoryItemCreateRequested({
      'sku': _sku.text.trim().toUpperCase(),
      'name': _name.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'category': _category,
      'unit': _unit,
      'unit_cost': double.tryParse(_cost.text.replaceAll(',', '.')) ?? 0,
      'initial_stock': int.tryParse(_initial.text) ?? 0,
      'min_stock': min,
      'max_stock': max,
      'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
      'supplier': _supplier.text.trim().isEmpty ? null : _supplier.text.trim(),
    }));
  }

  @override
  Widget build(BuildContext context) => BlocListener<InventoryBloc, InventoryState>(
    listenWhen: (a, b) => a.createdItem != b.createdItem || (a.failure != b.failure && b.failure != null),
    listener: (context, state) {
      if (state.createdItem != null) Navigator.of(context).pop();
      if (state.failure != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.failure!.message)));
    },
    child: BlocBuilder<InventoryBloc, InventoryState>(builder: (context, state) {
      final categoryOptions = state.options.where((o) => o.kind == 'category').toList();
      final unitOptions = state.options.where((o) => o.kind == 'unit').toList();
      final categories = categoryOptions.isEmpty
          ? const [DropdownMenuItem(value: 'spare_part', child: Text('Repuesto')), DropdownMenuItem(value: 'consumable', child: Text('Consumible')), DropdownMenuItem(value: 'accessory', child: Text('Accesorio')), DropdownMenuItem(value: 'tool', child: Text('Herramienta')), DropdownMenuItem(value: 'other', child: Text('Otro'))]
          : [for (final option in categoryOptions) DropdownMenuItem(value: option.value, child: Text(option.label))];
      final units = unitOptions.isEmpty
          ? const [DropdownMenuItem(value: 'unidad', child: Text('Unidad')), DropdownMenuItem(value: 'metro', child: Text('Metro')), DropdownMenuItem(value: 'litro', child: Text('Litro')), DropdownMenuItem(value: 'paquete', child: Text('Paquete')), DropdownMenuItem(value: 'caja', child: Text('Caja'))]
          : [for (final option in unitOptions) DropdownMenuItem(value: option.value, child: Text(option.label))];
      if (!categories.any((item) => item.value == _category)) _category = categories.first.value!;
      if (!units.any((item) => item.value == _unit)) _unit = units.first.value!;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.viewInsetsOf(context).bottom + 14),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: Column(children: [
            Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .55), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.inventory_2_outlined, color: AppColors.steel)),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nuevo ítem', style: TextStyle(color: AppColors.navy, fontSize: 19, fontWeight: FontWeight.w900)),
                Text('Registra un insumo y define sus existencias.', style: TextStyle(color: AppColors.slate, fontSize: 11.5)),
              ])),
              IconButton(tooltip: 'Cerrar', onPressed: state.saving ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: AppColors.steel)),
            ]),
            const SizedBox(height: 12),
            Expanded(child: Form(key: _form, child: ListView(children: [
              _field('Código (SKU) *', _sku, validator: _skuValidator, hint: 'Ej. CAB-USB-01'),
              const SizedBox(height: 10),
              _dropdown('Categoría *', _category, categories, (value) => setState(() => _category = value!)),
              const SizedBox(height: 10),
              _field('Nombre *', _name, validator: (value) => value == null || value.trim().length < 3 ? 'Escribe al menos 3 caracteres.' : null),
              const SizedBox(height: 10),
              _field('Descripción', _description, required: false, maxLines: 2),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _dropdown('Unidad *', _unit, units, (value) => setState(() => _unit = value!))),
                const SizedBox(width: 10),
                Expanded(child: _field('Costo unitario', _cost, keyboard: const TextInputType.numberWithOptions(decimal: true), validator: _moneyValidator)),
              ]),
              const SizedBox(height: 14),
              _section('CONTROL DE EXISTENCIAS'),
              Row(children: [
                Expanded(child: _field('Stock inicial', _initial, keyboard: TextInputType.number, validator: _integerValidator)),
                const SizedBox(width: 10),
                Expanded(child: _field('Stock mínimo *', _minimum, keyboard: TextInputType.number, validator: (value) => value == null || value.trim().isEmpty ? 'Este campo es obligatorio.' : _integerValidator(value))),
              ]),
              const SizedBox(height: 10),
              _field('Stock máximo', _maximum, required: false, keyboard: TextInputType.number, validator: _integerValidator),
              const SizedBox(height: 14),
              _section('UBICACIÓN Y PROVEEDOR'),
              _field('Ubicación', _location, required: false, hint: 'Ej. Almacén principal'),
              const SizedBox(height: 10),
              _field('Proveedor', _supplier, required: false, hint: 'Nombre del proveedor'),
              const SizedBox(height: 8),
            ]))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: state.saving ? null : () => Navigator.pop(context), child: const Text('Cancelar'))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton.icon(
                onPressed: state.saving ? null : _submit,
                icon: state.saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy)) : const Icon(Icons.add_rounded, size: 18),
                label: Text(state.saving ? 'Guardando…' : 'Crear ítem'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy),
              )),
            ]),
          ]),
        ),
      );
    }),
  );

  Widget _section(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(width: 4, height: 15, decoration: BoxDecoration(color: AppColors.mustard, borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 7),
      Text(value, style: const TextStyle(color: AppColors.steel, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: .5)),
    ]),
  );

  Widget _field(String label, TextEditingController controller, {String? Function(String?)? validator, bool required = true, int maxLines = 1, TextInputType? keyboard, String? hint}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.w800)),
    const SizedBox(height: 5),
    TextFormField(controller: controller, maxLines: maxLines, keyboardType: keyboard,
      decoration: InputDecoration(hintText: hint, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
      validator: validator ?? (required ? (value) => value == null || value.trim().isEmpty ? 'Este campo es obligatorio.' : null : null)),
  ]);

  Widget _dropdown(String label, String value, List<DropdownMenuItem<String>> items, ValueChanged<String?> onChanged) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.w800)),
    const SizedBox(height: 5),
    DropdownButtonFormField<String>(initialValue: value, isExpanded: true, decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)), items: items, onChanged: onChanged),
  ]);

  String? _skuValidator(String? value) {
    final text = value?.trim().toUpperCase() ?? '';
    if (text.length < 3 || text.length > 40 || !RegExp(r'^[A-Z0-9][A-Z0-9._-]*$').hasMatch(text)) return 'Usa 3–40 letras, números, punto, guion o guion bajo.';
    return null;
  }

  String? _integerValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final number = int.tryParse(value);
    return number == null || number < 0 || number > 1000000 ? 'Ingresa un entero entre 0 y 1.000.000.' : null;
  }

  String? _moneyValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final number = double.tryParse(value.replaceAll(',', '.'));
    return number == null || number < 0 || number > 1000000 ? 'Ingresa un costo válido.' : null;
  }
}

class InventoryMovementSheet extends StatefulWidget {
  const InventoryMovementSheet({super.key, required this.item, required this.kind});
  final InventoryItem item;
  final String kind;
  @override
  State<InventoryMovementSheet> createState() => _InventoryMovementSheetState();
}

class _InventoryMovementSheetState extends State<InventoryMovementSheet> {
  final _form = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _notes = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() { _quantity.dispose(); _notes.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => BlocListener<InventoryBloc, InventoryState>(
    listenWhen: (a, b) => _submitted && a.saving && !b.saving,
    listener: (context, state) {
      if (state.failure == null) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.failure!.message)));
      }
    },
    child: Padding(
      padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
      child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.kind == 'out' ? 'Registrar consumo' : 'Registrar entrada', style: const TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('${widget.item.name} · Stock actual: ${widget.item.stock} ${widget.item.unit}', style: const TextStyle(color: AppColors.slate, fontSize: 12)),
        const SizedBox(height: 14),
        TextFormField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad'), validator: (value) {
          final amount = int.tryParse(value ?? '');
          if (amount == null || amount <= 0) return 'Ingresa una cantidad mayor que cero.';
          if (widget.kind == 'out' && amount > widget.item.stock) return 'No puedes consumir más de lo disponible.';
          return null;
        }),
        const SizedBox(height: 10),
        TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
        const SizedBox(height: 16),
        BlocBuilder<InventoryBloc, InventoryState>(builder: (context, state) => FilledButton(
          onPressed: state.saving ? null : () {
            if (!_form.currentState!.validate()) return;
            setState(() => _submitted = true);
            context.read<InventoryBloc>().add(InventoryMovementRequested(itemId: widget.item.id, kind: widget.kind, quantity: int.parse(_quantity.text), notes: _notes.text));
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy),
          child: Text(state.saving ? 'Guardando…' : widget.kind == 'out' ? 'Registrar consumo' : 'Registrar entrada'),
        )),
      ])),
    ),
  );
}
