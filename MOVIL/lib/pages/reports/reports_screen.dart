import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/reports/report_export_bloc.dart';
import '../../bloc/reports/report_history_bloc.dart';
import '../../bloc/reports/report_preview_bloc.dart';
import '../../bloc/reports/reports_catalog_bloc.dart';
import '../../core/format/report_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/reports/report_models.dart';
import '../../repositories/reports/reports_repository.dart';
import '../../services/device_services.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/reports/report_export_panel.dart';
import '../../widgets/reports/report_filter_sheet.dart';
import '../../widgets/reports/report_gallery.dart';
import '../../widgets/reports/report_history_section.dart';
import '../../widgets/reports/report_preview_section.dart';
import '../../widgets/reports/reports_header.dart';
import '../../widgets/reports/reports_kpis.dart';
import '../../widgets/reports/reports_tabs.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/error_state.dart';
import '../../widgets/shared/filter_widgets.dart';
import '../../widgets/shared/multi_select_sheet.dart' show FilterButton;
import '../../widgets/shared/skeleton.dart';

/// Reportes: tres cifras arriba y dos vistas. En «Generar reporte» se elige uno de los 4 de la app,
/// se filtra, se elige el formato, se ve cuántos registros tendrá y se exporta en PDF o Excel. En
/// «Historial», las exportaciones ya hechas, por páginas. Requiere `reportes:ver`; exportar requiere
/// además `reportes:exportar`. La autorización real es del backend.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.clock});

  static const path = '/inicio/reportes';

  /// La hora de «ahora» (se inyecta para probar «última exportación»).
  final DateTime Function()? clock;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportsCatalogBloc _catalog;
  late final ReportHistoryBloc _history;
  late final ReportExportBloc _export;
  ReportsTab _tab = ReportsTab.generate;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final repository = context.read<ReportsRepository>();
    final device = context.read<DeviceServices>();
    _catalog = ReportsCatalogBloc(repository: repository)..add(const ReportsCatalogRequested());
    _history = ReportHistoryBloc(repository: repository)..add(const ReportHistoryStarted());
    _export = ReportExportBloc(repository: repository, share: device.share, tempFiles: device.tempFiles);
  }

  @override
  void dispose() {
    unawaited(_catalog.close());
    unawaited(_history.close());
    unawaited(_export.close());
    super.dispose();
  }

  Future<void> _refresh() {
    final catalog = Completer<void>();
    final history = Completer<void>();
    _catalog.add(ReportsCatalogRequested(done: catalog));
    _history.add(ReportHistoryRefreshed(done: history));
    return Future.wait([catalog.future, history.future]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) return const Scaffold(body: Center(child: Text('No encontramos los datos de tu sesión.')));
    return MultiBlocProvider(
      providers: [BlocProvider.value(value: _catalog), BlocProvider.value(value: _history), BlocProvider.value(value: _export)],
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: MantixAppBar(profile: profile),
        drawer: MantixDrawer(profile: profile, selectedPath: ReportsScreen.path),
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.skyLight.withValues(alpha: .45), AppColors.canvas], stops: const [0, .45])),
          child: RefreshIndicator(
            color: AppColors.steel,
            onRefresh: _refresh,
            child: BlocBuilder<ReportsCatalogBloc, ReportsCatalogState>(
              builder: (context, catalog) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                children: [
                  const ReportsHeader(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: BlocBuilder<ReportHistoryBloc, ReportHistoryState>(
                      builder: (context, history) {
                        final ready = history.status == HistoryStatus.success;
                        return ReportsKpis(
                          available: catalog.initialLoading || catalog.unavailable ? null : catalog.reports.length,
                          historyReady: ready,
                          lastExport: ready && history.items.isNotEmpty ? history.items.first.at : null,
                          exports: ready ? history.total : null,
                          now: _now,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg), child: ReportsTabs(selected: _tab, onChanged: (tab) => setState(() => _tab = tab))),
                  const SizedBox(height: AppSpacing.lg),
                  if (_tab == ReportsTab.history)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: BlocBuilder<ReportHistoryBloc, ReportHistoryState>(
                        builder: (context, history) => ReportHistorySection(
                          state: history,
                          pageSize: _history.pageSize,
                          onPage: (page) => _history.add(ReportHistoryPageSelected(page)),
                          onRetry: () => _history.add(const ReportHistoryStarted()),
                        ),
                      ),
                    )
                  else
                    ..._generate(catalog, profile.can('reportes:exportar')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// «Generar reporte»: cargando, error con reintento, vacío o la lista con su espacio de trabajo.
  List<Widget> _generate(ReportsCatalogState state, bool canExport) {
    if (state.initialLoading) {
      return const [Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg), child: Column(children: [Skeleton(height: 72, radius: AppRadius.lg), SizedBox(height: AppSpacing.sm), Skeleton(height: 72, radius: AppRadius.lg), SizedBox(height: AppSpacing.sm), Skeleton(height: 72, radius: AppRadius.lg)]))];
    }
    if (state.unavailable) {
      return [SizedBox(height: 380, child: ErrorState(failure: state.failure!, onRetry: () => _catalog.add(const ReportsCatalogRequested())))];
    }
    final selected = state.selected;
    if (selected == null) {
      return const [SizedBox(height: 320, child: EmptyState(title: 'No hay reportes disponibles', message: 'Cuando tu cuenta tenga reportes habilitados, aparecerán aquí.', icon: Icons.assessment_outlined))];
    }
    return [
      // Un espacio de trabajo por reporte: al cambiar de reporte los filtros empiezan limpios.
      _ReportWorkspace(
        key: ValueKey(selected.key),
        definition: selected,
        maxRows: state.maxRows,
        canExport: canExport,
        gallery: ReportGallery(reports: state.reports, selectedKey: state.selectedKey, onSelect: (key) => _catalog.add(ReportSelected(key))),
      ),
    ];
  }
}

/// La lista de reportes, los filtros, el formato, la vista previa y la exportación de un reporte. Se
/// crea de nuevo al cambiar de reporte, con su propia vista previa.
class _ReportWorkspace extends StatefulWidget {
  const _ReportWorkspace({super.key, required this.definition, required this.maxRows, required this.canExport, required this.gallery});

  final ReportDefinition definition;
  final int maxRows;
  final bool canExport;

  /// La lista de reportes que se muestra arriba (la construye la pantalla).
  final Widget gallery;

  @override
  State<_ReportWorkspace> createState() => _ReportWorkspaceState();
}

class _ReportWorkspaceState extends State<_ReportWorkspace> {
  late final ReportPreviewBloc _preview;
  ReportFormat _format = ReportFormat.pdf;

  @override
  void initState() {
    super.initState();
    _preview = ReportPreviewBloc(repository: context.read<ReportsRepository>(), definition: widget.definition)..add(const ReportPreviewRequested(ReportFilterValues()));
  }

  @override
  void dispose() {
    unawaited(_preview.close());
    super.dispose();
  }

  Future<void> _openFilters() async {
    final picked = await showReportFilterSheet(context, definition: widget.definition, initial: _preview.state.values);
    if (picked != null && picked != _preview.state.values) _preview.add(ReportPreviewRequested(picked));
  }

  Future<void> _toggleChip(String key, String value) async {
    final values = _preview.state.values;
    final next = {...values.selected(key)}..remove(value);
    _preview.add(ReportPreviewRequested(values.withSelected(key, next)));
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
        value: _preview,
        child: BlocBuilder<ReportPreviewBloc, ReportPreviewState>(
          builder: (context, state) {
            final values = state.values;
            final description = describeFilters(widget.definition, values);
            final active = values.activeCount(widget.definition);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                widget.gallery,
                const SizedBox(height: AppSpacing.xs),
                // Los filtros y el formato del reporte elegido, juntos en una tarjeta.
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(color: AppColors.mustard.withValues(alpha: .16), borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.mustard.withValues(alpha: .5))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      FilterButton(count: active, onPressed: _openFilters),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: Text(description, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3))),
                    ]),
                    if (widget.canExport) ...[
                      const SizedBox(height: AppSpacing.md),
                      BlocBuilder<ReportExportBloc, ReportExportState>(
                        builder: (context, export) => ReportFormatField(format: _format, enabled: !export.working, onFormat: (format) => setState(() => _format = format)),
                      ),
                    ],
                  ]),
                ),
                if (_chips(values).isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Wrap(spacing: AppSpacing.sm, children: _chips(values))),
                const SizedBox(height: AppSpacing.md),
                ReportPreviewSection(state: state, maxRows: widget.maxRows, onRetry: () => _preview.add(ReportPreviewRequested(values))),
                if (widget.canExport) ...[
                  const SizedBox(height: AppSpacing.xl),
                  BlocBuilder<ReportExportBloc, ReportExportState>(
                    builder: (context, export) => ReportExportPanel(
                      format: _format,
                      state: export,
                      canExport: state.canExport,
                      onExport: () => context.read<ReportExportBloc>().add(ReportExportRequested(definition: widget.definition, format: _format, values: values)),
                      onDismiss: () => context.read<ReportExportBloc>().add(const ReportExportDismissed()),
                    ),
                  ),
                ],
              ]),
            );
          },
        ),
      );

  /// Un chip por cada opción elegida de los filtros de selección, para quitarla de un toque.
  List<Widget> _chips(ReportFilterValues values) => [
        for (final filter in widget.definition.filters.where((f) => f.kind == ReportFilterKind.multiselect))
          for (final option in filter.options)
            if (values.selected(filter.key).contains(option.value)) ActiveFilterChip(label: option.label, onRemove: () => _toggleChip(filter.key, option.value)),
      ];
}
