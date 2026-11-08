import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/auth/login_screen.dart';
import 'package:mantix/repositories/auth/mobile_auth_repository.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mocktail/mocktail.dart';

class _MockMobileAuthRepository extends Mock implements MobileAuthRepository {}

void main() {
  late _MockMobileAuthRepository repository;

  setUp(() => repository = _MockMobileAuthRepository());

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
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
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
  Future<void> registerAndReachVerification(WidgetTester tester) async {
    when(() => repository.register(email: any(named: 'email'), password: any(named: 'password'), firstName: any(named: 'firstName'), lastName: any(named: 'lastName'))).thenAnswer((_) async {});
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
    expect(find.text('Verifica tu correo'), findsOneWidget);
  }

  testWidgets('la contraseña del registro viaja junto al código al verificar el correo', (tester) async {
    when(() => repository.verifyEmail(email: any(named: 'email'), code: any(named: 'code'), password: any(named: 'password'))).thenAnswer((_) async {});
    await registerAndReachVerification(tester);

    await tester.enterText(field(0), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Verificar y continuar'));
    await tester.pumpAndSettle();

    verify(() => repository.verifyEmail(email: 'ana@mantix.test', code: '123456', password: 'Clave12345')).called(1);
  });

  testWidgets('si el código es incorrecto se puede reintentar sin volver a escribir la contraseña', (tester) async {
    var attempts = 0;
    when(() => repository.verifyEmail(email: any(named: 'email'), code: any(named: 'code'), password: any(named: 'password'))).thenAnswer((_) async {
      attempts++;
      if (attempts == 1) {
        throw DioException(
          requestOptions: RequestOptions(path: '/mobile-auth/verify-email'),
          response: Response(requestOptions: RequestOptions(path: '/mobile-auth/verify-email'), statusCode: 403, data: {'detail': 'El código no es válido o ha vencido.', 'code': 'auth_code_invalid'}),
          type: DioExceptionType.badResponse,
        );
      }
    });
    await registerAndReachVerification(tester);

    await tester.enterText(field(0), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Verificar y continuar'));
    await tester.pumpAndSettle();
    expect(find.text('El código no es válido o ha vencido.'), findsOneWidget);

    await tester.enterText(field(0), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Verificar y continuar'));
    await tester.pumpAndSettle();

    verify(() => repository.verifyEmail(email: 'ana@mantix.test', code: '123456', password: 'Clave12345')).called(1);
  });
  testWidgets('el registro envía el nombre y el apellido', (tester) async {
    await registerAndReachVerification(tester);

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

  testWidgets('desde la verificación se puede volver al registro conservando los datos', (tester) async {
    await registerAndReachVerification(tester);

    await tester.tap(find.text('Volver al registro'));
    await tester.pumpAndSettle();

    expect(find.text('Crea tu cuenta'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('ana@mantix.test'), findsOneWidget);
  });
}
