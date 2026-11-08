import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/domain/ticket_meta.dart';
import '../../core/errors/failure.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/validation/validators.dart';
import '../../widgets/shared/app_text_field.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../bloc/requests/create_request_bloc.dart';
import 'equipment_picker_screen.dart';
import 'my_requests_screen.dart';

const requestTitleMax = 200;
const requestDescriptionMax = 2000;

/// Formulario para reportar un problema con un equipo.
class CreateRequestScreen extends StatelessWidget {
  const CreateRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CreateRequestBloc(repository: context.read<RequestsRepository>()),
      child: const _CreateRequestForm(),
    );
  }
}

class _CreateRequestForm extends StatefulWidget {
  const _CreateRequestForm();

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
    final picked = await Navigator.of(context).push<EquipmentOption>(
      MaterialPageRoute(builder: (_) => const EquipmentPickerScreen()),
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
      context.pushReplacement(RequestRoutes.detail(state.createdId!));
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
      appBar: AppBar(title: const Text('Nueva solicitud')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Equipo', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                minVerticalPadding: AppSpacing.md,
                leading: const Icon(Icons.devices_other_outlined),
                title: Text(_equipment?.label ?? 'Elegir equipo'),
                subtitle: _equipment == null || _equipment!.typeName.isEmpty ? null : Text(_equipment!.typeName),
                trailing: const Icon(Icons.chevron_right),
                onTap: submitting ? null : _pickEquipment,
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
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Título',
              hint: 'Por ejemplo: la laptop no enciende',
              controller: _title,
              enabled: !submitting,
              maxLength: requestTitleMax,
              textInputAction: TextInputAction.next,
              errorText: _serverErrors['title'],
              onChanged: (_) => _clearServerError('title'),
              validator: Validators.all([Validators.required('El título'), Validators.maxLength(requestTitleMax, 'El título')]),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Descripción',
              hint: 'Cuéntanos qué pasa y desde cuándo',
              controller: _description,
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
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: InputDecoration(labelText: 'Prioridad', errorText: _serverErrors['priority']),
              items: [
                for (final code in knownPriorities.reversed)
                  DropdownMenuItem(value: code, child: Text(priorityMeta(code).label)),
              ],
              onChanged: submitting
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _priority = value);
                      _clearServerError('priority');
                    },
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: submitting ? null : _submit,
              child: submitting
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Enviando'))
                  : const Text('Enviar solicitud'),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
