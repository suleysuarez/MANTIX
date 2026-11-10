import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/equipment/create_equipment_type_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../shared/mantix_sheet.dart';

const equipmentTypeNameMin = 2;
const equipmentTypeNameMax = 100;

/// Nombre como lo guarda el servidor: sin espacios a los lados y con los internos colapsados.
String normalizeTypeName(String value) => value.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).join(' ');

/// Mensaje en español si [normalized] no sirve como nombre de categoría; `null` si es válido.
String? validateTypeName(String normalized) {
  if (normalized.isEmpty) return 'Escribe el nombre de la categoría.';
  if (normalized.length < equipmentTypeNameMin) return 'El nombre necesita al menos $equipmentTypeNameMin caracteres.';
  if (normalized.length > equipmentTypeNameMax) return 'El nombre admite como máximo $equipmentTypeNameMax caracteres.';
  if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(normalized)) return 'El nombre necesita al menos una letra o un número.';
  return null;
}

/// Hoja para crear una categoría (requiere `equipos:crear`). Devuelve la categoría creada o, si
/// el servidor responde que ya existe una con ese nombre y la persona elige usarla, la que ya
/// estaba en [existing]. Devuelve `null` si se cierra sin elegir.
Future<EquipmentType?> showCreateTypeSheet(BuildContext context, {required List<EquipmentType> existing}) {
  final repository = context.read<EquipmentRepository>();
  return showMantixSheet<EquipmentType>(
    context,
    title: 'Nueva categoría',
    initialHeight: .75,
    builder: (sheetContext, controller) => BlocProvider(
      create: (_) => CreateEquipmentTypeBloc(repository: repository),
      child: _CreateTypeBody(controller: controller, existing: existing),
    ),
  );
}

class _CreateTypeBody extends StatefulWidget {
  const _CreateTypeBody({required this.controller, required this.existing});

  final ScrollController controller;
  final List<EquipmentType> existing;

  @override
  State<_CreateTypeBody> createState() => _CreateTypeBodyState();
}

class _CreateTypeBodyState extends State<_CreateTypeBody> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = normalizeTypeName(_name.text);
    final error = validateTypeName(name);
    setState(() => _error = error);
    if (error == null) context.read<CreateEquipmentTypeBloc>().add(EquipmentTypeSubmitted(name));
  }

  /// La categoría que ya existe con ese nombre (sin distinguir mayúsculas), si está en el catálogo.
  EquipmentType? _existingNamed(String name) => widget.existing.where((type) => type.name.toLowerCase() == name.toLowerCase()).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocConsumer<CreateEquipmentTypeBloc, CreateEquipmentTypeState>(
      listenWhen: (previous, current) => previous.status != current.status && current.status == CreateTypeStatus.success,
      listener: (context, state) => Navigator.of(context).pop(state.created),
      builder: (context, state) {
        final submitting = state.status == CreateTypeStatus.submitting;
        final existing = state.status == CreateTypeStatus.conflict ? _existingNamed(state.name) : null;
        return Column(children: [
          Expanded(
            child: ListView(
          controller: widget.controller,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('El nombre no puede repetirse (no distingue mayúsculas).', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              enabled: !submitting,
              autofocus: true,
              maxLength: equipmentTypeNameMax,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Nombre de la categoría', hintText: 'Por ejemplo: Proyector', counterText: '', prefixIcon: const Icon(Icons.category_outlined), errorText: _error),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
            ),
            if (state.status == CreateTypeStatus.conflict) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: AppColors.mustard.withValues(alpha: .2), borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.mustard)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(existing == null ? 'Ya existe una categoría con ese nombre, pero no está disponible para elegirla.' : 'Ya existe la categoría «${existing.name}».', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w700)),
                  if (existing != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(existing),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Usar la existente'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  ],
                ]),
              ),
            ],
            if (state.status == CreateTypeStatus.failure && state.failure != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(state.failure!.message, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
              ),
          ],
            ),
          ),
          // El botón queda fijo abajo: en una pantalla chica no se pierde fuera de vista.
          Container(
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x140B1F3A), blurRadius: 12, offset: Offset(0, -3))]),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: FilledButton.icon(
                  onPressed: submitting ? null : _submit,
                  icon: submitting ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Creando')) : const Icon(Icons.add_rounded),
                  label: const Text('Crear categoría'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
