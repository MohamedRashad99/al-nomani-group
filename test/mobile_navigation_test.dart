import 'package:al_nomani_group/core/utils/breakpoints.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phones keep the compact shell even in landscape', () {
    expect(Breakpoints.isPhoneSize(const Size(390, 844)), isTrue);
    expect(Breakpoints.isPhoneSize(const Size(844, 390)), isTrue);
    expect(Breakpoints.isPhoneSize(const Size(1024, 768)), isFalse);
  });
}
