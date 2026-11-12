import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/settings/settings_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/settings/settings_models.dart';
import '../../repositories/settings/settings_repository.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  static const path = '/configuracion';
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsBloc _bloc;
  @override
  void initState() {
    super.initState();
    _bloc = SettingsBloc(repository: context.read<SettingsRepository>())..add(const SettingsStarted());
  }
  @override
  void dispose() { unawaited(_bloc.close()); super.dispose(); }

  void _onState(BuildContext context, SettingsState state) {
    final message = state.notice ?? state.failure?.message;
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: state.failure == null ? AppColors.navy : AppColors.error));
  }

  Future<void> _editOrganization(SettingsState state) async {
    final controller = TextEditingController(text: state.organization?.companyName ?? 'Mantix');
    final key = GlobalKey<FormState>();
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Nombre de la organización'),
      content: Form(key: key, child: TextFormField(controller: controller, autofocus: true, maxLength: 150,
        decoration: const InputDecoration(labelText: 'Nombre de la empresa'),
        validator: (v) => (v ?? '').trim().length < 2 ? 'Ingresa al menos 2 caracteres.' : null)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, controller.text.trim().replaceAll(RegExp(r'\s+'), ' ')); }, child: const Text('Guardar')),
      ],
    ));
    controller.dispose();
    if (value != null && mounted) _bloc.add(OrganizationSaveRequested(value));
  }

  Future<void> _openCatalogs(bool canEdit) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => BlocProvider.value(value: _bloc, child: _CatalogSheet(canEdit: canEdit)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final profile = auth is Authenticated ? auth.profile : null;
    if (profile == null) return const Scaffold(body: Center(child: Text('No encontramos los datos de tu sesión.')));
    final canEdit = profile.can('configuracion:editar');
    return BlocProvider.value(value: _bloc, child: BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (a, b) => a.notice != b.notice || (a.failure != b.failure && b.failure != null),
      listener: _onState,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: MantixAppBar(profile: profile),
        drawer: MantixDrawer(profile: profile, selectedPath: SettingsScreen.path),
        body: BlocBuilder<SettingsBloc, SettingsState>(builder: (context, state) => RefreshIndicator(
          color: AppColors.steel,
          onRefresh: () { final done = Completer<void>(); _bloc.add(SettingsRefreshRequested(done)); return done.future; },
          child: ListView(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
            physics: const AlwaysScrollableScrollPhysics(), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Configuración', style: TextStyle(color: AppColors.navy, fontSize: 23, fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text('Administra los datos esenciales y revisa el estado de Mantix.', style: TextStyle(color: AppColors.steel, fontSize: 12)),
              ])),
              IconButton.filledTonal(tooltip: 'Actualizar', onPressed: state.loading ? null : () => _bloc.add(const SettingsRefreshRequested()),
                icon: const Icon(Icons.refresh_rounded), style: IconButton.styleFrom(backgroundColor: AppColors.skyLight.withValues(alpha: .55), foregroundColor: AppColors.steel)),
            ]),
            const SizedBox(height: AppSpacing.lg),
            if (state.loading && state.health == null)
              const _Panel(child: Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: AppColors.steel))))
            else if (state.failure != null && state.health == null)
              _LoadError(message: state.failure!.message, onRetry: () => _bloc.add(const SettingsStarted()))
            else if (state.health != null) ...[
              _Metrics(health: state.health!),
              const SizedBox(height: AppSpacing.md),
              _SystemCard(health: state.health!),
              const SizedBox(height: AppSpacing.md),
              _OrganizationCard(organization: state.organization, canEdit: canEdit, onEdit: () => _editOrganization(state)),
              const SizedBox(height: AppSpacing.md),
              _CatalogCard(categories: state.categories, priorities: state.priorities, canEdit: canEdit, onOpen: () => _openCatalogs(canEdit)),
              const SizedBox(height: AppSpacing.md),
              _AuditCard(entries: state.health!.audit.recent),
              const SizedBox(height: AppSpacing.md),
              _RuntimeCard(environment: state.health!.environment),
              if (state.loading) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 2, color: AppColors.mustard, backgroundColor: AppColors.skyLight)),
            ],
          ]),
        )),
      ),
    ));
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.health});
  final SystemHealth health;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const _Title('Resumen administrativo', 'Indicadores clave de la plataforma.'),
    const SizedBox(height: 9),
    GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: 2.05, children: [
      _Metric('Usuarios activos', health.users.active.toString(), 'de ${health.users.total} cuentas', Icons.groups_outlined),
      _Metric('Roles activos', health.roles.where((r) => r.isActive).length.toString(), 'perfiles de acceso', Icons.admin_panel_settings_outlined),
      _Metric('Actividad en 24 h', health.audit.last24h.toString(), 'acciones registradas', Icons.history_rounded),
      _Metric('Sin rol asignado', health.users.withoutRole.toString(), health.users.withoutRole == 0 ? 'sin pendientes' : 'requieren autorización', Icons.person_search_outlined, mustard: health.users.withoutRole > 0),
    ]),
  ]);
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.detail, this.icon, {this.mustard = false});
  final String label, value, detail;
  final IconData icon;
  final bool mustard;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.grey.withValues(alpha: .75))),
    child: Row(children: [
      Container(width: 34, height: 34, decoration: BoxDecoration(color: mustard ? AppColors.mustard.withValues(alpha: .22) : AppColors.skyLight.withValues(alpha: .55), borderRadius: AppRadius.smAll),
        child: Icon(icon, size: 18, color: mustard ? AppColors.navy : AppColors.steel)),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 20, height: 1.1, fontWeight: FontWeight.w900)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontSize: 10, fontWeight: FontWeight.w800)),
        Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 9)),
      ])),
    ]),
  );
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.health});
  final SystemHealth health;
  @override
  Widget build(BuildContext context) {
    final color = health.overall == 'ok' ? AppColors.steel : health.overall == 'error' ? AppColors.error : AppColors.mustard;
    final label = health.overall == 'ok' ? 'Operativo' : health.overall == 'error' ? 'Requiere atención' : 'Revisar componentes';
    return _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const _IconTile(Icons.monitor_heart_outlined),
        const SizedBox(width: 10),
        const Expanded(child: _Title('Estado del sistema', 'Conexiones y servicios principales.')),
        Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: AppRadius.pillAll),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 5),
            Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 10, fontWeight: FontWeight.w800))])),
      ]),
      const SizedBox(height: 10),
      for (final item in health.integrations) _IntegrationRow(item),
      const SizedBox(height: 6),
      Text('Última revisión: ${DateFormat('dd/MM/yyyy · HH:mm').format(health.generatedAt.toLocal())}', style: const TextStyle(color: AppColors.slate, fontSize: 10)),
    ]));
  }
}

class _IntegrationRow extends StatelessWidget {
  const _IntegrationRow(this.item);
  final IntegrationHealth item;
  @override
  Widget build(BuildContext context) {
    final color = item.status == 'ok' ? AppColors.steel : item.status == 'disabled' ? AppColors.slate : item.status == 'error' ? AppColors.error : AppColors.mustard;
    final label = switch (item.status) { 'ok' => 'Conectado', 'disabled' => 'Desactivado', 'error' => 'Error', _ => 'Advertencia' };
    return Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.name, style: const TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.w700)),
        Text(item.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 10)),
      ])),
      Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
      if (item.latencyMs != null) Padding(padding: const EdgeInsets.only(left: 7), child: Text('${item.latencyMs!.round()} ms', style: const TextStyle(color: AppColors.slate, fontSize: 10))),
    ]));
  }
}

class _OrganizationCard extends StatelessWidget {
  const _OrganizationCard({required this.organization, required this.canEdit, required this.onEdit});
  final OrganizationSettings? organization;
  final bool canEdit;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => _Panel(child: Row(children: [
    const _IconTile(Icons.apartment_outlined), const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Organización', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w900)),
      Text(organization?.companyName ?? 'Mantix', style: const TextStyle(color: AppColors.steel, fontSize: 12, fontWeight: FontWeight.w700)),
      const Text('Nombre que aparece en los reportes exportados.', style: TextStyle(color: AppColors.slate, fontSize: 10)),
    ])),
    if (canEdit) IconButton(tooltip: 'Editar organización', onPressed: onEdit, icon: const Icon(Icons.edit_outlined, color: AppColors.steel)),
  ]));
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.categories, required this.priorities, required this.canEdit, required this.onOpen});
  final List<CategoryAdmin> categories;
  final List<PriorityAdmin> priorities;
  final bool canEdit;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const _IconTile(Icons.tune_rounded), const SizedBox(width: 10), const Expanded(child: _Title('Catálogos operativos', 'Clasificación de solicitudes y tickets.'))]),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: _CountTile('Categorías', categories.where((c) => c.isActive).length, categories.length)),
      const SizedBox(width: 9),
      Expanded(child: _CountTile('Prioridades', priorities.where((p) => p.isActive).length, priorities.length)),
    ]),
    const SizedBox(height: 11),
    SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: onOpen, icon: Icon(canEdit ? Icons.settings_outlined : Icons.visibility_outlined, size: 17),
      label: Text(canEdit ? 'Administrar catálogos' : 'Consultar catálogos'),
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.steel, side: const BorderSide(color: AppColors.skyLight), minimumSize: const Size(0, 44)))),
  ]));
}

class _CountTile extends StatelessWidget {
  const _CountTile(this.label, this.active, this.total);
  final String label;
  final int active, total;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: AppColors.canvas, borderRadius: AppRadius.smAll),
    child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.slate, fontSize: 10, fontWeight: FontWeight.w700)),
      Text('$active', style: const TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w900)),
    ])), Text('/ $total', style: const TextStyle(color: AppColors.slate, fontSize: 11))]));
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.entries});
  final List<AuditEntry> entries;
  @override
  Widget build(BuildContext context) => _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Row(children: [ _IconTile(Icons.history_rounded), SizedBox(width: 10), Expanded(child: _Title('Actividad reciente', 'Últimos movimientos administrativos.')) ]),
    const SizedBox(height: 7),
    if (entries.isEmpty) const Text('Aún no hay actividad registrada.', style: TextStyle(color: AppColors.slate, fontSize: 11)),
    for (final entry in entries.take(4)) Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
      Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.mustard, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_auditLabel(entry.action), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontSize: 11, fontWeight: FontWeight.w800)),
        Text('${entry.by ?? 'Sistema'} · ${entry.entityType}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 9.5)),
      ])),
      if (entry.at != null) Text(DateFormat('dd/MM HH:mm').format(entry.at!.toLocal()), style: const TextStyle(color: AppColors.slate, fontSize: 9)),
    ])),
  ]));
}

class _RuntimeCard extends StatelessWidget {
  const _RuntimeCard({required this.environment});
  final EnvironmentInfo environment;
  @override
  Widget build(BuildContext context) => _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Información del servicio', style: TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w900)),
    const SizedBox(height: 7),
    _InfoLine('Entorno', environment.name), _InfoLine('Versión API', environment.version),
    _InfoLine('Límite por adjunto', '${environment.maxUploadMb} MB'),
    _InfoLine('Avisos preventivos', 'Cada ${environment.reminderIntervalMinutes} min'),
    _InfoLine('Tareas automáticas', environment.schedulerEnabled ? 'Habilitadas' : 'Deshabilitadas'),
  ]));
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
    Expanded(child: Text(label, style: const TextStyle(color: AppColors.slate, fontSize: 10.5))),
    Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 10.5, fontWeight: FontWeight.w700)),
  ]));
}

class _Title extends StatelessWidget {
  const _Title(this.title, [this.subtitle]);
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w900)),
    if (subtitle != null) Text(subtitle!, style: const TextStyle(color: AppColors.slate, fontSize: 10)),
  ]);
}

class _IconTile extends StatelessWidget {
  const _IconTile(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(width: 37, height: 37, decoration: BoxDecoration(color: AppColors.skyLight.withValues(alpha: .5), borderRadius: AppRadius.smAll), child: Icon(icon, color: AppColors.steel, size: 20));
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.lgAll, border: Border.all(color: AppColors.grey.withValues(alpha: .7)),
      boxShadow: const [BoxShadow(color: Color(0x080B172A), blurRadius: 10, offset: Offset(0, 2))]), child: child);
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => _Panel(child: Column(children: [
    const Icon(Icons.cloud_off_outlined, color: AppColors.mustard, size: 30), const SizedBox(height: 8),
    Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.steel, fontSize: 12)),
    const SizedBox(height: 10), FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
  ]));
}

class _CatalogSheet extends StatelessWidget {
  const _CatalogSheet({required this.canEdit});
  final bool canEdit;
  @override
  Widget build(BuildContext context) => SafeArea(child: FractionallySizedBox(heightFactor: .9, child: Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 10), child: Row(children: [
      const Expanded(child: Text('Catálogos operativos', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w900))),
      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
    ])),
    Expanded(child: BlocBuilder<SettingsBloc, SettingsState>(builder: (context, state) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Row(children: [const Expanded(child: Text('Categorías de solicitud', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w900))),
        if (canEdit) TextButton.icon(onPressed: () => _createCategory(context), icon: const Icon(Icons.add_rounded, size: 17), label: const Text('Nueva'))]),
      const Text('Clasifican las solicitudes. Las que ya tienen registros se deben desactivar, no eliminar.', style: TextStyle(color: AppColors.slate, fontSize: 10)),
      const SizedBox(height: 8),
      for (final category in state.categories) _CategoryRow(category: category, canEdit: canEdit),
      const Divider(height: 25),
      const Text('Prioridades de tickets', style: TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w900)),
      const Text('Define el nivel de urgencia y el tiempo objetivo de resolución.', style: TextStyle(color: AppColors.slate, fontSize: 10)),
      const SizedBox(height: 8),
      for (final priority in state.priorities) _PriorityRow(priority: priority, canEdit: canEdit),
    ]))),
  ])));

  Future<void> _createCategory(BuildContext context) async {
    final code = TextEditingController(); final name = TextEditingController(); final key = GlobalKey<FormState>();
    final result = await showDialog<(String, String)>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Nueva categoría'),
      content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v) => (v ?? '').trim().length < 3 ? 'Usa al menos 3 caracteres.' : null),
        TextFormField(controller: code, decoration: const InputDecoration(labelText: 'Identificador', hintText: 'ej. redes'), validator: (v) => RegExp(r'^[a-z][a-z_]{1,29}$').hasMatch((v ?? '').trim()) ? null : 'Minúsculas y guion bajo (2–30 caracteres).'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, (code.text.trim(), name.text.trim())); }, child: const Text('Crear'))],
    ));
    code.dispose(); name.dispose();
    if (result != null && context.mounted) context.read<SettingsBloc>().add(CategoryCreateRequested(code: result.$1, name: result.$2));
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.canEdit});
  final CategoryAdmin category; final bool canEdit;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.smAll, border: Border.all(color: AppColors.grey)),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(category.name, style: const TextStyle(color: AppColors.navy, fontSize: 11.5, fontWeight: FontWeight.w800)),
        Text('${category.code} · ${category.usage} solicitudes', style: const TextStyle(color: AppColors.slate, fontSize: 9.5)),
      ])),
      if (canEdit) ...[
        IconButton(tooltip: 'Renombrar', visualDensity: VisualDensity.compact, onPressed: () => _rename(context), icon: const Icon(Icons.edit_outlined, size: 17, color: AppColors.steel)),
        Switch.adaptive(value: category.isActive, activeThumbColor: AppColors.mustard, onChanged: (v) => context.read<SettingsBloc>().add(CategoryUpdateRequested(id: category.id, isActive: v))),
      ] else Text(category.isActive ? 'Activa' : 'Inactiva', style: const TextStyle(color: AppColors.steel, fontSize: 10)),
    ]));
  Future<void> _rename(BuildContext context) async {
    final c = TextEditingController(text: category.name);
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Renombrar categoría'),
      content: TextField(controller: c, autofocus: true, maxLength: 100, decoration: const InputDecoration(labelText: 'Nombre')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () { if (c.text.trim().length >= 3) Navigator.pop(ctx, c.text.trim()); }, child: const Text('Guardar'))]));
    c.dispose();
    if (value != null && context.mounted) context.read<SettingsBloc>().add(CategoryUpdateRequested(id: category.id, name: value));
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({required this.priority, required this.canEdit});
  final PriorityAdmin priority; final bool canEdit;
  @override
  Widget build(BuildContext context) {
    final sla = priority.slaHours == null ? 'Sin plazo' : 'SLA: ${priority.slaHours} h';
    return Container(margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.smAll, border: Border.all(color: AppColors.grey)),
      child: Row(children: [
        Container(width: 29, height: 29, alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.mustard.withValues(alpha: .25), borderRadius: AppRadius.smAll),
          child: Text('${priority.level}', style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900))),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(priority.name, style: const TextStyle(color: AppColors.navy, fontSize: 11.5, fontWeight: FontWeight.w800)),
          Text(sla, style: const TextStyle(color: AppColors.slate, fontSize: 9.5)),
        ])),
        if (canEdit) ...[
          IconButton(tooltip: 'Editar prioridad', visualDensity: VisualDensity.compact, onPressed: () => _edit(context), icon: const Icon(Icons.edit_outlined, size: 17, color: AppColors.steel)),
          Switch.adaptive(value: priority.isActive, activeColor: AppColors.mustard, onChanged: (v) => context.read<SettingsBloc>().add(PriorityUpdateRequested(id: priority.id, isActive: v))),
        ] else Text(priority.isActive ? 'Activa' : 'Inactiva', style: const TextStyle(color: AppColors.steel, fontSize: 10)),
      ]));
  }
  Future<void> _edit(BuildContext context) async {
    final name = TextEditingController(text: priority.name); final level = TextEditingController(text: '${priority.level}');
    final sla = TextEditingController(text: priority.slaHours?.toString() ?? ''); final key = GlobalKey<FormState>();
    final result = await showDialog<(String, int, int?, bool)>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Editar ${priority.name}'),
      content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v) => (v ?? '').trim().isEmpty ? 'Campo obligatorio.' : null),
        TextFormField(controller: level, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nivel (1–100)'), validator: (v) { final n = int.tryParse(v ?? ''); return n == null || n < 1 || n > 100 ? 'Ingresa un valor entre 1 y 100.' : null; }),
        TextFormField(controller: sla, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'SLA en horas (opcional)'), validator: (v) { if ((v ?? '').trim().isEmpty) return null; final n = int.tryParse(v!); return n == null || n < 1 || n > 8760 ? 'Ingresa horas entre 1 y 8760.' : null; }),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, (name.text.trim(), int.parse(level.text), sla.text.trim().isEmpty ? null : int.parse(sla.text), sla.text.trim().isEmpty && priority.slaHours != null)); }, child: const Text('Guardar'))],
    ));
    name.dispose(); level.dispose(); sla.dispose();
    if (result != null && context.mounted) context.read<SettingsBloc>().add(PriorityUpdateRequested(id: priority.id, name: result.$1, level: result.$2, slaHours: result.$3, clearSla: result.$4));
  }
}

String _auditLabel(String action) => switch (action) {
  'organization.updated' => 'Datos de organización actualizados',
  'category.created' => 'Categoría creada',
  'category.updated' => 'Categoría modificada',
  'category.deleted' => 'Categoría eliminada',
  'priority.updated' => 'Prioridad modificada',
  'user.roles_changed' => 'Roles de usuario actualizados',
  'user.activated' => 'Usuario activado',
  'user.deactivated' => 'Usuario desactivado',
  _ => action.replaceAll('.', ' ').replaceAll('_', ' '),
};
