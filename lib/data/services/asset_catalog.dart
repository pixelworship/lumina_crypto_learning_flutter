import '../../design_system/tokens/lumina_palette.dart';
import '../models/asset_category.dart';
import '../models/crypto_asset.dart';

/// Read-only registry of supported crypto assets.
///
/// Anything that needs to resolve a [CryptoAsset] from a symbol should depend
/// on this interface rather than a hard-coded switch. Tests can substitute a
/// minimal in-memory catalog; production swaps in whatever the backend ships.
abstract class AssetCatalog {
  /// Every asset known to the app.
  List<CryptoAsset> all();

  /// Looks up an asset by its (case-insensitive) symbol.
  ///
  /// Returns `null` when the symbol is not in the catalog. Callers should
  /// decide whether to throw, fall back, or surface an error to the user.
  CryptoAsset? findBySymbol(String symbol);

  /// Registers a synthesized asset so subsequent [findBySymbol] calls
  /// resolve it. Used by mock services that mint additional assets at
  /// runtime (e.g. paginated market discovery beyond the static
  /// seed). Returns the canonical instance — if [asset]'s symbol is
  /// already known, the existing instance is returned unchanged.
  CryptoAsset register(CryptoAsset asset);
}

/// In-memory catalog seeded with the assets we ship by default.
///
/// Mutable: additional assets can be [register]ed after construction
/// (used for paginated mock data). Static iteration order via [all]
/// preserves insertion order so stable rank assignment in the markets
/// list survives page-by-page generation.
class StaticAssetCatalog implements AssetCatalog {
  StaticAssetCatalog([List<CryptoAsset>? assets])
      : _byUpperSymbol = <String, CryptoAsset>{
          for (final CryptoAsset a in assets ?? _defaultAssets)
            a.symbol.toUpperCase(): a,
        },
        _all = <CryptoAsset>[...assets ?? _defaultAssets];

  final Map<String, CryptoAsset> _byUpperSymbol;
  final List<CryptoAsset> _all;

  @override
  List<CryptoAsset> all() => List<CryptoAsset>.unmodifiable(_all);

  @override
  CryptoAsset? findBySymbol(String symbol) =>
      _byUpperSymbol[symbol.toUpperCase()];

  @override
  CryptoAsset register(CryptoAsset asset) {
    final String key = asset.symbol.toUpperCase();
    final CryptoAsset? existing = _byUpperSymbol[key];
    if (existing != null) return existing;
    _byUpperSymbol[key] = asset;
    _all.add(asset);
    return asset;
  }

  // ---------------------------------------------------------------------------
  // Default catalog — these would come from an `/assets` endpoint in a real
  // app. Kept here so the mock service has a deterministic baseline.
  // ---------------------------------------------------------------------------
  static const List<CryptoAsset> _defaultAssets = <CryptoAsset>[
    CryptoAsset(
      id: 'btc',
      symbol: 'BTC',
      name: 'Bitcoin',
      color: LuminaPalette.brandBtc,
      iconLetter: 'B',
      categories: <AssetCategory>[AssetCategory.layer1],
    ),
    CryptoAsset(
      id: 'eth',
      symbol: 'ETH',
      name: 'Ethereum',
      color: LuminaPalette.brandEth,
      iconLetter: 'E',
      categories: <AssetCategory>[AssetCategory.layer1, AssetCategory.defi],
    ),
    CryptoAsset(
      id: 'sol',
      symbol: 'SOL',
      name: 'Solana',
      color: LuminaPalette.brandSol,
      iconLetter: 'S',
      categories: <AssetCategory>[AssetCategory.layer1],
    ),
    CryptoAsset(
      id: 'uni',
      symbol: 'UNI',
      name: 'Uniswap',
      color: LuminaPalette.brandUni,
      iconLetter: 'U',
      categories: <AssetCategory>[AssetCategory.defi],
    ),
    CryptoAsset(
      id: 'ada',
      symbol: 'ADA',
      name: 'Cardano',
      color: LuminaPalette.brandAda,
      iconLetter: 'A',
      categories: <AssetCategory>[AssetCategory.layer1],
    ),
    CryptoAsset(
      id: 'usdt',
      symbol: 'USDT',
      name: 'Tether',
      color: LuminaPalette.brandUsdt,
      iconLetter: 'T',
      categories: <AssetCategory>[AssetCategory.stablecoin],
    ),
    CryptoAsset(
      id: 'avax',
      symbol: 'AVAX',
      name: 'Avalanche',
      color: LuminaPalette.brandAvax,
      iconLetter: 'A',
      categories: <AssetCategory>[AssetCategory.layer1, AssetCategory.defi],
    ),
    CryptoAsset(
      id: 'axs',
      symbol: 'AXS',
      name: 'Axie Infinity',
      color: LuminaPalette.brandAxs,
      iconLetter: 'X',
      categories: <AssetCategory>[AssetCategory.gaming],
    ),
    CryptoAsset(
      id: 'sand',
      symbol: 'SAND',
      name: 'The Sandbox',
      color: LuminaPalette.brandSand,
      iconLetter: 'S',
      categories: <AssetCategory>[AssetCategory.gaming],
    ),
  ];
}
