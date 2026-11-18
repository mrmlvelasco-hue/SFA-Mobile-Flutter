import 'package:flutter_test/flutter_test.dart';
import 'package:sfa_mobile/core/formatting.dart';

void main() {
  test('calculatePercentage: one decimal, 0.0 for a missing or zero whole', () {
    expect(calculatePercentage(1, 3), '33.3');
    expect(calculatePercentage(843210.5, 1000000), '84.3');
    expect(calculatePercentage(5, 0), '0.0');
    expect(calculatePercentage(null, 10), '0.0');
    expect(calculatePercentage(150, 100), '150.0');
  });

  test('numberWithDecimals and roundedWithCommas', () {
    expect(numberWithDecimals(1234567.891), '1,234,567.89');
    expect(numberWithDecimals(0), '0.00');
    expect(roundedWithCommas(1234567.5), '1,234,568');
    expect(roundedWithCommas(999.4), '999');
  });

  test('jsNumberText mirrors JavaScript Number()', () {
    expect(jsNumberText('001234'), '1234');
    expect(jsNumberText('R1'), 'NaN');
    expect(jsNumberText(''), '0');
    expect(jsNumberText(null), 'NaN');
    expect(jsNumberText('12.5'), '12.5');
  });

  test('longDateWithWeekday and dayKey', () {
    expect(longDateWithWeekday(DateTime(2026, 11, 17)), 'November 17, 2026 (Tuesday)');
    expect(dayKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
  });

  test('asNum reads numbers and numeric strings', () {
    expect(asNum(5), 5);
    expect(asNum(' 1500.9 '), 1500.9);
    expect(asNum('abc'), isNull);
    expect(asNum(null), isNull);
  });
}
