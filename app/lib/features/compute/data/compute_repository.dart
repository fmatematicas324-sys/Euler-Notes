import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../domain/compute.dart';

class ComputeRepository {
  ComputeRepository(this._api);

  final ApiClient _api;

  Future<ComputeResult> compute({
    required String expr,
    required ComputeOp op,
    String variable = 'x',
  }) async => ComputeResult.fromJson(
    await _api.post(
      '/compute',
      {'expr': expr, 'op': op.name, 'var': variable},
      timeout: _api.timeouts.compute,
      idempotent: true,
    ) as Map<String, dynamic>,
  );
}

final computeRepositoryProvider = Provider<ComputeRepository>(
  (ref) => ComputeRepository(ref.watch(apiClientProvider)),
);
