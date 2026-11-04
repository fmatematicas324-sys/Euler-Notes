import 'dart:convert';

import 'package:cuaderno_cientifico/core/api_client.dart';
import 'package:cuaderno_cientifico/features/plot/domain/plot_spec.dart';
import 'package:cuaderno_cientifico/features/plot/presentation/plot_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend());

  Widget host(PlotSpec spec, {Brightness brightness = Brightness.light}) =>
      ProviderScope(
        overrides: [httpClientProvider.overrideWithValue(backend.client)],
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 640, child: PlotView(spec: spec)),
            ),
          ),
        ),
      );

  Future<void> pumpHost(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(2000, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  testWidgets('pide la gráfica con ancho, tema y escala del dispositivo', (
    tester,
  ) async {
    await pumpHost(
      tester,
      host(const PlotSpec(exprs: ['sin(x)']), brightness: Brightness.dark),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(backend.plotRequests.single, {
      'exprs': ['sin(x)'],
      'var': 'x',
      'x_min': -10.0,
      'x_max': 10.0,
      'theme': 'dark',
      'width': 600, // 640 redondeado a múltiplos de 50
      'height': 300,
      'scale': 2.0,
    });
  });

  testWidgets('cambios rápidos: espera y pide solo la última versión', (
    tester,
  ) async {
    await pumpHost(tester, host(const PlotSpec(exprs: ['x'])));
    expect(backend.plotRequests, hasLength(1));

    for (final expr in ['x^', 'x^2', 'x^2 +', 'x^2 + 1']) {
      await tester.pumpWidget(host(PlotSpec(exprs: [expr])));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(backend.plotRequests, hasLength(1));

    await tester.pump(PlotView.debounce);
    await tester.pumpAndSettle();
    expect(backend.plotRequests, hasLength(2));
    expect(backend.plotRequests.last['exprs'], ['x^2 + 1']);
  });

  testWidgets('volver a una gráfica ya pedida sale de la caché', (
    tester,
  ) async {
    await pumpHost(tester, host(const PlotSpec(exprs: ['cos(x)'])));
    await tester.pumpWidget(host(const PlotSpec(exprs: ['sin(x)'])));
    await tester.pump(PlotView.debounce);
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(const PlotSpec(exprs: ['cos(x)'])));
    await tester.pump(PlotView.debounce);
    await tester.pumpAndSettle();

    expect(backend.plotRequests.map((r) => r['exprs']), [
      ['cos(x)'],
      ['sin(x)'],
    ]);
  });

  testWidgets('muestra el error del backend', (tester) async {
    backend.onPlot = (_) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'error': {
            'code': 'invalid_expression',
            'message': '«a*x» solo puede depender de x (contiene a)',
          },
        }),
      ),
      400,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    await pumpHost(tester, host(const PlotSpec(exprs: ['a*x'])));

    expect(find.textContaining('solo puede depender de x'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('tras un error, Reintentar vuelve a pedir la gráfica', (
    tester,
  ) async {
    var fail = true;
    final defaultPlot = backend.onPlot;
    backend.onPlot = (request) => fail
        ? http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'error': {
                  'code': 'compute_timeout',
                  'message': 'El cálculo superó el límite de 5 s',
                },
              }),
            ),
            408,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )
        : defaultPlot(request);
    await pumpHost(tester, host(const PlotSpec(exprs: ['sin(x)'])));
    expect(find.textContaining('límite de 5 s'), findsOneWidget);

    fail = false;
    await tester.tap(find.byTooltip('Reintentar'));
    await tester.pumpAndSettle();

    expect(backend.plotRequests, hasLength(2));
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('límite de 5 s'), findsNothing);
  });
}
