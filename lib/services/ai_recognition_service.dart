import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../models/menu_item.dart';
import 'db_service.dart';

class AiMatch {
  final MenuItem item;
  final double similarity;

  const AiMatch(this.item, this.similarity);
}

class AiRecognitionService {
  static const _channel = MethodChannel('cashier/ai_embedding');

  Future<List<double>> embedImage(String path) async {
    final values = await _channel
        .invokeListMethod<num>('embedImage', {'path': path})
        .timeout(const Duration(seconds: 15));
    if (values == null || values.isEmpty) {
      throw StateError('Image model returned no features');
    }
    return values.map((value) => value.toDouble()).toList();
  }

  Future<List<AiMatch>> recognize(
    List<double> embedding,
    List<MenuItem> items,
  ) async {
    final samples = await DbService().visualSamples();
    return rank(embedding, samples, items);
  }

  static List<AiMatch> rank(
    List<double> query,
    List<(int, List<double>)> samples,
    List<MenuItem> items,
  ) {
    final available = {
      for (final item in items)
        if (item.id != null && !item.isQuickWeigh) item.id!: item,
    };
    final best = <int, double>{};
    for (final (itemId, vector) in samples) {
      if (!available.containsKey(itemId)) continue;
      final score = cosine(query, vector);
      if (score == null) continue;
      if (score > (best[itemId] ?? -2)) best[itemId] = score;
    }
    final matches = [
      for (final entry in best.entries)
        AiMatch(available[entry.key]!, entry.value),
    ]..sort((a, b) => b.similarity.compareTo(a.similarity));
    return matches.take(3).toList();
  }

  static double? cosine(List<double> a, List<double> b) {
    if (a.isEmpty || a.length != b.length) return null;
    var dot = 0.0;
    var aa = 0.0;
    var bb = 0.0;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].isFinite || !b[i].isFinite) return null;
      dot += a[i] * b[i];
      aa += a[i] * a[i];
      bb += b[i] * b[i];
    }
    if (aa == 0 || bb == 0) return null;
    return dot / (math.sqrt(aa) * math.sqrt(bb));
  }
}
