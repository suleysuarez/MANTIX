import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../bloc/auth/auth_bloc.dart';
import '../bloc/auth/permissions_cubit.dart';
import '../bloc/notifications/notifications_bloc.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';
import '../repositories/auth/mobile_auth_repository.dart';
import '../repositories/catalogs/catalogs_repository.dart';
import '../repositories/equipment/equipment_repository.dart';
import '../repositories/home/dashboard_repository.dart';
import '../repositories/queue/queue_repository.dart';
import '../repositories/notifications/notifications_repository.dart';
import '../repositories/requests/requests_repository.dart';
import '../services/device_services.dart';

class MantixApp extends StatefulWidget {
  const MantixApp({
    super.key,
    required this.authBloc,
    required this.requestsRepository,
    required this.catalogsRepository,
    required this.mobileAuthRepository,
    required this.dashboardRepository,
    required this.equipmentRepository,
    required this.notificationsRepository,
    required this.queueRepository,
    this.deviceServices,
  });

  final AuthBloc authBloc;
  final RequestsRepository requestsRepository;
  final CatalogsRepository catalogsRepository;
  final MobileAuthRepository mobileAuthRepository;
  final DashboardRepository dashboardRepository;
  final EquipmentRepository equipmentRepository;
  final NotificationsRepository notificationsRepository;
  final QueueRepository queueRepository;

  /// Cámara, selectores, compartir y archivos temporales; las pruebas pasan simulacros.
  final DeviceServices? deviceServices;

  @override
  State<MantixApp> createState() => _MantixAppState();
}

class _MantixAppState extends State<MantixApp> {
  late final GoRouterRefreshStream _refresh = GoRouterRefreshStream(widget.authBloc.stream);
  late final DeviceServices _device = widget.deviceServices ?? DeviceServices();
  late final GoRouter _router = createAppRouter(authBloc: widget.authBloc, refresh: _refresh);

  @override
  void dispose() {
    _router.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: widget.requestsRepository),
        RepositoryProvider.value(value: widget.catalogsRepository),
        RepositoryProvider.value(value: widget.mobileAuthRepository),
        RepositoryProvider.value(value: widget.dashboardRepository),
        RepositoryProvider.value(value: widget.equipmentRepository),
        RepositoryProvider.value(value: widget.notificationsRepository),
        RepositoryProvider.value(value: widget.queueRepository),
        RepositoryProvider.value(value: _device),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: widget.authBloc),
          BlocProvider(create: (_) => PermissionsCubit(widget.authBloc)),
          BlocProvider(create: (_) => NotificationsBloc(repository: widget.notificationsRepository)),
        ],
        // Las notificaciones se cargan al iniciar sesión y se vacían al cerrarla.
        child: BlocListener<AuthBloc, AuthState>(
          listenWhen: (previous, current) => (previous is Authenticated) != (current is Authenticated),
          listener: (context, state) => context.read<NotificationsBloc>().add(state is Authenticated ? const NotificationsLoaded() : const NotificationsCleared()),
          child: MaterialApp.router(
          title: 'Mantix',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          routerConfig: _router,
          locale: const Locale('es'),
          supportedLocales: const [Locale('es')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
        ),
      ),
    );
  }
}
