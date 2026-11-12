import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/technicians/technician_actions_bloc.dart';
import '../../core/format/technicians_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/equipment/equipment_models.dart';
import '../../models/technicians/technician_models.dart';
import '../equipment/custodian_picker.dart';
import '../users/user_cards.dart' show UserAvatar;

/// Formulario de un técnico en una hoja inferior. Sin [technician] registra uno nuevo (pide el
/// usuario, la especialización y la tarifa); con él edita su especialización y su tarifa. La
/// hoja sigue abierta mientras se guarda: si el servidor lo rechaza, el motivo sale dentro y lo
/// escrito no se pierde. Devuelve `true` si se guardó y `null` si se cerró sin guardar.
Future<bool?> showTechnicianForm(BuildContext context, {required TechnicianActionsBloc actions, Technician? technician}) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(value: actions, child: _TechnicianForm(technician: technician)),
    );

class _TechnicianForm extends StatefulWidget {
  const _TechnicianForm({this.technician});

  final Technician? technician;

  @override
  State<_TechnicianForm> createState() => _TechnicianFormState();
}

class _TechnicianFormState extends State<_TechnicianForm> {
  late final _specialization = TextEditingController(text: widget.technician?.specialization ?? '');
  late final _rate = TextEditingController(text: rateInput(widget.technician?.hourlyRate));
  CustodianCandidate? _user;

  /// El error de cada campo solo se enseña cuando la persona ya escribió en él o intentó guardar.
  bool _specializationTouched = false;
  bool _rateTouched = false;
  bool _userMissing = false;

  /// Esta hoja pidió algo y espera su resultado (otras hojas comparten el mismo bloc).
  bool _waiting = false;
  String? _error;

  bool get _creating => widget.technician == null;

  @override
  void dispose() {
    _specialization.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _pickUser() async {
    final choice = await showCustodianPicker(context, selected: _user, title: 'Usuario del perfil de técnico', allowClear: false);
    if (choice?.candidate == null || !mounted) return;
    setState(() {
      _user = choice!.candidate;
      _userMissing = false;
    });
  }

  void _submit() {
    setState(() {
      _specializationTouched = true;
      _rateTouched = true;
      _userMissing = _creating && _user == null;
      _error = null;
    });
    if (_userMissing || specializationError(_specialization.text) != null || rateError(_rate.text) != null) return;
    _waiting = true;
    final technician = widget.technician;
    context.read<TechnicianActionsBloc>().add(
          technician == null
              ? TechnicianCreateRequested(userId: _user?.id, specialization: _specialization.text, rate: _rate.text)
              : TechnicianEditRequested(technician, specialization: _specialization.text, rate: _rate.text),
        );
  }

  void _onOutcome(BuildContext context, TechnicianActionsState state) {
    final outcome = state.outcome;
    if (outcome == null || !_waiting) return;
    _waiting = false;
    if (outcome.kind == TechnicianOutcomeKind.succeeded) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = outcome.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final technician = widget.technician;
    final specializationProblem = _specializationTouched ? specializationError(_specialization.text) : null;
    final rateProblem = _rateTouched ? rateError(_rate.text) : null;
    final rateValid = rateError(_rate.text) == null;
    final tags = specialties(Technician(id: 0, fullName: '', specialization: _specialization.text));
    return BlocConsumer<TechnicianActionsBloc, TechnicianActionsState>(
      listenWhen: (previous, current) => current.outcome != null && previous.outcome != current.outcome,
      listener: _onOutcome,
      builder: (context, state) {
        final busy = state.busy;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
            child: Material(
              color: AppColors.canvas,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg + 8)),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _Banner(
                  icon: _creating ? Icons.person_add_alt_1_rounded : Icons.edit_rounded,
                  title: _creating ? 'Registrar técnico' : 'Editar perfil',
                  subtitle: _creating ? 'Abre un perfil técnico a un usuario existente' : technician!.fullName,
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      if (_creating) ...[
                        _Section(
                          icon: Icons.person_search_rounded,
                          title: 'Usuario',
                          required: true,
                          children: [
                            _UserTile(user: _user, error: _userMissing, onTap: busy ? null : _pickUser),
                            if (_userMissing)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('Selecciona el usuario al que pertenece el perfil de técnico.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                              ),
                            const SizedBox(height: AppSpacing.sm),
                            const _Hint('Solo aparecen usuarios activos. Un usuario puede tener un único perfil de técnico.'),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _Section(
                        icon: Icons.handyman_outlined,
                        title: 'Especialización',
                        children: [
                          TextField(
                            controller: _specialization,
                            enabled: !busy,
                            maxLength: maxSpecialization,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() => _specializationTouched = true),
                            decoration: InputDecoration(
                              hintText: 'Ej: Hardware, Redes',
                              prefixIcon: const Icon(Icons.folder_open_rounded, color: AppColors.steel),
                              errorText: specializationProblem,
                              errorMaxLines: 2,
                            ),
                          ),
                          if (tags.isEmpty)
                            const _Hint('Separa varias especialidades con comas.')
                          else
                            Wrap(spacing: 6, runSpacing: 6, children: [for (final tag in tags) _Tag(tag)]),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _Section(
                        icon: Icons.payments_outlined,
                        title: 'Tarifa por hora',
                        accent: true,
                        children: [
                          TextField(
                            controller: _rate,
                            enabled: !busy,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [LengthLimitingTextInputFormatter(14)],
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() => _rateTouched = true),
                            onSubmitted: (_) => busy ? null : _submit(),
                            decoration: InputDecoration(
                              hintText: '0,00',
                              prefixIcon: const Icon(Icons.attach_money_rounded, color: AppColors.navy),
                              suffixText: 'por hora',
                              errorText: rateProblem,
                              errorMaxLines: 2,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _Hint(
                            _rate.text.trim().isEmpty || !rateValid
                                ? 'Opcional. Sin negativos, con coma o punto y hasta dos decimales.'
                                : 'Se guardará como ${formatRate(parseRate(_rate.text))} por hora.',
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.md),
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
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: AppColors.steel),
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Cancelar', maxLines: 1)),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: busy ? null : _submit,
                              icon: Icon(_creating ? Icons.person_add_alt_1_rounded : Icons.check_rounded, size: 20),
                              label: FittedBox(fit: BoxFit.scaleDown, child: Text(busy ? 'Guardando…' : (_creating ? 'Registrar técnico' : 'Guardar cambios'), maxLines: 1)),
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: AppColors.navy, foregroundColor: AppColors.mustard),
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

/// Cabecera navy de la hoja, con el asa, el icono en mostaza, el título y el botón de cerrar.
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.navy, AppColors.bannerLight]),
        border: Border(bottom: BorderSide(color: AppColors.mustard, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.xs, AppSpacing.md),
      child: Column(children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .35), borderRadius: AppRadius.pillAll)),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .12), borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.skyLight.withValues(alpha: .35))),
            child: Icon(icon, color: AppColors.mustard, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.white, fontWeight: FontWeight.w800))),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.skyLight, height: 1.3)),
            ]),
          ),
          IconButton(tooltip: 'Cerrar', color: AppColors.white, onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_rounded)),
        ]),
      ]),
    );
  }
}

/// Tarjeta de un campo: icono de color, título y, si es obligatorio, su marca. [accent] usa el
/// mostaza en vez del azul claro.
class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children, this.required = false, this.accent = false});

  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool required;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: accent ? AppColors.mustard.withValues(alpha: .7) : AppColors.skyLight.withValues(alpha: .8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: accent ? AppColors.mustard.withValues(alpha: .32) : AppColors.skyLight.withValues(alpha: .55), borderRadius: AppRadius.smAll),
            child: Icon(icon, size: 19, color: accent ? AppColors.navy : AppColors.steel),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800))),
          if (required)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.mustard, borderRadius: AppRadius.pillAll),
              child: Text('Obligatorio', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: AppSpacing.md),
        ...children,
      ]),
    );
  }
}

/// El usuario elegido (con sus iniciales) o la invitación a buscar uno.
class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.error, required this.onTap});

  final CustodianCandidate? user;
  final bool error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = user;
    return Semantics(
      button: true,
      label: picked == null ? 'Buscar usuario por nombre o correo' : 'Usuario elegido: ${picked.fullName}. Toca para cambiarlo',
      excludeSemantics: true,
      child: Material(
        color: picked == null ? AppColors.canvas : AppColors.skyLight.withValues(alpha: .3),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: error ? theme.colorScheme.error : (picked == null ? AppColors.grey : AppColors.steel))),
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(children: [
                if (picked == null) const Icon(Icons.search_rounded, color: AppColors.slate) else UserAvatar(name: picked.fullName, size: 38),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: picked == null
                      ? Text('Buscar usuario por nombre o correo…', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.steel))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(picked.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800)),
                          Text(picked.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.steel)),
                        ]),
                ),
                Icon(picked == null ? Icons.keyboard_arrow_down_rounded : Icons.swap_horiz_rounded, color: AppColors.steel),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.info_outline_rounded, size: 14, color: AppColors.slate)),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.steel, height: 1.3))),
      ]);
}

/// Cada especialidad escrita, como etiqueta, para ver cómo quedará.
class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: AppRadius.pillAll),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_outlined, size: 14, color: AppColors.steel),
          const SizedBox(width: 4),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w700))),
        ]),
      );
}
