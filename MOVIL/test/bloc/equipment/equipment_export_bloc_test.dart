import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/equipment/equipment_export_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/equipment/export_models.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/device_fakes.dart';

class _MockEquipmentRepository extends Mock implements EquipmentRepository {}

void main() {
  late _MockEquipmentRepository repository;
  late FakeShare share;
  late FakeTempFiles temp;

  setUp(() {
    repository = _MockEquipmentRepository();
    share = FakeShare();
    temp = FakeTempFiles();
  });

  void stubDownload({Object? error, Future<void> Function()? wait}) => when(
        () => repository.downloadEquipmentReport(
          format: any(named: 'format'),
          savePath: any(named: 'savePath'),
          statuses: any(named: 'statuses'),
          typeId: any(named: 'typeId'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) async {
        if (wait != null) await wait();
        if (error != null) throw error;
        final onProgress = invocation.namedArguments[#onProgress] as void Function(double)?;
        onProgress?.call(0.5);
        onProgress?.call(1);
      });

  EquipmentExportBloc newBloc() {
    final bloc = EquipmentExportBloc(repository: repository, share: share, tempFiles: temp);
    addTearDown(bloc.close);
    return bloc;
  }

  Future<EquipmentExportState> export(EquipmentExportBloc bloc, ExportFormat format, {String? statuses, int? typeId}) async {
    bloc.add(EquipmentExportRequested(format, statuses: statuses, typeId: typeId));
    return bloc.stream.firstWhere((s) => s.status != ExportStatus.working && s.status != ExportStatus.idle);
  }

  test('exporta: descarga a un temporal, lo comparte y lo borra', () async {
    stubDownload();
    final bloc = newBloc();

    final result = await export(bloc, ExportFormat.xlsx, statuses: 'in_repair', typeId: 2);

    expect(result.status, ExportStatus.shared);
    final path = temp.created.single;
    expect(path, matches(RegExp(r'^/tmp/mantix_test/equipos-\d{4}-\d{2}-\d{2}\.xlsx$')));
    verify(() => repository.downloadEquipmentReport(format: 'xlsx', savePath: path, statuses: 'in_repair', typeId: 2, onProgress: any(named: 'onProgress'))).called(1);
    expect(share.shared.single.path, path);
    expect(share.shared.single.mimeType, ExportFormat.xlsx.mimeType);
    expect(temp.deleted, [path], reason: 'el temporal se borra después de compartir');
  });

  test('cada formato usa su extensión y su tipo', () async {
    stubDownload();
    final bloc = newBloc();

    await export(bloc, ExportFormat.csv);
    await export(bloc, ExportFormat.pdf);

    expect(temp.created.map((p) => p.split('.').last), ['csv', 'pdf']);
    expect(share.shared.map((s) => s.mimeType), ['text/csv', 'application/pdf']);
  });

  test('informa el avance de la descarga', () async {
    stubDownload();
    final bloc = newBloc();
    final progress = <double?>[];
    bloc.stream.listen((s) => progress.add(s.progress));

    await export(bloc, ExportFormat.csv);

    expect(progress, contains(0.5));
  });

  test('sin permiso (403) avisa y no comparte nada, pero borra el temporal', () async {
    stubDownload(error: const ForbiddenFailure());
    final bloc = newBloc();

    final result = await export(bloc, ExportFormat.xlsx);

    expect(result.status, ExportStatus.failure);
    expect(result.message, 'No tienes permiso para exportar el inventario.');
    expect(share.shared, isEmpty);
    expect(temp.deleted, temp.created);
  });

  test('un error de red avisa con el mensaje de conexión y borra el temporal', () async {
    stubDownload(error: const NetworkFailure());
    final bloc = newBloc();

    final result = await export(bloc, ExportFormat.xlsx);

    expect(result.status, ExportStatus.failure);
    expect(result.message, contains('Revisa tu conexión'));
    expect(share.shared, isEmpty);
    expect(temp.deleted, temp.created);
  });

  test('un error del servidor no filtra detalles internos', () async {
    stubDownload(error: const ServerFailure(code: 'internal_error'));
    final bloc = newBloc();

    final result = await export(bloc, ExportFormat.xlsx);

    expect(result.message, 'Algo salió mal en el servidor. Inténtalo más tarde.');
  });

  test('un archivo vacío se avisa y no se comparte', () async {
    stubDownload();
    temp.size = 0;
    final bloc = newBloc();

    final result = await export(bloc, ExportFormat.xlsx);

    expect(result.status, ExportStatus.empty);
    expect(result.message, 'No hay equipos para exportar con estos filtros.');
    expect(share.shared, isEmpty);
    expect(temp.deleted, temp.created);
  });

  test('si la hoja de compartir falla se avisa y se borra el temporal igualmente', () async {
    stubDownload();
    share.error = StateError('plugin roto');
    final bloc = newBloc();

    final result = await export(bloc, ExportFormat.xlsx);

    expect(result.status, ExportStatus.failure);
    expect(result.message, 'No pudimos abrir la hoja de compartir.');
    expect(result.message, isNot(contains('plugin roto')));
    expect(temp.deleted, temp.created);
  });

  test('si no se puede ni crear el temporal se avisa sin romper', () async {
    stubDownload();
    final broken = _BrokenTemp();
    final bloc = EquipmentExportBloc(repository: repository, share: share, tempFiles: broken);
    addTearDown(bloc.close);

    final result = await export(bloc, ExportFormat.xlsx);

    expect(result.status, ExportStatus.failure);
    expect(result.message, 'No pudimos preparar el archivo para exportar.');
    verifyNever(() => repository.downloadEquipmentReport(format: any(named: 'format'), savePath: any(named: 'savePath'), onProgress: any(named: 'onProgress')));
  });

  test('si no se puede borrar el temporal no cambia el resultado', () async {
    stubDownload();
    temp.deleteError = const FileSystemFailure();
    final bloc = newBloc();

    final result = await export(bloc, ExportFormat.xlsx);

    expect(result.status, ExportStatus.shared);
  });

  test('mientras exporta, otra petición se ignora', () async {
    final release = Completer<void>();
    stubDownload(wait: () => release.future);
    final bloc = newBloc();

    bloc.add(const EquipmentExportRequested(ExportFormat.xlsx));
    await bloc.stream.firstWhere((s) => s.status == ExportStatus.working);
    bloc.add(const EquipmentExportRequested(ExportFormat.csv));
    release.complete();
    await bloc.stream.firstWhere((s) => s.status == ExportStatus.shared);
    await Future<void>.delayed(Duration.zero);

    expect(temp.created, hasLength(1));
    verify(() => repository.downloadEquipmentReport(format: 'xlsx', savePath: any(named: 'savePath'), statuses: null, typeId: null, onProgress: any(named: 'onProgress'))).called(1);
    verifyNever(() => repository.downloadEquipmentReport(format: 'csv', savePath: any(named: 'savePath'), statuses: any(named: 'statuses'), typeId: any(named: 'typeId'), onProgress: any(named: 'onProgress')));
  });
}

class FileSystemFailure implements Exception {
  const FileSystemFailure();
}

class _BrokenTemp extends FakeTempFiles {
  @override
  Future<String> createPath(String fileName) async => throw const FileSystemFailure();
}
