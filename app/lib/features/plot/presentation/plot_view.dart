import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../data/plot_repository.dart';
import '../domain/plot_spec.dart';

/// Gráfica generada por el backend (`/plot`) que se adapta al ancho disponible,
/// al tema (claro/oscuro) y a la densidad de píxeles del dispositivo.
///
/// Mientras se escribe, espera [debounce] antes de pedir la nueva versión y
/// mantiene visible la anterior.
class PlotView extends ConsumerStatefulWidget {
  const PlotView({super.key, required this.spec, this.height = 300});

  final PlotSpec spec;
  final double height;

  static const debounce = Duration(milliseconds: 400);

  @override
  ConsumerState<PlotView> createState() => _PlotViewState();
}

class _PlotViewState extends ConsumerState<PlotView> {
  Uint8List? _image;
  Object? _error;
  bool _loading = false;
  Timer? _timer;
  _Request? _requested;
  int _generation = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Anchos en saltos de 50 px: redimensionar la ventana no pide una imagen
  /// por cada píxel.
  static int _bucketWidth(double width) =>
      ((width / 50).floor() * 50).clamp(200, 1600);

  void _ensureRequested(_Request request) {
    if (request == _requested) return;
    _requested = request;
    _timer?.cancel();
    final firstLoad = _image == null && _error == null;
    _timer = Timer(firstLoad ? Duration.zero : PlotView.debounce, () {
      _fetch(request);
    });
  }

  Future<void> _fetch(_Request request) async {
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final png = await ref
          .read(plotRepositoryProvider)
          .render(
            request.spec,
            dark: request.dark,
            width: request.width,
            height: request.height,
            scale: request.scale,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _image = png;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final scale = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final height = widget.height.round().clamp(150, 1200);

    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureRequested(
          _Request(
            spec: widget.spec,
            dark: dark,
            width: _bucketWidth(constraints.maxWidth),
            height: height,
            scale: scale,
          ),
        );
        final image = _image;
        return SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              if (image != null)
                Positioned.fill(
                  child: Opacity(
                    opacity: _error != null ? 0.4 : 1,
                    child: Image.memory(
                      image,
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                      semanticLabel:
                          'Gráfica de ${widget.spec.exprs.join(', ')}',
                    ),
                  ),
                )
              else if (_error == null)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.show_chart, size: 48),
                    ),
                  ),
                ),
              if (_error != null)
                Positioned.fill(
                  child: Center(
                    child: _PlotError(
                      error: _error!,
                      onRetry: _loading || _requested == null
                          ? null
                          : () => _fetch(_requested!),
                    ),
                  ),
                ),
              if (_loading)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PlotError extends StatelessWidget {
  const _PlotError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              errorMessage(error),
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Reintentar',
            onPressed: onRetry,
            color: colors.onErrorContainer,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

@immutable
class _Request {
  const _Request({
    required this.spec,
    required this.dark,
    required this.width,
    required this.height,
    required this.scale,
  });

  final PlotSpec spec;
  final bool dark;
  final int width;
  final int height;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is _Request &&
      other.spec == spec &&
      other.dark == dark &&
      other.width == width &&
      other.height == height &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(spec, dark, width, height, scale);
}
