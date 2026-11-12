import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/paged/paged_bloc.dart';
import '../../bloc/profile/avatar_cubit.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/profile/profile_history_bloc.dart';
import '../../core/format/formatters.dart';
import '../../core/format/users_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/profile/profile_models.dart';
import '../../repositories/profile/profile_repository.dart';
import '../../services/device_services.dart';
import '../../widgets/home/mantix_app_bar.dart';
import '../../widgets/home/mantix_drawer.dart';
import '../../widgets/profile/profile_edit_sheet.dart';
import '../../widgets/profile/profile_header.dart';
import '../../widgets/profile/profile_sections.dart';
import '../../widgets/shared/empty_state.dart';
import '../../widgets/shared/skeleton.dart';

/// Mi perfil: foto, nombre, correo y roles; mis datos (editables con `perfil:editar`); mi
/// actividad reciente, paginada, y cerrar sesión. También es el inicio de quien no
/// tiene ningún permiso de las demás pantallas, así que sin los datos del servidor muestra lo que
/// ya sabe la sesión. Solo oculta y deshabilita: la autorización real es del backend.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.clock});

  /// La hora de «ahora» (se inyecta para probar el último acceso).
  final DateTime Function()? clock;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileBloc _profile;
  late final ProfileHistoryBloc _history;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final repository = context.read<ProfileRepository>();
    _profile = ProfileBloc(
      repository: repository,
      images: context.read<DeviceServices>().imagePicker,
    )..add(const ProfileRequested());
    _history = ProfileHistoryBloc(repository: repository)
      ..add(const PagedStarted());
  }

  @override
  void dispose() {
    unawaited(_profile.close());
    unawaited(_history.close());
    super.dispose();
  }

  Future<void> _refresh() {
    final done = Completer<void>();
    _profile.add(ProfileRequested(done: done));
    return Future.wait([done.future, _history.refresh()]);
  }

  Future<void> _edit(ProfileData data) async {
    final input = await showProfileEditSheet(
      context,
      fullName: data.fullName,
      phone: data.phone,
      email: data.email,
    );
    if (input == null || !mounted) return;
    _profile.add(
      ProfileSaveRequested(fullName: input.fullName, phone: input.phone),
    );
  }

  Future<void> _photo(ProfileData data) async {
    final action = await showPhotoMenu(context, hasPhoto: data.hasAvatar);
    if (action == null || !mounted) return;
    _profile.add(switch (action) {
      PhotoAction.camera => const ProfilePhotoRequested(
        ProfilePhotoSource.camera,
      ),
      PhotoAction.gallery => const ProfilePhotoRequested(
        ProfilePhotoSource.gallery,
      ),
      PhotoAction.remove => const ProfilePhotoRemoveRequested(),
    });
  }

  void _onState(BuildContext context, ProfileState state) {
    final messenger = ScaffoldMessenger.of(context);
    if (state.actionError != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(state.actionError!),
            backgroundColor: AppColors.error,
          ),
        );
    } else if (state.notice != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(state.notice!),
            backgroundColor: AppColors.navy,
          ),
        );
      // La actividad incluye lo que acaba de pasar.
      _history.add(const PagedRefreshed());
    }
  }

  @override
  Widget build(BuildContext context) {
    // El Perfil también es el inicio de quien no tiene otros permisos; solo se muestra con sesión activa.
    final session = context.watch<AuthBloc>().state.profile;
    if (session == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(semanticsLabel: 'Cargando'),
        ),
      );
    }
    final canEdit = session.can('perfil:editar');
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _profile),
        BlocProvider.value(value: _history),
      ],
      // Mi foto es la misma en el encabezado y el menú: cuando cambia aquí, se avisa a toda la app.
      child: BlocListener<ProfileBloc, ProfileState>(
        listenWhen: (previous, current) =>
            !identical(previous.avatar, current.avatar),
        listener: (context, state) =>
            context.read<AvatarCubit>().show(state.avatar),
        child: BlocListener<ProfileBloc, ProfileState>(
          listenWhen: (previous, current) =>
              (current.notice != null && previous.notice != current.notice) ||
              (current.actionError != null &&
                  previous.actionError != current.actionError),
          listener: _onState,
          child: Scaffold(
            backgroundColor: AppColors.canvas,
            appBar: MantixAppBar(profile: session),
            drawer: MantixDrawer(profile: session, selectedPath: '/perfil'),
            body: RefreshIndicator(
              color: AppColors.steel,
              onRefresh: _refresh,
              child: BlocBuilder<ProfileBloc, ProfileState>(
                builder: (context, state) {
                  final data = state.profile;
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.xxl,
                    ),
                    children: [
                      ProfileHeader(
                        name: data?.fullName ?? session.fullName,
                        email: data?.email ?? session.email,
                        roles: data != null
                            ? [
                                for (final role in data.roles)
                                  (code: role.code, name: role.name),
                              ]
                            : [
                                for (final code in session.roles)
                                  (code: code, name: code),
                              ],
                        avatar: state.avatar,
                        canEditPhoto: canEdit && data != null,
                        saving: state.saving,
                        onPhoto: () => _photo(data!),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ProfileSectionTitle(
                        'Mis datos',
                        trailing: canEdit && data != null
                            ? TextButton.icon(
                                onPressed: state.saving
                                    ? null
                                    : () => _edit(data),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Editar'),
                              )
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (state.initialLoading)
                        Semantics(
                          container: true,
                          label: 'Cargando tus datos',
                          child: const Skeleton(
                            height: 190,
                            radius: AppRadius.md,
                          ),
                        )
                      else if (data == null)
                        EmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'No pudimos cargar tus datos',
                          message: state.failure?.message,
                          actionLabel: 'Reintentar',
                          onAction: () =>
                              _profile.add(const ProfileRequested()),
                        )
                      else
                        ProfileInfoCard(
                          rows: [
                            (
                              Icons.person_outline_rounded,
                              'Nombre',
                              data.fullName,
                            ),
                            (Icons.email_outlined, 'Correo', data.email),
                            (Icons.phone_outlined, 'Teléfono', data.phone),
                            (
                              Icons.event_outlined,
                              'Miembro desde',
                              formatDate(data.createdAt),
                            ),
                            (
                              Icons.login_rounded,
                              'Último acceso',
                              data.lastLoginAt == null
                                  ? null
                                  : lastAccessText(data.lastLoginAt, _now),
                            ),
                          ],
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      BlocBuilder<
                        ProfileHistoryBloc,
                        PagedListState<HistoryEntry>
                      >(
                        builder: (context, history) => ProfileHistorySection(
                          state: history,
                          onPage: (page) =>
                              _history.add(PagedPageSelected(page)),
                          onRetry: () => _history.add(const PagedRefreshed()),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      OutlinedButton.icon(
                        onPressed: () => context.read<AuthBloc>().add(
                          const AuthSignOutRequested(),
                        ),
                        icon: const Icon(Icons.logout),
                        label: const Text('Cerrar sesión'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: AppColors.navy,
                          side: const BorderSide(color: AppColors.steel),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
