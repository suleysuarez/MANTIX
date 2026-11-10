import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/queue/queue_summary_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/repositories/queue/queue_repository.dart';

import '../../models/queue/queue_models_test.dart' show summaryJson;
import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  late ResponseBody Function(RequestOptions) handler;
  late FakeAdapter adapter;

  setUp(() {
    handler = (_) => jsonResponse(200, summaryJson);
    adapter = FakeAdapter((options) => handler(options));
  });

  QueueSummaryBloc build() => QueueSummaryBloc(repository: QueueRepository(dioWith(adapter)));

  test('empieza cargando y pasa a listo con el resumen', () async {
    final bloc = build();
    addTearDown(bloc.close);
    expect(bloc.state.status, SummaryStatus.loading);

    bloc.add(const QueueSummaryRequested());
    final ready = await bloc.stream.firstWhere((state) => state.status == SummaryStatus.ready);

    expect(ready.summary!.pendingTotal, 14);
    expect(ready.unavailable, isFalse);
  });

  test('si falla, queda «no disponible» con el error en español y se puede reintentar', () async {
    handler = (_) => errorResponse(500);
    final bloc = build();
    addTearDown(bloc.close);

    bloc.add(const QueueSummaryRequested());
    final failed = await bloc.stream.firstWhere((state) => state.status == SummaryStatus.failure);
    expect(failed.unavailable, isTrue);
    expect(failed.failure, isA<ServerFailure>());
    expect(failed.failure!.message, isNot(contains('interno')));

    handler = (_) => jsonResponse(200, summaryJson);
    bloc.add(const QueueSummaryRequested());
    final ready = await bloc.stream.firstWhere((state) => state.status == SummaryStatus.ready);
    expect(ready.failure, isNull);
    expect(ready.summary, isNotNull);
  });

  test('una recarga que falla conserva el último resumen en vez de mostrar «no disponible»', () async {
    final bloc = build();
    addTearDown(bloc.close);
    bloc.add(const QueueSummaryRequested());
    await bloc.stream.firstWhere((state) => state.status == SummaryStatus.ready);

    handler = (_) => errorResponse(500);
    bloc.add(const QueueSummaryRequested());
    final failed = await bloc.stream.firstWhere((state) => state.status == SummaryStatus.failure);

    expect(failed.summary, isNotNull);
    expect(failed.unavailable, isFalse);
  });

  test('sin permiso ve el motivo, no un error genérico', () async {
    handler = (_) => errorResponse(403, code: 'forbidden');
    final bloc = build();
    addTearDown(bloc.close);

    bloc.add(const QueueSummaryRequested());
    final failed = await bloc.stream.firstWhere((state) => state.status == SummaryStatus.failure);
    expect(failed.failure, isA<ForbiddenFailure>());
  });

  test('avisa cuando termina la carga, con éxito o con error', () async {
    final bloc = build();
    addTearDown(bloc.close);

    final ok = Completer<void>();
    bloc.add(QueueSummaryRequested(done: ok));
    await ok.future.timeout(const Duration(seconds: 2));
    expect(bloc.state.status, SummaryStatus.ready);

    handler = (_) => errorResponse(500);
    final failed = Completer<void>();
    bloc.add(QueueSummaryRequested(done: failed));
    await failed.future.timeout(const Duration(seconds: 2));
    expect(bloc.state.status, SummaryStatus.failure);
  });
}
