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

    test('toDisplay hides trailing zeros without changing storage', () {
      expect(Money.parse('125').toDisplay(), '125');
      expect(Money.parse('250').toDisplay(), '250');
      expect(Money.parse('75').toDisplay(), '75');
      expect(Money.parse('125.25').toDisplay(), '125.25');
      expect(Money.parse('125.50').toDisplay(), '125.5');
      expect(Money.parse('125.75').toDisplay(), '125.75');
      expect(Money.zero().toDisplay(), '0');
      expect(Money.parse('1250000').toDisplay(), '1250000');
      expect(Money.parse('125').toStorage(), '125.000');
    });
  });

  group('Quantity', () {
    test('supports fractional kg', () {
      expect(Quantity.parse('0.250').toStorage(), '0.250');
      expect(
        (Quantity.parse('1') - Quantity.parse('0.500')).toStorage(),
        '0.500',
      );
    });

    test('multiplies package count by package size', () {
      expect(
        (Quantity.parse('100') * Quantity.parse('250')).toDisplay(),
        '25000',
      );
      expect((Quantity.parse('20') * Quantity.parse('50')).toDisplay(), '1000');
    });
  });
}
