import 'package:al_nomani_shared/al_nomani_shared.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('parses and adds without floating point', () {
      final total = Money.parse('1000');
      final paid = Money.parse('400');
      final remaining = total - paid;
      expect(remaining.toStorage(), '600.000');
    });

    test('rejects extra decimals', () {
      expect(() => Money.parse('1.2345'), throwsFormatException);
    });

    test('partial payment accounting', () {
      var balance = Money.zero();
      balance += Money.parse('1000');
      balance -= Money.parse('250');
      balance -= Money.parse('300');
      expect(balance.toStorage(), '450.000');
    });
  });

  group('Quantity', () {
    test('supports fractional kg', () {
      expect(Quantity.parse('0.250').toStorage(), '0.250');
      expect((Quantity.parse('1') - Quantity.parse('0.500')).toStorage(), '0.500');
    });
  });
}
