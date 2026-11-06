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
  bool failPicker = false;

  /// Nombres que «elige» el usuario en cada apertura del selector (`null` =
  /// cierra el selector). Vacío: acepta el nombre sugerido.
  final picks = <String?>[];
  final suggested = <String>[];

  /// El proveedor no deja saber si el documento tiene contenido.
  bool contentUnknown = false;
  bool contentThrows = false;
  bool failDelete = false;

  /// Cambia el hash devuelto tras copiar (simula un proveedor que guarda
  /// algo distinto o un hash recortado).
  String Function(String sha)? tamperSha;
  final created = <String>[];
  final deleted = <String>[];
  File? copiedFrom;

  File _file(String uri) =>
      File('${dir.path}/${Uri.parse(uri).pathSegments.last}');

  @override
  Future<String?> create(String suggestedName, String mimeType) async {
    if (failPicker) throw PlatformException(code: 'no_picker');
    if (cancelPicker) return null;
    suggested.add(suggestedName);
    final name = picks.isEmpty ? suggestedName : picks.removeAt(0);
    if (name == null) return null;
    final uri = 'content://docs/$name';
    // Un documento nuevo se crea vacío; uno existente se entrega tal cual.
    if (!_file(uri).existsSync()) _file(uri).createSync();
    created.add(uri);
    return uri;
  }

  @override
  Future<bool?> hasContent(String uri) async {
    if (contentThrows) throw PlatformException(code: 'query_failed');
    if (contentUnknown) return null;
    return _file(uri).lengthSync() > 0;
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
    return DocumentCopyReceipt(
      bytes: out.lengthSync(),
      sha256: tamperSha?.call(check) ?? check,
    );
  }

  @override
  Future<bool> delete(String uri) async {
    deleted.add(uri);
    if (failDelete) throw MissingPluginException();
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
    BackupReplacer? replace,
  }) => BackupService(
    db,
    platform: platform,
    documents: store,
    pickSavePath: pick,
    tempDirectory: () async => temp,
    clock: () => DateTime(2026, 11, 6, 15, 30),
    openWriter: openWriter,
    replace: replace,
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

  group('Android: hash completo, selector y proveedores', () {
    Matcher fails(String code) =>
        throwsA(isA<BackupException>().having((e) => e.code, 'code', code));

    test('un hash distinto solo en la última cifra se rechaza', () async {
      store.tamperSha = (sha) =>
          sha.substring(0, 63) + (sha.endsWith('0') ? '1' : '0');
      await expectLater(service().export(), fails('verify_failed'));
      expect(store.deleted, store.created);
      expect(docs.listSync(), isEmpty);
    });

    test('un hash recortado (prefijo correcto) se rechaza', () async {
      store.tamperSha = (sha) => sha.substring(0, 12);
      await expectLater(service().export(), fails('verify_failed'));
      expect(docs.listSync(), isEmpty);
    });

    test('un hash vacío (respuesta incompleta del canal) se rechaza', () async {
      store.tamperSha = (_) => '';
      await expectLater(service().export(), fails('verify_failed'));
      expect(docs.listSync(), isEmpty);
    });

    test('el mismo hash en mayúsculas se acepta', () async {
      store.tamperSha = (sha) => sha.toUpperCase();
      expect(await service().export(), isNotNull);
      expect(store.deleted, isEmpty);
    });

    test('si el selector falla no se crea nada', () async {
      store.failPicker = true;
      await expectLater(service().export(), fails('copy_failed'));
      expect(store.created, isEmpty);
      expect(docs.listSync(), isEmpty);
      expect(temp.listSync(), isEmpty);
    });

    test('un fallo al borrar no oculta el error original', () async {
      store.failCopy = true;
      store.failDelete = true;
      await expectLater(service().export(), fails('copy_failed'));
      expect(store.deleted, store.created);
      expect(temp.listSync(), isEmpty);
    });

    test('cancelar antes de copiar borra el documento vacío', () async {
      final cancel = BackupCancelToken();
      await expectLater(
        service().export(
          cancel: cancel,
          onProgress: (p) {
            if (p.phase == BackupPhase.verifying) cancel.cancel();
          },
        ),
        throwsA(isA<BackupException>().having((e) => e.cancelled, 'c', true)),
      );
      expect(store.copiedFrom, isNull);
      expect(store.deleted, store.created);
      expect(docs.listSync(), isEmpty);
      expect(temp.listSync(), isEmpty);
    });

    test('isFullSha256', () {
      expect(isFullSha256('a' * 64), isTrue);
      expect(isFullSha256('A' * 64), isTrue);
      expect(isFullSha256('a' * 63), isFalse);
      expect(isFullSha256('${'a' * 63}g'), isFalse);
      expect(isFullSha256(''), isFalse);
    });
  });

  group('Android: nunca sobrescribir una copia anterior', () {
    const oldName = 'copia-anterior.eulernotes';
    late File old;
    late List<int> oldBytes;

    Matcher fails(String code) =>
        throwsA(isA<BackupException>().having((e) => e.code, 'code', code));

    setUp(() async {
      // Copia anterior válida en la carpeta del proveedor.
      await service(
        platform: BackupPlatform.desktop,
        pick: (_) async {
          return '${docs.path}/$oldName';
        },
      ).export();
      old = File('${docs.path}/$oldName');
      oldBytes = old.readAsBytesSync();
      await LocalNotebooksRepository(db).create('Cálculo');
    });

    void expectOldIntact() {
      expect(old.readAsBytesSync(), oldBytes);
      expect(store.deleted, isNot(contains('content://docs/$oldName')));
    }

    test('elegir el archivo existente y no aceptar otro nombre', () async {
      store.picks.add(oldName);
      var asked = 0;
      await expectLater(
        service().export(
          onTargetExists: () async {
            asked++;
            return false;
          },
        ),
        fails('target_exists'),
      );
      expect(asked, 1);
      expectOldIntact();
      expect(store.copiedFrom, isNull);
      expect(store.deleted, isEmpty);
      expect(temp.listSync(), isEmpty);
    });

    test(
      'sin diálogo (onTargetExists ausente) tampoco se sobrescribe',
      () async {
        store.picks.add(oldName);
        await expectLater(service().export(), fails('target_exists'));
        expectOldIntact();
      },
    );

    test(
      'elegir otro nombre guarda la copia nueva y conserva la anterior',
      () async {
        store.picks.add(oldName); // la segunda vez acepta el sugerido
        final summary = await service().export(
          onTargetExists: () async => true,
        );
        expect(store.suggested, [
          'euler-notes-20261106-1530.eulernotes',
          'euler-notes-20261106-1530-2.eulernotes',
        ]);
        expect(
          summary!.location,
          'content://docs/euler-notes-20261106-1530-2.eulernotes',
        );
        expectOldIntact();
        final fresh = File(
          '${docs.path}/euler-notes-20261106-1530-2.eulernotes',
        );
        expect((await verifyBackupFile(fresh)).counts['notebooks'], 2);
        expect((await verifyBackupFile(old)).counts['notebooks'], 1);
      },
    );

    test(
      'si no se puede saber si tiene contenido, se trata como ocupado',
      () async {
        store.picks.add(oldName);
        store.contentUnknown = true;
        await expectLater(service().export(), fails('target_exists'));
        expectOldIntact();
        expect(store.copiedFrom, isNull);
      },
    );

    test('si la consulta del proveedor falla, se trata como ocupado', () async {
      store.picks.add(oldName);
      store.contentThrows = true;
      await expectLater(service().export(), fails('target_exists'));
      expectOldIntact();
    });

    test(
      'tras $maxNameAttempts nombres ocupados se rinde sin tocar nada',
      () async {
        store.picks.addAll(List.filled(maxNameAttempts, oldName));
        await expectLater(
          service().export(onTargetExists: () async => true),
          fails('target_exists'),
        );
        expect(store.suggested, hasLength(maxNameAttempts));
        expectOldIntact();
      },
    );

    test('un documento existente pero vacío sí se puede usar', () async {
      File('${docs.path}/vacio.eulernotes').createSync();
      store.picks.add('vacio.eulernotes');
      final summary = await service().export();
      expect(summary!.location, 'content://docs/vacio.eulernotes');
      expectOldIntact();
    });

    test('error al escribir: se borra solo el documento nuevo', () async {
      await expectLater(
        service(
          openWriter: (_) async =>
              throw const FileSystemException('No space left on device'),
        ).export(),
        fails('write_failed'),
      );
      expectOldIntact();
      expect(store.deleted, [
        'content://docs/euler-notes-20261106-1530.eulernotes',
      ]);
      expect(docs.listSync().map((e) => e.uri.pathSegments.last), [oldName]);
      expect(temp.listSync(), isEmpty);
    });

    test('error al verificar: se borra solo el documento nuevo', () async {
      await expectLater(
        service(
          openWriter: (file) async =>
              _Corrupting(await FileBackupWriter.open(file)),
        ).export(),
        fails('verify_failed'),
      );
      expect(store.copiedFrom, isNull);
      expectOldIntact();
      expect(docs.listSync().map((e) => e.uri.pathSegments.last), [oldName]);
    });

    test(
      'error al copiar al proveedor: se borra solo el documento nuevo',
      () async {
        store.failCopy = true;
        await expectLater(service().export(), fails('copy_failed'));
        expectOldIntact();
        expect(docs.listSync().map((e) => e.uri.pathSegments.last), [oldName]);
      },
    );

    test(
      'copia distinta en el proveedor: se borra solo el documento nuevo',
      () async {
        store.corruptCopy = true;
        await expectLater(service().export(), fails('verify_failed'));
        expectOldIntact();
        expect(docs.listSync().map((e) => e.uri.pathSegments.last), [oldName]);
      },
    );
  });

  group('escritorio: reemplazo atómico de un archivo local', () {
    late File old;
    late List<int> oldBytes;

    Future<BackupSummary?> exportTo(
      File file, {
      BackupWriterFactory? openWriter,
      BackupReplacer? replace,
    }) => service(
      platform: BackupPlatform.desktop,
      pick: (_) async => file.path,
      openWriter: openWriter,
      replace: replace,
    ).export();

    setUp(() async {
      old = File('${root.path}/mi-copia.eulernotes');
      await exportTo(old);
      oldBytes = old.readAsBytesSync();
      await LocalNotebooksRepository(db).create('Cálculo');
    });

    test(
      'éxito: la copia anterior se sustituye por la nueva verificada',
      () async {
        await exportTo(old);
        expect((await verifyBackupFile(old)).counts['notebooks'], 2);
        expect(File('${old.path}.partial').existsSync(), isFalse);
      },
    );

    test('error al escribir: la anterior queda intacta', () async {
      await expectLater(
        exportTo(
          old,
          openWriter: (_) async =>
              throw const FileSystemException('No space left on device'),
        ),
        throwsA(isA<BackupException>()),
      );
      expect(old.readAsBytesSync(), oldBytes);
      expect(File('${old.path}.partial').existsSync(), isFalse);
    });

    test('error al verificar: la anterior queda intacta', () async {
      await expectLater(
        exportTo(
          old,
          openWriter: (file) async =>
              _Corrupting(await FileBackupWriter.open(file)),
        ),
        throwsA(isA<BackupException>()),
      );
      expect(old.readAsBytesSync(), oldBytes);
      expect(File('${old.path}.partial').existsSync(), isFalse);
    });

    test('error al reemplazar: la anterior queda intacta', () async {
      await expectLater(
        exportTo(
          old,
          replace: (_, destination) async =>
              throw FileSystemException('rename falló', destination),
        ),
        throwsA(isA<BackupException>()),
      );
      expect(old.readAsBytesSync(), oldBytes);
      expect(File('${old.path}.partial').existsSync(), isFalse);
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

    testWidgets('muestra el SHA-256 completo y permite copiarlo', (
      tester,
    ) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
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
          if (find.byKey(const Key('backup-done')).evaluate().isNotEmpty) {
            break;
          }
        }
      });
      await tester.pump();
      final saved = File('${docs.path}/euler-notes-20261106-1530.eulernotes');
      final sha = (await tester.runAsync(() => verifyBackupFile(saved)))!
          .sha256;
      expect(sha, hasLength(64));
      final shown = tester.widget<SelectableText>(
        find.byKey(const Key('backup-sha256')),
      );
      expect(shown.data, sha); // completo, sin recortar

      await tester.tap(find.byKey(const Key('backup-copy-sha256')));
      await tester.pump();
      expect(clipboard, sha);
      expect(find.text('SHA-256 copiado'), findsOneWidget);
    });

    testWidgets('archivo existente: pregunta y no lo sobrescribe', (
      tester,
    ) async {
      final old = File('${docs.path}/anterior.eulernotes')
        ..writeAsStringSync('copia anterior\n');
      store.picks.add('anterior.eulernotes');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backupServiceProvider.overrideWithValue(service())],
          child: const MaterialApp(home: BackupScreen()),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('backup-export')));
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find
              .byKey(const Key('backup-target-exists'))
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
      });
      expect(find.byKey(const Key('backup-target-exists')), findsOneWidget);
      expect(old.readAsStringSync(), 'copia anterior\n');

      await tester.tap(find.byKey(const Key('backup-choose-another')));
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.byKey(const Key('backup-done')).evaluate().isNotEmpty) {
            break;
          }
        }
      });
      await tester.pump();
      expect(find.byKey(const Key('backup-done')), findsOneWidget);
      expect(old.readAsStringSync(), 'copia anterior\n');
      expect(store.suggested.last, 'euler-notes-20261106-1530-2.eulernotes');
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

/// Escritor que estropea un byte: la verificación debe detectarlo.
class _Corrupting implements BackupWriter {
  _Corrupting(this._inner);

  final BackupWriter _inner;
  bool _done = false;

  @override
  Future<void> write(List<int> bytes) async {
    if (!_done && bytes.length > 20) {
      _done = true;
      final copy = [...bytes];
      copy[10] = copy[10] ^ 0x01;
      return _inner.write(copy);
    }
    await _inner.write(bytes);
  }

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> abort() => _inner.abort();
}
