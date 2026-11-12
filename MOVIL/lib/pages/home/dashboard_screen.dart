import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/ticket_meta.dart';
import '../../core/routing/home_resolver.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/shared/status_message.dart';
import '../../repositories/home/dashboard_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.destination});

  final HomeDestination destination;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _scrollController = ScrollController();
  String _period = '30d';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _kpis = {};
  Map<String, dynamic> _trends = {};
  Map<String, dynamic> _alerts = {};
  List<dynamic> _topEquipment = [];
  List<dynamic> _technicians = [];

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
      safe(() => repository.loadTechnicians(_period)),
    ]);
    if (!mounted) return;
    setState(() {
      _kpis = results[0];
      _trends = results[1];
      _alerts = results[2];
      final equipment = results[3]['equipment'];
      _topEquipment = equipment is List ? equipment : [];
      final technicians = results[4]['technicians'];
      _technicians = technicians is List ? technicians : [];
      _loading = false;
      if (_kpis.isEmpty && _trends.isEmpty && _alerts.isEmpty && _technicians.isEmpty) {
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

  String _percent(dynamic value) => value is num ? '${value.toStringAsFixed(1).replaceAll('.', ',')}%' : '—';

  String _duration(dynamic hours) {
    if (hours is! num) return '—';
    if (hours < 1) return '${(hours * 60).round().clamp(1, 59)} min';
    return hours < 48
        ? '${hours.toStringAsFixed(1).replaceAll('.', ',')} h'
        : '${(hours / 24).toStringAsFixed(1).replaceAll('.', ',')} d';
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
          drawer: MantixDrawer(profile: profile, selectedPath: widget.destination.path),
          appBar: MantixAppBar(profile: profile),
          body: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.steel,
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              children: [
                // El banner ocupa todo el ancho; el resto de la pantalla conserva sus márgenes.
                _WelcomeHero(name: profile.fullName),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _PeriodPicker(value: _period, onChanged: (value) {
                  setState(() => _period = value);
                  _load();
                }),
                const SizedBox(height: 12),
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
                    trailing: profile.can('equipos:ver') ? const _SectionLink(label: 'Ver todos', path: '/modulos/equipos') : null,
                    child: _EquipmentRanking(items: _topEquipment),
                  ),
                ],
                const SizedBox(height: 14),
                _SectionCard(
                  title: isGlobal ? 'Rendimiento del equipo técnico' : 'Mi rendimiento',
                  subtitle: _periodLabel(),
                  trailing: isGlobal && profile.can('tecnicos:ver') ? const _SectionLink(label: 'Ver técnicos', path: '/tecnicos') : null,
                  child: _TechnicianPerformance(items: _technicians),
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Atención inmediata',
                  subtitle: 'Lo que necesita acción ahora',
                  child: _AlertsList(tickets: _tickets, downEquipment: _downEquipment),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text('MANTIX  •  Sistema inteligente de mantenimiento', style: TextStyle(color: AppColors.slate.withValues(alpha: 0.8), fontSize: 10)),
                ),
                  ]),
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
    final firstAssignment = _kpis['first_assignment_hours'];
    final points = _trends['points'] is List ? (_trends['points'] as List).whereType<Map>().toList() : <Map>[];

    double? numOf(dynamic value) => value is num ? value.toDouble() : null;
    List<double> series(String key) => [for (final point in points) if (point[key] is num) (point[key] as num).toDouble()];
    // Backlog at the end of each bucket, rebuilt backwards from the open tickets now.
    List<double> backlogSeries(double? open) {
      if (open == null || points.length < 2) return const [];
      final result = List<double>.filled(points.length, 0);
      var running = open;
      for (var i = points.length - 1; i >= 0; i--) {
        result[i] = running;
        running -= (numOf(points[i]['created']) ?? 0) - (numOf(points[i]['resolved']) ?? 0);
      }
      return result;
    }

    String sampleNote(Map<dynamic, dynamic> kpi) {
      final n = kpi['sample_size'];
      return 'vs. período anterior${n is num ? ' · n=${n.toInt()}' : ''}${kpi['low_sample'] == true ? ' · pocos datos' : ''}';
    }

    final met = sla is Map && sla['met'] is num ? (sla['met'] as num).toInt() : null;
    final missed = sla is Map && sla['missed'] is num ? (sla['missed'] as num).toInt() : null;
    final cards = <_KpiData>[
      _KpiData(
        label: 'MTTR · mediana',
        value: _duration(mttr is Map ? mttr['value'] : null),
        icon: Icons.timer_outlined,
        caption: firstAssignment is Map && firstAssignment['value'] is num ? 'Resolución · 1.ª asignación en ${_duration(firstAssignment['value'])}' : 'Tiempo de resolución',
        change: mttr is Map ? numOf(mttr['change_pct']) : null,
        higherIsBetter: false,
        note: mttr is Map ? sampleNote(mttr) : null,
        spark: series('mttr_hours'),
      ),
      _KpiData(
        label: 'Cumplimiento SLA',
        value: _percent(sla is Map ? sla['value'] : null),
        icon: Icons.verified_user_outlined,
        caption: met != null && missed != null ? '$met de ${met + missed} a tiempo' : 'Tickets resueltos a tiempo',
        change: sla is Map ? numOf(sla['change_pct']) : null,
        note: sla is Map ? sampleNote(sla) : null,
        spark: series('sla_compliance_pct'),
      ),
      _KpiData(
        label: 'Disponibilidad',
        value: _percent(availability is Map ? availability['value'] : null),
        icon: Icons.desktop_windows_outlined,
        caption: availability is Map ? '${availability['operational'] ?? 0} de ${availability['total'] ?? 0} equipos operativos' : 'Equipos operativos',
        change: availability is Map ? numOf(availability['change_pct']) : null,
        note: 'vs. inicio del período',
      ),
      _KpiData(
        label: 'Backlog',
        value: _number(backlog is Map ? backlog['open'] : null),
        icon: Icons.inbox_outlined,
        caption: 'tickets abiertos',
        change: backlog is Map ? numOf(backlog['change_pct']) : null,
        higherIsBetter: false,
        note: 'vs. inicio del período',
        spark: backlogSeries(backlog is Map ? numOf(backlog['open']) : null),
      ),
    ];
    return GridView.builder(
      itemCount: cards.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, mainAxisExtent: 148 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5)),
      itemBuilder: (context, index) => _KpiCard(data: cards[index]),
    );
  }

}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+'));
    final firstName = words.first.isEmpty ? 'USUARIO' : words.first;
    const radius = BorderRadius.vertical(bottom: Radius.circular(22));
    return Container(
      height: 176,
      decoration: const BoxDecoration(
        borderRadius: radius,
        boxShadow: [BoxShadow(color: Color(0x40050B1A), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset('assets/images/card_dashboard.png', fit: BoxFit.cover, alignment: Alignment.centerRight, cacheWidth: 1200),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xE6071D35), Color(0xB3071D35), Color(0x33071D35)],
                    stops: [0, 0.6, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AuthTokens.glassBorder.withValues(alpha: 0.25)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.circle, size: 7, color: AuthTokens.accent),
                      const SizedBox(width: 6),
                      Text('HOLA, ${firstName.toUpperCase()}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  // Texto centrado en el espacio bajo la etiqueta, un poco por encima del centro.
                  Expanded(
                    child: Align(
                      alignment: const Alignment(-1, -0.2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            width: 250,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('Sistema Inteligente\nde Mantenimiento', textAlign: TextAlign.left, style: TextStyle(color: Colors.white, fontSize: 21, height: 1.1, fontWeight: FontWeight.w900)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const SizedBox(
                            width: 230,
                            child: Text('Gestión de incidentes y control en tiempo real del parque tecnológico empresarial.', textAlign: TextAlign.left, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white70, fontSize: 10, height: 1.3)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static const _shadow = [BoxShadow(color: Color(0x100B1F3A), blurRadius: 8)];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: _shadow),
    child: Row(children: [
      for (final item in const [('7d', '7 días'), ('30d', '30 días'), ('12m', '12 meses')])
        Expanded(
          child: Semantics(
            button: true,
            selected: value == item.$1,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(item.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: value == item.$1 ? const Color(0xFF0B1F3A) : Colors.transparent, borderRadius: BorderRadius.circular(22)),
                child: Text(item.$2, style: TextStyle(color: value == item.$1 ? Colors.white : AppColors.slate, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
    ]),
  );
}

class _KpiData {
  const _KpiData({
    required this.label,
    required this.value,
    required this.icon,
    required this.caption,
    this.change,
    this.higherIsBetter = true,
    this.note,
    this.spark = const [],
  });
  final String label;
  final String value;
  final IconData icon;
  final String caption;
  final double? change;
  final bool higherIsBetter;
  final String? note;
  final List<double> spark;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiData data;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5EEF6)), boxShadow: const [BoxShadow(color: Color(0x0C0B1F3A), blurRadius: 12, offset: Offset(0, 4))]),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 24, height: 24, decoration: BoxDecoration(color: const Color(0xFFEAF5FF), borderRadius: BorderRadius.circular(8)), child: Icon(data.icon, color: const Color(0xFF2678C8), size: 14)),
          const SizedBox(width: 7),
          Expanded(child: Text(data.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 9, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(data.value, style: const TextStyle(color: Color(0xFF153A60), fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.5)))),
          if (data.spark.length >= 2) SizedBox(width: 48, height: 22, child: CustomPaint(painter: _SparklinePainter(data.spark))),
        ]),
        const SizedBox(height: 3),
        Text(data.caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 9, height: 1.15)),
        const Spacer(),
        if (data.change != null)
          Row(children: [
            _DeltaChip(change: data.change!, higherIsBetter: data.higherIsBetter),
            const SizedBox(width: 6),
            Expanded(child: Text(data.note ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 8, height: 1.15))),
          ])
        else if (data.note != null)
          Text(data.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 8, height: 1.15)),
      ],
    ),
  );
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.change, required this.higherIsBetter});
  final double change;
  final bool higherIsBetter;

  @override
  Widget build(BuildContext context) {
    final good = change == 0 || (change > 0) == higherIsBetter;
    final color = good ? const Color(0xFF1E8E63) : const Color(0xFFC77A12);
    final arrow = change == 0 ? '' : (change > 0 ? '▲ ' : '▼ ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: good ? const Color(0xFFE3F6EE) : const Color(0xFFFFF0D9), borderRadius: BorderRadius.circular(8)),
      child: Text('$arrow${change.abs().toStringAsFixed(1).replaceAll('.', ',')}%', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final range = high - low;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = range == 0 ? size.height / 2 : size.height - (values[i] - low) / range * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE59A2F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}

class _KpiLoading extends StatelessWidget {
  const _KpiLoading();

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 2,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    childAspectRatio: 1.2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: List.generate(4, (_) => Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)))),
  );
}

class _SectionLink extends StatelessWidget {
  const _SectionLink({required this.label, required this.path});
  final String label;
  final String path;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: () => context.go(path),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Center(child: Text('$label →', style: const TextStyle(color: Color(0xFF2678C8), fontSize: 10, fontWeight: FontWeight.w800))),
      ),
    ),
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
          ?trailing,
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
    final ranked = items.whereType<Map>().take(5).toList();
    return Column(children: [
      for (var i = 0; i < ranked.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 1),
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Color(0xFF0B1F3A), shape: BoxShape.circle),
              child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${ranked[i]['asset_tag'] ?? 'Equipo'}  ${ranked[i]['brand'] ?? ''} ${ranked[i]['model'] ?? ''}'.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF274765), fontSize: 10.5, fontWeight: FontWeight.w700))),
                  Text('${ranked[i]['tickets'] ?? 0}', style: const TextStyle(color: AppColors.steel, fontSize: 11, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 5),
                ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ((ranked[i]['tickets'] is num ? (ranked[i]['tickets'] as num).toDouble() : 0) / max).clamp(0, 1).toDouble(), minHeight: 5, backgroundColor: const Color(0xFFE6EEF6), color: const Color(0xFF3287D2))),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

class _TechnicianPerformance extends StatelessWidget {
  const _TechnicianPerformance({required this.items});
  final List<dynamic> items;

  static const _head = TextStyle(color: AppColors.slate, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3);
  static const _cell = TextStyle(color: Color(0xFF244765), fontSize: 10.5, fontWeight: FontWeight.w700);
  static const _small = TextStyle(color: AppColors.slate, fontSize: 8);
  static const _widths = (open: 44.0, resolved: 52.0, mttr: 56.0, sla: 52.0, n: 24.0, reopened: 32.0);

  @override
  Widget build(BuildContext context) {
    final rows = items.whereType<Map>().take(6).toList();
    if (rows.isEmpty) {
      return const Text('No hay datos de rendimiento disponibles para este periodo.', style: TextStyle(color: AppColors.slate, fontSize: 11));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(child: Text('TÉCNICO', style: _head)),
          _cellBox(_widths.open, const Text('ABIERTOS', style: _head)),
          _cellBox(_widths.resolved, const Text('RESUELTOS', style: _head)),
          _cellBox(_widths.mttr, const Text('MTTR\n(MEDIANA)', textAlign: TextAlign.center, style: _head)),
          _cellBox(_widths.sla, const Text('SLA', style: _head)),
          _cellBox(_widths.n, const Text('N', style: _head)),
          _cellBox(_widths.reopened, const Text('REAB.', style: _head)),
        ]),
        const Divider(height: 14, color: Color(0xFFE5EEF6)),
        for (final item in rows) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(color: item['is_available'] == true ? const Color(0xFF20A67A) : AppColors.mustard, shape: BoxShape.circle),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${item['full_name'] ?? 'Técnico'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _cell),
                Text('${item['specialization'] ?? 'Sin especialidad'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _small),
              ]),
            ),
            _cellBox(_widths.open, Text('${item['open_tickets'] ?? 0}', style: _cell)),
            _cellBox(_widths.resolved, Text('${item['resolved'] ?? 0}', style: _cell)),
            _cellBox(_widths.mttr, Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_days(item['mttr_median_hours']), style: _cell),
              if (item['low_sample'] == true) const Text('pocos datos', style: TextStyle(color: Color(0xFFC77A12), fontSize: 7)),
            ])),
            _cellBox(_widths.sla, Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_slaText(item['sla_compliance_pct']), style: _cell),
              if (item['sla_sample_size'] is num) Text('(n=${(item['sla_sample_size'] as num).toInt()})', style: _small),
            ])),
            _cellBox(_widths.n, Text('${item['sample_size'] ?? 0}', style: _cell)),
            _cellBox(_widths.reopened, Text('${item['reopened'] ?? 0}', style: _cell)),
          ]),
          const Divider(height: 18, color: Color(0xFFEEF3F8)),
        ],
        const SizedBox(height: 2),
        const Text(
          'n = tickets resueltos en el periodo. Las prioridades sin SLA no entran en el cumplimiento. Reabiertos: pasaron de resuelto a en curso.',
          style: TextStyle(color: AppColors.slate, fontSize: 8.5, height: 1.3),
        ),
      ],
    );
  }

  static Widget _cellBox(double width, Widget child) => SizedBox(width: width, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: child)));

  static String _days(dynamic hours) => hours is num ? '${(hours / 24).toStringAsFixed(1).replaceAll('.', ',')} d' : '—';

  static String _slaText(dynamic value) {
    if (value is! num) return '—';
    final text = value.toStringAsFixed(1);
    return '${(text.endsWith('.0') ? text.substring(0, text.length - 2) : text).replaceAll('.', ',')}%';
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
            subtitle: _ticketDetail(item),
            badge: _badge(item['reason']),
          ),
      for (final item in downEquipment.take(3))
        if (item is Map)
          _AlertRow(
            icon: Icons.desktop_windows_outlined,
            title: '${item['asset_tag'] ?? 'Equipo'} fuera de servicio',
            subtitle: '${item['brand'] ?? ''} ${item['model'] ?? ''}'.trim(),
            badge: const _Badge('Fuera de servicio', Color(0xFFC77A12), Color(0xFFFFF0D9)),
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

  static String _ticketDetail(Map<dynamic, dynamic> item) {
    final deadline = item['sla_deadline'] is String ? DateTime.tryParse(item['sla_deadline'] as String) : null;
    return [
      '${item['asset_tag'] ?? 'Equipo'}',
      if (item['priority'] is String) priorityMeta(item['priority'] as String).label.toLowerCase(),
      item['assigned'] == true ? 'asignado' : 'sin asignar',
      if (deadline != null) 'vence ${formatDate(deadline.toLocal())}',
    ].join(' · ');
  }

  static _Badge? _badge(dynamic reason) => switch (reason) {
    'unassigned_critical' => const _Badge('Crítico sin asignar', Color(0xFFD64545), Color(0xFFFDE8E8)),
    'sla_breached' => const _Badge('SLA vencido', Color(0xFFD64545), Color(0xFFFDE8E8)),
    'sla_at_risk' => const _Badge('SLA en riesgo', Color(0xFFC77A12), Color(0xFFFFF0D9)),
    _ => null,
  };
}

class _Badge {
  const _Badge(this.label, this.color, this.background);
  final String label;
  final Color color;
  final Color background;
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.icon, required this.title, required this.subtitle, this.badge});
  final IconData icon;
  final String title;
  final String subtitle;
  final _Badge? badge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: const Color(0xFFFFF3DF), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: const Color(0xFFE59A2F), size: 17),
      ),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF244765), fontSize: 10.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 8.5, height: 1.25)),
      ])),
      if (badge != null) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(color: badge!.background, borderRadius: BorderRadius.circular(9)),
          child: Text(badge!.label, style: TextStyle(color: badge!.color, fontSize: 8.5, fontWeight: FontWeight.w800)),
        ),
      ],
      const Icon(Icons.chevron_right_rounded, color: AppColors.slate, size: 18),
    ]),
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
