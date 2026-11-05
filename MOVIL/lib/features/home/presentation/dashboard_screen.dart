import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/bloc/auth_bloc.dart';
import '../../../core/auth/home_resolver.dart';
import '../../../core/auth/user_profile.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/status_message.dart';
import '../data/dashboard_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.destination});

  final HomeDestination destination;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _scrollController = ScrollController();
  final _alertsKey = GlobalKey();
  String _period = '30d';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _kpis = {};
  Map<String, dynamic> _trends = {};
  Map<String, dynamic> _alerts = {};
  List<dynamic> _topEquipment = [];

  static const _navItems = <_NavItem>[
    _NavItem('Dashboard', Icons.home_rounded, '/inicio/dashboard-global'),
    _NavItem('Equipos', Icons.desktop_windows_rounded, '/modulos/equipos', 'equipos:ver'),
    _NavItem('Tickets', Icons.confirmation_number_outlined, '/modulos/tickets', 'tickets:ver'),
    _NavItem('Solicitudes', Icons.inbox_outlined, '/inicio/solicitudes', 'solicitudes:ver'),
    _NavItem('Técnicos', Icons.engineering_outlined, '/modulos/tecnicos', 'tecnicos:ver'),
    _NavItem('Mantenimiento', Icons.event_repeat_rounded, '/modulos/mantenimiento', 'mantenimiento:ver'),
    _NavItem('Inventario', Icons.inventory_2_outlined, '/modulos/inventario', 'inventario:ver'),
    _NavItem('Reportes', Icons.monitoring_rounded, '/inicio/reportes', 'reportes:ver'),
    _NavItem('Usuarios', Icons.manage_accounts_outlined, '/modulos/usuarios', 'usuarios:ver'),
    _NavItem('Roles y permisos', Icons.admin_panel_settings_outlined, '/modulos/roles', 'usuarios:asignar'),
    _NavItem('Usuarios pendientes', Icons.how_to_reg_outlined, '/modulos/usuarios-pendientes', 'usuarios:asignar'),
    _NavItem('Configuración', Icons.settings_outlined, '/modulos/configuracion', 'configuracion:ver'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = context.read<DashboardRepository>();
    Future<Map<String, dynamic>> safe(Future<Map<String, dynamic>> Function() request) async {
      try {
        return await request();
      } catch (_) {
        return <String, dynamic>{};
      }
    }

    final results = await Future.wait([
      safe(() => repository.loadKpis(_period)),
      safe(() => repository.loadTrends(_period)),
      safe(repository.loadAlerts),
      safe(() => repository.loadTopEquipment(_period)),
    ]);
    if (!mounted) return;
    setState(() {
      _kpis = results[0];
      _trends = results[1];
      _alerts = results[2];
      final equipment = results[3]['equipment'];
      _topEquipment = equipment is List ? equipment : [];
      _loading = false;
      if (_kpis.isEmpty && _trends.isEmpty && _alerts.isEmpty) {
        _error = 'No pudimos cargar los indicadores. Revisa tu conexión o tus permisos.';
      }
    });
  }

  String _number(dynamic value, {String suffix = ''}) {
    if (value == null) return '—';
    if (value is num) {
      final rounded = value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
      return '$rounded$suffix';
    }
    return '$value$suffix';
  }

  String _percent(dynamic value) => value is num ? '${value.toStringAsFixed(1)}%' : '—';

  String _duration(dynamic hours) {
    if (hours is! num) return '—';
    final days = hours / 24;
    return days >= 1 ? '${days.toStringAsFixed(1)} d' : '${hours.toStringAsFixed(1)} h';
  }

  String _periodLabel() => switch (_period) {
    '7d' => 'Últimos 7 días',
    '12m' => 'Últimos 12 meses',
    _ => 'Últimos 30 días',
  };

  List<dynamic> get _tickets => _alerts['tickets'] is List ? _alerts['tickets'] as List : [];
  List<dynamic> get _downEquipment => _alerts['down_equipment'] is List ? _alerts['down_equipment'] as List : [];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final profile = authState is Authenticated ? authState.profile : null;
        if (profile == null) {
          return const StatusMessage(
            icon: Icons.dashboard_outlined,
            title: 'Dashboard',
            message: 'No encontramos los datos de tu sesión.',
          );
        }
        final isGlobal = profile.can('dashboard:ver_todos');
        return Scaffold(
          backgroundColor: const Color(0xFFF2F7FC),
          drawer: _buildDrawer(profile),
          appBar: AppBar(
            backgroundColor: const Color(0xFF071D35),
            foregroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 4,
            title: const _BrandWordmark(),
            actions: [
              IconButton(
                tooltip: 'Ver alertas',
                onPressed: _scrollToAlerts,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none_rounded, size: 25),
                    if (_tickets.isNotEmpty || _downEquipment.isNotEmpty)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: AppColors.mustard, shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14, left: 2),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.sky,
                  child: Text(_initials(profile.fullName), style: const TextStyle(color: AppColors.navy, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.steel,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: [
                _WelcomeHero(name: profile.fullName),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Indicadores', style: TextStyle(color: Color(0xFF0B1F3A), fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    _PeriodPicker(value: _period, onChanged: (value) {
                      setState(() => _period = value);
                      _load();
                    }),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3, bottom: 12),
                  child: Text(_periodLabel(), style: const TextStyle(color: AppColors.slate, fontSize: 11)),
                ),
                if (_error != null)
                  _ErrorBanner(message: _error!, onRetry: _load)
                else if (_loading)
                  const _KpiLoading()
                else
                  _buildKpis(),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Tickets creados y resueltos',
                  subtitle: _periodLabel(),
                  trailing: const _ChartLegend(),
                  child: _TrendChart(points: _trends['points'] is List ? _trends['points'] as List : const []),
                ),
                if (isGlobal) ...[
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: 'Equipos con más incidencias',
                    subtitle: 'Candidatos a revisar o reemplazar',
                    child: _EquipmentRanking(items: _topEquipment),
                  ),
                ],
                const SizedBox(height: 14),
                Container(key: _alertsKey),
                _SectionCard(
                  title: 'Atención inmediata',
                  subtitle: 'Lo que necesita acción ahora',
                  child: _AlertsList(tickets: _tickets, downEquipment: _downEquipment),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text('MANTIX  •  Sistema inteligente de mantenimiento', style: TextStyle(color: AppColors.slate.withValues(alpha: 0.8), fontSize: 10)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKpis() {
    final availability = _kpis['availability'];
    final backlog = _kpis['backlog'];
    final mttr = _kpis['mttr_hours'];
    final sla = _kpis['sla_compliance_pct'];
    final cards = <_KpiData>[
      _KpiData('MTTR · mediana', _duration(mttr is Map ? mttr['value'] : null), Icons.timer_outlined, 'Tiempo de resolución'),
      _KpiData('Cumplimiento SLA', _percent(sla is Map ? sla['value'] : null), Icons.verified_user_outlined, 'Tickets resueltos a tiempo'),
      _KpiData('Disponibilidad', _percent(availability is Map ? availability['value'] : null), Icons.desktop_windows_outlined, availability is Map ? '${availability['operational'] ?? 0} de ${availability['total'] ?? 0} equipos operativos' : 'Equipos operativos'),
      _KpiData('Backlog', _number(backlog is Map ? backlog['open'] : null), Icons.inbox_outlined, 'Tickets abiertos'),
    ];
    return GridView.builder(
      itemCount: cards.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.42),
      itemBuilder: (context, index) => _KpiCard(data: cards[index]),
    );
  }

  Widget _buildDrawer(UserProfile profile) {
    final allowed = _navItems.where((item) => item.permission == null || profile.can(item.permission!)).toList();
    final homePath = resolveHome(profile.permissions).path;
    return Drawer(
      width: 306,
      backgroundColor: const Color(0xFF0B2341),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
              child: Row(
                children: [
                  const Expanded(child: _BrandWordmark(fontSize: 27)),
                  IconButton(
                    tooltip: 'Cerrar menú',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final item in allowed)
                    _DrawerItem(
                      item: item,
                      selected: item.path == homePath || (item.path == '/inicio/dashboard-global' && widget.destination == HomeDestination.globalDashboard) || (item.path == '/inicio/dashboard' && widget.destination == HomeDestination.ownDashboard),
                      onTap: () {
                        Navigator.of(context).pop();
                        final target = item.label == 'Dashboard' ? homePath : item.path;
                        context.go(target);
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text('PERFIL', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                  ),
                  Material(
                    color: const Color(0xFF24476B),
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go('/perfil');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(11),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AppColors.sky,
                              child: Text(_initials(profile.fullName), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(profile.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                  Text(profile.roles.isEmpty ? 'Usuario' : profile.roles.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => context.read<AuthBloc>().add(const AuthSignOutRequested()),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Cerrar sesión'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToAlerts() {
    final context = _alertsKey.currentContext;
    if (context != null) Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).take(2);
    final value = parts.map((part) => part[0].toUpperCase()).join();
    return value.isEmpty ? 'M' : value;
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.path, [this.permission]);
  final String label;
  final IconData icon;
  final String path;
  final String? permission;
}

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark({this.fontSize = 25});
  final double fontSize;

  @override
  Widget build(BuildContext context) => RichText(
    text: TextSpan(
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, letterSpacing: -1.1),
      children: const [
        TextSpan(text: 'MANT', style: TextStyle(color: Colors.white)),
        TextSpan(text: 'IX', style: TextStyle(color: AppColors.mustard)),
      ],
    ),
  );
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    return Container(
      height: 154,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: const LinearGradient(colors: [Color(0xFFEAF5FF), Color(0xFFD9ECFC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: const [BoxShadow(color: Color(0x143E5C76), blurRadius: 18, offset: Offset(0, 7))],
      ),
      child: Stack(
        children: [
          Positioned(right: -15, bottom: -20, child: Icon(Icons.memory_rounded, size: 138, color: AppColors.sky.withValues(alpha: 0.45))),
          Positioned(right: 55, top: 10, child: Icon(Icons.settings_rounded, size: 56, color: AppColors.steel.withValues(alpha: 0.13))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.circle, size: 7, color: AppColors.mustard),
                  const SizedBox(width: 6),
                  Text('HOLA, ${firstName.toUpperCase()}', style: const TextStyle(color: AppColors.steel, fontSize: 10, fontWeight: FontWeight.w800)),
                ]),
              ),
              const Spacer(),
              const SizedBox(
                width: 230,
                child: Text('Sistema inteligente\nde mantenimiento', style: TextStyle(color: Color(0xFF0B1F3A), fontSize: 21, height: 1.08, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 5),
              const SizedBox(
                width: 230,
                child: Text('Gestión de incidentes y control en tiempo real del parque tecnológico.', style: TextStyle(color: Color(0xFF526B83), fontSize: 10, height: 1.3)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Color(0x100B1F3A), blurRadius: 8)]),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      for (final item in const [('7d', '7 d'), ('30d', '30 d'), ('12m', '12 m')])
        GestureDetector(
          onTap: () => onChanged(item.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: value == item.$1 ? const Color(0xFF0B1F3A) : Colors.transparent, borderRadius: BorderRadius.circular(22)),
            child: Text(item.$2, style: TextStyle(color: value == item.$1 ? Colors.white : AppColors.slate, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
    ]),
  );
}

class _KpiData {
  const _KpiData(this.label, this.value, this.icon, this.caption);
  final String label;
  final String value;
  final IconData icon;
  final String caption;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiData data;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5EEF6)), boxShadow: const [BoxShadow(color: Color(0x0C0B1F3A), blurRadius: 12, offset: Offset(0, 4))]),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 27, height: 27, decoration: BoxDecoration(color: const Color(0xFFEAF5FF), borderRadius: BorderRadius.circular(9)), child: Icon(data.icon, color: const Color(0xFF2678C8), size: 16)),
          const SizedBox(width: 7),
          Expanded(child: Text(data.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 9, fontWeight: FontWeight.w800))),
        ]),
        const Spacer(),
        Text(data.value, style: const TextStyle(color: Color(0xFF153A60), fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
        const SizedBox(height: 3),
        Text(data.caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 9, height: 1.2)),
      ],
    ),
  );
}

class _KpiLoading extends StatelessWidget {
  const _KpiLoading();

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 2,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    childAspectRatio: 1.42,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: List.generate(4, (_) => Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)))),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE5EEF6)), boxShadow: const [BoxShadow(color: Color(0x0C0B1F3A), blurRadius: 12, offset: Offset(0, 4))]),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Color(0xFF173A5E), fontSize: 14, fontWeight: FontWeight.w800)),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(subtitle!, style: const TextStyle(color: AppColors.slate, fontSize: 10))),
          ])),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      _LegendDot(color: Color(0xFF93C5FD), label: 'Creados'),
      SizedBox(height: 4),
      _LegendDot(color: Color(0xFF2678C8), label: 'Resueltos'),
    ],
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 7, height: 7, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(color: AppColors.slate, fontSize: 9)),
  ]);
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});
  final List<dynamic> points;

  @override
  Widget build(BuildContext context) {
    final visible = points.whereType<Map>().toList();
    if (visible.isEmpty) {
      return Container(height: 145, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFF5F9FD), borderRadius: BorderRadius.circular(12)), child: const Text('No hay datos para este periodo.', style: TextStyle(color: AppColors.slate, fontSize: 11)));
    }
    final maxValue = visible.fold<int>(1, (max, item) {
      final created = item['created'] is num ? (item['created'] as num).toInt() : 0;
      final resolved = item['resolved'] is num ? (item['resolved'] as num).toInt() : 0;
      final value = created > resolved ? created : resolved;
      return value > max ? value : max;
    });
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < visible.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: _Bar(value: visible[i]['created'], max: maxValue, color: const Color(0xFF93C5FD))),
                          const SizedBox(width: 2),
                          Expanded(child: _Bar(value: visible[i]['resolved'], max: maxValue, color: const Color(0xFF2678C8))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (visible.length <= 7 || i % 4 == 0)
                      Text(_bucket(visible[i]['bucket']), maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(color: AppColors.slate, fontSize: 7))
                    else
                      const SizedBox(height: 9),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _bucket(dynamic value) {
    if (value is! String || value.length < 10) return '';
    return value.substring(5, 10);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.max, required this.color});
  final dynamic value;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final amount = value is num ? value.toDouble() : 0.0;
    return LayoutBuilder(builder: (context, constraints) {
      final height = amount == 0 ? 0.0 : (amount / max * constraints.maxHeight).clamp(3.0, constraints.maxHeight).toDouble();
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
        ),
      );
    });
  }
}

class _EquipmentRanking extends StatelessWidget {
  const _EquipmentRanking({required this.items});
  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('No hay equipos con incidencias en este periodo.', style: TextStyle(color: AppColors.slate, fontSize: 11));
    final max = items.fold<int>(1, (value, item) {
      final count = item is Map && item['tickets'] is num ? (item['tickets'] as num).toInt() : 0;
      return count > value ? count : value;
    });
    return Column(children: [
      for (final item in items.take(5))
        if (item is Map)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text('${item['asset_tag'] ?? 'Equipo'} · ${item['brand'] ?? ''} ${item['model'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF274765), fontSize: 10, fontWeight: FontWeight.w700))),
                  Text('${item['tickets'] ?? 0}', style: const TextStyle(color: AppColors.steel, fontSize: 11, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 5),
                ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ((item['tickets'] is num ? (item['tickets'] as num).toDouble() : 0) / max).clamp(0, 1).toDouble(), minHeight: 5, backgroundColor: const Color(0xFFE6EEF6), color: const Color(0xFF3287D2))),
              ],
            ),
          ),
    ]);
  }
}

class _AlertsList extends StatelessWidget {
  const _AlertsList({required this.tickets, required this.downEquipment});
  final List<dynamic> tickets;
  final List<dynamic> downEquipment;

  @override
  Widget build(BuildContext context) {
    final all = <Widget>[
      for (final item in tickets.take(5))
        if (item is Map)
          _AlertRow(
            icon: Icons.confirmation_number_outlined,
            title: '${item['ticket_number'] ?? 'Ticket'} · ${item['title'] ?? 'Incidencia'}',
            subtitle: '${item['asset_tag'] ?? 'Equipo'} · ${_reason(item['reason'])}',
            tone: AppColors.mustard,
          ),
      for (final item in downEquipment.take(3))
        if (item is Map)
          _AlertRow(
            icon: Icons.desktop_access_disabled_outlined,
            title: '${item['asset_tag'] ?? 'Equipo'} fuera de servicio',
            subtitle: '${item['brand'] ?? ''} ${item['model'] ?? ''}',
            tone: const Color(0xFFD18B35),
          ),
    ];
    if (all.isEmpty) {
      return const Row(children: [
        Icon(Icons.check_circle_outline_rounded, color: Color(0xFF269B76), size: 22),
        SizedBox(width: 9),
        Expanded(child: Text('No hay alertas que requieran atención inmediata.', style: TextStyle(color: AppColors.slate, fontSize: 11))),
      ]);
    }
    return Column(children: all);
  }

  static String _reason(dynamic value) => switch (value) {
    'unassigned_critical' => 'Crítico sin asignar',
    'sla_breached' => 'SLA vencido',
    'sla_at_risk' => 'SLA en riesgo',
    _ => 'Requiere atención',
  };
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.icon, required this.title, required this.subtitle, required this.tone});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(children: [
      Icon(icon, color: tone, size: 19),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF244765), fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 9)),
      ])),
      const Icon(Icons.chevron_right_rounded, color: AppColors.slate, size: 18),
    ]),
  );
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.item, required this.selected, required this.onTap});
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Material(
      color: selected ? const Color(0xFF2878AA) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 48,
          child: Row(children: [
            const SizedBox(width: 15),
            Icon(item.icon, color: Colors.white.withValues(alpha: selected ? 1 : 0.82), size: 21),
            const SizedBox(width: 14),
            Expanded(child: Text(item.label, style: TextStyle(color: Colors.white.withValues(alpha: selected ? 1 : 0.88), fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
          ]),
        ),
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: const Color(0xFFFFF4DD), borderRadius: BorderRadius.circular(13)),
    child: Row(children: [
      const Icon(Icons.info_outline_rounded, color: Color(0xFF9B6A19), size: 20),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(color: Color(0xFF76521A), fontSize: 11))),
      TextButton(onPressed: onRetry, child: const Text('Reintentar')),
    ]),
  );
}
