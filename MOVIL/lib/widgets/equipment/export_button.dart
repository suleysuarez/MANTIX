import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/equipment/equipment_export_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../models/equipment/export_models.dart';

/// Botón «Exportar» del listado de equipos: abre la hoja de formatos. Se deshabilita mientras
/// se genera el archivo. [statuses] y [typeId] son los filtros vigentes.
class ExportButton extends StatelessWidget {
  const ExportButton({super.key, this.statuses, this.typeId});

  final String? statuses;
  final int? typeId;

  @override
  Widget build(BuildContext context) {
    final working = context.select(
      (EquipmentExportBloc bloc) => bloc.state.status == ExportStatus.working,
    );
    return OutlinedButton.icon(
      key: const Key('export-button'),
      onPressed: working ? null : () => _choose(context),
      icon: working
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.ios_share_rounded, size: 18),
      label: Text(working ? 'Exportando…' : 'Exportar'),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final bloc = context.read<EquipmentExportBloc>();
    final format = await showModalBottomSheet<ExportFormat>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Exportar inventario',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Se aplican los filtros de estado y categoría; la búsqueda por texto no se incluye.',
                style: TextStyle(color: AppColors.slate, fontSize: 12),
              ),
            ),
            for (final format in ExportFormat.values)
              ListTile(
                key: Key('export-${format.extension}'),
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(format.label),
                onTap: () => Navigator.of(sheetContext).pop(format),
              ),
          ],
        ),
      ),
    );
    if (format != null) {
      bloc.add(EquipmentExportRequested(format, statuses: statuses, typeId: typeId));
    }
  }
}
