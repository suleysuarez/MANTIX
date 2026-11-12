part of 'settings_bloc.dart';

sealed class SettingsEvent { const SettingsEvent(); }
class SettingsStarted extends SettingsEvent { const SettingsStarted(); }
class SettingsRefreshRequested extends SettingsEvent { const SettingsRefreshRequested([this.done]); final Completer<void>? done; }
class OrganizationSaveRequested extends SettingsEvent { const OrganizationSaveRequested(this.companyName); final String companyName; }
class CategoryCreateRequested extends SettingsEvent { const CategoryCreateRequested({required this.code, required this.name}); final String code, name; }
class CategoryUpdateRequested extends SettingsEvent { const CategoryUpdateRequested({required this.id, this.name, this.isActive}); final int id; final String? name; final bool? isActive; }
class CategoryDeleteRequested extends SettingsEvent { const CategoryDeleteRequested(this.id); final int id; }
class PriorityUpdateRequested extends SettingsEvent {
  const PriorityUpdateRequested({required this.id, this.name, this.level, this.slaHours, this.clearSla = false, this.isActive});
  final int id; final String? name; final int? level, slaHours;
  final bool clearSla; final bool? isActive;
}
