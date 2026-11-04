# TSTZ-M 源码补丁（CI 里在编译前执行）。按文件事务：某个文件的任一锚点不匹配，该文件整体不改；已应用的补丁按标签跳过，可重复运行。
import sys, pathlib, importlib.util

ROOT = pathlib.Path(__file__).resolve().parents[2]
LEDGER = ROOT / '.github' / 'patches' / 'applied.txt'
applied = set(LEDGER.read_text(encoding='utf-8').split()) if LEDGER.exists() else set()
files = {}
bad = {}
done = {}


def load(p):
    if p not in files:
        files[p] = (ROOT / p).read_text(encoding='utf-8')
    return files[p]


def rep(tag, p, old, new):
    if tag in applied or p in bad:
        return
    t = load(p)
    n = t.count(old)
    if n != 1:
        bad[p] = '%s: 锚点匹配 %d 次（需要 1 次）:: %r' % (tag, n, old[:80])
        return
    files[p] = t.replace(old, new)
    done.setdefault(p, []).append(tag)


def cut(tag, p, start, end, new):
    if tag in applied or p in bad:
        return
    t = load(p)
    if t.count(start) != 1:
        bad[p] = '%s: 起点匹配 %d 次 :: %r' % (tag, t.count(start), start[:80])
        return
    i = t.index(start)
    if end is None:
        j = len(t)
    else:
        if t.count(end) != 1:
            bad[p] = '%s: 终点匹配 %d 次 :: %r' % (tag, t.count(end), end[:80])
            return
        j = t.index(end)
        if j < i:
            bad[p] = '%s: 终点在起点之前' % tag
            return
    files[p] = t[:i] + new + t[j:]
    done.setdefault(p, []).append(tag)


spec = importlib.util.spec_from_file_location('plist', str(ROOT / '.github' / 'patches' / 'plist.py'))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.register(rep, cut)

ok_tags = []
for p, t in files.items():
    if p in bad:
        continue
    (ROOT / p).write_text(t, encoding='utf-8')
    ok_tags += done.get(p, [])
if ok_tags:
    LEDGER.write_text('\n'.join(sorted(applied | set(ok_tags))) + '\n', encoding='utf-8')
for p, e in bad.items():
    print('PATCH_FAILED', p, e)
print('PATCH_OK', ' '.join(ok_tags) if ok_tags else '(none new)')
