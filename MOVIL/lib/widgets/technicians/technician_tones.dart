import '../../core/theme/app_colors.dart';
import '../../models/technicians/technician_filters.dart';

export '../../core/theme/app_colors.dart' show ChipColors;

/// Color de cada estado de un técnico, con los tonos de estado del tema: verde para quien está
/// libre, ámbar para quien tiene tickets y gris para quien no está disponible. El texto del
/// estado acompaña siempre al color.
ChipColors statusTone(TechnicianStatus status) => switch (status) {
      TechnicianStatus.free => StatusColors.resolved,
      TechnicianStatus.busy => StatusColors.inProgress,
      TechnicianStatus.unavailable => StatusColors.closed,
    };

/// Tono sobrio de la marca para lo que no es un estado (cifras generales, especialidades).
const ChipColors neutralTone = EquipmentColors.info;

/// Cuenta de usuario inactiva.
const ChipColors inactiveTone = StatusColors.cancelled;

/// Aviso de «pocos datos» en un indicador.
const ChipColors fewDataTone = StatusColors.inProgress;
