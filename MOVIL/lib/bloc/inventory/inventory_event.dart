part of 'inventory_bloc.dart';

sealed class InventoryEvent { const InventoryEvent(); }
class InventoryStarted extends InventoryEvent { const InventoryStarted(); }
class InventoryQueryChanged extends InventoryEvent {
  const InventoryQueryChanged({this.search = '', this.category, this.status, this.clearCategory = false, this.clearStatus = false});
  final String search;
  final String? category;
  final String? status;
  final bool clearCategory;
  final bool clearStatus;
}
class InventoryPageChanged extends InventoryEvent {
  const InventoryPageChanged(this.page);
  final int page;
}
class InventoryItemCreateRequested extends InventoryEvent {
  const InventoryItemCreateRequested(this.payload);
  final Map<String, Object?> payload;
}
class InventoryItemUpdateRequested extends InventoryEvent {
  const InventoryItemUpdateRequested(this.itemId, this.payload);
  final int itemId;
  final Map<String, Object?> payload;
}
class InventoryMovementRequested extends InventoryEvent {
  const InventoryMovementRequested({required this.itemId, required this.kind, required this.quantity, this.notes});
  final int itemId;
  final String kind;
  final int quantity;
  final String? notes;
}
