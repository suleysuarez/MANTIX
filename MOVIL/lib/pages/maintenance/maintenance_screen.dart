import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/maintenance/maintenance_calendar_bloc.dart';
import '../../bloc/maintenance/upcoming_maintenance_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../repositories/maintenance/maintenance_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/maintenance/maintenance_calendar_card.dart';
import '../../widgets/maintenance/maintenance_cards.dart';
import '../../widgets/maintenance/maintenance_header.dart';
import '../../widgets/maintenance/schedule_detail_sheet.dart';
import '../../widgets/maintenance/schedules_tab.dart';
import '../../widgets/maintenance/upcoming_section.dart';

/// Mantenimientos preventivos: el calendario del mes con sus servicios marcados, los próximos
/// mantenimientos y, en «Lista», todos los planes por páginas. Cada servicio o plan abre su ficha
/// en una hoja inferior. Requiere `mantenimiento:ver`; la ruta lo exige y la autorización real es
/// del backend. Quien solo ve lo asignado recibe únicamente sus planes.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, this.clock});

  static const path = '/mantenimiento';

  /// La hora de «hoy» (se inyecta para probar el calendario).
  final DateTime Function()? clock;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  late final MaintenanceCalendarBloc _calendar;
  late final UpcomingMaintenanceBloc _upcoming;
  bool _list = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final repository = context.read<MaintenanceRepository>();
    _calendar = MaintenanceCalendarBloc(repository: repository, clock: widget.clock)..add(const CalendarRequested());
    _upcoming = UpcomingMaintenanceBloc(repository: repository, clock: widget.clock)..add(const UpcomingRequested());
  }

  @override
  void dispose() {
    unawaited(_calendar.close());
    unawaited(_upcoming.close());
    super.dispose();
  }

  Future<void> _refresh() {
    final calendar = Completer<void>();
    final upcoming = Completer<void>();
    _calendar.add(CalendarRequested(done: calendar));
    _upcoming.add(UpcomingRequested(done: upcoming));
    return Future.wait([calendar.future, upcoming.future]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) {
      return const Scaffold(body: Center(child: Text('No encontramos los datos de tu sesión.')));
    }
    final top = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const MaintenanceHeader(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: _ViewToggle(list: _list, onChanged: (list) => setState(() => _list = list)),
      ),
      const SizedBox(height: AppSpacing.md),
    ]);
    return MultiBlocProvider(
      providers: [BlocProvider.value(value: _calendar), BlocProvider.value(value: _upcoming)],
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: MantixAppBar(profile: profile),
        drawer: MantixDrawer(profile: profile, selectedPath: MaintenanceScreen.path),
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.skyLight.withValues(alpha: .45), AppColors.canvas], stops: const [0, .45])),
          child: _list
              ? SchedulesTab(top: top, now: _now, canFilterByTechnician: profile.can('tecnicos:ver'), onOpen: (schedule) => showScheduleDetail(context, scheduleId: schedule.id, now: _now))
              : RefreshIndicator(
                  color: AppColors.steel,
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    children: [
                      top,
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _CalendarSection(now: _now, onOpen: (id) => showScheduleDetail(context, scheduleId: id, now: _now)),
                          const SizedBox(height: AppSpacing.lg),
                          BlocBuilder<UpcomingMaintenanceBloc, UpcomingMaintenanceState>(
                            builder: (context, state) => UpcomingSection(
                              state: state,
                              onOpen: (event) => showScheduleDetail(context, scheduleId: event.scheduleId, now: _now),
                              onSeeAll: () => setState(() => _list = true),
                              onRetry: () => _upcoming.add(const UpcomingRequested()),
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// El conmutador Calendario / Lista: el seleccionado va en navy.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.list, required this.onChanged});

  final bool list;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Vista de mantenimientos',
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.calendar_month_outlined, size: 18), label: FittedBox(fit: BoxFit.scaleDown, child: Text('Calendario'))),
            ButtonSegment(value: true, icon: Icon(Icons.view_list_outlined, size: 18), label: FittedBox(fit: BoxFit.scaleDown, child: Text('Lista'))),
          ],
          selected: {list},
          onSelectionChanged: (selection) => onChanged(selection.first),
          style: SegmentedButton.styleFrom(
            backgroundColor: AppColors.white,
            foregroundColor: AppColors.steel,
            selectedBackgroundColor: AppColors.navy,
            selectedForegroundColor: AppColors.white,
            side: const BorderSide(color: AppColors.grey),
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      );
}

/// El calendario y, debajo, los servicios del día elegido.
class _CalendarSection extends StatelessWidget {
  const _CalendarSection({required this.now, required this.onOpen});

  final DateTime now;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) => BlocBuilder<MaintenanceCalendarBloc, MaintenanceCalendarState>(
        builder: (context, state) {
          final bloc = context.read<MaintenanceCalendarBloc>();
          final selected = state.selectedKey;
          final events = state.selectedEvents;
          final theme = Theme.of(context);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MaintenanceCalendarCard(
              anchor: state.anchor,
              today: now,
              byDay: state.byDay,
              selectedKey: selected,
              loading: state.loading,
              truncated: state.truncated,
              errorMessage: state.status == CalendarStatus.failure ? 'No pudimos cargar el calendario. ${state.failure?.message ?? ''}'.trim() : null,
              onPrevious: () => bloc.add(const CalendarMonthShifted(-1)),
              onNext: () => bloc.add(const CalendarMonthShifted(1)),
              onToday: () => bloc.add(const CalendarTodayRequested()),
              onSelect: (key) => bloc.add(CalendarDaySelected(key)),
              onRetry: () => bloc.add(const CalendarRequested()),
            ),
            if (selected != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(children: [
                const Icon(Icons.event_note_outlined, color: AppColors.navy),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Semantics(header: true, child: Text('Servicios del ${dayHeading(selected)}', maxLines: 2, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)))),
              ]),
              const SizedBox(height: AppSpacing.sm),
              if (events.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .6))),
                  child: Text('No hay servicios este día.', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel)),
                )
              else
                for (final event in events) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: MaintenanceEventCard(event: event, onTap: () => onOpen(event.scheduleId))),
            ],
          ]);
        },
      );
}
