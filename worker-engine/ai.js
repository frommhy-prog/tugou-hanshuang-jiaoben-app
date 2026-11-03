// TSTZ-M 引擎 AI 模块 v3：Groq 多模型 + 可选密钥后端依次回退；模型输出严格清洗（数组里混进空字符串、字段形状不对都修正）；坏结果不缓存。不使用 Cloudflare Workers AI。
export function makeAI(h) {
  const { vGet, now } = h;
  const enc = new TextEncoder();
  const GROQ = 'https://api.groq.com/openai/v1';
  const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
  const sha = async (s) => hex(await crypto.subtle.digest('SHA-256', enc.encode(s))).slice(0, 32);
  const E = (code, detail, status) => Object.assign(new Error(code), { code, detail, status });
  async function cget(env, key, ttl) {
    const c = await env.DB.prepare('SELECT v, at FROM cache WHERE k=?').bind(key).first();
    if (c && now() - c.at < ttl) { try { return JSON.parse(c.v); } catch (_) {} }
    return null;
  }
  async function cput(env, key, v) { await env.DB.prepare('INSERT OR REPLACE INTO cache (k,v,at) VALUES (?,?,?)').bind(key, JSON.stringify(v), now()).run(); }
  async function tfetch(url, init, ms) {
    const ac = new AbortController();
    const t = setTimeout(() => ac.abort(), ms);
    try { return await fetch(url, { ...init, signal: ac.signal }); } finally { clearTimeout(t); }
  }

  // ---------- 清洗 ----------
  const S = (v, n = 400) => {
    if (v == null) return '';
    if (typeof v === 'string') return v.trim().slice(0, n);
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    if (Array.isArray(v)) return v.map((x) => S(x, n)).filter(Boolean).join('；').slice(0, n);
    if (typeof v === 'object') return Object.values(v).map((x) => S(x, n)).filter(Boolean).join('：').slice(0, n);
    return '';
  };
  const L = (v, max, n = 200) => {
    const a = Array.isArray(v) ? v : v == null || v === '' ? [] : [v];
    return a.map((x) => S(x, n)).filter(Boolean).slice(0, max);
  };
  const STANCES = ['偏风险', '中性', '偏积极', '数据不足'];
  function normAI(a) {
    if (!a || typeof a !== 'object') return null;
    const pts = [];
    for (const p of Array.isArray(a.points) ? a.points : []) {
      if (typeof p === 'string') { const c = S(p, 160); if (c) pts.push({ claim: c, why: '', evidence: '' }); }
      else if (p && typeof p === 'object') {
        const claim = S(p.claim ?? p.point ?? p.title, 160);
        if (claim) pts.push({ claim, why: S(p.why ?? p.reason, 300), evidence: S(p.evidence ?? p.basis, 300) });
      }
      if (pts.length >= 6) break;
    }
    let stance = S(a.stance, 12);
    if (!STANCES.includes(stance)) stance = stance.includes('险') ? '偏风险' : stance.includes('积极') ? '偏积极' : stance.includes('不足') ? '数据不足' : '中性';
    return { headline: S(a.headline ?? a.summary, 80), stance, points: pts, risks: L(a.risks, 4), watch: L(a.watch, 5), unknown: L(a.unknown, 6) };
  }
  const okAI = (a) => a && a.points.length >= 1 && a.headline;
  function normNarr(a) {
    if (!a || typeof a !== 'object') return null;
    let c = S(a.confidence, 4);
    if (!['低', '中', '高'].includes(c)) c = '低';
    return { narrative: S(a.narrative, 200), themes: L(a.themes, 3, 30), keywords: L(a.keywords, 4, 30), evidence: L(a.evidence, 4), risks: L(a.risks, 4), unknown: L(a.unknown, 5), confidence: c };
  }
  const okNarr = (a) => a && a.narrative;
  function extractJson(txt) {
    if (!txt) return null;
    const tries = [txt];
    const i = txt.indexOf('{'), j = txt.lastIndexOf('}');
    if (i >= 0 && j > i) tries.push(txt.slice(i, j + 1));
    for (const t of tries) {
      for (const s of [t, t.replace(/,\s*([}\]])/g, '$1')]) { try { const o = JSON.parse(s); if (o && typeof o === 'object') return o; } catch (_) {} }
    }
    return null;
  }

  // ---------- 提示词 ----------
  const AI_SYS = '你是为链上交易员服务的分析师。输入 facts 是程序已从链上算出的结果（持有人成本/盈亏/入场时点、集中度、池子与成交流向、风险项等）。任务是给出看完数据后的判断，而不是复述数据。规则：1）headline：一句话结论（不超过30字）；stance 只能是「偏风险」「中性」「偏积极」「数据不足」之一，这只是风险评估，不是买卖建议；2）points 3 到 6 条，每条都是对象 {claim, why, evidence}，三个字段必须是非空字符串。claim 是推断出的含义（例如“多个大户在同一时段买入，疑似同一团队控盘”，禁止只复述数字）；why 写清因果；evidence 用自然语言引用 facts 里的具体数字，数字必须逐字取自 facts，不得自相矛盾，严禁出现字段名、下标、JSON 路径；3）risks：最该警惕的 1 到 3 点（字符串）；watch：接下来该盯的 2 到 4 个可验证信号（字符串）；4）unknown：facts 缺失、无法判断的事（字符串）；5）只能使用 facts 里的数字，禁止编造数字、地址、事件；样本少或窗口不全必须明说；6）数组里只能放对象或字符串，禁止出现空字符串、null、嵌套数组。只输出 JSON：{"headline":"","stance":"","points":[{"claim":"","why":"","evidence":""}],"risks":[""],"watch":[""],"unknown":[""]}。全部使用简体中文。';
  const NARR_SYS = '你是加密叙事研究员。输入是某代币的名称、符号、简介、社交链接、分类（来自公开资料，可能为空）。任务：1）narrative：用一句话说明这个代币在讲什么故事、蹭什么热点，只能依据输入文字推断；输入太少无法判断就写“信息不足”；2）themes：1 到 3 个主题标签；3）keywords：2 到 4 个用于搜索同类代币的词，必须取自名称/简介里真实出现的词；4）evidence：每条引用输入里的原文片段；5）risks：叙事层面的风险；6）unknown：输入里没有、无法判断的事；7）confidence：「低」「中」「高」。严禁编造团队、合作、事件、数据。数组里只能放字符串，禁止空字符串。只输出 JSON：{"narrative":"","themes":[""],"keywords":[""],"evidence":[""],"risks":[""],"unknown":[""],"confidence":""}。全部使用简体中文。';

  // ---------- 后端 ----------
  const MODEL_PREF = ['llama-3.3-70b-versatile', 'openai/gpt-oss-120b', 'openai/gpt-oss-20b', 'llama-3.1-8b-instant'];
  async function groqModels(env, key) {
    const c = await env.DB.prepare("SELECT v FROM kv WHERE k='groq_model4'").first();
    if (c) { try { const o = JSON.parse(c.v); if (now() - o.at < 6 * 3600e3) return o.list; } catch (_) {} }
    let list = MODEL_PREF;
    try {
      const r = await tfetch(GROQ + '/models', { headers: { authorization: 'Bearer ' + key } }, 8000);
      if (r.ok) { const ids = ((await r.json()).data || []).map((m) => m.id); const got = MODEL_PREF.filter((m) => ids.includes(m)); if (got.length) list = got; }
    } catch (_) {}
    await env.DB.prepare("INSERT OR REPLACE INTO kv (k,v) VALUES ('groq_model4',?)").bind(JSON.stringify({ list, at: now() })).run();
    return list;
  }
  async function groqCall(env, key, model, sys, user, maxTokens) {
    const payload = { model, temperature: 0.2, max_tokens: maxTokens, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: sys }, { role: 'user', content: user }] };
    if (/gpt-oss/.test(model)) payload.reasoning_effort = 'low';
    const r = await tfetch(GROQ + '/chat/completions', { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + key }, body: JSON.stringify(payload) }, 28000);
    const hdr = { status: r.status, model };
    for (const [k, v] of r.headers) if (k.startsWith('x-ratelimit') || k === 'retry-after') hdr[k] = v;
    try { await env.DB.prepare('INSERT OR REPLACE INTO quota (provider,hdr,at) VALUES (?,?,?)').bind('groq', JSON.stringify(hdr), now()).run(); } catch (_) {}
    const txt = await r.text();
    if (!r.ok) throw E('groq_' + r.status, txt.slice(0, 160), r.status);
    const j = JSON.parse(txt);
    return (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || '';
  }
  // 其余免费后端（OpenAI 兼容接口）：有密钥才启用（Secret 或密钥库），没有就跳过
  const COMPAT = [
    { id: 'cerebras', env: 'CEREBRAS_API_KEY', url: 'https://api.cerebras.ai/v1/chat/completions', models: ['gpt-oss-120b', 'llama-3.3-70b'] },
    { id: 'gemini', env: 'GEMINI_API_KEY', url: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions', models: ['gemini-2.5-flash', 'gemini-2.0-flash'] },
    { id: 'openrouter', env: 'OPENROUTER_API_KEY', url: 'https://openrouter.ai/api/v1/chat/completions', models: ['openai/gpt-oss-120b:free', 'meta-llama/llama-3.3-70b-instruct:free'] },
    { id: 'mistral', env: 'MISTRAL_API_KEY', url: 'https://api.mistral.ai/v1/chat/completions', models: ['mistral-small-latest'] },
  ];
  async function compatCall(p, key, model, sys, user, maxTokens) {
    const r = await tfetch(p.url, { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + key }, body: JSON.stringify({ model, temperature: 0.2, max_tokens: maxTokens, messages: [{ role: 'system', content: sys }, { role: 'user', content: user }] }) }, 28000);
    const txt = await r.text();
    if (!r.ok) throw E(p.id + '_' + r.status, txt.slice(0, 160), r.status);
    const j = JSON.parse(txt);
    return (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || '';
  }

  async function llm(env, o) {
    if (!o.fresh) { const c = await cget(env, o.ck, 15 * 60e3); if (c) return { ...c, cached: true }; }
    const errs = [], t0 = now();
    const attempt = async (label, fn) => {
      try {
        const obj = extractJson(await fn());
        const a = obj && o.norm(obj);
        if (a && o.ok(a)) return a;
        errs.push(label + ':bad_output');
      } catch (e) { errs.push(label + ':' + String((e && (e.code || e.message)) || e).slice(0, 60)); }
      return null;
    };
    const done = async (a, model, provider) => {
      const res = { analysis: a, model, provider, generatedAt: now() };
      await cput(env, o.ck, res);
      return res;
    };
    const gk = await vGet(env, 'groq');
    if (gk) {
      for (const model of await groqModels(env, gk)) {
        if (now() - t0 > 40000) break;
        const a = await attempt('groq/' + model, () => groqCall(env, gk, model, o.sys, o.user, o.maxTokens));
        if (a) return done(a, model, 'groq');
      }
    } else errs.push('groq:no_key');
    for (const p of COMPAT) {
      const key = env[p.env] || (await vGet(env, p.id));
      if (!key) continue;
      for (const model of p.models) {
        if (now() - t0 > 55000) break;
        const a = await attempt(p.id + '/' + model, () => compatCall(p, key, model, o.sys, o.user, o.maxTokens));
        if (a) return done(a, model, p.id);
      }
    }
    return { error: gk ? 'ai_all_failed' : 'no_groq_key', detail: errs.join(' | ').slice(0, 300) };
  }

  async function ai(env, body) {
    const facts = JSON.stringify(body.facts || {}).slice(0, 3800);
    return llm(env, { sys: AI_SYS, user: '类型：' + (body.kind || '') + '\nfacts：' + facts, ck: 'ai4:' + (await sha((body.kind || '') + facts)), fresh: body.fresh, maxTokens: 1200, norm: normAI, ok: okAI });
  }
  async function narrative(env, body) {
    const f = { 名称: String(body.name || '').slice(0, 80), 符号: String(body.symbol || '').slice(0, 30), 链: String(body.chain || ''), 简介: String(body.description || '').slice(0, 1200), 分类: body.categories || [], 社交: body.socials || [], 官网: body.websites || [] };
    const facts = JSON.stringify(f).slice(0, 3000);
    return llm(env, { sys: NARR_SYS, user: '代币资料：' + facts, ck: 'nr2:' + (await sha(facts)), fresh: body.fresh, maxTokens: 800, norm: normNarr, ok: okNarr });
  }
  // 自检：每个后端发一条极短请求，返回是否可用与耗时
  async function test(env) {
    const out = [];
    const probe = async (label, fn) => {
      const t = now();
      try { const o = extractJson(await fn()); out.push({ p: label, ok: !!o, ms: now() - t }); } catch (e) { out.push({ p: label, ok: false, ms: now() - t, err: String((e && (e.code || e.message)) || e).slice(0, 80), detail: String((e && e.detail) || '').slice(0, 120) }); }
    };
    const gk = await vGet(env, 'groq');
    if (gk) for (const m of await groqModels(env, gk)) await probe('groq/' + m, () => groqCall(env, gk, m, '只输出 JSON', '输出 {"ok":true}', 40));
    else out.push({ p: 'groq', ok: false, err: 'no_key' });
    for (const p of COMPAT) { const key = env[p.env] || (await vGet(env, p.id)); if (key) await probe(p.id + '/' + p.models[0], () => compatCall(p, key, p.models[0], '只输出 JSON', '输出 {"ok":true}', 40)); else out.push({ p: p.id, ok: false, err: 'no_key' }); }
    return { providers: out, at: now() };
  }
  return { ai, narrative, test, _t: { normAI, normNarr, extractJson } };
}
