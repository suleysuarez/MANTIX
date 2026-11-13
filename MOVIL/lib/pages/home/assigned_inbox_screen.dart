import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/maintenance/upcoming_maintenance_bloc.dart';
import '../../bloc/paged/paged_bloc.dart';
import '../../bloc/requests/assigned_summary_bloc.dart';
import '../../bloc/requests/assigned_tickets_bloc.dart';
import '../../core/routing/home_resolver.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/maintenance/maintenance_models.dart';
import '../../models/requests/request_models.dart';
import '../../repositories/maintenance/maintenance_repository.dart';
import '../../repositories/requests/requests_repository.dart';
import '../../widgets/home/assigned_kpis.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/maintenance/schedule_detail_sheet.dart';
import '../../widgets/maintenance/upcoming_section.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/paginator.dart';
import '../../widgets/shared/skeleton.dart';
import '../../widgets/tickets/ticket_cards.dart';
import '../../widgets/tickets/ticket_detail_sheet.dart';
import '../maintenance/maintenance_screen.dart';
import '../tickets/tickets_screen.dart';

/// Inicio de quien trabaja los tickets asignados («Mi bandeja de trabajo»): cuatro cifras, sus
/// tickets abiertos y sus mantenimientos próximos o vencidos. Todo lo que el servidor entrega ya
/// viene acotado a lo asignado a la persona; los permisos solo deciden qué secciones se enseñan.
/// Cada ticket y cada mantenimiento abre su ficha en una hoja inferior.
class AssignedInboxScreen extends StatefulWidget {
  const AssignedInboxScreen({super.key, this.clock});

  /// La hora de «hoy» (se inyecta para probar).
  final DateTime Function()? clock;

  @override
  State<AssignedInboxScreen> createState() => _AssignedInboxScreenState();
}

class _AssignedInboxScreenState extends State<AssignedInboxScreen> {
  /// Tickets por página (los pide así al servidor) y mantenimientos por página (se reparten aquí).
  static const _ticketsPerPage = 10;
  static const _maintenancePerPage = 5;

  late final AssignedTicketsBloc _tickets;
  late final AssignedSummaryBloc _summary;
  late final UpcomingMaintenanceBloc _upcoming;
  late final bool _canMaintenance;
  int _maintenancePage = 1;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthBloc>().state;
    _canMaintenance = auth is Authenticated && auth.profile.can('mantenimiento:ver');
    final requests = context.read<RequestsRepository>();
    _tickets = AssignedTicketsBloc(repository: requests, pageSize: _ticketsPerPage)..add(const PagedStarted());
    _summary = AssignedSummaryBloc(repository: requests)..add(const AssignedSummaryRequested());
    _upcoming = UpcomingMaintenanceBloc(repository: context.read<MaintenanceRepository>(), clock: widget.clock);
    if (_canMaintenance) _upcoming.add(const UpcomingRequested());
  }

  @override
  void dispose() {
    unawaited(_tickets.close());
    unawaited(_summary.close());
    unawaited(_upcoming.close());
    super.dispose();
  }

  Future<void> _refresh() {
    final summary = Completer<void>();
    final upcoming = Completer<void>();
    _summary.add(AssignedSummaryRequested(done: summary));
    if (_canMaintenance) {
      _upcoming.add(UpcomingRequested(done: upcoming));
    } else {
      upcoming.complete();
    }
    return Future.wait([_tickets.refresh(), summary.future, upcoming.future]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const Scaffold(body: Center(child: Text('No encontramos los datos de tu sesión.')));
    }
    return MultiBlocProvider(
      providers: [BlocProvider.value(value: _tickets), BlocProvider.value(value: _summary), BlocProvider.value(value: _upcoming)],
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: MantixAppBar(profile: profile),
        drawer: MantixDrawer(profile: profile, selectedPath: HomeDestination.assignedInbox.path),
        body: RefreshIndicator(
          color: AppColors.steel,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
            children: [
              const _Header(),
              const SizedBox(height: AppSpacing.md),
              _Kpis(canMaintenance: _canMaintenance),
              const SizedBox(height: AppSpacing.lg),
              _TicketsSection(onRetry: _tickets.refresh),
              if (_canMaintenance) ...[
                const SizedBox(height: AppSpacing.lg),
                BlocBuilder<UpcomingMaintenanceBloc, UpcomingMaintenanceState>(
                  builder: (context, state) => UpcomingSection(
                    title: 'Mis mantenimientos',
                    state: state,
                    onOpen: (event) => showScheduleDetail(context, scheduleId: event.scheduleId, now: _now),
                    onSeeAll: () => context.go(MaintenanceScreen.path),
                    onRetry: () => _upcoming.add(const UpcomingRequested()),
                    onRangeChanged: (range) {
                      setState(() => _maintenancePage = 1);
                      _upcoming.add(UpcomingRangeChanged(range));
                    },
                    limit: _maintenancePerPage,
                    page: _maintenancePage,
                    onPage: (page) => setState(() => _maintenancePage = page),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(width: 5, height: 46, decoration: BoxDecoration(color: AppColors.mustard, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Mi bandeja de trabajo', style: TextStyle(color: AppColors.navy, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1))),
            SizedBox(height: 2),
            Text('Tus tickets y mantenimientos asignados', style: TextStyle(color: AppColors.slate, fontSize: 12)),
          ]),
        ),
      ]);
}

/// Las cuatro cifras: abiertos, en proceso y urgentes (totales del servidor) y mantenimientos vencidos.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.canMaintenance});

  final bool canMaintenance;

  @override
  Widget build(BuildContext context) => BlocBuilder<AssignedSummaryBloc, AssignedSummaryState>(
        builder: (context, summary) => BlocBuilder<UpcomingMaintenanceBloc, UpcomingMaintenanceState>(
          builder: (context, upcoming) {
            final overdue = canMaintenance && upcoming.status == UpcomingStatus.ready ? upcoming.items.where((event) => event.kind == CalendarKind.overdue).length : null;
            return AssignedKpis(
              loading: summary.initialLoading || (canMaintenance && upcoming.initialLoading),
              kpis: [
                AssignedKpi(label: 'TICKETS ABIERTOS', value: summary.open, icon: Icons.assignment_ind_outlined, tone: StatusColors.assigned),
                AssignedKpi(label: 'EN PROCESO', value: summary.inProgress, icon: Icons.settings_outlined, tone: StatusColors.inProgress),
                AssignedKpi(label: 'URGENTES', value: summary.urgent, icon: Icons.priority_high_rounded, tone: StatusColors.critical),
                AssignedKpi(label: 'MANT. VENCIDOS', value: overdue, icon: Icons.event_busy_outlined, tone: StatusColors.high),
              ],
            );
          },
        ),
      );
}

/// «Mis tickets»: los abiertos, de 10 en 10 con el paginador numerado (cada página sustituye a la
/// anterior), y cargando, vacío y error con reintento.
class _TicketsSection extends StatelessWidget {
  const _TicketsSection({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<AssignedTicketsBloc, PagedListState<TicketListItem>>(
      builder: (context, state) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.confirmation_number_outlined, color: AppColors.navy),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Semantics(header: true, child: Text('Mis tickets asignados', maxLines: 2, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)))),
            TextButton(
              onPressed: () => context.go(TicketRoutes.list),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Ver todos'), Icon(Icons.chevron_right_rounded, size: 20)]),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          if (state.status == PagedStatus.loading && state.items.isEmpty)
            Semantics(container: true, label: 'Cargando tus tickets', child: const Column(children: [Skeleton(height: 104, radius: AppRadius.lg), SizedBox(height: AppSpacing.sm), Skeleton(height: 104, radius: AppRadius.lg)]))
          else if (state.status == PagedStatus.failure && state.items.isEmpty)
            EmptyState(icon: Icons.cloud_off_outlined, title: 'No pudimos cargar tus tickets', message: state.failure?.message, actionLabel: 'Reintentar', onAction: onRetry)
          else if (state.items.isEmpty)
            const EmptyState(icon: Icons.task_alt_rounded, title: 'No tienes tickets asignados', message: 'Cuando te asignen uno aparecerá aquí.')
          else ...[
            for (final item in state.items) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: TicketListCard(item: item, onTap: () => showTicketDetail(context, item.id, canAct: item.canAct))),
            if (state.loadMoreFailure != null) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: Text(state.loadMoreFailure!.message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error, fontSize: 12))),
            if (state.info case final info?) Paginator(page: info.page, pageSize: info.pageSize, total: info.total, totalPages: info.totalPages, loading: state.loadingMore, onPage: (page) => context.read<AssignedTicketsBloc>().add(PagedPageSelected(page))),
          ],
        ]);
      },
    );
  }
}
