import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/format/ticket_meta.dart';
import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/validation/validators.dart';
import '../../widgets/shared/app_text_field.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../bloc/requests/create_request_bloc.dart';
import '../../bloc/requests/equipment_search_bloc.dart';
import '../../widgets/shared/mantix_sheet.dart';
import '../../widgets/shared/search_picker_sheet.dart';

const requestTitleMax = 200;
const requestDescriptionMax = 2000;

/// Formulario para reportar un problema con un equipo.
class CreateRequestScreen extends StatelessWidget {
  const CreateRequestScreen({super.key, this.title = 'Nueva solicitud', this.submitLabel = 'Enviar solicitud', this.controller});

  final String title;
  final String submitLabel;

  /// Controlador de desplazamiento de la hoja, para que arrastrar y desplazar convivan.
  final ScrollController? controller;

  /// Abre el formulario en una hoja inferior arrastrable; la pantalla de fondo no se pierde.
  static Future<void> show(BuildContext context, {String title = 'Nueva solicitud', String submitLabel = 'Enviar solicitud'}) => showMantixSheet<void>(
        context,
        title: title,
        builder: (sheetContext, controller) => CreateRequestScreen(title: title, submitLabel: submitLabel, controller: controller),
      );

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CreateRequestBloc(repository: context.read<RequestsRepository>()),
      child: _CreateRequestForm(title: title, submitLabel: submitLabel, controller: controller),
    );
  }
}

class _CreateRequestForm extends StatefulWidget {
  const _CreateRequestForm({required this.title, required this.submitLabel, this.controller});

  final String title;
  final String submitLabel;
  final ScrollController? controller;

  @override
  State<_CreateRequestForm> createState() => _CreateRequestFormState();
}

class _CreateRequestFormState extends State<_CreateRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  EquipmentOption? _equipment;
  String _priority = 'medium';
  bool _equipmentMissing = false;

  /// Errores del servidor (422) por campo; se borran al editar el campo.
  Map<String, String> _serverErrors = const {};

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _clearServerError(String field) {
    if (!_serverErrors.containsKey(field)) return;
    setState(() => _serverErrors = {..._serverErrors}..remove(field));
  }

  Future<void> _pickEquipment() async {
    final repository = context.read<RequestsRepository>();
    final picked = await showSearchPicker<EquipmentOption>(
      context,
      title: 'Elegir equipo',
      hint: 'Etiqueta, serie, marca o modelo',
      emptyTitle: 'No encontramos equipos',
      createBloc: (search) => EquipmentSearchBloc(repository: repository, search: search),
      itemBuilder: (context, item, select) => Material(
        color: AppColors.canvas,
        borderRadius: AppRadius.mdAll,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          minVerticalPadding: AppSpacing.md,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: AppRadius.smAll),
            child: const Icon(Icons.desktop_windows_outlined, color: AppColors.steel),
          ),
          title: Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: item.typeName.isEmpty ? null : Text(item.typeName),
          trailing: item.id == _equipment?.id ? const Icon(Icons.check_rounded, color: AppColors.steel) : null,
          onTap: select,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _equipment = picked;
      _equipmentMissing = false;
    });
    _clearServerError('equipment_id');
  }

  void _submit() {
    final valid = _formKey.currentState!.validate();
    setState(() => _equipmentMissing = _equipment == null);
    if (!valid || _equipment == null) return;

    setState(() => _serverErrors = const {});
    context.read<CreateRequestBloc>().add(CreateRequestSubmitted(NewRequest(
          equipmentId: _equipment!.id,
          title: Validators.normalize(_title.text),
          description: Validators.normalize(_description.text),
          priority: _priority,
        )));
  }

  void _onResult(BuildContext context, CreateRequestState state) {
    if (state.status == CreateStatus.success) {
      // Se cierra la hoja; los listados abiertos se recargan solos y resaltan lo nuevo.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Solicitud creada.')));
    } else if (state.status == CreateStatus.failure) {
      final failure = state.failure!;
      if (failure is ValidationFailure) {
        setState(() => _serverErrors = failure.fieldErrors);
        if (failure.fieldErrors.isNotEmpty) return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final equipmentError = _equipmentMissing ? 'Elige el equipo con el problema.' : _serverErrors['equipment_id'];
    final submitting = context.select((CreateRequestBloc bloc) => bloc.state.status == CreateStatus.submitting);
    return BlocListener<CreateRequestBloc, CreateRequestState>(
      listener: _onResult,
      child: Scaffold(
      backgroundColor: AppColors.canvas,
      body: Form(
        key: _formKey,
        child: ListView(
          controller: widget.controller,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _Section(
              icon: Icons.devices_other_rounded,
              title: 'Equipo afectado',
              children: [
                _RequiredLabel('Equipo tecnológico', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Material(
                  color: AppColors.canvas,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.mdAll,
                    side: BorderSide(color: equipmentError == null ? AppColors.grey : theme.colorScheme.error),
                  ),
                  child: InkWell(
                    borderRadius: AppRadius.mdAll,
                    onTap: submitting ? null : _pickEquipment,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: AppRadius.smAll),
                          child: const Icon(Icons.desktop_windows_outlined, color: AppColors.steel),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_equipment?.label ?? 'Elegir equipo', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: _equipment == null ? AppColors.slate : AppColors.navy, fontWeight: FontWeight.w700)),
                            if (_equipment != null && _equipment!.typeName.isNotEmpty)
                              Text(_equipment!.typeName, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
                          ]),
                        ),
                        const Icon(Icons.search_rounded, color: AppColors.slate),
                      ]),
                    ),
                  ),
                ),
                // Siempre presente (vacío si no hay error): si apareciera y desapareciera
                // desplazaría los campos de la lista y perderían su estado de validación.
                Padding(
                  padding: EdgeInsets.only(top: equipmentError == null ? 0 : AppSpacing.xs, left: AppSpacing.md),
                  child: equipmentError == null
                      ? const SizedBox.shrink()
                      : Text(equipmentError, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              icon: Icons.edit_note_rounded,
              title: 'Detalle de la incidencia',
              children: [
                _RequiredLabel('Título de la incidencia', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                AppTextField(
                  label: '',
                  hint: 'Por ejemplo: la laptop no enciende',
                  controller: _title,
                  prefixIcon: const Icon(Icons.title_rounded),
                  enabled: !submitting,
                  maxLength: requestTitleMax,
                  textInputAction: TextInputAction.next,
                  errorText: _serverErrors['title'],
                  onChanged: (_) => _clearServerError('title'),
                  validator: Validators.all([Validators.required('El título'), Validators.maxLength(requestTitleMax, 'El título')]),
                ),
                const SizedBox(height: AppSpacing.md),
                _RequiredLabel('Descripción detallada', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                AppTextField(
                  label: '',
                  hint: 'Cuéntanos qué pasa y desde cuándo',
                  controller: _description,
                  prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 84), child: Icon(Icons.notes_rounded)),
                  enabled: !submitting,
                  maxLines: 5,
                  maxLength: requestDescriptionMax,
                  keyboardType: TextInputType.multiline,
                  errorText: _serverErrors['description'],
                  onChanged: (_) => _clearServerError('description'),
                  validator: Validators.all([
                    Validators.required('La descripción', true),
                    Validators.maxLength(requestDescriptionMax, 'La descripción'),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _Section(
              icon: Icons.flag_outlined,
              title: 'Prioridad',
              children: [
                Row(
                  children: [
                    for (final code in const ['low', 'medium', 'high', 'critical'])
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: code == 'critical' ? 0 : 6),
                          child: _PriorityOption(
                            code: code,
                            selected: _priority == code,
                            enabled: !submitting,
                            onTap: () {
                              setState(() => _priority = code);
                              _clearServerError('priority');
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                if (_serverErrors['priority'] != null)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text(_serverErrors['priority']!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: submitting ? null : _submit,
              icon: submitting ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Enviando')) : const Icon(Icons.send_rounded, size: 18),
              // Con letra grande en una pantalla estrecha el texto se achica en vez de desbordar.
              label: submitting ? const SizedBox.shrink() : FittedBox(fit: BoxFit.scaleDown, child: Text(widget.submitLabel, maxLines: 1)),
            ),
          ],
        ),
      ),
    ),
    );
  }
}


class _RequiredLabel extends StatelessWidget {
  const _RequiredLabel(this.value, {required this.style});
  final String value;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => RichText(text: TextSpan(style: style, children: [
    TextSpan(text: value),
    const TextSpan(text: ' *', style: TextStyle(color: AppColors.mustard, fontWeight: FontWeight.w800)),
  ]));
}

class _PriorityOption extends StatelessWidget {
  const _PriorityOption({required this.code, required this.selected, required this.enabled, required this.onTap});
  final String code;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final meta = priorityMeta(code);
    final colors = meta.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.background : Colors.white,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: AppRadius.mdAll,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: selected ? colors.dot : AppColors.grey, width: selected ? 1.8 : 1),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(priorityIcon(code), size: 20, color: selected ? colors.foreground : AppColors.slate),
              const SizedBox(height: 4),
              Text(meta.label, maxLines: 1, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: selected ? colors.foreground : AppColors.slate, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta blanca con icono y título que agrupa los campos de una misma parte del formulario.
class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .5))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .45), borderRadius: AppRadius.smAll),
              child: Icon(icon, size: 18, color: AppColors.steel),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ]),
      );
}
