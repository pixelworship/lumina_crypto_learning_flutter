import 'dart:math';

import '../../core/utils/perlin_noise.dart';

/// Deterministic price function over wall-clock time.
///
/// Combines two decorrelated Perlin layers:
///   * Macro — months/quarters/year scale, drives long-term trend.
///   * Micro — seconds/minutes scale, drives intraday wiggle.
///
/// Sharing one [PriceNoise] instance between historical and live
/// repositories yields perfect continuity across the boundary.
class PriceNoise {
  PriceNoise({
    this.basePrice = 100.0,

    // Macro — long-term trend. Default base period ≈ 2 months;
    // amplitude ~$55 so a year-long view sweeps a realistic range.
    this.macroAmplitude = 55.0,
    this.macroTimeScale = 5e-8,
    this.macroOctaves = 6,
    this.macroPersistence = 0.55,
    this.macroLacunarity = 2.0,

    // Micro — short-term variation. Fastest octave ≈ 30s,
    // amplitude ~$3 so per-second/minute changes are clearly visible.
    this.microAmplitude = 3.0,
    this.microTimeScale = 0.0008,
    this.microOctaves = 4,
    this.microPersistence = 0.5,
    this.microLacunarity = 2.0,

    int? seed,
  }) {
    final int actualSeed = seed ?? Random().nextInt(1 << 30);
    _macroNoise = PerlinNoise1D(seed: actualSeed);
    // XOR with golden-ratio constant gives a decorrelated companion seed.
    _microNoise = PerlinNoise1D(seed: actualSeed ^ 0x9E3779B9);
  }

  late final PerlinNoise1D _macroNoise;
  late final PerlinNoise1D _microNoise;

  final double basePrice;

  final double macroAmplitude;

  /// Noise units per millisecond for the macro layer. Smaller = slower.
  final double macroTimeScale;
  final int macroOctaves;
  final double macroPersistence;
  final double macroLacunarity;

  final double microAmplitude;
  final double microTimeScale;
  final int microOctaves;
  final double microPersistence;
  final double microLacunarity;

  double priceAt(DateTime t) {
    final double tx = t.millisecondsSinceEpoch.toDouble();
    final double macro = _macroNoise.fbm(
      tx * macroTimeScale,
      octaves: macroOctaves,
      persistence: macroPersistence,
      lacunarity: macroLacunarity,
    );
    final double micro = _microNoise.fbm(
      tx * microTimeScale,
      octaves: microOctaves,
      persistence: microPersistence,
      lacunarity: microLacunarity,
    );
    return basePrice + macro * macroAmplitude + micro * microAmplitude;
  }
}
