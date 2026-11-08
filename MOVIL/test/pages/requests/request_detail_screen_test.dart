import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/requests/request_detail_screen.dart';
import 'package:mantix/widgets/shared/skeleton.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

ResponseBodyHandler routes({
  Object? attachments,
  bool attachmentsFail = false,
  int detailStatus = 200,
}) =>
    (options) {
      if (options.path.endsWith('/attachments')) {
        return attachmentsFail ? errorResponse(500) : jsonResponse(200, attachments ?? <Object?>[]);
      }
      return detailStatus == 200 ? jsonResponse(200, detailJson()) : errorResponse(detailStatus, code: 'ticket_not_found');
    };

typedef ResponseBodyHandler = ResponseBody Function(RequestOptions options);

void main() {
  testWidgets('muestra esqueleto, luego datos, técnico, historial y adjuntos', (tester) async {
    final adapter = FakeAdapter(routes(attachments: [
      {'id': 1, 'file_name': 'foto.jpg', 'mime_type': 'image/jpeg', 'file_size': 2048},
    ]));
    await pumpScreen(tester, const RequestDetailScreen(requestId: 1), adapter);
    expect(find.byType(SkeletonList), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('TCK-0001'), findsOneWidget);
    expect(find.text('La laptop no enciende'), findsOneWidget);
    expect(find.text('EQ-0012 · Dell Latitude'), findsOneWidget);
    expect(find.text('Luis Técnico'), findsOneWidget);
    expect(find.text('Enviado → Asignado'), findsOneWidget);
    expect(find.text('Revisar hoy'), findsOneWidget);
    expect(find.text('foto.jpg'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
  });

  testWidgets('sin adjuntos lo dice', (tester) async {
    await pumpScreen(tester, const RequestDetailScreen(requestId: 1), FakeAdapter(routes()));
    await tester.pumpAndSettle();
    expect(find.text('Esta solicitud no tiene adjuntos.'), findsOneWidget);
  });

  testWidgets('si fallan los adjuntos el resto del detalle sigue visible', (tester) async {
    await pumpScreen(tester, const RequestDetailScreen(requestId: 1), FakeAdapter(routes(attachmentsFail: true)));
    await tester.pumpAndSettle();
    expect(find.text('La laptop no enciende'), findsOneWidget);
    expect(find.text('No pudimos cargar los adjuntos.'), findsOneWidget);
  });

  testWidgets('un ticket que ya no existe muestra el mensaje específico', (tester) async {
    await pumpScreen(tester, const RequestDetailScreen(requestId: 99), FakeAdapter(routes(detailStatus: 404)));
    await tester.pumpAndSettle();
    expect(find.text('Este ticket ya no existe.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
