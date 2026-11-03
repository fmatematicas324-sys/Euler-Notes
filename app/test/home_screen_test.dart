import 'package:cuaderno_cientifico/app.dart';
import 'package:cuaderno_cientifico/core/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget _appWith(MockClient mock) => ProviderScope(
  overrides: [httpClientProvider.overrideWithValue(mock)],
  child: const CuadernoApp(),
);

void main() {
  testWidgets('muestra la versión cuando el backend responde', (tester) async {
    await tester.pumpWidget(
      _appWith(
        MockClient(
          (_) async => http.Response('{"status":"ok","version":"0.1.0"}', 200),
        ),
      ),
    );
    expect(find.text('Cuaderno Científico'), findsOneWidget);
    expect(find.text('Conectando con el backend…'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Backend conectado (v0.1.0)'), findsOneWidget);
  });

  testWidgets('ofrece reintentar cuando el backend no responde', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _appWith(
        MockClient((_) async {
          calls++;
          throw http.ClientException('sin conexión');
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Backend no disponible'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
