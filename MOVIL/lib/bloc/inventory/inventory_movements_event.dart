part of 'inventory_movements_bloc.dart';

sealed class InventoryMovementsEvent { const InventoryMovementsEvent(); }

/// Carga (o recarga) el historial desde la primera página.
class InventoryMovementsStarted extends InventoryMovementsEvent { const InventoryMovementsStarted(); }

/// Pide la página siguiente (scroll infinito). No hace nada si ya no hay más o si ya está cargando.
class InventoryMovementsMoreRequested extends InventoryMovementsEvent { const InventoryMovementsMoreRequested(); }
