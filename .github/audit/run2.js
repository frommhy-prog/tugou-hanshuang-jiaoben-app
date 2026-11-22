const fs = require('fs');
const UA = { 'user-agent': 'Mozilla/5.0', accept: 'application/json' };
const BUA = { 'user-agent': 'binance-web3/1.1 (Skill)', accept: 'application/json' };
const DEX = { solana: 'solana', eth: 'ethereum', base: 'base', bsc: 'bsc' };
const GT = { solana: 'solana', eth: 'eth', base: 'base', bsc: 'bsc' };
const BID = { solana: 'CT_501', eth: '1', base: '8453', bsc: '56' };
const T = [
  { c: 'solana', a: 'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263', n: 'BONK' },
  { c: 'solana', a: 'EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm', n: 'WIF' },
  { c: 'eth', a: '0x6982508145454Ce325dDbE47a25d4ec3d2311933', n: 'PEPE' },
  { c: 'base', a: '0x532f27101965dd16442E59d40670FaF5eBB142E4', n: 'BRETT' },
  { c: 'bsc', a: '0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82', n: 'CAKE' },
];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function j(url, h) {
  const t0 = Date.now();
  try {
    const r = await fetch(url, { headers: h || UA });
    const txt = await r.text();
    let o = null; try { o = JSON.parse(txt); } catch (_) {}
    return { status: r.status, ms: Date.now() - t0, o, txt: o ? undefined : txt.slice(0, 200) };
  } catch (e) { return { status: 0, ms: Date.now() - t0, err: String(e) }; }
}
function flat(o, p, out, d) {
  if (o == null || d > 3 || out.length > 200) return out;
  if (typeof o !== 'object') { out.push(p + '=' + String(o).slice(0, 60)); return out; }
  if (Array.isArray(o)) { out.push(p + '[len]=' + o.length); return out; }
  for (const [k, v] of Object.entries(o)) flat(v, p ? p + '.' + k : k, out, d + 1);
  return out;
}
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
(async () => {
  let S = '';
  const L = (s) => { S += s + '\n'; console.log(s); };
  for (const t of T) {
    L('\n==== ' + t.n + ' ' + t.c);
    const tp = await j('https://api.dexscreener.com/token-pairs/v1/' + DEX[t.c] + '/' + t.a);
    const ld = await j('https://api.dexscreener.com/latest/dex/tokens/' + t.a);
    const v1 = await j('https://api.dexscreener.com/tokens/v1/' + DEX[t.c] + '/' + t.a);
    const gp = await j('https://api.geckoterminal.com/api/v2/networks/' + GT[t.c] + '/tokens/' + t.a + '/pools?page=1');
    const gtok = await j('https://api.geckoterminal.com/api/v2/networks/' + GT[t.c] + '/tokens/' + t.a);
    const bd = await j('https://web3.binance.com/bapi/defi/v4/public/wallet-direct/buw/wallet/market/token/dynamic/info?chainId=' + BID[t.c] + '&contractAddress=' + t.a, BUA);
    const sum = (arr, f) => arr.reduce((a, p) => a + num(f(p)), 0);
    const tpa = Array.isArray(tp.o) ? tp.o : [];
    L('DEX token-pairs/v1 status=' + tp.status + ' n=' + tpa.length + ' liqSum=' + Math.round(sum(tpa, (p) => p.liquidity && p.liquidity.usd)) + ' vol24Sum=' + Math.round(sum(tpa, (p) => p.volume && p.volume.h24)) + ' buys24=' + sum(tpa, (p) => p.txns && p.txns.h24 && p.txns.h24.buys) + ' sells24=' + sum(tpa, (p) => p.txns && p.txns.h24 && p.txns.h24.sells));
    tpa.slice().sort((a, b) => num(b.liquidity && b.liquidity.usd) - num(a.liquidity && a.liquidity.usd)).slice(0, 4).forEach((p) => L('   pool ' + p.dexId + ' ' + (p.labels || []).join('/') + ' quote=' + (p.quoteToken && p.quoteToken.symbol) + ' liq=' + Math.round(num(p.liquidity && p.liquidity.usd)) + ' vol24=' + Math.round(num(p.volume && p.volume.h24)) + ' price=' + p.priceUsd + ' mcap=' + p.marketCap));
    const lda = ld.o && Array.isArray(ld.o.pairs) ? ld.o.pairs.filter((p) => p.chainId === DEX[t.c]) : [];
    L('DEX latest/tokens status=' + ld.status + ' n(chain)=' + lda.length + ' liqSum=' + Math.round(sum(lda, (p) => p.liquidity && p.liquidity.usd)) + ' vol24Sum=' + Math.round(sum(lda, (p) => p.volume && p.volume.h24)));
    L('DEX tokens/v1 n=' + (Array.isArray(v1.o) ? v1.o.length : -1));
    const gpa = gp.o && Array.isArray(gp.o.data) ? gp.o.data : [];
    L('GT pools status=' + gp.status + ' n=' + gpa.length + ' reserveSum=' + Math.round(sum(gpa, (p) => p.attributes.reserve_in_usd)) + ' vol24Sum=' + Math.round(sum(gpa, (p) => p.attributes.volume_usd && p.attributes.volume_usd.h24)) + ' buys24=' + sum(gpa, (p) => p.attributes.transactions && p.attributes.transactions.h24 && p.attributes.transactions.h24.buys));
    const ga = (gtok.o && gtok.o.data && gtok.o.data.attributes) || {};
    L('GT token status=' + gtok.status + ' vol24=' + (ga.volume_usd && ga.volume_usd.h24) + ' reserveTotal=' + Math.round(num(ga.total_reserve_in_usd)));
    L('BIN dynamic status=' + bd.status + ' code=' + (bd.o && bd.o.code) + (bd.txt ? ' txt=' + bd.txt : ''));
    if (bd.o && bd.o.data) flat(bd.o.data, '', [], 0).forEach((x) => L('   B ' + x));
    await sleep(2200);
  }
  fs.mkdirSync('docs/audit', { recursive: true });
  fs.writeFileSync('docs/audit/summary2.txt', S);
})();
