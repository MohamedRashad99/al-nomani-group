import 'package:al_nomani_group/core/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Arabic product name is present', () {
    expect(S.appName, 'مجموعة النعماني');
    expect(S.protected, 'محمي');
    expect(S.waitingSync, 'في انتظار المزامنة');
    expect(S.syncProblem, 'توجد مشكلة في المزامنة');
  });
}
