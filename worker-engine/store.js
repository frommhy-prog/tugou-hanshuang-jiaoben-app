// TSTZ-M 储存区 v1：用户手动扫过的代币 / 钱包（含叙事）存进 D1，供分析用。
// 原则：写入前独立二次核对（App 自带值 + 手机直连币安 + 服务器直连 Dexscreener 全池汇总），多源一致才标 verified，
// 对不上的字段不写数、只记录各源原值；叙事没有项目官方描述时只标 name_only，不当事实用。原始快照整份保留（JSON），可用 json_extract 再算。
export function makeStore(h) {
  const now = h.now;
  const DEXID = { solana: 'solana', eth: 'ethereum', bsc: 'bsc', base: 'base', arbitrum: 'arbitrum', optimism: 'optimism', polygon: 'polygon', robinhood: 'robinhood', okc: 'okc', xlayer: 'xlayer' };
  const okAddr = (chain, a) => (chain === 'solana' ? /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(a || '') : DEXID[chain] ? /^0x[0-9a-fA-F]{40}$/.test(a || '') : false);
  const num = (v) => { if (v == null || v === '') return null; const n = Number(v); return Number.isFinite(n) ? n : null; };
  const int = (v) => { const n = num(v); return n == null ? null : Math.round(n); };
  const keyAddr = (chain, a) => (chain === 'solana' ? a : String(a).toLowerCase());

  const SCHEMA = [
    `CREATE TABLE IF NOT EXISTS st_token (chain TEXT NOT NULL, addr TEXT NOT NULL, sym TEXT, name TEXT, first_at INTEGER, last_at INTEGER, scans INTEGER DEFAULT 0,
      price REAL, mcap REAL, fdv REAL, liq REAL, vol24 REAL, chg24 REAL, holders INTEGER, top10 REAL, pools INTEGER, buys24 INTEGER, sells24 INTEGER, created_ms INTEGER, dex TEXT, pair TEXT,
      dev_pct REAL, bundler_pct REAL, insider_pct REAL, newwallet_pct REAL, smart_n INTEGER, kol_n INTEGER, pro_n INTEGER,
      buy_tax REAL, sell_tax REAL, honeypot INTEGER, risk TEXT,
      q_price TEXT, q_mcap TEXT, q_fdv TEXT, q_liq TEXT, q_vol24 TEXT, q_chg24 TEXT, q_holders TEXT, q_top10 TEXT,
      theme TEXT, narr_status TEXT, narr TEXT, info TEXT, quality TEXT, snap TEXT,
      first_price REAL, first_mcap REAL, peak_price REAL, peak_mcap REAL, PRIMARY KEY (chain, addr))`,
    `CREATE TABLE IF NOT EXISTS st_token_hist (id INTEGER PRIMARY KEY AUTOINCREMENT, chain TEXT, addr TEXT, at INTEGER, price REAL, mcap REAL, liq REAL, vol24 REAL, chg24 REAL, holders INTEGER, top10 REAL, pools INTEGER, buys24 INTEGER, sells24 INTEGER, quality TEXT)`,
    `CREATE INDEX IF NOT EXISTS st_token_hist_k ON st_token_hist (chain, addr, at)`,
    `CREATE TABLE IF NOT EXISTS st_wallet (chain TEXT NOT NULL, addr TEXT NOT NULL, kind TEXT, first_at INTEGER, last_at INTEGER, scans INTEGER DEFAULT 0, src_token TEXT, tags TEXT,
      trades INTEGER, tokens_traded INTEGER, realized REAL, realized_unit TEXT, win_rate REAL, wins INTEGER, realized_n INTEGER, med_hold_sec REAL, span_days REAL, q TEXT, quality TEXT, snap TEXT, PRIMARY KEY (chain, addr))`,
    `CREATE TABLE IF NOT EXISTS st_wallet_hist (id INTEGER PRIMARY KEY AUTOINCREMENT, chain TEXT, addr TEXT, at INTEGER, trades INTEGER, realized REAL, win_rate REAL, q TEXT)`,
    `CREATE TABLE IF NOT EXISTS st_edge (chain TEXT NOT NULL, wallet TEXT NOT NULL, token TEXT NOT NULL, rank INTEGER, pct REAL, kind TEXT, at INTEGER, PRIMARY KEY (chain, wallet, token))`,
    `CREATE INDEX IF NOT EXISTS st_edge_t ON st_edge (chain, token)`,
  ];
  let ready = false;
  async function init(env) {
    if (ready) return;
    await env.DB.batch(SCHEMA.map((s) => env.DB.prepare(s)));
    ready = true;
  }

  async function ft(url, ms = 9000) {
    const ac = new AbortController();
    const t = setTimeout(() => ac.abort(), ms);
    try {
      const r = await fetch(url, { headers: { accept: 'application/json', 'user-agent': 'Mozilla/5.0' }, signal: ac.signal });
      if (!r.ok) return null;
      return await r.json();
    } catch (_) { return null; } finally { clearTimeout(t); }
  }

  // 服务器端独立来源：Dexscreener 全池（token-pairs 返回最多 30 个池；tokens/v1 现在只回 1 个池，不能用）
  async function dexAgg(chain, addr) {
    const cid = DEXID[chain];
    if (!cid) return null;
    let arr = await ft('https://api.dexscreener.com/token-pairs/v1/' + cid + '/' + addr);
    if (!Array.isArray(arr)) {
      const l = await ft('https://api.dexscreener.com/latest/dex/tokens/' + addr);
      arr = l && Array.isArray(l.pairs) ? l.pairs.filter((p) => p.chainId === cid) : null;
    }
    if (!arr || !arr.length) return null;
    const low = String(addr).toLowerCase();
    const mine = arr.filter((p) => String((p.baseToken && p.baseToken.address) || '').toLowerCase() === low);
    if (!mine.length) return { mismatch: true };
    mine.sort((a, b) => (num(b.liquidity && b.liquidity.usd) || 0) - (num(a.liquidity && a.liquidity.usd) || 0));
    const best = mine[0];
    const sum = (f) => mine.reduce((a, p) => a + (num(f(p)) || 0), 0);
    const created = mine.map((p) => num(p.pairCreatedAt)).filter((x) => x != null);
    return {
      pools: mine.length, truncated: arr.length >= 30, price: num(best.priceUsd), mcap: num(best.marketCap), fdv: num(best.fdv),
      liq: sum((p) => p.liquidity && p.liquidity.usd), vol24: sum((p) => p.volume && p.volume.h24),
      buys24: Math.round(sum((p) => p.txns && p.txns.h24 && p.txns.h24.buys)), sells24: Math.round(sum((p) => p.txns && p.txns.h24 && p.txns.h24.sells)),
      chg24: num(best.priceChange && best.priceChange.h24), dex: best.dexId || null, pair: best.pairAddress || null,
      created: created.length ? Math.min(...created) : null, sym: (best.baseToken && best.baseToken.symbol) || null, name: (best.baseToken && best.baseToken.name) || null,
    };
  }

  // 手机直连币安 Web3 公共接口取到的原始 data（服务器出口被币安 403，只能手机取）
  function binNorm(b) {
    if (!b || typeof b !== 'object') return null;
    return {
      price: num(b.price), mcap: num(b.marketCap), fdv: num(b.fdv), liq: num(b.liquidity), vol24: num(b.volume24h), chg24: num(b.percentChange24h),
      holders: int(b.holders), top10: num(b.top10HoldersPercentage), dev: num(b.devHoldingPercent), bundler: num(b.bundlerHoldingPercent), insider: num(b.insiderHoldingPercent),
      newWallet: num(b.newWalletHoldingPercent), smartN: int(b.smartMoneyHolders), kolN: int(b.kolHolders), proN: int(b.proHolders), launch: num(b.launchTime),
    };
  }

  const close = (a, b, tol, abs) => (abs != null ? Math.abs(a - b) <= abs : (() => { const m = Math.max(Math.abs(a), Math.abs(b)); return m === 0 || Math.abs(a - b) / m <= tol; })());
  // 多源共识：最大一致组 ≥2 个源 → verified；只有 1 个源 → single；彼此对不上 → conflict（不写数，只记各源原值）
  function consensus(vals, tol, abs) {
    const a = vals.filter((x) => x.v != null && Number.isFinite(x.v));
    if (!a.length) return { v: null, st: 'none' };
    if (a.length === 1) return { v: a[0].v, st: 'single', src: a[0].src };
    let best = [];
    for (const x of a) { const g = a.filter((y) => close(x.v, y.v, tol, abs)); if (g.length > best.length) best = g; }
    if (best.length >= 2) {
      const pick = best.find((x) => x.src === 'bin') || best.find((x) => x.src === 'dex') || best[0];
      const out = a.filter((x) => !best.includes(x)).map((x) => x.src + '=' + x.v);
      return { v: pick.v, st: 'verified', src: best.map((x) => x.src).join('+'), outliers: out.length ? out : undefined };
    }
    return { v: null, st: 'conflict', alts: Object.fromEntries(a.map((x) => [x.src, x.v])) };
  }

  const sumBy = (arr, f) => (Array.isArray(arr) ? arr.reduce((a, p) => a + (num(f(p)) || 0), 0) : null);
  function appFacts(snap) {
    const pairs = Array.isArray(snap && snap.pairs) ? snap.pairs : [];
    const sec = (snap && snap.security) || {};
    const main = pairs[0] || {};
    return {
      price: num(main.priceUsd), mcap: num(main.marketCap), fdv: num(main.fdv),
      liq: pairs.length ? sumBy(pairs, (p) => p.liquidity && p.liquidity.usd) : null, vol24: pairs.length ? sumBy(pairs, (p) => p.volume && p.volume.h24) : null,
      chg24: num(main.priceChange && main.priceChange.h24), holders: int(sec.holders != null ? sec.holders : sec.realHolders), top10: num(sec.topHoldersPct),
      pools: pairs.length, sym: (main.baseToken && main.baseToken.symbol) || null, name: (main.baseToken && main.baseToken.name) || null,
    };
  }

  function buildFacts(app, bin, dex) {
    const f = {}, q = {};
    const put = (k, vals, tol, abs) => { const c = consensus(vals, tol, abs); f[k] = c.v; q[k] = { st: c.st, src: c.src, outliers: c.outliers, alts: c.alts }; };
    put('price', [{ src: 'app', v: app.price }, { src: 'bin', v: bin && bin.price }, { src: 'dex', v: dex && dex.price }], 0.05);
    put('mcap', [{ src: 'app', v: app.mcap }, { src: 'bin', v: bin && bin.mcap }, { src: 'dex', v: dex && dex.mcap }], 0.12);
    put('fdv', [{ src: 'app', v: app.fdv }, { src: 'bin', v: bin && bin.fdv }, { src: 'dex', v: dex && dex.fdv }], 0.12);
    put('liq', [{ src: 'app', v: app.liq }, { src: 'bin', v: bin && bin.liq }, { src: 'dex', v: dex && dex.liq }], 0.5);
    put('vol24', [{ src: 'app', v: app.vol24 }, { src: 'bin', v: bin && bin.vol24 }, { src: 'dex', v: dex && dex.vol24 }], 0.5);
    put('chg24', [{ src: 'app', v: app.chg24 }, { src: 'bin', v: bin && bin.chg24 }, { src: 'dex', v: dex && dex.chg24 }], null, 3);
    put('holders', [{ src: 'app', v: app.holders }, { src: 'bin', v: bin && bin.holders }], 0.25);
    put('top10', [{ src: 'app', v: app.top10 }, { src: 'bin', v: bin && bin.top10 }], null, 4);
    return { f, q };
  }

  function narrOf(narr, info) {
    const themes = narr && Array.isArray(narr.themes) ? narr.themes.map(String).slice(0, 6) : [];
    const desc = info && typeof info.desc === 'string' ? info.desc.trim() : '';
    const bio = info && info.xProfile && typeof info.xProfile.bio === 'string' ? info.xProfile.bio.trim() : '';
    const evidence = { descSrc: (info && info.descSrc) || null, desc: desc ? desc.slice(0, 500) : null, xBio: bio ? bio.slice(0, 300) : null, x: (info && info.x) || null, tg: (info && info.tg) || null, web: (info && info.web) || null };
    let status = 'none';
    if (themes.length) status = desc || bio ? 'evidenced' : 'name_only';
    return { status, theme: themes[0] || null, narr: narr ? { themes, keywords: narr.keywords || [], summary: narr.summary || null, level: narr.level || null, levelBasis: narr.levelBasis || null, position: narr.position || null, heat: narr.heat || null, heatBasis: narr.heatBasis || null, similar: Array.isArray(narr.similar) ? narr.similar.slice(0, 12) : [], notes: narr.notes || [], evidence } : null, evidence };
  }

  const j = (o) => JSON.stringify(o, (k, v) => (v === undefined ? undefined : v));
  function trimSnap(snap, max) {
    let s = j(snap);
    if (s.length <= max) return s;
    const c = { ...snap }; delete c.trades; s = j(c);
    if (s.length <= max) return s;
    delete c.analyses; s = j(c);
    return s.length <= max ? s : j({ truncated: true, address: snap.address, chain: snap.chain });
  }

  async function storeToken(env, b) {
    const chain = String((b && b.chain) || '').toLowerCase();
    const addr = String((b && b.address) || '').trim();
    if (!okAddr(chain, addr)) return { stored: false, reason: 'bad_chain_or_address' };
    const snap = b.snap && typeof b.snap === 'object' ? b.snap : {};
    const app = appFacts(snap);
    const bin = binNorm(b.bin);
    const dex = await dexAgg(chain, addr);
    if (dex && dex.mismatch) return { stored: false, reason: 'address_not_base_token_on_chain' };
    if (!dex && !bin && !app.price) return { stored: false, reason: 'no_market_data' };
    const { f, q } = buildFacts(app, bin, dex);
    if (f.price == null && q.price.st === 'none') return { stored: false, reason: 'no_price' };
    const nar = narrOf(b.narr, b.info);
    const t = now();
    const ak = keyAddr(chain, addr);
    const old = await env.DB.prepare('SELECT first_at, scans, first_price, first_mcap, peak_price, peak_mcap, last_at, mcap FROM st_token WHERE chain=? AND addr=?').bind(chain, ak).first();
    const sym = app.sym || (dex && dex.sym) || null, name = app.name || (dex && dex.name) || null;
    const info = b.info && typeof b.info === 'object' ? { desc: nar.evidence.desc, descSrc: nar.evidence.descSrc, x: nar.evidence.x, tg: nar.evidence.tg, web: nar.evidence.web, created: b.info.created || null, xProfile: b.info.xProfile || null, tweets: Array.isArray(b.info.tweets) ? b.info.tweets.slice(0, 6) : [], tgPosts: Array.isArray(b.info.tgPosts) ? b.info.tgPosts.slice(0, 5) : [] } : null;
    const sec = snap.security || {};
    const created = (dex && dex.created) || (bin && bin.launch) || (snap.pairs && snap.pairs[0] && num(snap.pairs[0].pairCreatedAt)) || null;
    const quality = { q, sources: { app: true, bin: !!bin, dex: !!dex }, dexPools: dex ? dex.pools : null, dexTruncated: dex ? dex.truncated : null, appPools: app.pools };
    const row = [
      chain, ak, sym, name, old ? old.first_at : t, t, (old ? old.scans : 0) + 1,
      f.price, f.mcap, f.fdv, f.liq, f.vol24, f.chg24, f.holders, f.top10, dex ? dex.pools : app.pools, dex ? int(dex.buys24) : null, dex ? int(dex.sells24) : null, created, (dex && dex.dex) || null, (dex && dex.pair) || null,
      bin ? bin.dev : null, bin ? bin.bundler : null, bin ? bin.insider : null, bin ? bin.newWallet : null, bin ? bin.smartN : null, bin ? bin.kolN : null, bin ? bin.proN : null,
      num(sec.buyTax), num(sec.sellTax), sec.honeypot === true ? 1 : sec.honeypot === false ? 0 : null, sec.risk || null,
      q.price.st, q.mcap.st, q.fdv.st, q.liq.st, q.vol24.st, q.chg24.st, q.holders.st, q.top10.st,
      nar.theme, nar.status, nar.narr ? j(nar.narr) : null, info ? j(info) : null, j(quality), trimSnap(snap, 1400000),
      old && old.first_price != null ? old.first_price : f.price, old && old.first_mcap != null ? old.first_mcap : f.mcap,
      Math.max(old && old.peak_price != null ? old.peak_price : 0, f.price || 0) || null, Math.max(old && old.peak_mcap != null ? old.peak_mcap : 0, f.mcap || 0) || null,
    ];
    const cols = 'chain,addr,sym,name,first_at,last_at,scans,price,mcap,fdv,liq,vol24,chg24,holders,top10,pools,buys24,sells24,created_ms,dex,pair,dev_pct,bundler_pct,insider_pct,newwallet_pct,smart_n,kol_n,pro_n,buy_tax,sell_tax,honeypot,risk,q_price,q_mcap,q_fdv,q_liq,q_vol24,q_chg24,q_holders,q_top10,theme,narr_status,narr,info,quality,snap,first_price,first_mcap,peak_price,peak_mcap';
    const stmts = [env.DB.prepare('INSERT OR REPLACE INTO st_token (' + cols + ') VALUES (' + row.map(() => '?').join(',') + ')').bind(...row)];
    const histDue = !old || t - (old.last_at || 0) >= 10 * 60000 || (old.mcap && f.mcap && Math.abs(f.mcap - old.mcap) / old.mcap >= 0.03);
    if (histDue) {
      stmts.push(env.DB.prepare('INSERT INTO st_token_hist (chain,addr,at,price,mcap,liq,vol24,chg24,holders,top10,pools,buys24,sells24,quality) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)')
        .bind(chain, ak, t, f.price, f.mcap, f.liq, f.vol24, f.chg24, f.holders, f.top10, row[15], row[16], row[17], j(Object.fromEntries(Object.entries(q).map(([k, v]) => [k, v.st])))));
      stmts.push(env.DB.prepare('DELETE FROM st_token_hist WHERE chain=? AND addr=? AND id NOT IN (SELECT id FROM st_token_hist WHERE chain=? AND addr=? ORDER BY id DESC LIMIT 500)').bind(chain, ak, chain, ak));
    }
    const hs = Array.isArray(snap.holders) ? snap.holders.filter((x) => x && x.kind === 'wallet' && x.owner).slice(0, 30) : [];
    for (const x of hs) stmts.push(env.DB.prepare('INSERT OR REPLACE INTO st_edge (chain,wallet,token,rank,pct,kind,at) VALUES (?,?,?,?,?,?,?)').bind(chain, keyAddr(chain, x.owner), ak, int(x.rank), num(x.pct), x.kind, t));
    await env.DB.batch(stmts);
    const bad = Object.entries(q).filter(([, v]) => v.st === 'conflict').map(([k]) => k);
    return { stored: true, chain, address: addr, sym, scans: row[6], facts: f, quality: Object.fromEntries(Object.entries(q).map(([k, v]) => [k, v.st])), conflicts: bad, narr: nar.status, theme: nar.theme, edges: hs.length };
  }

  const pickStats = (s) => {
    s = s || {};
    let wr = num(s.winRate);
    if (wr != null && wr > 1 && wr <= 100) wr /= 100;
    if (wr != null && (wr < 0 || wr > 1)) wr = null;
    let wins = int(s.winN), rn = int(s.realizedN);
    if (wins != null && rn != null && wins > rn) { wins = null; rn = null; wr = null; }
    const realized = num(s.realizedSol != null ? s.realizedSol : s.realizedUsd != null ? s.realizedUsd : s.realized);
    return {
      trades: int(s.tradeN != null ? s.tradeN : s.swapTx), tokens: int(s.tokensTraded), realized: realized != null && Math.abs(realized) < 1e9 ? realized : null,
      unit: s.realizedSol != null ? 'SOL' : s.realizedUsd != null ? 'USD' : s.realized != null ? 'unknown' : null, wr, wins, rn, hold: num(s.medHoldSec), span: num(s.spanDays),
    };
  };

  async function storeWallet(env, b) {
    const chain = String((b && b.chain) || '').toLowerCase();
    const addr = String((b && b.address) || '').trim();
    if (!okAddr(chain, addr)) return { stored: false, reason: 'bad_chain_or_address' };
    const snap = b.snap && typeof b.snap === 'object' ? b.snap : null;
    if (!snap || snap.error) return { stored: false, reason: snap && snap.error ? 'upstream_error:' + snap.error : 'empty_snapshot' };
    const st = pickStats(snap.stats || snap.summary || snap);
    const tags = Array.isArray(snap.tags) ? snap.tags.map((x) => (x && x.tag) || x).filter((x) => typeof x === 'string').slice(0, 12) : [];
    const hasNumbers = st.trades != null || st.realized != null || st.wr != null || tags.length;
    if (!hasNumbers) return { stored: false, reason: 'no_recognized_fields' };
    const t = now();
    const ak = keyAddr(chain, addr);
    const old = await env.DB.prepare('SELECT first_at, scans FROM st_wallet WHERE chain=? AND addr=?').bind(chain, ak).first();
    const quality = { q: 'structural', note: '引擎按链上原始记录现算，仅做结构与合理性校验（胜率 0-1、胜场≤已平仓数、金额有限）', sane: { winRate: st.wr != null, counts: st.trades != null } };
    const stmts = [
      env.DB.prepare('INSERT OR REPLACE INTO st_wallet (chain,addr,kind,first_at,last_at,scans,src_token,tags,trades,tokens_traded,realized,realized_unit,win_rate,wins,realized_n,med_hold_sec,span_days,q,quality,snap) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)')
        .bind(chain, ak, String(b.kind || ''), old ? old.first_at : t, t, (old ? old.scans : 0) + 1, b.srcToken ? String(b.srcToken).slice(0, 64) : null, tags.join(','), st.trades, st.tokens, st.realized, st.unit, st.wr, st.wins, st.rn, st.hold, st.span, 'structural', j(quality), trimSnap(snap, 1400000)),
      env.DB.prepare('INSERT INTO st_wallet_hist (chain,addr,at,trades,realized,win_rate,q) VALUES (?,?,?,?,?,?,?)').bind(chain, ak, t, st.trades, st.realized, st.wr, 'structural'),
      env.DB.prepare('DELETE FROM st_wallet_hist WHERE chain=? AND addr=? AND id NOT IN (SELECT id FROM st_wallet_hist WHERE chain=? AND addr=? ORDER BY id DESC LIMIT 200)').bind(chain, ak, chain, ak),
    ];
    await env.DB.batch(stmts);
    return { stored: true, chain, address: addr, scans: (old ? old.scans : 0) + 1, tags, stats: st };
  }

  async function stats(env) {
    const one = async (sql) => (await env.DB.prepare(sql).first()) || {};
    const [a, b, c, d, e] = await Promise.all([
      one('SELECT COUNT(*) n, SUM(scans) scans, MAX(last_at) lastAt FROM st_token'), one('SELECT COUNT(*) n, SUM(scans) scans FROM st_wallet'), one('SELECT COUNT(*) n FROM st_token_hist'), one('SELECT COUNT(*) n FROM st_edge'),
      env.DB.prepare('SELECT q_liq st, COUNT(*) n FROM st_token GROUP BY q_liq').all(),
    ]);
    return { tokens: a, wallets: b, hist: c.n, edges: d.n, liqQuality: e.results || [] };
  }

  async function route(env, p, q, req) {
    if (!p.startsWith('/e/store/')) return undefined;
    await init(env);
    if (p === '/e/store/token' && req.method === 'POST') return storeToken(env, await req.json());
    if (p === '/e/store/wallet' && req.method === 'POST') return storeWallet(env, await req.json());
    if (p === '/e/store/stats') return stats(env);
    return { error: 'not_found', path: p };
  }
  return { route, init, consensus, appFacts, buildFacts, binNorm, narrOf, pickStats, storeToken, storeWallet };
}
