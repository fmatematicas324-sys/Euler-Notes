import 'package:euler_notes/core/api_client.dart';
import 'package:euler_notes/core/server_settings.dart';
import 'package:euler_notes/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_backend.dart';

void main() {
  group('normalizeServerUrl', () {
    for (final (input, expected) in [
      ('192.168.1.20:8000', 'http://192.168.1.20:8000'),
      ('  http://pc.local:8001/  ', 'http://pc.local:8001'),
      ('https://euler.example.org', 'https://euler.example.org'),
    ]) {
      test(input, () => expect(normalizeServerUrl(input), expected));
    }
    for (final input in ['', 'ftp://pc:21', 'http://', ':8000']) {
      test('inválida: «$input»', () {
        expect(() => normalizeServerUrl(input), throwsFormatException);
      });
    }
  });

  testWidgets('configurar el servidor lo guarda y reconecta', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final backend = FakeBackend()..offline = true;
    final hosts = <String>[];
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        httpClientProvider.overrideWithValue(backend.client),
      ],
    );
    addTearDown(container.dispose);
    container.listen(serverUrlProvider, (_, url) => hosts.add(url));

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const EulerNotesApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Sin conexión: se ofrece configurar el servidor.
    expect(find.text('Configurar servidor'), findsOneWidget);
    await tester.tap(find.text('Configurar servidor'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('server-url')), 'nada');
    backend.offline = false;
    await tester.enterText(
      find.byKey(const Key('server-url')),
      '192.168.1.20:8000',
    );
    await tester.tap(find.text('Probar conexión'));
    await tester.pumpAndSettle();
    expect(find.text('Conectado: backend v0.1.0'), findsOneWidget);

    backend.addNotebook('Desde la tablet');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(preferences.getString('server_url'), 'http://192.168.1.20:8000');
    expect(hosts, ['http://192.168.1.20:8000']);
    expect(find.text('Desde la tablet'), findsOneWidget);
  });

  testWidgets('una dirección inválida no se guarda', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final backend = FakeBackend();
    await pumpApp(
      tester,
      backend,
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    await tester.tap(find.byTooltip('Servidor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('server-url')), 'ftp://pc');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dirección no válida'), findsOneWidget);
    expect(preferences.getString('server_url'), isNull);
  });
}
