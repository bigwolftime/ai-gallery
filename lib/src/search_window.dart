/// Shared with both platforms: only the initial window uses score gaps.
class SearchWindow {
  static const expansionSize = 15;
  static const minimumGap = 0.02;
  static const minimumScale = 0.001;
  static const madToSigma = 1.4826;
  static const significantDeviation = 3.0;

  static int initialCount(List<double> scores) {
    if (scores.length < 2) return scores.length;
    final gaps = List.generate(
        scores.length - 1, (index) => scores[index] - scores[index + 1]);
    final sorted = [...gaps]..sort();
    // Match the existing Swift upper-median rule, including even-sized samples.
    final median = sorted[sorted.length ~/ 2];
    final deviations = sorted.map((gap) => (gap - median).abs()).toList()
      ..sort();
    final mad = deviations[deviations.length ~/ 2];
    final scale = (mad * madToSigma).clamp(minimumScale, double.infinity);
    final threshold = median +
        (scale * significantDeviation).clamp(minimumGap, double.infinity);
    final boundary = gaps.indexWhere((gap) => gap >= threshold);
    return boundary < 0 ? scores.length : boundary + 1;
  }

  static int expand(int visible, int total) =>
      (visible + expansionSize).clamp(0, total);
}
