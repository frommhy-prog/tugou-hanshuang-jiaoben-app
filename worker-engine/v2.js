// TSTZ-M 引擎 v2 入口：原 v2 模块（持有人、交易所、MCP 等）原样保留在 v2base.js；AI 与叙事改走 ai.js（清洗 + 多后端回退）；情报（EVM 持有人多读页、钱包关联）走 intel.js；上游调用计数走 usage.js（/e/usage）
import { makeV2 as makeBase } from './v2base.js';
import { makeAI } from './ai.js';
import { makeIntel } from './intel.js';
import { installUsage, usageReport } from './usage.js';
export function makeV2(h) {
  const base = makeBase(h);
  const A = makeAI(h);
  const I = makeIntel(h);
  async function route(env, p, q, req) {
    installUsage(env); // 每次请求先登记 env，并保证全局 fetch 已被计数包装
    if (p === '/e/usage') return usageReport(env);
    if (p === '/e/ai' || p === '/e/v2/ai') return A.ai(env, await req.json());
    if (p === '/e/v2/narrative') return A.narrative(env, await req.json());
    if (p === '/e/v2/aitest') return A.test(env);
    if (p === '/e/v2/holders2') return I.holders(env, q);
    if (p === '/e/v2/links') return I.links(env, q);
    return base.route(env, p, q, req);
  }
  return { ...base, route, ai: A.ai };
}
