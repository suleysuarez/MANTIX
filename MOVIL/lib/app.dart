import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/bloc/auth_bloc.dart';
import 'core/auth/bloc/permissions_cubit.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/requests/data/requests_repository.dart';

/// Raíz de la app. Recibe las dependencias ya construidas (ver `main.dart`) y las
/// reparte con `RepositoryProvider` y `BlocProvider`; las pantallas crean sus
/// propios Bloc por ruta.
class MantixApp extends StatefulWidget {
  const MantixApp({super.key, required this.authBloc, required this.requestsRepository, this.clerk});

  final AuthBloc authBloc;
  final RequestsRepository requestsRepository;

  /// Estado de Clerk ya iniciado, o `null` si no hay clave o falló el arranque.
  final ClerkAuthState? clerk;

  @override
  State<MantixApp> createState() => _MantixAppState();
}

class _MantixAppState extends State<MantixApp> {
  late final GoRouterRefreshStream _refresh = GoRouterRefreshStream(widget.authBloc.stream);
  late final GoRouter _router = createAppRouter(
    authBloc: widget.authBloc,
    refresh: _refresh,
    hasClerk: widget.clerk != null,
  );

  @override
  void dispose() {
    _router.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clerk = widget.clerk;
    return MultiRepositoryProvider(
      providers: [RepositoryProvider.value(value: widget.requestsRepository)],
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
          // Los widgets de Clerk necesitan su estado en el árbol, por encima del router.
          builder: clerk == null
              ? null
              : (context, child) => ClerkAuth(
                    authState: clerk,
                    child: ClerkErrorListener(child: child ?? const SizedBox.shrink()),
                  ),
        ),
      ),
    );
  }
}
