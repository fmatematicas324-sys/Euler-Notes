import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:euler_notes/core/local_db/local_database.dart';
import 'package:euler_notes/features/backup/data/backup_exporter.dart';
import 'package:euler_notes/features/backup/data/backup_service.dart';
import 'package:euler_notes/features/backup/data/backup_verifier.dart';
import 'package:euler_notes/features/backup/domain/backup_format.dart';
import 'package:euler_notes/features/backup/presentation/backup_screen.dart';
import 'package:euler_notes/features/notebooks/data/local_notebooks_repository.dart';
import 'package:euler_notes/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Selector de documentos de Android simulado: los «documentos» son archivos
/// de una carpeta de pruebas.
class FakeDocumentStore implements DocumentStore {
  FakeDocumentStore(this.dir);

  final Directory dir;
  bool cancelPicker = false;
  bool corruptCopy = false;
  bool failCopy = false;
  final created = <String>[];
  final deleted = <String>[];
  File? copiedFrom;

  File _file(String uri) =>
      File('${dir.path}/${Uri.parse(uri).pathSegments.last}');

  @override
  Future<String?> create(String suggestedName, String mimeType) async {
    if (cancelPicker) return null;
    final uri = 'content://docs/$suggestedName';
    _file(uri).createSync(); // Android crea el documento vacío al elegirlo
    created.add(uri);
    return uri;
  }

  @override
  Future<DocumentCopyReceipt> copyFrom(File file, String uri) async {
    copiedFrom = file;
    if (failCopy) throw PlatformException(code: 'copy_failed');
    final out = _file(uri);
    file.copySync(out.path);
    if (corruptCopy) {
      out.writeAsBytesSync(out.readAsBytesSync().sublist(1));
    }
    final check = await verifyFileSha(out);
    return DocumentCopyReceipt(bytes: out.lengthSync(), sha256: check);
  }

  @override
  Future<bool> delete(String uri) async {
    deleted.add(uri);
    final file = _file(uri);
    if (file.existsSync()) file.deleteSync();
    return true;
  }
}

Future<String> verifyFileSha(File file) async {
  try {
    return (await verifyBackupFile(file)).sha256;
  } on BackupException {
    return 'dañado';
  }
}

void main() {
  late Directory root;
  late Directory docs;
  late Directory temp;
  late LocalDatabase db;
  late FakeDocumentStore store;

  BackupService service({
    BackupPlatform platform = BackupPlatform.android,
    SavePathPicker? pick,
    BackupWriterFactory? openWriter,
  }) => BackupService(
    db,
    platform: platform,
    documents: store,
    pickSavePath: pick,
    tempDirectory: () async => temp,
    clock: () => DateTime(2026, 11, 6, 15, 30),
    openWriter: openWriter,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('euler-backup-service-');
    docs = await Directory('${root.path}/docs').create();
    temp = await Directory('${root.path}/cache').create();
    db = LocalDatabase(NativeDatabase.memory());
    store = FakeDocumentStore(docs);
    await LocalNotebooksRepository(db).create('Física');
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  group('Android (selector de documentos)', () {
    test('guarda la copia verificada y limpia lo temporal', () async {
      final phases = <BackupPhase>[];
      final summary = await service().export(
        onProgress: (p) => phases.add(p.phase),
      );
      expect(summary, isNotNull);
      expect(
        summary!.location,
        'content://docs/euler-notes-20261106-1530.eulernotes',
      );
      expect(summary.counts['notebooks'], 1);
      expect(store.deleted, isEmpty);
      final saved = File('${docs.path}/euler-notes-20261106-1530.eulernotes');
      expect((await verifyBackupFile(saved)).sha256, summary.sha256);
      expect(temp.listSync(), isEmpty); // sin restos en la caché
      expect(phases.first, BackupPhase.choosing);
      expect(phases, contains(BackupPhase.copying));
      expect(phases.last, BackupPhase.done);
    });

    test('si el usuario cancela el selector no se exporta nada', () async {
      store.cancelPicker = true;
      expect(await service().export(), isNull);
      expect(docs.listSync(), isEmpty);
      expect(temp.listSync(), isEmpty);
    });

    test('si el documento guardado no coincide, se borra', () async {
      store.corruptCopy = true;
      await expectLater(
        service().export(),
        throwsA(
          isA<BackupException>().having((e) => e.code, 'code', 'verify_failed'),
        ),
      );
      expect(store.deleted, store.created);
      expect(docs.listSync(), isEmpty);
      expect(temp.listSync(), isEmpty);
    });

    test('si falla la copia al destino, se borra el documento', () async {
      store.failCopy = true;
      await expectLater(
        service().export(),
        throwsA(
          isA<BackupException>().having((e) => e.code, 'code', 'copy_failed'),
        ),
      );
      expect(docs.listSync(), isEmpty);
      expect(temp.listSync(), isEmpty);
    });

    test('si falla la generación, se borra el documento vacío', () async {
      await expectLater(
        service(
          openWriter: (_) async =>
              throw const FileSystemException('No space left on device'),
        ).export(),
        throwsA(
          isA<BackupException>().having((e) => e.code, 'code', 'write_failed'),
        ),
      );
      expect(store.copiedFrom, isNull);
      expect(docs.listSync(), isEmpty);
      expect(temp.listSync(), isEmpty);
    });
  });

  group('escritorio y otras plataformas', () {
    test('Linux: escribe en la ruta elegida', () async {
      final path = '${root.path}/mi-copia.eulernotes';
      String? suggested;
      final summary = await service(
        platform: BackupPlatform.desktop,
        pick: (name) async {
          suggested = name;
          return path;
        },
      ).export();
      expect(suggested, 'euler-notes-20261106-1530.eulernotes');
      expect(summary!.location, path);
      await verifyBackupFile(File(path));
    });

    test('Linux: cancelar el diálogo no escribe nada', () async {
      final summary = await service(
        platform: BackupPlatform.desktop,
        pick: (_) async => null,
      ).export();
      expect(summary, isNull);
    });

    test('Web: avisa de que no está disponible', () async {
      await expectLater(
        service(platform: BackupPlatform.unsupported).export(),
        throwsA(
          isA<BackupException>().having(
            (e) => e.code,
            'code',
            'unsupported_platform',
          ),
        ),
      );
    });
  });

  group('pantalla', () {
    Widget app(BackupService service) => ProviderScope(
      overrides: [backupServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: SettingsScreen()),
    );

    testWidgets('Configuración → Datos → Copia de seguridad → Exportar', (
      tester,
    ) async {
      await tester.pumpWidget(app(service()));
      expect(find.text('Datos'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-backup')));
      await tester.pumpAndSettle();
      expect(find.byType(BackupScreen), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('backup-export')));
        // La exportación usa E/S real: se espera fuera del reloj falso.
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (find.byKey(const Key('backup-done')).evaluate().isNotEmpty) {
            break;
          }
          await tester.pump();
        }
      });
      await tester.pump();
      expect(find.byKey(const Key('backup-done')), findsOneWidget);
      expect(find.textContaining('1 cuadernos · 0 notas'), findsOneWidget);
      expect(
        find.textContaining('Copia completada y verificada'),
        findsOneWidget,
      );
    });

    testWidgets('informa si la copia falla', (tester) async {
      store.failCopy = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backupServiceProvider.overrideWithValue(service())],
          child: const MaterialApp(home: BackupScreen()),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('backup-export')));
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.byKey(const Key('backup-failed')).evaluate().isNotEmpty) {
            break;
          }
        }
      });
      await tester.pump();
      expect(find.byKey(const Key('backup-failed')), findsOneWidget);
      expect(
        find.textContaining('No se pudo escribir en el destino'),
        findsOneWidget,
      );
    });

    testWidgets('muestra el progreso mientras exporta', (tester) async {
      final gate = Completer<String?>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backupServiceProvider.overrideWithValue(
              service(
                platform: BackupPlatform.desktop,
                pick: (_) => gate.future,
              ),
            ),
          ],
          child: const MaterialApp(home: BackupScreen()),
        ),
      );
      await tester.tap(find.byKey(const Key('backup-export')));
      await tester.pump();
      expect(find.byKey(const Key('backup-progress')), findsOneWidget);
      expect(find.text(BackupPhase.choosing.label), findsOneWidget);
      gate.complete(null); // el usuario cierra el diálogo
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backup-progress')), findsNothing);
      expect(find.textContaining('No se eligió dónde guardar'), findsOneWidget);
    });
  });

  test('el canal nativo de Android usa el mismo nombre y métodos', () {
    final kotlin = File(
      'android/app/src/main/kotlin/dev/eulernotes/euler_notes/MainActivity.kt',
    ).readAsStringSync();
    expect(kotlin, contains('"dev.eulernotes/backup"'));
    for (final method in [
      'createDocument',
      'copyToDocument',
      'deleteDocument',
    ]) {
      expect(kotlin, contains('"$method"'));
    }
    expect(kotlin, contains('Intent.ACTION_CREATE_DOCUMENT'));
    expect(kotlin, isNot(contains('Log.'))); // nada en los logs
  });
}
