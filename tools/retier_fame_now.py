"""Nice Pull, Nov 27 2026 — "fame-now" re-tier (Austin: "i want ppl to score more points when possible").
Players were landing on Chalk/Box Score 65% of the time. Only names every fan knows TODAY keep the low tiers.

On every active prompt (locked ones excepted), each Chalk or Box Score Guy answer keeps its tier only if he is
  ICON     on the hand icon/fame lists (any era), or Hall of Famer / superstar by honors / MVP with a career reaching 1995
  CURRENT  active now (NFL 2026 roster, NBA 2025-26/2026-27, MLB 2025) AND known by honors or on the young-stars list
  FACE     the first Chalk name on the prompt (two on team prompts) when he's known by honors (Julio, Marshall for Cutler)
Everyone else drops: career ended before 2000 -> Deep Cut, otherwise -> Nice Pull.
Names with no pro record (college-only, golf, Olympics, tennis) are left alone. Then a cap: Chalk + Box Score
at most 5 (pools under 40), 8 (under 150), 10 (under 400) or 12; icons and current stars are kept first, overflow -> Nice Pull. Every prompt keeps 1+ Chalk.
Only moves answers DOWN (more points)."""
import json, re, sys, io, contextlib, collections
import pandas as pd
src = open('/home/claude/build/fix_franchise_stars.py').read().split("moves = []; DRY")[0]
ns = {'__file__': 'ff'}
with contextlib.redirect_stdout(io.StringIO()):
    exec(src, ns)
un, known, superstar, ICONS, LASTS, TL = ns['un'], ns['known'], ns['superstar'], ns['ICONS'], ns['LASTS'], ns['TL']
NP = '/home/claude/nicepull/data.json'
d = json.load(open(NP)); N = d['names']; B = d['bank']; S = d['schedule']
ys = open('/home/claude/build/young_stars.py').read()
STARS = {un(s.strip()) for s in re.search(r'STARS = """(.*?)"""', ys, re.S).group(1).replace('\n', ' ').split(',') if s.strip()}
OLD_NFL = """Franco Harris, Lynn Swann, John Stallworth, Joe Greene, Jack Lambert, Mel Blount, Jack Ham, Earl Campbell, Tony Dorsett,
Fran Tarkenton, Ken Stabler, Dan Fouts, Bob Griese, Larry Csonka, Paul Hornung, Mike Ditka, Ray Nitschke, Deacon Jones, Bob Hayes,
Lance Alworth, Fred Biletnikoff, Gene Upshaw, Art Shell, Ted Hendricks, Steve Largent, Ozzie Newsome, Kellen Winslow, Randy White,
Tom Dempsey, Mean Joe Greene, Don Shula, John Riggins, Marcus Allen, Eric Dickerson, Howie Long, Ronnie Lott, Mike Singletary,
Jim Plunkett, Joe Theismann, William Perry, Jim McMahon, Lester Hayes, Sam Huff, Frank Gifford, Y.A. Tittle, Len Dawson, George Blanda,
Night Train Lane, Dick Lane, Elroy Hirsch, Raymond Berry, Lenny Moore, Merlin Olsen, Jack Youngblood, Alan Page, Carl Eller, Paul Warfield,
Bob Lilly, Chuck Bednarik, Doak Walker, Sid Luckman, Bronko Nagurski, Red Grange, Jim Thorpe, Sammy Baugh, Don Hutson, Otto Graham"""
ICONS['NFL'] |= {un(x.strip()) for x in OLD_NFL.replace('\n', ' ').split(',') if x.strip()}
# 2026 starting QBs: most pass attempts for each team in 2026
pb = pd.read_parquet('/home/claude/pbp/p2026.parquet', columns=['posteam', 'passer_player_name', 'passer_player_id', 'pass_attempt'])
pl = pd.read_csv('/home/claude/pbp/players.csv', low_memory=False); fulln = dict(zip(pl.gsis_id, pl.display_name))
qb = pb[pb.pass_attempt == 1].groupby(['posteam', 'passer_player_id']).size().reset_index(name='n').sort_values('n').groupby('posteam').tail(1)
QB26 = {un(fulln.get(i, '')) for i in qb.passer_player_id}
# extra hall of fame: NBA (Basketball Reference) and NFL draft data are inside known/superstar via honors; add NBA HOF flag
ci = pd.read_csv('/home/claude/dl/bbr/Player_Career_Info.csv'); HOFNBA = {un(p) for p in ci[ci.hof == True].player}
dp = pd.read_csv('/tmp/dp.csv', low_memory=False); HOFNFL = {un(str(p)) for p in dp[dp.hof.astype(str).str.upper() == 'TRUE'].pfr_player_name}
hof = pd.read_csv('/home/claude/mlb25/HallOfFame.csv'); ppl = pd.read_csv('/home/claude/mlb25/People.csv')
nmm = {r.playerID: f"{r.nameFirst} {r.nameLast}" for r in ppl.itertuples()}
HOFMLB = {un(nmm.get(p, '')) for p in hof[(hof.inducted == 'Y') & (hof.category == 'Player')].playerID}
# famous to every fan without the honors to prove it, recent Hall of Fame classes the data predates, league MVPs
FAME = {'NFL': '''Tim Tebow, Johnny Manziel, Vince Young, Robert Griffin III, Michael Vick, Cam Newton, Marshawn Lynch, Chad Johnson,
Odell Beckham Jr., Antonio Brown, Reggie Bush, Brian Bosworth, Ricky Williams, Tony Romo, Eli Manning, Philip Rivers,
Ben Roethlisberger, Matt Ryan, Julio Jones, Larry Fitzgerald, Calvin Johnson, Jason Witten, Antonio Gates, Reggie Wayne, Jared Allen,
Rob Gronkowski, Adrian Peterson, LaDainian Tomlinson, Drew Brees, Peyton Manning, Tom Brady, Ray Lewis, Ed Reed, Troy Polamalu, J.J. Watt,
Aaron Donald, Julian Edelman, Wes Welker, Drew Bledsoe, Russell Wilson, Aaron Rodgers, Matthew Stafford, Kirk Cousins, Derek Carr, Ezekiel Elliott, Le'Veon Bell, DeAndre Hopkins''',
 'NBA': '''Carmelo Anthony, Vince Carter, Tracy McGrady, Yao Ming, Dwight Howard, Chris Paul, Paul Pierce, Ray Allen, Kyrie Irving,
Klay Thompson, Draymond Green, Jimmy Butler, Blake Griffin, Derrick Rose, Jeremy Lin, Lonzo Ball, Zion Williamson, Ja Morant,
Russell Westbrook, James Harden, Kevin Love, Pau Gasol, Tony Parker, Manu Ginóbili, Damian Lillard, Paul George, Kawhi Leonard,
Rajon Rondo, Kevin Garnett, Steve Nash, Jason Kidd, Dennis Rodman, Ben Wallace, Rasheed Wallace, Grant Hill, Alonzo Mourning''',
 'MLB': '''Derek Jeter, Alex Rodriguez, David Ortiz, Barry Bonds, Roger Clemens, Sammy Sosa, Mark McGwire, Manny Ramirez, Ichiro Suzuki,
Albert Pujols, Miguel Cabrera, Buster Posey, Clayton Kershaw, Justin Verlander, Max Scherzer, Mike Trout, Bryce Harper, Pedro Martinez,
Randy Johnson, Greg Maddux, Chipper Jones, Mariano Rivera, Jose Canseco, Bo Jackson, Ken Griffey Jr., Vladimir Guerrero, Joey Votto'''}
FAME = {s: {un(x.strip()) for x in v.replace('\n', ' ').split(',') if x.strip()} for s, v in FAME.items()}
MVPS = {'NFL': 'aw_nfl_mvp', 'NBA': 'nba_mvp', 'MLB': 'mlb_aw_mvp'}
MVPW = {sp: set() for sp in MVPS}
for sp, pid in MVPS.items():
    for p in B:
        if p['id'] == pid: MVPW[sp] |= {un(N[i][0]) for i in sum(p['t'], [])}
# hand lists count in any era; Hall of Fame / honors / MVP count only for careers that reached 1995
# (Austin: only true icons are Chalk from the old eras; Riggs on the Falcons is a Deep Cut)
HANDICON = {sp: ICONS[sp] | FAME[sp] for sp in FAME}
HONORICON = {'NFL': HOFNFL | superstar['NFL'] | MVPW['NFL'], 'NBA': HOFNBA | superstar['NBA'] | MVPW['NBA'], 'MLB': HOFMLB | superstar['MLB'] | MVPW['MLB']}
ACTIVE = {'NFL': 2026, 'NBA': 2026, 'MLB': 2025}
LOCKED_Q = {'Scored 10+ TDs in a season for the Falcons', 'Threw a pass to Larry Fitzgerald', 'Won a tennis major',
            'Played at least one snap for Sean Payton', 'Caught a pass from Jay Cutler', 'Caught a pass from Josh Allen', 'Caught a pass from Alex Smith'}
LOCKED_ID = {'gm_20hr_NYY'}
# Austin's hand calls that must keep their low tier (prompt, name)
HAND = {('Had 200+ hits in a season', 'Pete Rose'), ('Had 200+ hits in a season', 'Ty Cobb')}
SKIP_SP = {'Golf', 'Olympics', 'Tennis'}
def sports_for(p):
    s = p['s']
    if s in ('NFL', 'NBA', 'MLB'): return [s]
    if s in ('College', 'Crossover'): return ['NFL', 'NBA']
    return []
TEAMQ = re.compile(r'^(Played for (the )?|Won .* with the |Played for both)')
def status(i, sps):
    u = un(N[i][0]); best = None
    for sp in sps:
        last = LASTS[sp].get(u)
        if last is None: continue
        icon = u in HANDICON[sp] or (u in HONORICON[sp] and last >= 1995)
        cur = last >= ACTIVE[sp] and (u in known[sp] or u in STARS)
        k = (u in known[sp] and last >= 1995) or icon
        r = dict(last=last, icon=icon, cur=cur, known=k)
        if best is None or (r['icon'], r['cur'], r['last']) > (best['icon'], best['cur'], best['last']): best = r
    return best
def cap(n): return 5 if n < 40 else 8 if n < 150 else 10 if n < 400 else 12
sched = {i for g in S for i in g}
moves = collections.Counter(); per = []; examples = []
for pi, p in enumerate(B):
    if p.get('retired') or p['q'] in LOCKED_Q or p['id'] in LOCKED_ID: continue
    sps = sports_for(p); n = sum(map(len, p['t']))
    t = [list(x) for x in p['t']]
    low = t[0] + t[1]; keep0, keep1, down3, down4 = [], [], [], []
    if sps:
        nface = 2 if TEAMQ.match(p['q']) else 1
        for pos, i in enumerate(low):
            st = status(i, sps); tier = 0 if pos < len(t[0]) else 1
            if st is None: (keep0 if tier == 0 else keep1).append(i); continue
            face = (tier == 0 and pos < nface and st['known']) or (p['q'], N[i][0]) in HAND
            if st['icon'] or st['cur'] or face: (keep0 if tier == 0 else keep1).append(i)
            elif st['last'] < 2000: down4.append(i)
            else: down3.append(i)
    else:
        keep0, keep1 = t[0][:], t[1][:]
    c = cap(n)
    # the true icons (hand list) and Austin's hand calls never count against the cap
    free = {i for i in keep0 + keep1 if (p['q'], N[i][0]) in HAND or any(un(N[i][0]) in ICONS[sp] for sp in sps)}
    c += len(free)
    if len(keep0) + len(keep1) > c:
        # keep icons and current stars first, then the rest in their existing (fame) order
        def pri(i):
            st = status(i, sps) if sps else None
            if i in free: return (0, low.index(i))
            return (1 if st and st['cur'] else 2 if st and st['icon'] else 3, low.index(i))
        ranked = sorted(keep0 + keep1, key=pri); keepset = set(ranked[:c])
        over = [i for i in keep0 + keep1 if i not in keepset]
        keep0 = [i for i in keep0 if i in keepset]; keep1 = [i for i in keep1 if i in keepset]
        down3 = over + down3
    if not keep0:
        if keep1: keep0.append(keep1.pop(0))
        elif down3 or down4:
            src = down3 if down3 and (not down4 or low.index(down3[0]) < low.index(down4[0])) else down4
            keep0.append(src.pop(0))
    if down3 or down4:
        t[0], t[1] = keep0, keep1
        t[3] = down3 + t[3]; t[4] = down4 + t[4]
        if pi in sched: per.append((p['q'], [N[i][0] for i in down3], [N[i][0] for i in down4]))
        moves['NP'] += len(down3); moves['DC'] += len(down4); moves['prompts'] += 1
        p['t'] = t
print(dict(moves))
import random; random.seed(3)
for q, a, b in random.sample(per, min(25, len(per))): print('-', q, '| NP:', a[:6], '| DC:', b[:6])
# distribution after
c = collections.Counter(); tot = 0
for i in sched:
    p = B[i]
    if p.get('retired'): continue
    for k, x in enumerate(p['t']): c[k] += len(x)
print({k: v for k, v in sorted(c.items())})
if '--dry' not in sys.argv: json.dump(d, open(NP, 'w'), separators=(',', ':'), ensure_ascii=False); print('saved')
