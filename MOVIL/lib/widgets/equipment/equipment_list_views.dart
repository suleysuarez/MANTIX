import 'package:flutter/material.dart';

import '../../core/format/equipment_meta.dart';
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
  const EquipmentTable({super.key, required this.items, required this.onOpen, this.highlightId});

  final List<Equipment> items;

  /// Equipo recién registrado: su fila se resalta con el acento mostaza.
  final int? highlightId;
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
            child: const Text('EQUIPO Y MODELO · ESTADO', style: TextStyle(color: AppColors.slate, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFEEF3F8)),
            _TableRow(item: items[i], highlighted: items[i].id == highlightId, onTap: () => onOpen(items[i])),
          ],
        ]),
      );
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.item, required this.onTap, this.highlighted = false});

  final Equipment item;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = equipmentStatusMeta(item.status);
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: highlighted ? AppColors.mustard.withValues(alpha: .28) : Colors.transparent,
          border: Border(left: BorderSide(color: highlighted ? AppColors.mustard : Colors.transparent, width: 4)),
        ),
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
              // Estado y etiqueta se acomodan en varias líneas si no caben: con letra grande en una
              // pantalla estrecha una fila fija se desbordaría.
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                AppChip(label: status.label, colors: status.colors, semanticPrefix: 'Estado'),
                _TagChip(item.assetTag),
              ]),
              const SizedBox(height: 6),
              _Location(item),
            ]),
          ),
          const SizedBox(width: 8),
          const Padding(padding: EdgeInsets.only(top: 8), child: Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.slate)),
        ]),
      ),
    );
  }
}

/// Vista de cuadrícula: dos equipos por fila.
class EquipmentGrid extends StatelessWidget {
  const EquipmentGrid({super.key, required this.items, required this.onOpen, this.highlightId});

  final List<Equipment> items;
  final int? highlightId;
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
        itemBuilder: (context, index) => _GridTile(item: items[index], highlighted: items[index].id == highlightId, onTap: () => onOpen(items[index])),
      );
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.item, required this.onTap, this.highlighted = false});

  final Equipment item;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = equipmentStatusMeta(item.status);
    return Material(
      color: highlighted ? const Color(0xFFFBF1DC) : Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: highlighted ? AppColors.mustard : const Color(0xFFE5EEF6), width: highlighted ? 2 : 1),
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
