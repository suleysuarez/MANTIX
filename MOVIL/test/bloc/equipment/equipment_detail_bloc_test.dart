import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/equipment/equipment_detail_bloc.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  EquipmentDetailBloc build(FakeAdapter adapter) => EquipmentDetailBloc(
        equipmentId: 7,
        equipment: EquipmentRepository(dioWith(adapter)),
        requests: RequestsRepository(dioWith(adapter)),
      );

  final attachment = {'id': 5, 'file_name': 'factura.pdf', 'mime_type': 'application/pdf', 'file_size': 2048};

  test('carga tickets y adjuntos a la vez y conserva los dos resultados', () async {
    final adapter = FakeAdapter((options) => options.path.endsWith('/attachments') ? jsonResponse(200, [attachment]) : pagedResponse([ticketJson(id: 1)]));
    final bloc = build(adapter)..add(const EquipmentDetailStarted());
    await bloc.stream.firstWhere((state) => state.ticketsStatus != DetailPart.loading && state.attachmentsStatus != DetailPart.loading);

    expect(bloc.state.tickets.single.ticketNumber, 'TCK-0001');
    expect(bloc.state.attachments.single.fileName, 'factura.pdf');
    final ticketRequest = adapter.requests.firstWhere((r) => r.path == '/maintenance/requests');
    expect(ticketRequest.queryParameters, containsPair('equipment_id', 7));
    expect(ticketRequest.queryParameters, containsPair('size', EquipmentDetailBloc.ticketLimit));
    await bloc.close();
  });

  test('un fallo en los tickets no oculta los adjuntos, y al revés', () async {
    final adapter = FakeAdapter((options) => options.path.endsWith('/attachments') ? jsonResponse(200, [attachment]) : errorResponse(500));
    final bloc = build(adapter)..add(const EquipmentDetailStarted());
    await bloc.stream.firstWhere((state) => state.ticketsStatus == DetailPart.failure && state.attachmentsStatus == DetailPart.success);

    expect(bloc.state.ticketsFailure, isNotNull);
    expect(bloc.state.attachments, hasLength(1));
    await bloc.close();
  });

  blocTest<EquipmentDetailBloc, EquipmentDetailState>(
    'sin tickets ni adjuntos termina en éxito con listas vacías',
    build: () => build(FakeAdapter((options) => options.path.endsWith('/attachments') ? jsonResponse(200, []) : pagedResponse([]))),
    act: (bloc) => bloc.add(const EquipmentDetailStarted()),
    wait: const Duration(milliseconds: 50),
    verify: (bloc) {
      expect(bloc.state.ticketsStatus, DetailPart.success);
      expect(bloc.state.attachmentsStatus, DetailPart.success);
      expect(bloc.state.tickets, isEmpty);
    },
  );
}
