part of 'settings_bloc.dart';

class SettingsState extends Equatable {
  const SettingsState({this.loading = false, this.saving = false, this.health, this.categories = const [], this.organization, this.priorities = const [], this.failure, this.notice});
  final bool loading, saving;
  final SystemHealth? health;
  final List<CategoryAdmin> categories;
  final OrganizationSettings? organization;
  final List<PriorityAdmin> priorities;
  final Failure? failure;
  final String? notice;
  int get activeCategories => categories.where((item) => item.isActive).length;
  int get activePriorities => priorities.where((item) => item.isActive).length;
  SettingsState copyWith({bool? loading, bool? saving, SystemHealth? health, List<CategoryAdmin>? categories, OrganizationSettings? organization, List<PriorityAdmin>? priorities, Failure? failure, bool clearFailure = false, String? notice, bool clearNotice = false}) => SettingsState(
    loading: loading ?? this.loading, saving: saving ?? this.saving, health: health ?? this.health, categories: categories ?? this.categories,
    organization: organization ?? this.organization, priorities: priorities ?? this.priorities,
    failure: clearFailure ? null : (failure ?? this.failure), notice: clearNotice ? null : (notice ?? this.notice),
  );
  @override
  List<Object?> get props => [loading, saving, health, categories, organization, priorities, failure, notice];
}
