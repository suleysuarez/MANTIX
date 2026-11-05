import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/bloc/auth_bloc.dart';
import 'core/auth/bloc/permissions_cubit.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/mobile_auth_repository.dart';
import 'features/home/data/dashboard_repository.dart';
import 'features/requests/data/requests_repository.dart';

class MantixApp extends StatefulWidget {
  const MantixApp({
    super.key,
    required this.authBloc,
    required this.requestsRepository,
    required this.mobileAuthRepository,
    required this.dashboardRepository,
  });

  final AuthBloc authBloc;
  final RequestsRepository requestsRepository;
  final MobileAuthRepository mobileAuthRepository;
  final DashboardRepository dashboardRepository;

  @override
  State<MantixApp> createState() => _MantixAppState();
}

class _MantixAppState extends State<MantixApp> {
  late final GoRouterRefreshStream _refresh = GoRouterRefreshStream(widget.authBloc.stream);
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
        RepositoryProvider.value(value: widget.mobileAuthRepository),
        RepositoryProvider.value(value: widget.dashboardRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: widget.authBloc),
          BlocProvider(create: (_) => PermissionsCubit(widget.authBloc)),
        ],
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
    );
  }
}
