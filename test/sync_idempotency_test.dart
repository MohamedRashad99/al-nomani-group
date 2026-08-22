import 'package:al_nomani_group/core/config/app_config.dart';
import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same operation id is the idempotency key', () {
    const id = 'SALE-UUID-123';
    expect(id, 'SALE-UUID-123');
    expect(SyncStatus.parse('pending'), SyncStatus.pending);
    expect(SyncStatus.parse('failed'), SyncStatus.failed);
    expect(SyncDefaults.productionIntervalDays, 5);
  });

  test('unsafe production configuration fails closed', () {
    expect(
      () => AppConfig.fromJson({
        'environment': 'production',
        'api_base_url': 'https://api.example.com',
        'allow_seed': false,
      }),
      throwsFormatException,
    );
    expect(
      () => AppConfig.fromJson({
        'environment': 'production',
        'api_base_url': 'https://erp-api.alnomani.example',
        'allow_seed': true,
      }),
      throwsFormatException,
    );
  });
}
