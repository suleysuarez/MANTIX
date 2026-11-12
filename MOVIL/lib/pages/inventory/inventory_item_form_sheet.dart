import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/inventory/inventory_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../models/inventory/inventory_models.dart';

/// Valor interno del selector que abre un campo para escribir un valor que aún no está en la lista.
const _otherValue = '__other__';

/// Formulario de un ítem: crea uno nuevo o, si recibe [item], edita el existente.
///
/// Al editar, el SKU no cambia y el stock tampoco (se mueve con entradas y consumos).
class InventoryItemFormSheet extends StatefulWidget {
  const InventoryItemFormSheet({super.key, this.item});
  final InventoryItem? item;
  @override
  State<InventoryItemFormSheet> createState() => _InventoryItemFormSheetState();
}

class _InventoryItemFormSheetState extends State<InventoryItemFormSheet> {
  final _form = GlobalKey<FormState>();
  late final _sku = TextEditingController(text: widget.item?.sku);
  late final _name = TextEditingController(text: widget.item?.name);
  late final _description = TextEditingController(text: widget.item?.description);
  late final _cost = TextEditingController(text: widget.item?.unitCost ?? '0.00');
  final _initial = TextEditingController(text: '0');
  late final _minimum = TextEditingController(text: '${widget.item?.minStock ?? 0}');
  late final _maximum = TextEditingController(text: widget.item?.maxStock?.toString() ?? '');
  final _locationText = TextEditingController();
  final _supplierText = TextEditingController();
  late String _category = widget.item?.category ?? 'spare_part';
  late String _unit = widget.item?.unit ?? 'unidad';
  late String? _location = widget.item?.location;
  late String? _supplier = widget.item?.supplier;

  bool get _editing => widget.item != null;

  @override
  void dispose() {
    for (final c in [_sku, _name, _description, _cost, _initial, _minimum, _maximum, _locationText, _supplierText]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _catalogValue(String? choice, TextEditingController other) {
    final text = choice == _otherValue ? other.text.trim() : choice;
    return text == null || text.isEmpty ? null : text;
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
    final fields = <String, Object?>{
      'name': _name.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'category': _category,
      'unit': _unit,
      'unit_cost': double.tryParse(_cost.text.replaceAll(',', '.')) ?? 0,
      'min_stock': min,
      'max_stock': max,
      'location': _catalogValue(_location, _locationText),
      'supplier': _catalogValue(_supplier, _supplierText),
    };
    final bloc = context.read<InventoryBloc>();
    if (_editing) {
      bloc.add(InventoryItemUpdateRequested(widget.item!.id, fields));
    } else {
      bloc.add(InventoryItemCreateRequested({
        'sku': _sku.text.trim().toUpperCase(),
        'initial_stock': int.tryParse(_initial.text) ?? 0,
        ...fields,
      }));
    }
  }

  @override
  Widget build(BuildContext context) => BlocListener<InventoryBloc, InventoryState>(
    listenWhen: (a, b) => a.savedItem != b.savedItem || (a.failure != b.failure && b.failure != null),
    listener: (context, state) {
      if (state.savedItem != null) Navigator.of(context).pop();
      if (state.failure != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.failure!.message)));
    },
    child: BlocBuilder<InventoryBloc, InventoryState>(builder: (context, state) {
      List<DropdownMenuItem<String>> items(String kind, List<DropdownMenuItem<String>> fallback, {String? current}) {
        final options = state.options.where((o) => o.kind == kind).toList();
        final list = options.isEmpty ? fallback : [for (final option in options) DropdownMenuItem(value: option.value, child: Text(option.label))];
        // Un valor que el ítem ya tiene y que no está en la lista (por ejemplo, uno antiguo) no se pierde.
        if (current != null && !list.any((item) => item.value == current)) return [DropdownMenuItem(value: current, child: Text(current)), ...list];
        return list;
      }

      final categories = items('category', const [DropdownMenuItem(value: 'spare_part', child: Text('Repuesto')), DropdownMenuItem(value: 'consumable', child: Text('Consumible')), DropdownMenuItem(value: 'accessory', child: Text('Accesorio')), DropdownMenuItem(value: 'tool', child: Text('Herramienta')), DropdownMenuItem(value: 'other', child: Text('Otro'))], current: _category);
      final units = items('unit', const [DropdownMenuItem(value: 'unidad', child: Text('Unidad')), DropdownMenuItem(value: 'metro', child: Text('Metro')), DropdownMenuItem(value: 'litro', child: Text('Litro')), DropdownMenuItem(value: 'paquete', child: Text('Paquete')), DropdownMenuItem(value: 'caja', child: Text('Caja'))], current: _unit);
      final locations = items('location', const [], current: _location == _otherValue ? null : _location);
      final suppliers = items('supplier', const [], current: _supplier == _otherValue ? null : _supplier);
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.viewInsetsOf(context).bottom + 14),
        child: Column(children: [
            Row(children: [
              Container(width: 4, height: 38, decoration: BoxDecoration(color: AppColors.mustard, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_editing ? 'Editar ítem' : 'Nuevo ítem', style: const TextStyle(color: AppColors.navy, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
                Text(_editing ? 'Actualiza los datos del insumo' : 'Agrega un nuevo insumo al inventario', style: const TextStyle(color: AppColors.slate, fontSize: 11.5)),
              ])),
              IconButton(tooltip: 'Cerrar', onPressed: state.saving ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: AppColors.steel)),
            ]),
            const SizedBox(height: 10),
            Expanded(child: Form(key: _form, child: ListView(children: [
              _field('Código (SKU) *', _sku, Icons.tag_rounded, validator: _editing ? null : _skuValidator, hint: 'Ej. CAB-USB-01', enabled: !_editing),
              _dropdown('Categoría *', _category, categories, Icons.grid_view_rounded, (value) => setState(() => _category = value!)),
              _field('Nombre *', _name, Icons.label_outline_rounded, validator: (value) => value == null || value.trim().length < 3 ? 'Escribe al menos 3 caracteres.' : null, hint: 'Nombre del ítem'),
              _field('Descripción', _description, Icons.notes_rounded, required: false, maxLines: 2, hint: 'Describe el ítem (opcional)'),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _dropdown('Unidad *', _unit, units, Icons.inventory_2_outlined, (value) => setState(() => _unit = value!))),
                const SizedBox(width: 10),
                Expanded(child: _field('Costo unitario', _cost, Icons.payments_outlined, keyboard: const TextInputType.numberWithOptions(decimal: true), validator: _moneyValidator)),
              ]),
              if (!_editing) _field('Stock inicial', _initial, Icons.add_box_outlined, keyboard: TextInputType.number, validator: _integerValidator),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _field('Stock mínimo *', _minimum, Icons.warning_amber_rounded, keyboard: TextInputType.number, validator: (value) => value == null || value.trim().isEmpty ? 'Obligatorio.' : _integerValidator(value))),
                const SizedBox(width: 10),
                Expanded(child: _field('Stock máximo', _maximum, Icons.bar_chart_rounded, required: false, keyboard: TextInputType.number, validator: _integerValidator)),
              ]),
              _catalog('Ubicación', Icons.place_outlined, 'Sin ubicación', _location, locations, _locationText, 'Escribe la ubicación', (value) => setState(() => _location = value)),
              _catalog('Proveedor', Icons.local_shipping_outlined, 'Sin proveedor', _supplier, suppliers, _supplierText, 'Escribe el proveedor', (value) => setState(() => _supplier = value)),
              if (_editing) const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('El stock no se edita aquí: usa «Registrar entrada» o «Registrar consumo».', style: TextStyle(color: AppColors.slate, fontSize: 11)),
              ),
            ]))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: state.saving ? null : () => Navigator.pop(context), child: const Text('Cancelar'))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton.icon(
                onPressed: state.saving ? null : _submit,
                icon: state.saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy)) : const Icon(Icons.save_outlined, size: 18),
                label: Text(state.saving ? 'Guardando…' : _editing ? 'Guardar cambios' : 'Crear ítem'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy),
              )),
            ]),
        ]),
      );
    }),
  );

  InputDecoration _decoration(String label, IconData icon, {String? hint}) => InputDecoration(
    labelText: label, hintText: hint, isDense: true,
    prefixIcon: Icon(icon, size: 19, color: AppColors.steel),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  Widget _field(String label, TextEditingController controller, IconData icon, {String? Function(String?)? validator, bool required = true, int maxLines = 1, TextInputType? keyboard, String? hint, bool enabled = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(controller: controller, maxLines: maxLines, keyboardType: keyboard, enabled: enabled,
      decoration: _decoration(label, icon, hint: hint),
      validator: validator ?? (required && enabled ? (value) => value == null || value.trim().isEmpty ? 'Este campo es obligatorio.' : null : null)),
  );

  Widget _dropdown(String label, String value, List<DropdownMenuItem<String>> items, IconData icon, ValueChanged<String?> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<String>(initialValue: value, isExpanded: true, decoration: _decoration(label, icon), items: items, onChanged: onChanged),
  );

  /// Selector de un catálogo (ubicación, proveedor): se elige uno existente, ninguno o «Otro…» para escribirlo.
  Widget _catalog(String label, IconData icon, String none, String? value, List<DropdownMenuItem<String>> items, TextEditingController other, String otherHint, ValueChanged<String?> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(children: [
      DropdownButtonFormField<String?>(
        initialValue: value, isExpanded: true, decoration: _decoration(label, icon),
        items: [
          DropdownMenuItem<String?>(value: null, child: Text(none)),
          ...items,
          const DropdownMenuItem<String?>(value: _otherValue, child: Text('Otro…')),
        ],
        onChanged: onChanged,
      ),
      if (value == _otherValue) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextFormField(controller: other, decoration: _decoration(otherHint, Icons.edit_outlined), validator: (text) => text == null || text.trim().isEmpty ? 'Escribe un valor o elige uno de la lista.' : null),
      ),
    ]),
  );

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

/// Entrada o consumo de stock de un ítem, con selector de cantidad y vista previa del resultado.
class InventoryMovementSheet extends StatefulWidget {
  const InventoryMovementSheet({super.key, required this.item, required this.kind});
  final InventoryItem item;

  /// `in` (entrada) o `out` (consumo).
  final String kind;
  @override
  State<InventoryMovementSheet> createState() => _InventoryMovementSheetState();
}

class _InventoryMovementSheetState extends State<InventoryMovementSheet> {
  final _form = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '1');
  final _notes = TextEditingController();
  bool _submitted = false;

  bool get _out => widget.kind == 'out';

  @override
  void dispose() { _quantity.dispose(); _notes.dispose(); super.dispose(); }

  int get _amount => int.tryParse(_quantity.text) ?? 0;

  void _step(int delta) {
    final upper = _out ? widget.item.stock.clamp(1, 1000000) : 1000000;
    final next = (_amount + delta).clamp(1, upper);
    _quantity.text = '$next';
    _quantity.selection = TextSelection.collapsed(offset: _quantity.text.length);
  }

  String? _validate(String? value) {
    final amount = int.tryParse(value ?? '');
    if (amount == null || amount <= 0) return 'Ingresa una cantidad mayor que cero.';
    if (_out && amount > widget.item.stock) return 'Solo hay ${widget.item.stock} ${widget.item.unit} disponibles.';
    if (amount > 1000000) return 'La cantidad máxima es 1.000.000.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return BlocListener<InventoryBloc, InventoryState>(
      listenWhen: (a, b) => _submitted && a.saving && !b.saving,
      listener: (context, state) {
        if (state.failure == null) {
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.failure!.message)));
        }
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
        child: SingleChildScrollView(
          child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: (_out ? AppColors.navy : AppColors.mustard).withValues(alpha: _out ? .1 : .3), borderRadius: BorderRadius.circular(14)),
                child: Icon(_out ? Icons.north_west_rounded : Icons.south_east_rounded, color: AppColors.navy),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_out ? 'Registrar consumo' : 'Registrar entrada', style: const TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w900, height: 1.1)),
                Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 12)),
              ])),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .3), borderRadius: BorderRadius.circular(13)),
              child: Row(children: [
                const Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.steel),
                const SizedBox(width: 8),
                const Expanded(child: Text('Stock actual', style: TextStyle(color: AppColors.steel, fontSize: 12, fontWeight: FontWeight.w700))),
                Text('${item.stock} ${item.unit}', style: const TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w900)),
              ]),
            ),
            const SizedBox(height: 16),
            const Text('Cantidad', style: TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton.filledTonal(tooltip: 'Restar uno', onPressed: () => setState(() => _step(-1)), icon: const Icon(Icons.remove_rounded)),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(
                controller: _quantity, keyboardType: TextInputType.number, textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.navy, fontSize: 24, fontWeight: FontWeight.w900),
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)),
                validator: _validate,
                onChanged: (_) => setState(() {}),
              )),
              const SizedBox(width: 10),
              IconButton.filledTonal(tooltip: 'Sumar uno', onPressed: () => setState(() => _step(1)), icon: const Icon(Icons.add_rounded)),
            ]),
            const SizedBox(height: 8),
            _Preview(out: _out, current: item.stock, amount: _amount, unit: item.unit),
            const SizedBox(height: 12),
            TextFormField(controller: _notes, maxLines: 2, maxLength: 300, decoration: const InputDecoration(labelText: 'Nota (opcional)', prefixIcon: Icon(Icons.notes_rounded, size: 19, color: AppColors.steel))),
            const SizedBox(height: 8),
            BlocBuilder<InventoryBloc, InventoryState>(builder: (context, state) => Row(children: [
              Expanded(child: OutlinedButton(onPressed: state.saving ? null : () => Navigator.pop(context), child: const Text('Cancelar'))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton(
                onPressed: state.saving ? null : () {
                  if (!_form.currentState!.validate()) return;
                  setState(() => _submitted = true);
                  context.read<InventoryBloc>().add(InventoryMovementRequested(itemId: item.id, kind: widget.kind, quantity: _amount, notes: _notes.text));
                },
                style: FilledButton.styleFrom(backgroundColor: _out ? AppColors.navy : AppColors.mustard, foregroundColor: _out ? AppColors.white : AppColors.navy),
                child: Text(state.saving ? 'Guardando…' : _out ? 'Registrar consumo' : 'Registrar entrada'),
              )),
            ])),
          ])),
        ),
      ),
    );
  }
}

/// «Quedará en X unidades»: lo que resulta de aplicar la cantidad al stock actual.
class _Preview extends StatelessWidget {
  const _Preview({required this.out, required this.current, required this.amount, required this.unit});
  final bool out;
  final int current, amount;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final result = out ? current - amount : current + amount;
    final invalid = amount <= 0 || result < 0;
    return Center(child: Text(
      invalid ? 'Revisa la cantidad' : 'Quedará en $result $unit',
      style: TextStyle(color: invalid ? AppColors.error : AppColors.steel, fontSize: 12.5, fontWeight: FontWeight.w700),
    ));
  }
}
