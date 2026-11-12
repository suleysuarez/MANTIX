import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/auth/login_screen.dart';
import 'package:mantix/widgets/auth/auth_shell.dart';
import 'package:mantix/repositories/auth/mobile_auth_repository.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mocktail/mocktail.dart';

class _MockMobileAuthRepository extends Mock implements MobileAuthRepository {}

void main() {
  late _MockMobileAuthRepository repository;

  setUp(() {
    repository = _MockMobileAuthRepository();
    when(() => repository.login(email: any(named: 'email'), password: any(named: 'password'))).thenAnswer((_) async {});
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<MobileAuthRepository>.value(
        value: repository,
        child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(int index) => find.byType(TextFormField).at(index);

  testWidgets('muestra el formulario de inicio de sesión', (tester) async {
    await pumpLogin(tester);

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Iniciar sesión'), findsOneWidget);
    expect(find.text('Crear una cuenta'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsNothing, reason: 'ya no hay recuperación por correo');
  });

  testWidgets('con un correo inválido muestra el error y no llama al servidor', (tester) async {
    await pumpLogin(tester);

    await tester.enterText(field(0), 'no-es-un-correo');
    await tester.enterText(field(1), 'cualquiera');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe un correo válido.'), findsOneWidget);
    verifyNever(() => repository.login(email: any(named: 'email'), password: any(named: 'password')));
  });

  testWidgets('envía el correo recortado y la contraseña al iniciar sesión', (tester) async {
    when(() => repository.login(email: any(named: 'email'), password: any(named: 'password'))).thenAnswer((_) async {});
    await pumpLogin(tester);

    await tester.enterText(field(0), '  ana@mantix.test ');
    await tester.enterText(field(1), 'Clave12345');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();

    verify(() => repository.login(email: 'ana@mantix.test', password: 'Clave12345')).called(1);
  });

  testWidgets('un fallo de red muestra un mensaje sin detalles internos', (tester) async {
    when(() => repository.login(email: any(named: 'email'), password: any(named: 'password'))).thenThrow(
      DioException(requestOptions: RequestOptions(path: '/mobile-auth/login'), type: DioExceptionType.connectionError, message: 'SocketException 10.0.2.2:8001'),
    );
    await pumpLogin(tester);

    await tester.enterText(field(0), 'ana@mantix.test');
    await tester.enterText(field(1), 'Clave12345');
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No logramos comunicarnos con Mantix'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
  });

  testWidgets('crear una cuenta pide confirmar la contraseña y exige que coincidan', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Crea tu cuenta'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(5));

    await tester.enterText(field(0), 'Ana');
    await tester.enterText(field(2), 'ana@mantix.test');
    await tester.enterText(field(3), 'Clave12345');
    await tester.enterText(field(4), 'Otra123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();

    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    verifyNever(() => repository.register(email: any(named: 'email'), password: any(named: 'password'), firstName: any(named: 'firstName'), lastName: any(named: 'lastName')));
  });
  /// Abre el registro, escribe los datos de Ana y lo envía (sin simular nada: cada prueba decide qué responde el servidor).
  Future<void> submitRegistration(WidgetTester tester) async {
    await pumpLogin(tester);
    await tester.tap(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();
    await tester.enterText(field(0), 'Ana');
    await tester.enterText(field(1), 'Pérez');
    await tester.enterText(field(2), 'ana@mantix.test');
    await tester.enterText(field(3), 'Clave12345');
    await tester.enterText(field(4), 'Clave12345');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();
  }

  Future<void> registerAccount(WidgetTester tester) async {
    when(() => repository.register(email: any(named: 'email'), password: any(named: 'password'), firstName: any(named: 'firstName'), lastName: any(named: 'lastName'))).thenAnswer((_) async {});
    await submitRegistration(tester);
  }

  testWidgets('al crear la cuenta se inicia sesión enseguida, sin pedir ningún código', (tester) async {
    await registerAccount(tester);

    verify(() => repository.register(email: 'ana@mantix.test', password: 'Clave12345', firstName: 'Ana', lastName: 'Pérez')).called(1);
    verify(() => repository.login(email: 'ana@mantix.test', password: 'Clave12345')).called(1);
    expect(find.text('Verifica tu correo'), findsNothing);
    expect(find.text('Código de 6 dígitos'), findsNothing);
  });

  testWidgets('si la cuenta se crea pero el inicio de sesión falla, vuelve al acceso con un aviso', (tester) async {
    when(() => repository.login(email: any(named: 'email'), password: any(named: 'password'))).thenThrow(
      DioException(requestOptions: RequestOptions(path: '/mobile-auth/login'), type: DioExceptionType.connectionError),
    );
    await registerAccount(tester);

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(find.text('Tu cuenta se creó. Inicia sesión para continuar.'), findsOneWidget);
  });

  testWidgets('un correo ya registrado se explica y no inicia sesión', (tester) async {
    when(() => repository.register(email: any(named: 'email'), password: any(named: 'password'), firstName: any(named: 'firstName'), lastName: any(named: 'lastName'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/mobile-auth/register'),
        response: Response(requestOptions: RequestOptions(path: '/mobile-auth/register'), statusCode: 409, data: {'detail': 'Ya existe una cuenta con este correo.', 'code': 'user_email_taken'}),
        type: DioExceptionType.badResponse,
      ),
    );
    await submitRegistration(tester);

    expect(find.text('Ya existe una cuenta con este correo.'), findsOneWidget);
    expect(find.text('Crea tu cuenta'), findsOneWidget);
    verifyNever(() => repository.login(email: any(named: 'email'), password: any(named: 'password')));
  });

  testWidgets('el registro envía el nombre y el apellido', (tester) async {
    await registerAccount(tester);

    verify(() => repository.register(email: 'ana@mantix.test', password: 'Clave12345', firstName: 'Ana', lastName: 'Pérez')).called(1);
  });

  testWidgets('el apellido es opcional pero el nombre es obligatorio', (tester) async {
    when(() => repository.register(email: any(named: 'email'), password: any(named: 'password'), firstName: any(named: 'firstName'), lastName: any(named: 'lastName'))).thenAnswer((_) async {});
    await pumpLogin(tester);
    await tester.tap(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();

    await tester.enterText(field(2), 'ana@mantix.test');
    await tester.enterText(field(3), 'Clave12345');
    await tester.enterText(field(4), 'Clave12345');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe tu nombre.'), findsOneWidget);
    verifyNever(() => repository.register(email: any(named: 'email'), password: any(named: 'password'), firstName: any(named: 'firstName'), lastName: any(named: 'lastName')));

    await tester.enterText(field(0), 'Ana');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();
    verify(() => repository.register(email: 'ana@mantix.test', password: 'Clave12345', firstName: 'Ana', lastName: '')).called(1);
  });

  Future<void> pumpRegisterOn(WidgetTester tester, Size size, {double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<MobileAuthRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: app!,
          ),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();
  }

  testWidgets('en el registro los campos obligatorios llevan asterisco y el apellido no', (tester) async {
    await pumpRegisterOn(tester, const Size(393, 852));

    for (final label in ['Nombre *', 'Correo electrónico *', 'Contraseña *', 'Confirmar contraseña *']) {
      expect(find.text(label, findRichText: true), findsOneWidget, reason: label);
    }
    expect(find.text('Apellido'), findsOneWidget);
    expect(find.text('Apellido *', findRichText: true), findsNothing);
    expect(find.textContaining('Obligatorio'), findsOneWidget);
  });

  testWidgets('el inicio de sesión no lleva asteriscos', (tester) async {
    await pumpLogin(tester);

    expect(find.textContaining(' *', findRichText: true), findsNothing);
  });

  testWidgets('el nombre y el apellido comparten fila', (tester) async {
    await pumpRegisterOn(tester, const Size(393, 852));

    expect(tester.getTopLeft(find.byType(TextFormField).at(0)).dy, tester.getTopLeft(find.byType(TextFormField).at(1)).dy);
  });

  for (final size in const [Size(393, 852), Size(360, 800)]) {
    testWidgets('la tarjeta de registro cabe bajo el logo sin desplazarse en ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await pumpRegisterOn(tester, size);

      final scrollable = find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Scrollable)).first;
      expect(tester.takeException(), isNull);
      expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent, 0, reason: 'la tarjeta debe caber sin moverse');
    });
  }

  testWidgets('con la fuente más grande la tarjeta se desplaza solo dentro de su zona', (tester) async {
    await pumpRegisterOn(tester, const Size(360, 800), textScale: 1.4);

    final top = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(find.byType(SingleChildScrollView)).dy, top);
    expect(find.byType(AuthShell), findsOneWidget);
  });
}
