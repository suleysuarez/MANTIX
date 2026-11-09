import 'package:flutter/material.dart';

import '../../core/format/equipment_meta.dart';
import '../../core/format/formatters.dart';
import '../../core/theme/app_colors.dart';
import '../../models/equipment/equipment_models.dart';
import '../shared/app_chip.dart';

/// Cómo se muestra el listado de equipos.
enum EquipmentView { table, grid }

const equipmentPageSizes = [10];

String _subtitle(Equipment item) {
  final description = item.description?.trim();
  if (description != null && description.isNotEmpty) return description;
  final serial = item.serialNumber?.trim();
  return 'Serie: ${serial == null || serial.isEmpty ? 'sin registrar' : serial}';
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.item, this.size = 40});

  final Equipment item;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: EquipmentColors.info.background, borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(equipmentCategoryIcon(item.typeCode), color: EquipmentColors.info.foreground, size: size * 0.52),
      );
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF334155), fontSize: 10.5, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
      );
}

class _Location extends StatelessWidget {
  const _Location(this.item);

  final Equipment item;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.place_outlined, size: 13, color: AppColors.slate),
        const SizedBox(width: 3),
        Flexible(child: Text(item.locationName ?? 'Sin ubicación', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 10.5))),
      ]);
}

/// Vista de tabla: una fila por equipo con su estado, como en la web.
class EquipmentTable extends StatelessWidget {
  const EquipmentTable({super.key, required this.items, required this.onOpen});

  final List<Equipment> items;
  final ValueChanged<Equipment> onOpen;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5EEF6)),
          boxShadow: const [BoxShadow(color: Color(0x0C0B1F3A), blurRadius: 12, offset: Offset(0, 4))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            color: const Color(0xFFF4F8FC),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: const Row(children: [
              Expanded(child: Text('EQUIPO Y MODELO', style: TextStyle(color: AppColors.slate, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6))),
              Text('ESTADO', style: TextStyle(color: AppColors.slate, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              SizedBox(width: 22),
            ]),
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFEEF3F8)),
            _TableRow(item: items[i], onTap: () => onOpen(items[i])),
          ],
        ]),
      );
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.item, required this.onTap});

  final Equipment item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = equipmentStatusMeta(item.status);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _IconBox(item: item),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${item.brand} ${item.model}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF153A60), fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 2),
              Text(_subtitle(item), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 11.5)),
              const SizedBox(height: 6),
              Row(children: [
                _TagChip(item.assetTag),
                const SizedBox(width: 8),
                Expanded(child: _Location(item)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 118),
            child: AppChip(label: status.label, colors: status.colors, semanticPrefix: 'Estado'),
          ),
          const Padding(padding: EdgeInsets.only(top: 8), child: Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.slate)),
        ]),
      ),
    );
  }
}

/// Vista de cuadrícula: dos equipos por fila.
class EquipmentGrid extends StatelessWidget {
  const EquipmentGrid({super.key, required this.items, required this.onOpen});

  final List<Equipment> items;
  final ValueChanged<Equipment> onOpen;

  @override
  Widget build(BuildContext context) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        // El alto crece con el tamaño de letra del sistema para que nada se corte.
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: 172 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
        ),
        itemBuilder: (context, index) => _GridTile(item: items[index], onTap: () => onOpen(items[index])),
      );
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.item, required this.onTap});

  final Equipment item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = equipmentStatusMeta(item.status);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFE5EEF6)),
            boxShadow: const [BoxShadow(color: Color(0x0C0B1F3A), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _IconBox(item: item, size: 34),
              const SizedBox(width: 6),
              Expanded(child: Align(alignment: Alignment.centerRight, child: AppChip(label: status.label, colors: status.colors, semanticPrefix: 'Estado'))),
            ]),
            const SizedBox(height: 8),
            Text('${item.brand} ${item.model}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF153A60), fontSize: 13, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 3),
            Text(_subtitle(item), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.slate, fontSize: 10.5)),
            const Spacer(),
            Align(alignment: Alignment.centerLeft, child: _TagChip(item.assetTag)),
            const SizedBox(height: 5),
            _Location(item),
          ]),
        ),
      ),
    );
  }
}

/// Páginas que se muestran como botones: la primera, la última y las vecinas de la actual
/// (`null` marca un hueco).
List<int?> pageButtons(int page, int totalPages) {
  final shown = <int>{1, totalPages, page - 1, page, page + 1}.where((p) => p >= 1 && p <= totalPages).toList()..sort();
  final result = <int?>[];
  for (var i = 0; i < shown.length; i++) {
    if (i > 0 && shown[i] - shown[i - 1] > 1) result.add(null);
    result.add(shown[i]);
  }
  return result;
}

/// «Mostrando 1 – 5 de 38 equipos», tamaño de página y botones de página.
class EquipmentPagination extends StatelessWidget {
  const EquipmentPagination({
    super.key,
    required this.page,
    required this.totalPages,
    required this.total,
    required this.shown,
    required this.pageSize,
    required this.onPage,
    
  });

  final int page;
  final int totalPages;
  final int total;

  /// Equipos en la página actual.
  final int shown;
  final int pageSize;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : (page - 1) * pageSize + 1;
    final to = total == 0 ? 0 : from + shown - 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text('Mostrando $from – $to de $total equipos', style: const TextStyle(color: AppColors.slate, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _PageButton(icon: Icons.chevron_left_rounded, tooltip: 'Página anterior', onTap: page > 1 ? () => onPage(page - 1) : null),
          for (final number in pageButtons(page, totalPages))
            if (number == null)
              const SizedBox(width: 28, child: Center(child: Text('…', style: TextStyle(color: AppColors.slate))))
            else
              _PageButton(label: '$number', selected: number == page, tooltip: 'Página $number', onTap: number == page ? null : () => onPage(number)),
          _PageButton(icon: Icons.chevron_right_rounded, tooltip: 'Página siguiente', onTap: page < totalPages ? () => onPage(page + 1) : null),
        ]),
    ]);
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({this.label, this.icon, required this.tooltip, this.selected = false, this.onTap});

  final String? label;
  final IconData? icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
        button: true,
        selected: selected,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? EquipmentColors.info.dot : Colors.transparent),
            child: label != null
                ? Text(label!, style: TextStyle(color: selected ? Colors.white : const Color(0xFF334155), fontSize: 13, fontWeight: FontWeight.w800))
                : Icon(icon, size: 22, color: onTap == null ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
          ),
        ),
        ),
      );
}

/// Ficha del equipo en una hoja inferior (solo lectura).
Future<void> showEquipmentDetails(BuildContext context, Equipment item) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _EquipmentDetails(item: item),
    );

class _EquipmentDetails extends StatelessWidget {
  const _EquipmentDetails({required this.item});

  final Equipment item;

  @override
  Widget build(BuildContext context) {
    final status = equipmentStatusMeta(item.status);
    final last = item.lastMaintenanceAt;
    final rows = <(String, String)>[
      ('Código de activo', item.assetTag),
      ('Categoría', item.typeName),
      ('Número de serie', item.serialNumber == null || item.serialNumber!.isEmpty ? 'Sin registrar' : item.serialNumber!),
      ('Ubicación', item.locationName ?? 'Sin ubicación'),
      ('Responsable', item.custodianName ?? 'Sin responsable'),
      ('Último mantenimiento', last == null ? 'Sin mantenimientos' : formatDate(last.toLocal())),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _IconBox(item: item, size: 46),
            const SizedBox(width: 12),
            Expanded(child: Text('${item.brand} ${item.model}', style: const TextStyle(color: Color(0xFF0B1F3A), fontSize: 18, fontWeight: FontWeight.w800, height: 1.2))),
          ]),
          const SizedBox(height: 10),
          AppChip(label: status.label, colors: status.colors, semanticPrefix: 'Estado'),
          if (item.description != null && item.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(item.description!, style: const TextStyle(color: Color(0xFF475569), fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 14),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppColors.slate, fontSize: 12))),
                Expanded(child: Text(value, style: const TextStyle(color: Color(0xFF0B1F3A), fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
            ),
        ]),
      ),
    );
  }
}
