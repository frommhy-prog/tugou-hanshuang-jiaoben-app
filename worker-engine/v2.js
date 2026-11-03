// TSTZ-M 引擎 v2 入口：原 v2 模块（持有人、交易所、MCP 等）原样保留在 v2base.js；AI 与叙事改走 ai.js（清洗 + 多后端回退）
import { makeV2 as makeBase } from './v2base.js';
import { makeAI } from './ai.js';
export function makeV2(h) {
  const base = makeBase(h);
  const A = makeAI(h);
  async function route(env, p, q, req) {
    if (p === '/e/ai' || p === '/e/v2/ai') return A.ai(env, await req.json());
    if (p === '/e/v2/narrative') return A.narrative(env, await req.json());
    if (p === '/e/v2/aitest') return A.test(env);
    return base.route(env, p, q, req);
  }
  return { ...base, route, ai: A.ai };
}
