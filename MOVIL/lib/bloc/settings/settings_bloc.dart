import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../core/errors/failure.dart';
import '../../core/errors/failure_mapper.dart';
import '../../models/settings/settings_models.dart';
import '../../repositories/settings/settingsrepository.dart';

part 'settings_event.dart';
part 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({required this.repository}) : super(const SettingsState()) {
    on<SettingsStarted>((event, emit) => _load(emit));
    on<SettingsRefreshRequested>((event, emit) async { try { await _load(emit); } finally { if (event.done != null && !event.done!.isCompleted) event.done!.complete(); } });
    on<OrganizationSaveRequested>(_onOrganizationSave);
    on<CategoryCreateRequested>(_onCategoryCreate);
    on<CategoryUpdateRequested>(_onCategoryUpdate);
    on<CategoryDeleteRequested>(_onCategoryDelete);
    on<PriorityUpdateRequested>(_onPriorityUpdate);
  }

  final SettingsRepository repository;

  Future<void> _load(Emitter<SettingsState> emit, {bool showLoading = true}) async {
    if (showLoading) emit(state.copyWith(loading: true, clearFailure: true));
    try {
      final values = await Future.wait<Object>([
        _repository.health(), _repository.categories(), _repository.organization(), _repository.priorities(),
      ]);
      emit(state.copyWith(loading: false, health: values[0] as SystemHealth, categories: values[1] as List<CategoryAdmin>,
        organization: values[2] as OrganizationSettings, priorities: values[3] as List<PriorityAdmin>, clearFailure: true));
    } catch (error) { emit(state.copyWith(loading: false, failure: toFailure(error))); }
  }

  Future<void> _onOrganizationSave(OrganizationSaveRequested event, Emitter<SettingsState> emit) async =>
      _mutate(emit, 'Datos de la organización guardados.', () => _repository.saveOrganization(event.companyName));
  Future<void> _onCategoryCreate(CategoryCreateRequested event, Emitter<SettingsState> emit) async =>
      _mutate(emit, 'Categoría creada.', () => _repository.createCategory(code: event.code, name: event.name));
  Future<void> _onCategoryUpdate(CategoryUpdateRequested event, Emitter<SettingsState> emit) async =>
      _mutate(emit, 'Categoría actualizada.', () => _repository.updateCategory(event.id, name: event.name, isActive: event.isActive));
  Future<void> _onCategoryDelete(CategoryDeleteRequested event, Emitter<SettingsState> emit) async =>
      _mutate(emit, 'Categoría eliminada.', () => _repository.deleteCategory(event.id));
  Future<void> _onPriorityUpdate(PriorityUpdateRequested event, Emitter<SettingsState> emit) async =>
      _mutate(emit, 'Prioridad actualizada.', () => _repository.updatePriority(event.id, name: event.name, level: event.level, slaHours: event.slaHours, clearSla: event.clearSla, isActive: event.isActive));

  Future<void> _mutate(Emitter<SettingsState> emit, String success, Future<void> Function() action) async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, clearFailure: true, clearNotice: true));
    try {
      await action();
      emit(state.copyWith(saving: false, notice: success));
      await _load(emit, showLoading: false);
    } catch (error) { emit(state.copyWith(saving: false, failure: toFailure(error))); }
  }
}
