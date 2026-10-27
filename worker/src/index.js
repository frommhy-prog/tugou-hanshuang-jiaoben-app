// 土狗寒霜脚本app - Cloudflare Worker 统一网关（第一阶段脚手架）
// 原则：App 和小组件只读这里的 JSON，不直连上游；Secrets 只从 env 读，绝不写进代码。
// 链适配器只做映射，不按链重做一套。

const CHAINS = {
  bsc: { dex: "bsc", gecko: "bsc", evm: true },
  eth: { dex: "ethereum", gecko: "eth", evm: true },
  base: { dex: "base", gecko: "base", evm: true },
  solana: { dex: "solana", gecko: "solana", evm: false },
  robinhood: { dex: "robinhood", gecko: "robinhood", evm: true, chainId: 4663 },
};

const SOURCES = [
  { id: "dexscreener", role: "价格/池子", link: "https://dexscreener.com/" },
  { id: "geckoterminal", role: "价格/池子", link: "https://www.geckoterminal.com/" },
  { id: "ave", role: "行情/跳转", link: "https://ave.ai/" },
  { id: "gmgn", role: "行情/聪明钱/跳转", link: "https://gmgn.ai/" },
  { id: "x", role: "社媒信号/新币线索", link: "https://x.com/" },
  { id: "blockscout", role: "Robinhood 地址/交易/代币页", link: "https://robinhoodchain.blockscout.com/" },
];

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function isValidAddress(chain, address) {
  if (!address || typeof address !== "string") return false;
  const c = CHAINS[chain];
  if (!c) return false;
  if (c.evm) return /^0x[0-9a-fA-F]{40}$/.test(address);
  return /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(address); // Solana base58
}

// Dexscreener：按合约查最深的池子。查不到不编数。
async function dexToken(chain, address) {
  const url = `https://api.dexscreener.com/tokens/v1/${CHAINS[chain].dex}/${address}`;
  const res = await fetch(url, { headers: { accept: "application/json" } });
  if (!res.ok) return null;
  const pairs = await res.json();
  if (!Array.isArray(pairs) || pairs.length === 0) return null;
  const best = pairs.sort((a, b) => (b.liquidity?.usd || 0) - (a.liquidity?.usd || 0))[0];
  return {
    name: best.baseToken?.name ?? null,
    symbol: best.baseToken?.symbol ?? null,
    priceUsd: best.priceUsd ? Number(best.priceUsd) : null,
    liquidityUsd: best.liquidity?.usd ?? null,
    volume24hUsd: best.volume?.h24 ?? null,
    priceChange24hPct: best.priceChange?.h24 ?? null,
    pairAddress: best.pairAddress ?? null,
    dexId: best.dexId ?? null,
    source: "dexscreener",
  };
}

// GeckoTerminal 兜底：Dexscreener 经 Worker 返回空时再查一次。
// 只给价格和 24h 量，流动性/涨跌/池子地址该接口不直接给，就留空，不编数。
async function geckoToken(chain, address) {
  const url = `https://api.geckoterminal.com/api/v2/networks/${CHAINS[chain].gecko}/tokens/${address}`;
  const res = await fetch(url, { headers: { accept: "application/json" } });
  if (!res.ok) return null;
  const body = await res.json();
  const attr = body?.data?.attributes;
  if (!attr || attr.price_usd == null) return null;
  return {
    name: attr.name ?? null,
    symbol: attr.symbol ?? null,
    priceUsd: Number(attr.price_usd),
    liquidityUsd: null,
    volume24hUsd: attr.volume_usd?.h24 ? Number(attr.volume_usd.h24) : null,
    priceChange24hPct: null,
    pairAddress: null,
    dexId: null,
    source: "geckoterminal",
  };
}

async function cached(env, key, fn, ttlSeconds = 180) {
  // 有 KV 就缓存 3 分钟；没有 KV 就直接查，不假装缓存了。
  try {
    if (env.CACHE_KV) {
      const hit = await env.CACHE_KV.get(key);
      if (hit) return JSON.parse(hit);
      const value = await fn();
      if (value) await env.CACHE_KV.put(key, JSON.stringify(value), { expirationTtl: ttlSeconds });
      return value;
    }
  } catch (_) { /* fall through to direct fetch */ }
  return fn();
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/health") return json({ ok: true, service: "tugou-hanshuang-jiaoben-app" });
    if (path === "/api/sources") return json({ sources: SOURCES });

    if (path === "/api/token" && request.method === "GET") {
      const chain = (url.searchParams.get("chain") || "").toLowerCase();
      const address = url.searchParams.get("address") || "";
      if (!CHAINS[chain]) return json({ error: "unknown_chain", chain }, 400);
      if (!isValidAddress(chain, address)) return json({ error: "invalid_address", chain }, 400);
      const dexPrice = await cached(env, `token:${chain}:${address.toLowerCase()}`, () => dexToken(chain, address));
      const price = dexPrice || (await geckoToken(chain, address));
      return json({
        chain, address,
        price,
        // 第二阶段再接，不编数据：
        holders: null, topHoldersPct: null, buyTax: null, sellTax: null,
        honeypot: null, renounced: null, mintable: null, blacklist: null,
        lpLocked: null, poolAge: null, creatorHistory: null,
        risk: null, riskSource: "pending",
        tradeLinks: {
          ave: `https://ave.ai/token/${address}-${chain}`,
          gmgn: `https://gmgn.ai/${chain}/token/${address}`,
          dexscreener: price?.pairAddress ? `https://dexscreener.com/${CHAINS[chain].dex}/${price.pairAddress}` : null,
        },
      });
    }

    if (path === "/api/holdings" && request.method === "POST") {
      let body = {};
      try { body = await request.json(); } catch (_) { return json({ error: "bad_json" }, 400); }
      const wallets = Array.isArray(body.wallets) ? body.wallets : [];
      const valid = [];
      const invalid = [];
      for (const w of wallets) {
        const chain = String(w.chain || "").toLowerCase();
        if (CHAINS[chain] && isValidAddress(chain, w.address)) {
          valid.push({ chain, address: w.address, label: w.label || "" });
        } else {
          invalid.push({ chain: w.chain || null, address: w.address || null, reason: "invalid_chain_or_address" });
        }
      }
      // 第一版：钱包列表校验 + 聚合骨架。链上余额接口（Blockscout / RPC）
      // 需 Secrets 到位后在第二步接通，这里不返回假余额。
      return json({
        wallets: valid, invalid,
        byChain: {},
        totalUsd: null,
        balanceSource: "pending",
        note: "钱包可随时在 App 内增删改，Worker 按当前列表聚合；余额源接通前不估算。",
      });
    }

    return json({ error: "not_found", path }, 404);
  },
};
