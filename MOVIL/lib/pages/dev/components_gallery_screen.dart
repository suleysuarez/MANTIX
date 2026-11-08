import 'package:flutter/material.dart';

import '../../core/format/ticket_meta.dart';
import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/validation/validators.dart';
import '../../widgets/shared/app_chip.dart';
import '../../widgets/shared/app_text_field.dart';
import '../../widgets/shared/confirm_dialog.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/error_state.dart';
import '../../widgets/shared/glass_card.dart';
import '../../widgets/shared/skeleton.dart';

/// Galería de componentes para revisar el sistema de diseño en un dispositivo.
/// Solo se registra en modo debug; no existe en las compilaciones de producción.
class ComponentsGalleryScreen extends StatelessWidget {
  const ComponentsGalleryScreen({super.key});

  static const String path = '/dev/componentes';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Componentes')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          const _Section('Estados de ticket'),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            for (final code in knownStatuses) StatusChip(code),
            const StatusChip('estado_nuevo'),
          ]),
          const _Section('Prioridades'),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            for (final code in knownPriorities) PriorityChip(code),
          ]),
          const _Section('Botones'),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            FilledButton(onPressed: () {}, child: const Text('Principal')),
            OutlinedButton(onPressed: () {}, child: const Text('Secundario')),
            TextButton(onPressed: () {}, child: const Text('Texto')),
            const FilledButton(onPressed: null, child: Text('Deshabilitado')),
          ]),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () => showConfirmDialog(
              context,
              title: 'Cerrar ticket',
              message: 'El ticket pasará a «Cerrado» y ya no se podrá editar.',
              confirmLabel: 'Cerrar ticket',
              destructive: true,
            ),
            child: const Text('Abrir diálogo de confirmación'),
          ),
          const _Section('Campos de texto'),
          const AppTextField(label: 'Título', hint: 'Ej: Ruido anormal en el ventilador', maxLength: 200),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Título con validación',
            hint: 'Escribe y borra para ver el error',
            validator: Validators.all([Validators.required('El título'), Validators.minLength(5, 'El título')]),
          ),
          const SizedBox(height: AppSpacing.md),
          const AppTextField(label: 'Prioridad', errorText: 'Valor no válido (error del servidor)'),
          const _Section('Esqueleto de carga'),
          const Row(children: [
            Skeleton(width: 56, height: 56, radius: AppRadius.md),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Skeleton(height: 16),
                SizedBox(height: AppSpacing.sm),
                Skeleton(width: 140, height: 12),
              ]),
            ),
          ]),
          const _Section('Estado vacío'),
          const SizedBox(
            height: 260,
            child: EmptyState(
              title: 'Aún no hay tickets registrados.',
              message: 'Los tickets aparecerán aquí una vez que se creen en el sistema.',
              icon: Icons.note_add_outlined,
              actionLabel: 'Nuevo ticket',
              onAction: _noop,
            ),
          ),
          const _Section('Estados de error'),
          const SizedBox(height: 300, child: ErrorState(failure: NetworkFailure(), onRetry: _noop)),
          const SizedBox(height: 320, child: ErrorState(failure: ServerFailure(requestId: '542dcaa102d5415b'), onRetry: _noop)),
          const SizedBox(height: 260, child: ErrorState(failure: ForbiddenFailure())),
          const _Section('Glass (solo puntual, sobre fondo oscuro)'),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: const BoxDecoration(
              borderRadius: AppRadius.lgAll,
              gradient: LinearGradient(colors: [AppColors.navy, AppColors.steel]),
            ),
            child: const GlassCard(
              child: Text('Tarjeta translúcida', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

void _noop() {}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );
  }
}
