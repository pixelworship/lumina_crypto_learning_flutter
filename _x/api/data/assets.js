// Mirror of the Flutter app's static asset catalog
// (lib/data/services/asset_catalog.dart). Kept in lockstep so the
// `/v1/assets` endpoint can answer "what symbols can I query?"
// without the client having to know the list out-of-band.

/**
 * @typedef {Object} AssetEntry
 * @property {string} id
 * @property {string} symbol
 * @property {string} name
 * @property {string[]} categories
 */

/** @type {AssetEntry[]} */
export const SUPPORTED_ASSETS = [
  { id: 'btc',  symbol: 'BTC',  name: 'Bitcoin',      categories: ['layer1'] },
  { id: 'eth',  symbol: 'ETH',  name: 'Ethereum',     categories: ['layer1', 'defi'] },
  { id: 'sol',  symbol: 'SOL',  name: 'Solana',       categories: ['layer1'] },
  { id: 'uni',  symbol: 'UNI',  name: 'Uniswap',      categories: ['defi'] },
  { id: 'ada',  symbol: 'ADA',  name: 'Cardano',      categories: ['layer1'] },
  { id: 'usdt', symbol: 'USDT', name: 'Tether',       categories: ['stablecoin'] },
  { id: 'avax', symbol: 'AVAX', name: 'Avalanche',    categories: ['layer1', 'defi'] },
  { id: 'axs',  symbol: 'AXS',  name: 'Axie Infinity', categories: ['gaming'] },
  { id: 'sand', symbol: 'SAND', name: 'The Sandbox',  categories: ['gaming'] },
];

const BY_SYMBOL = new Map(
  SUPPORTED_ASSETS.map((a) => [a.symbol.toUpperCase(), a]),
);

/** Looks up a CATALOG asset by symbol (case-insensitive). */
export function findBySymbol(symbol) {
  if (!symbol) return null;
  return BY_SYMBOL.get(symbol.toUpperCase()) ?? null;
}

/**
 * Permissive ticker shape — uppercase alphanumerics, 1-16 chars.
 *
 * The events table is intentionally schema-light: any string the
 * client wants to store is fine, but we still gate on a sane format
 * so an empty/garbled value never lands in `chart_events.asset` and
 * starts polluting filtered queries. Catalog membership is a UI
 * affordance (see `/v1/assets`), not an authorization check.
 */
const TICKER_REGEX = /^[A-Z0-9]{1,16}$/;

export function isValidAssetSymbol(symbol) {
  if (typeof symbol !== "string") return false;
  return TICKER_REGEX.test(symbol.toUpperCase());
}
