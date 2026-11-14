#!/usr/bin/env python3
"""Captures focused reference cases for spitters, projectiles and parries.

Usage:  python3 -I tools/reference/capture_spitters_and_parries.py [out.json]
        (the committed copy is godot/tests/reference/spitters_and_parries.json)

Slice #10 of the Godot port. Like capture_crowd_and_walls.py (whose loader and
helpers it reuses) it drives the prototype's REAL classes -- `Game`, `Enemy`,
`Projectile`, `Sword`, `Player` from game/main.py -- with fixed 1/60 s steps under
SDL's dummy drivers. Nothing here re-implements a rule: spitter movement, the
charge/shot, projectile flight and expiry, the hit on the player and the Fang
parry are all read off the prototype's own `Enemy.update`, `Game.update`,
`Sword.update` and `Game.parry_projectiles`.

Mechanics outside this slice are switched off, and the capture asserts that:
  * `afflict` (elemental conditions) is a no-op,
  * every enemy it creates is unarmed (`armed is None`) -- armed foes drop swords
    (issue #17),
  * only husks and spitters appear (runners/brutes are already covered by #9),
  * only Fang swords are ever equipped, and no ultimate or Converge is invoked,
  * the wave machine is off (spitters first appear in wave 3, issue #18).
Per-case controls: enemy speed, clock `t` and `shoot_cd` are pinned (the prototype
draws uniform(0.9, 1.12), uniform(0, 10) and uniform(1.5, 3.0)); the cooldown after
a shot is a uniform(2.0, 2.9) draw that cannot be matched across random streams, so
it is recorded as a range, with the intervals the prototype actually produced.
Where a Fang strike has to be in a known state, the case sets the sword's own
fields (`state`, `timer`, `pos`, `dir`, `aim`) -- the same ones the Godot checks
set -- and then lets the prototype's `Sword.update` run.
"""
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import capture_fang_survival_loop as base  # noqa: E402  (loads the prototype)

NS = base.NS
V = base.V
Enemy = base.Enemy
Projectile = NS["Projectile"]
Sword = NS["Sword"]
WORLD = base.WORLD
DT = base.DT
r = base.r
hold = base.hold
new_game = base.new_game
NoCrit = base.NoCrit
ENEMY_TYPES = NS["ENEMY_TYPES"]
KINDS = ("husk", "spitter")
PLAYER = (1300.0, 900.0)  # the arena centre, where the prototype's player spawns

_CREATED = []   # every enemy, to prove the fixture was unarmed and in scope
_SWORDS = []    # every sword, to prove only Fang swords took part
_BANNED_CALLS = []


def foe(g, kind, at, wave=1, vel=(0.0, 0.0), stun=0.0, t=0.0, hp=None, speed=None, shoot_cd=99.0, charge=0.0):
    """An enemy built by the prototype's own constructor, then pinned."""
    assert kind in KINDS, kind
    e = Enemy(kind, V(at), wave)
    assert e.armed is None
    e.speed = float(ENEMY_TYPES[kind]["speed"] if speed is None else speed)
    e.t = float(t)
    e.vel = V(vel)
    e.stun = float(stun)
    e.shoot_cd = float(shoot_cd)
    e.charge = float(charge)
    if hp is not None:
        e.hp = float(hp)
    # How the Godot side must place the same enemy; written beside every case so
    # the fixtures come from this file rather than from numbers copied twice.
    e.setup = dict(kind=kind, x=r(e.pos.x), y=r(e.pos.y), vx=r(e.vel.x), vy=r(e.vel.y), stun=r(e.stun),
                   hp=r(e.hp), t=r(e.t), wave=wave, speed_scale=0.0 if e.speed == 0.0 else 1.0,
                   shoot_cd=r(e.shoot_cd), charge=r(e.charge))
    g.enemies.append(e)
    _CREATED.append(e)
    return e


def shot(g, at, vel, life=None):
    """A projectile exactly as `Enemy.update` makes one, placed by hand."""
    pr = Projectile(V(at), V(vel))
    if life is not None:
        pr.life = float(life)
    pr.setup = dict(x=r(pr.pos.x), y=r(pr.pos.y), vx=r(pr.vel.x), vy=r(pr.vel.y), life=r(pr.life))
    g.projectiles.append(pr)
    return pr


def snap(e):
    return dict(kind=e.kind, x=r(e.pos.x), y=r(e.pos.y), vx=r(e.vel.x), vy=r(e.vel.y), hp=r(e.hp),
                stun=r(e.stun), charge=r(e.charge), shoot_cd=r(e.shoot_cd), dead=bool(e.dead))


def fresh(seed=1):
    random.seed(seed)
    g = new_game(swords=[])
    hold()
    assert (g.player.pos.x, g.player.pos.y) == PLAYER
    return g


def tick(g, n=1):
    for _ in range(n):
        g.update(DT)


def fang(g, at, direction=(1.0, 0.0), aim=None, timer=0.3, cd=5.0, rarity=0):
    """A Fang mid-strike: the state the prototype's `Sword.strike` leaves it in.

    The sweep then runs through the prototype's own `Sword.update` strike branch.
    """
    sw = Sword("fang", rarity, "fire", V(at))
    sw.state = "strike"
    sw.timer = float(timer)
    sw.dir = V(direction)
    sw.vel = V(direction) * NS["SWORD_TYPES"]["fang"]["speed"]
    sw.aim = V(aim if aim is not None else (at[0] + 2000.0 * direction[0], at[1] + 2000.0 * direction[1]))
    sw.target = None
    sw.cd = float(cd)
    sw.setup = dict(x=r(sw.pos.x), y=r(sw.pos.y), dx=r(sw.dir.x, 4), dy=r(sw.dir.y, 4), aimx=r(sw.aim.x), aimy=r(sw.aim.y),
                    timer=r(sw.timer), rarity=rarity)
    g.swords.append(sw)
    _SWORDS.append(sw)
    return sw


# ------------------------------------------------------------------ cases
def case_table():
    d = ENEMY_TYPES["spitter"]
    out = dict(spitter=dict(r=d["r"], hp=d["hp"], speed=d["speed"], dmg=d["dmg"], knock=d["knock"]),
               wave_health={str(w): r(Enemy("spitter", V(0, 0), w).maxhp) for w in (1, 2, 3, 5)})
    p = Projectile(V(0, 0), V(0, 0))
    out["projectile"] = dict(r=p.r, life=p.life)
    # the numbers the AI and the shot use, read off a probe of the real class
    out["initial_shoot_cd_range"] = [1.5, 3.0]
    out["shot_speed"] = 270.0
    return out


def case_movement():
    """A spitter alone, stationary player, shoot_cd pinned high so nothing is fired.

    Distances sit in each AI band: retreat (< 260), orbit (260..380), approach.
    """
    out = {}
    marks = {15: "0.25", 30: "0.5", 60: "1.0", 120: "2.0"}
    for label, dist in (("retreat_150", 150.0), ("orbit_300", 300.0), ("approach_450", 450.0), ("far_800", 800.0)):
        g = fresh()
        e = foe(g, "spitter", (PLAYER[0] - dist, PLAYER[1] + 40.0))
        trace = {}
        for step in range(1, 121):
            tick(g)
            if step in marks:
                trace[marks[step]] = dict(x=r(e.pos.x - PLAYER[0]), y=r(e.pos.y - PLAYER[1]), vx=r(e.vel.x), vy=r(e.vel.y),
                                          fx=r(e.facing.x, 4), fy=r(e.facing.y, 4), shot=len(g.projectiles))
        out[label] = dict(setup=[e.setup], trace=trace)
    # the band edges: the first tick's velocity reveals which branch applied
    edges = {}
    for dist in (259.0, 259.9, 260.1, 261.0, 379.0, 379.9, 380.1, 381.0):
        g = fresh()
        e = foe(g, "spitter", (PLAYER[0] - dist, PLAYER[1]))
        tick(g)
        edges["%.1f" % dist] = dict(setup=e.setup, vx=r(e.vel.x), vy=r(e.vel.y))
    out["band_edges"] = edges
    # the orbit's sideways direction is fixed (V(-dirp.y, dirp.x)): from the east of the player it goes +y
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 300.0, PLAYER[1]))
    tick(g, 10)
    out["orbit_from_east"] = dict(setup=[e.setup], vx=r(e.vel.x), vy=r(e.vel.y))
    return out


def case_shooting():
    out = {}
    # A. the first shot, tick by tick: shoot_cd 1.0, spitter at 450 px with its own speed zeroed
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 450.0, PLAYER[1]), shoot_cd=1.0)
    first = None
    charge_trace = {}
    for step in range(1, 241):
        tick(g)
        if step in (50, 60, 61, 62, 70, 80, 90):
            charge_trace[str(step)] = dict(charge=r(e.charge), shoot_cd=r(e.shoot_cd), vx=r(e.vel.x), vy=r(e.vel.y))
        if g.projectiles and first is None:
            first = step
            pr = g.projectiles[0]
            out["first_shot"] = dict(setup=[e.setup], tick=step, x=r(pr.pos.x - e.pos.x), y=r(pr.pos.y - e.pos.y),
                                     vx=r(pr.vel.x), vy=r(pr.vel.y), spitter_x=r(e.pos.x), spitter_y=r(e.pos.y),
                                     charge_after=r(e.charge), cooldown_after_range=[2.0, 2.9],
                                     shoot_cd_after=r(e.shoot_cd))
            break
    out["first_shot"]["charge_trace"] = charge_trace
    # B. a long spitter at 450 stationary player: when does it shoot and at what intervals
    random.seed(11)
    g = fresh(11)
    e = foe(g, "spitter", (PLAYER[0] + 330.0, PLAYER[1]), shoot_cd=0.6, speed=0.0)
    g.player.hp = 1e9
    g.player.iframes = 1e9
    fires, seen = [], set()
    for step in range(1, 60 * 30 + 1):
        tick(g)
        for pr in g.projectiles:
            if id(pr) not in seen:
                seen.add(id(pr))
                fires.append(step)
    intervals = [b - a for a, b in zip(fires, fires[1:])]
    out["shot_intervals"] = dict(setup=[e.setup], fire_ticks=fires, intervals_ticks=intervals,
                                 min_interval_s=r(min(intervals) / 60.0), max_interval_s=r(max(intervals) / 60.0),
                                 expected_range_s=[2.5, 3.4])
    # C. out of range: shoot_cd already 0 at 650 px with speed 0 -> never charges; charge is kept, not reset
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 650.0, PLAYER[1]), shoot_cd=0.0, speed=0.0, charge=0.2)
    tick(g, 120)
    out["out_of_range"] = dict(setup=[e.setup], projectiles=len(g.projectiles), charge=r(e.charge), shoot_cd=r(e.shoot_cd))
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 619.0, PLAYER[1]), shoot_cd=0.0, speed=0.0)
    tick(g, 10)
    out["just_in_range"] = dict(setup=[e.setup], charge=r(e.charge))
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 621.0, PLAYER[1]), shoot_cd=0.0, speed=0.0)
    tick(g, 10)
    out["just_out_of_range"] = dict(setup=[e.setup], charge=r(e.charge))
    # D. charging slows the spitter to 15 % of its wanted speed
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 450.0, PLAYER[1]), shoot_cd=0.0)
    tick(g, 1)
    out["charge_slows_first_tick"] = dict(setup=[e.setup], vx=r(e.vel.x), vy=r(e.vel.y), charge=r(e.charge))
    tick(g, 9)
    out["charge_slows_tick_10"] = dict(vx=r(e.vel.x), vy=r(e.vel.y), charge=r(e.charge))
    # E. a stun cancels the charge and pauses the cooldown
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 450.0, PLAYER[1]), shoot_cd=0.0, charge=0.3)
    e.stun = 0.5
    tick(g, 6)
    out["stun_cancels_charge"] = dict(setup=[e.setup], charge=r(e.charge), shoot_cd=r(e.shoot_cd), stun=r(e.stun),
                                      projectiles=len(g.projectiles))
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 450.0, PLAYER[1]), shoot_cd=0.4, charge=0.0, stun=0.5)
    tick(g, 12)
    out["stun_freezes_cooldown"] = dict(setup=[e.setup], shoot_cd=r(e.shoot_cd))
    # F. a dead player: the spitter wanders and never charges
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 400.0, PLAYER[1]), shoot_cd=0.0)
    g.player.dead = True
    tick(g, 90)
    out["player_dead_no_shot"] = dict(setup=[e.setup], projectiles=len(g.projectiles), charge=r(e.charge))
    return out


def case_projectile_flight():
    out = {}
    marks = (1, 2, 30, 60)
    g = fresh()
    far = (PLAYER[0], PLAYER[1] + 700.0)
    pr = shot(g, (1300.0, 1000.0), (270.0, 0.0))
    trace = {}
    for step in range(1, 301):
        tick(g)
        if step in marks:
            trace[str(step)] = dict(x=r(pr.pos.x), y=r(pr.pos.y), life=r(pr.life))
        if pr.dead or pr not in g.projectiles:
            out["expiry_in_the_open"] = dict(setup=pr.setup, removed_tick=step, trace=trace, final_x=r(pr.pos.x),
                                             final_y=r(pr.pos.y), life=r(pr.life))
            break
    for label, at, vel in (("east", (2000.0, 1500.0), (270.0, 0.0)), ("west", (600.0, 1500.0), (-270.0, 0.0)),
                           ("south", (400.0, 1300.0), (0.0, 270.0)), ("north", (400.0, 500.0), (0.0, -270.0)),
                           ("diagonal", (2200.0, 1500.0), (190.9188, 190.9188))):
        g = fresh()
        pr = shot(g, at, vel)
        removed = None
        for step in range(1, 241):
            tick(g)
            if pr.dead:
                removed = step
                break
        out["leaves_%s" % label] = dict(setup=pr.setup, removed_tick=removed, x=r(pr.pos.x), y=r(pr.pos.y), life=r(pr.life))
    # a projectile already outside the arena is removed on its first tick
    g = fresh()
    pr = shot(g, (2599.0, 900.0), (270.0, 0.0))
    tick(g)
    out["already_at_the_wall"] = dict(setup=pr.setup, dead=bool(pr.dead), removed=pr not in g.projectiles)
    # short life: expires on the tick life reaches 0, whatever it is doing
    g = fresh()
    pr = shot(g, (1300.0, 1300.0), (0.0, 0.0), life=0.05)
    removed = None
    for step in range(1, 12):
        tick(g)
        if pr.dead:
            removed = step
            break
    out["short_life"] = dict(setup=pr.setup, removed_tick=removed)
    # slow motion scales a projectile's flight (the scaled dt)
    g = fresh()
    g.slowmo, g.slowmo_scale = 10.0, 0.25
    pr = shot(g, (1300.0, 1300.0), (270.0, 0.0))
    tick(g, 60)
    out["slow_motion"] = dict(setup=pr.setup, x=r(pr.pos.x), life=r(pr.life))
    # hitstop freezes it, pause freezes it
    g = fresh()
    pr = shot(g, (1300.0, 1300.0), (270.0, 0.0))
    g.hitstop = 5 / 60.0 + 0.0001
    tick(g, 3)
    frozen = r(pr.pos.x)
    out["hitstop_freezes"] = dict(setup=pr.setup, x_after_3_ticks=frozen)
    g = fresh()
    pr = shot(g, (1300.0, 1300.0), (270.0, 0.0))
    g.paused = True
    tick(g, 30)
    out["pause_freezes"] = dict(setup=pr.setup, x=r(pr.pos.x), life=r(pr.life))
    return out


def case_player_hit():
    out = {}
    # a projectile 100 px east of the player flying at it
    g = fresh()
    pr = shot(g, (PLAYER[0] + 100.0, PLAYER[1]), (-270.0, 0.0))
    hit_tick = None
    for step in range(1, 61):
        tick(g)
        if g.player.hp < 100:
            hit_tick = step
            break
    out["head_on"] = dict(setup=pr.setup, tick=hit_tick, hp=r(g.player.hp), iframes=r(g.player.iframes),
                          player_vx=r(g.player.vel.x), player_vy=r(g.player.vel.y), hitstop=r(g.hitstop), trauma=r(g.trauma),
                          projectile_gone=bool(pr.dead) and pr not in g.projectiles, projectile_x=r(pr.pos.x))
    # the same flight from below-right: knockback follows the projectile's position
    g = fresh()
    pr = shot(g, (PLAYER[0] + 70.0, PLAYER[1] + 70.0), (-190.9188, -190.9188))
    hit_tick = None
    for step in range(1, 61):
        tick(g)
        if g.player.hp < 100:
            hit_tick = step
            break
    out["diagonal"] = dict(setup=pr.setup, tick=hit_tick, hp=r(g.player.hp), player_vx=r(g.player.vel.x), player_vy=r(g.player.vel.y))
    # grazing: parallel flight offset by 20 hits, 22 misses (r 7 + 14 = 21)
    for offset in (20.0, 22.0):
        g = fresh()
        pr = shot(g, (PLAYER[0] + 100.0, PLAYER[1] + offset), (-270.0, 0.0))
        tick(g, 60)
        out["graze_%d" % offset] = dict(setup=pr.setup, hp=r(g.player.hp), alive=pr in g.projectiles)
    # damage is always 8, not the shooter's contact damage
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 900.0, PLAYER[1]), speed=0.0)
    pr = shot(g, (PLAYER[0] + 100.0, PLAYER[1]), (-270.0, 0.0))
    tick(g, 40)
    out["damage_is_eight"] = dict(setup=pr.setup, hp=r(g.player.hp))
    # invulnerability: a projectile passes THROUGH an invulnerable player and flies on
    g = fresh()
    g.player.iframes = 0.5
    pr = shot(g, (PLAYER[0] + 100.0, PLAYER[1]), (-270.0, 0.0))
    tick(g, 50)
    out["passes_through_iframes"] = dict(setup=pr.setup, iframes_start=0.5, hp=r(g.player.hp), alive=pr in g.projectiles,
                                        x=r(pr.pos.x), life=r(pr.life), dead=bool(pr.dead))
    # ... and strikes once the invulnerability has run out while it is still overlapping
    g = fresh()
    g.player.iframes = 0.1
    pr = shot(g, (PLAYER[0] + 40.0, PLAYER[1]), (-30.0, 0.0))
    hit_tick = None
    for step in range(1, 120):
        tick(g)
        if g.player.hp < 100:
            hit_tick = step
            break
    out["hits_when_iframes_end"] = dict(setup=pr.setup, iframes_start=0.1, tick=hit_tick, hp=r(g.player.hp))
    # a dash gives 0.24 s of invulnerability: a projectile crossing during it is harmless
    g = fresh()
    g.player.facing = V(0, 1)
    g.player.dash(g)
    dash_iframes = r(g.player.iframes)
    pr = shot(g, (PLAYER[0] + 20.0, PLAYER[1] + 40.0), (-270.0, 0.0))
    tick(g, 20)
    out["dash_dodges"] = dict(setup=pr.setup, iframes_after_dash=dash_iframes, hp=r(g.player.hp), alive=pr in g.projectiles)
    # two projectiles inside the invulnerability window of the first hit: only one hurts
    g = fresh()
    a = shot(g, (PLAYER[0] + 100.0, PLAYER[1]), (-270.0, 0.0))
    b = shot(g, (PLAYER[0] + 160.0, PLAYER[1]), (-270.0, 0.0))
    ticks = []
    last = g.player.hp
    for step in range(1, 90):
        tick(g)
        if g.player.hp < last:
            ticks.append(step)
            last = g.player.hp
    out["second_shot_inside_iframes"] = dict(setup=[a.setup, b.setup], hit_ticks=ticks, hp=r(g.player.hp),
                                             second_alive=b in g.projectiles, second_x=r(b.pos.x))
    # a dead player is not hit: the projectile flies through
    g = fresh()
    g.player.dead = True
    pr = shot(g, (PLAYER[0] + 100.0, PLAYER[1]), (-270.0, 0.0))
    tick(g, 50)
    out["dead_player_not_hit"] = dict(setup=pr.setup, hp=r(g.player.hp), alive=pr in g.projectiles, x=r(pr.pos.x))
    # a lethal shot
    g = fresh()
    g.player.hp = 8.0
    pr = shot(g, (PLAYER[0] + 100.0, PLAYER[1]), (-270.0, 0.0))
    for step in range(1, 41):
        tick(g)
        if g.player.dead:
            break
    out["lethal"] = dict(setup=pr.setup, start_health=8.0, tick=step, hp=r(g.player.hp), dead=bool(g.player.dead),
                         slowmo=r(g.slowmo), slowmo_scale=g.slowmo_scale)
    # expiry beats a hit in the same tick (the `elif` in Game.update)
    g = fresh()
    pr = shot(g, (PLAYER[0] + 24.0, PLAYER[1]), (-270.0, 0.0), life=0.015)
    tick(g, 1)
    out["expiry_beats_hit"] = dict(setup=pr.setup, hp=r(g.player.hp), dead=bool(pr.dead))
    return out


def case_spitter_as_enemy():
    """The spitter obeys the same contact, knockback and death rules as any enemy."""
    out = {}
    g = fresh()
    e = foe(g, "spitter", (PLAYER[0] + 20.0, PLAYER[1]), shoot_cd=99.0)
    tick(g)
    out["contact"] = dict(setup=[e.setup], hp=r(g.player.hp), iframes=r(g.player.iframes), enemy_vx=r(e.vel.x),
                          enemy_stun=r(e.stun))
    for crit in (False, True):
        with NoCrit(crit):
            g = fresh()
            sw = Sword("fang", 0, "fire", g.player.pos)
            _SWORDS.append(sw)
            e = foe(g, "spitter", (PLAYER[0] + 60.0, PLAYER[1]))
            g.hit_enemy(e, sw.damage, V(1, 0), NS["SWORD_TYPES"]["fang"]["knock"], sw)
            out["fang_%s" % ("crit" if crit else "hit")] = dict(setup=[e.setup], dealt=r(e.maxhp - e.hp), vx=r(e.vel.x),
                                                                  vy=r(e.vel.y), stun=r(e.stun), hitstop=r(g.hitstop))
    return out


def _strike_run(case, ticks=6):
    """Runs a prepared game for a few ticks and records the parry's footprint."""
    g, sword, projs = case
    parried_tick = {}
    trace = []
    hitstop_at = {}
    for step in range(1, ticks + 1):
        tick(g)
        for i, pr in enumerate(projs):
            if pr.dead and i not in parried_tick:
                parried_tick[i] = step
                hitstop_at[i] = r(g.hitstop)
        trace.append(dict(tick=step, sword_x=r(sword.pos.x), sword_state=sword.state, hitstop=r(g.hitstop),
                          trauma=r(g.trauma)))
    return dict(parried=[parried_tick.get(i) for i in range(len(projs))], hitstop_at_parry=[hitstop_at.get(i) for i in range(len(projs))],
                sword_state=sword.state,
                sword_x=r(sword.pos.x), sword_y=r(sword.pos.y), hitstop=r(g.hitstop), trauma=r(g.trauma), kills=g.kills,
                combo=g.combo, trace=trace)


def case_fang_parry():
    out = {}
    L = NS["SWORD_TYPES"]["fang"]["length"]
    start = (1000.0, 600.0)   # the sword, well away from the player
    # geometry: perpendicular reach (r 7 + pad 8 = 15 from the sweep segment)
    reach = {}
    for off in (0.0, 10.0, 14.0, 16.0, 20.0, -14.0, -16.0):
        g = fresh()
        sw = fang(g, start)
        pr = shot(g, (start[0] + 40.0, start[1] + off), (0.0, 0.0))
        run = _strike_run((g, sw, [pr]), ticks=1)
        reach["off_%+d" % off] = dict(setup=dict(sword=sw.setup, projectile=pr.setup), parried=run["parried"][0] == 1,
                                       hitstop=run["hitstop"])
    out["perpendicular_reach"] = reach
    # along the sweep: the segment runs from the sword's previous position to its new tip
    along = {}
    for label, dx in (("behind_14", -14.0), ("behind_16", -16.0), ("start", 0.0), ("middle", 25.0), ("ahead_of_tip_14", 28.3 + 0.65 * L + 14.0),
                      ("ahead_of_tip_16", 28.3 + 0.65 * L + 16.0)):
        g = fresh()
        sw = fang(g, start)
        pr = shot(g, (start[0] + dx, start[1]), (0.0, 0.0))
        run = _strike_run((g, sw, [pr]), ticks=1)
        along[label] = dict(setup=dict(sword=sw.setup, projectile=pr.setup), parried=run["parried"][0] == 1)
    out["along_the_sweep"] = along
    # a moving projectile crossing the strike line is parried on the tick the sweep reaches it
    # (the sword covers 28.33 px a tick; the projectile starts 54 px off the line)
    moving = {}
    for label, px, py, vel in (("crossing_down", 1335.0, start[1] - 54.0, (0.0, 270.0)),
                               ("crossing_up", 1335.0, start[1] + 54.0, (0.0, -270.0)),
                               ("head_on", 1500.0, start[1] + 3.0, (-270.0, 0.0)),
                               ("running_ahead", 1100.0, start[1], (270.0, 0.0))):
        g = fresh()
        sw = fang(g, start, timer=0.3)
        pr = shot(g, (px, py), vel)
        run = _strike_run((g, sw, [pr]), ticks=30)
        moving[label] = dict(setup=dict(sword=sw.setup, projectile=pr.setup), parried_tick=run["parried"][0],
                             sword_state=run["sword_state"], hitstop_at_parry=run["hitstop_at_parry"][0], sword_x=run["sword_x"])
    out["moving_projectile"] = moving
    # the strike carries on after a parry: it is not cancelled, shaken or recovered
    g = fresh()
    sw = fang(g, start)
    pr = shot(g, (start[0] + 40.0, start[1]), (0.0, 0.0))
    run = _strike_run((g, sw, [pr]), ticks=3)
    out["parry_does_not_end_the_strike"] = dict(setup=dict(sword=sw.setup, projectile=pr.setup), parried_tick=run["parried"][0],
                                               sword_state_after_3=run["sword_state"], trauma=run["trauma"],
                                               hitstop_trace=[t["hitstop"] for t in run["trace"]])
    # two projectiles in one sweep are both parried on that tick; hitstop is a max, not a sum
    g = fresh()
    sw = fang(g, start)
    a = shot(g, (start[0] + 20.0, start[1] + 5.0), (0.0, 0.0))
    b = shot(g, (start[0] + 40.0, start[1] - 5.0), (0.0, 0.0))
    run = _strike_run((g, sw, [a, b]), ticks=1)
    out["two_in_one_sweep"] = dict(setup=dict(sword=sw.setup, projectiles=[a.setup, b.setup]), parried=run["parried"],
                                   hitstop=run["hitstop"], projectiles_left=len(g.projectiles))
    # the distinction between a hit and a parry: a sweep that hits an enemy this tick does NOT parry on it
    g = fresh()
    sw = fang(g, start)
    husk = foe(g, "husk", (start[0] + 40.0, start[1]), speed=0.0)
    pr = shot(g, (start[0] + 20.0, start[1] + 4.0), (0.0, 0.0))
    with NoCrit(False):
        run = _strike_run((g, sw, [pr]), ticks=1)
    out["hit_tick_does_not_parry"] = dict(setup=dict(sword=sw.setup, enemy=husk.setup, projectile=pr.setup),
                                          enemy_hp=r(husk.hp), parried=run["parried"][0], sword_state=run["sword_state"],
                                          hitstop=run["hitstop"], projectile_alive=pr in g.projectiles)
    # ... and on the next tick the sword is recovering, so the same projectile is not parried either
    g = fresh()
    sw = fang(g, start)
    husk = foe(g, "husk", (start[0] + 40.0, start[1]), speed=0.0)
    pr = shot(g, (start[0] + 20.0, start[1] + 4.0), (0.0, 0.0))
    with NoCrit(False):
        tick(g, 6)
    out["recovering_sword_does_not_parry"] = dict(setup=dict(sword=sw.setup, enemy=husk.setup, projectile=pr.setup),
                                                 parried=bool(pr.dead), sword_state=sw.state, alive=pr in g.projectiles)
    # an idle, winding-up or recovering sword never parries
    g = fresh()
    sw = Sword("fang", 0, "fire", V(start))
    _SWORDS.append(sw)
    sw.cd = 99.0
    g.swords.append(sw)
    pr = shot(g, (start[0] + 3.0, start[1] - 5.0), (0.0, 0.0))
    tick(g, 30)
    out["idle_sword_does_not_parry"] = dict(setup=dict(projectile=pr.setup, sword_x=r(start[0]), sword_y=r(start[1])),
                                            parried=bool(pr.dead), sword_state=sw.state)
    # the strike's last tick still parries (the parry runs before the timer check)
    g = fresh()
    sw = fang(g, start, timer=0.015)
    pr = shot(g, (start[0] + 40.0, start[1]), (0.0, 0.0))
    run = _strike_run((g, sw, [pr]), ticks=1)
    out["final_strike_tick_parries"] = dict(setup=dict(sword=sw.setup, projectile=pr.setup), parried=run["parried"][0] == 1,
                                            sword_state=run["sword_state"])
    # a rarity-scaled sword (Mythic: longer blade) reaches farther along the line
    g = fresh()
    sw = fang(g, start, rarity=2)
    tip = 28.333 + 0.65 * L * 1.18
    pr = shot(g, (start[0] + tip + 14.0, start[1]), (0.0, 0.0))
    run = _strike_run((g, sw, [pr]), ticks=1)
    out["mythic_reach"] = dict(setup=dict(sword=sw.setup, projectile=pr.setup), parried=run["parried"][0] == 1)
    return out


def case_parry_vs_hit_on_player():
    """The prototype's own order of events when a parry and a player hit coincide.

    `Game.update` moves every projectile in `self.projectiles` without testing
    `pr.dead`, so a projectile the sword has already destroyed this tick is still
    moved and, if it overlaps the player, still hurts. The port does not copy this
    (a projectile resolves exactly once); the observation is recorded so the
    exception is explicit.
    """
    g = fresh()
    sw = fang(g, (PLAYER[0] + 60.0, PLAYER[1]), direction=(-1.0, 0.0), timer=0.3)
    pr = shot(g, (PLAYER[0] + 24.0, PLAYER[1]), (-270.0, 0.0))
    tick(g)
    return dict(setup=dict(sword=sw.setup, projectile=pr.setup), parried=bool(pr.dead), player_hp=r(g.player.hp),
                player_iframes=r(g.player.iframes),
                note="a projectile destroyed by the sweep this tick still hurt the player in the prototype (hp 92); the port resolves it once, as a parry (hp 100)")


def case_fang_auto():
    """Through acquire -> windup -> strike with a real Fang (start cooldown 0.4).

    A husk stands 170 px east of the player; a projectile hangs on the line the
    sword will take to reach it. Whether the sweep parries it depends only on the
    geometry, so the first strike's parry tick is deterministic.
    """
    out = {}
    for label, off in (("on_the_line", 0.0), ("near_the_line", 12.0), ("clear_of_the_line", 40.0)):
        random.seed(4)
        with NoCrit(False):
            g = base.fang_game(1)
            hold()
            _SWORDS.extend(g.swords)
            husk = foe(g, "husk", (PLAYER[0] + 170.0, PLAYER[1]), speed=0.0, hp=900.0)
            pr = shot(g, (PLAYER[0] + 100.0, PLAYER[1] + off), (0.0, 0.0), life=10.0)
            sw = g.swords[0]
            parried = hit = None
            hp_last = husk.hp
            for step in range(1, 61):
                tick(g)
                if pr.dead and parried is None:
                    parried = step
                    hitstop_at_parry = r(g.hitstop)
                if husk.hp < hp_last and hit is None:
                    hit = step
                hp_last = husk.hp
            out[label] = dict(setup=[husk.setup], projectile=pr.setup, offset=off, parried_tick=parried, first_hit_tick=hit,
                              hitstop_at_parry=hitstop_at_parry if parried else None, alive=pr in g.projectiles)
    # a spitter's shot reaching a player who is not defended: the timeline up to the first hit
    random.seed(4)
    g = fresh(4)
    spitter = foe(g, "spitter", (PLAYER[0] + 420.0, PLAYER[1]), speed=0.0, shoot_cd=0.2)
    shot_tick = hit_tick = None
    for step in range(1, 181):
        tick(g)
        if g.projectiles and shot_tick is None:
            shot_tick = step
        if g.player.hp < 100 and hit_tick is None:
            hit_tick = step
    out["undefended_shot"] = dict(setup=[spitter.setup], shot_tick=shot_tick, hit_tick=hit_tick, hp=r(g.player.hp))
    return out


def assert_fixtures_in_scope():
    for e in _CREATED:
        assert e.armed is None, "armed enemy in an unarmed fixture"
        assert e.kind in KINDS, e.kind
    for sw in _SWORDS:
        assert sw.kind == "fang", sw.kind
    return dict(enemies_created=len(_CREATED), armed_enemies=0, kinds=list(KINDS), afflict_disabled=True,
                swords_used=sorted({sw.kind for sw in _SWORDS}), ultimates_and_converge_used=False, waves_enabled=False)


def main():
    cases = dict(
        table=case_table(), movement=case_movement(), shooting=case_shooting(), projectile_flight=case_projectile_flight(),
        player_hit=case_player_hit(), spitter_as_enemy=case_spitter_as_enemy(), fang_parry=case_fang_parry(),
        prototype_quirk=case_parry_vs_hit_on_player(), fang_auto=case_fang_auto(),
    )
    cases["fixture_scope"] = assert_fixtures_in_scope()
    text = json.dumps(cases, indent=2, sort_keys=False)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
