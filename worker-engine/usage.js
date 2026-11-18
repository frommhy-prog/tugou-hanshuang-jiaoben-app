// 上游 API 调用计数：包装全局 fetch，按供应商把「次数 + 估算消耗单位」记到 D1 api_usage 表（按 UTC 日）。
// App「API 用量控制台」读 /e/usage；Alchemy 按官方 CU 表估算，Helius 按官方 credits 表估算，其余按次数。
const UP = { env: null, installed: false, ready: false };
const dayKey = (t) => new Date(t == null ? Date.now() : t).toISOString().slice(0, 10);

// Alchemy 官方 CU 表（常用方法；没列到的按 20 CU 估）
const ALCHEMY_CU = { eth_chainid: 0, eth_blocknumber: 10, eth_call: 26, eth_getlogs: 60, eth_getbalance: 19, eth_getcode: 19, eth_getblockbynumber: 20, eth_gettransactionbyhash: 20, eth_gettransactionreceipt: 20, eth_gettransactioncount: 20, eth_gasprice: 19, eth_getstorageat: 20, alchemy_getassettransfers: 120, alchemy_gettokenbalances: 100, alchemy_gettokenmetadata: 10 };
// Helius：标准 RPC 1 credit；DAS / getProgramAccounts / getTransactionsForAddress 起步 10 credits；Enhanced Transactions（api.helius.xyz/v0）100 credits
const HELIUS_10 = new Set(['getasset', 'getassetbatch', 'getassetsbyowner', 'getassetsbygroup', 'getassetsbycreator', 'getassetsbyauthority', 'searchassets', 'getassetproof', 'getassetproofbatch', 'getsignaturesforasset', 'gettokenaccounts', 'getnfteditions', 'getprogramaccounts', 'gettransactionsforaddress']);

function provOf(h) {
  if (h.endsWith('alchemy.com')) return 'alchemy';
  if (h.endsWith('helius-rpc.com') || h.endsWith('helius.xyz')) return 'helius';
  if (h.endsWith('groq.com')) return 'groq';
  if (h.endsWith('cerebras.ai')) return 'cerebras';
  if (h.endsWith('googleapis.com')) return 'gemini';
  if (h.endsWith('openrouter.ai')) return 'openrouter';
  if (h.endsWith('mistral.ai')) return 'mistral';
  if (h.endsWith('dexscreener.com')) return 'dexscreener';
  if (h.endsWith('geckoterminal.com')) return 'geckoterminal';
  if (h.endsWith('rugcheck.xyz')) return 'rugcheck';
  if (h.endsWith('gopluslabs.io')) return 'goplus';
  if (h.endsWith('coingecko.com')) return 'coingecko';
  if (h.endsWith('jup.ag')) return 'jupiter';
  if (h.endsWith('dexpaprika.com')) return 'dexpaprika';
  if (h.endsWith('publicnode.com')) return 'publicnode';
  if (h.endsWith('binance.com') || h.endsWith('binance.vision')) return 'binance';
  if (h.endsWith('okx.com')) return 'okx';
  if (h.endsWith('gateio.ws')) return 'gate';
  if (h.endsWith('pump.fun')) return 'pumpfun';
  return null;
}

function methodsOf(body) {
  if (!body) return [];
  try {
    const j = JSON.parse(body);
    return (Array.isArray(j) ? j : [j]).map((x) => String((x && x.method) || '').toLowerCase());
  } catch (_) { return []; }
}

function unitsOf(prov, u, body) {
  if (prov === 'alchemy') {
    const ms = methodsOf(body);
    if (!ms.length) return 20;
    return ms.reduce((s, m) => s + (ALCHEMY_CU[m] != null ? ALCHEMY_CU[m] : 20), 0);
  }
  if (prov === 'helius') {
    if (u.hostname.endsWith('helius.xyz')) return /\/v0\//.test(u.pathname) ? 100 : 1;
    const ms = methodsOf(body);
    if (!ms.length) return 1;
    return ms.reduce((s, m) => s + (HELIUS_10.has(m) ? 10 : 1), 0);
  }
  return 1;
}

async function ensure(env) {
  if (UP.ready) return;
  await env.DB.prepare('CREATE TABLE IF NOT EXISTS api_usage (day TEXT NOT NULL, provider TEXT NOT NULL, calls INTEGER NOT NULL DEFAULT 0, units REAL NOT NULL DEFAULT 0, PRIMARY KEY (day, provider))').run();
  UP.ready = true;
}

async function track(hit) {
  const env = UP.env;
  if (!env || !env.DB) return;
  try {
    await ensure(env);
    await env.DB.prepare('INSERT INTO api_usage (day, provider, calls, units) VALUES (?, ?, 1, ?) ON CONFLICT(day, provider) DO UPDATE SET calls = calls + 1, units = units + excluded.units').bind(dayKey(), hit.prov, hit.units).run();
  } catch (_) { /* 计数失败不影响业务 */ }
}

export function installUsage(env) {
  UP.env = env;
  if (UP.installed) return;
  UP.installed = true;
  const orig = globalThis.fetch.bind(globalThis);
  globalThis.fetch = async function (input, init) {
    let hit = null;
    try {
      const url = typeof input === 'string' ? input : (input && input.url) || String(input);
      const u = new URL(url);
      const prov = provOf(u.hostname);
      if (prov) hit = { prov, units: unitsOf(prov, u, init && typeof init.body === 'string' ? init.body : null) };
    } catch (_) { /* 解析失败就不计数 */ }
    try {
      return await orig(input, init);
    } finally {
      if (hit) await track(hit);
    }
  };
}

export async function usageReport(env) {
  await ensure(env);
  const today = dayKey();
  const monthStart = today.slice(0, 7) + '-01';
  const t = await env.DB.prepare('SELECT provider, calls, units FROM api_usage WHERE day = ?').bind(today).all();
  const m = await env.DB.prepare('SELECT provider, SUM(calls) AS calls, SUM(units) AS units FROM api_usage WHERE day >= ? GROUP BY provider').bind(monthStart).all();
  let groq = null;
  try {
    const g = await env.DB.prepare("SELECT hdr, at FROM quota WHERE provider = 'groq'").first();
    if (g) groq = { hdr: JSON.parse(g.hdr), at: g.at };
  } catch (_) { groq = null; }
  return { day: today, since: monthStart, today: t.results || [], month: m.results || [], groq, at: Date.now() };
}
