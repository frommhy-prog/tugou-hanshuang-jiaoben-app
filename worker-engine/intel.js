// TSTZ-M 引擎：EVM 持有人（多读页、不带时间戳，减小体积）+ 钱包关联（首笔资金来源聚类；Solana 用 Helius funded-by）
// 路由：/e/v2/holders2?chain=&token=&pages=  /e/v2/links?chain=&owners=a,b,c
export function makeIntel(h) {
  const { vGet, jget, sleep, now, cached } = h;
  const NET = { bsc: 'bnb-mainnet', eth: 'eth-mainnet', base: 'base-mainnet', arbitrum: 'arb-mainnet', optimism: 'opt-mainnet', polygon: 'polygon-mainnet' };
  const DEX = { bsc: 'bsc', eth: 'ethereum', base: 'base', arbitrum: 'arbitrum', optimism: 'optimism', polygon: 'polygon' };
  const ZERO = '0x' + '0'.repeat(40);
  const DEAD = '0x' + '0'.repeat(36) + 'dead';
  const okEvm = (s) => /^0x[0-9a-fA-F]{40}$/.test(s || '');
  const okSol = (s) => /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(s || '');
  const r4 = (v) => (v == null ? null : Math.round(v * 10000) / 10000);

  async function akey(env) {
    const k = (await vGet(env, 'alchemy')) || env.ALCHEMY_API_KEY;
    if (!k) throw new Error('no_alchemy_key');
    return k;
  }
  async function rpcRaw(env, chain, body) {
    const k = await akey(env);
    return jget('https://' + NET[chain] + '.g.alchemy.com/v2/' + k, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  }
  async function rpc(env, chain, method, params) {
    const j = await rpcRaw(env, chain, { jsonrpc: '2.0', id: 1, method, params });
    if (j.error) throw new Error(method + ':' + String(j.error.message || '').slice(0, 120));
    return j.result;
  }
  async function market(chain, T) {
    try {
      const j = await jget('https://api.dexscreener.com/latest/dex/tokens/' + T, { headers: { accept: 'application/json' } });
      let best = null;
      for (const p of j.pairs || []) {
        if (p.chainId !== DEX[chain]) continue;
        const b = p.baseToken && p.baseToken.address && p.baseToken.address.toLowerCase();
        if (b !== T) continue;
        const liq = (p.liquidity && p.liquidity.usd) || 0;
        if (!best || liq > best.liq) best = { sym: p.baseToken.symbol, name: p.baseToken.name, liq, priceUsd: Number(p.priceUsd) || null, priceNative: Number(p.priceNative) || null, quote: p.quoteToken && p.quoteToken.address ? p.quoteToken.address.toLowerCase() : null, pair: p.pairAddress ? p.pairAddress.toLowerCase() : null, dex: p.dexId, createdAt: p.pairCreatedAt || null, b24: p.txns && p.txns.h24 ? p.txns.h24.buys : null, s24: p.txns && p.txns.h24 ? p.txns.h24.sells : null, vol24: p.volume ? p.volume.h24 : null, mc: p.marketCap || p.fdv || null };
      }
      return best;
    } catch (_) { return null; }
  }

  // ---------- 持有人：读全部 ERC20 转账累加余额；读不完就明说，不给假榜单 ----------
  async function buildHolders(env, chain, T, maxPages) {
    const mk = await market(chain, T);
    let supply = null, dec = null;
    try { const s = await rpc(env, chain, 'eth_call', [{ to: T, data: '0x18160ddd' }, 'latest']); if (s && s !== '0x') supply = BigInt(s); } catch (_) {}
    try { const d = await rpc(env, chain, 'eth_call', [{ to: T, data: '0x313ce567' }, 'latest']); if (d && d !== '0x') dec = parseInt(d, 16); } catch (_) {}
    const bal = new Map();
    let key = null, complete = false, used = 0, n = 0, minted = null;
    while (used < maxPages) {
      const params = { category: ['erc20'], contractAddresses: [T], order: 'asc', excludeZeroValue: true, maxCount: '0x3e8' };
      if (key) params.pageKey = key;
      const r = await rpc(env, chain, 'alchemy_getAssetTransfers', [params]);
      used++;
      for (const t of (r && r.transfers) || []) {
        const raw = t.rawContract && t.rawContract.value;
        if (!raw) continue;
        const v = BigInt(raw), f = String(t.from || ZERO).toLowerCase(), to = String(t.to || ZERO).toLowerCase();
        n++;
        if (f === ZERO) { if (!minted) minted = to; } else bal.set(f, (bal.get(f) || 0n) - v);
        bal.set(to, (bal.get(to) || 0n) + v);
      }
      if (!r || !r.pageKey) { complete = true; break; }
      key = r.pageKey;
    }
    const notes = ['持有人由该代币全部转账记录累加还原；只统计 ERC20 转账事件，无转账事件的特殊代币可能有偏差'];
    const base = { chain, token: T, decimals: dec, market: mk, at: now() };
    if (!complete) {
      return { ...base, complete: false, transferN: n, holders: [], findings: [{ level: 'info', text: '该代币转账记录超过 ' + n + ' 笔，云端读了 ' + used + ' 页仍未读完，无法还原完整持有人榜单（已自动改用备用数据源）', basis: '每页 1000 笔，最多读 ' + maxPages + ' 页' }], notes };
    }
    let live = 0n;
    for (const [a, b] of bal) if (b > 0n && a !== ZERO && a !== DEAD) live += b;
    const burnB = (bal.get(ZERO) || 0n) + (bal.get(DEAD) || 0n);
    if (!supply || supply <= 0n) { supply = live + burnB; notes.push('链上 totalSupply 读取失败，总量按转账累加值推算'); }
    const pct = (b) => (supply > 0n ? Number((b * 1000000n) / supply) / 10000 : null);
    const dnum = (b) => (dec != null ? Number(b) / Math.pow(10, dec) : null);
    const list = [...bal.entries()].filter(([a, b]) => b > 0n && a !== ZERO && a !== DEAD).sort((a, b) => (a[1] < b[1] ? 1 : a[1] > b[1] ? -1 : 0));
    const top = list.slice(0, 20);
    let codes = [];
    if (top.length) {
      try {
        const arr = await rpcRaw(env, chain, top.map(([a], i) => ({ jsonrpc: '2.0', id: i, method: 'eth_getCode', params: [a, 'latest'] })));
        codes = new Array(top.length).fill(null);
        if (Array.isArray(arr)) for (const x of arr) if (x && x.result != null) codes[x.id] = x.result;
      } catch (_) { codes = []; }
    }
    const holders = top.map(([a, b], i) => {
      const code = codes[i];
      const kind = mk && mk.pair === a ? 'pool' : code == null ? 'unknown' : code !== '0x' ? 'contract' : 'wallet';
      return { rank: i + 1, owner: a, kind, amount: dnum(b), pct: pct(b) };
    });
    const sumPct = (arr) => r4(arr.reduce((s, x) => s + (x.pct || 0), 0));
    const wallets = holders.filter((x) => x.kind === 'wallet');
    const conc = { top1: sumPct(holders.slice(0, 1)), top5: sumPct(holders.slice(0, 5)), top10: sumPct(holders.slice(0, 10)), top20: sumPct(holders), wallets10: sumPct(wallets.slice(0, 10)), nonWallet: sumPct(holders.filter((x) => x.kind !== 'wallet')), listed: holders.length };
    const f = [];
    f.push({ level: 'info', text: '共 ' + list.length + ' 个持有人，已读完全部 ' + n + ' 笔转账记录', basis: '按转账累加还原，读了 ' + used + ' 页' });
    if (wallets.length >= 3) f.push({ level: conc.wallets10 >= 30 ? 'risk' : conc.wallets10 >= 15 ? 'warn' : 'ok', text: '前 ' + Math.min(10, wallets.length) + ' 大普通钱包合计持有 ' + conc.wallets10 + '%', basis: '占总供应量；普通钱包 = 地址没有合约代码且不是已知池子' });
    if (conc.nonWallet >= 50) f.push({ level: 'info', text: '前 20 大持有人里 ' + conc.nonWallet + '% 在池子/合约中，不是普通钱包', basis: '多为 AMM 池、发射台曲线合约、质押或锁仓合约' });
    if (holders[0] && holders[0].kind === 'wallet' && conc.top1 >= 20) f.push({ level: 'risk', text: '第 1 大持有人是普通钱包，持有 ' + conc.top1 + '%', basis: '地址 ' + holders[0].owner });
    if (minted) { const mb = bal.get(minted) || 0n; f.push({ level: 'info', text: '代币首次铸造给 ' + minted.slice(0, 8) + '…，该地址当前持有 ' + pct(mb) + '%', basis: '首笔来自零地址的转账接收方；可能是部署者、发射台或分发合约' }); }
    const bp = pct(burnB); if (bp != null && bp > 0) f.push({ level: 'info', text: '已销毁 ' + bp + '%（发送到零地址/dead 地址）', basis: '转账累加' });
    return { ...base, complete: true, transferN: n, supply: dnum(supply), holderCount: list.length, burnedPct: bp, holders, concentration: conc, findings: f, notes };
  }
  async function holders(env, q) {
    const chain = q.get('chain'), T = String(q.get('token') || '').toLowerCase();
    if (!NET[chain]) return { error: 'chain_unsupported', detail: '支持：' + Object.keys(NET).join('、') };
    if (!okEvm(T)) return { error: 'bad_token' };
    const pages = Math.min(14, Math.max(3, Number(q.get('pages')) || 12));
    return cached(env, 'h2:' + chain + ':' + T + ':' + pages, 60, q.get('fresh') === '1', () => buildHolders(env, chain, T, pages));
  }

  // ---------- 钱包关联：每个钱包收到的第一笔原生币来自谁，共享出资地址的归为一组 ----------
  async function evmLinks(env, chain, owners) {
    const rows = await Promise.all(owners.map(async (o) => {
      try {
        const r = await rpc(env, chain, 'alchemy_getAssetTransfers', [{ toAddress: o, category: ['external'], order: 'asc', maxCount: '0x1', excludeZeroValue: true, withMetadata: true }]);
        const t = ((r && r.transfers) || [])[0];
        if (!t) return { owner: o, funder: null };
        const ts = t.metadata && t.metadata.blockTimestamp ? Math.floor(Date.parse(t.metadata.blockTimestamp) / 1000) : null;
        return { owner: o, funder: String(t.from || '').toLowerCase(), amt: t.value, asset: t.asset, ts, hash: t.hash };
      } catch (e) { return { owner: o, funder: null, err: String((e && e.message) || e).slice(0, 80) }; }
    }));
    const by = new Map();
    for (const r of rows) if (r.funder) { if (!by.has(r.funder)) by.set(r.funder, []); by.get(r.funder).push(r.owner); }
    const groups = [...by.entries()].filter(([, v]) => v.length >= 2);
    let codes = {};
    if (groups.length) {
      try {
        const arr = await rpcRaw(env, chain, groups.map(([f], i) => ({ jsonrpc: '2.0', id: i, method: 'eth_getCode', params: [f, 'latest'] })));
        if (Array.isArray(arr)) for (const x of arr) if (x && x.result != null) codes[groups[x.id][0]] = x.result !== '0x';
      } catch (_) {}
    }
    const clusters = groups.map(([f, v]) => ({ funder: f, owners: v, n: v.length, contract: codes[f] === true, name: codes[f] === true ? '合约（交易所路由/批量分发，仅作线索）' : null })).sort((a, b) => b.n - a.n);
    return { chain, links: rows, clusters, at: now() };
  }
  async function solLinks(env, owners) {
    const k = await vGet(env, 'helius');
    if (!k) return { error: 'no_helius_key' };
    const rows = await Promise.all(owners.map(async (o) => {
      try {
        const j = await jget('https://api.helius.xyz/v1/wallet/' + o + '/funded-by?api-key=' + k, undefined, 2);
        return { owner: o, funder: j.funder || null, amt: j.amount, asset: 'SOL', ts: j.timestamp, hash: j.signature, name: j.funderName || null, type: j.funderType || null };
      } catch (e) { return { owner: o, funder: null, err: String((e && e.message) || e).slice(0, 80) }; }
    }));
    const by = new Map();
    for (const r of rows) if (r.funder) { if (!by.has(r.funder)) by.set(r.funder, []); by.get(r.funder).push(r); }
    const clusters = [...by.entries()].filter(([, v]) => v.length >= 2).map(([f, v]) => ({ funder: f, owners: v.map((x) => x.owner), n: v.length, contract: false, name: v[0].name || (v[0].type ? String(v[0].type) : null) })).sort((a, b) => b.n - a.n);
    return { chain: 'solana', links: rows, clusters, at: now() };
  }
  async function links(env, q) {
    const chain = q.get('chain');
    const owners = String(q.get('owners') || '').split(',').map((s) => s.trim()).filter(Boolean).slice(0, 14);
    if (!owners.length) return { error: 'no_owners' };
    const sol = chain === 'solana';
    if (sol ? !owners.every(okSol) : !(NET[chain] && owners.every(okEvm))) return { error: 'bad_args', detail: sol ? '需要 Solana 地址' : '链不支持或地址格式不对' };
    const key = 'lk:' + chain + ':' + owners.map((x) => x.toLowerCase()).sort().join(',');
    return cached(env, key, 600, q.get('fresh') === '1', () => (sol ? solLinks(env, owners) : evmLinks(env, chain, owners)));
  }

  return { holders, links };
}
