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
import '../../widgets/shared/blurred_sheet.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/error_state.dart';
import '../../widgets/shared/paginator.dart';
import '../../widgets/shared/status_message.dart';
import 'inventory_item_form_sheet.dart';
import 'inventory_detail_sheet.dart';

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
            initialValue: category, decoration: const InputDecoration(labelText: 'Categoría'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('Todas')), for (final option in categories) DropdownMenuItem<String?>(value: option.value, child: Text(option.label))],
            onChanged: (value) => setSheet(() => category = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: status, decoration: const InputDecoration(labelText: 'Disponibilidad'),
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

  // Las hojas cuelgan del Navigator, fuera del BlocProvider de la pantalla: se les pasa el bloc.
  // Se ven sobre la pantalla desenfocada, así el encabezado no se pierde.
  void _create() {
    final bloc = context.read<InventoryBloc>();
    showBlurredSheet<void>(context, heightFactor: .8, builder: (_) => BlocProvider.value(value: bloc, child: const InventoryItemFormSheet()));
  }

  void _edit(InventoryItem item) {
    final bloc = context.read<InventoryBloc>();
    showBlurredSheet<void>(context, heightFactor: .8, builder: (_) => BlocProvider.value(value: bloc, child: InventoryItemFormSheet(item: item)));
  }

  void _open(InventoryItem item) {
    final state = context.read<InventoryBloc>().state;
    final categories = {for (final option in state.options.where((o) => o.kind == 'category')) option.value: option.label};
    showInventoryDetail(
      context, item,
      categoryLabel: categories[item.category] ?? item.category,
      actions: InventoryItemActions(
        onConsume: widget.profile.can('inventario:consumir') ? () => _movement(item, 'out') : null,
        onReceive: widget.profile.can('inventario:editar') ? () => _movement(item, 'in') : null,
        onEdit: widget.profile.can('inventario:editar') ? () => _edit(item) : null,
      ),
    );
  }

  void _movement(InventoryItem item, String kind) {
    final bloc = context.read<InventoryBloc>();
    showBlurredSheet<void>(context, builder: (_) => BlocProvider.value(value: bloc, child: InventoryMovementSheet(item: item, kind: kind)));
  }

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
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(width: 5, height: 46, decoration: BoxDecoration(color: AppColors.mustard, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 9),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Inventario', style: TextStyle(color: AppColors.navy, fontSize: 30, fontWeight: FontWeight.w900, height: 1)),
              SizedBox(height: 4),
              Text('Controla qué hay, qué se gasta y qué toca reponer', style: TextStyle(color: AppColors.slate, fontSize: 11.5)),
            ])),
          ]),
          const SizedBox(height: 12),
          _StockValue(overview: state.overview),
          const SizedBox(height: 8),
          _Kpis(overview: state.overview),
          const SizedBox(height: 10),
          Row(children: [
            if (widget.profile.can('inventario:crear'))
              Expanded(child: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_rounded, size: 17), label: const Text('Nuevo ítem'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, minimumSize: const Size(0, 44), textStyle: const TextStyle(fontWeight: FontWeight.w800), shape: const StadiumBorder()))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: SizedBox(height: 42, child: TextField(
              controller: _search,
              onChanged: (value) { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 350), () => _applyQuery(search: value)); },
              onSubmitted: (value) { _debounce?.cancel(); _applyQuery(search: value); },
              decoration: InputDecoration(hintText: 'Buscar por SKU, nombre…', prefixIcon: const Icon(Icons.search_rounded, color: AppColors.steel, size: 19),
                suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); _applyQuery(search: ''); }, icon: const Icon(Icons.close_rounded))),
            ))),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: 'Filtros', onPressed: () => _filters(state), style: IconButton.styleFrom(backgroundColor: AppColors.skyLight.withValues(alpha: .55), foregroundColor: AppColors.navy), icon: const Icon(Icons.filter_alt_rounded)),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .28), borderRadius: BorderRadius.circular(13)),
            child: Row(children: [
              const Icon(Icons.tune_rounded, color: AppColors.steel, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('Categorías', style: TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.w800))),
              DropdownButtonHideUnderline(child: DropdownButton<String?>(
                value: state.category,
                borderRadius: BorderRadius.circular(12),
                isDense: true,
                items: [const DropdownMenuItem<String?>(value: null, child: Text('Todas')), for (final option in state.options.where((o) => o.kind == 'category')) DropdownMenuItem<String?>(value: option.value, child: Text(option.label))],
                onChanged: (value) => _applyQuery(category: value, status: state.status, clearCategory: value == null),
              )),
            ]),
          ),
          if (state.status != null) ...[
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: InputChip(label: Text(_statusLabel(state.status!)), onDeleted: () => _applyQuery(category: state.category, status: null, clearStatus: true))),
          ],
          const SizedBox(height: 10),
          if (state.loading && state.items.isEmpty)
            const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator(color: AppColors.steel)))
          else if (state.failure != null && state.items.isEmpty)
            ErrorState(failure: state.failure!, onRetry: () => context.read<InventoryBloc>().add(const InventoryStarted()))
          else if (state.items.isEmpty)
            const EmptyState(icon: Icons.inventory_2_outlined, title: 'No hay insumos para mostrar', message: 'Crea un ítem o cambia los filtros.')
          else ...[
            for (final item in state.items) _ItemCard(
              item: item,
              onOpen: () => _open(item),
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
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.skyLight, AppColors.sky], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.skyLight.withValues(alpha: .8)),
      ),
      child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .65), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.inventory_2_outlined, color: AppColors.navy, size: 25)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Valor del stock', style: TextStyle(color: AppColors.navy, fontSize: 10.5, fontWeight: FontWeight.w700)),
          FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(amount, style: const TextStyle(color: AppColors.navy, fontSize: 23, fontWeight: FontWeight.w900, height: 1.1))),
        ])),
        if (overview?.stockChangePct != null) ...[
          Container(width: 1, height: 38, color: AppColors.steel.withValues(alpha: .22)),
          const SizedBox(width: 10),
          _Change(percent: overview!.stockChangePct!),
        ],
      ]),
    );
  }
}

/// Variación del valor del stock frente al periodo anterior: sube en navy con flecha arriba, baja en rojo.
class _Change extends StatelessWidget {
  const _Change({required this.percent});
  final double percent;
  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    final color = up ? AppColors.navy : AppColors.error;
    final text = '${up ? '+' : '−'}${percent.abs().toStringAsFixed(1).replaceAll('.', ',')} %';
    return Column(crossAxisAlignment: CrossAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: color),
          const SizedBox(width: 2),
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
        ]),
      ),
      const SizedBox(height: 2),
      const Text('vs. periodo anterior', style: TextStyle(color: AppColors.steel, fontSize: 8.5, fontWeight: FontWeight.w700)),
    ]);
  }
}

/// Las tres cifras de arriba, cada una con su rayita de avance:
/// «Por reponer» y «Agotados» frente a los ítems activos, y «Consumo» frente al periodo anterior.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.overview});
  final InventoryOverview? overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    double share(int part) => o == null || o.activeItems <= 0 ? 0 : (part / o.activeItems).clamp(0.0, 1.0);
    final consumptionBase = o == null ? 0 : (o.consumptionUnits > o.previousConsumptionUnits ? o.consumptionUnits : o.previousConsumptionUnits);
    final consumption = o == null || consumptionBase <= 0 ? 0.0 : o.consumptionUnits / consumptionBase;
    return Row(children: [
      Expanded(child: _Metric(title: 'Por reponer', value: o?.lowStock.toString() ?? '–', icon: Icons.inventory_2_outlined, color: AppColors.mustard, progress: share(o?.lowStock ?? 0))),
      const SizedBox(width: 6),
      Expanded(child: _Metric(title: 'Agotados', value: o?.outOfStock.toString() ?? '–', icon: Icons.warning_rounded, color: AppColors.error, progress: share(o?.outOfStock ?? 0))),
      const SizedBox(width: 6),
      Expanded(child: _Metric(title: 'Consumo del mes', value: o?.consumptionUnits.toString() ?? '–', icon: Icons.bar_chart_rounded, color: AppColors.steel, progress: consumption)),
    ]);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.title, required this.value, required this.icon, required this.color, required this.progress});
  final String title, value;
  final IconData icon;
  final Color color;
  final double progress;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.skyLight.withValues(alpha: .75))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 27, height: 27, decoration: BoxDecoration(color: color.withValues(alpha: .18), shape: BoxShape.circle), child: Icon(icon, size: 16, color: color)),
        const SizedBox(width: 6),
        Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w900)))),
      ]),
      const SizedBox(height: 4),
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.steel, fontSize: 9.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: AppColors.grey.withValues(alpha: .45), color: color)),
    ]),
  );
}

/// Una fila del listado: icono de la categoría, nombre y SKU, cantidad con su unidad, estado y `>`.
/// Tocarla abre la ficha del ítem, donde están las acciones y el historial.
/// Anchos de las dos columnas de la derecha de cada fila (cantidad y estado).
const double _qtyWidth = 50;
const double _chipWidth = 74;

/// Estado del stock en una pastilla compacta de ancho fijo: el texto se encoge si no cabe.
class _StockChip extends StatelessWidget {
  const _StockChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = stockStatusColors(status);
    final label = stockStatusLabel(status);
    return Semantics(
      label: 'Estado: $label',
      excludeSemantics: true,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: colors.dot, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: TextStyle(color: colors.foreground, fontSize: 10, fontWeight: FontWeight.w800)))),
        ]),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onOpen});
  final InventoryItem item;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    elevation: 0,
    color: AppColors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: BorderSide(color: AppColors.skyLight.withValues(alpha: .75))),
    child: InkWell(
      onTap: onOpen,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9), child: Row(children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .48), borderRadius: BorderRadius.circular(11)), child: Icon(inventoryCategoryIcon(item.category), color: AppColors.steel, size: 21)),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.15)),
          Text(item.sku, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.steel, fontSize: 9.5)),
        ])),
        const SizedBox(width: 4),
        // Columnas de ancho fijo: la cantidad y el estado quedan alineados en todas las filas,
        // sin importar si el texto es corto («En stock») o largo («Por reponer»).
        SizedBox(
          width: _qtyWidth,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(item.stock.toString(), style: const TextStyle(color: AppColors.navy, fontSize: 19, fontWeight: FontWeight.w900, height: 1.05))),
            FittedBox(fit: BoxFit.scaleDown, child: Text(item.stock == 1 ? item.unit : _plural(item.unit), maxLines: 1, style: const TextStyle(color: AppColors.slate, fontSize: 9.5))),
          ]),
        ),
        const SizedBox(width: 4),
        SizedBox(width: _chipWidth, child: _StockChip(status: item.status)),
        const Icon(Icons.chevron_right_rounded, color: AppColors.navy, size: 22),
      ])),
    ),
  );
}

String _statusLabel(String value) => stockStatusLabel(value);

/// «unidad» → «unidades», «caja» → «cajas»: plural sencillo para la etiqueta bajo la cantidad.
String _plural(String unit) {
  final value = unit.trim();
  if (value.isEmpty || value.endsWith('s')) return value;
  return RegExp(r'[aeiouáéíóú]$', caseSensitive: false).hasMatch(value) ? '${value}s' : '${value}es';
}
