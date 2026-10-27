// 土狗寒霜脚本app - Cloudflare Worker 统一网关（第一阶段脚手架）
// 原则：App 和小组件只读这里的 JSON，不直连上游；Secrets 只从 env 读，绝不写进代码。
// 链适配器只做映射，不按链重做一套。

const CHAINS = {
  bsc: { dex: "bsc", gecko: "bsc", evm: true, chainId: 56 },
  eth: { dex: "ethereum", gecko: "eth", evm: true, chainId: 1 },
  base: { dex: "base", gecko: "base", evm: true, chainId: 8453 },
  solana: { dex: "solana", gecko: "solana", evm: false, chainId: null },
  robinhood: { dex: "robinhood", gecko: "robinhood", evm: true, chainId: 4663 },
  arbitrum: { dex: "arbitrum", gecko: "arbitrum", evm: true, chainId: 42161 },
  optimism: { dex: "optimism", gecko: "optimism", evm: true, chainId: 10 },
  polygon: { dex: "polygon", gecko: "polygon", evm: true, chainId: 137 },
  okc: { dex: "okc", gecko: "okc", evm: true, chainId: 66 },
  xlayer: { dex: "xlayer", gecko: "x-layer", evm: true, chainId: 196 },
};

const SOURCES = [
  { id: "dexscreener", role: "价格/池子", link: "https://dexscreener.com/" },
  { id: "geckoterminal", role: "价格/池子", link: "https://www.geckoterminal.com/" },
  { id: "ave", role: "行情/跳转", link: "https://ave.ai/" },
  { id: "gmgn", role: "行情/聪明钱/跳转", link: "https://gmgn.ai/" },
  { id: "x", role: "社媒信号/新币线索", link: "https://x.com/" },
  { id: "blockscout", role: "Pro 统一接口：持仓/Top10/创建者（ETH、Arbitrum、Optimism、Robinhood；Base、Polygon、Sc 回 402、BSC 无 Blockscout 实例回 404）", link: "https://api.blockscout.com/" },
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
  const sorted = pairs.sort((a, b) => (b.liquidity?.usd || 0) - (a.liquidity?.usd || 0));
  const best = sorted[0];
  const sum = (fn) => sorted.reduce((a, p) => a + (Number(fn(p)) || 0), 0);
  return {
    name: best.baseToken?.name ?? null,
    symbol: best.baseToken?.symbol ?? null,
    priceUsd: best.priceUsd ? Number(best.priceUsd) : null,
    liquidityUsd: best.liquidity?.usd ?? null,
    liquidityBase: best.liquidity?.base ?? null,
    liquidityQuote: best.liquidity?.quote ?? null,
    baseTokenAddress: best.baseToken?.address ?? null,
    quoteTokenAddress: best.quoteToken?.address ?? null,
    quoteTokenSymbol: best.quoteToken?.symbol ?? null,
    volume24hUsd: best.volume?.h24 ?? null,
    totalVolume24hUsd: sum((p) => p.volume?.h24),
    totalLiquidityUsd: sum((p) => p.liquidity?.usd),
    priceChange5mPct: best.priceChange?.m5 ?? null,
    priceChange1hPct: best.priceChange?.h1 ?? null,
    priceChange24hPct: best.priceChange?.h24 ?? null,
    txns5m: best.txns?.m5 ?? null,
    txns1h: best.txns?.h1 ?? null,
    txns24h: best.txns?.h24 ?? null,
    pairAddress: best.pairAddress ?? null,
    pairCreatedAt: best.pairCreatedAt ?? null,
    dexId: best.dexId ?? null,
    labels: best.labels ?? null,
    boostsActive: best.boosts?.active ?? null,
    source: "dexscreener",
    allPairs: sorted.slice(0, 5).map((q) => ({ pairAddress: q.pairAddress ?? null, dexId: q.dexId ?? null, labels: q.labels ?? null, priceUsd: q.priceUsd ? Number(q.priceUsd) : null, liquidityUsd: q.liquidity?.usd ?? null, volume24hUsd: q.volume?.h24 ?? null, pairCreatedAt: q.pairCreatedAt ?? null, baseTokenSymbol: q.baseToken?.symbol ?? null, quoteTokenSymbol: q.quoteToken?.symbol ?? null })),
  };
}

// Dexscreener 付费推广：orders（付费广告/增强信息订单）+ boosts（付费 Boost），免费公开接口，无 Key
// 只能覆盖 Dexscreener 这一家；X/Telegram/KOL 付费、Ave/GMGN 付费置顶没有公开免费接口，不编
async function dexOrders(chain, address) {
  const url = `https://api.dexscreener.com/orders/v1/${CHAINS[chain].dex}/${address}`;
  const res = await fetch(url, { headers: { accept: "application/json" } });
  if (!res.ok) throw new Error(`dex_orders_status_${res.status}`);
  return await res.json();
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

async function geckoPair(chain, address) {
  try {
    const url = `https://api.geckoterminal.com/api/v2/networks/${CHAINS[chain].gecko}/tokens/${address}`;
    const res = await fetch(url, { headers: { accept: "application/json" } });
    if (!res.ok) return null;
    const body = await res.json();
    const id = body?.data?.relationships?.top_pools?.data?.[0]?.id;
    if (!id) return null;
    const addr = String(id).split("_").pop();
    return /^0x[0-9a-fA-F]{40}$/.test(addr) ? addr : null;
  } catch (_) { return null; }
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
const BLOCKSCOUT = { eth: "eth.blockscout.com", base: "base.blockscout.com", robinhood: "robinhoodchain.blockscout.com", bsc: "bsc.blockscout.com", arbitrum: "arb.blockscout.com", optimism: "optimism.blockscout.com", polygon: "polygon.blockscout.com" };
const RPC = { eth: "https://eth.llamarpc.com", bsc: "https://bsc-dataseed.binance.org", base: "https://mainnet.base.org", arbitrum: "https://arb1.arbitrum.io/rpc", optimism: "https://mainnet.optimism.io", polygon: "https://polygon-rpc.com", okc: "https://exchainrpc.okex.org", xlayer: "https://rpc.xlayer.tech" };
const RPC_URLS = {
  eth: ["https://cloudflare-eth.com", "https://ethereum.publicnode.com", "https://eth.llamarpc.com", "https://rpc.ankr.com/eth"],
  bsc: ["https://bsc-dataseed.binance.org", "https://bsc-dataseed1.bnbchain.org", "https://bsc-dataseed2.bnbchain.org", "https://bsc.publicnode.com"],
  base: ["https://rpc.ankr.com/base", "https://base.llamarpc.com", "https://base-mainnet.public.blastapi.io", "https://1rpc.io/base", "https://mainnet.base.org", "https://base.publicnode.com"],
  arbitrum: ["https://arb1.arbitrum.io/rpc", "https://arbitrum.publicnode.com"],
  optimism: ["https://mainnet.optimism.io", "https://optimism.publicnode.com"],
  polygon: ["https://polygon-rpc.com", "https://polygon.publicnode.com"],
  okc: ["https://exchainrpc.okex.org", "https://oktc-mainnet.public.blastapi.io"],
  xlayer: ["https://rpc.xlayer.tech", "https://xlayer-mainnet.public.blastapi.io"],
};
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
  const urls = Array.isArray(rpcUrl) ? rpcUrl : [rpcUrl];
  for (const u of urls) {
    try {
      const res = await fetch(u, { method: "POST", headers: { "content-type": "application/json", accept: "application/json", "user-agent": "tugou-hanshuang-jiaoben-app/1.0" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_call", params: [{ to, data }, "latest"] }) });
      if (!res.ok) continue;
      const body = await res.json();
      const v = hexToBigInt(body?.result);
      if (v !== null) return v;
    } catch (_) {}
  }
  return null;
}
// LP 销毁占比：只对 V2 式 LP 代币有意义。V3 池没有 LP 代币，totalSupply 调不出来就返回 null，不硬填。
async function rpcLpBurn(chain, pairAddress) {
  const urls = RPC_URLS[chain] || (RPC[chain] ? [RPC[chain]] : []);
  if (!urls.length || !pairAddress) return null;
  const deadBal = await rpcCall(urls, pairAddress, "0x70a08231" + "000000000000000000000000" + DEAD.slice(2));
  const total = await rpcCall(urls, pairAddress, "0x18160ddd");
  if (deadBal === null || total === null || total === 0n) return null;
  const pctX100 = Number((deadBal * 10000n) / total) / 100;
  return { lpLocked: pctX100 >= 50, lpBurnedPct: pctX100 };
}

// Etherscan V2（免费 Key）：源码扫描 + ETH 创建者。注意免费档限制：持仓列表/代币信息是 Pro 接口，
// Base/BSC 的 getcontractcreation 在免费档返回 Free API access is not supported for this chain，
// 所以 Top10 占比仍不能靠 Etherscan 免费 Key，creatorHistory 也只在 ETH 上能填。
const ETHERSCAN_CHAINID = { eth: "1", bsc: "56", base: "8453", arbitrum: "42161", optimism: "10", polygon: "137", okc: "66", xlayer: "196" };
function scanSource(src) {
  const low = (src || "").toLowerCase();
  if (!low || low.length < 50) return null;
  return { verified: true, mintable: /function\s+(mint|issue)\s*\(/.test(low), blacklist: /blacklist|black_list|isblacklisted/.test(low) };
}
async function etherscanSecurity(env, chain, address) {
  const key = env.ETHERSCAN_API_KEY;
  if (!key) return { error: "missing_env_ETHERSCAN_API_KEY" };
  const chainid = ETHERSCAN_CHAINID[chain];
  if (!chainid) return { error: "etherscan_chain_not_supported" };
  const base = `https://api.etherscan.io/v2/api?chainid=${chainid}&apikey=${encodeURIComponent(key)}`;
  let sourceScan = null, creatorHistory = null, etherscanError = null;
  const crP = fetchJson(`${base}&module=contract&action=getcontractcreation&contractaddresses=${address}`).catch((e) => ({ __error: String(e && e.message ? e.message : e) }));
  try {
    const sc = await fetchJson(`${base}&module=contract&action=getsourcecode&address=${address}`);
    let r = Array.isArray(sc.result) ? sc.result[0] : null;
    let src = r?.SourceCode || "";
    let scannedFrom = "self";
    if (r?.Implementation && r.Implementation.toLowerCase() !== address.toLowerCase()) {
      try {
        const impl = await fetchJson(`${base}&module=contract&action=getsourcecode&address=${r.Implementation}`);
        const ri = Array.isArray(impl.result) ? impl.result[0] : null;
        if (ri?.SourceCode) { src = ri.SourceCode; scannedFrom = "implementation"; }
      } catch (_) {}
    }
    sourceScan = scanSource(src);
    if (sourceScan) sourceScan.scannedFrom = scannedFrom;
    if (sc.status !== "1") etherscanError = `source_${sc.message || sc.result || "unknown"}`;
  } catch (e) { etherscanError = `source_${e && e.message ? e.message : e}`; }
  try {
    const cr = await crP;
    if (cr && cr.__error) { etherscanError = (etherscanError ? etherscanError + ";" : "") + `creation_${cr.__error}`; }
    else {
      const c = Array.isArray(cr.result) ? cr.result[0] : null;
      if (cr.status === "1" && c?.contractCreator) {
        creatorHistory = { creatorAddress: c.contractCreator, creationTxHash: c.txHash ?? null, creationTimestamp: c.timestamp ? Number(c.timestamp) : null };
      } else if (cr.status !== "1") {
        etherscanError = (etherscanError ? etherscanError + ";" : "") + `creation_${cr.message || cr.result || "unknown"}`;
      }
    }
  } catch (e) { etherscanError = (etherscanError ? etherscanError + ";" : "") + `creation_${e && e.message ? e.message : e}`; }
  return { mintable: sourceScan ? sourceScan.mintable : null, blacklist: sourceScan ? sourceScan.blacklist : null, creatorHistory, sourceScan, error: etherscanError };
}
async function rpcOwner(chain, address) {
  const urls = RPC_URLS[chain] || (RPC[chain] ? [RPC[chain]] : []);
  if (!urls.length) return null;
  const res = await rpcCall(urls, address, "0x8da5cb5b");
  if (res === null) return null;
  const hex = res.toString(16).padStart(64, "0");
  if (hex === "0".repeat(64)) return true;
  if (/^[0-9a-f]{64}$/.test(hex) && hex.slice(24) !== "0".repeat(40)) return false;
  return null;
}

const NATIVE_SYMBOL = { eth: "ETH", bsc: "BNB", base: "ETH", arbitrum: "ETH", optimism: "ETH", polygon: "MATIC", robinhood: "ETH", solana: "SOL", okc: "OKT", xlayer: "OKB" };
const NATIVE_WRAPPED = { eth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", bsc: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", base: "0x4200000000000000000000000000000000000006", arbitrum: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1", optimism: "0x4200000000000000000000000000000000000006", polygon: "0x0d500B1d8E8eF5fE704DF2C2B8d8c9e8F1e5e5", xlayer: "0xe538905cf8410324e03a5a23c1c177a474d59b2b" };
async function rpcJson(rpcUrl, method, params) {
  const urls = Array.isArray(rpcUrl) ? rpcUrl : [rpcUrl];
  let lastErr = null;
  for (const u of urls) {
    try {
      const res = await fetch(u, { method: "POST", headers: { "content-type": "application/json", accept: "application/json", "user-agent": "tugou-hanshuang-jiaoben-app/1.0" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
      if (!res.ok) { lastErr = new Error(`rpc_status_${res.status}`); continue; }
      const body = await res.json();
      if (body.error) { lastErr = new Error(`rpc_${body.error.message || "error"}`); continue; }
      return body.result;
    } catch (e) { lastErr = e; }
  }
  throw lastErr || new Error("rpc_no_url");
}
async function evmNativeAmount(chain, address) {
  const urls = RPC_URLS[chain] || (RPC[chain] ? [RPC[chain]] : []);
  if (!urls.length) return null;
  const hex = await rpcJson(urls, "eth_getBalance", [address, "latest"]);
  const v = hexToBigInt(hex);
  return v === null ? null : Number(v) / 1e18;
}
async function evmTokenAmount(chain, tokenAddress, walletAddress) {
  const dec = await rpcCall(RPC_URLS[chain] || RPC[chain], tokenAddress, "0x313ce567");
  const bal = await rpcCall(RPC_URLS[chain] || RPC[chain], tokenAddress, "0x70a08231" + "000000000000000000000000" + walletAddress.slice(2));
  if (bal === null || dec === null) return null;
  return Number(bal) / (10 ** Number(dec));
}
async function solNativeAmount(address) {
  const v = await rpcJson("https://api.mainnet-beta.solana.com", "getBalance", [address]);
  return v && typeof v.value === "number" ? v.value / 1e9 : null;
}
async function solTokenAmount(walletAddress, mint) {
  const res = await rpcJson("https://api.mainnet-beta.solana.com", "getTokenAccountsByOwner", [walletAddress, { mint }, { encoding: "jsonParsed" }]);
  const accounts = res?.value || [];
  let sum = 0;
  for (const a of accounts) { const u = a?.account?.data?.parsed?.info?.tokenAmount?.uiAmount; if (typeof u === "number") sum += u; }
  return accounts.length ? sum : null;
}
async function priceFor(chain, address) {
  let pr = null;
  try { pr = await dexToken(chain, address); } catch (_) {}
  if (!pr) { try { pr = await geckoToken(chain, address); } catch (_) {} }
  return pr;
}

const BLOCKSCOUT_PRO_CHAINID = { eth: "1", arbitrum: "42161", optimism: "10", robinhood: "4663", base: "8453", polygon: "137", bsc: "56", okc: "66", xlayer: "196" };
const TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";
function hexToInt(h) { try { return parseInt(h, 16); } catch (_) { return null; } }
async function rpcJsonChain(chain, method, params) {
  const urls = RPC_URLS[chain] || (RPC[chain] ? [RPC[chain]] : []);
  return rpcJson(urls, method, params);
}
const BLOCK_TIME_SEC = { eth: 12, bsc: 3, base: 2, arbitrum: 1, optimism: 2, polygon: 2, robinhood: 2, okc: 3, xlayer: 2 };
const LOG_RPC = { base: "https://base.publicnode.com", bsc: "https://bsc.publicnode.com", polygon: "https://polygon.publicnode.com", eth: "https://ethereum.publicnode.com", arbitrum: "https://arbitrum.publicnode.com", optimism: "https://optimism.publicnode.com", okc: "https://exchainrpc.okex.org", xlayer: "https://rpc.xlayer.tech" };
const ALCHEMY_BASE = { eth: "https://eth-mainnet.g.alchemy.com/v2/", arbitrum: "https://arb-mainnet.g.alchemy.com/v2/", optimism: "https://opt-mainnet.g.alchemy.com/v2/", base: "https://base-mainnet.g.alchemy.com/v2/", polygon: "https://polygon-mainnet.g.alchemy.com/v2/", bsc: "https://bnb-mainnet.g.alchemy.com/v2/" };
function alchemyUrl(env, chain) {
  const key = env.ALCHEMY_API_KEY;
  const base = ALCHEMY_BASE[chain];
  return key && base ? base + key : null;
}
async function rpcJsonChainSlow(env, chain, method, params) {
  await new Promise((r) => setTimeout(r, 250));
  const alch = env ? alchemyUrl(env, chain) : null;
  if (alch) return rpcJson(alch, method, params);
  const single = LOG_RPC[chain];
  if (single) return rpcJson(single, method, params);
  return rpcJsonChain(chain, method, params);
}
async function blockNumberAtTime(env, chain, tsSec, latest) {
  // 单次取最新块时间戳 + 出块时间估算，留 2000 块余量，不做多次微调，避免子请求超限
  try {
    const latestBlk = await rpcJsonChainSlow(env, chain, "eth_getBlockByNumber", ["0x" + latest.toString(16), false]);
    const latestTs = latestBlk?.timestamp ? hexToInt(latestBlk.timestamp) : null;
    if (latestTs == null) return null;
    const bt = BLOCK_TIME_SEC[chain] || 2;
    const est = latest - Math.floor((latestTs - tsSec) / bt);
    return Math.max(0, est - 2000);
  } catch (_) { return null; }
}
// BSC Four.meme 内盘：代理合约 0x5c952063c7fc8610FFDB798152D69F0B9550762b 的持仓即内盘剩余量
// 总量 1B，进度 = 100 - ((余额 - 200M) * 100 / 800M)；余额 0 = 非 Four.meme 或已毕业（看外盘对是否存在区分）
async function fourInternal(chain, address) {
  if (chain !== "bsc") return null;
  try {
    const proxy = "0x5c952063c7fc8610FFDB798152D69F0B9550762b";
    const balHex = await rpcCall(RPC_URLS[chain] || [], address, "0x70a08231" + "000000000000000000000000" + proxy.slice(2));
    const decHex = await rpcCall(RPC_URLS[chain] || [], address, "0x313ce567");
    if (balHex === null) return { platform: "four.meme", status: "unknown", error: "rpc_no_balance" };
    const dec = decHex !== null ? Number(decHex) : 18;
    const balTokens = Number(balHex) / (10 ** dec);
    if (balTokens > 200000000 && balTokens <= 1050000000) {
      const progress = Math.round((100 - ((balTokens - 200000000) * 100 / 800000000)) * 100) / 100;
      return { platform: "four.meme", status: "internal", balanceTokens: balTokens, progressPct: progress };
    }
    return { platform: "four.meme", status: "external_or_not_four", balanceTokens: balTokens, progressPct: null };
  } catch (e) { return { platform: "four.meme", status: "unknown", error: String(e && e.message ? e.message : e) }; }
}

async function lpInfoAlchemy(env, chain, pairAddress) {
  const out = { lpLocked: null, lpBurnPct: null, lpTopHolder: null, lpTopHolderPct: null, lpTopHolderIsContract: null, lpError: null };
  const alchUrl = env ? alchemyUrl(env, chain) : null;
  if (!alchUrl || !pairAddress) { out.lpError = alchUrl ? "no_pair" : "no_alchemy_key"; return out; }
  if (!/^0x[0-9a-fA-F]{40}$/.test(pairAddress)) { out.lpError = "v4_pool_id_no_lp_token"; return out; }
  try {
    const balOf = async (holder) => {
      const h = holder.slice(2).padStart(64, "0");
      const b = await rpcJson(alchUrl, "eth_call", [{ to: pairAddress, data: "0x70a08231" + h }, "latest"]);
      return b ? BigInt(b) : 0n;
    };
    const [totalHex, zeroBal, deadBal] = await Promise.all([rpcJson(alchUrl, "eth_call", [{ to: pairAddress, data: "0x18160ddd" }, "latest"]).catch(() => null), balOf("0x0000000000000000000000000000000000000000").catch(() => 0n), balOf("0x000000000000000000000000000000000000dEaD").catch(() => 0n)]);
    const total = totalHex ? BigInt(totalHex) : 0n;
    if (total <= 0n) { out.lpError = "v3_or_not_erc20"; return out; }
    out.lpBurnPct = Math.round(Number(((zeroBal + deadBal) * 10000n) / total) / 100 * 100) / 100;
    out.lpLocked = out.lpBurnPct >= 50;
    // LP 持仓分布：getAssetTransfers 按 LP 合约过滤，V2 新币通常只有几笔到几百笔
    let pageKey = null, all = [], complete = true;
    for (let pg = 0; pg < 10; pg++) {
      const params = [{ fromBlock: "0x0", toBlock: "latest", contractAddresses: [pairAddress], category: ["erc20"], maxCount: "0x3e8", withMetadata: false, order: "asc" }];
      if (pageKey) params[0].pageKey = pageKey;
      const res = await rpcJson(alchUrl, "alchemy_getAssetTransfers", params);
      const trs = res?.transfers || [];
      all = all.concat(trs);
      pageKey = res?.pageKey || null;
      if (!pageKey) break;
      if (all.length > 10000) { complete = false; break; }
    }
    if (!complete) { out.lpError = "lp_transfers_cap"; return out; }
    const bals = new Map();
    for (const tr of all) {
      const v = Number(tr.value || 0);
      if (!v) continue;
      const f = String(tr.from).toLowerCase(), to = String(tr.to).toLowerCase();
      bals.set(f, (bals.get(f) || 0) - v);
      bals.set(to, (bals.get(to) || 0) + v);
    }
    const vals = [...bals.entries()].filter(([, v]) => v > 0).sort((a, b) => b[1] - a[1]);
    if (vals.length > 0) {
      const [topAddr, topVal] = vals[0];
      let dec = 18;
      try {
        const decHex = await rpcJson(alchUrl, "eth_call", [{ to: pairAddress, data: "0x313ce567" }, "latest"]);
        if (decHex) dec = parseInt(decHex, 16);
      } catch (_) {}
      const totalFloat = Number(total) / (10 ** dec);
      out.lpTopHolder = topAddr;
      out.lpTopHolderPct = totalFloat > 0 ? Math.round((topVal / totalFloat) * 10000) / 100 : null;
      try {
        const code = await rpcJson(alchUrl, "eth_getCode", [topAddr, "latest"]);
        out.lpTopHolderIsContract = !!(code && code !== "0x");
      } catch (_) {}
    }
  } catch (e) {
    const msg = String(e && e.message ? e.message : e);
    out.lpError = /revert|execution reverted|invalid opcode/i.test(msg) ? "v3_or_not_erc20" : msg;
  }
  return out;
}

async function evmLogScan(env, chain, address, pairCreatedAtMs) {
  // 链上 Transfer 日志聚合：只给土狗用。大币（转账数超上限）返回 partial，不编一个假 Top10。
  // 返回：{ topHoldersPct, holders, logScanComplete, scannedLogs, creatorHistory, logScanError }
  const out = { topHoldersPct: null, holders: null, realHolders: null, logScanComplete: false, scannedLogs: 0, creatorHistory: null, logScanError: null };
  try {
    const latestHex = await rpcJsonChainSlow(env, chain, "eth_blockNumber", []);
    const latest = hexToInt(latestHex);
    if (latest == null) { out.logScanError = "rpc_no_latest_block"; return out; }
    // 起始块：优先用池子创建时间前 7 天，否则用最新块前 200 万块（约 Base 46 天、BSC 23 天、Polygon 46 天）
    let startBlock = null;
    if (pairCreatedAtMs) {
      const ts = Math.floor(Number(pairCreatedAtMs) / 1000) - 6 * 3600;
      startBlock = await blockNumberAtTime(env, chain, ts, latest);
    }
    if (startBlock == null) startBlock = Math.max(0, latest - 2000000);
    const MAX_LOGS = 10000;
    const balances = new Map();
    let totalLogs = 0, complete = false, firstLogBlock = null;
    const alchUrl = env ? alchemyUrl(env, chain) : null;
    if (alchUrl) {
      try {
        let pageKey = null, all = [];
        for (let pg = 0; pg < 10; pg++) {
          const params = [{ fromBlock: "0x" + startBlock.toString(16), toBlock: "0x" + latest.toString(16), contractAddresses: [address], category: ["erc20"], maxCount: "0x3e8", withMetadata: false, order: "asc" }];
          if (pageKey) params[0].pageKey = pageKey;
          const res = await rpcJson(alchUrl, "alchemy_getAssetTransfers", params);
          const trs = res?.transfers || [];
          all = all.concat(trs);
          pageKey = res?.pageKey || null;
          if (!pageKey || all.length > MAX_LOGS) break;
        }
        out.scannedLogs = all.length;
        out.logScanComplete = !pageKey && all.length <= MAX_LOGS;
        if (!out.logScanComplete) out.logScanError = "log_cap_exceeded";
        if (out.logScanComplete && all.length > 0) {
          const bals = new Map();
          for (const tr of all) {
            const v = Number(tr.value || 0);
            if (!v) continue;
            bals.set(String(tr.from).toLowerCase(), (bals.get(String(tr.from).toLowerCase()) || 0) - v);
            bals.set(String(tr.to).toLowerCase(), (bals.get(String(tr.to).toLowerCase()) || 0) + v);
          }
          const vals = [...bals.values()].filter((v) => v > 0).sort((a, b) => b - a);
          out.holders = vals.length;
          const exclude = new Set(["0x0000000000000000000000000000000000000000", "0x000000000000000000000000000000000000dead", String(address).toLowerCase()]);
          out.realHolders = [...bals.entries()].filter(([a, v]) => v > 0 && !exclude.has(String(a).toLowerCase())).length;
          try {
            const totalHex = await rpcJson(alchUrl, "eth_call", [{ to: address, data: "0x18160ddd" }, "latest"]);
            const decHex = await rpcJson(alchUrl, "eth_call", [{ to: address, data: "0x313ce567" }, "latest"]);
            const dec = decHex ? parseInt(decHex, 16) : 18;
            const total = Number(BigInt(totalHex || "0x0")) / (10 ** dec);
            if (total > 0) out.topHoldersPct = Math.round((vals.slice(0, 10).reduce((a, b) => a + b, 0) / total) * 10000) / 100;
          } catch (_) {}
          const first = all[0];
          if (first?.blockNum) {
            try {
              const fb = parseInt(first.blockNum, 16);
              for (let b = fb; b < fb + 3; b++) {
                const blk = await rpcJson(alchUrl, "eth_getBlockByNumber", ["0x" + b.toString(16), true]);
                let found = false;
                for (const tx of blk?.transactions || []) {
                  if (tx.hash && String(tx.hash).toLowerCase() === String(first.hash).toLowerCase()) {
                    const rc = await rpcJson(alchUrl, "eth_getTransactionReceipt", [tx.hash]);
                    if (rc?.contractAddress && String(rc.contractAddress).toLowerCase() === address.toLowerCase()) {
                      out.creatorHistory = { creatorAddress: tx.from, creationTxHash: tx.hash, creationTimestamp: blk?.timestamp ? parseInt(blk.timestamp, 16) : null };
                      found = true; break;
                    }
                  }
                }
                if (found) break;
              }
            } catch (_) {}
          }
        }
        return out;
      } catch (e) { out.logScanError = String(e && e.message ? e.message : e); return out; }
    }
    let from = startBlock, chunk = chain === "okc" ? 2000 : chain === "xlayer" ? 500 : 50000, calls = 0;
    while (from <= latest && calls < 20) {
      const to = Math.min(latest, from + chunk - 1);
      let logs;
      try {
        logs = await rpcJsonChainSlow(env, chain, "eth_getLogs", [{ address, fromBlock: "0x" + from.toString(16), toBlock: "0x" + to.toString(16), topics: [TRANSFER_TOPIC] }]);
      } catch (e) {
        const msg = String(e && e.message ? e.message : e);
        if (/exceed|too many|max results|span|less than|range|limit|400/i.test(msg) && chunk > 100) { chunk = Math.max(100, Math.floor(chunk / 4)); continue; }
        out.logScanError = msg; break;
      }
      calls++;
      if (!Array.isArray(logs)) break;
      totalLogs += logs.length;
      if (firstLogBlock == null && logs.length > 0) firstLogBlock = hexToInt(logs[0].blockNumber);
      for (const log of logs) {
        try {
          const fromA = "0x" + (log.topics?.[1] || "").slice(-40);
          const toA = "0x" + (log.topics?.[2] || "").slice(-40);
          const val = BigInt(log.data || "0x0");
          if (val === 0n) continue;
          balances.set(fromA, (balances.get(fromA) || 0n) - val);
          balances.set(toA, (balances.get(toA) || 0n) + val);
        } catch (_) {}
      }
      if (totalLogs > MAX_LOGS) { out.logScanError = "log_cap_exceeded"; break; }
      from = to + 1;
      if (to >= latest) { complete = true; break; }
      if (chunk < 50000) chunk = Math.min(50000, chunk * 2);
    }
    if (!complete && !out.logScanError && calls >= 20) out.logScanError = "log_call_cap_exceeded";
    out.scannedLogs = totalLogs;
    out.logScanComplete = complete && !out.logScanError;
    if (out.logScanComplete && balances.size > 0) {
      // 总供应走 RPC，失败则 Top10 算不出，不编数
      try {
        const totalHex = await rpcJsonChainSlow(env, chain, "eth_call", [{ to: address, data: "0x18160ddd" }, "latest"]);
        const total = totalHex ? BigInt(totalHex) : 0n;
        if (total > 0n) {
          const vals = [...balances.values()].filter((v) => v > 0n).sort((a, b) => (a > b ? -1 : a < b ? 1 : 0));
          out.holders = vals.length;
          let sum = 0n;
          for (const v of vals.slice(0, 10)) sum += v;
          out.topHoldersPct = Number((sum * 10000n) / total) / 100;
        }
      } catch (_) {}
    }
    // 创建者：取首笔 Transfer 所在区块，找 to 为空且 receipt 合约地址等于本币的交易
    if (firstLogBlock != null) {
      try {
        for (let b = firstLogBlock; b < firstLogBlock + 3; b++) {
          const blk = await rpcJsonChainSlow(env, chain, "eth_getBlockByNumber", ["0x" + b.toString(16), true]);
          const txs = blk?.transactions || [];
          let found = false;
          for (const tx of txs) {
            if (tx.to != null) continue;
            try {
              const rc = await rpcJsonChainSlow(env, chain, "eth_getTransactionReceipt", [tx.hash]);
              if (rc?.contractAddress && String(rc.contractAddress).toLowerCase() === address.toLowerCase()) {
                let ts = null;
                try { ts = blk?.timestamp ? hexToInt(blk.timestamp) : null; } catch (_) {}
                out.creatorHistory = { creatorAddress: tx.from, creationTxHash: tx.hash, creationTimestamp: ts };
                found = true; break;
              }
            } catch (_) {}
          }
          if (found) break;
        }
      } catch (_) {}
    }
  } catch (e) { out.logScanError = String(e && e.message ? e.message : e); }
  return out;
}

async function blockscoutProInfo(env, chain, address) {
  const key = env.BLOCKSCOUT_API_KEY;
  if (!key) return { error: "missing_env_BLOCKSCOUT_API_KEY" };
  const cid = BLOCKSCOUT_PRO_CHAINID[chain];
  if (!cid) return { error: "blockscout_pro_chain_not_supported" };
  const base = `https://api.blockscout.com/${cid}/api/v2`;
  const err = {};
  let token = null, holders = null, addr = null;
  const [tokenR, holdersR, addrR] = await Promise.allSettled([fetchJson(`${base}/tokens/${address}?apikey=${key}`), fetchJson(`${base}/tokens/${address}/holders?apikey=${key}`), fetchJson(`${base}/addresses/${address}?apikey=${key}`)]);
  token = tokenR.status === "fulfilled" ? tokenR.value : null;
  holders = holdersR.status === "fulfilled" ? holdersR.value : null;
  addr = addrR.status === "fulfilled" ? addrR.value : null;
  if (tokenR.status === "rejected") err.token = String(tokenR.reason && tokenR.reason.message ? tokenR.reason.message : tokenR.reason);
  if (holdersR.status === "rejected") err.holders = String(holdersR.reason && holdersR.reason.message ? holdersR.reason.message : holdersR.reason);
  if (addrR.status === "rejected") err.address = String(addrR.reason && addrR.reason.message ? addrR.reason.message : addrR.reason);
  if (!token && !holders && !addr) throw new Error(`blockscout_pro_token_${err.token}_holders_${err.holders}_address_${err.address}`);
  let topHoldersPct = null;
  try {
    const total = token?.total_supply ? BigInt(String(token.total_supply)) : 0n;
    const items = Array.isArray(holders?.items) ? holders.items.slice(0, 10) : [];
    if (total > 0n && items.length > 0) {
      let sum = 0n;
      for (const it of items) { try { sum += BigInt(String(it.value)); } catch (_) {} }
      topHoldersPct = Number((sum * 10000n) / total) / 100;
    }
  } catch (_) {}
  let creatorHistory = null;
  try {
    if (addr?.creator_address_hash) {
      let ts = null;
      if (addr.creation_transaction_hash) {
        try { const tx = await fetchJson(`${base}/transactions/${addr.creation_transaction_hash}?apikey=${key}`); if (tx?.timestamp) ts = Math.floor(new Date(tx.timestamp).getTime() / 1000); } catch (_) {}
      }
      creatorHistory = { creatorAddress: addr.creator_address_hash, creationTxHash: addr.creation_transaction_hash ?? null, creationTimestamp: ts };
    }
  } catch (_) {}
  return {
    holders: token?.holders_count != null ? Number(token.holders_count) : null,
    totalSupply: token?.total_supply ?? null,
    topHoldersPct, creatorHistory, bsProError: err,
  };
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

    if (path === "/api/cache-test") {
      try {
        if (!env.CACHE_KV) return json({ kv: false });
        const hit = await env.CACHE_KV.get("cache-test");
        if (hit) return json({ hit: true, body: hit });
        await env.CACHE_KV.put("cache-test", "hello-cache", { expirationTtl: 60 });
        return json({ hit: false, put: true });
      } catch (e) { return json({ error: String(e && e.message ? e.message : e) }); }
    }

    if (path === "/health") return json({ ok: true, service: "tugou-hanshuang-jiaoben-app" });
    if (path === "/api/sources") return json({ sources: SOURCES });

    if (path === "/api/token-fast" && request.method === "GET") {
      const chain = (url.searchParams.get("chain") || "").toLowerCase();
      const address = url.searchParams.get("address") || "";
      if (!CHAINS[chain]) return json({ error: "unknown_chain", chain }, 400);
      if (!isValidAddress(chain, address)) return json({ error: "invalid_address", chain }, 400);
      const t0 = Date.now();
      const withTimeout = (pr, ms) => Promise.race([pr, new Promise((_, rej) => setTimeout(() => rej(new Error(`timeout_${ms}ms`)), ms))]);
      const [dexR, geckoR] = await Promise.allSettled([withTimeout(dexToken(chain, address), 800), withTimeout(geckoToken(chain, address), 800)]);
      const dexPrice = dexR.status === "fulfilled" ? dexR.value : null;
      const geckoPrice = geckoR.status === "fulfilled" ? geckoR.value : null;
      const price = dexPrice || geckoPrice;
      const poolAge = price?.pairCreatedAt ? Math.round(((Date.now() - Number(price.pairCreatedAt)) / 86400000) * 10) / 10 : null;
      return json({ chain, address, fast: true, price, poolAge, txns24h: price?.txns24h ?? null, totalVolume24hUsd: price?.totalVolume24hUsd ?? null, allPairs: price?.allPairs ?? null, priceDexUsd: dexPrice?.priceUsd ?? null, priceGeckoUsd: geckoPrice?.priceUsd ?? null, queryTimeMs: Date.now() - t0, note: "快价只含价格/流动性/量/买卖笔数/池龄，完整体检走 /api/token" });
    }

    if (path === "/api/token" && request.method === "GET") {
      const chain = (url.searchParams.get("chain") || "").toLowerCase();
      const address = url.searchParams.get("address") || "";
      if (!CHAINS[chain]) return json({ error: "unknown_chain", chain }, 400);
      if (!isValidAddress(chain, address)) return json({ error: "invalid_address", chain }, 400);
      try {
        if (env.CACHE_KV) {
          const hit = await env.CACHE_KV.get(`tokenfull:${chain}:${address.toLowerCase()}`);
          if (hit) { const hb = JSON.parse(hit); hb.cached = true; hb.queryTimeMs = 0; return json(hb); }
        }
      } catch (_) {}
      const t0 = Date.now();
      // 第一波并行：同一链同一合约，价格、安全、Pro、Etherscan 同时查，秒级返回，不串行等、不只信单源
      const withTimeout = (pr, ms) => Promise.race([pr, new Promise((_, rej) => setTimeout(() => rej(new Error(`timeout_${ms}ms`)), ms))]);
      const settled = (pr) => withTimeout(pr, 10000).then((v) => ({ ok: true, v }), (e) => ({ ok: false, error: String(e && e.message ? e.message : e) }));
      const dexP = settled(cached(env, `token:${chain}:${address.toLowerCase()}`, () => dexToken(chain, address)));
      const geckoP = settled(geckoToken(chain, address));
      const goplusP = chain === "solana" ? Promise.resolve({ ok: false, error: "solana_no_goplus" }) : settled(goplusSecurity(chain, address));
      const honeypotP = chain === "solana" ? Promise.resolve({ ok: false, error: "solana_no_honeypot" }) : settled(honeypotSecurity(chain, address));
      const rugP = chain === "solana" ? settled(rugcheckSecurity(address)) : Promise.resolve({ ok: false, error: "evm_no_rugcheck" });
      const proP = chain === "solana" ? Promise.resolve({ ok: false, error: "solana_no_pro" }) : settled(blockscoutProInfo(env, chain, address));
      const esP = chain === "solana" ? Promise.resolve({ ok: false, error: "solana_no_etherscan" }) : settled(etherscanSecurity(env, chain, address));
      const ordersP = settled(dexOrders(chain, address));
      const [dexR, geckoR, goplusR, honeypotR, rugR, proR, esR, ordersR] = await Promise.all([dexP, geckoP, goplusP, honeypotP, rugP, proP, esP, ordersP]);
      const ordersData = ordersR.ok ? ordersR.v : null;
      const ordersList = Array.isArray(ordersData?.orders) ? ordersData.orders : null;
      const boostsList = Array.isArray(ordersData?.boosts) ? ordersData.boosts : null;
      const paidPromotion = { orders: ordersList, boosts: boostsList, hasPaidPromotion: (ordersList && ordersList.length > 0) || (boostsList && boostsList.length > 0), orderTypes: ordersList ? [...new Set(ordersList.map((o) => o.type).filter(Boolean))] : null, orderStatuses: ordersList ? [...new Set(ordersList.map((o) => o.status).filter(Boolean))] : null, boostsActive: (dexR.ok && dexR.v ? dexR.v.boostsActive ?? null : null), source: "dexscreener_orders", error: ordersR.ok ? null : (ordersR.error || null), note: "只覆盖 Dexscreener 付费推广（Boost 与付费订单），X/Telegram/KOL 付费与 Ave/GMGN 付费置顶无公开免费接口，本字段不覆盖" };
      const dexPrice = dexR.ok ? dexR.v : null;
      const geckoPrice = geckoR.ok ? geckoR.v : null;
      let price = dexPrice || geckoPrice;
      const priceDiscrepancyPct = dexPrice?.priceUsd != null && geckoPrice?.priceUsd != null && dexPrice.priceUsd > 0 ? Math.round(Math.abs(dexPrice.priceUsd - geckoPrice.priceUsd) / dexPrice.priceUsd * 10000) / 100 : null;
      // 安全：GoPlus 与 honeypot 同时出结果，取最保守（蜜罐任一 true 即 true，税取最大值），分歧超过 10% 标出
      let security = null;
      let securityError = null;
      if (chain === "solana") {
        if (rugR.ok && rugR.v) security = rugR.v; else securityError = rugR.error || "upstream_empty";
      } else {
        const gp = goplusR.ok ? goplusR.v : null;
        const hp = honeypotR.ok ? honeypotR.v : null;
        if (gp && hp) {
          security = { ...gp, honeypot: gp.honeypot === true || hp.honeypot === true, buyTax: Math.max(gp.buyTax ?? 0, hp.buyTax ?? 0), sellTax: Math.max(gp.sellTax ?? 0, hp.sellTax ?? 0), source: "goplus+honeypot", flags: { ...(gp.flags || {}), honeypot_is: { buyTax: hp.buyTax, sellTax: hp.sellTax, honeypot: hp.honeypot }, securityDiscrepancy: Math.abs((gp.buyTax ?? 0) - (hp.buyTax ?? 0)) > 10 || Math.abs((gp.sellTax ?? 0) - (hp.sellTax ?? 0)) > 10 || gp.honeypot !== hp.honeypot } };
          if (security.honeypot === true) security.risk = "red";
        } else if (gp) security = gp;
        else if (hp) security = hp;
        else securityError = goplusR.error || honeypotR.error || "upstream_empty";
      }
      let bs = null; let bsError = null; let lpBurn = null;
      let bsPro = null; let bsProError = null;
      if (proR.ok && proR.v) {
        if (proR.v.error) { bsProError = proR.v.error; }
        else {
          bsPro = proR.v;
          if (!security) security = { holders: null, topHoldersPct: null, buyTax: null, sellTax: null, honeypot: null, renounced: null, mintable: null, blacklist: null, lpLocked: null, risk: null, source: "blockscout_pro", flags: {} };
          if (security.holders == null && bsPro.holders != null) security.holders = bsPro.holders;
          if (security.topHoldersPct == null && bsPro.topHoldersPct != null) security.topHoldersPct = bsPro.topHoldersPct;
          security.flags = { ...(security.flags || {}), blockscout_pro: { holders: bsPro.holders, topHoldersPct: bsPro.topHoldersPct, totalSupply: bsPro.totalSupply, bsProError: bsPro.bsProError } };
        }
      } else if (chain !== "solana") { bsProError = proR.error || null; }
      let esCreator = null; let etherscanError = null;
      if (esR.ok && esR.v) {
        const es = esR.v;
        if (es.error) etherscanError = es.error;
        if (es.mintable != null || es.blacklist != null || es.creatorHistory) {
          if (!security) security = { holders: null, topHoldersPct: null, buyTax: null, sellTax: null, honeypot: null, renounced: null, mintable: null, blacklist: null, lpLocked: null, risk: null, source: "etherscan", flags: {} };
          if (security.mintable == null && es.mintable != null) security.mintable = es.mintable;
          if (security.blacklist == null && es.blacklist != null) security.blacklist = es.blacklist;
          if (es.creatorHistory) esCreator = es.creatorHistory;
          security.flags = { ...(security.flags || {}), etherscan: { mintable: es.mintable, blacklist: es.blacklist, sourceScan: es.sourceScan } };
          if (security.risk == null && (es.mintable != null || es.blacklist != null)) security.risk = es.blacklist === true ? "yellow" : es.mintable === true ? "yellow" : "green";
        }
      } else if (chain !== "solana") { etherscanError = esR.error || null; }
      // 第二波并行：日志扫描、LP、总供应、gas 同时查，都依赖价格但彼此独立
      const holdersNum = security?.holders != null ? Number(security.holders) : null;
      const skipLogScan = holdersNum != null && holdersNum > 500000;
      const needLogScan = chain !== "solana" && !skipLogScan && (security?.topHoldersPct == null || (bsPro?.creatorHistory == null && esCreator == null && bs?.creatorHistory == null));
      const logScanP = needLogScan ? Promise.race([evmLogScan(env, chain, address, price?.pairCreatedAt), new Promise((res) => setTimeout(() => res(null), 15000))]).catch(() => null) : Promise.resolve(null);
      const pairP = (async () => {
        if (chain === "solana") return null;
        if (price?.pairAddress) return price.pairAddress;
        try { return await geckoPair(chain, address); } catch (_) { return null; }
      })();
      const supplyP = (async () => {
        try {
          if (chain === "solana") {
            const sup = await rpcJson("https://api.mainnet-beta.solana.com", "getTokenSupply", [address]);
            if (sup?.amount) return { raw: sup.amount, tokens: Number(sup.amount) / (10 ** Number(sup.decimals || 0)) };
          } else {
            const totHex = await rpcCall(RPC_URLS[chain] || [], address, "0x18160ddd");
            const decHex = await rpcCall(RPC_URLS[chain] || [], address, "0x313ce567");
            if (totHex !== null && decHex !== null) return { raw: totHex.toString(), tokens: Number(totHex) / (10 ** Number(decHex)) };
            if (bsPro?.totalSupply) { const dec = decHex !== null ? Number(decHex) : 18; return { raw: String(bsPro.totalSupply), tokens: Number(BigInt(bsPro.totalSupply)) / (10 ** dec) }; }
          }
        } catch (_) {}
        return null;
      })();
      const gasP = (async () => {
        try { if (chain === "solana") return null; const gasHex = await rpcJson(RPC_URLS[chain] || [], "eth_gasPrice", []); return gasHex ? Number(BigInt(gasHex)) / 1e9 : null; } catch (_) { return null; }
      })();
      const ownerP = (chain !== "solana" && security?.renounced == null) ? rpcOwner(chain, address).catch(() => null) : Promise.resolve(null);
      const fourP = fourInternal(chain, address).catch(() => null);
      const [logScanRes, pairAddr, supplyRes, gasRes, ownerRes, fourRes] = await Promise.all([logScanP, pairP, supplyP, gasP, ownerP, fourP]);
      if (security && security.renounced == null && ownerRes != null) security.renounced = ownerRes;
      let logScan = logScanRes;
      if (logScan) {
        if (logScan.logScanComplete) {
          if (security && security.topHoldersPct == null && logScan.topHoldersPct != null) security.topHoldersPct = logScan.topHoldersPct;
          if (security && security.holders == null && logScan.holders != null) security.holders = logScan.holders;
        }
        if (security) security.flags = { ...(security.flags || {}), logScan: { complete: logScan.logScanComplete, scannedLogs: logScan.scannedLogs, error: logScan.logScanError } };
      }
      let lpInfo = null;
      if (chain !== "solana" && pairAddr) {
        try {
          lpInfo = await lpInfoAlchemy(env, chain, pairAddr);
          if (lpInfo && lpInfo.lpBurnPct != null && security) {
            security.lpLocked = lpInfo.lpLocked;
            security.flags = { ...(security.flags || {}), lpAlchemy: { burnPct: lpInfo.lpBurnPct, topHolder: lpInfo.lpTopHolder, topHolderPct: lpInfo.lpTopHolderPct, topHolderIsContract: lpInfo.lpTopHolderIsContract, error: lpInfo.lpError } };
          }
        } catch (_) { lpInfo = null; }
      }
      let totalSupplyTokens = supplyRes ? supplyRes.tokens : null;
      let totalSupplyRaw = supplyRes ? supplyRes.raw : null;
      const marketCapUsd = price?.priceUsd != null && totalSupplyTokens != null ? price.priceUsd * totalSupplyTokens : null;
      let swapFeePct = null, swapFeeError = null, gasPriceGwei = gasRes;
      try {
        if (pairAddr && /^0x[0-9a-fA-F]{40}$/.test(pairAddr) && chain !== "solana") {
          const feeHex = await rpcCall(RPC_URLS[chain] || [], pairAddr, "0xddca3f43");
          if (feeHex !== null) swapFeePct = Number(feeHex) / 10000;
          else if (Array.isArray(price?.labels) && price.labels.includes("v2")) swapFeePct = 0.3;
        } else if (pairAddr && !/^0x[0-9a-fA-F]{40}$/.test(pairAddr)) { swapFeeError = "v4_pool_id_no_lp_token"; }
      } catch (e) { swapFeeError = String(e && e.message ? e.message : e); }
      let finalRisk = security?.risk ?? null;
      if (finalRisk !== "red" && (security?.mintable === true || security?.blacklist === true)) finalRisk = "yellow";
      const volumePoolRatio = price?.volume24hUsd != null && price?.liquidityUsd ? Math.round((price.volume24hUsd / price.liquidityUsd) * 10000) / 10000 : null;
      const poolAge = price?.pairCreatedAt ? Math.round(((Date.now() - Number(price.pairCreatedAt)) / 86400000) * 10) / 10 : null;
      const body = {
        chain, address,
        price,
        // 第二阶段再接，不编数据：
        holders: (security?.holders != null && Number(security.holders) > 0) ? security.holders : (logScan?.logScanComplete ? logScan.holders : null), topHoldersPct: security?.topHoldersPct ?? null,
        buyTax: security?.buyTax ?? null, sellTax: security?.sellTax ?? null,
        honeypot: security?.honeypot ?? null, renounced: security?.renounced ?? null,
        mintable: security?.mintable ?? null, blacklist: security?.blacklist ?? null,
        lpLocked: security?.lpLocked ?? null, lpBurnPct: lpInfo?.lpBurnPct ?? null, lpTopHolder: lpInfo?.lpTopHolder ?? null, lpTopHolderPct: lpInfo?.lpTopHolderPct ?? null, lpTopHolderIsContract: lpInfo?.lpTopHolderIsContract ?? null, lpError: lpInfo?.lpError ?? null, poolAge,
        marketCapUsd, totalSupplyTokens, totalSupplyRaw,
        txns5m: price?.txns5m ?? null, txns1h: price?.txns1h ?? null, txns24h: price?.txns24h ?? null,
        totalVolume24hUsd: price?.totalVolume24hUsd ?? null, totalLiquidityUsd: price?.totalLiquidityUsd ?? null, volumePoolRatio,
        liquidityBase: price?.liquidityBase ?? null, liquidityQuote: price?.liquidityQuote ?? null, quoteTokenSymbol: price?.quoteTokenSymbol ?? null,
        priceChange5mPct: price?.priceChange5mPct ?? null, priceChange1hPct: price?.priceChange1hPct ?? null,
        swapFeePct, swapFeeError, gasPriceGwei, realHolders: logScan?.realHolders ?? null,
        allPairs: price?.allPairs ?? null,
        internalMarket: chain === "solana" ? { platform: "pump.fun", status: (price?.allPairs || []).some((q) => q.dexId === "pump") ? "internal" : (price?.allPairs || []).some((q) => ["pumpswap", "raydium", "orca"].includes(q.dexId)) ? "graduated_external" : (price ? "external_or_unknown" : "unknown_no_dex_pair"), dexIds: (price?.allPairs || []).map((q) => q.dexId), note: "Pump.fun 前端 API 自 2026-09-24 起 404，Worker 内盘只按 Dex 池 dexId 判定（pump=内盘，pumpswap/raydium=已毕业外盘），链上曲线 PDA 需 Solana ed25519 数学、本版未内置，不编曲线储备数；无 Dex 对的 pump 币可能是未索引的内盘，标 unknown_no_dex_pair" } : chain === "bsc" ? { ...(fourRes || {}), externalPools: price?.allPairs ?? null, note: "BSC 内盘走 Four.meme 代理余额法，余额 200M-1B 为内盘，余额 0 且有 PancakeSwap 外盘对为已毕业，余额 0 且无外盘对为非 Four.meme" } : { platform: null, status: "external_only", externalPools: price?.allPairs ?? null, note: "本链无统一免费内盘接口（Base/ETH 等发射台各异、无统一代理余额法），本版只给外盘多池，内盘不编数" },
        multiSource: { priceDexUsd: dexPrice?.priceUsd ?? null, priceGeckoUsd: geckoPrice?.priceUsd ?? null, priceDiscrepancyPct, pricePrimary: dexPrice ? "dexscreener" : geckoPrice ? "geckoterminal" : null, holdersPro: bsPro?.holders ?? null, holdersSecurity: security?.holders ?? null, holdersLogScan: logScan?.holders ?? null, goplusError: goplusR.error ?? null, honeypotError: honeypotR.error ?? null, queryTimeMs: Date.now() - t0 },
        paidPromotion,
        backupSources: { price: ["dexscreener", "geckoterminal"], security: ["goplus", "honeypot_is", "etherscan_source"], holdersTop10Creator: ["blockscout_pro", "alchemy_logscan", "public_rpc_logscan", "goplus_honeypot_holders"], lp: ["alchemy_lp", "public_rpc_lp_burn"] }, creatorHistory: bsPro?.creatorHistory ?? esCreator ?? bs?.creatorHistory ?? logScan?.creatorHistory ?? null,
        risk: finalRisk, riskSource: security?.source ?? "pending",
        security: security ? { source: security.source, flags: security.flags } : null,
        securityError, bsError, bsProError, etherscanError, logScan: logScan ? { complete: logScan.logScanComplete, scannedLogs: logScan.scannedLogs, error: logScan.logScanError } : null,
        tradeLinks: {
          ave: `https://ave.ai/token/${address}-${chain}`,
          gmgn: `https://gmgn.ai/${chain}/token/${address}`,
          dexscreener: price?.pairAddress ? `https://dexscreener.com/${CHAINS[chain].dex}/${price.pairAddress}` : null,
        },
      };
      try { if (env.CACHE_KV) await env.CACHE_KV.put(`tokenfull:${chain}:${address.toLowerCase()}`, JSON.stringify(body), { expirationTtl: 60 }); } catch (_) {}
      return json(body);
    }


    if (path === "/api/rpc-test" && request.method === "GET") {
      const chain = (url.searchParams.get("chain") || "").toLowerCase();
      const idx = Number(url.searchParams.get("rpc") || "0");
      const method = url.searchParams.get("method") || "eth_blockNumber";
      const urls = RPC_URLS[chain] || [];
      const rpcUrl = urls[idx];
      if (!rpcUrl) return json({ error: "no_rpc_url", chain, idx }, 400);
      try {
        let params = [];
        if (method === "eth_getLogs") {
          const address = url.searchParams.get("address") || "";
          const from = url.searchParams.get("from") || "0x0";
          const to = url.searchParams.get("to") || "latest";
          params = [{ address, fromBlock: from, toBlock: to, topics: [TRANSFER_TOPIC] }];
        }
        const res = await fetch(rpcUrl, { method: "POST", headers: { "content-type": "application/json", accept: "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
        const body = await res.json().catch(() => ({}));
        return json({ chain, rpcUrl, status: res.status, result: body.result ?? null, error: body.error ?? null, count: Array.isArray(body.result) ? body.result.length : null });
      } catch (e) { return json({ chain, rpcUrl, error: String(e && e.message ? e.message : e) }); }
    }

    if (path === "/api/holdings" && request.method === "POST") {
      let body = {};
      try { body = await request.json(); } catch (_) { return json({ error: "bad_json" }, 400); }
      const wallets = Array.isArray(body.wallets) ? body.wallets.slice(0, 20) : [];
      const tokens = Array.isArray(body.tokens) ? body.tokens.slice(0, 20) : [];
      const valid = [];
      const invalid = [];
      for (const w of wallets) {
        const chain = String(w.chain || "").toLowerCase();
        if (CHAINS[chain] && isValidAddress(chain, w.address)) valid.push({ chain, address: w.address, label: w.label || "" });
        else invalid.push({ chain: w.chain || null, address: w.address || null, reason: "invalid_chain_or_address" });
      }
      const results = [];
      const byChain = {};
      let totalUsd = 0;
      let pricedAny = false;
      for (const w of valid) {
        const balances = [];
        let walletUsd = 0;
        try {
          if (w.chain === "solana") {
            const amt = await solNativeAmount(w.address);
            let priceUsd = null;
            try { const pr = await priceFor("solana", "So11111111111111111111111111111111111111112"); priceUsd = pr?.priceUsd ?? null; } catch (_) {}
            const usd = amt != null && priceUsd != null ? amt * priceUsd : null;
            if (usd != null) { walletUsd += usd; pricedAny = true; }
            balances.push({ kind: "native", symbol: "SOL", amount: amt, priceUsd, usd });
            for (const tk of tokens.filter((x) => String(x.chain || "").toLowerCase() === "solana" && isValidAddress("solana", x.address))) {
              const amt2 = await solTokenAmount(w.address, tk.address);
              if (amt2 == null) continue;
              const pr = await priceFor("solana", tk.address);
              const usd2 = pr?.priceUsd != null ? amt2 * pr.priceUsd : null;
              if (usd2 != null) { walletUsd += usd2; pricedAny = true; }
              balances.push({ kind: "token", address: tk.address, symbol: pr?.symbol ?? tk.symbol ?? null, amount: amt2, priceUsd: pr?.priceUsd ?? null, usd: usd2 });
            }
          } else {
            const amt = await evmNativeAmount(w.chain, w.address);
            let priceUsd = null;
            const wrapped = NATIVE_WRAPPED[w.chain];
            if (wrapped) { try { const pr = await priceFor(w.chain, wrapped); priceUsd = pr?.priceUsd ?? null; } catch (_) {} }
            const usd = amt != null && priceUsd != null ? amt * priceUsd : null;
            if (usd != null) { walletUsd += usd; pricedAny = true; }
            balances.push({ kind: "native", symbol: NATIVE_SYMBOL[w.chain] || null, amount: amt, priceUsd, usd });
            for (const tk of tokens.filter((x) => String(x.chain || "").toLowerCase() === w.chain && isValidAddress(w.chain, x.address))) {
              const amt2 = await evmTokenAmount(w.chain, tk.address, w.address);
              if (amt2 == null) continue;
              const pr = await priceFor(w.chain, tk.address);
              const usd2 = pr?.priceUsd != null ? amt2 * pr.priceUsd : null;
              if (usd2 != null) { walletUsd += usd2; pricedAny = true; }
              balances.push({ kind: "token", address: tk.address, symbol: pr?.symbol ?? tk.symbol ?? null, amount: amt2, priceUsd: pr?.priceUsd ?? null, usd: usd2 });
            }
          }
        } catch (e) {
          balances.push({ kind: "error", error: String(e && e.message ? e.message : e) });
        }
        results.push({ ...w, balances, totalUsd: walletUsd });
        byChain[w.chain] = (byChain[w.chain] || 0) + walletUsd;
        totalUsd += walletUsd;
      }
      return json({
        wallets: results, invalid,
        byChain, totalUsd: pricedAny ? totalUsd : null,
        balanceSource: pricedAny ? "rpc" : "rpc_partial",
        note: "钱包监控：只读公开地址，不碰私钥；原生与自选代币余额走公开 RPC，现货价走 Dexscreener/GeckoTerminal；未定价的余额不计入 totalUsd；自动分析（胜率、盈亏、聪明钱画像）是第二阶段，在交易历史接通后做，不在这里编数。",
      });
    }

    return json({ error: "not_found", path }, 404);
  },
};
