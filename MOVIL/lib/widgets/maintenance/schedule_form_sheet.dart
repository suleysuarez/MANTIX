import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/catalogs/technician_search_bloc.dart';
import '../../bloc/equipment/equipment_search_bloc.dart';
import '../../bloc/maintenance/schedule_actions_bloc.dart';
import '../../core/format/maintenance_calendar.dart';
import '../../core/format/maintenance_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/equipment/equipment_models.dart';
import '../../models/technicians/technician_models.dart';
import '../../repositories/equipment/equipment_repository.dart';
import '../../repositories/technicians/technicians_repository.dart';
import '../shared/search_picker_sheet.dart';

/// Elige la fecha y la hora del primer servicio a partir de [initial]; `null` si se cancela.
typedef DateTimePicker = Future<DateTime?> Function(BuildContext context, DateTime initial, DateTime now);

/// El selector del sistema: primero el día y luego la hora.
Future<DateTime?> pickDateAndTime(BuildContext context, DateTime initial, DateTime now) async {
  final first = startOfDay(now);
  final date = await showDatePicker(context: context, initialDate: initial.isBefore(first) ? first : initial, firstDate: first, lastDate: DateTime(now.year + 10, 12, 31), helpText: 'Fecha del primer servicio');
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial), helpText: 'Hora del primer servicio');
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// «Programar mantenimiento»: el formulario de un plan en una hoja inferior. Pide el equipo, el
/// título, cada cuántos días se repite, con cuántos días de antelación se recuerda y la fecha del
/// primer servicio; la descripción, las horas estimadas y el técnico responsable son opcionales
/// (el técnico solo se ofrece con [techniciansRepository], para quien puede ver técnicos; sin él,
/// los recordatorios le llegan a quien programa). Cada error sale bajo su campo cuando la persona
/// ya lo tocó o intentó programar. La hoja sigue abierta mientras se guarda: si el servidor lo
/// rechaza, el motivo sale dentro y lo escrito no se pierde. Devuelve `true` si se programó y
/// `null` si se cerró sin guardar.
Future<bool?> showScheduleForm(
  BuildContext context, {
  required ScheduleActionsBloc actions,
  TechniciansRepository? techniciansRepository,
  DateTime? now,
  DateTimePicker pickDateTime = pickDateAndTime,
}) {
  final equipment = context.read<EquipmentRepository>();
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider.value(value: actions, child: _ScheduleForm(equipmentRepository: equipment, techniciansRepository: techniciansRepository, now: now, pickDateTime: pickDateTime)),
  );
}

class _ScheduleForm extends StatefulWidget {
  const _ScheduleForm({required this.equipmentRepository, required this.techniciansRepository, required this.now, required this.pickDateTime});

  final EquipmentRepository equipmentRepository;
  final TechniciansRepository? techniciansRepository;
  final DateTime? now;
  final DateTimePicker pickDateTime;

  @override
  State<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<_ScheduleForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _interval = TextEditingController(text: '$defaultIntervalDays');
  final _remind = TextEditingController(text: '$defaultRemindDays');
  final _hours = TextEditingController();
  late DateTime _first = defaultFirstDue(_now);
  Equipment? _equipment;
  Technician? _technician;

  /// Un campo enseña su error cuando la persona ya escribió en él o intentó programar.
  final _touched = <String>{};
  bool _submitted = false;

  /// Esta hoja pidió programar y espera su resultado (otras hojas comparten el mismo bloc).
  bool _waiting = false;
  String? _error;

  DateTime get _now => (widget.now ?? DateTime.now());

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _interval.dispose();
    _remind.dispose();
    _hours.dispose();
    super.dispose();
  }

  bool _show(String field) => _submitted || _touched.contains(field);
  void _touch(String field) => setState(() => _touched.add(field));

  String? get _equipmentError => _equipment == null ? 'Este campo es obligatorio.' : null;
  String? get _titleError => planTitleError(_title.text);
  String? get _descriptionError => planDescriptionError(_description.text);
  String? get _intervalError => intervalError(_interval.text);
  String? get _remindError => remindError(_remind.text, _interval.text);
  String? get _firstError => firstDueError(_first, _now);
  String? get _hoursError => hoursError(_hours.text);

  bool get _valid => [_equipmentError, _titleError, _descriptionError, _intervalError, _remindError, _firstError, _hoursError].every((error) => error == null);

  Future<void> _pickEquipment() async {
    final picked = await showSearchPicker<Equipment>(
      context,
      title: 'Selecciona un equipo',
      hint: 'Etiqueta, serie, marca o modelo',
      emptyTitle: 'No encontramos equipos',
      createBloc: (search) => EquipmentSearchBloc(repository: widget.equipmentRepository, search: search),
      itemBuilder: (context, item, select) => ListTile(
        minVerticalPadding: 12,
        tileColor: AppColors.canvas,
        leading: const Icon(Icons.computer_outlined, color: AppColors.steel),
        title: Text(item.assetTag, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${item.brand} ${item.model} · ${item.typeName}', maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: _equipment?.id == item.id ? const Icon(Icons.check_rounded, color: AppColors.steel) : null,
        onTap: select,
      ),
    );
    if (picked != null && mounted) setState(() => _equipment = picked);
  }

  Future<void> _pickTechnician() async {
    final repository = widget.techniciansRepository!;
    final picked = await showSearchPicker<Technician>(
      context,
      title: 'Técnico responsable',
      hint: 'Nombre, correo o especialidad',
      emptyTitle: 'No encontramos técnicos',
      createBloc: (search) => TechnicianSearchBloc(repository: repository, search: search),
      itemBuilder: (context, item, select) => ListTile(
        minVerticalPadding: 12,
        tileColor: AppColors.canvas,
        leading: const Icon(Icons.engineering_outlined, color: AppColors.steel),
        title: Text(item.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: item.specialization == null ? null : Text(item.specialization!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: _technician?.id == item.id ? const Icon(Icons.check_rounded, color: AppColors.steel) : null,
        onTap: select,
      ),
    );
    if (picked != null && mounted) setState(() => _technician = picked);
  }

  Future<void> _pickFirst() async {
    final picked = await widget.pickDateTime(context, _first, _now);
    if (picked != null && mounted) {
      setState(() {
        _first = picked;
        _touched.add('first');
      });
    }
  }

  void _submit() {
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_valid) return;
    _waiting = true;
    context.read<ScheduleActionsBloc>().add(ScheduleCreateRequested(
          equipmentId: _equipment?.id,
          title: _title.text,
          description: _description.text,
          intervalDays: _interval.text,
          remindDays: _remind.text,
          firstDueAt: _first,
          estimatedHours: _hours.text,
          technicianId: _technician?.id,
        ));
  }

  void _onOutcome(BuildContext context, ScheduleActionsState state) {
    final outcome = state.outcome;
    if (outcome == null || !_waiting) return;
    _waiting = false;
    if (outcome.kind == ScheduleOutcomeKind.succeeded) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = outcome.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocConsumer<ScheduleActionsBloc, ScheduleActionsState>(
      listenWhen: (previous, current) => current.outcome != null && previous.outcome != current.outcome,
      listener: _onOutcome,
      builder: (context, state) {
        final busy = state.busy;
        final compact = MediaQuery.textScalerOf(context).scale(1) > 1.15 || MediaQuery.sizeOf(context).width < 340;
        Widget pair(Widget a, Widget b) => compact ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: AppSpacing.md), b]) : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: AppSpacing.md), Expanded(child: b)]);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
            child: Material(
              color: AppColors.canvas,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg + 8)),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const _FormHeader(),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .7))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _Field(
                            icon: Icons.computer_outlined,
                            label: 'Equipo',
                            required: true,
                            error: _show('equipment') ? _equipmentError : null,
                            child: _Selector(text: _equipment == null ? 'Selecciona un equipo...' : '${_equipment!.assetTag} · ${_equipment!.brand} ${_equipment!.model}', placeholder: _equipment == null, error: _show('equipment') && _equipmentError != null, enabled: !busy, onTap: () async {
                              await _pickEquipment();
                              _touch('equipment');
                            }),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _Field(
                            icon: Icons.title_rounded,
                            label: 'Título',
                            required: true,
                            error: _show('title') ? _titleError : null,
                            child: TextField(
                              controller: _title,
                              enabled: !busy,
                              maxLength: planTitleMax,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => _touch('title'),
                              decoration: InputDecoration(hintText: 'Ingresa el título del mantenimiento', counterText: '', errorText: _show('title') ? _titleError : null, errorMaxLines: 2),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _Field(
                            icon: Icons.format_list_bulleted_rounded,
                            label: 'Descripción',
                            error: _show('description') ? _descriptionError : null,
                            child: TextField(
                              controller: _description,
                              enabled: !busy,
                              maxLength: planDescriptionMax,
                              minLines: 3,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: (_) => _touch('description'),
                              decoration: InputDecoration(hintText: 'Describe el mantenimiento...', counterText: '', errorText: _show('description') ? _descriptionError : null, errorMaxLines: 2),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          pair(
                            _Field(
                              icon: Icons.schedule_rounded,
                              label: 'Cada cuántos días',
                              required: true,
                              error: _show('interval') ? _intervalError : null,
                              child: TextField(
                                controller: _interval,
                                enabled: !busy,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')), LengthLimitingTextInputFormatter(5)],
                                textInputAction: TextInputAction.next,
                                onChanged: (_) {
                                  _touch('interval');
                                  _touched.add('remind');
                                },
                                decoration: InputDecoration(errorText: _show('interval') ? _intervalError : null, errorMaxLines: 3),
                              ),
                            ),
                            _Field(
                              icon: Icons.sync_rounded,
                              label: 'Recordar en (días de antelación)',
                              required: true,
                              error: _show('remind') ? _remindError : null,
                              child: TextField(
                                controller: _remind,
                                enabled: !busy,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')), LengthLimitingTextInputFormatter(4)],
                                textInputAction: TextInputAction.next,
                                onChanged: (_) => _touch('remind'),
                                decoration: InputDecoration(errorText: _show('remind') ? _remindError : null, errorMaxLines: 4),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          pair(
                            _Field(
                              icon: Icons.calendar_today_outlined,
                              label: 'Primer servicio',
                              required: true,
                              error: _show('first') ? _firstError : null,
                              child: _Selector(text: formatFormDateTime(_first), icon: Icons.calendar_month_outlined, error: _show('first') && _firstError != null, enabled: !busy, onTap: _pickFirst),
                            ),
                            _Field(
                              icon: Icons.timer_outlined,
                              label: 'Horas estimadas',
                              error: _show('hours') ? _hoursError : null,
                              child: TextField(
                                controller: _hours,
                                enabled: !busy,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [LengthLimitingTextInputFormatter(7)],
                                onChanged: (_) => _touch('hours'),
                                decoration: InputDecoration(hintText: 'Ej. 1.5', errorText: _show('hours') ? _hoursError : null, errorMaxLines: 3),
                              ),
                            ),
                          ),
                          if (widget.techniciansRepository != null) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _Field(
                              icon: Icons.build_rounded,
                              label: 'Técnico responsable',
                              child: _Selector(
                                text: _technician?.fullName ?? 'Sin asignar',
                                placeholder: _technician == null,
                                enabled: !busy,
                                onTap: _pickTechnician,
                                onClear: _technician == null ? null : () => setState(() => _technician = null),
                              ),
                            ),
                            if (_technician == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('Sin técnico, los recordatorios te llegan a ti.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
                              ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.lg),
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: AppRadius.mdAll),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Icon(Icons.error_outline_rounded, size: 18, color: theme.colorScheme.onErrorContainer),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer, height: 1.3))),
                              ]),
                            ),
                          ],
                        ]),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.grey.withValues(alpha: .6)))),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (busy) const Padding(padding: EdgeInsets.only(bottom: AppSpacing.sm), child: LinearProgressIndicator(minHeight: 3, color: AppColors.mustard)),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: busy ? null : () => Navigator.of(context).maybePop(),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: AppColors.navy, backgroundColor: AppColors.skyLight.withValues(alpha: .25), side: const BorderSide(color: AppColors.sky)),
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Cancelar', maxLines: 1)),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: busy ? null : _submit,
                              icon: const Icon(Icons.calendar_today_outlined, size: 20),
                              label: FittedBox(fit: BoxFit.scaleDown, child: Text(busy ? 'Programando…' : 'Programar', maxLines: 1)),
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: AppColors.mustard, foregroundColor: AppColors.navy, textStyle: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Encabezado de la hoja: el icono, la línea mostaza, el título y la explicación.
class _FormHeader extends StatelessWidget {
  const _FormHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.skyLight.withValues(alpha: .55), AppColors.canvas])),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.xs, AppSpacing.md),
      child: Column(children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.grey, borderRadius: AppRadius.pillAll)),
        const SizedBox(height: AppSpacing.md),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.edit_calendar_outlined, size: 40, color: AppColors.navy),
            Container(width: 3, margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2), decoration: BoxDecoration(color: AppColors.mustard, borderRadius: AppRadius.pillAll)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Semantics(header: true, child: Text('Programar mantenimiento', maxLines: 2, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w900, height: 1.1))),
                const SizedBox(height: 2),
                Text('Completa la información del servicio para agendar el mantenimiento.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3)),
              ]),
            ),
            IconButton(tooltip: 'Cerrar', color: AppColors.navy, onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
      ]),
    );
  }
}

/// Un campo con su icono y nombre encima, la marca de obligatorio y, si el campo no puede enseñar
/// su error por sí mismo (los selectores), el error debajo.
class _Field extends StatelessWidget {
  const _Field({required this.icon, required this.label, required this.child, this.required = false, this.error});

  final IconData icon;
  final String label;
  final Widget child;
  final bool required;

  /// Solo para los campos que no son de texto; los de texto lo enseñan ellos.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isText = child is TextField;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 19, color: AppColors.navy)),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: label),
              if (required) TextSpan(text: ' *', style: TextStyle(color: theme.colorScheme.error)),
            ]),
            style: theme.textTheme.labelLarge?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      child,
      if (!isText && error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 15, color: theme.colorScheme.error),
            const SizedBox(width: 5),
            Expanded(child: Text(error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
          ]),
        ),
    ]);
  }
}

/// Un campo que se toca para elegir (equipo, fecha y hora, técnico): muestra lo elegido o el
/// texto de invitación, y con [onClear] un botón para quitarlo.
class _Selector extends StatelessWidget {
  const _Selector({required this.text, required this.onTap, this.placeholder = false, this.icon = Icons.keyboard_arrow_down_rounded, this.error = false, this.enabled = true, this.onClear});

  final String text;
  final VoidCallback onTap;
  final bool placeholder;
  final IconData icon;
  final bool error;
  final bool enabled;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: Material(
        color: AppColors.canvas,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: error ? theme.colorScheme.error : AppColors.grey)),
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(children: [
                Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: placeholder ? AppColors.slate : AppColors.navy, fontWeight: placeholder ? FontWeight.w500 : FontWeight.w700))),
                if (onClear != null)
                  IconButton(tooltip: 'Quitar', visualDensity: VisualDensity.compact, onPressed: enabled ? onClear : null, icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.steel))
                else
                  Icon(icon, color: AppColors.slate),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
