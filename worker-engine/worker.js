// TSTZ-M 引擎 Worker v4：Solana + EVM 钱包/代币/持有人/池子交易分析（全部由链上原始数据现算，每条结论附依据）
import { makeEvm } from './evm.js';
const enc = new TextEncoder();
const SOL = 'So11111111111111111111111111111111111111112';
const USDC = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const USDT = 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB';
const QUOTES = new Set([SOL, USDC, USDT]);
const SYS_PROG = '11111111111111111111111111111111';
const HOSTS = ['api.helius.xyz', 'mainnet.helius-rpc.com', 'api.groq.com', 'api.dexscreener.com', 'api.geckoterminal.com', 'api.rugcheck.xyz', 'legacy.internal', 'bnb-mainnet.g.alchemy.com', 'eth-mainnet.g.alchemy.com', 'base-mainnet.g.alchemy.com', 'arb-mainnet.g.alchemy.com', 'opt-mainnet.g.alchemy.com', 'polygon-mainnet.g.alchemy.com', 'bsc-rpc.publicnode.com', 'ethereum-rpc.publicnode.com', 'base-rpc.publicnode.com', 'arbitrum-one-rpc.publicnode.com', 'optimism-rpc.publicnode.com', 'polygon-bor-rpc.publicnode.com']; // 新增：Alchemy 与公共 RPC（仅探测台用）
const GROQ = 'https://api.groq.com/openai/v1';
const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const now = () => Date.now();
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

// ---------- 密钥库 ----------
async function vkey(env) {
  const d = await crypto.subtle.digest('SHA-256', enc.encode(env.VAULT_KEY || ''));
  return crypto.subtle.importKey('raw', d, 'AES-GCM', false, ['decrypt']);
}
async function vGet(env, provider) {
  const r = await env.DB.prepare('SELECT blob FROM vault WHERE provider=?').bind(provider).first();
  if (!r) return null;
  const [ivs, cts] = r.blob.split('.');
  try { return new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(ivs) }, await vkey(env), unb64(cts))); } catch (_) { return null; }
}
function authed(req, env) {
  const h = req.headers.get('authorization') || '';
  const t = h.startsWith('Bearer ') ? h.slice(7) : '';
  const s = env.APP_TOKEN || '';
  if (!s || t.length !== s.length) return false;
  let r = 0;
  for (let i = 0; i < s.length; i++) r |= t.charCodeAt(i) ^ s.charCodeAt(i);
  return r === 0;
}

// ---------- 数据源 ----------
async function jget(url, init, tries = 4) {
  let last = '';
  for (let i = 0; i < tries; i++) {
    const r = await fetch(url, init);
    if (r.status === 429 || r.status >= 500) {
      last = 'http_' + r.status;
      const ra = Number(r.headers.get('retry-after'));
      await sleep(ra > 0 && ra < 10 ? ra * 1000 : 1200 * (i + 1));
      continue;
    }
    const t = await r.text();
    if (!r.ok) throw new Error('http_' + r.status + ':' + t.slice(0, 160));
    return JSON.parse(t);
  }
  throw new Error('数据源限速或暂时不可用(' + last + ')，稍后重试');
}
async function hKey(env) { const k = await vGet(env, 'helius'); if (!k) throw new Error('no_helius_key'); return k; }
async function rpc(env, method, params) {
  const k = await hKey(env);
  const j = await jget('https://mainnet.helius-rpc.com/?api-key=' + k, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) });
  if (j.error) throw new Error(method + ':' + (j.error.message || 'rpc_error'));
  return j.result;
}
// 地址的解析后交易历史（只取 SWAP），从新到旧翻页。complete=true 表示翻到了没有更多记录
async function history(env, addr, pages, type) {
  const k = await hKey(env);
  const txs = []; let before = null, complete = false, used = 0;
  for (let p = 0; p < pages; p++) {
    const url = `https://api.helius.xyz/v0/addresses/${addr}/transactions?api-key=${k}&limit=100${type ? '&type=' + type : ''}${before ? '&before=' + before : ''}`;
    const arr = await jget(url);
    used++;
    if (!Array.isArray(arr) || arr.length === 0) { complete = true; break; }
    txs.push(...arr);
    before = arr[arr.length - 1].signature;
    await sleep(450);
  }
  return { txs, complete, pages: used };
}
async function dexBatch(mints) {
  const out = {};
  for (let i = 0; i < mints.length; i += 30) {
    const j = await jget('https://api.dexscreener.com/latest/dex/tokens/' + mints.slice(i, i + 30).join(','), { headers: { accept: 'application/json' } });
    for (const p of j.pairs || []) {
      const m = p.baseToken && p.baseToken.address; if (!m) continue;
      const liq = (p.liquidity && p.liquidity.usd) || 0;
      if (!out[m] || liq > out[m].liq) out[m] = { sym: p.baseToken.symbol, name: p.baseToken.name, liq, priceUsd: Number(p.priceUsd) || null, priceNative: Number(p.priceNative) || null, quote: p.quoteToken && p.quoteToken.address, pair: p.pairAddress, dex: p.dexId, createdAt: p.pairCreatedAt || null, b24: p.txns && p.txns.h24 ? p.txns.h24.buys : null, s24: p.txns && p.txns.h24 ? p.txns.h24.sells : null, vol24: p.volume ? p.volume.h24 : null, mc: p.marketCap || p.fdv || null };
    }
  }
  return out;
}

// ---------- 交易提取：用链上余额变化，不猜 ----------
function extractTrades(txs, W) {
  const trades = []; let multi = 0, fees = 0;
  for (const tx of txs) {
    let lam = 0; const tok = {};
    for (const a of tx.accountData || []) {
      if (a.account === W) lam += a.nativeBalanceChange || 0;
      for (const t of a.tokenBalanceChanges || []) {
        if (t.userAccount !== W) continue;
        const dec = (t.rawTokenAmount && t.rawTokenAmount.decimals) || 0;
        tok[t.mint] = (tok[t.mint] || 0) + Number((t.rawTokenAmount && t.rawTokenAmount.tokenAmount) || 0) / Math.pow(10, dec);
      }
    }
    if (tx.feePayer === W) { lam += tx.fee || 0; fees += tx.fee || 0; }
    const dSOL = lam / 1e9 + (tok[SOL] || 0);
    const dUSD = (tok[USDC] || 0) + (tok[USDT] || 0);
    const bases = Object.keys(tok).filter((m) => !QUOTES.has(m) && Math.abs(tok[m]) > 0);
    if (bases.length !== 1) { if (bases.length > 1) multi++; continue; }
    const m = bases[0], d = tok[m];
    let q = null, amt = 0;
    if (d > 0 && dSOL < -0.0005) { q = 'SOL'; amt = -dSOL; }
    else if (d < 0 && dSOL > 0.0005) { q = 'SOL'; amt = dSOL; }
    else if (d > 0 && dUSD < -0.01) { q = 'USD'; amt = -dUSD; }
    else if (d < 0 && dUSD > 0.01) { q = 'USD'; amt = dUSD; }
    if (!q) continue;
    trades.push({ sig: tx.signature, t: tx.timestamp, mint: m, side: d > 0 ? 'buy' : 'sell', qty: Math.abs(d), amt, q, src: tx.source || null });
  }
  return { trades, multi, fees: fees / 1e9 };
}
// 平均成本法账本：卖出只在有已记录买入的部分计盈亏，其余标「来源不明」，不硬算
function ledger(trades) {
  const asc = [...trades].sort((a, b) => a.t - b.t);
  const pos = {};
  for (const x of asc) {
    const key = x.mint + '|' + x.q;
    const p = pos[key] || (pos[key] = { mint: x.mint, q: x.q, qty: 0, cost: 0, bought: 0, boughtAmt: 0, sold: 0, soldAmt: 0, realized: 0, buys: 0, sells: 0, firstBuy: null, lastSell: null, firstTrade: x.t, lastTrade: x.t, uncovQty: 0, uncovAmt: 0, bestSig: null, bestPnl: -Infinity, worstSig: null, worstPnl: Infinity });
    p.lastTrade = x.t;
    if (x.side === 'buy') { p.qty += x.qty; p.cost += x.amt; p.bought += x.qty; p.boughtAmt += x.amt; p.buys++; if (p.firstBuy == null) p.firstBuy = x.t; }
    else {
      p.sells++; p.sold += x.qty; p.soldAmt += x.amt; p.lastSell = x.t;
      if (p.qty > 1e-9) {
        const cov = Math.min(x.qty, p.qty), frac = cov / x.qty, costCov = p.cost * (cov / p.qty);
        const pnl = x.amt * frac - costCov;
        p.realized += pnl; p.cost -= costCov; p.qty -= cov;
        if (pnl > p.bestPnl) { p.bestPnl = pnl; p.bestSig = x.sig; }
        if (pnl < p.worstPnl) { p.worstPnl = pnl; p.worstSig = x.sig; }
        if (x.qty > cov) { p.uncovQty += x.qty - cov; p.uncovAmt += x.amt * (1 - frac); }
      } else { p.uncovQty += x.qty; p.uncovAmt += x.amt; }
    }
  }
  return pos;
}
const dur = (s) => (s == null ? '未知' : s < 90 ? Math.round(s) + ' 秒' : s < 5400 ? (s / 60).toFixed(1) + ' 分钟' : s < 172800 ? (s / 3600).toFixed(1) + ' 小时' : (s / 86400).toFixed(1) + ' 天');
const r4 = (v) => (v == null ? null : Math.round(v * 10000) / 10000);

function summarize(trades, pos, h, multi, fees) {
  const sol = Object.values(pos).filter((p) => p.q === 'SOL');
  const realizedSet = sol.filter((p) => p.sells > 0 && p.sold > p.uncovQty + 1e-12);
  const wins = realizedSet.filter((p) => p.realized > 0);
  const realizedTotal = realizedSet.reduce((s, p) => s + p.realized, 0);
  const closed = sol.filter((p) => p.sells > 0 && p.firstBuy != null && p.qty <= 0.05 * p.bought);
  const holds = closed.map((p) => ({ mint: p.mint, s: p.lastSell - p.firstBuy })).filter((x) => x.s >= 0).sort((a, b) => a.s - b.s);
  const medHold = holds.length ? holds[Math.floor(holds.length / 2)].s : null;
  const buys = trades.filter((t) => t.side === 'buy' && t.q === 'SOL');
  const buyAmts = buys.map((t) => t.amt).sort((a, b) => a - b);
  const medBuy = buyAmts.length ? buyAmts[Math.floor(buyAmts.length / 2)] : null;
  const ts = trades.map((t) => t.t).sort((a, b) => a - b);
  const allTs = h.txs.map((t) => t.timestamp).filter(Boolean).sort((a, b) => a - b);
  const winSpan = allTs.length > 1 ? (allTs[allTs.length - 1] - allTs[0]) / 86400 : null;
  const spanDays = ts.length > 1 ? Math.max(1 / 24, (ts[ts.length - 1] - ts[0]) / 86400) : null;
  const S = {
    swapTx: h.txs.length, pages: h.pages, complete: h.complete, tradeN: trades.length, multiSkipped: multi, feesSol: r4(fees),
    from: ts[0] || allTs[0] || null, to: ts[ts.length - 1] || allTs[allTs.length - 1] || null, spanDays: winSpan != null ? r4(winSpan) : (spanDays ? r4(spanDays) : null),
    tokensTraded: new Set(trades.map((t) => t.mint)).size, realizedN: realizedSet.length, winN: wins.length,
    winRate: realizedSet.length ? r4(wins.length / realizedSet.length) : null, realizedSol: r4(realizedTotal),
    closedN: closed.length, medHoldSec: medHold, medBuySol: r4(medBuy), perDay: spanDays ? r4(trades.length / spanDays) : null,
    uncoveredTokens: sol.filter((p) => p.uncovQty > 1e-9).length, usdQuoteTrades: trades.filter((t) => t.q === 'USD').length,
  };
  const tags = [];
  if (closed.length >= 5 && medHold != null) {
    const evs = holds.slice(0, 5).map((x) => ({ mint: x.mint, text: '持仓 ' + dur(x.s) }));
    if (medHold < 900) tags.push({ tag: '快进快出', basis: `已平仓 ${closed.length} 个，持仓时间中位数 ${dur(medHold)}（判定阈值 15 分钟）`, ev: evs });
    else if (medHold > 6 * 3600) tags.push({ tag: '波段/持有型', basis: `已平仓 ${closed.length} 个，持仓时间中位数 ${dur(medHold)}（判定阈值 6 小时）`, ev: [] });
  }
  if (S.perDay != null && trades.length >= 30 && S.perDay >= 40) tags.push({ tag: '高频交易', basis: `窗口内 ${trades.length} 笔 / ${r4(spanDays)} 天，约 ${Math.round(S.perDay)} 笔/天（阈值 40）`, ev: [] });
  if (buyAmts.length >= 10) {
    const f = {}; for (const a of buyAmts) { const k = a.toFixed(2); f[k] = (f[k] || 0) + 1; }
    const top = Object.entries(f).sort((a, b) => b[1] - a[1])[0];
    if (top[1] / buyAmts.length >= 0.4) tags.push({ tag: '固定金额买入（疑似程序化）', basis: `${buyAmts.length} 笔买入里有 ${top[1]} 笔金额都是 ${top[0]} SOL（占 ${Math.round(top[1] / buyAmts.length * 100)}%，阈值 40%）`, ev: [] });
  }
  const sec = {}; for (const t of trades) sec[t.t] = (sec[t.t] || 0) + 1;
  const burst = Object.values(sec).filter((x) => x >= 3).length;
  if (burst >= 3) tags.push({ tag: '同一秒多笔成交（疑似程序化）', basis: `有 ${burst} 个时间点在同一秒内成交 3 笔及以上`, ev: [] });
  if (S.realizedN >= 8 && S.winRate != null) {
    if (S.winRate >= 0.6 && realizedTotal > 0) tags.push({ tag: '胜率高且净盈利', basis: `已兑现 ${S.realizedN} 个币，盈利 ${S.winN} 个（${Math.round(S.winRate * 100)}%），合计 ${r4(realizedTotal)} SOL`, ev: [] });
    else if (S.winRate <= 0.3 && realizedTotal < 0) tags.push({ tag: '胜率低且净亏损', basis: `已兑现 ${S.realizedN} 个币，盈利仅 ${S.winN} 个（${Math.round(S.winRate * 100)}%），合计 ${r4(realizedTotal)} SOL`, ev: [] });
  }
  if (medBuy != null && buyAmts.length >= 10) {
    if (medBuy < 0.05) tags.push({ tag: '小额试单', basis: `买入金额中位数 ${r4(medBuy)} SOL（阈值 0.05）`, ev: [] });
    else if (medBuy >= 5) tags.push({ tag: '大额重仓', basis: `买入金额中位数 ${r4(medBuy)} SOL（阈值 5）`, ev: [] });
  }
  const notes = [];
  if (!h.complete) notes.push(`只分析了最近 ${h.txs.length} 笔 swap（${S.spanDays != null ? '约 ' + r4(S.spanDays) + ' 天' : '时间跨度未知'}），更早的历史没有纳入，成本与盈亏只覆盖窗口内`);
  if (h.txs.length > 0 && trades.length === 0) notes.push(`读到 ${h.txs.length} 笔涉及该地址的 swap，但按链上余额变化无法归属为它自己的买卖（常见于做市商、路由或中转账户），所以没有盈亏统计`);
  else if (h.txs.length > 0 && trades.length < h.txs.length) notes.push(`${h.txs.length} 笔 swap 中 ${trades.length} 笔能归属为该钱包的买卖，其余是多币路由、纯转账或金额过小的变动`);
  if (S.uncoveredTokens > 0) notes.push(`${S.uncoveredTokens} 个币在窗口内出现过「卖出但找不到对应买入」，这部分不计入盈亏（可能是窗口之前买入、转入或空投）`);
  if (multi > 0) notes.push(`${multi} 笔一次涉及多个币的交易未计入`);
  if (S.usdQuoteTrades > 0) notes.push(`${S.usdQuoteTrades} 笔以 USDC/USDT 计价的交易未计入 SOL 盈亏统计`);
  notes.push('SOL 金额取自链上余额变化，含网络费、小费、账户租金，是近似值；盈亏按平均成本法计算');
  const sample = S.realizedN >= 8 && (S.spanDays || 0) >= 1 ? '样本可用' : '样本偏少，结论仅供参考';
  return { stats: S, tags, notes, sample };
}

// ---------- 操作 ----------
async function opWallet(env, addr, pages) {
  const h = await history(env, addr, pages, 'SWAP');
  const { trades, multi, fees } = extractTrades(h.txs, addr);
  const pos = ledger(trades);
  const mints = [...new Set(trades.map((t) => t.mint))];
  const info = mints.length ? await dexBatch(mints.slice(0, 60)) : {};
  const sum = summarize(trades, pos, h, multi, fees);
  const positions = Object.values(pos).map((p) => {
    const i = info[p.mint] || {};
    const open = p.qty > 1e-9 && p.q === 'SOL' && i.priceNative && i.quote === SOL ? p.qty * i.priceNative : null;
    return { mint: p.mint, sym: i.sym || null, q: p.q, buys: p.buys, sells: p.sells, bought: p.bought, sold: p.sold, boughtAmt: r4(p.boughtAmt), soldAmt: r4(p.soldAmt), realized: r4(p.realized), remainingQty: p.qty > 1e-9 ? p.qty : 0, remainingCost: p.qty > 1e-9 ? r4(p.cost) : 0, unrealized: open != null ? r4(open - p.cost) : null, firstBuy: p.firstBuy, lastSell: p.lastSell, firstTrade: p.firstTrade, lastTrade: p.lastTrade, uncovQty: p.uncovQty > 1e-9 ? p.uncovQty : 0, bestSig: p.bestSig, worstSig: p.worstSig, liqUsd: i.liq || null };
  }).sort((a, b) => b.lastTrade - a.lastTrade);
  for (const tg of sum.tags) for (const e of tg.ev) e.sym = (info[e.mint] || {}).sym || null;
  const recent = [...trades].sort((a, b) => b.t - a.t).slice(0, 200).map((t) => ({ ...t, sym: (info[t.mint] || {}).sym || null, amt: r4(t.amt) }));
  return { address: addr, ...sum, positions, trades: recent, at: now() };
}

async function opHolder(env, mint, owner, pages) {
  const h = await history(env, owner, pages, 'SWAP');
  const { trades, multi, fees } = extractTrades(h.txs, owner);
  const pos = ledger(trades);
  const sum = summarize(trades, pos, h, multi, fees);
  const mine = Object.values(pos).filter((p) => p.mint === mint).map((p) => ({ q: p.q, buys: p.buys, sells: p.sells, bought: p.bought, sold: p.sold, boughtAmt: r4(p.boughtAmt), soldAmt: r4(p.soldAmt), realized: r4(p.realized), remainingQty: p.qty > 1e-9 ? p.qty : 0, remainingCost: p.qty > 1e-9 ? r4(p.cost) : 0, firstBuy: p.firstBuy, lastSell: p.lastSell, uncovQty: p.uncovQty > 1e-9 ? p.uncovQty : 0, avgBuyPrice: p.bought > 0 ? p.boughtAmt / p.bought : null }));
  const tradesThis = trades.filter((t) => t.mint === mint).sort((a, b) => b.t - a.t).slice(0, 40).map((t) => ({ ...t, amt: r4(t.amt) }));
  const finding = mine.length === 0 ? '窗口内没有这个币的买卖记录：可能是更早买入、转账获得、空投或程序分发，成本无法确认' : null;
  return { owner, mint, tokenPositions: mine, tradesThis, finding, ...sum, at: now() };
}

async function opPool(env, pair, mint, pages) {
  const h = await history(env, pair, pages, 'SWAP');
  const by = {}; let buy = 0, sell = 0, nb = 0, ns = 0; const times = [];
  for (const tx of h.txs) {
    const w = tx.feePayer; if (!w) continue;
    const { trades } = extractTrades([tx], w);
    for (const t of trades) {
      if (t.mint !== mint || t.q !== 'SOL') continue;
      const a = by[w] || (by[w] = { w, buySol: 0, sellSol: 0, nb: 0, ns: 0, first: t.t, last: t.t });
      if (t.side === 'buy') { a.buySol += t.amt; a.nb++; buy += t.amt; nb++; } else { a.sellSol += t.amt; a.ns++; sell += t.amt; ns++; }
      a.first = Math.min(a.first, t.t); a.last = Math.max(a.last, t.t); times.push(t.t);
    }
  }
  const arr = Object.values(by);
  const gross = buy + sell;
  const top = (k) => [...arr].sort((a, b) => b[k] - a[k]).slice(0, 8).filter((x) => x[k] > 0).map((x) => ({ w: x.w, buySol: r4(x.buySol), sellSol: r4(x.sellSol), nb: x.nb, ns: x.ns }));
  const topBuyers = top('buySol'), topSellers = top('sellSol');
  const top5Share = gross > 0 ? arr.map((a) => a.buySol + a.sellSol).sort((a, b) => b - a).slice(0, 5).reduce((s, v) => s + v, 0) / gross : null;
  const wash = arr.filter((a) => a.nb >= 3 && a.ns >= 3 && Math.abs(a.buySol - a.sellSol) / Math.max(1e-9, a.buySol + a.sellSol) < 0.15).map((a) => ({ w: a.w, nb: a.nb, ns: a.ns, buySol: r4(a.buySol), sellSol: r4(a.sellSol) }));
  const repeat = arr.filter((a) => a.nb + a.ns >= 6).length;
  times.sort((a, b) => a - b);
  const findings = [];
  const attributed = nb + ns;
  if (gross > 0) {
    findings.push({ level: 'info', text: `窗口内买入 ${r4(buy)} SOL（${nb} 笔）、卖出 ${r4(sell)} SOL（${ns} 笔），净流入 ${r4(buy - sell)} SOL`, basis: `读取 ${h.txs.length} 笔 swap，其中 ${attributed} 笔能归属为该币的 SOL 计价买卖${times.length ? '，跨度 ' + dur(times[times.length - 1] - times[0]) : ''}` });
    if (top5Share != null && top5Share > 0.5 && arr.length >= 3) findings.push({ level: 'warn', text: `前 5 个交易地址贡献了窗口内 ${Math.round(top5Share * 100)}% 的成交额，成交高度集中`, basis: `共 ${arr.length} 个交易地址` });
    if (wash.length) findings.push({ level: 'warn', text: `${wash.length} 个地址在窗口内买卖各 ≥3 笔且买卖额接近（差额 <15%）。这种模式可能是套利机器人，也可能是对敲刷量，仅凭链上数据无法区分`, basis: wash.slice(0, 3).map((x) => x.w.slice(0, 6) + '…买' + x.nb + '卖' + x.ns).join('、') });
    if (arr.length >= 8 && repeat / arr.length > 0.4) findings.push({ level: 'warn', text: `${Math.round(repeat / arr.length * 100)}% 的交易地址在窗口内成交 ≥6 笔，程序化交易占比高`, basis: `${repeat} / ${arr.length} 个地址` });
  } else findings.push({ level: 'info', text: '窗口内没有解析到该币的 SOL 计价买卖', basis: `读取 ${h.txs.length} 笔 swap` });
  return { pair, mint, attributed, window: { swapTx: h.txs.length, from: times[0] || null, to: times[times.length - 1] || null, complete: h.complete, pages: h.pages }, totals: { buySol: r4(buy), sellSol: r4(sell), nb, ns, traders: arr.length, netInSol: r4(buy - sell) }, topBuyers, topSellers, wash, findings, notes: ['只统计该池子最近的 SOL 计价买卖；多池子代币需分别查看', '地址为交易发起人（手续费支付者），可能是机器人或聚合器'], at: now() };
}

async function opToken(env, mint) {
  const [dx, sup, lg, mi] = await Promise.all([
    dexBatch([mint]),
    rpc(env, 'getTokenSupply', [mint]),
    rpc(env, 'getTokenLargestAccounts', [mint]),
    rpc(env, 'getAccountInfo', [mint, { encoding: 'jsonParsed' }]),
  ]);
  const total = Number(sup.value.uiAmountString || sup.value.uiAmount);
  const minfo = mi && mi.value && mi.value.data && mi.value.data.parsed ? mi.value.data.parsed.info : {};
  const accts = lg.value || [];
  const ta = accts.length ? await rpc(env, 'getMultipleAccounts', [accts.map((a) => a.address), { encoding: 'jsonParsed' }]) : { value: [] };
  const owners = accts.map((a, i) => (ta.value[i] && ta.value[i].data && ta.value[i].data.parsed ? ta.value[i].data.parsed.info.owner : null));
  const uniq = [...new Set(owners.filter(Boolean))];
  const oa = uniq.length ? await rpc(env, 'getMultipleAccounts', [uniq, { encoding: 'base64', dataSlice: { offset: 0, length: 0 } }]) : { value: [] };
  const oinfo = {}; uniq.forEach((o, i) => { const a = oa.value[i]; oinfo[o] = a ? { program: a.owner, exec: a.executable, lamports: a.lamports } : null; });
  const kindOf = (i) => (!i ? 'pda' : i.exec ? 'program' : i.program === SYS_PROG ? 'wallet' : 'contract');
  const g = {};
  accts.forEach((a, i) => {
    const o = owners[i] || a.address;
    const k = kindOf(owners[i] ? oinfo[owners[i]] : null);
    const e = g[o] || (g[o] = { owner: o, amount: 0, accounts: 0, kind: owners[i] ? k : 'unknown', program: owners[i] && oinfo[owners[i]] ? oinfo[owners[i]].program : null });
    e.amount += Number(a.uiAmountString || a.uiAmount); e.accounts++;
  });
  const holders = Object.values(g).sort((a, b) => b.amount - a.amount).map((x, i) => ({ rank: i + 1, owner: x.owner, kind: x.kind, program: x.program, amount: x.amount, pct: total > 0 ? r4(x.amount / total * 100) : null }));
  const sumPct = (arr) => r4(arr.reduce((s, x) => s + (x.pct || 0), 0));
  const wallets = holders.filter((x) => x.kind === 'wallet');
  const conc = { top1: sumPct(holders.slice(0, 1)), top5: sumPct(holders.slice(0, 5)), top10: sumPct(holders.slice(0, 10)), top20: sumPct(holders), wallets10: sumPct(wallets.slice(0, 10)), nonWallet: sumPct(holders.filter((x) => x.kind !== 'wallet')), listed: holders.length };
  const mk = dx[mint] || null;
  const f = [];
  f.push(minfo.mintAuthority ? { level: 'risk', text: '仍有增发权限，发行方可以继续增发代币', basis: '链上 mint 账户 mintAuthority = ' + minfo.mintAuthority } : { level: 'ok', text: '已放弃增发权限', basis: '链上 mint 账户 mintAuthority 为空' });
  f.push(minfo.freezeAuthority ? { level: 'risk', text: '仍有冻结权限，发行方可以冻结持有人账户', basis: '链上 mint 账户 freezeAuthority = ' + minfo.freezeAuthority } : { level: 'ok', text: '已放弃冻结权限', basis: '链上 mint 账户 freezeAuthority 为空' });
  if (conc.wallets10 != null && wallets.length >= 3) f.push({ level: conc.wallets10 >= 30 ? 'risk' : conc.wallets10 >= 15 ? 'warn' : 'ok', text: `前 ${Math.min(10, wallets.length)} 大普通钱包合计持有 ${conc.wallets10}%`, basis: '来自链上最大 20 个代币账户，已按钱包/池子/合约分类（无 SOL 的派生地址、程序持有账户不计入钱包）' });
  if (conc.nonWallet >= 50) f.push({ level: 'info', text: `最大 20 个账户里 ${conc.nonWallet}% 在池子/合约/派生地址中，不是普通钱包`, basis: '多为 AMM 金库、质押或发射台合约' });
  if (conc.top1 >= 20 && holders[0].kind === 'wallet') f.push({ level: 'risk', text: `第 1 大持有人是普通钱包，持有 ${conc.top1}%`, basis: '地址 ' + holders[0].owner });
  if (mk && mk.createdAt) f.push({ level: 'info', text: '最深池子创建于 ' + new Date(mk.createdAt).toISOString().slice(0, 16).replace('T', ' ') + ' UTC', basis: 'Dexscreener pairCreatedAt' });
  return { mint, decimals: sup.value.decimals, supply: total, authorities: { mint: minfo.mintAuthority || null, freeze: minfo.freezeAuthority || null }, market: mk, holders, concentration: conc, findings: f, notes: ['持有人来自链上最大 20 个代币账户（RPC 只提供前 20），不是全部持有人', '同一钱包的多个代币账户已合并'], at: now() };
}

// ---------- AI（Groq）：只能解读已算出的事实 ----------
const AI_SYS = '你是链上数据分析师。你只能使用用户给出的 facts（已由程序从链上原始数据算出）。规则：1）每条结论必须在 basis 里引用 facts 中的具体字段名和数值；2）facts 里没有的内容一律写“未知”，禁止猜测、禁止编造数字和地址；3）样本偏少或窗口不全时必须明说；4）不给买卖建议。输出严格 JSON：{"summary":"一段不超过120字的结论","judgement":"一句话判断（例如：疑似程序化短线、样本不足无法判断）","points":[{"claim":"结论","basis":"依据（引用 facts 字段与数值）"}],"unknown":["facts 无法回答的问题"]}。全部使用简体中文。';
async function groqModels(env, key, force) {
  const c = await env.DB.prepare("SELECT v FROM kv WHERE k='groq_model2'").first();
  if (c && !force) { try { const o = JSON.parse(c.v); if (now() - o.at < 6 * 3600e3) return o.list; } catch (_) {} }
  const r = await fetch(GROQ + '/models', { headers: { authorization: 'Bearer ' + key } });
  if (!r.ok) throw new Error('groq_models_' + r.status);
  const data = (await r.json()).data || [];
  const ok = data.filter((m) => m.active !== false && (!m.output_modalities || m.output_modalities.includes('text')) && !/whisper|guard|tts|orpheus|safeguard|prompt/i.test(m.id) && (!m.supported_features || m.supported_features.includes('json_mode')) && (m.context_window || 0) >= 8000).map((m) => m.id);
  const rank = (id) => (/gpt-oss-120b/.test(id) ? 0 : /qwen/.test(id) ? 1 : /gpt-oss-20b/.test(id) ? 2 : /llama/.test(id) ? 3 : 9);
  ok.sort((a, b) => rank(a) - rank(b));
  await env.DB.prepare("INSERT OR REPLACE INTO kv (k,v) VALUES ('groq_model2',?)").bind(JSON.stringify({ list: ok, at: now() })).run();
  return ok;
}
async function opAI(env, body) {
  const key = await vGet(env, 'groq');
  if (!key) return { error: 'no_groq_key' };
  let list = await groqModels(env, key, false), last = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    const model = list[attempt];
    if (!model) break;
    const payload = { model, temperature: 0.2, max_tokens: 2600, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: AI_SYS }, { role: 'user', content: '类型=' + (body.kind || '') + '\nfacts=' + JSON.stringify(body.facts).slice(0, 8000) }] }; // facts 截断 14000→8000（Groq 每分钟令牌上限 8000）
    if (/gpt-oss/.test(model)) payload.reasoning_effort = 'low';
    const r = await fetch(GROQ + '/chat/completions', { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + key }, body: JSON.stringify(payload) });
    const hdr = { status: r.status, model };
    for (const [k, v] of r.headers) if (k.startsWith('x-ratelimit') || k === 'retry-after') hdr[k] = v;
    await env.DB.prepare('INSERT OR REPLACE INTO quota (provider,hdr,at) VALUES (?,?,?)').bind('groq', JSON.stringify(hdr), now()).run();
    const txt = await r.text();
    if (r.status === 404 || r.status === 400) { last = { error: 'groq_' + r.status, detail: txt.slice(0, 200) }; if (attempt === 0) list = await groqModels(env, key, true); continue; }
    if (!r.ok) return { error: 'groq_' + r.status, detail: txt.slice(0, 200), hdr };
    try {
      const c = JSON.parse(txt).choices[0].message.content || '';
      const m = c.match(/\{[\s\S]*\}/);
      return { analysis: JSON.parse(m ? m[0] : c), model, quota: hdr };
    } catch (e) { return { error: 'groq_parse', detail: txt.slice(0, 200), hdr }; }
  }
  return last || { error: 'no_model' };
}

// ---------- 路由 ----------
async function cached(env, key, ttl, fresh, fn) {
  if (!fresh) {
    const c = await env.DB.prepare('SELECT v, at FROM cache WHERE k=?').bind(key).first();
    if (c && now() - c.at < ttl * 1000) { const o = JSON.parse(c.v); o.cached = true; return o; }
  }
  const o = await fn();
  await env.DB.prepare('INSERT OR REPLACE INTO cache (k,v,at) VALUES (?,?,?)').bind(key, JSON.stringify(o), now()).run();
  return o;
}
const okSol = (s) => /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(s || '');
const okEvm = (s) => /^0x[0-9a-fA-F]{40}$/.test(s || '');
const EVMX = makeEvm({ vGet, jget, sleep, now, r4, dur, ledger }); // 新增：EVM 模块

export class Job {
  constructor(state, env) { this.state = state; this.env = env; }
  async fetch(req) {
    const env = this.env, url = new URL(req.url), p = url.pathname, q = url.searchParams;
    const fresh = q.get('fresh') === '1';
    try {
      if (p === '/e/ping') return json({ ok: true, at: now() });
      if (p === '/e/sol/token') { const m = q.get('mint'); if (!okSol(m)) return json({ error: 'bad_mint' }, 400); return json(await cached(env, 'tok:' + m, 90, fresh, () => opToken(env, m))); }
      if (p === '/e/sol/wallet') { const a = q.get('address'); if (!okSol(a)) return json({ error: 'bad_address' }, 400); const pg = Math.min(8, Math.max(1, Number(q.get('pages')) || 3)); return json(await cached(env, 'w:' + a + ':' + pg, 120, fresh, () => opWallet(env, a, pg))); }
      if (p === '/e/sol/holder') { const m = q.get('mint'), o = q.get('owner'); if (!okSol(m) || !okSol(o)) return json({ error: 'bad_args' }, 400); const pg = Math.min(5, Math.max(1, Number(q.get('pages')) || 3)); return json(await cached(env, 'h:' + m + ':' + o + ':' + pg, 600, fresh, () => opHolder(env, m, o, pg))); }
      if (p === '/e/sol/pool') { const pr = q.get('pair'), m = q.get('mint'); if (!okSol(pr) || !okSol(m)) return json({ error: 'bad_args' }, 400); const pg = Math.min(6, Math.max(1, Number(q.get('pages')) || 3)); return json(await cached(env, 'p:' + pr + ':' + m + ':' + pg, 90, fresh, () => opPool(env, pr, m, pg))); }
      if (p === '/e/ai') { const b = await req.json(); return json(await opAI(env, b)); }
      // ---- EVM（新增）----
      if (p === '/e/evm/chains') return json({ chains: EVMX.chains, keyPresent: await EVMX.hasKey(env) });
      if (p === '/e/evm/_sim') return json(EVMX.sim());
      if (p.startsWith('/e/evm/')) {
        const ch = q.get('chain');
        if (!EVMX.ok(ch)) return json({ error: 'chain_unsupported', detail: '支持：' + EVMX.chains.join('、') }, 400);
        const pg = Math.min(6, Math.max(1, Number(q.get('pages')) || 3));
        if (p === '/e/evm/wallet') { const a = q.get('address'); if (!okEvm(a)) return json({ error: 'bad_address' }, 400); return json(await cached(env, 'ew:' + ch + ':' + a.toLowerCase() + ':' + pg, 120, fresh, () => EVMX.opWallet(env, ch, a, pg))); }
        if (p === '/e/evm/holder') { const t = q.get('token'), o = q.get('owner'); if (!okEvm(t) || !okEvm(o)) return json({ error: 'bad_args' }, 400); return json(await cached(env, 'eh:' + ch + ':' + t.toLowerCase() + ':' + o.toLowerCase() + ':' + pg, 600, fresh, () => EVMX.opHolder(env, ch, t, o, pg))); }
        if (p === '/e/evm/token') { const t = q.get('token'); if (!okEvm(t)) return json({ error: 'bad_token' }, 400); return json(await cached(env, 'et:' + ch + ':' + t.toLowerCase() + ':' + pg, 90, fresh, () => EVMX.opToken(env, ch, t, pg))); }
      }
      return json({ error: 'not_found' }, 404);
    } catch (e) {
      if (String((e && e.message) || e) === 'no_alchemy_key') return json({ error: 'no_alchemy_key' }); // 新增：未配 Alchemy 密钥时返回 200 + 错误码，App 好提示
      return json({ error: 'engine', detail: String((e && e.message) || e).slice(0, 300) }, 502);
    }
  }
}

// ---------- 探测台（仅供开发排查）----------
const sub = (s, keys) => String(s).replace(/\{\{(\w+)\}\}/g, (_, k) => keys[k] ?? '');
async function probe(env, m) {
  const keys = {};
  for (const p of ['groq', 'helius']) keys[p] = (await vGet(env, p)) || '';
  keys.alchemy = (await vGet(env, 'alchemy')) || env.ALCHEMY_API_KEY || ''; // 新增
  const url = sub(m.url, keys);
  const host = new URL(url).host;
  if (!HOSTS.includes(host)) return { error: 'host_not_allowed', host };
  const headers = {};
  for (const [k, v] of Object.entries(m.headers || {})) headers[k] = sub(v, keys);
  const init = { method: m.method || 'GET', headers };
  if (m.body) init.body = sub(typeof m.body === 'string' ? m.body : JSON.stringify(m.body), keys);
  const t0 = Date.now();
  const r = host === 'legacy.internal' ? await env.LEGACY.fetch(url, init) : await fetch(url, init);
  const txt = await r.text();
  return { status: r.status, ms: Date.now() - t0, len: txt.length, head: txt.slice(m.skip || 0, (m.skip || 0) + (m.max || 3000)).split(keys.alchemy || '\u0000').join('***') }; // 新增：输出里抹掉 Alchemy 密钥
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === '/health') return json({ ok: true, v: 4 });
    if (!authed(req, env)) return json({ error: 'unauthorized' }, 401);
    if (!url.pathname.startsWith('/e/')) return json({ error: 'not_found' }, 404);
    const stub = env.JOB.get(env.JOB.idFromName(crypto.randomUUID()));
    return stub.fetch(req);
  },
  async queue(batch, env) {
    for (const msg of batch.messages) {
      const m = msg.body || {};
      let out;
      try {
        if (m.op === 'api') {
          const stub = env.JOB.get(env.JOB.idFromName(crypto.randomUUID()));
          const r = await stub.fetch('https://job' + m.path, { method: m.method || 'GET', body: m.body ? JSON.stringify(m.body) : undefined });
          const t = await r.text();
          out = { status: r.status, len: t.length, head: t.slice(m.skip || 0, (m.skip || 0) + (m.max || 6000)) };
        } else out = await probe(env, m);
      } catch (e) { out = { error: String((e && e.message) || e) }; }
      await env.DB.prepare('INSERT INTO selftest (ts,name,out) VALUES (?,?,?)').bind(now(), m.name || 'probe', JSON.stringify(out).slice(0, 30000)).run();
      msg.ack();
    }
  },
};
