import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/inventory/inventory_movements_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/inventory/inventory_models.dart';
import '../../repositories/inventory/inventory_repository.dart';
import '../../widgets/shared/app_chip.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/error_state.dart';
import '../../widgets/shared/mantix_sheet.dart';

/// Qué puede hacer la persona con un ítem y cómo se hace. Las acciones cierran la ficha y luego
/// abren su formulario desde la pantalla, que es la que tiene el Bloc.
class InventoryItemActions {
  const InventoryItemActions({this.onConsume, this.onReceive, this.onEdit});
  final VoidCallback? onConsume;
  final VoidCallback? onReceive;
  final VoidCallback? onEdit;
}

/// Colores del estado de stock: verde en stock, naranja por reponer, rojo agotado.
ChipColors stockStatusColors(String status) => switch (status) {
      'out' => StatusColors.critical,
      'low' => StatusColors.high,
      _ => StatusColors.resolved,
    };

String stockStatusLabel(String status) => switch (status) { 'ok' => 'En stock', 'low' => 'Por reponer', 'out' => 'Agotado', _ => status };

IconData inventoryCategoryIcon(String value) => switch (value) {
      'spare_part' => Icons.memory_rounded,
      'consumable' => Icons.water_drop_outlined,
      'accessory' => Icons.cable_rounded,
      'tool' => Icons.build_outlined,
      _ => Icons.category_outlined,
    };

/// Abre la ficha de [item]: datos, nivel de stock, acciones y su historial de movimientos.
///
/// La hoja cuelga del Navigator, fuera de los providers de la pantalla: recibe el repositorio.
Future<void> showInventoryDetail(BuildContext context, InventoryItem item, {required String categoryLabel, InventoryItemActions actions = const InventoryItemActions()}) {
  final repository = context.read<InventoryRepository>();
  return showMantixSheet<void>(
    context,
    title: 'Detalle del ítem',
    builder: (_, controller) => BlocProvider(
      create: (_) => InventoryMovementsBloc(repository: repository, itemId: item.id)..add(const InventoryMovementsStarted()),
      child: _DetailBody(item: item, categoryLabel: categoryLabel, actions: actions, controller: controller),
    ),
  );
}

class _DetailBody extends StatefulWidget {
  const _DetailBody({required this.item, required this.categoryLabel, required this.actions, required this.controller});
  final InventoryItem item;
  final String categoryLabel;
  final InventoryItemActions actions;
  final ScrollController controller;
  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  @override
  void initState() { super.initState(); widget.controller.addListener(_onScroll); }

  @override
  void dispose() { widget.controller.removeListener(_onScroll); super.dispose(); }

  void _onScroll() {
    final position = widget.controller.position;
    if (position.extentAfter < 300) context.read<InventoryMovementsBloc>().add(const InventoryMovementsMoreRequested());
  }

  void _run(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final actions = widget.actions;
    return BlocBuilder<InventoryMovementsBloc, InventoryMovementsState>(builder: (context, state) {
      final bloc = context.read<InventoryMovementsBloc>();
      final created = state.reachedEnd ? item.createdAt : null;
      return ListView(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
        children: [
          _Header(item: item),
          const SizedBox(height: AppSpacing.md),
          _LevelBar(item: item),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: _Stat(icon: Icons.warning_amber_rounded, label: 'Mínimo', value: '${item.minStock}', tint: AppColors.mustard)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _Stat(icon: Icons.bar_chart_rounded, label: 'Máximo', value: item.maxStock?.toString() ?? '—', tint: AppColors.sky)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _Stat(icon: Icons.payments_outlined, label: 'Costo unit.', value: _money(item.unitCost), tint: AppColors.skyLight)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          _Stat(icon: Icons.account_balance_wallet_outlined, label: 'Valor en stock', value: _money(item.stockValue), tint: AppColors.mustard, wide: true),
          const SizedBox(height: AppSpacing.md),
          _InfoCard(rows: [
            (Icons.grid_view_rounded, 'Categoría', widget.categoryLabel),
            (Icons.place_outlined, 'Ubicación', item.location),
            (Icons.local_shipping_outlined, 'Proveedor', item.supplier),
            if (item.description != null && item.description!.trim().isNotEmpty) (Icons.notes_rounded, 'Descripción', item.description),
          ]),
          if (actions.onConsume != null || actions.onReceive != null || actions.onEdit != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              if (actions.onConsume != null) Expanded(child: FilledButton.icon(
                onPressed: item.stock > 0 ? () => _run(actions.onConsume!) : null,
                icon: const Icon(Icons.north_west_rounded, size: 17), label: const Text('Consumir'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: AppColors.white, minimumSize: const Size(0, 44)),
              )),
              if (actions.onConsume != null && actions.onReceive != null) const SizedBox(width: AppSpacing.sm),
              if (actions.onReceive != null) Expanded(child: FilledButton.icon(
                onPressed: () => _run(actions.onReceive!),
                icon: const Icon(Icons.south_east_rounded, size: 17), label: const Text('Entrada'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, minimumSize: const Size(0, 44)),
              )),
            ]),
            if (actions.onEdit != null) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => _run(actions.onEdit!),
                icon: const Icon(Icons.edit_outlined, size: 17), label: const Text('Editar ítem'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: AppColors.navy, side: const BorderSide(color: AppColors.steel)),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(children: [
            Container(width: 4, height: 18, decoration: BoxDecoration(color: AppColors.mustard, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 8),
            const Text('Movimientos', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          if (state.loading && state.items.isEmpty)
            const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator(color: AppColors.steel)))
          else if (state.failure != null && state.items.isEmpty)
            ErrorState(failure: state.failure!, onRetry: () => bloc.add(const InventoryMovementsStarted()))
          else if (state.items.isEmpty && created == null)
            const EmptyState(icon: Icons.swap_vert_rounded, title: 'Aún no hay movimientos', message: 'Las entradas y los consumos de este ítem aparecerán aquí.')
          else ...[
            for (final movement in state.items) _MovementTile(movement: movement, unit: item.unit),
            if (created != null) _CreationTile(date: created),
          ],
          if (state.loadingMore) const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: CircularProgressIndicator(color: AppColors.steel, strokeWidth: 2.5))),
          if (state.failure != null && state.items.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Column(children: [
              Text(state.failure!.message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error, fontSize: 12)),
              TextButton(onPressed: () => bloc.add(const InventoryMovementsMoreRequested()), child: const Text('Reintentar')),
            ]),
          ),
        ],
      );
    });
  }
}

String _money(String value) {
  final number = double.tryParse(value) ?? 0;
  final fixed = number.toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '\$$digits.${parts.last}';
}

/// Cabecera de color: icono de la categoría, nombre, SKU, estado y el stock en grande.
class _Header extends StatelessWidget {
  const _Header({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [AppColors.skyLight, AppColors.sky], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Row(children: [
      Container(width: 54, height: 54, decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(16)), child: Icon(inventoryCategoryIcon(item.category), size: 28, color: AppColors.navy)),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900, height: 1.15)),
        const SizedBox(height: 2),
        Text(item.sku, style: const TextStyle(color: AppColors.steel, fontSize: 11.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        AppChip(label: stockStatusLabel(item.status), colors: stockStatusColors(item.status), semanticPrefix: 'Estado'),
      ])),
      const SizedBox(width: AppSpacing.sm),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${item.stock}', style: const TextStyle(color: AppColors.navy, fontSize: 34, fontWeight: FontWeight.w900, height: 1)),
        Text(item.unit, style: const TextStyle(color: AppColors.steel, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    ]),
  );
}

/// Barra del nivel de stock (`level_pct` del servidor), del color del estado.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final pct = item.levelPct;
    if (pct == null) return const SizedBox.shrink();
    final colors = stockStatusColors(item.status);
    final fraction = (pct / 100).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.skyLight.withValues(alpha: .75))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Nivel de stock', style: TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w800))),
          Text('${pct.round()} %', style: TextStyle(color: colors.foreground, fontSize: 12.5, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: AppRadius.pillAll, child: LinearProgressIndicator(value: fraction, minHeight: 8, backgroundColor: AppColors.grey.withValues(alpha: .5), color: colors.dot)),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.tint, this.wide = false});
  final IconData icon;
  final String label, value;
  final Color tint;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final iconBox = Container(width: 32, height: 32, decoration: BoxDecoration(color: tint.withValues(alpha: .35), shape: BoxShape.circle), child: Icon(icon, size: 17, color: AppColors.navy));
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.steel, fontSize: 10.5, fontWeight: FontWeight.w700)),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900))),
    ]);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.skyLight.withValues(alpha: .75))),
      child: wide
          ? Row(children: [iconBox, const SizedBox(width: 10), Expanded(child: text)])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [iconBox, const SizedBox(height: 6), text]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});
  final List<(IconData, String, String?)> rows;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.skyLight.withValues(alpha: .75))),
    child: Column(children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) Divider(height: 1, color: AppColors.grey.withValues(alpha: .5)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(rows[i].$1, size: 18, color: AppColors.steel),
            const SizedBox(width: 10),
            SizedBox(width: 84, child: Text(rows[i].$2, style: const TextStyle(color: AppColors.steel, fontSize: 12, fontWeight: FontWeight.w700))),
            Expanded(child: Text(rows[i].$3 == null || rows[i].$3!.trim().isEmpty ? 'Sin definir' : rows[i].$3!, style: TextStyle(color: rows[i].$3 == null || rows[i].$3!.trim().isEmpty ? AppColors.slate : AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w700))),
          ]),
        ),
      ],
    ]),
  );
}

String _kindLabel(InventoryMovement movement) {
  if (movement.isInitialLoad) return 'Alta del ítem · carga inicial';
  return switch (movement.kind) { 'in' => 'Entrada', 'out' => 'Consumo', _ => 'Ajuste' };
}

IconData _kindIcon(InventoryMovement movement) {
  if (movement.isInitialLoad) return Icons.add_box_outlined;
  return switch (movement.kind) { 'in' => Icons.south_east_rounded, 'out' => Icons.north_west_rounded, _ => Icons.tune_rounded };
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.unit});
  final InventoryMovement movement;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final out = movement.quantity < 0;
    final tone = movement.kind == 'out' ? AppColors.navy : movement.kind == 'adjust' ? AppColors.sky : AppColors.mustard;
    final amount = '${movement.quantity > 0 ? '+' : ''}${movement.quantity}';
    final detail = [
      if (movement.createdAt != null) formatDateTime(movement.createdAt!),
      if (movement.createdBy != null && movement.createdBy!.isNotEmpty) movement.createdBy!,
    ].join(' · ');
    final note = movement.isInitialLoad ? null : movement.notes;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.skyLight.withValues(alpha: .75))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 34, height: 34, decoration: BoxDecoration(color: tone.withValues(alpha: movement.kind == 'out' ? .1 : .32), borderRadius: BorderRadius.circular(10)), child: Icon(_kindIcon(movement), size: 18, color: AppColors.navy)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_kindLabel(movement), style: const TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w800)),
          if (detail.isNotEmpty) Text(detail, style: const TextStyle(color: AppColors.slate, fontSize: 10.5)),
          if (note != null && note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(note, style: const TextStyle(color: AppColors.steel, fontSize: 11))),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$amount $unit', style: TextStyle(color: out ? AppColors.error : AppColors.navy, fontSize: 14, fontWeight: FontWeight.w900)),
          Text('Quedó en ${movement.stockAfter}', style: const TextStyle(color: AppColors.slate, fontSize: 10)),
        ]),
      ]),
    );
  }
}

/// Cierra el historial con el momento en que se creó el ítem, lo haya o no con existencias.
class _CreationTile extends StatelessWidget {
  const _CreationTile({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(children: [
      Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), shape: BoxShape.circle), child: const Icon(Icons.flag_outlined, size: 18, color: AppColors.steel)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ítem creado', style: TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w800)),
        Text(formatDateTime(date), style: const TextStyle(color: AppColors.slate, fontSize: 10.5)),
      ])),
    ]),
  );
}
