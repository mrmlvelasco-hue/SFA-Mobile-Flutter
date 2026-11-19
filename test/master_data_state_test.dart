import 'package:flutter_test/flutter_test.dart';
import 'package:sfa_mobile/core/api_client.dart';
import 'package:sfa_mobile/core/offline_store.dart';
import 'package:sfa_mobile/features/auth/auth_state.dart';
import 'package:sfa_mobile/features/master_data/master_data_state.dart';

import 'helpers.dart';

final _today = DateTime(2026, 11, 18, 9, 30);
DateTime _clock() => _today;

/// The RN app's DownloadData.js order.
const _rnOrder = [
  'download-datav2',
  'sku-list',
  'promo-discount',
  'empties-pullout-tab',
  'order-details',
  'sales-return',
  'material-inventory',
  'collections',
  'outlets',
  'receivables',
  'rebates',
  'customer-pickup-discount',
  'partners',
  'all-pricing',
  'customer-sales-vol',
  'customer-promo',
];

MasterDataState _state(FakeMasterDataRepository repo, InMemoryOfflineStore store, {AuthState? auth}) =>
    MasterDataState(auth: auth ?? signedInAuth(clock: _clock), repository: repo, store: store, clock: _clock);

void main() {
  test('download() makes the RN app\'s 16 calls, in its order', () async {
    final repo = FakeMasterDataRepository();
    final state = _state(repo, InMemoryOfflineStore());

    await state.download();

    expect(repo.paths, _rnOrder);
    expect(state.status, MasterDataStatus.ready);
    expect(state.progress, 1);
  });

  test('download() sends the RN app\'s payloads', () async {
    final repo = FakeMasterDataRepository();
    await _state(repo, InMemoryOfflineStore()).download();
    final customers = ['DEMO0003', 'DEMO0001', 'DEMO0002', 'DEMO0004', 'DEMO0005'];
    final device = {'employee_id': 'E1', 'device_id': 'phone-1', 'lat': 0.0, 'lng': 0.0, 'ip': '0.0.0.0', 'sales_org': ['1000']};

    expect(repo.bodies['download-datav2'], device);
    expect(repo.bodies['sku-list'], {'sales_org': ['1000']});
    expect(repo.bodies['promo-discount'], {...device, 'customer_list': customers});
    expect(repo.bodies['empties-pullout-tab'], {...device, 'customer_list': customers});
    expect(repo.bodies['sales-return'], {'customer_list': customers, 'org': ['1000']});
    expect(repo.bodies['material-inventory'], {'sales_area': ['9101'], 'org': ['1000']});
    expect(repo.bodies['outlets']!['customer_org'], hasLength(5));
    expect((repo.bodies['outlets']!['customer_org'] as List).first, {'customer_number': 'DEMO0003', 'sales_org': '1000'});
    expect(repo.bodies['customer-pickup-discount'], {'employee_id': 'E1', 'customer_list': customers});
    expect(repo.bodies['all-pricing']!['customer_list'], customers);
    expect((repo.bodies['all-pricing']!['route_calls'] as Map)['count'], 5);
    expect(repo.bodies['customer-promo'], {'employee_id': 'E1', 'org': '1000', 'customer_list': customers});
  });

  test('the combined data has the RN offlineData keys, and is saved for this user and day', () async {
    final store = InMemoryOfflineStore();
    final state = _state(FakeMasterDataRepository(), store);

    await state.download();

    expect(state.data.keys, containsAll(['constants', 'route_calls', 'order_details', 'pricing', 'feedback_reasons', 'customer_sales_vol']));
    expect(state.data['pricing'], hasLength(1));
    final saved = await store.read(OfflineDocs.downloadData);
    expect(saved!['employee_id'], 'E1');
    expect(saved['day'], '2026-11-18');
    expect((saved['data'] as Map).containsKey('pricing'), isFalse, reason: 'pricing has its own document');
    final pricing = await store.read(OfflineDocs.pricing);
    expect(pricing!['data'], hasLength(1));
  });

  test('start() uses today\'s saved download without calling the server (works offline)', () async {
    final store = InMemoryOfflineStore();
    await _state(FakeMasterDataRepository(), store).download();

    final offlineRepo = FakeMasterDataRepository();
    final reopened = _state(offlineRepo, store);
    await reopened.start();

    expect(offlineRepo.paths, isEmpty);
    expect(reopened.isReady, isTrue);
    expect((reopened.data['route_calls'] as Map)['count'], 5);
    expect(reopened.data['pricing'], hasLength(1));
  });

  test('start() downloads again when the saved download is from another day or user', () async {
    final store = InMemoryOfflineStore();
    await store.write(OfflineDocs.downloadData, {'employee_id': 'E1', 'day': '2026-11-17', 'data': <String, dynamic>{}});
    final repo = FakeMasterDataRepository();
    await _state(repo, store).start();
    expect(repo.paths, _rnOrder);

    await store.write(OfflineDocs.downloadData, {'employee_id': 'E9', 'day': '2026-11-18', 'data': <String, dynamic>{}});
    final repo2 = FakeMasterDataRepository();
    await _state(repo2, store).start();
    expect(repo2.paths.first, 'download-datav2');
  });

  group('pricing cache (RN rule)', () {
    Future<InMemoryOfflineStore> withSavedPricing(String day, {String employee = 'E1'}) async {
      final store = InMemoryOfflineStore();
      await store.write(OfflineDocs.pricing, {
        'employee_id': employee,
        'day': day,
        'data': [
          {'customer_number': 'OLD', 'price': 1}
        ]
      });
      return store;
    }

    test('saved pricing is reused when there is no price update', () async {
      final repo = FakeMasterDataRepository();
      final state = _state(repo, await withSavedPricing('2026-11-10'));

      await state.download();

      expect(repo.paths, isNot(contains('all-pricing')));
      expect(state.data['pricing'], [
        {'customer_number': 'OLD', 'price': 1}
      ]);
      expect(state.progress, 1);
    });

    test('a price update re-downloads pricing saved on an earlier day', () async {
      final repo = FakeMasterDataRepository(priceUpdate: true);
      final state = _state(repo, await withSavedPricing('2026-11-10'));

      await state.download();

      expect(repo.paths, contains('all-pricing'));
      expect((state.data['pricing'] as List).first['customer_number'], 'DEMO0001');
    });

    test('a price update does not re-download pricing already downloaded today', () async {
      final repo = FakeMasterDataRepository(priceUpdate: true);
      await _state(repo, await withSavedPricing('2026-11-18')).download();
      expect(repo.paths, isNot(contains('all-pricing')));
    });

    test('another user\'s saved pricing is not used', () async {
      final repo = FakeMasterDataRepository();
      await _state(repo, await withSavedPricing('2026-11-18', employee: 'E9')).download();
      expect(repo.paths, contains('all-pricing'));
    });
  });

  test('a failing call stops the download, names the step, and saves nothing', () async {
    final store = InMemoryOfflineStore();
    final repo = FakeMasterDataRepository(responses: {
      'sku-list': ApiEnvelope(code: 500, status: 'Error', message: 'relation "sfa_skus" does not exist'),
    });
    final state = _state(repo, store);

    await state.download();

    expect(state.status, MasterDataStatus.failed);
    expect(state.errorMessage, 'Materials: relation "sfa_skus" does not exist');
    expect(repo.paths, ['download-datav2', 'sku-list']);
    expect(await store.read(OfflineDocs.downloadData), isNull);
  });

  test('a rejected token signs the user out', () async {
    final auth = signedInAuth(clock: _clock);
    final repo = FakeMasterDataRepository(responses: {
      'download-datav2': ApiEnvelope(code: 401, message: 'Unauthenticated.'),
    });

    await _state(repo, InMemoryOfflineStore(), auth: auth).download();

    expect(auth.status, AuthStatus.signedOut);
    expect(auth.errorMessage, contains('session has expired'));
  });

  group('DC stock (materials-inventory-sap)', () {
    test('fetched after the download for every sales office, grouped and saved for offline use', () async {
      final store = InMemoryOfflineStore();
      final repo = FakeMasterDataRepository();
      final state = _state(repo, store);
      await state.download();

      expect(repo.gets, ['materials-inventory-sap']);
      expect(repo.getQueries.single, {'sales_office': '9101'});
      expect(state.dcInventoryError, isNull);
      expect((state.dcInventory['9101'] as List), hasLength(2));

      final reopened = _state(FakeMasterDataRepository(), store);
      await reopened.start();
      expect((reopened.dcInventory['9101'] as List), hasLength(2));
    });

    test('a failure does not fail the download', () async {
      final repo = FakeMasterDataRepository()
        ..stockResponse = ApiEnvelope(code: 0, message: 'No internet connection');
      final state = _state(repo, InMemoryOfflineStore());
      await state.download();

      expect(state.isReady, isTrue);
      expect(state.dcInventory, isEmpty);
      expect(state.dcInventoryError, 'No internet connection');
    });
  });
}
