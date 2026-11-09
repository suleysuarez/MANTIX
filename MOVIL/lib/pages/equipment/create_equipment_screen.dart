import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/equipment/create_equipment_bloc.dart';
import '../../bloc/equipment/equipment_catalog_bloc.dart';
import '../../core/errors/failure.dart';
import '../../core/format/equipment_meta.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validation/validators.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../../widgets/equipment/custodian_picker.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import 'equipment_screen.dart';

const equipmentTagMax = 50;
const equipmentNameMax = 100;
const equipmentDescriptionMax = 2000;

/// Formulario «Registrar nuevo equipo» (permiso `equipos:crear`). La ubicación y el responsable
/// solo se ofrecen a quien tiene `equipos:editar` y `equipos:asignar`, respectivamente.
class CreateEquipmentScreen extends StatelessWidget {
  const CreateEquipmentScreen({super.key});

  static const path = '/modulos/equipos/nuevo';

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
        providers: [
          BlocProvider(create: (context) => CreateEquipmentBloc(repository: context.read<EquipmentRepository>())),
          BlocProvider(create: (context) => EquipmentCatalogBloc(repository: context.read<EquipmentRepository>())..add(const EquipmentCatalogStarted())),
        ],
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
  int? _locationId;
  CustodianCandidate? _custodian;
  String _status = 'in_storage';
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
          status: _status,
          locationId: _locationId,
          custodianId: _custodian?.id,
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
      messenger.showSnackBar(SnackBar(content: Text(['Equipo registrado.', ...state.warnings].join(' '))));
    } else if (state.status == CreateEquipmentStatus.failure) {
      final failure = state.failure!;
      if (failure is ValidationFailure) {
        setState(() => _serverErrors = failure.fieldErrors);
        if (failure.fieldErrors.isNotEmpty) return;
      }
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _pickCustodian() async {
    final picked = await showCustodianPicker(context, selected: _custodian);
    if (!mounted || picked == null) return;
    setState(() => _custodian = picked.cleared ? null : picked.candidate);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    final submitting = context.select((CreateEquipmentBloc bloc) => bloc.state.status == CreateEquipmentStatus.submitting);
    final catalog = context.watch<EquipmentCatalogBloc>().state;
    final canLocate = profile?.can('equipos:editar') ?? false;
    final canAssign = profile?.can('equipos:asignar') ?? false;
    return BlocListener<CreateEquipmentBloc, CreateEquipmentState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: _onResult,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: profile == null ? AppBar(title: const Text('Registrar nuevo equipo')) : MantixAppBar(profile: profile),
        drawer: profile == null ? null : MantixDrawer(profile: profile, selectedPath: EquipmentScreen.path),
        bottomNavigationBar: _ActionBar(submitting: submitting, onCancel: () => context.pop(), onSubmit: _submit),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5EEF6)),
                  boxShadow: const [BoxShadow(color: Color(0x0C0B1F3A), blurRadius: 14, offset: Offset(0, 5))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _PanelHeader(onClose: () => context.pop()),
                  const SizedBox(height: 18),
                  const _SectionTitle(number: 1, title: 'Información general', trailing: true),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: _Labeled(
                        label: 'Código de activo',
                        required: true,
                        child: TextFormField(
                          key: const Key('field-asset-tag'),
                          controller: _tag,
                          maxLength: equipmentTagMax,
                          textInputAction: TextInputAction.next,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          decoration: InputDecoration(hintText: 'Ej: EQ-029', counterText: '', errorText: _serverErrors['asset_tag']),
                          validator: (v) => Validators.all([Validators.required('La etiqueta', true), Validators.maxLength(equipmentTagMax, 'La etiqueta')])(Validators.normalize(v)),
                          onChanged: (_) => _clearServerError('asset_tag'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Labeled(
                        label: 'Categoría',
                        required: true,
                        child: _TypeField(
                          catalog: catalog,
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
                        ),
                      ),
                    ),
                  ]),
                  if (catalog.status == CatalogStatus.failure)
                    _CatalogRetry(message: catalog.failure?.message, onRetry: () => context.read<EquipmentCatalogBloc>().add(const EquipmentCatalogStarted())),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: _Labeled(
                        label: 'Marca',
                        required: true,
                        child: TextFormField(
                          key: const Key('field-brand'),
                          controller: _brand,
                          maxLength: equipmentNameMax,
                          textInputAction: TextInputAction.next,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          decoration: InputDecoration(hintText: 'Ej: Dell, HP, Lenovo', counterText: '', errorText: _serverErrors['brand']),
                          validator: (v) => Validators.all([Validators.required('La marca', true), Validators.maxLength(equipmentNameMax, 'La marca')])(Validators.normalize(v)),
                          onChanged: (_) => _clearServerError('brand'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Labeled(
                        label: 'Modelo',
                        required: true,
                        child: TextFormField(
                          key: const Key('field-model'),
                          controller: _model,
                          maxLength: equipmentNameMax,
                          textInputAction: TextInputAction.next,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          decoration: InputDecoration(hintText: 'Ej: Latitude 5540', counterText: '', errorText: _serverErrors['model']),
                          validator: (v) => Validators.all([Validators.required('El modelo'), Validators.maxLength(equipmentNameMax, 'El modelo')])(Validators.normalize(v)),
                          onChanged: (_) => _clearServerError('model'),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _Labeled(
                    label: 'Número de serie (SN)',
                    child: TextFormField(
                      key: const Key('field-serial'),
                      controller: _serial,
                      maxLength: equipmentNameMax,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(hintText: 'Ej: SN-DELL-882194', counterText: '', errorText: _serverErrors['serial_number']),
                      validator: (v) => Validators.maxLength(equipmentNameMax, 'El número de serie')(Validators.normalize(v)),
                      onChanged: (_) => _clearServerError('serial_number'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Labeled(
                    label: 'Descripción y especificaciones técnicas',
                    child: TextFormField(
                      key: const Key('field-description'),
                      controller: _description,
                      maxLength: equipmentDescriptionMax,
                      maxLines: 3,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(hintText: 'Ej: Intel Core i7 13th Gen, 16GB RAM DDR5, 512GB SSD NVMe', counterText: '', errorText: _serverErrors['description']),
                      validator: (v) => Validators.maxLength(equipmentDescriptionMax, 'La descripción')(Validators.normalize(v)),
                      onChanged: (_) => _clearServerError('description'),
                    ),
                  ),
                  if (canLocate || canAssign) ...[
                    const SizedBox(height: 22),
                    const _SectionTitle(number: 2, title: 'Asignación y ubicación'),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (canLocate)
                        Expanded(
                          child: _Labeled(
                            label: 'Ubicación física o área',
                            child: DropdownButtonFormField<int?>(
                              key: ValueKey('location-${catalog.locations.length}-$_locationId'),
                              initialValue: _locationId,
                              isExpanded: true,
                              decoration: const InputDecoration(),
                              items: [
                                const DropdownMenuItem<int?>(value: null, child: Text('Sin ubicación por ahora', overflow: TextOverflow.ellipsis)),
                                for (final location in catalog.locations) DropdownMenuItem<int?>(value: location.id, child: Text(location.name, overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: submitting ? null : (id) => setState(() => _locationId = id),
                            ),
                          ),
                        ),
                      if (canLocate && canAssign) const SizedBox(width: 10),
                      if (canAssign)
                        Expanded(
                          child: _Labeled(
                            label: 'Responsable asignado / custodio',
                            child: _CustodianField(custodian: _custodian, enabled: !submitting, onTap: _pickCustodian),
                          ),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 22),
                  _SectionTitle(number: canLocate || canAssign ? 3 : 2, title: 'Estado y garantía'),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: _Labeled(
                        label: 'Estado',
                        required: true,
                        child: DropdownButtonFormField<String>(
                          key: const Key('field-status'),
                          initialValue: _status,
                          isExpanded: true,
                          decoration: InputDecoration(errorText: _serverErrors['status']),
                          items: [for (final status in knownEquipmentStatuses) DropdownMenuItem(value: status, child: Text(equipmentStatusMeta(status).label, overflow: TextOverflow.ellipsis))],
                          onChanged: submitting
                              ? null
                              : (status) {
                                  if (status == null) return;
                                  setState(() => _status = status);
                                  _clearServerError('status');
                                },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Labeled(
                        label: 'Costo de adquisición',
                        child: TextFormField(
                          key: const Key('field-cost'),
                          controller: _cost,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(hintText: '0.00', errorText: _serverErrors['purchase_cost']),
                          validator: (v) => Validators.all([Validators.nonNegativeNumber('El costo'), _costDecimals])(Validators.normalize(v)),
                          onChanged: (_) => _clearServerError('purchase_cost'),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _Labeled(
                    label: 'Fecha de adquisición',
                    child: _DateField(
                      value: _purchase,
                      errorText: _purchaseError ?? _serverErrors['purchase_date'],
                      onChanged: (date) {
                        setState(() => _purchase = date);
                        _clearServerError('purchase_date');
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: _Labeled(
                        label: 'Garantía desde',
                        child: _DateField(
                          value: _warrantyStart,
                          errorText: _serverErrors['warranty_start_date'],
                          onChanged: (date) {
                            setState(() => _warrantyStart = date);
                            _clearServerError('warranty_start_date');
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Labeled(
                        label: 'Garantía hasta',
                        child: _DateField(
                          value: _warrantyEnd,
                          errorText: _warrantyError ?? _serverErrors['warranty_end_date'],
                          onChanged: (date) {
                            setState(() => _warrantyEnd = date);
                            _clearServerError('warranty_end_date');
                          },
                        ),
                      ),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: EquipmentColors.info.background, borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.add_rounded, color: EquipmentColors.info.foreground, size: 26),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Registrar nuevo equipo', style: TextStyle(color: Color(0xFF0B1F3A), fontSize: 17, fontWeight: FontWeight.w800)),
            SizedBox(height: 2),
            Text('Completa la ficha técnica, ubicación y estado del dispositivo.', style: TextStyle(color: AppColors.slate, fontSize: 11.5, height: 1.3)),
          ]),
        ),
        IconButton(tooltip: 'Cerrar', onPressed: onClose, icon: const Icon(Icons.close_rounded, color: AppColors.slate)),
      ]);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.number, required this.title, this.trailing = false});

  final int number;
  final String title;

  /// Muestra «* Campos requeridos» a la derecha.
  final bool trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFF0B1F3A), shape: BoxShape.circle),
            child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title.toUpperCase(), style: const TextStyle(color: Color(0xFF0B1F3A), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
          if (trailing)
            const Text.rich(TextSpan(children: [
              TextSpan(text: '* ', style: TextStyle(color: AppColors.mustard, fontWeight: FontWeight.w800)),
              TextSpan(text: 'Campos requeridos'),
            ]), style: TextStyle(color: AppColors.slate, fontSize: 10.5)),
        ]),
      );
}

/// Etiqueta fija sobre el campo (con asterisco mostaza si es obligatorio).
class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child, this.required = false});

  final String label;
  final bool required;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text.rich(
            TextSpan(text: label, children: [if (required) const TextSpan(text: ' *', style: TextStyle(color: AppColors.mustard, fontWeight: FontWeight.w800))]),
            style: const TextStyle(color: Color(0xFF334155), fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
        child,
      ]);
}

class _TypeField extends StatelessWidget {
  const _TypeField({required this.catalog, required this.value, required this.missing, required this.enabled, required this.onChanged, this.serverError});

  final EquipmentCatalogState catalog;
  final int? value;
  final bool missing;
  final bool enabled;
  final String? serverError;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final loading = catalog.status == CatalogStatus.loading;
    return DropdownButtonFormField<int>(
      key: ValueKey('type-${catalog.types.length}-$value'),
      initialValue: value,
      isExpanded: true,
      hint: Text(loading ? 'Cargando…' : 'Seleccionar categoría', overflow: TextOverflow.ellipsis),
      decoration: InputDecoration(errorText: missing ? 'Elige la categoría del equipo.' : serverError, errorMaxLines: 2),
      items: [for (final type in catalog.types) DropdownMenuItem(value: type.id, child: Text(type.name, overflow: TextOverflow.ellipsis))],
      onChanged: loading || !enabled ? null : onChanged,
    );
  }
}

class _CatalogRetry extends StatelessWidget {
  const _CatalogRetry({required this.onRetry, this.message});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.slate),
          const SizedBox(width: 8),
          Expanded(child: Text('No pudimos cargar las categorías y ubicaciones. ${message ?? ''}'.trim(), style: const TextStyle(color: AppColors.slate, fontSize: 12))),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ]),
      );
}

class _CustodianField extends StatelessWidget {
  const _CustodianField({required this.custodian, required this.enabled, required this.onTap});

  final CustodianCandidate? custodian;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.person_search_outlined, size: 20)),
          child: Text(
            custodian?.fullName ?? 'Buscar por nombre o correo…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: custodian == null ? AppColors.slate : const Color(0xFF0B1F3A), fontSize: custodian == null ? 13 : 14),
          ),
        ),
      );
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onChanged, this.errorText});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
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
            errorText: errorText,
            errorMaxLines: 2,
            suffixIcon: value == null
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : IconButton(tooltip: 'Quitar fecha', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => onChanged(null)),
          ),
          child: Text(value == null ? 'Elegir fecha' : formatDate(value!), style: TextStyle(color: value == null ? AppColors.slate : const Color(0xFF0B1F3A), fontSize: value == null ? 13 : 14)),
        ),
      );
}

/// Barra inferior: aviso y los botones «Cancelar» y «Guardar equipo».
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.submitting, required this.onCancel, required this.onSubmit});

  final bool submitting;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x140B1F3A), blurRadius: 16, offset: Offset(0, -4))]),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.info_outline_rounded, size: 14, color: AppColors.slate),
                SizedBox(width: 6),
                Expanded(child: Text('El equipo se integra de inmediato al inventario.', style: TextStyle(color: AppColors.slate, fontSize: 11))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: submitting ? null : onCancel, child: const Text('Cancelar'))),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: submitting ? null : onSubmit,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0B1F3A), foregroundColor: Colors.white),
                    icon: submitting ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('GUARDAR EQUIPO'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );
}
