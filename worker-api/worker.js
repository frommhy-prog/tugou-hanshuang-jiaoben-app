// TSTZ-M API 网关 v3：鉴权 + 代理旧 Worker + 加密密钥库 + Groq（真实额度响应头）+ 提醒 + 寒霜新码检测推送 + DO 闹钟调度（不占 Cron 名额）
const DEX = { bsc: 'bsc', eth: 'ethereum', base: 'base', solana: 'solana', robinhood: 'robinhood', arbitrum: 'arbitrum', optimism: 'optimism', polygon: 'polygon', okc: 'okc', xlayer: 'xlayer' };
const PROVIDERS = ['groq', 'helius', 'alchemy', 'telegram_token', 'telegram_chat', 'bark', 'binance_key', 'binance_secret', 'okx_key', 'okx_secret', 'okx_pass', 'gate_key', 'gate_secret']; // 新增 alchemy（EVM 钱包/代币分析）
const GROQ = 'https://api.groq.com/openai/v1';
const PREF = ['llama-3.3-70b-versatile', 'openai/gpt-oss-120b', 'openai/gpt-oss-20b', 'llama-3.1-8b-instant'];
const enc = new TextEncoder();
const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
const now = () => Date.now();
const num = (v) => { const n = Number(v); return v != null && v !== '' && Number.isFinite(n) ? n : null; };

function authed(req, env) {
  const h = req.headers.get('authorization') || '';
  const t = h.startsWith('Bearer ') ? h.slice(7) : '';
  const s = env.APP_TOKEN || '';
  if (!s || t.length !== s.length) return false;
  let r = 0;
  for (let i = 0; i < s.length; i++) r |= t.charCodeAt(i) ^ s.charCodeAt(i);
  return r === 0;
}

// ---- 加密密钥库（AES-GCM，主密钥来自 Secret VAULT_KEY，D1 里只存密文）----
async function vkey(env) {
  const d = await crypto.subtle.digest('SHA-256', enc.encode(env.VAULT_KEY || ''));
  return crypto.subtle.importKey('raw', d, 'AES-GCM', false, ['encrypt', 'decrypt']);
}
const b64 = (u8) => btoa(String.fromCharCode(...u8));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
async function vPut(env, provider, value) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await vkey(env), enc.encode(value)));
  await env.DB.prepare('INSERT OR REPLACE INTO vault (provider, blob, last4, updated) VALUES (?,?,?,?)').bind(provider, b64(iv) + '.' + b64(ct), value.slice(-4), now()).run();
}
async function vGet(env, provider) {
  const r = await env.DB.prepare('SELECT blob FROM vault WHERE provider=?').bind(provider).first();
  if (!r) return null;
  const [ivs, cts] = r.blob.split('.');
  try { return new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(ivs) }, await vkey(env), unb64(cts))); } catch (_) { return null; }
}

function parseDur(s) {
  if (!s) return null;
  const re = /([\d.]+)(ms|h|m|s)/g; let m, t = 0, any = false;
  while ((m = re.exec(s))) { any = true; const v = parseFloat(m[1]); t += m[2] === 'h' ? v * 3600 : m[2] === 'm' ? v * 60 : m[2] === 's' ? v : v / 1000; }
  return any ? t : null;
}
async function saveQuota(env, provider, hdr) { await env.DB.prepare('INSERT OR REPLACE INTO quota (provider,hdr,at) VALUES (?,?,?)').bind(provider, JSON.stringify(hdr), now()).run(); }
function track(env, ctx, ep) {
  const day = new Date().toISOString().slice(0, 10);
  ctx.waitUntil(env.DB.prepare('INSERT INTO usage (day,ep,n) VALUES (?,?,1) ON CONFLICT(day,ep) DO UPDATE SET n=n+1').bind(day, ep).run().catch(() => {}));
}
function ensureSched(env, ctx) {
  try { ctx.waitUntil(env.SCHED.get(env.SCHED.idFromName('main')).fetch('https://sched/ensure').catch(() => {})); } catch (_) {}
}

async function legacy(env, path, init) { return env.LEGACY.fetch('https://legacy.internal' + path, init); }
async function proxy(req, env, url) {
  const init = { method: req.method, headers: { accept: 'application/json' } };
  if (req.method !== 'GET' && req.method !== 'HEAD') { init.body = await req.text(); init.headers['content-type'] = req.headers.get('content-type') || 'application/json'; }
  const r = await legacy(env, url.pathname + url.search, init);
  return new Response(r.body, { status: r.status, headers: { 'content-type': r.headers.get('content-type') || 'application/json', 'cache-control': 'no-store' } });
}

// ---- Groq ----
async function groqModel(env, key) {
  const c = await env.DB.prepare("SELECT v FROM kv WHERE k='groq_model'").first();
  if (c) { try { const o = JSON.parse(c.v); if (now() - o.at < 12 * 3600e3) return o.id; } catch (_) {} }
  let id = PREF[0];
  try {
    const r = await fetch(GROQ + '/models', { headers: { authorization: 'Bearer ' + key } });
    if (r.ok) {
      const ids = ((await r.json()).data || []).map((m) => m.id);
      id = PREF.find((p) => ids.includes(p)) || ids.find((i) => /llama|gpt-oss|qwen/.test(i) && !/whisper|guard|tts|prompt/.test(i)) || id;
    }
  } catch (_) {}
  await env.DB.prepare("INSERT OR REPLACE INTO kv (k,v) VALUES ('groq_model',?)").bind(JSON.stringify({ id, at: now() })).run();
  return id;
}
async function groqJson(env, system, user) {
  const key = await vGet(env, 'groq');
  if (!key) return { error: 'no_groq_key' };
  const model = await groqModel(env, key);
  const body = { model, temperature: 0.2, max_tokens: 1500, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: system }, { role: 'user', content: user }] };
  const r = await fetch(GROQ + '/chat/completions', { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + key }, body: JSON.stringify(body) });
  const hdr = { status: r.status, model };
  for (const [k, v] of r.headers) if (k.startsWith('x-ratelimit') || k === 'retry-after') hdr[k] = v;
  await saveQuota(env, 'groq', hdr);
  const txt = await r.text();
  if (!r.ok) return { error: 'groq_' + r.status, detail: txt.slice(0, 300), hdr };
  try {
    const c = JSON.parse(txt).choices?.[0]?.message?.content || '';
    const m = c.match(/\{[\s\S]*\}/);
    return { data: JSON.parse(m ? m[0] : c), hdr, model };
  } catch (_) { return { error: 'groq_parse', detail: txt.slice(0, 300), hdr }; }
}
function compactFacts(t) {
  const p = t.price || {};
  return {
    chain: t.chain ?? null, symbol: p.symbol ?? null, name: p.name ?? null, priceUsd: p.priceUsd ?? null, liquidityUsd: p.liquidityUsd ?? null,
    volume24hUsd: p.volume24hUsd ?? null, change24hPct: p.priceChange24hPct ?? null, marketCapUsd: t.marketCapUsd ?? null, poolAgeDays: t.poolAge ?? null,
    holders: t.holders ?? t.realHolders ?? null, top10Pct: t.topHoldersPct ?? null, buyTax: t.buyTax ?? null, sellTax: t.sellTax ?? null,
    honeypot: t.honeypot ?? null, mintable: t.mintable ?? null, blacklist: t.blacklist ?? null, renounced: t.renounced ?? null,
    lpLocked: t.lpLocked ?? null, lpBurnPct: t.lpBurnPct ?? null, riskLight: t.risk ?? null, riskSource: t.riskSource ?? null,
    buys24h: t.tradeFlow?.h24?.buys ?? t.txns24h?.buys ?? null, sells24h: t.tradeFlow?.h24?.sells ?? t.txns24h?.sells ?? null,
    solanaMintRenounced: t.solanaAuthorities?.mintRenounced ?? null, solanaFreezeRenounced: t.solanaAuthorities?.freezeRenounced ?? null,
  };
}
const SYS = '你是链上风控分析师。只能使用用户给出的 facts JSON 里的数据；值为 null 表示未知，必须写“未知”，禁止猜测、禁止补数字、禁止出现 facts 里没有的数值。' +
  '严格输出 JSON：{"verdict":"绿|黄|红|未知","score":0到100整数(越高越安全；数据不足给50并说明),"headline":"一句话结论(不超过40字)","bullets":[{"tag":"风险|亮点|未知","text":"一条(不超过50字)"}],"watch":["后续观察点"]}。bullets 给 3 到 6 条。不给买卖建议。全部使用简体中文。';
async function analyze(env, url) {
  const chain = url.searchParams.get('chain'), address = url.searchParams.get('address');
  if (!DEX[chain] || !address) return json({ error: 'bad_args' }, 400);
  const r = await legacy(env, `/api/token?chain=${chain}&address=${encodeURIComponent(address)}`);
  let t = null; try { t = await r.json(); } catch (_) {}
  if (!t || t.error) return json({ error: 'token_unavailable', detail: t && t.error }, 502);
  const facts = compactFacts(t);
  const g = await groqJson(env, SYS, 'facts=' + JSON.stringify(facts));
  if (g.error) return json({ error: g.error, detail: g.detail, facts }, g.error === 'no_groq_key' ? 200 : 502);
  return json({ facts, analysis: g.data, model: g.model, quota: g.hdr, at: now() });
}

// ---- 额度 ----
async function quotas(env) {
  const key = await env.DB.prepare("SELECT 1 x FROM vault WHERE provider='groq'").first();
  const g = await env.DB.prepare("SELECT hdr, at FROM quota WHERE provider='groq'").first();
  let groq = { keyPresent: !!key, called: false };
  if (g) {
    const h = JSON.parse(g.hdr);
    const rr = parseDur(h['x-ratelimit-reset-requests']), rt = parseDur(h['x-ratelimit-reset-tokens']), ra = num(h['retry-after']);
    groq = { keyPresent: !!key, called: true, at: g.at, status: h.status, model: h.model,
      limitRequests: num(h['x-ratelimit-limit-requests']), remainingRequests: num(h['x-ratelimit-remaining-requests']), resetRequestsAtMs: rr != null ? g.at + rr * 1000 : null,
      limitTokens: num(h['x-ratelimit-limit-tokens']), remainingTokens: num(h['x-ratelimit-remaining-tokens']), resetTokensAtMs: rt != null ? g.at + rt * 1000 : null,
      limited: h.status === 429, retryAtMs: ra != null ? g.at + ra * 1000 : null };
  }
  const day = new Date().toISOString().slice(0, 10);
  const u = await env.DB.prepare('SELECT ep, n FROM usage WHERE day=? ORDER BY n DESC').bind(day).all();
  let lg = null; try { lg = await (await legacy(env, '/api/quotas')).json(); } catch (_) {}
  return { day, groq, usage: u.results, legacy: lg };
}

// ---- 推送（Telegram / Bark）----
async function push(env, title, body, opts = {}) {
  const out = { telegram: null, bark: null };
  const tt = await vGet(env, 'telegram_token'), tc = await vGet(env, 'telegram_chat');
  if (tt && tc) {
    try {
      const payload = opts.tg ? { chat_id: tc, text: opts.tg, parse_mode: 'HTML' } : { chat_id: tc, text: title + '\n' + body };
      out.telegram = (await fetch(`https://api.telegram.org/bot${tt}/sendMessage`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload) })).ok;
    } catch (_) { out.telegram = false; }
  }
  const bk = await vGet(env, 'bark');
  if (bk) {
    try {
      const base = /^https?:/.test(bk) ? bk.replace(/\/$/, '') : 'https://api.day.app/' + bk;
      let q = '?group=TSTZ-M';
      if (opts.url) q += '&url=' + encodeURIComponent(opts.url);
      if (opts.copy) q += '&copy=' + encodeURIComponent(opts.copy);
      out.bark = (await fetch(`${base}/${encodeURIComponent(title)}/${encodeURIComponent(body)}${q}`)).ok;
    } catch (_) { out.bark = false; }
  }
  return out;
}

// ---- 提醒评估 ----
const fp = (v) => (v == null ? '未知' : Number(v) >= 1 ? Number(v).toFixed(4) : Number(v).toPrecision(4));
function check(a, d) {
  if (!d) return null;
  const s = d.symbol || a.symbol || '';
  switch (a.kind) {
    case 'price_above': return d.price != null && d.price >= a.value ? `${s} 价格 ${fp(d.price)} 已高于 ${fp(a.value)}` : null;
    case 'price_below': return d.price != null && d.price <= a.value ? `${s} 价格 ${fp(d.price)} 已低于 ${fp(a.value)}` : null;
    case 'change5m_abs': return d.m5 != null && Math.abs(d.m5) >= a.value ? `${s} 5 分钟涨跌 ${d.m5}%（阈值 ${a.value}%）` : null;
    case 'change1h_abs': return d.h1 != null && Math.abs(d.h1) >= a.value ? `${s} 1 小时涨跌 ${d.h1}%（阈值 ${a.value}%）` : null;
    case 'drop_from_ref': { if (d.price == null || !(a.ref > 0)) return null; const dr = (a.ref - d.price) / a.ref * 100; return dr >= a.value ? `${s} 较参考价 ${fp(a.ref)} 下跌 ${dr.toFixed(1)}%` : null; }
    case 'liq_below': return d.liq != null && d.liq <= a.value ? `${s} 流动性 ${Math.round(d.liq)} 美元，已低于 ${a.value}` : null;
    case 'vol24_above': return d.vol != null && d.vol >= a.value ? `${s} 24h 成交 ${Math.round(d.vol)} 美元，已高于 ${a.value}` : null;
    default: return null;
  }
}
async function evalAlerts(env) {
  const rows = (await env.DB.prepare('SELECT * FROM alerts WHERE active=1').all()).results || [];
  const res = { at: now(), alerts: rows.length, fired: 0, pushed: null };
  if (rows.length) {
    const byChain = {};
    for (const a of rows) if (DEX[a.chain] && a.address) (byChain[a.chain] ||= new Set()).add(a.address);
    const px = {}; let calls = 0;
    for (const [chain, set] of Object.entries(byChain)) {
      const addrs = [...set];
      for (let i = 0; i < addrs.length && calls < 30; i += 30) {
        calls++;
        try {
          const r = await fetch(`https://api.dexscreener.com/tokens/v1/${DEX[chain]}/${addrs.slice(i, i + 30).join(',')}`, { headers: { accept: 'application/json' } });
          if (!r.ok) continue;
          const pairs = await r.json();
          if (!Array.isArray(pairs)) continue;
          for (const p of pairs) {
            const k = chain + ':' + String(p.baseToken?.address || '').toLowerCase(), liq = p.liquidity?.usd || 0;
            if (!px[k] || liq > px[k]._liq) px[k] = { _liq: liq, price: p.priceUsd ? Number(p.priceUsd) : null, m5: p.priceChange?.m5 ?? null, h1: p.priceChange?.h1 ?? null, liq: p.liquidity?.usd ?? null, vol: p.volume?.h24 ?? null, symbol: p.baseToken?.symbol };
          }
        } catch (_) {}
      }
    }
    const t = now();
    for (const a of rows) {
      if (t - (a.last_fired || 0) < (a.cooldown_min || 60) * 60000) continue;
      const msg = check(a, px[a.chain + ':' + String(a.address || '').toLowerCase()]);
      if (!msg) continue;
      const r = await push(env, 'TSTZ-M 提醒', msg);
      res.pushed = r;
      await env.DB.prepare('UPDATE alerts SET last_fired=? WHERE id=?').bind(t, a.id).run();
      res.fired++;
    }
  }
  await env.DB.prepare("INSERT OR REPLACE INTO kv (k,v) VALUES ('last_eval',?)").bind(JSON.stringify(res)).run();
  return res;
}

// ---- 寒霜：新兑换码检测（多站点共识 + 旧 Worker 人工名单），新码推送 ----
const WOS_SOURCES = [
  'https://commonsensegamer.com/whiteout-survival-gift-code/',
  'https://gamepretty.com/whiteout-survival-codes/',
  'https://www.pocketgamer.com/white-out-survival/codes/',
  'https://www.bluestacks.com/blog/news/whiteout-survival-redeem-codes-en.html',
  'https://beebom.com/whiteout-survival-codes/',
  'https://www.gamesradar.com/games/survival/whiteout-survival-codes-gift',
];
const WOS_STOP = /whiteout|survival|centurygame|century|facebook|youtube|discord|twitter|instagram|google|android|iphone|redeem|gamerevolution|pocketgamer|bluestacks|beebom|gamesradar|gamepretty|commonsense|topuplist|dexerto|expired|working|active|current|tiktok(?!10)/i;
function plausibleCode(w) {
  if (/^[0-9]+$/.test(w)) return false;
  if (/^[a-z]+$/.test(w)) return false;
  if (/^[A-Z][a-z]+$/.test(w)) return false;
  if (WOS_STOP.test(w)) return false;
  return true;
}
function wosCandidates(html) {
  let t = html.replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<!--[\s\S]*?-->/g, ' ');
  t = t.replace(/<[^>]+>/g, '\n').replace(/&nbsp;|&#160;/g, ' ').replace(/&amp;/g, '&');
  const a = t.search(/(active|working|current|valid)[^\n]{0,40}codes?/i);
  const body = a >= 0 ? t.slice(a) : t;
  const e = body.search(/\n\s*(expired|inactive|old|no longer)[^\n]{0,40}codes?/i);
  const seg = e > 0 ? body.slice(0, e) : body;
  const out = new Set();
  for (const m of seg.matchAll(/\b[A-Za-z0-9]{5,16}\b/g)) if (plausibleCode(m[0])) out.add(m[0]);
  return [...out];
}
async function pollWos(env) {
  const res = { at: now(), sources: [], newCodes: [], baseline: false };
  const count = {};
  for (const url of WOS_SOURCES) {
    try {
      const r = await fetch(url, { headers: { 'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1', accept: 'text/html', 'accept-language': 'en-US,en;q=0.9' }, cf: { cacheTtl: 900 } });
      const c = r.ok ? wosCandidates(await r.text()) : [];
      res.sources.push({ h: new URL(url).host, s: r.status, n: c.length });
      for (const w of c) count[w] = (count[w] || 0) + 1;
    } catch (e) { res.sources.push({ h: url, err: String((e && e.message) || e).slice(0, 80) }); }
  }
  try {
    const j = await (await legacy(env, '/api/wos-codes')).json();
    for (const c of j.codes || []) if (c.code && !/expire|过期|失效/i.test(c.status || '')) count[c.code] = (count[c.code] || 0) + 2;
  } catch (_) {}
  const known = new Set(((await env.DB.prepare('SELECT code FROM wos_codes').all()).results || []).map((r) => r.code));
  res.baseline = known.size === 0;
  const stmts = [];
  for (const [code, n] of Object.entries(count)) {
    if (n < 2 || known.has(code)) continue;
    stmts.push(env.DB.prepare('INSERT OR IGNORE INTO wos_codes (code, first_seen, sources, notified) VALUES (?,?,?,?)').bind(code, now(), n, res.baseline ? 1 : 0));
    if (!res.baseline) res.newCodes.push(code);
  }
  if (stmts.length) await env.DB.batch(stmts);
  if (res.newCodes.length) {
    const list = res.newCodes.slice(0, 8);
    res.pushed = await push(env, '寒霜新兑换码', list.join('、') + '\n打开 TSTZ-M「寒霜」页，手动或自动兑换', {
      tg: '🎁 <b>寒霜启示录 新兑换码</b>\n' + list.map((c) => '<code>' + c + '</code>').join('\n') + '\n打开 TSTZ-M 的「寒霜」页，手动或自动兑换',
      url: 'tstzm://frost?code=' + encodeURIComponent(list[0]), copy: list[0],
    });
  }
  await env.DB.prepare("INSERT OR REPLACE INTO kv (k,v) VALUES ('last_wos',?)").bind(JSON.stringify(res)).run();
  return res;
}

export class Scheduler {
  constructor(state, env) { this.state = state; this.env = env; }
  async fetch() {
    if ((await this.state.storage.getAlarm()) == null) await this.state.storage.setAlarm(Date.now() + 30000);
    return new Response('ok');
  }
  async alarm() {
    const st = this.state.storage;
    let next = 5 * 60000;
    try {
      const phase = (await st.get('phase')) || 'alerts';
      if (phase === 'poll') {
        await pollWos(this.env);
        await st.put('lastPoll', Date.now());
        await st.put('phase', 'alerts');
      } else {
        await evalAlerts(this.env);
        const last = (await st.get('lastPoll')) || 0;
        if (Date.now() - last > 30 * 60000) { await st.put('phase', 'poll'); next = 15000; }
      }
    } catch (_) {}
    await st.setAlarm(Date.now() + next);
  }
}

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    if (url.pathname === '/health') return json({ ok: true, v: 3 });
    if (!authed(req, env)) return json({ error: 'unauthorized' }, 401);
    const p = url.pathname, m = req.method;
    try {
      if (p === '/v1/ping') {
        ensureSched(env, ctx);
        const le = await env.DB.prepare("SELECT v FROM kv WHERE k='last_eval'").first();
        return json({ ok: true, at: now(), lastEval: le ? JSON.parse(le.v) : null });
      }
      if (p.startsWith('/api/')) { track(env, ctx, p); return await proxy(req, env, url); }
      if (p === '/v1/ai/analyze') { track(env, ctx, 'ai-analyze'); return await analyze(env, url); }
      if (p === '/v1/quotas') return json(await quotas(env));
      if (p === '/v1/config') {
        if (m === 'PUT') { await env.DB.prepare("INSERT OR REPLACE INTO kv (k,v) VALUES ('profile',?)").bind(await req.text()).run(); return json({ ok: true }); }
        const r = await env.DB.prepare("SELECT v FROM kv WHERE k='profile'").first();
        return json({ profile: r ? JSON.parse(r.v) : null });
      }
      if (p === '/v1/wos/codes') {
        ensureSched(env, ctx);
        const rows = (await env.DB.prepare('SELECT code, first_seen AS firstSeen, sources FROM wos_codes ORDER BY first_seen DESC LIMIT 60').all()).results || [];
        const lw = await env.DB.prepare("SELECT v FROM kv WHERE k='last_wos'").first();
        const last = lw ? JSON.parse(lw.v) : null;
        return json({ codes: rows, lastPollAt: last ? last.at : null, sources: last ? last.sources : null });
      }
      if (p === '/v1/wos/poll') { track(env, ctx, 'wos-poll'); return json(await pollWos(env)); }
      if (p === '/v1/keys') {
        if (m === 'PUT') { const b = await req.json(); if (!PROVIDERS.includes(b.provider) || !b.value || String(b.value).length < 4) return json({ error: 'bad_args' }, 400); await vPut(env, b.provider, String(b.value).trim()); return json({ ok: true }); }
        if (m === 'DELETE') { await env.DB.prepare('DELETE FROM vault WHERE provider=?').bind(url.searchParams.get('provider')).run(); return json({ ok: true }); }
        const rows = (await env.DB.prepare('SELECT provider,last4,updated FROM vault').all()).results || [];
        return json({ providers: PROVIDERS.map((id) => { const r = rows.find((x) => x.provider === id); return { id, present: !!r, last4: r ? r.last4 : null, updated: r ? r.updated : null }; }) });
      }
      if (p === '/v1/alerts') {
        ensureSched(env, ctx);
        if (m === 'POST') {
          const b = await req.json();
          if (!['price_above', 'price_below', 'change5m_abs', 'change1h_abs', 'drop_from_ref', 'liq_below', 'vol24_above'].includes(b.kind) || !DEX[b.chain] || !b.address || !(Number(b.value) > 0)) return json({ error: 'bad_args' }, 400);
          const r = await env.DB.prepare('INSERT INTO alerts (kind,chain,address,symbol,value,ref,active,cooldown_min,last_fired,created) VALUES (?,?,?,?,?,?,1,?,0,?)').bind(b.kind, b.chain, b.address, b.symbol || null, Number(b.value), b.ref != null ? Number(b.ref) : null, Number(b.cooldownMin) || 60, now()).run();
          return json({ ok: true, id: r.meta.last_row_id });
        }
        const id = Number(url.searchParams.get('id'));
        if (m === 'PATCH') { const b = await req.json(); await env.DB.prepare('UPDATE alerts SET active=? WHERE id=?').bind(b.active ? 1 : 0, id).run(); return json({ ok: true }); }
        if (m === 'DELETE') { await env.DB.prepare('DELETE FROM alerts WHERE id=?').bind(id).run(); return json({ ok: true }); }
        return json({ alerts: (await env.DB.prepare('SELECT * FROM alerts ORDER BY id DESC').all()).results });
      }
      if (p === '/v1/push/test') return json(await push(env, 'TSTZ-M 测试', '推送通道正常'));
      if (p === '/v1/run-alerts') return json(await evalAlerts(env));
      return json({ error: 'not_found' }, 404);
    } catch (e) {
      return json({ error: 'server', detail: String((e && e.message) || e) }, 500);
    }
  },
  async scheduled(event, env, ctx) { ctx.waitUntil(evalAlerts(env).catch(() => {})); },
};
