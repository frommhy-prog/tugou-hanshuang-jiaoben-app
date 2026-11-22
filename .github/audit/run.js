const fs = require('fs');
const BASE = 'https://tugou-hanshuang-jiaoben-app.from-mhy.workers.dev';
const UA = { 'user-agent': 'Mozilla/5.0', accept: 'application/json' };
const DEX = { solana: 'solana', eth: 'ethereum', base: 'base', bsc: 'bsc' };
const GT = { solana: 'solana', eth: 'eth', base: 'base', bsc: 'bsc' };
const CG = { solana: 'solana', eth: 'ethereum', base: 'base', bsc: 'binance-smart-chain' };
const GP = { eth: 1, base: 8453, bsc: 56 };
const T = [
  { c: 'solana', a: 'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263', n: 'BONK' },
  { c: 'solana', a: 'EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm', n: 'WIF' },
  { c: 'eth', a: '0x6982508145454Ce325dDbE47a25d4ec3d2311933', n: 'PEPE' },
  { c: 'base', a: '0x532f27101965dd16442E59d40670FaF5eBB142E4', n: 'BRETT' },
  { c: 'bsc', a: '0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82', n: 'CAKE' },
];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function j(url) {
  const t0 = Date.now();
  try {
    const r = await fetch(url, { headers: UA });
    const txt = await r.text();
    let o = null; try { o = JSON.parse(txt); } catch (_) {}
    return { status: r.status, ms: Date.now() - t0, o, txt: o ? undefined : txt.slice(0, 300) };
  } catch (e) { return { status: 0, ms: Date.now() - t0, err: String(e) }; }
}
function flat(o, p, out, d) {
  if (o == null || d > 4 || out.length > 500) return out;
  if (typeof o !== 'object') { out.push(p + '=' + String(o).slice(0, 70)); return out; }
  if (Array.isArray(o)) { out.push(p + '[len]=' + o.length); o.slice(0, 2).forEach((v, i) => flat(v, p + '[' + i + ']', out, d + 1)); return out; }
  for (const [k, v] of Object.entries(o)) flat(v, p ? p + '.' + k : k, out, d + 1);
  return out;
}
(async () => {
  fs.mkdirSync('docs/audit', { recursive: true });
  let S = '';
  const L = (s) => { S += s + '\n'; console.log(s); };
  for (const t of T) {
    L('\n==== ' + t.n + ' ' + t.c + ' ' + t.a);
    const app = await j(BASE + '/api/token?chain=' + t.c + '&address=' + t.a);
    L('APP status=' + app.status + ' ms=' + app.ms + (app.txt ? ' txt=' + app.txt : ''));
    const dex = await j('https://api.dexscreener.com/tokens/v1/' + DEX[t.c] + '/' + t.a);
    const gt = await j('https://api.geckoterminal.com/api/v2/networks/' + GT[t.c] + '/tokens/' + t.a + '?include=top_pools');
    await sleep(2500);
    const cg = await j('https://api.coingecko.com/api/v3/coins/' + CG[t.c] + '/contract/' + (t.c === 'solana' ? t.a : t.a.toLowerCase()));
    const sec = t.c === 'solana' ? await j('https://api.rugcheck.xyz/v1/tokens/' + t.a + '/report') : await j('https://api.gopluslabs.io/api/v1/token_security/' + GP[t.c] + '?contract_addresses=' + t.a);
    const pairs = Array.isArray(dex.o) ? dex.o.slice().sort((a, b) => ((b.liquidity && b.liquidity.usd) || 0) - ((a.liquidity && a.liquidity.usd) || 0)) : [];
    const b = pairs[0] || {};
    const sum = (f) => pairs.reduce((a, p) => a + (Number(f(p)) || 0), 0);
    L('DEX status=' + dex.status + ' pairs=' + pairs.length + ' best.dex=' + b.dexId + ' price=' + b.priceUsd + ' mcap=' + b.marketCap + ' fdv=' + b.fdv + ' liq=' + (b.liquidity && b.liquidity.usd) + ' vol24best=' + (b.volume && b.volume.h24) + ' vol24sum=' + sum((p) => p.volume && p.volume.h24) + ' h24best=' + (b.priceChange && b.priceChange.h24) + ' liqSum=' + sum((p) => p.liquidity && p.liquidity.usd));
    const ga = (gt.o && gt.o.data && gt.o.data.attributes) || {};
    L('GT  status=' + gt.status + ' price=' + ga.price_usd + ' mcap=' + ga.market_cap_usd + ' fdv=' + ga.fdv_usd + ' vol24=' + (ga.volume_usd && ga.volume_usd.h24) + ' reserve=' + ga.total_reserve_in_usd + ' supply=' + ga.normalized_total_supply);
    const md = (cg.o && cg.o.market_data) || {};
    L('CG  status=' + cg.status + ' price=' + (md.current_price && md.current_price.usd) + ' mcap=' + (md.market_cap && md.market_cap.usd) + ' fdv=' + (md.fully_diluted_valuation && md.fully_diluted_valuation.usd) + ' vol24=' + (md.total_volume && md.total_volume.usd) + ' h24=' + md.price_change_percentage_24h + ' circ=' + md.circulating_supply + ' total=' + md.total_supply);
    if (t.c === 'solana') {
      const r = sec.o || {};
      const th = Array.isArray(r.topHolders) ? r.topHolders : [];
      L('RUG status=' + sec.status + ' totalHolders=' + r.totalHolders + ' topHolders.len=' + th.length + ' keys0=' + (th[0] ? Object.keys(th[0]).join(',') : '-') + ' top10_sum(pct)=' + th.slice(0, 10).reduce((a, h) => a + (Number(h.pct) || 0), 0).toFixed(3) + ' top10_sum(percent)=' + th.slice(0, 10).reduce((a, h) => a + (Number(h.percent) || 0), 0));
      L('RUG risks=' + JSON.stringify((r.risks || []).map((x) => x.name + ':' + x.level)).slice(0, 300) + ' mintAuth=' + (r.token && r.token.mintAuthority) + ' freeze=' + (r.token && r.token.freezeAuthority));
    } else {
      const r = (sec.o && sec.o.result && (sec.o.result[t.a.toLowerCase()] || Object.values(sec.o.result)[0])) || {};
      const h = Array.isArray(r.holders) ? r.holders : [];
      L('GP  status=' + sec.status + ' code=' + (sec.o && sec.o.code) + ' holder_count=' + r.holder_count + ' holders.len=' + h.length + ' top10(frac sum)=' + h.slice(0, 10).reduce((a, x) => a + (Number(x.percent) || 0), 0).toFixed(4) + ' buy_tax=' + r.buy_tax + ' sell_tax=' + r.sell_tax + ' honeypot=' + r.is_honeypot + ' owner=' + r.owner_address);
    }
    L('APP-FLAT:');
    flat(app.o, '', [], 0).forEach((x) => L('  ' + x));
    fs.writeFileSync('docs/audit/' + t.n + '.app.json', JSON.stringify(app.o, null, 1).slice(0, 120000));
    await sleep(2500);
  }
  fs.writeFileSync('docs/audit/summary.txt', S);
})();
