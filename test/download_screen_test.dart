import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sfa_mobile/core/api_client.dart';
import 'package:sfa_mobile/core/offline_store.dart';
import 'package:sfa_mobile/features/auth/auth_state.dart';
import 'package:sfa_mobile/features/master_data/download_screen.dart';
import 'package:sfa_mobile/features/master_data/master_data_state.dart';

import 'helpers.dart';

/// Holds the 'sku-list' call until [gate] completes, to see the screen mid-download.
class _PausingRepository extends FakeMasterDataRepository {
  final gate = Completer<void>();

  @override
  Future<ApiEnvelope> post(String path, Map<String, dynamic> body) async {
    if (path.endsWith('/sku-list')) await gate.future;
    return super.post(path, body);
  }
}

Future<MasterDataState> _pump(WidgetTester tester, FakeMasterDataRepository repo) async {
  final auth = signedInAuth();
  final state = MasterDataState(auth: auth, repository: repo, store: InMemoryOfflineStore());
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthState>.value(value: auth),
      ChangeNotifierProvider<MasterDataState>.value(value: state),
    ],
    child: const MaterialApp(home: DownloadScreen()),
  ));
  return state;
}

void main() {
  testWidgets('shows the step being downloaded and the percentage', (tester) async {
    final repo = _PausingRepository();
    final state = await _pump(tester, repo);

    unawaited(state.download());
    await tester.pump();

    expect(find.text('Downloading data'), findsOneWidget);
    // 1 of 16 steps done (the summary), now on 'Materials'.
    expect(find.text('Materials  6%'), findsOneWidget);

    repo.gate.complete();
    await tester.pump();
    expect(state.isReady, isTrue);
  });

  testWidgets('on failure shows the failing step, and Retry downloads again', (tester) async {
    final repo = FakeMasterDataRepository(responses: {
      'sku-list': ApiEnvelope(code: 500, status: 'Error', message: 'boom'),
    });
    final state = await _pump(tester, repo);

    unawaited(state.download());
    await tester.pump();

    expect(find.text('Download failed'), findsOneWidget);
    expect(find.text('Materials: boom'), findsOneWidget);

    repo.responses.clear();
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(state.isReady, isTrue);
  });
}
