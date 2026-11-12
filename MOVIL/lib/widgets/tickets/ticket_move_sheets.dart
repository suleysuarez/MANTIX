import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/catalogs/category_search_bloc.dart';
import '../../bloc/catalogs/priorities_cubit.dart';
import '../../bloc/catalogs/technician_search_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/catalogs/catalog_models.dart';
import '../../models/requests/request_models.dart';
import '../../models/technicians/technician_models.dart';
import '../../repositories/catalogs/catalogs_repository.dart';
import '../../repositories/technicians/technicians_repository.dart';
import '../shared/error_state.dart';
import '../shared/mantix_sheet.dart';
import '../shared/search_picker_sheet.dart';
import '../shared/skeleton.dart';
import 'ticket_move_dialog.dart';

/// Hoja para pasar un ticket a «En triaje»: pide la categoría y la prioridad antes de
/// confirmar. Devuelve lo elegido o `null` si se cierra sin confirmar.
Future<TicketMoveInput?> showClassifySheet(BuildContext context, {required TicketListItem ticket, String title = 'Pasar a «En triaje»'}) {
  final catalogs = context.read<CatalogsRepository>();
  return showMantixSheet<TicketMoveInput>(
    context,
    title: title,
    initialHeight: .8,
    builder: (sheetContext, controller) => BlocProvider(
      create: (_) => PrioritiesCubit(catalogs)..load(),
      child: _ClassifyBody(ticket: ticket, controller: controller, catalogs: catalogs),
    ),
  );
}

class _ClassifyBody extends StatefulWidget {
  const _ClassifyBody({required this.ticket, required this.controller, required this.catalogs});

  final TicketListItem ticket;
  final ScrollController controller;
  final CatalogsRepository catalogs;

  @override
  State<_ClassifyBody> createState() => _ClassifyBodyState();
}

class _ClassifyBodyState extends State<_ClassifyBody> {
  final _notes = TextEditingController();
  RequestCategory? _category;
  String? _priority;
  bool _prefilled = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final picked = await showSearchPicker<RequestCategory>(
      context,
      title: 'Categoría',
      hint: 'Buscar categoría',
      emptyTitle: 'No hay categorías con ese nombre',
      createBloc: (search) => CategorySearchBloc(repository: widget.catalogs, search: search),
      itemBuilder: (context, category, select) => ListTile(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        tileColor: AppColors.canvas,
        minVerticalPadding: AppSpacing.md,
        leading: const Icon(Icons.label_outline_rounded, color: AppColors.steel),
        title: Text(category.name),
        trailing: category.code == _category?.code ? const Icon(Icons.check_rounded, color: AppColors.steel) : null,
        onTap: select,
      ),
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Expanded(
        child: ListView(
          controller: widget.controller,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(widget.ticket.ticketNumber, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w700)),
            Text(widget.ticket.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.lg),
            Text('Categoría', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Semantics(
              button: true,
              label: 'Categoría: ${_category?.name ?? 'sin elegir'}',
              excludeSemantics: true,
              child: InkWell(
                key: const Key('field-category'),
                borderRadius: BorderRadius.circular(12),
                onTap: _pickCategory,
                child: InputDecorator(
                  decoration: const InputDecoration(suffixIcon: Icon(Icons.search_rounded), prefixIcon: Icon(Icons.label_outline_rounded)),
                  child: Text(_category?.name ?? 'Elegir categoría', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _category == null ? AppColors.slate : AppColors.navy)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Prioridad', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            BlocConsumer<PrioritiesCubit, PrioritiesState>(
              // La prioridad con que se creó el ticket queda elegida; se puede cambiar.
              listenWhen: (previous, current) => current.status == PrioritiesStatus.success && !_prefilled,
              listener: (context, state) {
                _prefilled = true;
                if (state.priorities.any((priority) => priority.code == widget.ticket.priority)) setState(() => _priority = widget.ticket.priority);
              },
              builder: (context, state) => switch (state.status) {
                PrioritiesStatus.loading => const Skeleton(height: 48),
                PrioritiesStatus.failure => ErrorState(failure: state.failure!, onRetry: () => context.read<PrioritiesCubit>().load()),
                PrioritiesStatus.success => Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                    for (final priority in state.priorities)
                      ChoiceChip(
                        label: Text(priority.name),
                        selected: _priority == priority.code,
                        onSelected: (_) => setState(() => _priority = priority.code),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                  ]),
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _notes,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Por ejemplo: requiere visita'),
            ),
          ],
        ),
      ),
      _ConfirmBar(
        label: 'Confirmar triaje',
        enabled: _category != null && _priority != null,
        onConfirm: () => Navigator.of(context).pop(TicketMoveInput(category: _category!.code, priority: _priority, notes: _notes.text)),
      ),
    ]);
  }
}

/// Hoja para pasar un ticket a «Asignado»: se busca un técnico **activo** y se confirma.
/// Devuelve la elección o `null` si se cierra sin confirmar.
Future<TicketMoveInput?> showAssignSheet(BuildContext context, {required TicketListItem ticket, String? title}) {
  final technicians = context.read<TechniciansRepository>();
  return showMantixSheet<TicketMoveInput>(
    context,
    title: title ?? 'Pasar a «Asignado»',
    initialHeight: .85,
    builder: (sheetContext, controller) => _AssignBody(ticket: ticket, controller: controller, technicians: technicians),
  );
}

class _AssignBody extends StatefulWidget {
  const _AssignBody({required this.ticket, required this.controller, required this.technicians});

  final TicketListItem ticket;
  final ScrollController controller;
  final TechniciansRepository technicians;

  @override
  State<_AssignBody> createState() => _AssignBodyState();
}

class _AssignBodyState extends State<_AssignBody> {
  Technician? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('${widget.ticket.ticketNumber} · ${widget.ticket.title}', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
        ),
      ),
      Expanded(
        child: SearchPicker<Technician>(
          controller: widget.controller,
          hint: 'Nombre, correo o especialidad',
          emptyTitle: 'No hay técnicos activos con ese criterio',
          createBloc: (search) => TechnicianSearchBloc(repository: widget.technicians, search: search),
          itemBuilder: (context, technician, select) => _TechnicianTile(technician: technician, selected: _selected?.id == technician.id, onTap: () => setState(() => _selected = technician)),
        ),
      ),
      _ConfirmBar(
        label: _selected == null ? 'Asignar técnico' : 'Asignar a ${_selected!.fullName}',
        enabled: _selected != null,
        onConfirm: () => Navigator.of(context).pop(TicketMoveInput(technicianId: _selected!.id, technicianName: _selected!.fullName)),
      ),
    ]);
  }
}

class _TechnicianTile extends StatelessWidget {
  const _TechnicianTile({required this.technician, required this.selected, required this.onTap});

  final Technician technician;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = technician.specialization?.trim().isNotEmpty == true ? technician.specialization! : technician.email;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.skyLight.withValues(alpha: .45) : AppColors.canvas,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: selected ? AppColors.steel : Colors.transparent, width: 2)),
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(children: [
              const CircleAvatar(backgroundColor: AppColors.skyLight, child: Icon(Icons.engineering_outlined, color: AppColors.steel)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(technician.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                  if (detail.isNotEmpty) Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate)),
                  Text(technician.isAvailable ? 'Disponible' : 'No disponible', style: theme.textTheme.labelSmall?.copyWith(color: technician.isAvailable ? const Color(0xFF065F46) : AppColors.slate, fontWeight: FontWeight.w700)),
                ]),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.steel),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Barra inferior con el botón de confirmar (desactivado hasta que haya lo necesario).
class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({required this.label, required this.enabled, required this.onConfirm});

  final String label;
  final bool enabled;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x140B1F3A), blurRadius: 12, offset: Offset(0, -3))]),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton.icon(
              onPressed: enabled ? onConfirm : null,
              icon: const Icon(Icons.check_rounded),
              label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ),
        ),
      );
}
