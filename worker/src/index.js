// 土狗寒霜脚本app - Cloudflare Worker 统一网关（第一阶段脚手架）
// 原则：App 和小组件只读这里的 JSON，不直连上游；Secrets 只从 env 读，绝不写进代码。
// 链适配器只做映射，不按链重做一套。

const CHAINS = {
  bsc: { dex: "bsc", gecko: "bsc", evm: true, chainId: 56 },
  eth: { dex: "ethereum", gecko: "eth", evm: true, chainId: 1 },
  base: { dex: "base", gecko: "base", evm: true, chainId: 8453 },
  solana: { dex: "solana", gecko: "solana", evm: false, chainId: null },
  robinhood: { dex: "robinhood", gecko: "robinhood", evm: true, chainId: 4663 },
};

const SOURCES = [
  { id: "dexscreener", role: "价格/池子", link: "https://dexscreener.com/" },
  { id: "geckoterminal", role: "价格/池子", link: "https://www.geckoterminal.com/" },
  { id: "ave", role: "行情/跳转", link: "https://ave.ai/" },
  { id: "gmgn", role: "行情/聪明钱/跳转", link: "https://gmgn.ai/" },
  { id: "x", role: "社媒信号/新币线索", link: "https://x.com/" },
  { id: "blockscout", role: "Robinhood 地址/交易/代币页", link: "https://robinhoodchain.blockscout.com/" },
  { id: "goplus", role: "EVM 合约风险", link: "https://gopluslabs.io/" },
  { id: "rugcheck", role: "Solana 风险", link: "https://rugcheck.xyz/" },
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
    pairCreatedAt: best.pairCreatedAt ?? null,
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

// 风险字段说明：只返回上游原值或按原值算的汇总，不编数。
// GoPlus 的 holders[].percent 在实测里是小数（如 0.1837 = 18.37%），
// 所以 top10 汇总时：最大值 <= 1 按小数处理乘 100，否则按已是百分比处理。
function flag(v) { return v === "1" || v === 1 || v === true ? true : v === "0" || v === 0 || v === false ? false : null; }
function num(v) { const n = Number(v); return Number.isFinite(n) ? n : null; }
function top10Pct(holders) {
  if (!Array.isArray(holders) || holders.length === 0) return null;
  const vals = holders.slice(0, 10).map((h) => Number(h.percent)).filter(Number.isFinite);
  if (vals.length === 0) return null;
  const sum = vals.reduce((a, b) => a + b, 0);
  return Math.max(...vals) <= 1 ? sum * 100 : sum;
}

// EVM：GoPlus token_security，免费、无 Key。Robinhood（4663）若 GoPlus 不支持，
// 接口会返回空结果，安全字段保持 null，riskSource 回到 pending，不假装已查。
async function goplusSecurity(chain, address) {
  const chainId = CHAINS[chain].chainId;
  if (!chainId) return null;
  const res = await fetch(`https://api.gopluslabs.io/api/v1/token_security/${chainId}?contract_addresses=${address}`, { headers: { accept: "application/json", "user-agent": "tugou-hanshuang-jiaoben-app/1.0" } });
  if (!res.ok) throw new Error(`goplus_status_${res.status}`);
  const body = await res.json();
  if (body?.code !== 1) throw new Error(`goplus_code_${body?.code ?? "empty"}`);
  const r = body?.result?.[address.toLowerCase()];
  if (!r) throw new Error("goplus_no_result");
  const buyTax = num(r.buy_tax);
  const sellTax = num(r.sell_tax);
  const honeypot = flag(r.is_honeypot);
  const mintable = flag(r.is_mintable);
  const blacklist = flag(r.is_blacklisted);
  const owner = typeof r.owner_address === "string" ? r.owner_address.toLowerCase() : null;
  const renounced = owner ? owner === "0x0000000000000000000000000000000000000000" : null;
  let risk = "green";
  if (honeypot === true || (buyTax !== null && buyTax >= 50) || (sellTax !== null && sellTax >= 50) || flag(r.hidden_owner) === true || flag(r.owner_change_balance) === true || flag(r.selfdestruct) === true) risk = "red";
  else if (mintable === true || blacklist === true || flag(r.transfer_pausable) === true || flag(r.is_proxy) === true || flag(r.slippage_modifiable) === true) risk = "yellow";
  return {
    holders: num(r.holder_count), topHoldersPct: top10Pct(r.holders),
    buyTax, sellTax, honeypot, renounced, mintable, blacklist,
    lpLocked: null, risk, source: "goplus",
    flags: { isProxy: flag(r.is_proxy), hiddenOwner: flag(r.hidden_owner), canTakeBackOwnership: flag(r.can_take_back_ownership), transferPausable: flag(r.transfer_pausable), isOpenSource: flag(r.is_open_source), creatorAddress: r.creator_address ?? null },
  };
}

// EVM 兜底：GoPlus 从 Worker 出口 IP 返回 4029 时（直接查同一地址返回 code 1，
// 说明是上游对 Worker 出口 IP 的限流/拦截，不是映射写错），改走 honeypot.is。
// 它只给蜜罐、买卖税、持仓人数、开源/代理，增发、黑名单、Top 占比留空，不编数。
async function honeypotSecurity(chain, address) {
  const chainId = CHAINS[chain].chainId;
  if (!chainId) return null;
  const res = await fetch(`https://api.honeypot.is/v2/IsHoneypot?address=${address}&chainID=${chainId}`, { headers: { accept: "application/json", "user-agent": "tugou-hanshuang-jiaoben-app/1.0" } });
  if (!res.ok) throw new Error(`honeypot_status_${res.status}`);
  const r = await res.json();
  if (!r || !r.honeypotResult) return null;
  const honeypot = r.honeypotResult.isHoneypot ?? null;
  const summaryRisk = r.summary?.risk ?? null;
  let risk = null;
  if (honeypot === true) risk = "red";
  else if (summaryRisk === "high") risk = "red";
  else if (summaryRisk === "medium" || (Array.isArray(r.flags) && r.flags.length > 0)) risk = "yellow";
  else if (summaryRisk === "low") risk = "green";
  return {
    holders: num(r.token?.totalHolders), topHoldersPct: null,
    buyTax: num(r.simulationResult?.buyTax), sellTax: num(r.simulationResult?.sellTax),
    honeypot, renounced: null, mintable: null, blacklist: null, lpLocked: null,
    risk, source: "honeypot_is",
    flags: { openSource: r.contractCode?.openSource ?? null, isProxy: r.contractCode?.isProxy ?? null, summaryRisk, simulationSuccess: r.simulationSuccess ?? null },
  };
}

async function evmSecurity(chain, address) {
  try { const s = await goplusSecurity(chain, address); if (s) return s; } catch (e) { /* fall through to honeypot.is, keep original error below if it also fails */ }
  try { const s = await honeypotSecurity(chain, address); if (s) return s; } catch (_) {}
  // 两路都失败时，重新抛 GoPlus 的原始错误，方便 securityError 说清原因。
  return await goplusSecurity(chain, address);
}

// Solana：RugCheck 报告，免费、无 Key。totalHolders 为 0 时是缺失数据，按 null 处理，不返回 0 人。
async function rugcheckSecurity(address) {
  const res = await fetch(`https://api.rugcheck.xyz/v1/tokens/${address}/report`, { headers: { accept: "application/json", "user-agent": "tugou-hanshuang-jiaoben-app/1.0" } });
  if (!res.ok) throw new Error(`rugcheck_status_${res.status}`);
  const r = await res.json();
  if (!r || typeof r !== "object") return null;
  const risks = Array.isArray(r.risks) ? r.risks : [];
  const totalHolders = num(r.totalHolders);
  const lockers = r.lockers && typeof r.lockers === "object" ? Object.keys(r.lockers) : [];
  let risk = null;
  if (r.rugged === true) risk = "red";
  else if (risks.length > 0) risk = "yellow";
  else if (r.score != null || r.score_normalised != null) risk = "green";
  return {
    holders: totalHolders && totalHolders > 0 ? totalHolders : null,
    topHoldersPct: top10Pct(r.topHolders),
    buyTax: null, sellTax: null, honeypot: null,
    renounced: null,
    mintable: r.token?.mintAuthority ? true : r.token?.mintAuthority === null ? false : null,
    blacklist: null,
    lpLocked: lockers.length > 0 ? true : null,
    risk, source: "rugcheck",
    flags: { score: num(r.score), scoreNormalised: num(r.score_normalised), risks, mintAuthority: r.token?.mintAuthority ?? null, freezeAuthority: r.token?.freezeAuthority ?? null, rugged: r.rugged ?? null },
  };
}

// Blockscout：ETH / Base / Robinhood / BSC（BSC 实例若不存在会失败，届时走兜底，不报错）。
const BLOCKSCOUT = { eth: "eth.blockscout.com", base: "base.blockscout.com", robinhood: "robinhoodchain.blockscout.com", bsc: "bsc.blockscout.com" };
const RPC = { eth: "https://eth.llamarpc.com", bsc: "https://bsc-dataseed.binance.org", base: "https://mainnet.base.org" };
const DEAD = "0x000000000000000000000000000000000000dEaD";

async function fetchJson(url) {
  const res = await fetch(url, { headers: { accept: "application/json", "user-agent": "tugou-hanshuang-jiaoben-app/1.0" } });
  if (!res.ok) throw new Error(`upstream_status_${res.status}`);
  return await res.json();
}
function hexToBigInt(hex) {
  if (typeof hex !== "string" || !hex.startsWith("0x")) return null;
  try { return BigInt(hex); } catch (_) { return null; }
}
async function rpcCall(rpcUrl, to, data) {
  const res = await fetch(rpcUrl, { method: "POST", headers: { "content-type": "application/json", accept: "application/json", "user-agent": "tugou-hanshuang-jiaoben-app/1.0" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_call", params: [{ to, data }, "latest"] }) });
  if (!res.ok) return null;
  const body = await res.json();
  return hexToBigInt(body?.result);
}
// LP 销毁占比：只对 V2 式 LP 代币有意义。V3 池没有 LP 代币，totalSupply 调不出来就返回 null，不硬填。
async function rpcLpBurn(chain, pairAddress) {
  const rpcUrl = RPC[chain];
  if (!rpcUrl || !pairAddress) return null;
  const deadBal = await rpcCall(rpcUrl, pairAddress, "0x70a08231" + "000000000000000000000000" + DEAD.slice(2));
  const total = await rpcCall(rpcUrl, pairAddress, "0x18160ddd");
  if (deadBal === null || total === null || total === 0n) return null;
  const pctX100 = Number((deadBal * 10000n) / total) / 100;
  return { lpLocked: pctX100 >= 50, lpBurnedPct: pctX100 };
}

async function blockscoutInfo(chain, address) {
  const host = BLOCKSCOUT[chain];
  if (!host) return null;
  const api = `https://${host}/api`;
  const bsError = { token: null, holders: null, source: null, creation: null };
  let tokenRes = null, holdersRes = null, sourceRes = null, creationRes = null;
  try { tokenRes = await fetchJson(`${api}?module=token&action=getToken&contractaddress=${address}`); } catch (e) { bsError.token = String(e && e.message ? e.message : e); }
  try { holdersRes = await fetchJson(`${api}?module=token&action=getTokenHolders&contractaddress=${address}&page=1&offset=10`); } catch (e) { bsError.holders = String(e && e.message ? e.message : e); }
  try { sourceRes = await fetchJson(`${api}?module=contract&action=getsourcecode&address=${address}`); } catch (e) { bsError.source = String(e && e.message ? e.message : e); }
  try { creationRes = await fetchJson(`${api}?module=contract&action=getcontractcreation&contractaddresses=${address}`); } catch (e) { bsError.creation = String(e && e.message ? e.message : e); }
  if (!tokenRes && !holdersRes && !sourceRes && !creationRes) throw new Error(`blockscout_v1_token_${bsError.token}_holders_${bsError.holders}_source_${bsError.source}_creation_${bsError.creation}`);
  let topHoldersPct = null;
  try {
    const total = tokenRes?.result?.totalSupply ? BigInt(String(tokenRes.result.totalSupply)) : 0n;
    const items = Array.isArray(holdersRes?.result) ? holdersRes.result.slice(0, 10) : [];
    if (total > 0n && items.length > 0) {
      let sum = 0n;
      for (const it of items) { try { sum += BigInt(String(it.value)); } catch (_) {} }
      topHoldersPct = Number((sum * 10000n) / total) / 100;
    }
  } catch (_) {}
  let sourceScan = null;
  try {
    const src = typeof sourceRes?.result?.[0]?.SourceCode === "string" ? sourceRes.result[0].SourceCode.toLowerCase() : "";
    if (src && src.length > 50) {
      sourceScan = { verified: true, mintable: /function\s+(mint|issue)\s*\(/.test(src), blacklist: /blacklist|black_list|isblacklisted/.test(src), isProxy: sourceRes.result[0].IsProxy === "true" };
    }
  } catch (_) {}
  let creatorHistory = null;
  try {
    const c = creationRes?.result?.[0];
    if (c?.contractCreator) creatorHistory = { creatorAddress: c.contractCreator, creationTxHash: c.txHash ?? null, creationTimestamp: c.timestamp ? Number(c.timestamp) : null };
  } catch (_) {}
  return { holders: null, topHoldersPct, mintable: sourceScan ? sourceScan.mintable : null, blacklist: sourceScan ? sourceScan.blacklist : null, creatorHistory, sourceScan, bsError };
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
      let dexPrice = await cached(env, `token:${chain}:${address.toLowerCase()}`, () => dexToken(chain, address));
      if (!dexPrice) dexPrice = await dexToken(chain, address);
      let price = dexPrice || (await geckoToken(chain, address));
      if (!price) price = await geckoToken(chain, address);
      let security = null;
      let securityError = null;
      try { security = chain === "solana" ? await rugcheckSecurity(address) : await evmSecurity(chain, address); if (!security) securityError = "upstream_empty"; } catch (e) { security = null; securityError = String(e && e.message ? e.message : e); }
      let bs = null;
      let bsError = null;
      let lpBurn = null;
      if (chain !== "solana") {
        try { bs = await blockscoutInfo(chain, address); } catch (e) { bs = null; bsError = String(e && e.message ? e.message : e); }
        if (bs) {
          if (!security) security = { holders: null, topHoldersPct: null, buyTax: null, sellTax: null, honeypot: null, renounced: null, mintable: null, blacklist: null, lpLocked: null, risk: null, source: "blockscout", flags: {} };
          if (security.holders == null && bs.holders != null) security.holders = bs.holders;
          if (security.topHoldersPct == null && bs.topHoldersPct != null) security.topHoldersPct = bs.topHoldersPct;
          if (security.mintable == null && bs.mintable != null) security.mintable = bs.mintable;
          if (security.blacklist == null && bs.blacklist != null) security.blacklist = bs.blacklist;
          security.flags = { ...(security.flags || {}), blockscout: { topHoldersPct: bs.topHoldersPct, sourceScan: bs.sourceScan, bsError: bs.bsError } };
          if (security.risk == null && (bs.mintable != null || bs.blacklist != null)) security.risk = bs.blacklist === true ? "yellow" : bs.mintable === true ? "yellow" : "green";
          if (security.source === "blockscout") securityError = null;
        }
        try { lpBurn = await rpcLpBurn(chain, price?.pairAddress); } catch (_) { lpBurn = null; }
        if (lpBurn && security && security.lpLocked == null) { security.lpLocked = lpBurn.lpLocked; security.flags = { ...(security.flags || {}), lpBurnedPct: lpBurn.lpBurnedPct }; }
      }
      const poolAge = price?.pairCreatedAt ? Math.round(((Date.now() - Number(price.pairCreatedAt)) / 86400000) * 10) / 10 : null;
      return json({
        chain, address,
        price,
        // 第二阶段再接，不编数据：
        holders: security?.holders ?? null, topHoldersPct: security?.topHoldersPct ?? null,
        buyTax: security?.buyTax ?? null, sellTax: security?.sellTax ?? null,
        honeypot: security?.honeypot ?? null, renounced: security?.renounced ?? null,
        mintable: security?.mintable ?? null, blacklist: security?.blacklist ?? null,
        lpLocked: security?.lpLocked ?? null, poolAge, creatorHistory: bs?.creatorHistory ?? null,
        risk: security?.risk ?? null, riskSource: security?.source ?? "pending",
        security: security ? { source: security.source, flags: security.flags } : null,
        securityError, bsError,
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
