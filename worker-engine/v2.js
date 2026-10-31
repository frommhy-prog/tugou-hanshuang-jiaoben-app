// TSTZ-M 引擎 v2 模块：持有人分析（USD 折算、入场时点、盈亏、抛压）、交易所持仓（只读）、AI（多模型回退+缓存）、MCP 服务
export function makeV2(h) {
  const { vGet, jget, sleep, now, r4, ledger, history, extractTrades, summarize, EVMX, solWallet, solToken, solPool, cached } = h;
  const enc = new TextEncoder();
  const DEXID = { solana: 'solana', bsc: 'bsc', eth: 'ethereum', base: 'base', arbitrum: 'arbitrum', optimism: 'optimism', polygon: 'polygon' };
  const NATSYM = { solana: 'SOLUSDT', bsc: 'BNBUSDT', eth: 'ETHUSDT', base: 'ETHUSDT', arbitrum: 'ETHUSDT', optimism: 'ETHUSDT', polygon: 'POLUSDT' };
  const CHAINS = Object.keys(DEXID);
  const okAddr = (chain, a) => (chain === 'solana' ? /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(a || '') : /^0x[0-9a-fA-F]{40}$/.test(a || ''));
  const bad = (code, detail) => ({ error: code, detail });

  async function cget(env, key, ttlMs) {
    const c = await env.DB.prepare('SELECT v, at FROM cache WHERE k=?').bind(key).first();
    if (c && now() - c.at < ttlMs) { try { return JSON.parse(c.v); } catch (_) {} }
    return null;
  }
  async function cput(env, key, v) { await env.DB.prepare('INSERT OR REPLACE INTO cache (k,v,at) VALUES (?,?,?)').bind(key, JSON.stringify(v), now()).run(); }

  // ---------- 原生币历史价格（Binance 公共行情，小时开盘价线性插值）----------
  async function series(env, sym, from, to) {
    const start = Math.floor(from / 3600) * 3600 - 3600, end = to + 3600;
    const key = 'kl2:' + sym + ':' + Math.floor(start / 3600) + ':' + Math.floor(end / 3600);
    const c = await cget(env, key, 1800e3); if (c) return c;
    const out = []; let cur = start * 1000;
    for (let i = 0; i < 3 && cur < end * 1000; i++) {
      const j = await jget('https://data-api.binance.vision/api/v3/klines?symbol=' + sym + '&interval=1h&startTime=' + cur + '&limit=1000', { headers: { accept: 'application/json' } });
      if (!Array.isArray(j) || !j.length) break;
      for (const k of j) out.push([Math.floor(k[0] / 1000), Number(k[1])]);
      cur = j[j.length - 1][0] + 3600000;
      if (j.length < 1000) break;
    }
    if (out.length) await cput(env, key, out);
    return out;
  }
  function priceAt(s, t) {
    if (!s || !s.length) return null;
    if (t <= s[0][0]) return s[0][1];
    let lo = 0, hi = s.length - 1;
    if (t >= s[hi][0]) return s[hi][1];
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (s[mid][0] <= t) lo = mid; else hi = mid; }
    const f = (t - s[lo][0]) / Math.max(1, s[hi][0] - s[lo][0]);
    return s[lo][1] + (s[hi][1] - s[lo][1]) * f;
  }

  // ---------- 代币行情（Dexscreener，带缓存；失败返回空对象，不编数）----------
  async function market(env, chain, token) {
    const key = 'm2:' + chain + ':' + token.toLowerCase();
    const c = await cget(env, key, 60e3); if (c) return c;
    let best = null;
    try {
      const arr = await jget('https://api.dexscreener.com/tokens/v1/' + DEXID[chain] + '/' + token, { headers: { accept: 'application/json' } });
      for (const p of Array.isArray(arr) ? arr : []) {
        if (!p.baseToken || String(p.baseToken.address).toLowerCase() !== token.toLowerCase()) continue;
        const liq = (p.liquidity && p.liquidity.usd) || 0;
        if (!best || liq > best.liq) best = { sym: p.baseToken.symbol, name: p.baseToken.name, liq, priceUsd: Number(p.priceUsd) || null, pair: p.pairAddress, createdAt: p.pairCreatedAt || null, vol24: p.volume ? p.volume.h24 : null, mc: p.marketCap || p.fdv || null, dex: p.dexId };
      }
    } catch (_) { best = null; }
    if (best) await cput(env, key, best);
    return best || {};
  }

  const usd = (v) => (v == null || !Number.isFinite(v) ? '未知' : (v < 0 ? '-' : '') + '$' + (Math.abs(v) >= 100 ? Math.round(Math.abs(v)).toLocaleString('en-US') : Math.abs(v) >= 1 ? Math.abs(v).toFixed(2) : Math.abs(v).toPrecision(3)));
  const pctS = (v) => (v == null || !Number.isFinite(v) ? '未知' : (v >= 0 ? '+' : '') + (v * 100).toFixed(0) + '%');

  // ---------- 持有人分析：成本、盈亏、入场时点、抛压（金额统一折算为美元，口径写明）----------
  async function holder(env, chain, token, owner, pages) {
    const sol = chain === 'solana';
    let trades = [], stats = null, tags = [], notes = [], sample = null, native = sol ? 'SOL' : null, truncated = false;
    if (sol) {
      const hh = await history(env, owner, pages, 'SWAP');
      const ex = extractTrades(hh.txs, owner);
      const sum = summarize(ex.trades, ledger(ex.trades), hh, ex.multi, ex.fees);
      trades = ex.trades.filter((t) => t.mint === token).map((t) => ({ t: t.t, side: t.side, qty: t.qty, amt: t.amt, q: t.q === 'SOL' ? 'NATIVE' : 'USD', tx: t.sig, approx: false }));
      stats = sum.stats; tags = sum.tags; notes = sum.notes; sample = sum.sample;
    } else {
      const r = await EVMX.opHolder(env, chain, token, owner, pages);
      native = r.native;
      trades = (r.tradesThis || []).map((t) => ({ t: t.t, side: t.side, qty: t.qty, amt: t.amt, q: t.q, tx: t.tx, approx: !!t.approx }));
      truncated = trades.length >= 40;
      stats = r.stats; tags = r.tags; notes = r.notes; sample = r.sample;
    }
    const mk = await market(env, chain, token);
    trades.sort((a, b) => a.t - b.t);
    const out = { chain, token, owner, native, market: { sym: mk.sym || null, priceUsd: mk.priceUsd || null, liq: mk.liq || null, createdAt: mk.createdAt || null }, stats, tags, notes: [...(notes || [])], sample, truncated, at: now() };
    if (!trades.length) {
      out.position = null;
      out.insights = [{ level: 'info', text: '窗口内没有这个钱包在该币上的买卖记录', basis: '可能是更早买入、转账获得或空投，成本无法确认；不据此下结论' }];
      out.trades = [];
      return out;
    }
    let ser = null, serErr = null;
    if (trades.some((t) => t.q === 'NATIVE')) {
      try { ser = await series(env, NATSYM[chain], trades[0].t, trades[trades.length - 1].t); } catch (e) { serErr = String((e && e.message) || e).slice(0, 80); }
    }
    const tr = trades.map((t) => ({ ...t, usd: t.q === 'USD' ? t.amt : ser && ser.length ? (priceAt(ser, t.t) || 0) * t.amt || null : null }));
    const full = tr.every((t) => t.usd != null);
    out.usdBasis = ser && ser.length ? 'SOL/BNB/ETH 计价的成交按成交时刻的 Binance 小时开盘价线性插值折算为美元（近似）；稳定币计价直接取面值' : null;
    if (!full) out.notes.push('部分成交无法折算为美元（' + (serErr || '价格源不可用') + '），盈亏未汇总');
    out.trades = tr.slice(-40).reverse().map((t) => ({ tx: t.tx, t: t.t, side: t.side, qty: t.qty, amt: r4(t.amt), q: t.q, usd: t.usd != null ? r4(t.usd) : null, approx: t.approx }));
    const insights = [];
    if (full) {
      const pos = Object.values(ledger(tr.map((t) => ({ sig: t.tx, t: t.t, mint: token, side: t.side, qty: t.qty, amt: t.usd, q: 'USD' }))))[0];
      const price = mk.priceUsd, qtyHeld = pos.qty > 1e-9 ? pos.qty : 0;
      const value = price != null ? qtyHeld * price : null, unreal = value != null ? value - (qtyHeld > 0 ? pos.cost : 0) : null;
      const spent = pos.boughtAmt, realized = pos.realized;
      const roi = spent > 0 && unreal != null ? (realized + unreal) / spent : null;
      const avgBuy = pos.bought > 0 ? pos.boughtAmt / pos.bought : null, avgSell = pos.sold > 0 ? pos.soldAmt / pos.sold : null;
      const soldPct = pos.bought > 0 ? pos.sold / pos.bought : null;
      const launch = mk.createdAt ? mk.createdAt / 1000 : null;
      const delayMin = launch && pos.firstBuy ? (pos.firstBuy - launch) / 60 : null;
      const entry = delayMin == null ? null : delayMin < 0 ? '池子创建前就已持有' : delayMin <= 1 ? '狙击（池子创建 1 分钟内买入）' : delayMin <= 10 ? '早期买家（10 分钟内）' : delayMin <= 60 ? '上线首小时买家' : '后来者（上线 1 小时后）';
      const state = qtyHeld <= 0 ? '已清仓' : soldPct != null && soldPct >= 0.05 ? '已减仓 ' + (soldPct * 100).toFixed(0) + '%' : '持仓中（基本未卖）';
      out.position = { boughtUsd: r4(spent), soldUsd: r4(pos.soldAmt), realizedUsd: r4(realized), qtyHeld, costHeldUsd: r4(qtyHeld > 0 ? pos.cost : 0), valueNowUsd: value != null ? r4(value) : null, unrealizedUsd: unreal != null ? r4(unreal) : null, roi: roi != null ? r4(roi) : null, avgBuyUsd: avgBuy, avgSellUsd: avgSell, priceNowUsd: price, soldPct: soldPct != null ? r4(soldPct) : null, firstBuy: pos.firstBuy, lastSell: pos.lastSell, buys: pos.buys, sells: pos.sells, delayMin: delayMin != null ? r4(delayMin) : null, entry, state, uncovQty: pos.uncovQty > 1e-9 ? pos.uncovQty : 0 };
      if (entry) insights.push({ level: delayMin <= 10 && delayMin >= 0 ? 'warn' : 'info', text: '入场：' + entry, basis: '首次买入距池子创建 ' + (delayMin < 0 ? '为负（买入早于最深池子创建）' : delayMin.toFixed(1) + ' 分钟') });
      if (avgBuy != null && price != null && avgBuy > 0) {
        const gain = price / avgBuy - 1;
        insights.push({ level: gain >= 1 ? 'warn' : gain <= -0.5 ? 'info' : 'info', text: gain >= 0 ? '成本低于现价：平均买入价 ' + usd(avgBuy) + '，现价 ' + usd(price) + '，账面浮盈 ' + pctS(gain) + '，兑现动力强' : '成本高于现价：平均买入价 ' + usd(avgBuy) + '，现价 ' + usd(price) + '，账面浮亏 ' + pctS(gain) + '，倾向持有或止损', basis: '按美元成本的平均成本法；现价取 Dexscreener 最深池子' });
      }
      if (value != null && qtyHeld > 0 && mk.liq > 0) {
        const imp = value / mk.liq;
        insights.push({ level: imp >= 0.2 ? 'risk' : imp >= 0.05 ? 'warn' : 'ok', text: '抛压：持仓价值 ' + usd(value) + '，相当于最深池子流动性（' + usd(mk.liq) + '）的 ' + (imp * 100).toFixed(1) + '%', basis: '持仓数量 × 现价 ÷ 池子流动性；全部卖出的价格冲击会比这更大' });
      }
      insights.push({ level: 'info', text: '累计投入 ' + usd(spent) + '，已兑现 ' + usd(realized) + (unreal != null ? '，浮动 ' + usd(unreal) : '') + (roi != null ? '，综合回报 ' + pctS(roi) : ''), basis: '共 ' + pos.buys + ' 笔买入、' + pos.sells + ' 笔卖出；状态：' + state });
      if (pos.uncovQty > 1e-9) insights.push({ level: 'info', text: '有一部分卖出找不到对应买入（窗口之前买入或转入），那部分不计盈亏', basis: '平均成本法只对已记录的买入计成本' });
    } else {
      out.position = null;
      insights.push({ level: 'info', text: '成交金额无法统一折算为美元，只给出原始成交列表', basis: serErr || '价格源不可用' });
    }
    if (truncated) out.notes.push('该币买卖记录超过 40 笔，只取最近 40 笔，成本可能不完整');
    out.insights = insights;
    return out;
  }

  // ---------- 交易所持仓（只读：仅查询余额，不下单、不提现）----------
  const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
  async function hmac(alg, secret, msg, b64) {
    const k = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: alg }, false, ['sign']);
    const s = new Uint8Array(await crypto.subtle.sign('HMAC', k, enc.encode(msg)));
    return b64 ? btoa(String.fromCharCode(...s)) : hex(s);
  }
  const STABLE = new Set(['USDT', 'USDC', 'FDUSD', 'BUSD', 'TUSD', 'USD1', 'DAI', 'USDE', 'USDD', 'PYUSD']);
  async function ex(url, init) {
    const r = await fetch(url, init);
    const t = await r.text();
    if (!r.ok) { const e = new Error('http_' + r.status); e.detail = t.slice(0, 220); throw e; }
    return JSON.parse(t);
  }
  const fin = (ex2, assets, accounts) => {
    const total = assets.reduce((s, a) => s + (a.usd || 0), 0);
    const unpriced = assets.filter((a) => a.usd == null).length;
    assets.sort((a, b) => (b.usd || 0) - (a.usd || 0));
    return { ex: ex2, totalUsd: r4(total), unpriced, accounts, assets: assets.slice(0, 80).map((a) => ({ sym: a.sym, amount: a.amount, usd: a.usd != null ? r4(a.usd) : null, acct: a.acct })), at: now() };
  };
  async function binance(env) {
    const key = await vGet(env, 'binance_key'), sec = await vGet(env, 'binance_secret');
    if (!key || !sec) return bad('no_key', '未绑定币安 API 密钥');
    const q = 'timestamp=' + Date.now() + '&recvWindow=20000';
    const acc = await ex('https://api.binance.com/api/v3/account?' + q + '&signature=' + (await hmac('SHA-256', sec, q)), { headers: { 'X-MBX-APIKEY': key } });
    const px = {};
    for (const t of await ex('https://api.binance.com/api/v3/ticker/price')) px[t.symbol] = Number(t.price);
    const price = (s) => (STABLE.has(s) ? 1 : px[s + 'USDT'] != null ? px[s + 'USDT'] : px[s + 'BUSD'] != null ? px[s + 'BUSD'] : px[s + 'BTC'] != null && px.BTCUSDT ? px[s + 'BTC'] * px.BTCUSDT : null);
    const assets = [];
    for (const b of acc.balances || []) {
      const amt = Number(b.free) + Number(b.locked); if (!(amt > 0)) continue;
      const base = /^LD[A-Z0-9]+$/.test(b.asset) && b.asset !== 'LDO' ? b.asset.slice(2) : b.asset;
      const p = price(base);
      assets.push({ sym: b.asset, amount: amt, usd: p != null ? amt * p : null, acct: '现货' });
    }
    const accounts = { 现货: r4(assets.reduce((s, a) => s + (a.usd || 0), 0)) };
    try {
      const q2 = 'timestamp=' + Date.now() + '&recvWindow=20000';
      const fd = await ex('https://api.binance.com/sapi/v1/asset/get-funding-asset?' + q2 + '&signature=' + (await hmac('SHA-256', sec, q2)), { method: 'POST', headers: { 'X-MBX-APIKEY': key } });
      let s = 0;
      for (const b of fd || []) { const amt = Number(b.free) + Number(b.locked) + Number(b.freeze || 0); if (!(amt > 0)) continue; const p = price(b.asset); assets.push({ sym: b.asset, amount: amt, usd: p != null ? amt * p : null, acct: '资金' }); s += p != null ? amt * p : 0; }
      accounts['资金'] = r4(s);
    } catch (_) {}
    return fin('binance', assets, accounts);
  }
  async function okx(env) {
    const key = await vGet(env, 'okx_key'), sec = await vGet(env, 'okx_secret'), pass = await vGet(env, 'okx_pass');
    if (!key || !sec || !pass) return bad('no_key', '未绑定欧易 API 密钥/密码');
    const call = async (path) => {
      const ts = new Date().toISOString();
      return ex('https://www.okx.com' + path, { headers: { 'OK-ACCESS-KEY': key, 'OK-ACCESS-SIGN': await hmac('SHA-256', sec, ts + 'GET' + path, true), 'OK-ACCESS-TIMESTAMP': ts, 'OK-ACCESS-PASSPHRASE': pass, 'Content-Type': 'application/json' } });
    };
    const px = {};
    const tk = await ex('https://www.okx.com/api/v5/market/tickers?instType=SPOT');
    for (const t of tk.data || []) if (/-USDT$/.test(t.instId)) px[t.instId.replace('-USDT', '')] = Number(t.last);
    const price = (s) => (STABLE.has(s) ? 1 : px[s] != null ? px[s] : null);
    const assets = [], accounts = {};
    const tb = await call('/api/v5/account/balance');
    if (tb.code !== '0') return bad('okx_' + tb.code, String(tb.msg || '').slice(0, 120));
    let s1 = 0;
    for (const d of (tb.data && tb.data[0] && tb.data[0].details) || []) { const amt = Number(d.cashBal || d.eq || 0); if (!(amt > 0)) continue; const p = price(d.ccy); const u = d.eqUsd != null && d.eqUsd !== '' ? Number(d.eqUsd) : p != null ? amt * p : null; assets.push({ sym: d.ccy, amount: amt, usd: u, acct: '交易账户' }); s1 += u || 0; }
    accounts['交易账户'] = r4(s1);
    try {
      const fb = await call('/api/v5/asset/balances');
      let s2 = 0;
      for (const d of fb.data || []) { const amt = Number(d.bal || 0); if (!(amt > 0)) continue; const p = price(d.ccy); assets.push({ sym: d.ccy, amount: amt, usd: p != null ? amt * p : null, acct: '资金账户' }); s2 += p != null ? amt * p : 0; }
      accounts['资金账户'] = r4(s2);
    } catch (_) {}
    return fin('okx', assets, accounts);
  }
  async function gate(env) {
    const key = await vGet(env, 'gate_key'), sec = await vGet(env, 'gate_secret');
    if (!key || !sec) return bad('no_key', '未绑定 Gate API 密钥');
    const path = '/api/v4/spot/accounts', ts = String(Math.floor(Date.now() / 1000));
    const bodyHash = hex(await crypto.subtle.digest('SHA-512', enc.encode('')));
    const sign = await hmac('SHA-512', sec, ['GET', path, '', bodyHash, ts].join('\n'));
    const accs = await ex('https://api.gateio.ws' + path, { headers: { KEY: key, Timestamp: ts, SIGN: sign, Accept: 'application/json' } });
    const px = {};
    for (const t of await ex('https://api.gateio.ws/api/v4/spot/tickers')) if (/_USDT$/.test(t.currency_pair)) px[t.currency_pair.replace('_USDT', '')] = Number(t.last);
    const assets = [];
    for (const a of accs || []) { const amt = Number(a.available) + Number(a.locked); if (!(amt > 0)) continue; const p = STABLE.has(a.currency) ? 1 : px[a.currency]; assets.push({ sym: a.currency, amount: amt, usd: p != null ? amt * p : null, acct: '现货' }); }
    return fin('gate', assets, { 现货: r4(assets.reduce((s, a) => s + (a.usd || 0), 0)) });
  }
  async function cex(env, name) {
    const fn = { binance, okx, gate }[name];
    if (!fn) return bad('bad_exchange', '支持 binance / okx / gate');
    try { return await fn(env); } catch (e) {
      const m = String((e && e.message) || e);
      const d = (e && e.detail) || '';
      const hint = m === 'http_451' ? '交易所拒绝了引擎所在地区（451），需换出口地区' : m === 'http_401' || m === 'http_403' ? '密钥无效、权限不足，或交易所限制了 IP 白名单（引擎出口 IP 不固定，请不要开 IP 白名单）' : '';
      return bad(m, (hint ? hint + '；' : '') + d.slice(0, 160));
    }
  }

  // ---------- AI：多模型回退 + 结果缓存；输出「判断」而不是复述 ----------
  const AI_SYS = '你是为链上交易员服务的分析师。输入 facts 是程序已从链上算出的结果（持有人成本/盈亏/入场时点、集中度、池子与成交流向、风险项等）。任务是给出看完数据后的判断，而不是复述数据。规则：1）headline：一句话结论（不超过30字）；stance：只能是「偏风险」「中性」「偏积极」「数据不足」之一，这只是风险评估，不是买卖建议；2）points 3 到 6 条，每条含 claim（推断出的含义，例如“多个大户在同一时段买入，疑似同一团队控盘”，禁止只复述数字）、why（为什么这样判断，写清因果）、evidence（自然语言引用具体数字，例如“前 10 大钱包合计持有 28.4%，其中 5 个在上线 3 分钟内买入”；严禁出现字段名、下标、JSON 路径）；3）risks：最该警惕的 1 到 3 点；watch：接下来该盯的 2 到 4 个可验证信号；4）unknown：facts 缺失、无法判断的事；5）只能使用 facts 里的数字，没有的写进 unknown，禁止编造数字、地址、事件；样本少或窗口不全必须明说。只输出 JSON：{"headline":"","stance":"","points":[{"claim":"","why":"","evidence":""}],"risks":[""],"watch":[""],"unknown":[""]}。全部使用简体中文。';
  const MODEL_PREF = ['openai/gpt-oss-120b', 'llama-3.3-70b-versatile', 'openai/gpt-oss-20b', 'llama-3.1-8b-instant'];
  async function aiModels(env, key) {
    const c = await env.DB.prepare("SELECT v FROM kv WHERE k='groq_model3'").first();
    if (c) { try { const o = JSON.parse(c.v); if (now() - o.at < 6 * 3600e3) return o.list; } catch (_) {} }
    let list = MODEL_PREF;
    try {
      const r = await fetch('https://api.groq.com/openai/v1/models', { headers: { authorization: 'Bearer ' + key } });
      if (r.ok) { const ids = ((await r.json()).data || []).map((m) => m.id); const got = MODEL_PREF.filter((m) => ids.includes(m)); if (got.length) list = got; }
    } catch (_) {}
    await env.DB.prepare("INSERT OR REPLACE INTO kv (k,v) VALUES ('groq_model3',?)").bind(JSON.stringify({ list, at: now() })).run();
    return list;
  }
  async function sha(s) { return hex(await crypto.subtle.digest('SHA-256', enc.encode(s))).slice(0, 32); }
  async function ai(env, body) {
    const key = await vGet(env, 'groq');
    if (!key) return { error: 'no_groq_key' };
    const facts = JSON.stringify(body.facts || {}).slice(0, 6500);
    const ck = 'ai3:' + (await sha((body.kind || '') + facts));
    if (!body.fresh) { const c = await cget(env, ck, 15 * 60e3); if (c) return { ...c, cached: true }; }
    const models = await aiModels(env, key);
    let last = { error: 'groq_unavailable' };
    for (let i = 0; i < models.length; i++) {
      const model = models[i];
      const payload = { model, temperature: 0.3, max_tokens: 1700, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: AI_SYS }, { role: 'user', content: '类型：' + (body.kind || '') + '\nfacts：' + facts }] };
      if (/gpt-oss/.test(model)) payload.reasoning_effort = 'low';
      let r;
      try { r = await fetch('https://api.groq.com/openai/v1/chat/completions', { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + key }, body: JSON.stringify(payload) }); } catch (e) { last = { error: 'groq_network', detail: String((e && e.message) || e).slice(0, 80) }; continue; }
      const hdr = { status: r.status, model };
      for (const [k, v] of r.headers) if (k.startsWith('x-ratelimit') || k === 'retry-after') hdr[k] = v;
      await env.DB.prepare('INSERT OR REPLACE INTO quota (provider,hdr,at) VALUES (?,?,?)').bind('groq', JSON.stringify(hdr), now()).run();
      const txt = await r.text();
      if (!r.ok) { last = { error: 'groq_' + r.status, detail: txt.slice(0, 160), hdr }; if (r.status === 401) break; continue; }
      try {
        const c = JSON.parse(txt).choices[0].message.content || '';
        const m = c.match(/\{[\s\S]*\}/);
        const a = JSON.parse(m ? m[0] : c);
        if (!a || !Array.isArray(a.points) || !a.points.length) { last = { error: 'groq_empty', detail: '模型没有给出要点', hdr }; continue; }
        const res = { analysis: a, model, quota: hdr };
        await cput(env, ck, res);
        return res;
      } catch (_) { last = { error: 'groq_parse', detail: txt.slice(0, 120), hdr }; }
    }
    return last;
  }

  // ---------- MCP 服务（Streamable HTTP，无状态，只读工具）----------
  const TOOLS = [
    { name: 'wallet_analysis', description: '钱包交易记录分析：逐笔买卖、平均成本盈亏、胜率、持仓时间、交易风格（Solana 与 EVM）', inputSchema: { type: 'object', properties: { chain: { type: 'string', enum: CHAINS }, address: { type: 'string' }, pages: { type: 'number' } }, required: ['chain', 'address'] } },
    { name: 'token_holders', description: '代币持有人榜单与集中度（Solana 读链上最大 20 个账户；EVM 由转账记录还原）', inputSchema: { type: 'object', properties: { chain: { type: 'string', enum: CHAINS }, address: { type: 'string' } }, required: ['chain', 'address'] } },
    { name: 'holder_analysis', description: '某持有人在某代币上的成本、盈亏（美元）、入场时点、抛压与风格', inputSchema: { type: 'object', properties: { chain: { type: 'string', enum: CHAINS }, token: { type: 'string' }, owner: { type: 'string' } }, required: ['chain', 'token', 'owner'] } },
    { name: 'cex_balances', description: '交易所只读持仓（binance / okx / gate），使用 App 内绑定的 API 密钥', inputSchema: { type: 'object', properties: { exchange: { type: 'string', enum: ['binance', 'okx', 'gate'] } }, required: ['exchange'] } },
  ];
  async function callTool(env, name, a) {
    const chain = a.chain || 'solana';
    const pg = Math.min(6, Math.max(1, Number(a.pages) || 3));
    if (name === 'cex_balances') return cex(env, a.exchange);
    if (!CHAINS.includes(chain)) return bad('bad_chain', CHAINS.join(','));
    if (name === 'wallet_analysis') { if (!okAddr(chain, a.address)) return bad('bad_address'); return chain === 'solana' ? solWallet(env, a.address, pg) : EVMX.opWallet(env, chain, a.address, pg); }
    if (name === 'token_holders') { if (!okAddr(chain, a.address)) return bad('bad_address'); return chain === 'solana' ? solToken(env, a.address) : EVMX.opToken(env, chain, a.address, pg); }
    if (name === 'holder_analysis') { if (!okAddr(chain, a.token) || !okAddr(chain, a.owner)) return bad('bad_address'); return holder(env, chain, a.token, a.owner, pg); }
    return bad('unknown_tool', name);
  }
  async function mcp(env, rpc) {
    const id = rpc.id, ok = (result) => ({ jsonrpc: '2.0', id, result }), err = (code, message) => ({ jsonrpc: '2.0', id, error: { code, message } });
    if (rpc.method === 'initialize') return ok({ protocolVersion: (rpc.params && rpc.params.protocolVersion) || '2025-03-26', capabilities: { tools: {} }, serverInfo: { name: 'tstzm-engine', version: '5' } });
    if (rpc.method === 'ping') return ok({});
    if (rpc.method === 'tools/list') return ok({ tools: TOOLS });
    if (rpc.method === 'tools/call') {
      try {
        const r = await callTool(env, rpc.params.name, rpc.params.arguments || {});
        return ok({ content: [{ type: 'text', text: JSON.stringify(r).slice(0, 60000) }], isError: !!(r && r.error) });
      } catch (e) { return ok({ content: [{ type: 'text', text: String((e && e.message) || e) }], isError: true }); }
    }
    if (rpc.method && rpc.method.startsWith('notifications/')) return null;
    return err(-32601, 'method_not_found');
  }

  async function route(env, p, q, req) {
    if (p === '/e/mcp') {
      if (req.method !== 'POST') return new Response('POST JSON-RPC', { status: 405 });
      const b = await req.json();
      const list = Array.isArray(b) ? b : [b];
      const outs = [];
      for (const r of list) { const o = await mcp(env, r); if (o) outs.push(o); }
      if (!outs.length) return new Response(null, { status: 202 });
      return new Response(JSON.stringify(Array.isArray(b) ? outs : outs[0]), { headers: { 'content-type': 'application/json; charset=utf-8' } });
    }
    if (!p.startsWith('/e/v2/')) return undefined;
    const fresh = q.get('fresh') === '1';
    if (p === '/e/v2/holder') {
      const chain = q.get('chain'), t = q.get('token'), o = q.get('owner');
      if (!CHAINS.includes(chain)) return bad('bad_chain', CHAINS.join('、'));
      if (!okAddr(chain, t) || !okAddr(chain, o)) return bad('bad_args');
      const pg = Math.min(5, Math.max(1, Number(q.get('pages')) || 3));
      return cached(env, 'h2:' + chain + ':' + t.toLowerCase() + ':' + o.toLowerCase() + ':' + pg, 600, fresh, () => holder(env, chain, t, o, pg));
    }
    if (p === '/e/v2/cex') return cex(env, q.get('ex'));
    if (p === '/e/v2/ai') return ai(env, await req.json());
    if (p === '/e/v2/px') {
      const chain = q.get('chain'), from = Number(q.get('from')), to = Number(q.get('to'));
      if (!NATSYM[chain] || !(from > 0) || !(to >= from)) return bad('bad_args');
      const s = await series(env, NATSYM[chain], from, to);
      return { sym: NATSYM[chain], n: s.length, first: s[0] || null, last: s[s.length - 1] || null, at_from: priceAt(s, from), at_to: priceAt(s, to) };
    }
    return bad('not_found');
  }
  return { route, holder, cex, ai };
}
