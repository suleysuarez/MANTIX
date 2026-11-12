import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/inventory/inventory_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../models/auth/user_profile.dart';
import '../../models/inventory/inventory_models.dart';
import '../../repositories/inventory/inventory_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/error_state.dart';
import '../../widgets/shared/paginator.dart';
import '../../widgets/shared/status_message.dart';
import 'inventory_item_form_sheet.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});
  static const path = '/modulos/inventario';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) return const StatusMessage(icon: Icons.inventory_2_outlined, title: 'Inventario', message: 'No encontramos los datos de tu sesión.');
    return BlocProvider(
      create: (context) => InventoryBloc(repository: context.read<InventoryRepository>())..add(const InventoryStarted()),
      child: _InventoryView(profile: profile),
    );
  }
}

class _InventoryView extends StatefulWidget {
  const _InventoryView({required this.profile});
  final UserProfile profile;
  @override
  State<_InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<_InventoryView> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() { _debounce?.cancel(); _search.dispose(); super.dispose(); }

  void _applyQuery({String? search, String? category, String? status, bool clearCategory = false, bool clearStatus = false}) {
    final bloc = context.read<InventoryBloc>();
    bloc.add(InventoryQueryChanged(search: search ?? bloc.state.search, category: category, status: status, clearCategory: clearCategory, clearStatus: clearStatus));
  }

  Future<void> _filters(InventoryState state) async {
    String? category = state.category;
    String? status = state.status;
    final categories = state.options.where((o) => o.kind == 'category').toList();
    final result = await showModalBottomSheet<bool>(
      context: context, useSafeArea: true, showDragHandle: true, isScrollControlled: true, backgroundColor: AppColors.white,
      builder: (sheet) => StatefulBuilder(builder: (context, setSheet) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Filtros de inventario', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy)),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            value: category, decoration: const InputDecoration(labelText: 'Categoría'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('Todas')), for (final option in categories) DropdownMenuItem<String?>(value: option.value, child: Text(option.label))],
            onChanged: (value) => setSheet(() => category = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            value: status, decoration: const InputDecoration(labelText: 'Disponibilidad'),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Todos los estados')),
              DropdownMenuItem<String?>(value: 'ok', child: Text('En stock')),
              DropdownMenuItem<String?>(value: 'low', child: Text('Por reponer')),
              DropdownMenuItem<String?>(value: 'out', child: Text('Agotados')),
            ],
            onChanged: (value) => setSheet(() => status = value),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => setSheet(() { category = null; status = null; }), child: const Text('Limpiar'))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: FilledButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Aplicar'))),
          ]),
        ]),
      )),
    );
    if (result == true && mounted) _applyQuery(category: category, status: status, clearCategory: category == null, clearStatus: status == null);
  }

  void _create() => showModalBottomSheet<void>(context: context, useSafeArea: true, isScrollControlled: true, showDragHandle: true, backgroundColor: AppColors.canvas, builder: (_) => const InventoryItemFormSheet());

  void _movement(InventoryItem item, String kind) => showModalBottomSheet<void>(context: context, useSafeArea: true, isScrollControlled: true, showDragHandle: true, backgroundColor: AppColors.canvas, builder: (_) => InventoryMovementSheet(item: item, kind: kind));

  @override
  Widget build(BuildContext context) => BlocListener<InventoryBloc, InventoryState>(
    listenWhen: (a, b) => a.notice != b.notice && b.notice != null,
    listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.notice!))),
    child: Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: MantixAppBar(profile: widget.profile),
      drawer: MantixDrawer(profile: widget.profile, selectedPath: InventoryScreen.path),
      body: BlocBuilder<InventoryBloc, InventoryState>(builder: (context, state) => RefreshIndicator(
        onRefresh: () async => context.read<InventoryBloc>().add(const InventoryStarted()),
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 18, 16, 28), children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('INVENTARIO', style: TextStyle(color: AppColors.navy, fontSize: 23, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text('Controla existencias, costos y reposición de insumos.', style: TextStyle(color: AppColors.slate, fontSize: 12)),
            ])),
            if (widget.profile.can('inventario:crear'))
              FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Nuevo ítem'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(horizontal: 10))),
          ]),
          const SizedBox(height: 16),
          _StockValue(overview: state.overview),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _Metric(title: 'Por reponer', value: state.overview?.lowStock.toString() ?? '–', icon: Icons.inventory_outlined, mustard: true)),
            const SizedBox(width: 8),
            Expanded(child: _Metric(title: 'Agotados', value: state.overview?.outOfStock.toString() ?? '–', icon: Icons.remove_shopping_cart_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _Metric(title: 'Consumo · 30 días', value: state.overview?.consumptionUnits.toString() ?? '–', icon: Icons.trending_down_rounded)),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: TextField(
              controller: _search,
              onChanged: (value) { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 350), () => _applyQuery(search: value)); },
              onSubmitted: (value) { _debounce?.cancel(); _applyQuery(search: value); },
              decoration: InputDecoration(hintText: 'Buscar por SKU, nombre o proveedor…', prefixIcon: const Icon(Icons.search_rounded, color: AppColors.steel),
                suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); _applyQuery(search: ''); }, icon: const Icon(Icons.close_rounded))),
            )),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: 'Filtros', onPressed: () => _filters(state), style: IconButton.styleFrom(backgroundColor: AppColors.skyLight.withValues(alpha: .55), foregroundColor: AppColors.navy), icon: const Icon(Icons.tune_rounded)),
          ]),
          if (state.category != null || state.status != null) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              if (state.category != null) InputChip(label: Text(state.category!), onDeleted: () => _applyQuery(category: null, status: state.status, clearCategory: true)),
              if (state.status != null) InputChip(label: Text(_statusLabel(state.status!)), onDeleted: () => _applyQuery(category: state.category, status: null, clearStatus: true)),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Text('INSUMOS', style: TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w900))),
            Text('\${state.total} registros', style: const TextStyle(color: AppColors.slate, fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          if (state.loading && state.items.isEmpty)
            const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator(color: AppColors.steel)))
          else if (state.failure != null && state.items.isEmpty)
            ErrorState(failure: state.failure!, onRetry: () => context.read<InventoryBloc>().add(const InventoryStarted()))
          else if (state.items.isEmpty)
            const EmptyState(icon: Icons.inventory_2_outlined, title: 'No hay insumos para mostrar', message: 'Crea un ítem o cambia los filtros.')
          else ...[
            for (final item in state.items) _ItemCard(
              item: item, canConsume: widget.profile.can('inventario:consumir'), canReceive: widget.profile.can('inventario:editar'),
              onConsume: () => _movement(item, 'out'), onReceive: () => _movement(item, 'in'),
            ),
            const SizedBox(height: 10),
            Paginator(page: state.page, pageSize: state.pageSize, total: state.total, totalPages: state.totalPages, loading: state.loading,
              onPage: (page) => context.read<InventoryBloc>().add(InventoryPageChanged(page))),
          ],
          if (state.failure != null && state.items.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(state.failure!.message, style: const TextStyle(color: AppColors.error, fontSize: 12))),
        ]),
      )),
    ),
  );
}

class _StockValue extends StatelessWidget {
  const _StockValue({required this.overview});
  final InventoryOverview? overview;
  @override
  Widget build(BuildContext context) {
    final amount = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 2).format(double.tryParse(overview?.stockValue ?? '') ?? 0);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.skyLight), boxShadow: const [BoxShadow(color: Color(0x0A0B1F3A), blurRadius: 12, offset: Offset(0, 3))]),
      child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .45), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.steel)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('VALOR DEL STOCK', style: TextStyle(color: AppColors.steel, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .5)),
          const SizedBox(height: 3),
          FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(amount, style: const TextStyle(color: AppColors.navy, fontSize: 27, fontWeight: FontWeight.w900))),
          const Text('Valorización actual de existencias', style: TextStyle(color: AppColors.slate, fontSize: 10.5)),
        ])),
        const Icon(Icons.trending_up_rounded, color: AppColors.mustard, size: 24),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.title, required this.value, required this.icon, this.mustard = false});
  final String title, value;
  final IconData icon;
  final bool mustard;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 88),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.grey.withValues(alpha: .7))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: mustard ? AppColors.mustard : AppColors.steel),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w900)),
      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.steel, fontSize: 10, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.canConsume, required this.canReceive, required this.onConsume, required this.onReceive});
  final InventoryItem item;
  final bool canConsume, canReceive;
  final VoidCallback onConsume, onReceive;
  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(item.status);
    final color = item.status == 'low' ? AppColors.mustard : AppColors.steel;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: AppColors.skyLight.withValues(alpha: .7))),
      child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .42), borderRadius: BorderRadius.circular(12)), child: Icon(_categoryIcon(item.category), color: AppColors.steel)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w800)),
            Text('SKU: ' + item.sku, style: const TextStyle(color: AppColors.slate, fontSize: 10.5)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(item.stock.toString(), style: const TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w900)),
            Text(item.unit, style: const TextStyle(color: AppColors.slate, fontSize: 10)),
          ]),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 10.5, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (item.location?.isNotEmpty == true) Flexible(child: Text(item.location!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 10))),
        ]),
        if (canConsume || canReceive) ...[
          const Divider(height: 16, color: AppColors.grey),
          Row(children: [
            if (canConsume) Expanded(child: OutlinedButton.icon(onPressed: item.stock > 0 ? onConsume : null, icon: const Icon(Icons.south_west_rounded, size: 15), label: const Text('Consumir'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), foregroundColor: AppColors.steel, side: const BorderSide(color: AppColors.skyLight)))),
            if (canConsume && canReceive) const SizedBox(width: 8),
            if (canReceive) Expanded(child: FilledButton.tonalIcon(onPressed: onReceive, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Entrada'), style: FilledButton.styleFrom(minimumSize: const Size(0, 38), backgroundColor: AppColors.mustard.withValues(alpha: .22), foregroundColor: AppColors.navy))),
          ]),
        ],
      ])),
    );
  }
}

String _statusLabel(String value) => switch (value) { 'ok' => 'En stock', 'low' => 'Por reponer', 'out' => 'Agotado', _ => value };
IconData _categoryIcon(String value) => switch (value) { 'spare_part' => Icons.memory_rounded, 'consumable' => Icons.water_drop_outlined, 'accessory' => Icons.cable_rounded, 'tool' => Icons.build_outlined, _ => Icons.category_outlined };
