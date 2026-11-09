import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/equipment/equipment_list_bloc.dart';
import '../../bloc/equipment/equipment_summary_bloc.dart';
import '../../bloc/paged/paged_bloc.dart';
import '../../core/format/equipment_meta.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../models/equipment/equipment_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/shared/app_chip.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/paged_list_view.dart';
import '../../widgets/shared/status_message.dart';

/// Gestión de equipos: contadores por estado que filtran el catálogo, búsqueda y listado.
class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key});

  static const path = '/modulos/equipos';

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  /// Filtros elegidos: estado efímero de la pantalla. Cambiarlos crea un `EquipmentListBloc` nuevo.
  EquipmentGroup _group = EquipmentGroup.all;
  String _search = '';

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  // Con una GlobalKey el campo conserva el foco y el teclado cuando el listado se recrea.
  final _searchKey = GlobalKey();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _applySearch(String value) {
    final term = value.trim();
    if (mounted && term != _search) setState(() => _search = term);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _applySearch(value));
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _applySearch('');
  }

  Future<void> _refresh(BuildContext context) => Future.wait([
        context.read<EquipmentListBloc>().refresh(),
        context.read<EquipmentSummaryBloc>().refresh(),
      ]);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const StatusMessage(icon: Icons.devices_other_rounded, title: 'Equipos', message: 'No encontramos los datos de tu sesión.');
    }
    final filtered = _group != EquipmentGroup.all || _search.isNotEmpty;
    return BlocProvider(
      create: (context) => EquipmentSummaryBloc(repository: context.read<EquipmentRepository>())..add(const EquipmentSummaryStarted()),
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: MantixAppBar(profile: profile),
        drawer: MantixDrawer(profile: profile, selectedPath: EquipmentScreen.path),
        body: BlocProvider(
          key: ValueKey('${_group.name}|$_search'),
          create: (context) => EquipmentListBloc(
            repository: context.read<EquipmentRepository>(),
            statuses: _group.filter,
            search: _search,
          )..add(const PagedStarted()),
          child: BlocBuilder<EquipmentListBloc, PagedListState<Equipment>>(
            builder: (context, state) => PagedListView<Equipment>(
              value: state,
              header: _Header(
                group: _group,
                onGroupSelected: (group) => setState(() => _group = group),
                total: state.status == PagedStatus.success ? state.info?.total : null,
                searchField: _SearchField(
                  key: _searchKey,
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  onSubmitted: (value) {
                    _debounce?.cancel();
                    _applySearch(value);
                  },
                  onClear: _clearSearch,
                ),
              ),
              onRefresh: () => _refresh(context),
              onLoadMore: () => context.read<EquipmentListBloc>().add(const PagedLoadMoreRequested()),
              itemBuilder: (context, item) => _EquipmentCard(item: item),
              empty: EmptyState(
                icon: Icons.devices_other_rounded,
                title: filtered ? 'Ningún equipo coincide con los filtros' : 'Aún no hay equipos registrados',
                message: filtered ? 'Prueba con otra búsqueda o muestra todo el catálogo.' : null,
                actionLabel: filtered ? 'Ver todo el catálogo' : null,
                onAction: filtered
                    ? () {
                        _clearSearch();
                        setState(() => _group = EquipmentGroup.all);
                      }
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.group, required this.onGroupSelected, required this.searchField, this.total});

  final EquipmentGroup group;
  final ValueChanged<EquipmentGroup> onGroupSelected;
  final Widget searchField;

  /// Equipos que coinciden con los filtros (`null` mientras carga).
  final int? total;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: EquipmentColors.info.background, borderRadius: BorderRadius.circular(14)),
        child: Icon(Icons.devices_other_rounded, color: EquipmentColors.info.foreground, size: 24),
      ),
      const SizedBox(height: 12),
      const Text('GESTIÓN DE EQUIPOS', style: TextStyle(color: Color(0xFF0B1F3A), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
      const SizedBox(height: 6),
      const Text(
        'Administra los equipos tecnológicos, consulta sus especificaciones y realiza seguimiento a su ciclo de vida y mantenimiento.',
        style: TextStyle(color: AppColors.slate, fontSize: 12.5, height: 1.4),
      ),
      const SizedBox(height: 16),
      _SummaryCards(group: group, onGroupSelected: onGroupSelected),
      const SizedBox(height: 16),
      searchField,
      if (total != null)
        Padding(
          padding: const EdgeInsets.only(top: 10, left: 4),
          child: Text(total == 1 ? '1 equipo' : '$total equipos', style: const TextStyle(color: AppColors.slate, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
    ],
  );
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.group, required this.onGroupSelected});

  final EquipmentGroup group;
  final ValueChanged<EquipmentGroup> onGroupSelected;

  static String _rate(double? value) => value == null ? '–' : '${value.toStringAsFixed(1).replaceAll('.', ',')}% tasa';

  @override
  Widget build(BuildContext context) => BlocBuilder<EquipmentSummaryBloc, EquipmentSummaryState>(
    builder: (context, state) {
      final summary = state.summary;
      String value(EquipmentGroup g) => summary == null ? '–' : '${summary.count(g)}';
      final cards = [
        _SummaryCard(
          icon: Icons.devices_rounded,
          colors: EquipmentColors.info,
          badge: 'Total',
          value: value(EquipmentGroup.all),
          caption: 'Equipos registrados en inventario',
          action: 'Ver todo',
          actionIcon: Icons.arrow_forward_rounded,
          selected: group == EquipmentGroup.all,
          onTap: () => onGroupSelected(EquipmentGroup.all),
        ),
        _SummaryCard(
          icon: Icons.check_circle_outline_rounded,
          colors: EquipmentColors.ok,
          badge: summary == null ? 'Tasa' : _rate(summary.operationalRate),
          value: value(EquipmentGroup.operational),
          caption: 'Operativos y en disponibilidad',
          action: 'Filtrar operativos',
          actionIcon: Icons.filter_alt_outlined,
          selected: group == EquipmentGroup.operational,
          onTap: () => onGroupSelected(EquipmentGroup.operational),
        ),
        _SummaryCard(
          icon: Icons.build_outlined,
          colors: EquipmentColors.warn,
          badge: 'En curso',
          value: value(EquipmentGroup.maintenance),
          caption: 'Bajo revisión o soporte técnico',
          action: 'Ver equipos en mantenimiento',
          actionIcon: Icons.arrow_forward_rounded,
          selected: group == EquipmentGroup.maintenance,
          onTap: () => onGroupSelected(EquipmentGroup.maintenance),
        ),
        _SummaryCard(
          icon: Icons.warning_amber_rounded,
          colors: EquipmentColors.bad,
          badge: 'Crítico',
          value: value(EquipmentGroup.offline),
          caption: 'Dados de baja, retirados o extraviados',
          action: 'Revisar estos equipos',
          actionIcon: Icons.arrow_forward_rounded,
          selected: group == EquipmentGroup.offline,
          onTap: () => onGroupSelected(EquipmentGroup.offline),
        ),
      ];
      return Column(
        children: [
          GridView(
            // El alto crece con el tamaño de letra del sistema para que nada se corte.
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, mainAxisExtent: 168 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6)),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: cards,
          ),
          if (state.status == SummaryStatus.failure)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.slate),
                const SizedBox(width: 8),
                Expanded(child: Text('No pudimos cargar los contadores. ${state.failure?.message ?? ''}'.trim(), style: const TextStyle(color: AppColors.slate, fontSize: 11))),
                TextButton(onPressed: () => context.read<EquipmentSummaryBloc>().add(const EquipmentSummaryStarted()), child: const Text('Reintentar')),
              ]),
            ),
        ],
      );
    },
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.colors,
    required this.badge,
    required this.value,
    required this.caption,
    required this.action,
    required this.actionIcon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final ChipColors colors;
  final String badge;
  final String value;
  final String caption;
  final String action;
  final IconData actionIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? colors.dot : const Color(0xFFE5EEF6), width: selected ? 1.6 : 1),
            boxShadow: const [BoxShadow(color: Color(0x0C0B1F3A), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, color: colors.dot, size: 19),
                ),
                const Spacer(),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(20)),
                    child: Text(badge, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.foreground, fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(color: Color(0xFF0B1F3A), fontSize: 28, fontWeight: FontWeight.w900, height: 1.05)),
              const SizedBox(height: 2),
              Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 10.5, height: 1.25)),
              const Spacer(),
              const Divider(height: 12, thickness: 1, color: Color(0xFFEEF3F8)),
              Row(children: [
                Expanded(child: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.foreground, fontSize: 10.5, fontWeight: FontWeight.w800))),
                const SizedBox(width: 4),
                Icon(actionIcon, size: 14, color: colors.foreground),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({super.key, required this.controller, required this.focusNode, required this.onChanged, required this.onSubmitted, required this.onClear});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => TextField(
      controller: controller,
      focusNode: focusNode,
      maxLength: 100,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        counterText: '',
        hintText: 'Buscar por código, serie, marca o modelo…',
        hintStyle: const TextStyle(color: AppColors.slate, fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.slate),
        suffixIcon: value.text.isEmpty ? null : IconButton(tooltip: 'Borrar búsqueda', icon: const Icon(Icons.close_rounded, size: 20), onPressed: onClear),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5EEF6))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE5EEF6))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: EquipmentColors.info.dot, width: 1.6)),
      ),
    ),
  );
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.item});

  final Equipment item;

  @override
  Widget build(BuildContext context) {
    final status = equipmentStatusMeta(item.status);
    final lastMaintenance = item.lastMaintenanceAt;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE5EEF6)),
        boxShadow: const [BoxShadow(color: Color(0x0C0B1F3A), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: EquipmentColors.info.background, borderRadius: BorderRadius.circular(13)),
              child: Icon(equipmentCategoryIcon(item.typeCode), color: EquipmentColors.info.foreground, size: 22),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${item.brand} ${item.model}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF153A60), fontSize: 14, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Text(item.assetTag, style: const TextStyle(color: Color(0xFF334155), fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Flexible(child: AppChip(label: status.label, colors: status.colors, semanticPrefix: 'Estado')),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: EquipmentColors.info.background, borderRadius: BorderRadius.circular(20)),
            child: Text(item.typeName, style: TextStyle(color: EquipmentColors.info.foreground, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 20, color: Color(0xFFEEF3F8)),
          _DetailRow(icon: Icons.place_outlined, text: item.locationName ?? 'Sin ubicación'),
          const SizedBox(height: 6),
          _DetailRow(icon: Icons.person_outline_rounded, text: item.custodianName ?? 'Sin custodio'),
          const SizedBox(height: 6),
          _DetailRow(icon: Icons.build_outlined, text: lastMaintenance == null ? 'Sin mantenimientos' : 'Último mantenimiento: ${formatDate(lastMaintenance.toLocal())}'),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 15, color: AppColors.slate),
    const SizedBox(width: 7),
    Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF475569), fontSize: 11.5))),
  ]);
}
