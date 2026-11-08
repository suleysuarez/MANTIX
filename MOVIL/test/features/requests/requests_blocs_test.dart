import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/page_info.dart';
import 'package:mantix/core/network/paged/paged_bloc.dart';
import 'package:mantix/models/requests/request_models.dart';
import 'package:mantix/features/requests/data/requests_repository.dart';
import 'package:mantix/features/requests/presentation/bloc/create_request_bloc.dart';
import 'package:mantix/features/requests/presentation/bloc/my_requests_bloc.dart';
import 'package:mantix/features/requests/presentation/bloc/request_detail_bloc.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fakes.dart';
import 'support.dart';

class MockRequestsRepository extends Mock implements RequestsRepository {}

const newRequest = NewRequest(equipmentId: 12, title: 'No enciende', description: 'Pantalla negra', priority: 'high');

TicketDetail detail({int id = 7}) => TicketDetail.fromJson(detailJson(id: id));

void main() {
  late MockRequestsRepository repository;
  setUp(() => repository = MockRequestsRepository());

  group('CreateRequestBloc', () {
    blocTest<CreateRequestBloc, CreateRequestState>(
      'enviar crea la solicitud y entrega el id del ticket',
      setUp: () => when(() => repository.create(newRequest)).thenAnswer((_) async => detail(id: 7)),
      build: () => CreateRequestBloc(repository: repository),
      act: (bloc) => bloc.add(const CreateRequestSubmitted(newRequest)),
      expect: () => [
        const CreateRequestState(status: CreateStatus.submitting),
        const CreateRequestState(status: CreateStatus.success, createdId: 7),
      ],
    );

    blocTest<CreateRequestBloc, CreateRequestState>(
      'un 422 conserva los errores por campo para mostrarlos bajo cada campo',
      setUp: () => when(() => repository.create(newRequest))
          .thenThrow(const ValidationFailure(fieldErrors: {'title': 'Título no válido'})),
      build: () => CreateRequestBloc(repository: repository),
      act: (bloc) => bloc.add(const CreateRequestSubmitted(newRequest)),
      expect: () => [
        const CreateRequestState(status: CreateStatus.submitting),
        const CreateRequestState(
          status: CreateStatus.failure,
          failure: ValidationFailure(fieldErrors: {'title': 'Título no válido'}),
        ),
      ],
    );

    blocTest<CreateRequestBloc, CreateRequestState>(
      'un error de servidor termina en fallo sin detalles internos',
      setUp: () => when(() => repository.create(newRequest)).thenThrow(const ServerFailure()),
      build: () => CreateRequestBloc(repository: repository),
      act: (bloc) => bloc.add(const CreateRequestSubmitted(newRequest)),
      expect: () => [
        const CreateRequestState(status: CreateStatus.submitting),
        const CreateRequestState(status: CreateStatus.failure, failure: ServerFailure()),
      ],
    );

    blocTest<CreateRequestBloc, CreateRequestState>(
      'un doble envío mientras se envía se ignora',
      setUp: () => when(() => repository.create(newRequest)).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return detail();
      }),
      build: () => CreateRequestBloc(repository: repository),
      act: (bloc) => bloc
        ..add(const CreateRequestSubmitted(newRequest))
        ..add(const CreateRequestSubmitted(newRequest)),
      wait: const Duration(milliseconds: 30),
      verify: (_) => verify(() => repository.create(newRequest)).called(1),
    );
  });

  group('RequestDetailBloc', () {
    blocTest<RequestDetailBloc, RequestDetailState>(
      'carga el ticket y por separado los adjuntos',
      setUp: () {
        when(() => repository.getRequest(7)).thenAnswer((_) async => detail());
        when(() => repository.listAttachments(7)).thenAnswer(
          (_) async => [const Attachment(id: 1, fileName: 'foto.png', mimeType: 'image/png', fileSize: 10)],
        );
      },
      build: () => RequestDetailBloc(repository: repository, requestId: 7),
      act: (bloc) => bloc
        ..add(const RequestDetailRequested())
        ..add(const RequestAttachmentsRequested()),
      verify: (bloc) {
        expect(bloc.state.status, LoadStatus.success);
        expect(bloc.state.ticket?.ticketNumber, 'TCK-0007');
        expect(bloc.state.attachmentsStatus, LoadStatus.success);
        expect(bloc.state.attachments.single.fileName, 'foto.png');
      },
    );

    blocTest<RequestDetailBloc, RequestDetailState>(
      'si fallan los adjuntos el ticket sigue visible',
      setUp: () {
        when(() => repository.getRequest(7)).thenAnswer((_) async => detail());
        when(() => repository.listAttachments(7)).thenThrow(const ServerFailure());
      },
      build: () => RequestDetailBloc(repository: repository, requestId: 7),
      act: (bloc) => bloc
        ..add(const RequestDetailRequested())
        ..add(const RequestAttachmentsRequested()),
      verify: (bloc) {
        expect(bloc.state.status, LoadStatus.success);
        expect(bloc.state.ticket, isNotNull);
        expect(bloc.state.attachmentsStatus, LoadStatus.failure);
      },
    );

    blocTest<RequestDetailBloc, RequestDetailState>(
      'un ticket que ya no existe termina en fallo con su mensaje',
      setUp: () => when(() => repository.getRequest(7)).thenThrow(const NotFoundFailure(message: 'La solicitud ya no existe.')),
      build: () => RequestDetailBloc(repository: repository, requestId: 7),
      act: (bloc) => bloc.add(const RequestDetailRequested()),
      verify: (bloc) {
        expect(bloc.state.status, LoadStatus.failure);
        expect(bloc.state.ticket, isNull);
        expect(bloc.state.failure?.message, 'La solicitud ya no existe.');
      },
    );

    test('reintentar tras un fallo recupera el ticket', () async {
      var fail = true;
      when(() => repository.getRequest(7)).thenAnswer((_) async => fail ? throw const NetworkFailure() : detail());
      final bloc = RequestDetailBloc(repository: repository, requestId: 7);
      addTearDown(bloc.close);
      bloc.add(const RequestDetailRequested());
      await bloc.stream.firstWhere((s) => s.status == LoadStatus.failure);

      fail = false;
      bloc.add(const RequestDetailRequested());
      await bloc.stream.firstWhere((s) => s.status == LoadStatus.success);

      expect(bloc.state.ticket, isNotNull);
      expect(bloc.state.failure, isNull);
    });
  });

  group('MyRequestsBloc', () {
    test('pide la primera página con el filtro de estado', () async {
      when(() => repository.changes).thenAnswer((_) => const Stream<void>.empty());
      when(() => repository.listRequests(page: 1, status: 'resolved')).thenAnswer(
        (_) async => PagedResult(items: [TicketListItem.fromJson(ticketJson(status: 'resolved'))]),
      );
      final bloc = MyRequestsBloc(repository: repository, status: 'resolved');
      addTearDown(bloc.close);

      bloc.add(const PagedStarted());
      await bloc.stream.firstWhere((s) => s.status == PagedStatus.success);

      expect(bloc.state.items.single.status, 'resolved');
      verify(() => repository.listRequests(page: 1, status: 'resolved')).called(1);
    });

    test('se recarga sola cuando se crea una solicitud', () async {
      final adapter = FakeAdapter((options) {
        if (options.method == 'POST') return jsonResponse(201, detailJson(id: 9));
        return pagedResponse([ticketJson()]);
      });
      final real = RequestsRepository(dioWith(adapter));
      final bloc = MyRequestsBloc(repository: real);
      addTearDown(bloc.close);
      bloc.add(const PagedStarted());
      await bloc.stream.firstWhere((s) => s.status == PagedStatus.success);
      int listCalls() => adapter.requests.where((r) => r.method == 'GET').length;
      expect(listCalls(), 1);

      await real.create(newRequest);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(listCalls(), 2, reason: 'el listado abierto vuelve a pedir la primera página');
    });
  });
}
