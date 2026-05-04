import 'dart:math';

/// Classic 1D Perlin gradient noise with a permutation table.
///
/// `sample(x)` returns a value approximately in `[-1, 1]`. `fbm` sums
/// multiple octaves to produce trend-with-detail behaviour.
///
/// Generic utility — no domain concepts. Used by both data-layer price
/// generation and presentation-layer organic motion (e.g. lava-lamp blobs).
class PerlinNoise1D {
  PerlinNoise1D({int? seed}) {
    final Random rng = Random(seed ?? Random().nextInt(1 << 30));
    final List<int> base = List<int>.generate(256, (int i) => i)..shuffle(rng);
    _perm = List<int>.unmodifiable(<int>[...base, ...base]);
  }

  late final List<int> _perm;

  static double _grad(int hash, double x) => (hash & 1) == 0 ? x : -x;
  static double _fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);
  static double _lerp(double a, double b, double t) => a + t * (b - a);

  double sample(double x) {
    final int xi0 = x.floor();
    final int xi = xi0 & 255;
    final double xf = x - xi0.toDouble();
    final double u = _fade(xf);
    final int ga = _perm[xi];
    final int gb = _perm[xi + 1];
    return _lerp(_grad(ga, xf), _grad(gb, xf - 1), u);
  }

  /// Fractal sum across [octaves] octaves. Output normalized to ~[-1, 1].
  double fbm(
    double x, {
    int octaves = 5,
    double persistence = 0.55,
    double lacunarity = 2.0,
  }) {
    double total = 0.0;
    double amplitude = 1.0;
    double frequency = 1.0;
    double maxAmplitude = 0.0;
    for (int i = 0; i < octaves; i++) {
      total += sample(x * frequency) * amplitude;
      maxAmplitude += amplitude;
      amplitude *= persistence;
      frequency *= lacunarity;
    }
    return total / maxAmplitude;
  }
}
