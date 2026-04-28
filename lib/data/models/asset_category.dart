/// Categories used to filter assets on the markets screen.
enum AssetCategory {
  all('All'),
  defi('DeFi'),
  layer1('Layer 1'),
  gaming('Gaming'),
  stablecoin('Stable');

  const AssetCategory(this.label);

  final String label;
}
