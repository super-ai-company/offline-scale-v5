import '../models/menu_item.dart';
import 'ai_recognition_service.dart';

/// Similarity is a distance score, never a calibrated probability.
class ProduceDecision {
  final String code;
  final List<AiMatch> candidates;
  const ProduceDecision(this.code, this.candidates);
  bool get accepted => code == 'accepted';
  Map<String, Object?> toJson() => {
    'code': code,
    'candidates': [
      for (final match in candidates)
        {
          'item_id': match.item.id,
          'similarity': match.similarity,
          'price_per_kg': match.item.price,
        },
    ],
  };
}

class ProduceRecognitionPolicy {
  final double minimumSimilarity;
  final double minimumMargin;
  const ProduceRecognitionPolicy({
    this.minimumSimilarity = .94,
    this.minimumMargin = .08,
  });

  ProduceDecision evaluate(
    List<double> query,
    List<(int, List<double>)> samples,
    List<MenuItem> items,
  ) {
    final products = items
        .where(
          (item) =>
              !item.isQuickWeigh &&
              item.isByWeight &&
              item.price.isFinite &&
              item.price > 0 &&
              item.id != null,
        )
        .toList();
    final candidates = AiRecognitionService.rank(query, samples, products);
    if (candidates.isEmpty) return const ProduceDecision('no_samples', []);
    if (candidates.first.similarity < minimumSimilarity) {
      return ProduceDecision('unknown', candidates);
    }
    if (candidates.length > 1 &&
        candidates.first.similarity - candidates[1].similarity <
            minimumMargin) {
      return ProduceDecision('ambiguous', candidates);
    }
    final counts = <int, int>{};
    for (final (id, vector) in samples) {
      if (AiRecognitionService.cosine(query, vector) != null) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    // Every sellable category must be represented. A one-category catalogue
    // cannot provide evidence that a visually similar unknown was excluded.
    if (products.length < 2 ||
        products.any((item) => (counts[item.id] ?? 0) < 5)) {
      return ProduceDecision('needs_samples', candidates);
    }
    return ProduceDecision('accepted', candidates);
  }
}

/// Owns a weighing cycle and invalidates asynchronous camera results.
class ProduceScanCycle {
  int generation = 0;
  bool locked = false;
  double? _kg;
  DateTime? _stableSince;
  int? _candidate;
  int _confirmations = 0;

  void update(double kg, bool ready, DateTime now) {
    if (!kg.isFinite || kg <= .005) {
      if (_kg != null || locked) invalidate();
      locked = false;
      _kg = null;
      return;
    }
    if (!ready || _kg == null || (kg - _kg!).abs() > .002) {
      invalidate();
      _kg = kg;
      _stableSince = ready ? now : null;
    } else {
      _stableSince ??= now;
    }
  }

  bool ready(DateTime now) =>
      !locked &&
      _stableSince != null &&
      now.difference(_stableSince!) >= const Duration(milliseconds: 1000);

  void invalidate() {
    generation++;
    _stableSince = null;
    _candidate = null;
    _confirmations = 0;
  }

  void manualOverride() {
    invalidate();
    locked = true;
  }

  bool confirm(ProduceDecision decision, int token) {
    if (token != generation || locked) return false;
    if (!decision.accepted) {
      _candidate = null;
      _confirmations = 0;
      return false;
    }
    final id = decision.candidates.first.item.id;
    _confirmations = id == _candidate ? _confirmations + 1 : 1;
    _candidate = id;
    return _confirmations >= 3;
  }
}
