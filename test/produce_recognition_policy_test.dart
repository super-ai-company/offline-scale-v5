import 'package:cashier_trae/models/menu_item.dart';
import 'package:cashier_trae/services/produce_recognition_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const potato = MenuItem(id: 1, nameEn: 'Potato', price: 12);
  const carrot = MenuItem(id: 2, nameEn: 'Carrot', price: 20);
  final samples = [
    for (var i = 0; i < 5; i++) ...[
      (1, <double>[1, 0]),
      (2, <double>[0, 1]),
    ],
  ];
  const policy = ProduceRecognitionPolicy();

  test('unknown and ambiguous produce cannot be automatically selected', () {
    expect(policy.evaluate([-1, 0], samples, [potato, carrot]).code, 'unknown');
    expect(
      const ProduceRecognitionPolicy(
        minimumSimilarity: .6,
      ).evaluate([1, 1], samples, [potato, carrot]).code,
      'ambiguous',
    );
    expect(policy.evaluate([1, 0], samples, [potato, carrot]).accepted, isTrue);
  });
  test(
    'untrained catalogue category and single-category catalogue block automation',
    () {
      expect(
        policy.evaluate(
          [1, 0],
          [
            (1, [1, 0]),
          ],
          [potato, carrot],
        ).code,
        'needs_samples',
      );
      expect(policy.evaluate([1, 0], samples, [potato]).code, 'needs_samples');
      expect(
        policy.evaluate(
          [1, 0],
          [
            ...samples,
            (3, [1, 0]),
          ],
          [potato, carrot, const MenuItem(id: 3, price: 8)],
        ).code,
        'ambiguous',
      );
    },
  );
  test(
    'deleted, unpriced, and fixed-quantity products cannot supply automatic price',
    () {
      expect(
        policy
            .evaluate(
              [1, 0],
              samples,
              [carrot, const MenuItem(id: 1, price: 0)],
            )
            .code,
        'unknown',
      );
      expect(
        policy
            .evaluate(
              [1, 0],
              samples,
              [const MenuItem(id: 1, price: 10, isByWeight: false)],
            )
            .code,
        'no_samples',
      );
      expect(
        policy.evaluate([1, 0], samples, []).toJson()['code'],
        'no_samples',
      );
    },
  );
  test('three agreeing frames required; disagreement resets confirmations', () {
    final cycle = ProduceScanCycle();
    final yes = policy.evaluate([1, 0], samples, [potato, carrot]);
    expect(cycle.confirm(yes, 0), isFalse);
    expect(cycle.confirm(yes, 0), isFalse);
    expect(cycle.confirm(const ProduceDecision('unknown', []), 0), isFalse);
    expect(cycle.confirm(yes, 0), isFalse);
    expect(cycle.confirm(yes, 0), isFalse);
    expect(cycle.confirm(yes, 0), isTrue);
  });
  test(
    'weight motion, manual overrides, and removal invalidate in-flight results',
    () {
      final now = DateTime(2026);
      final cycle = ProduceScanCycle()..update(.72, true, now);
      final token = cycle.generation;
      final yes = policy.evaluate([1, 0], samples, [potato, carrot]);
      expect(cycle.ready(now), isFalse);
      expect(cycle.ready(now.add(const Duration(seconds: 1))), isTrue);
      cycle.update(.8, true, now);
      expect(cycle.confirm(yes, token), isFalse);
      cycle.manualOverride();
      cycle.update(.82, true, now);
      expect(cycle.ready(now.add(const Duration(seconds: 2))), isFalse);
      cycle.update(0, true, now);
      cycle.update(.5, true, now);
      expect(cycle.ready(now.add(const Duration(seconds: 2))), isTrue);
    },
  );
  test('invalid scale data and disconnected scale never arm recognition', () {
    final cycle = ProduceScanCycle();
    final now = DateTime(2026);
    cycle.update(double.nan, true, now);
    expect(cycle.ready(now.add(const Duration(seconds: 3))), isFalse);
    cycle.update(.7, false, now);
    expect(cycle.ready(now.add(const Duration(seconds: 3))), isFalse);
  });
}
