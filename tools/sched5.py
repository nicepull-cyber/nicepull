"""Nice Pull, Nov 27 2026: every game from #3 on is 5 prompts (Austin).
Mix: NFL 1, NCAA 1 (College, or a Crossover school prompt), MLB 1, NBA 1, Mixed Bag 1 (golf, Olympics, tennis,
other crossovers). When the Mixed Bag or NCAA pools run dry the slot falls back to NFL (NFL 1-2 per Austin).
Order: three bigger/easier prompts first; prompt 4 (x2) the harder one; prompt 5 (x3) hard + smallest pool.
Same rules as before: no prompt twice anywhere, no prompt type twice in a game, no team/school/person twice in a game,
no type+sport from the previous day, at most 2 stat prompts, at most 1 award prompt. Games 0-2 (played) untouched;
Game #3 is Austin's test game."""
import json, re, random, collections, sys
sys.path.insert(0, '/tmp'); from famlib import is_stat, fam, ent
NP = '/home/claude/nicepull/data.json'
d = json.load(open(NP)); B = d['bank']; S = d['schedule']; NG = len(S)
gi = lambda n: (n - 1 + 79) % NG          # Nice Pull game #n -> schedule index
FIXED = {0: S[gi(0) if False else 78], 1: S[gi(1)], 2: S[gi(2)]}
qi = lambda q: next(i for i, p in enumerate(B) if p['q'] == q and not p.get('retired'))
G3 = [qi('Played for the Spurs'), qi('Threw a pass to Larry Fitzgerald'), qi('Won a tennis major'), qi('Won the Home Run Derby'),
      qi('Scored 10+ TDs in a season for the Falcons')]
used = {i for g in FIXED.values() for i in g} | set(G3)
SCHOOL = re.compile(r"^(Went to |Played college|Played QB at|Drafted out of|First-round pick out of|Won the Heisman)")
def bucket(p):
    s = p['s']
    if s in ('NFL', 'NBA', 'MLB'): return s
    if s == 'College': return 'NCAA'
    if s == 'Crossover': return 'NCAA' if SCHOOL.match(p['q']) else 'Mixed'
    return 'Mixed'          # Golf, Olympics, Tennis
size = lambda p: sum(map(len, p['t']))
DR = {'easy': 0, 'medium': 1, 'hard': 2}
hard = lambda p: (DR[p['d']], -size(p))          # bigger = harder
pool = collections.defaultdict(list)
for i, p in enumerate(B):
    if p.get('retired') or i in used or size(p) < 6: continue
    pool[bucket(p)].append(i)
rnd = random.Random(1128)
for k in pool: rnd.shuffle(pool[k])
avail0 = {k: collections.Counter(B[i]['d'] for i in v) for k, v in pool.items()}
usedd = collections.defaultdict(collections.Counter)
print({k: len(v) for k, v in pool.items()})
def ok(i, game, prev, lvl):
    p = B[i]; g = [B[j] for j in game]
    if lvl < 3:
        if any(fam(p) == fam(q) for q in g): return False
        if ent(p) & set().union(set(), *[ent(q) for q in g]): return False
    if lvl < 2:
        if (fam(p), p['s']) in {(fam(B[j]), B[j]['s']) for j in prev}: return False
        if ent(p) & set().union(set(), *[ent(B[j]) for j in prev]): return False
        if is_stat(p) and sum(is_stat(q) for q in g) >= 2: return False
        if (p.get('award') or fam(p) == 'award') and any(q.get('award') or fam(q) == 'award' for q in g): return False
    return True
def pick(bk, game, prev, want_hard):
    cands = pool[bk]
    for lvl in (1, 2, 3):
        best = None
        for i in cands:
            if not ok(i, game, prev, lvl): continue
            p = B[i]; dd = p['d']
            # keep each difficulty's share of the bucket even across the season
            bal = usedd[bk][dd] / max(1, avail0[bk][dd])
            want = 0 if not want_hard else (0 if dd != 'easy' else 0.6)
            # small team-specific MLB stat prompts are too hard (Austin, Nov 27: Marlins 30+ homers)
            tough_mlb = p['s'] == 'MLB' and is_stat(p) and re.search(r' for (the )?[A-Z]', p['q']) and size(p) < 40
            sc = bal + want + (2 if tough_mlb else 0) + rnd.random() * 0.05
            if best is None or sc < best[0]: best = (sc, i)
        if best: return best[1], lvl
    return None, 9
def order(game):
    ps = sorted(game, key=lambda i: hard(B[i]))
    last2 = ps[-2:]; first3 = sorted(ps[:3], key=lambda i: -size(B[i]))
    seq = first3 + last2
    # no sport twice in a row: shuffle the first three if needed
    import itertools
    for perm in itertools.permutations(first3):
        s = list(perm) + last2
        if all(B[s[k]]['s'] != B[s[k + 1]]['s'] for k in range(4)): return s
    return seq
new = {}; prev = G3; log = collections.Counter(); notes = []
for n in range(4, NG + 1):
    game = []
    slots = ['NFL', 'NCAA', 'MLB', 'NBA', 'Mixed']; rnd.shuffle(slots)
    for k, bk in enumerate(slots):
        want_hard = k >= 3 and not any(B[j]['d'] != 'easy' for j in game)
        tries = [bk] + (['NFL', 'NCAA'] if bk == 'Mixed' else ['NFL'] if bk == 'NCAA' else ['NFL', 'NBA', 'MLB'])
        got = None
        for b2 in tries:
            i, lvl = pick(b2, game, prev, want_hard)
            if i is not None and lvl <= 2: got = (i, lvl, b2); break
        if got is None:
            for b2 in tries:
                i, lvl = pick(b2, game, prev, want_hard)
                if i is not None: got = (i, lvl, b2); break
        i, lvl, b2 = got
        game.append(i); pool[b2].remove(i); usedd[b2][B[i]['d']] += 1
        log[(bk, b2)] += 1; log['lvl%d' % lvl] += 1
        if b2 != bk: notes.append((n, bk, b2))
    game = order(game); new[n] = game; prev = game
for n, g in new.items(): S[gi(n)] = g
S[gi(3)] = G3
# verify
flat = [i for k, g in enumerate(S) for i in g]
assert len(flat) == len(set(flat)), 'prompt reused'
for n in range(3, NG + 1): assert len(S[gi(n)]) == 5
print(dict(log))
first_fb = sorted({n for n, a, b in notes})
print('fallback games:', len(first_fb), 'first:', first_fb[:5])
print({k: len(v) for k, v in pool.items()}, 'left unused')
if '--dry' not in sys.argv:
    json.dump(d, open(NP, 'w'), separators=(',', ':'), ensure_ascii=False); print('saved')
for n in range(3, 10):
    print(n, ' / '.join(f"{B[i]['s']}:{B[i]['q']}({size(B[i])},{B[i]['d'][0]})" for i in S[gi(n)]))
