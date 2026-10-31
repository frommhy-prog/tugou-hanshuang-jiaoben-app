// TSTZ-M 引擎 EVM 模块 v1：Alchemy 转账记录 → 按交易哈希配对 swap → 平均成本盈亏。每条结论附依据，查不到写「未知」
// 数据源只有 Alchemy（密钥取自加密库 alchemy 或 Secret ALCHEMY_API_KEY）与 Dexscreener（价格/池子）
export function makeEvm(h) {
  const { vGet, jget, sleep, now, r4, dur, ledger } = h;
  const ZERO = '0x' + '0'.repeat(40);
  const DEAD = '0x' + '0'.repeat(36) + 'dead';
  const NEPS = 1e-6, UEPS = 0.01;
  const CH = {
    bsc: { net: 'bnb-mainnet', native: 'BNB', dex: 'bsc', wrapped: '0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c', small: 0.05, big: 5, stables: ['0x55d398326f99059ff775485246999027b3197955', '0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d', '0xe9e7cea3dedca5984780bafc599bd69add087d56', '0xc5f0f7b66764f6ec8c8dff7ba683102295e16409', '0x8d0d000ee44948fc98c9b98a4fa4921476f08b0d', '0x1af3f329e8be154074d8769d1ffa4ee058b1dbc3'] },
    eth: { net: 'eth-mainnet', native: 'ETH', dex: 'ethereum', wrapped: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2', small: 0.01, big: 1, stables: ['0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48', '0xdac17f958d2ee523a2206206994597c13d831ec7', '0x6b175474e89094c44da98b954eedeac495271d0f', '0x4c9edd5852cd905f086c759e8383e09bff1e68b3', '0xc5f0f7b66764f6ec8c8dff7ba683102295e16409', '0x8d0d000ee44948fc98c9b98a4fa4921476f08b0d'] },
    base: { net: 'base-mainnet', native: 'ETH', dex: 'base', wrapped: '0x4200000000000000000000000000000000000006', small: 0.01, big: 1, stables: ['0x833589fcd6edb6e08f4c7c32d4f71b54bda02913', '0xd9aaec86b65d86f6a7b5b1b0c42ffa531710b6ca', '0x50c5725949a6f0c72e6c4a641f24049a917db0cb'] },
    arbitrum: { net: 'arb-mainnet', native: 'ETH', dex: 'arbitrum', wrapped: '0x82af49447d8a07e3bd95bd0d56f35241523fbab1', small: 0.01, big: 1, stables: ['0xaf88d065e77c8cc2239327c5edb3a432268e5831', '0xff970a61a04b1ca14834a43f5de4533ebddb5cc8', '0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9', '0xda10009cbd5d07dd0cecc66161fc93d7c9000da1'] },
    optimism: { net: 'opt-mainnet', native: 'ETH', dex: 'optimism', wrapped: '0x4200000000000000000000000000000000000006', small: 0.01, big: 1, stables: ['0x0b2c639c533813f4aa9d7837caf62653d097ff85', '0x7f5c764cbc14f9669b88837ca1490cca17c31607', '0x94b008aa00579c1307b0ef2c499ad98a8ce58e58', '0xda10009cbd5d07dd0cecc66161fc93d7c9000da1'] },
    polygon: { net: 'polygon-mainnet', native: 'POL', dex: 'polygon', wrapped: '0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270', small: 0, big: 0, stables: ['0x3c499c542cef5e3811e1192ce70d8cc03d5c3359', '0x2791bca1f2de4661ed88a30c99a7a9449aa84174', '0xc2132d05d31c914a87c6611c10748aeb04b58e8f', '0x8f3cf7ad23cd3cadbd9735aff958023239c6a063'] },
  };
  const ok = (chain) => Object.prototype.hasOwnProperty.call(CH, chain);
  const stSet = (chain) => CH[chain]._st || (CH[chain]._st = new Set(CH[chain].stables));
  const hexBlock = (n) => '0x' + n.toString(16);

  // ---------- Alchemy ----------
  async function akey(env) {
    const k = (await vGet(env, 'alchemy')) || env.ALCHEMY_API_KEY;
    if (!k) throw new Error('no_alchemy_key');
    return k;
  }
  async function rpcRaw(env, chain, body) {
    const k = await akey(env);
    return jget('https://' + CH[chain].net + '.g.alchemy.com/v2/' + k, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  }
  // 批量 JSON-RPC：一个 HTTP 请求算 1 个子请求。返回与 calls 同序的 {v} 或 {err}
  async function batch(env, chain, calls) {
    const body = calls.map((c, i) => ({ jsonrpc: '2.0', id: i, method: c[0], params: c[1] }));
    const arr = await rpcRaw(env, chain, body);
    const out = new Array(calls.length).fill(null);
    if (Array.isArray(arr)) for (const r of arr) out[r.id] = r.error ? { err: String(r.error.message || 'err').slice(0, 100) } : { v: r.result };
    else if (arr && arr.error) throw new Error('batch:' + String(arr.error.message || '').slice(0, 120));
    return out;
  }
  // alchemy_getAssetTransfers 翻页。category 含 internal 但该链不支持时自动去掉并记入 st.internal=false
  async function scan(env, chain, base, pages, st) {
    const out = []; let key = null, complete = false, used = 0;
    for (let p = 0; p < pages; p++) {
      const params = { ...base, withMetadata: true, excludeZeroValue: true, maxCount: '0x3e8' };
      if (key) params.pageKey = key;
      let j = await rpcRaw(env, chain, { jsonrpc: '2.0', id: 1, method: 'alchemy_getAssetTransfers', params: [params] });
      if (j.error && params.category.includes('internal') && /categor|internal/i.test(String(j.error.message))) {
        base.category = params.category = params.category.filter((x) => x !== 'internal');
        if (st) st.internal = false;
        j = await rpcRaw(env, chain, { jsonrpc: '2.0', id: 1, method: 'alchemy_getAssetTransfers', params: [params] });
      }
      if (j.error) throw new Error('getAssetTransfers:' + String(j.error.message || '').slice(0, 160));
      used++;
      out.push(...((j.result && j.result.transfers) || []));
      if (!j.result || !j.result.pageKey) { complete = true; break; }
      key = j.result.pageKey;
      await sleep(150);
    }
    return { xs: out, complete, used };
  }

  async function dexEvm(chain, addrs) {
    const out = {}, id = CH[chain].dex;
    for (let i = 0; i < addrs.length; i += 30) {
      const j = await jget('https://api.dexscreener.com/latest/dex/tokens/' + addrs.slice(i, i + 30).join(','), { headers: { accept: 'application/json' } });
      for (const p of j.pairs || []) {
        if (p.chainId !== id) continue;
        const m = p.baseToken && p.baseToken.address && p.baseToken.address.toLowerCase(); if (!m) continue;
        const liq = (p.liquidity && p.liquidity.usd) || 0;
        if (!out[m] || liq > out[m].liq) out[m] = { sym: p.baseToken.symbol, name: p.baseToken.name, liq, priceUsd: Number(p.priceUsd) || null, priceNative: Number(p.priceNative) || null, quote: p.quoteToken && p.quoteToken.address ? p.quoteToken.address.toLowerCase() : null, pair: p.pairAddress ? p.pairAddress.toLowerCase() : null, dex: p.dexId, createdAt: p.pairCreatedAt || null, b24: p.txns && p.txns.h24 ? p.txns.h24.buys : null, s24: p.txns && p.txns.h24 ? p.txns.h24.sells : null, vol24: p.volume ? p.volume.h24 : null, mc: p.marketCap || p.fdv || null };
      }
    }
    return out;
  }

  // ---------- 转账 → 交易：按哈希汇总本钱包的净变化，不猜 ----------
  function build(chain, W, xs) {
    const c = CH[chain], st = stSet(chain), by = new Map();
    for (const t of xs) {
      const f = String(t.from || '').toLowerCase(), to = String(t.to || '').toLowerCase();
      const out = f === W, inn = to === W;
      if (out === inn) continue;
      const v = Number(t.value); if (!(v > 0)) continue;
      let g = by.get(t.hash);
      if (!g) { g = { hash: t.hash, block: parseInt(t.blockNum, 16), ts: Math.floor(Date.parse((t.metadata && t.metadata.blockTimestamp) || '') / 1000) || null, nat: 0, usd: 0, tok: {}, sym: {}, out: false }; by.set(t.hash, g); }
      if (out) g.out = true;
      const s = inn ? 1 : -1;
      const ca = t.rawContract && t.rawContract.address ? String(t.rawContract.address).toLowerCase() : null;
      if (t.category === 'erc20' && ca) {
        if (ca === c.wrapped) g.nat += s * v;
        else if (st.has(ca)) g.usd += s * v;
        else { g.tok[ca] = (g.tok[ca] || 0) + s * v; g.sym[ca] = t.asset || null; }
      } else if (t.category === 'external' || t.category === 'internal') g.nat += s * v;
    }
    const trades = [], cands = [], byBlock = new Map(); let multi = 0, inbound = 0;
    for (const g of by.values()) {
      if (!byBlock.has(g.block)) byBlock.set(g.block, []);
      byBlock.get(g.block).push(g);
      const bases = Object.keys(g.tok).filter((k) => g.tok[k] !== 0);
      if (bases.length !== 1) { if (bases.length > 1) multi++; continue; }
      const m = bases[0], d = g.tok[m];
      const base = { sig: g.hash, t: g.ts, block: g.block, mint: m, qty: Math.abs(d), sym: g.sym[m], approx: false };
      if (d > 0) {
        const pn = -g.nat, pu = -g.usd;
        if (pn > NEPS && pu <= UEPS) trades.push({ ...base, side: 'buy', q: 'NATIVE', amt: pn });
        else if (pu > UEPS && pn <= NEPS) trades.push({ ...base, side: 'buy', q: 'USD', amt: pu });
        else if (pn > NEPS && pu > UEPS) multi++;
        else inbound++;
      } else {
        if (g.nat > NEPS && g.usd <= UEPS) trades.push({ ...base, side: 'sell', q: 'NATIVE', amt: g.nat });
        else if (g.usd > UEPS && g.nat <= NEPS) trades.push({ ...base, side: 'sell', q: 'USD', amt: g.usd });
        else if (g.nat > NEPS && g.usd > UEPS) multi++;
        else cands.push({ g, m, qty: Math.abs(d) });
      }
    }
    return { trades, cands, byBlock, multi, inbound };
  }

  // 该链转账接口没有内部转账（如卖出收到的原生币）时：用区块前后余额变化 + 回执手续费反推卖出所得（标记 approx）
  async function resolveSells(env, chain, W, cands, byBlock) {
    const trades = []; let unresolved = 0, notSale = 0, shared = 0;
    const list = [...cands].sort((a, b) => b.g.block - a.g.block);
    const take = list.slice(0, 60); unresolved += list.length - take.length;
    for (let i = 0; i < take.length; i += 5) {
      const part = take.slice(i, i + 5), calls = [];
      for (const x of part) calls.push(['eth_getTransactionReceipt', [x.g.hash]], ['eth_getBalance', [W, hexBlock(x.g.block - 1)]], ['eth_getBalance', [W, hexBlock(x.g.block)]]);
      let r;
      try { r = await batch(env, chain, calls); } catch (_) { unresolved += part.length; continue; }
      part.forEach((x, k) => {
        const rc = r[k * 3], b0 = r[k * 3 + 1], b1 = r[k * 3 + 2];
        if (!rc || rc.err || !rc.v || !b0 || b0.err || !b1 || b1.err) { unresolved++; return; }
        let gas = 0n;
        if (rc.v.from && rc.v.from.toLowerCase() === W) gas = BigInt(rc.v.gasUsed || '0x0') * BigInt(rc.v.effectiveGasPrice || '0x0') + BigInt(rc.v.l1Fee || '0x0');
        const delta = Number(BigInt(b1.v) - BigInt(b0.v) + gas) / 1e18;
        const others = (byBlock.get(x.g.block) || []).filter((o) => o.hash !== x.g.hash);
        const otherNet = others.reduce((s, o) => s + o.nat, 0);
        if (others.length) shared++;
        const proceeds = delta - x.g.nat - otherNet;
        if (proceeds > 1e-5) trades.push({ sig: x.g.hash, t: x.g.ts, block: x.g.block, mint: x.m, qty: x.qty, sym: x.g.sym[x.m], side: 'sell', q: 'NATIVE', amt: proceeds, approx: true });
        else notSale++;
      });
      await sleep(900);
    }
    return { trades, unresolved, notSale, shared };
  }

  const med = (a) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.floor(s.length / 2)] : null; };
  function sumEvm(chain, trades, pos, meta) {
    const c = CH[chain], nat = c.native, all = Object.values(pos);
    const rs = all.filter((p) => p.sells > 0 && p.sold > p.uncovQty + 1e-12);
    const wins = rs.filter((p) => p.realized > 0);
    const sumQ = (q) => rs.filter((p) => p.q === q).reduce((s, p) => s + p.realized, 0);
    const closed = all.filter((p) => p.sells > 0 && p.firstBuy != null && p.qty <= 0.05 * p.bought);
    const holds = closed.map((p) => ({ mint: p.mint, s: p.lastSell - p.firstBuy })).filter((x) => x.s >= 0).sort((a, b) => a.s - b.s);
    const medHold = holds.length ? holds[Math.floor(holds.length / 2)].s : null;
    const buyN = trades.filter((t) => t.side === 'buy' && t.q === 'NATIVE').map((t) => t.amt);
    const buyU = trades.filter((t) => t.side === 'buy' && t.q === 'USD').map((t) => t.amt);
    const ts = trades.map((t) => t.t).sort((a, b) => a - b);
    const winSpan = meta.from && meta.to && meta.to > meta.from ? (meta.to - meta.from) / 86400 : null;
    const spanDays = ts.length > 1 ? Math.max(1 / 24, (ts[ts.length - 1] - ts[0]) / 86400) : null;
    const S = {
      xferN: meta.xferN, hashN: meta.hashN, pages: meta.pages, complete: meta.complete, tradeN: trades.length, approxN: trades.filter((t) => t.approx).length,
      multiSkipped: meta.multi, inboundN: meta.inbound, from: meta.from, to: meta.to, spanDays: winSpan != null ? r4(winSpan) : spanDays ? r4(spanDays) : null,
      tokensTraded: new Set(trades.map((t) => t.mint)).size, realizedN: rs.length, winN: wins.length, winRate: rs.length ? r4(wins.length / rs.length) : null,
      realizedNative: r4(sumQ('NATIVE')), realizedUsd: r4(sumQ('USD')), closedN: closed.length, medHoldSec: medHold,
      medBuyNative: r4(med(buyN)), medBuyUsd: r4(med(buyU)), perDay: spanDays ? r4(trades.length / spanDays) : null,
      uncoveredTokens: all.filter((p) => p.uncovQty > 1e-9).length, nativeQuoteTrades: trades.filter((t) => t.q === 'NATIVE').length, usdQuoteTrades: trades.filter((t) => t.q === 'USD').length,
    };
    const tags = [];
    if (closed.length >= 5 && medHold != null) {
      const evs = holds.slice(0, 5).map((x) => ({ mint: x.mint, text: '持仓 ' + dur(x.s) }));
      if (medHold < 900) tags.push({ tag: '快进快出', basis: `已平仓 ${closed.length} 个，持仓时间中位数 ${dur(medHold)}（判定阈值 15 分钟）`, ev: evs });
      else if (medHold > 6 * 3600) tags.push({ tag: '波段/持有型', basis: `已平仓 ${closed.length} 个，持仓时间中位数 ${dur(medHold)}（判定阈值 6 小时）`, ev: [] });
    }
    if (S.perDay != null && trades.length >= 30 && S.perDay >= 40) tags.push({ tag: '高频交易', basis: `${trades.length} 笔 / ${r4(spanDays)} 天，约 ${Math.round(S.perDay)} 笔/天（阈值 40）`, ev: [] });
    if (buyN.length >= 10) {
      const f = {}; for (const a of buyN) { const k = a.toFixed(4); f[k] = (f[k] || 0) + 1; }
      const top = Object.entries(f).sort((a, b) => b[1] - a[1])[0];
      if (top[1] / buyN.length >= 0.5) tags.push({ tag: '固定金额买入', basis: `${buyN.length} 笔 ${nat} 计价买入里有 ${top[1]} 笔都是 ${top[0]} ${nat}（占 ${Math.round(top[1] / buyN.length * 100)}%，阈值 50%）；可能是程序化，也可能只是习惯整数下单`, ev: [] });
    }
    const blk = {}; for (const t of trades) blk[t.block] = (blk[t.block] || 0) + 1;
    const burst = Object.values(blk).filter((x) => x >= 3).length;
    if (burst >= 3) tags.push({ tag: '同一区块多笔成交（疑似程序化）', basis: `有 ${burst} 个区块内成交 3 笔及以上`, ev: [] });
    if (S.realizedN >= 8 && S.winRate != null) {
      const sn = S.realizedNative, su = S.realizedUsd;
      if (S.winRate >= 0.6 && sn >= 0 && su >= 0) tags.push({ tag: '胜率高且净盈利', basis: `已兑现 ${S.realizedN} 个币，盈利 ${S.winN} 个（${Math.round(S.winRate * 100)}%），${nat} 计价合计 ${sn}，USD 计价合计 ${su}`, ev: [] });
      else if (S.winRate <= 0.3 && sn <= 0 && su <= 0) tags.push({ tag: '胜率低且净亏损', basis: `已兑现 ${S.realizedN} 个币，盈利仅 ${S.winN} 个（${Math.round(S.winRate * 100)}%），${nat} 计价合计 ${sn}，USD 计价合计 ${su}`, ev: [] });
    }
    if (c.small > 0 && S.medBuyNative != null && buyN.length >= 10) {
      if (S.medBuyNative < c.small) tags.push({ tag: '小额试单', basis: `${nat} 计价买入金额中位数 ${S.medBuyNative} ${nat}（阈值 ${c.small}）`, ev: [] });
      else if (S.medBuyNative >= c.big) tags.push({ tag: '大额重仓', basis: `${nat} 计价买入金额中位数 ${S.medBuyNative} ${nat}（阈值 ${c.big}）`, ev: [] });
    }
    const notes = [];
    if (!meta.complete) notes.push(`每个方向只读取了最近 ${meta.pages} 页转账（每页最多 1000 条），窗口约 ${S.spanDays != null ? r4(S.spanDays) + ' 天' : '时间跨度未知'}；更早的历史没有纳入，成本与盈亏只覆盖窗口内`);
    if (meta.hashN > 0 && trades.length === 0) notes.push(`窗口内 ${meta.hashN} 笔交易涉及该地址，但按转账配对无法归属为买卖（可能是纯转账、多币路由或做市），所以没有盈亏统计`);
    if (S.uncoveredTokens > 0) notes.push(`${S.uncoveredTokens} 个币在窗口内出现过「卖出但找不到对应买入」，这部分不计入盈亏（可能是窗口之前买入、转入或空投）`);
    if (meta.inbound > 0) notes.push(`${meta.inbound} 笔是收到代币但没有对应付款（转入、空投或领取），不计成本`);
    if (meta.multi > 0) notes.push(`${meta.multi} 笔一次涉及多个币或多种计价的交易未计入`);
    if (S.approxN > 0) notes.push(`${S.approxN} 笔卖出的 ${nat} 所得由区块前后余额变化反推（该链转账接口不含内部转账），已扣除手续费，仍是近似值`);
    if (meta.unresolved > 0) notes.push(`${meta.unresolved} 笔「卖出代币但没看到收款」的记录无法确认是卖出还是转账（读取余额失败或超出单次上限 60 笔），未计入`);
    if (meta.notSale > 0) notes.push(`${meta.notSale} 笔「转出代币」经余额核对没有收到原生币，判定为转账而非卖出`);
    if (meta.shared > 0) notes.push(`${meta.shared} 笔卖出所在区块还有该钱包的其他交易，反推所得可能有误差`);
    if (S.usdQuoteTrades > 0) notes.push(`${nat} 计价与 USD 计价（稳定币）分开统计，不互相折算；金额不含 gas`);
    notes.push('买卖由转账记录按交易哈希配对得出；盈亏按平均成本法；未计入 gas');
    const sample = S.realizedN >= 8 && (S.spanDays || 0) >= 1 ? '样本可用' : '样本偏少，结论仅供参考';
    return { stats: S, tags, notes, sample };
  }

  async function core(env, chain, addr, pages) {
    const c = CH[chain], W = addr.toLowerCase(), st = { internal: true };
    const mk = () => (st.internal ? ['external', 'internal', 'erc20'] : ['external', 'erc20']);
    const so = await scan(env, chain, { fromAddress: W, category: mk(), order: 'desc' }, pages, st);
    const si = await scan(env, chain, { toAddress: W, category: mk(), order: 'desc' }, pages, st);
    let cut = 0;
    for (const s of [so, si]) if (!s.complete && s.xs.length) cut = Math.max(cut, s.xs.reduce((m, x) => Math.min(m, parseInt(x.blockNum, 16)), Infinity));
    const xs = so.xs.concat(si.xs).filter((x) => cut === 0 || parseInt(x.blockNum, 16) > cut);
    const tss = xs.map((x) => Date.parse((x.metadata && x.metadata.blockTimestamp) || '') / 1000).filter((v) => v > 0);
    const bt = build(chain, W, xs);
    let rs = { trades: [], unresolved: 0, notSale: 0, shared: 0 }, transferOut = 0;
    if (!st.internal && bt.cands.length) rs = await resolveSells(env, chain, W, bt.cands, bt.byBlock);
    else transferOut = bt.cands.length;
    const trades = bt.trades.concat(rs.trades).filter((t) => t.t);
    const pos = ledger(trades);
    const mints = [...new Set([...trades].sort((a, b) => b.t - a.t).map((t) => t.mint))].slice(0, 60);
    let info = {}, dexErr = null;
    if (mints.length) { try { info = await dexEvm(chain, mints); } catch (e) { dexErr = String((e && e.message) || e).slice(0, 80); } }
    const meta = { xferN: xs.length, hashN: new Set(xs.map((x) => x.hash)).size, pages: Math.max(so.used, si.used), complete: so.complete && si.complete, from: tss.length ? Math.min(...tss) : null, to: tss.length ? Math.max(...tss) : null, multi: bt.multi, inbound: bt.inbound, unresolved: rs.unresolved, notSale: rs.notSale, shared: rs.shared };
    const sum = sumEvm(chain, trades, pos, meta);
    if (transferOut > 0) sum.notes.push(`${transferOut} 笔转出代币没有收款，判定为转账（该链转账接口包含内部转账，卖出所得会被记录）`);
    if (dexErr) sum.notes.push('价格源 Dexscreener 暂时不可用，浮动盈亏和币名可能缺失：' + dexErr);
    return { c, trades, pos, info, sum, internal: st.internal };
  }

  async function opWallet(env, chain, addr, pages) {
    const { c, trades, pos, info, sum, internal } = await core(env, chain, addr, pages);
    const stb = stSet(chain);
    const positions = Object.values(pos).map((p) => {
      const i = info[p.mint] || {};
      let open = null;
      if (p.qty > 1e-9) {
        if (p.q === 'NATIVE' && i.priceNative && i.quote === c.wrapped) open = p.qty * i.priceNative;
        else if (p.q === 'USD' && i.priceUsd && stb.has(i.quote)) open = p.qty * i.priceUsd;
      }
      return { token: p.mint, sym: i.sym || null, q: p.q, buys: p.buys, sells: p.sells, bought: p.bought, sold: p.sold, boughtAmt: r4(p.boughtAmt), soldAmt: r4(p.soldAmt), realized: r4(p.realized), remainingQty: p.qty > 1e-9 ? p.qty : 0, remainingCost: p.qty > 1e-9 ? r4(p.cost) : 0, unrealized: open != null ? r4(open - p.cost) : null, firstBuy: p.firstBuy, lastSell: p.lastSell, firstTrade: p.firstTrade, lastTrade: p.lastTrade, uncovQty: p.uncovQty > 1e-9 ? p.uncovQty : 0, bestTx: p.bestSig, worstTx: p.worstSig, liqUsd: i.liq || null };
    }).sort((a, b) => b.lastTrade - a.lastTrade);
    for (const tg of sum.tags) for (const e of tg.ev) e.sym = (info[e.mint] || {}).sym || null;
    const recent = [...trades].sort((a, b) => b.t - a.t).slice(0, 200).map((t) => ({ tx: t.sig, t: t.t, token: t.mint, side: t.side, qty: t.qty, amt: r4(t.amt), q: t.q, approx: t.approx, sym: (info[t.mint] || {}).sym || t.sym || null }));
    return { chain, address: addr, native: c.native, internalOk: internal, ...sum, positions, trades: recent, at: now() };
  }

  async function opHolder(env, chain, token, owner, pages) {
    const { c, trades, pos, info, sum } = await core(env, chain, owner, pages);
    const T = token.toLowerCase();
    const mine = Object.values(pos).filter((p) => p.mint === T).map((p) => ({ q: p.q, buys: p.buys, sells: p.sells, bought: p.bought, sold: p.sold, boughtAmt: r4(p.boughtAmt), soldAmt: r4(p.soldAmt), realized: r4(p.realized), remainingQty: p.qty > 1e-9 ? p.qty : 0, remainingCost: p.qty > 1e-9 ? r4(p.cost) : 0, firstBuy: p.firstBuy, lastSell: p.lastSell, uncovQty: p.uncovQty > 1e-9 ? p.uncovQty : 0, avgBuyPrice: p.bought > 0 ? p.boughtAmt / p.bought : null }));
    const tradesThis = trades.filter((t) => t.mint === T).sort((a, b) => b.t - a.t).slice(0, 40).map((t) => ({ tx: t.sig, t: t.t, token: t.mint, side: t.side, qty: t.qty, amt: r4(t.amt), q: t.q, approx: t.approx, sym: (info[t.mint] || {}).sym || t.sym || null }));
    const finding = mine.length === 0 ? '窗口内没有这个币的买卖记录：可能是更早买入、转账获得、空投或程序分发，成本无法确认' : null;
    return { chain, owner, token: T, native: c.native, tokenPositions: mine, tradesThis, finding, ...sum, at: now() };
  }

  // 代币持有人：把该合约全部 ERC20 转账从头累加得到余额，只有读完全部记录才给榜单，否则明说未知
  async function opToken(env, chain, token, pages) {
    const T = token.toLowerCase(), c = CH[chain];
    let dx = {}; try { dx = await dexEvm(chain, [T]); } catch (_) {}
    const mk = dx[T] || null;
    const meta = await batch(env, chain, [['eth_call', [{ to: T, data: '0x18160ddd' }, 'latest']], ['eth_call', [{ to: T, data: '0x313ce567' }, 'latest']]]);
    const sc = await scan(env, chain, { category: ['erc20'], contractAddresses: [T], order: 'asc' }, pages, null);
    const dec = meta[1] && meta[1].v && meta[1].v !== '0x' ? parseInt(meta[1].v, 16) : null;
    let supply = meta[0] && meta[0].v && meta[0].v !== '0x' ? BigInt(meta[0].v) : null;
    const notes = ['持有人由该代币全部转账记录累加还原；只统计 ERC20 转账事件，无转账事件的特殊代币可能有偏差'];
    const base = { chain, token: T, decimals: dec, market: mk, at: now() };
    if (!sc.complete) {
      return { ...base, complete: false, transferN: sc.xs.length, holders: [], findings: [{ level: 'info', text: `该代币转账记录超过 ${sc.xs.length} 笔，本次没有读完，无法还原持有人榜单（宁可显示未知，不给假数）`, basis: `按转账记录翻了 ${sc.used} 页仍有下一页；可调大 pages（最多 6 页 = 6000 笔）` }], notes };
    }
    const bal = new Map(); let mintedTo = null, firstTs = null, lastTs = null;
    for (const t of sc.xs) {
      const raw = t.rawContract && t.rawContract.value; if (!raw) continue;
      const v = BigInt(raw), f = String(t.from || '').toLowerCase(), to = String(t.to || ZERO).toLowerCase();
      const ts = t.metadata ? Date.parse(t.metadata.blockTimestamp) / 1000 : null;
      if (ts) { if (firstTs == null) firstTs = ts; lastTs = ts; }
      if (f === ZERO) { if (!mintedTo) mintedTo = to; } else bal.set(f, (bal.get(f) || 0n) - v);
      bal.set(to, (bal.get(to) || 0n) + v);
    }
    let live = 0n; for (const [a, b] of bal) if (b > 0n && a !== ZERO && a !== DEAD) live += b;
    const burnB = (bal.get(ZERO) || 0n) + (bal.get(DEAD) || 0n);
    if (!supply || supply <= 0n) { supply = live + burnB; notes.push('链上 totalSupply 读取失败，总量按转账累加值推算'); }
    const pct = (b) => (supply > 0n ? Number((b * 1000000n) / supply) / 10000 : null);
    const dnum = (b) => (dec != null ? Number(b) / Math.pow(10, dec) : null);
    const list = [...bal.entries()].filter(([a, b]) => b > 0n && a !== ZERO && a !== DEAD).sort((a, b) => (a[1] < b[1] ? 1 : a[1] > b[1] ? -1 : 0));
    const top = list.slice(0, 20);
    let codes = [];
    if (top.length) { try { codes = await batch(env, chain, top.map(([a]) => ['eth_getCode', [a, 'latest']])); } catch (_) { codes = []; } }
    const holders = top.map(([a, b], i) => {
      const code = codes[i] && codes[i].v;
      const kind = mk && mk.pair === a ? 'pool' : code == null ? 'unknown' : code !== '0x' ? 'contract' : 'wallet';
      return { rank: i + 1, owner: a, kind, amount: dnum(b), pct: pct(b) };
    });
    const sumPct = (arr) => r4(arr.reduce((s, x) => s + (x.pct || 0), 0));
    const wallets = holders.filter((x) => x.kind === 'wallet');
    const conc = { top1: sumPct(holders.slice(0, 1)), top5: sumPct(holders.slice(0, 5)), top10: sumPct(holders.slice(0, 10)), top20: sumPct(holders), wallets10: sumPct(wallets.slice(0, 10)), nonWallet: sumPct(holders.filter((x) => x.kind !== 'wallet')), listed: holders.length };
    const f = [];
    f.push({ level: 'info', text: `共 ${list.length} 个持有人，已读完全部 ${sc.xs.length} 笔转账记录`, basis: `按转账累加还原，窗口覆盖${firstTs ? ' 自 ' + new Date(firstTs * 1000).toISOString().slice(0, 16).replace('T', ' ') + ' UTC' : '全部历史'}` });
    if (wallets.length >= 3) f.push({ level: conc.wallets10 >= 30 ? 'risk' : conc.wallets10 >= 15 ? 'warn' : 'ok', text: `前 ${Math.min(10, wallets.length)} 大普通钱包合计持有 ${conc.wallets10}%`, basis: '占总供应量；普通钱包 = 地址没有合约代码且不是已知池子' });
    if (conc.nonWallet >= 50) f.push({ level: 'info', text: `前 20 大持有人里 ${conc.nonWallet}% 在池子/合约中，不是普通钱包`, basis: '多为 AMM 池、发射台曲线合约、质押或锁仓合约' });
    if (holders[0] && holders[0].kind === 'wallet' && conc.top1 >= 20) f.push({ level: 'risk', text: `第 1 大持有人是普通钱包，持有 ${conc.top1}%`, basis: '地址 ' + holders[0].owner });
    if (mintedTo) { const mb = bal.get(mintedTo) || 0n; f.push({ level: 'info', text: `代币首次铸造给 ${mintedTo.slice(0, 8)}…，该地址当前持有 ${pct(mb)}%`, basis: '首笔来自零地址的转账接收方；可能是部署者、发射台或分发合约' }); }
    const bp = pct(burnB); if (bp != null && bp > 0) f.push({ level: 'info', text: `已销毁 ${bp}%（发送到零地址/dead 地址）`, basis: '转账累加' });
    if (mk && mk.createdAt) f.push({ level: 'info', text: '最深池子创建于 ' + new Date(mk.createdAt).toISOString().slice(0, 16).replace('T', ' ') + ' UTC', basis: 'Dexscreener pairCreatedAt' });
    return { ...base, complete: true, transferN: sc.xs.length, supply: dnum(supply), holderCount: list.length, burnedPct: bp, holders, concentration: conc, findings: f, notes };
  }

  // 合成数据自检：不联网，验证配对与盈亏口径
  function sim() {
    const W = '0x' + 'a'.repeat(40), T1 = '0x' + '1'.repeat(40), T2 = '0x' + '2'.repeat(40), T3 = '0x' + '3'.repeat(40), U = CH.eth.stables[0], R = '0x' + '9'.repeat(40);
    const x = (hash, block, from, to, value, category, contract, asset) => ({ hash, blockNum: hexBlock(block), from, to, value, category, asset: asset || null, rawContract: { address: contract || null }, metadata: { blockTimestamp: new Date((1700000000 + block * 12) * 1000).toISOString() } });
    const xs = [
      x('0xb1', 100, W, R, 1, 'external', null, 'ETH'), x('0xb1', 100, R, W, 1000, 'erc20', T1, 'AAA'),
      x('0xs1', 110, W, R, 600, 'erc20', T1, 'AAA'), x('0xs1', 110, R, W, 0.8, 'internal', null, 'ETH'),
      x('0xs2', 120, W, R, 400, 'erc20', T1, 'AAA'), x('0xs2', 120, R, W, 1.5, 'internal', null, 'ETH'),
      x('0xt1', 130, W, R, 50, 'erc20', T2, 'BBB'),
      x('0xb2', 140, W, R, 100, 'erc20', U, 'USDC'), x('0xb2', 140, R, W, 5000, 'erc20', T3, 'CCC'),
      x('0xs3', 150, W, R, 5000, 'erc20', T3, 'CCC'), x('0xs3', 150, R, W, 150, 'erc20', U, 'USDC'),
    ];
    const bt = build('eth', W, xs), pos = ledger(bt.trades);
    const out = Object.values(pos).map((p) => ({ mint: p.mint.slice(0, 6), q: p.q, realized: r4(p.realized), qty: p.qty, buys: p.buys, sells: p.sells }));
    return { trades: bt.trades.map((t) => ({ h: t.sig, side: t.side, q: t.q, amt: t.amt, qty: t.qty })), cands: bt.cands.map((c2) => c2.g.hash), multi: bt.multi, inbound: bt.inbound, pos: out, expect: 'AAA NATIVE realized=+0.3 (0.8+1.5-1.0=1.3? 见 pos)；BBB 转出为 cand；CCC USD realized=+50' };
  }

  return { ok, chains: Object.keys(CH), opWallet, opHolder, opToken, sim, hasKey: async (env) => !!((await vGet(env, 'alchemy')) || env.ALCHEMY_API_KEY) };
}
