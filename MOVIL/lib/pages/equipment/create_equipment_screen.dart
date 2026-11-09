import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/equipment/create_equipment_bloc.dart';
import '../../core/errors/failure.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/validation/validators.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../../widgets/shared/app_text_field.dart';

const equipmentTagMax = 50;
const equipmentNameMax = 100;
const equipmentDescriptionMax = 2000;

/// Formulario «Nuevo equipo» (permiso `equipos:crear`).
class CreateEquipmentScreen extends StatelessWidget {
  const CreateEquipmentScreen({super.key});

  static const path = '/modulos/equipos/nuevo';

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => CreateEquipmentBloc(repository: context.read<EquipmentRepository>())..add(const CreateEquipmentStarted()),
        child: const _CreateEquipmentForm(),
      );
}

class _CreateEquipmentForm extends StatefulWidget {
  const _CreateEquipmentForm();

  @override
  State<_CreateEquipmentForm> createState() => _CreateEquipmentFormState();
}

class _CreateEquipmentFormState extends State<_CreateEquipmentForm> {
  final _formKey = GlobalKey<FormState>();
  final _tag = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _description = TextEditingController();
  final _cost = TextEditingController();
  int? _typeId;
  bool _typeMissing = false;
  DateTime? _purchase;
  DateTime? _warrantyStart;
  DateTime? _warrantyEnd;

  /// Errores del servidor (422) por campo; se borran al editar el campo.
  Map<String, String> _serverErrors = const {};

  @override
  void dispose() {
    for (final controller in [_tag, _brand, _model, _serial, _description, _cost]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearServerError(String field) {
    if (!_serverErrors.containsKey(field)) return;
    setState(() => _serverErrors = {..._serverErrors}..remove(field));
  }

  String? get _purchaseError => Validators.notInFuture(_purchase, field: 'La fecha de adquisición');
  String? get _warrantyError => Validators.dateRange(_warrantyStart, _warrantyEnd);

  static String? _costDecimals(String? value) {
    final text = Validators.normalize(value).replaceAll(',', '.');
    final dot = text.indexOf('.');
    return dot >= 0 && text.length - dot - 1 > 2 ? 'El costo admite como máximo dos decimales.' : null;
  }

  void _submit() {
    final valid = _formKey.currentState!.validate();
    setState(() => _typeMissing = _typeId == null);
    if (!valid || _typeId == null || _purchaseError != null || _warrantyError != null) return;

    setState(() => _serverErrors = const {});
    String? optional(TextEditingController controller) {
      final text = Validators.normalize(controller.text);
      return text.isEmpty ? null : text;
    }

    context.read<CreateEquipmentBloc>().add(CreateEquipmentSubmitted(NewEquipment(
          assetTag: Validators.normalize(_tag.text),
          typeId: _typeId!,
          brand: Validators.normalize(_brand.text),
          model: Validators.normalize(_model.text),
          serialNumber: optional(_serial),
          description: optional(_description),
          purchaseDate: _purchase,
          purchaseCost: optional(_cost)?.replaceAll(',', '.'),
          warrantyStart: _warrantyStart,
          warrantyEnd: _warrantyEnd,
        )));
  }

  void _onResult(BuildContext context, CreateEquipmentState state) {
    final messenger = ScaffoldMessenger.of(context);
    if (state.status == CreateEquipmentStatus.success) {
      context.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Equipo registrado.')));
    } else if (state.status == CreateEquipmentStatus.failure) {
      final failure = state.failure!;
      if (failure is ValidationFailure) {
        setState(() => _serverErrors = failure.fieldErrors);
        if (failure.fieldErrors.isNotEmpty) return;
      }
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CreateEquipmentBloc>().state;
    final submitting = state.status == CreateEquipmentStatus.submitting;
    return BlocListener<CreateEquipmentBloc, CreateEquipmentState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: _onResult,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('Nuevo equipo')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const _Section('Identificación'),
              AppTextField(
                label: 'Etiqueta de activo *',
                hint: 'Ej: EQ-029',
                controller: _tag,
                maxLength: equipmentTagMax,
                textInputAction: TextInputAction.next,
                errorText: _serverErrors['asset_tag'],
                validator: Validators.all([Validators.required('La etiqueta', true), Validators.maxLength(equipmentTagMax, 'La etiqueta')]),
                onChanged: (_) => _clearServerError('asset_tag'),
              ),
              const SizedBox(height: AppSpacing.md),
              _TypeField(
                state: state,
                value: _typeId,
                missing: _typeMissing,
                serverError: _serverErrors['equipment_type_id'],
                enabled: !submitting,
                onChanged: (id) {
                  setState(() {
                    _typeId = id;
                    _typeMissing = false;
                  });
                  _clearServerError('equipment_type_id');
                },
                onRetry: () => context.read<CreateEquipmentBloc>().add(const CreateEquipmentStarted()),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Marca *',
                hint: 'Ej: Dell, HP, Lenovo',
                controller: _brand,
                maxLength: equipmentNameMax,
                textInputAction: TextInputAction.next,
                errorText: _serverErrors['brand'],
                validator: Validators.all([Validators.required('La marca', true), Validators.maxLength(equipmentNameMax, 'La marca')]),
                onChanged: (_) => _clearServerError('brand'),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Modelo *',
                hint: 'Ej: Latitude 5540',
                controller: _model,
                maxLength: equipmentNameMax,
                textInputAction: TextInputAction.next,
                errorText: _serverErrors['model'],
                validator: Validators.all([Validators.required('El modelo'), Validators.maxLength(equipmentNameMax, 'El modelo')]),
                onChanged: (_) => _clearServerError('model'),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Número de serie',
                hint: 'Ej: SN-DELL-882194',
                controller: _serial,
                maxLength: equipmentNameMax,
                textInputAction: TextInputAction.next,
                errorText: _serverErrors['serial_number'],
                validator: Validators.maxLength(equipmentNameMax, 'El número de serie'),
                onChanged: (_) => _clearServerError('serial_number'),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _Section('Detalles'),
              AppTextField(
                label: 'Descripción y especificaciones técnicas',
                hint: 'Ej: Intel Core i7, 16 GB de RAM, SSD de 512 GB',
                controller: _description,
                maxLength: equipmentDescriptionMax,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                errorText: _serverErrors['description'],
                validator: Validators.maxLength(equipmentDescriptionMax, 'La descripción'),
                onChanged: (_) => _clearServerError('description'),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _Section('Compra y garantía'),
              AppTextField(
                label: 'Costo de adquisición',
                hint: '0.00',
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                errorText: _serverErrors['purchase_cost'],
                validator: Validators.all([Validators.nonNegativeNumber('El costo'), _costDecimals]),
                onChanged: (_) => _clearServerError('purchase_cost'),
              ),
              const SizedBox(height: AppSpacing.md),
              _DateField(
                label: 'Fecha de adquisición',
                value: _purchase,
                errorText: _purchaseError ?? _serverErrors['purchase_date'],
                onChanged: (date) {
                  setState(() => _purchase = date);
                  _clearServerError('purchase_date');
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _DateField(
                label: 'Garantía desde',
                value: _warrantyStart,
                errorText: _serverErrors['warranty_start_date'],
                onChanged: (date) {
                  setState(() => _warrantyStart = date);
                  _clearServerError('warranty_start_date');
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _DateField(
                label: 'Garantía hasta',
                value: _warrantyEnd,
                errorText: _warrantyError ?? _serverErrors['warranty_end_date'],
                onChanged: (date) {
                  setState(() => _warrantyEnd = date);
                  _clearServerError('warranty_end_date');
                },
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('* Obligatorio. El equipo se registra en almacén; después se le puede asignar custodio y ubicación.', style: TextStyle(color: AppColors.slate, fontSize: 11.5, height: 1.35)),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: submitting ? null : _submit,
                child: submitting ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Registrar equipo'),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Text(title.toUpperCase(), style: const TextStyle(color: AppColors.slate, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
      );
}

class _TypeField extends StatelessWidget {
  const _TypeField({
    required this.state,
    required this.value,
    required this.missing,
    required this.enabled,
    required this.onChanged,
    required this.onRetry,
    this.serverError,
  });

  final CreateEquipmentState state;
  final int? value;
  final bool missing;
  final bool enabled;
  final String? serverError;
  final ValueChanged<int?> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.typesStatus == TypesStatus.failure) {
      return Row(children: [
        const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.slate),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text('No pudimos cargar las categorías. ${state.typesFailure?.message ?? ''}'.trim(), style: const TextStyle(color: AppColors.slate, fontSize: 12))),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ]);
    }
    final loading = state.typesStatus == TypesStatus.loading;
    return DropdownButtonFormField<int>(
      key: ValueKey('${state.types.length}|$value'),
      initialValue: value,
      isExpanded: true,
      hint: Text(loading ? 'Cargando categorías…' : 'Elige una categoría'),
      decoration: InputDecoration(labelText: 'Categoría *', errorText: missing ? 'Elige la categoría del equipo.' : serverError),
      items: [for (final type in state.types) DropdownMenuItem(value: type.id, child: Text(type.name))],
      onChanged: loading || !enabled ? null : onChanged,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onChanged, this.errorText});

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(1990),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            suffixIcon: value == null
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : IconButton(tooltip: 'Quitar fecha', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => onChanged(null)),
          ),
          child: Text(value == null ? 'Elegir fecha' : formatDate(value!), style: TextStyle(color: value == null ? AppColors.slate : const Color(0xFF0B1F3A))),
        ),
      );
}
