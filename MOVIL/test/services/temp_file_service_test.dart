import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/services/temp_file_service.dart';

/// Usa el disco de verdad (carpeta temporal del sistema), pero ningún plugin.
void main() {
  const service = SystemTempFileService();

  test('crea una ruta nueva que todavía no existe y la borra con su carpeta', () async {
    final path = await service.createPath('equipos-2026-11-09.xlsx');
    final file = File(path);

    expect(path, endsWith('equipos-2026-11-09.xlsx'));
    expect(file.existsSync(), isFalse);
    expect(file.parent.existsSync(), isTrue);

    await file.writeAsBytes(List.filled(2048, 1));
    expect(await service.length(path), 2048);

    await service.delete(path);
    expect(file.existsSync(), isFalse);
    expect(file.parent.existsSync(), isFalse);
  });

  test('el tamaño de un archivo que no existe es cero y borrarlo no falla', () async {
    final path = await service.createPath('nada.csv');

    expect(await service.length(path), 0);
    await service.delete(path);
    await service.delete(path);
  });

  test('cada archivo vive en su propia carpeta', () async {
    final a = await service.createPath('a.csv');
    final b = await service.createPath('a.csv');
    addTearDown(() async {
      await service.delete(a);
      await service.delete(b);
    });

    expect(File(a).parent.path, isNot(File(b).parent.path));
  });
}
