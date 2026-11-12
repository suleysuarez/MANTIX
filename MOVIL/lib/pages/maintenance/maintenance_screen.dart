import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/maintenance/maintenance_calendar_bloc.dart';
import '../../bloc/maintenance/schedule_actions_bloc.dart';
import '../../bloc/maintenance/upcoming_maintenance_bloc.dart';
import '../../core/format/maintenance_calendar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../repositories/maintenance/maintenance_repository.dart';
import '../../repositories/technicians/technicians_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/maintenance/maintenance_agenda.dart';
import '../../widgets/maintenance/maintenance_calendar_card.dart';
import '../../widgets/maintenance/maintenance_cards.dart';
import '../../widgets/maintenance/maintenance_header.dart';
import '../../widgets/maintenance/schedule_form_sheet.dart';
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
  late final ScheduleActionsBloc _actions;
  _MaintenanceView _view = _MaintenanceView.calendar;

  /// Lunes de la semana que se ve en «Semana».
  late DateTime _weekStart = startOfWeek(_now);

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final repository = context.read<MaintenanceRepository>();
    _calendar = MaintenanceCalendarBloc(repository: repository, clock: widget.clock)..add(const CalendarRequested());
    _upcoming = UpcomingMaintenanceBloc(repository: repository, clock: widget.clock)..add(const UpcomingRequested());
    _actions = ScheduleActionsBloc(repository: repository, clock: widget.clock);
  }

  @override
  void dispose() {
    unawaited(_calendar.close());
    unawaited(_upcoming.close());
    unawaited(_actions.close());
    super.dispose();
  }

  /// El resultado de cada acción en un aviso: navy si salió bien, rojo si no. Lo que ni se pidió
  /// (un dato no válido) ya se explica dentro de la hoja. El calendario, los próximos y la lista se
  /// recargan solos cuando algo cambia.
  void _onOutcome(BuildContext context, ScheduleActionsState state) {
    final outcome = state.outcome!;
    if (outcome.kind == ScheduleOutcomeKind.blocked) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(outcome.message), backgroundColor: outcome.isError ? AppColors.error : AppColors.navy));
  }

  void _setView(_MaintenanceView view) {
    setState(() => _view = view);
    if (view == _MaintenanceView.week) _coverWeek();
  }

  /// La cuadrícula del calendario cubre las semanas completas de su mes: si la semana elegida cae
  /// en otro mes (la miramos por su jueves, como el calendario ISO), se mueve el mes del calendario.
  void _coverWeek() {
    final target = monthStart(addDays(_weekStart, 3));
    final anchor = _calendar.state.anchor;
    final months = (target.year - anchor.year) * 12 + target.month - anchor.month;
    if (months != 0) _calendar.add(CalendarMonthShifted(months.sign));
  }

  void _shiftWeek(int direction) {
    setState(() => _weekStart = addDays(_weekStart, 7 * direction));
    _coverWeek();
  }

  void _weekToday() {
    setState(() => _weekStart = startOfWeek(_now));
    _coverWeek();
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
    final canEdit = profile.can('mantenimiento:editar');
    // Programar exige además elegir el equipo, que se busca con `equipos:ver`.
    final canCreate = profile.can('mantenimiento:crear') && profile.can('equipos:ver');
    void openPlan(int id) => showScheduleDetail(context, scheduleId: id, now: _now, actions: _actions, canEdit: canEdit);
    final top = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MaintenanceHeader(
        action: canCreate
            ? _ProgramButton(onPressed: () => showScheduleForm(context, actions: _actions, now: _now, techniciansRepository: profile.can('tecnicos:ver') ? context.read<TechniciansRepository>() : null))
            : null,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: _ViewPills(view: _view, onChanged: _setView),
      ),
      const SizedBox(height: AppSpacing.md),
    ]);
    return MultiBlocProvider(
      providers: [BlocProvider.value(value: _calendar), BlocProvider.value(value: _upcoming)],
      child: BlocListener<ScheduleActionsBloc, ScheduleActionsState>(
        bloc: _actions,
        listenWhen: (previous, current) => current.outcome != null && previous.outcome != current.outcome,
        listener: _onOutcome,
        child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: MantixAppBar(profile: profile),
        drawer: MantixDrawer(profile: profile, selectedPath: MaintenanceScreen.path),
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.skyLight.withValues(alpha: .45), AppColors.canvas], stops: const [0, .45])),
          child: _view == _MaintenanceView.list
              ? SchedulesTab(top: top, now: _now, canFilterByTechnician: profile.can('tecnicos:ver'), onOpen: (schedule) => openPlan(schedule.id))
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
                          if (_view == _MaintenanceView.month)
                            _MonthAgenda(now: _now, onOpen: openPlan)
                          else if (_view == _MaintenanceView.week)
                            _WeekAgenda(now: _now, weekStart: _weekStart, onPrevious: () => _shiftWeek(-1), onNext: () => _shiftWeek(1), onToday: _weekToday, onOpen: openPlan)
                          else ...[
                          _CalendarSection(now: _now, onOpen: openPlan),
                          const SizedBox(height: AppSpacing.lg),
                          BlocBuilder<UpcomingMaintenanceBloc, UpcomingMaintenanceState>(
                            builder: (context, state) => UpcomingSection(
                              state: state,
                              onOpen: (event) => openPlan(event.scheduleId),
                              onSeeAll: () => setState(() => _view = _MaintenanceView.list),
                              onRetry: () => _upcoming.add(const UpcomingRequested()),
                              onRangeChanged: (range) => _upcoming.add(UpcomingRangeChanged(range)),
                            ),
                          ),
                          ],
                        ]),
                      ),
                    ],
                  ),
                ),
        ),
      ),
      ),
    );
  }
}

/// «Programar mantenimiento»: el botón mostaza del encabezado, con texto navy.
class _ProgramButton extends StatelessWidget {
  const _ProgramButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Programar mantenimiento', maxLines: 1)),
        style: FilledButton.styleFrom(backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, minimumSize: const Size(0, 50), shape: const StadiumBorder(), textStyle: const TextStyle(fontWeight: FontWeight.w800)),
      );
}

enum _MaintenanceView { calendar, list, month, week }

/// Las vistas como píldoras: Calendario, Lista, Mes y Semana. La elegida va en navy con texto blanco.
class _ViewPills extends StatelessWidget {
  const _ViewPills({required this.view, required this.onChanged});

  final _MaintenanceView view;
  final ValueChanged<_MaintenanceView> onChanged;

  static const _options = [
    (_MaintenanceView.calendar, 'Calendario', Icons.calendar_month_outlined),
    (_MaintenanceView.list, 'Lista', Icons.view_list_outlined),
    (_MaintenanceView.month, 'Mes', Icons.calendar_view_month_outlined),
    (_MaintenanceView.week, 'Semana', Icons.calendar_view_week_outlined),
  ];

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Vista de mantenimientos',
        child: Row(children: [
          for (var i = 0; i < _options.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _Pill(label: _options[i].$2, icon: _options[i].$3, selected: view == _options[i].$1, onTap: () => onChanged(_options[i].$1))),
          ],
        ]),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.white : AppColors.steel;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.navy : AppColors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.navy : AppColors.skyLight)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 17, color: foreground),
                  const SizedBox(width: 4),
                  Text(label, maxLines: 1, style: TextStyle(color: foreground, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Mes»: los servicios del mes del calendario, día por día, con flechas para cambiar de mes.
class _MonthAgenda extends StatelessWidget {
  const _MonthAgenda({required this.now, required this.onOpen});

  final DateTime now;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) => BlocBuilder<MaintenanceCalendarBloc, MaintenanceCalendarState>(
        builder: (context, state) {
          final bloc = context.read<MaintenanceCalendarBloc>();
          return MaintenanceAgenda(
            title: monthTitle(state.anchor),
            days: [for (final day in monthGrid(state.anchor, today: now)) if (day.inMonth) day.date],
            byDay: state.byDay,
            today: now,
            hideEmptyDays: true,
            isCurrent: state.anchor == monthStart(now),
            loading: state.loading,
            errorMessage: state.status == CalendarStatus.failure ? 'No pudimos cargar el mes. ${state.failure?.message ?? ''}'.trim() : null,
            previousLabel: 'Mes anterior',
            nextLabel: 'Mes siguiente',
            onPrevious: () => bloc.add(const CalendarMonthShifted(-1)),
            onNext: () => bloc.add(const CalendarMonthShifted(1)),
            onToday: () => bloc.add(const CalendarTodayRequested()),
            onRetry: () => bloc.add(const CalendarRequested()),
            onOpen: onOpen,
          );
        },
      );
}

/// «Semana»: los siete días de la semana elegida (de lunes a domingo), con flechas para cambiar de semana.
class _WeekAgenda extends StatelessWidget {
  const _WeekAgenda({required this.now, required this.weekStart, required this.onPrevious, required this.onNext, required this.onToday, required this.onOpen});

  final DateTime now;
  final DateTime weekStart;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) => BlocBuilder<MaintenanceCalendarBloc, MaintenanceCalendarState>(
        builder: (context, state) => MaintenanceAgenda(
          title: weekTitle(weekStart),
          days: [for (var i = 0; i < 7; i++) addDays(weekStart, i)],
          byDay: state.byDay,
          today: now,
          isCurrent: weekStart == startOfWeek(now),
          loading: state.loading,
          errorMessage: state.status == CalendarStatus.failure ? 'No pudimos cargar la semana. ${state.failure?.message ?? ''}'.trim() : null,
          previousLabel: 'Semana anterior',
          nextLabel: 'Semana siguiente',
          onPrevious: onPrevious,
          onNext: onNext,
          onToday: onToday,
          onRetry: () => context.read<MaintenanceCalendarBloc>().add(const CalendarRequested()),
          onOpen: onOpen,
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
