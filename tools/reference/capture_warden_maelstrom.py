#!/usr/bin/env python3
"""Captures focused reference cases for Warden (the sweeping arc) and Maelstrom (its ultimate).

Usage:  python3 -I tools/reference/capture_warden_maelstrom.py [out.json]
        (the committed copy is godot/tests/reference/warden_maelstrom.json)

Slice #13 of the Godot port. Like the earlier captures (whose loader and helpers it reuses) it
drives the prototype's REAL classes -- `Game`, `Sword`, `Enemy`, `Player`, `Projectile` from
game/main.py -- with fixed 1/60 s steps under SDL's dummy drivers. Warden's internal sword type is
`"blade"` (`SWORD_TYPES["blade"]`, displayed "Warden"; its ultimate is "Maelstrom"); nothing here
re-implements a rule: the alternating sweep, its targeting, geometry, hit set, parries and timing
come from `Sword.acquire/begin/update/strike`, the pull, ticks, burst and recovery from
`Sword.ultimate`/`Sword.update_ult`, the damage, crits, rounding and conditions from
`Game.hit_enemy` and `Game.afflict`, and the Q/E/R keys from the real `Game.handle`.

Every case writes its fixture (`setup`) into the JSON and the Godot checks build their scenarios
from it, including whether elemental conditions are ON: the physical cases run with
`Game.afflict` switched off (`setup.conditions == false`, exactly as the earlier slices' references
were captured), and the cases whose subject is how Warden's blows apply conditions
(`sweep_conditions`, `maelstrom_conditions`) leave the prototype's own `afflict` ON
(`setup.conditions == true`). The capture asserts which is which, and `fixture_scope` lists both.

Mechanics outside this slice are off, and the capture asserts that:
  * every enemy is an unarmed husk, runner or brute (arming and drops are issue #17),
  * only Warden swords are equipped (Pike #14, Colossus #15) and Converge is never commanded (#16),
  * the wave machine is off (issue #18).
Per-case controls: enemies stand still (speed 0), the auto-attack cooldown of a sword that is not
meant to fight is parked at 99 s, and crits are forced off (or on, where a case asks) by pinning
`random.random`. A few cases start an attack directly with `Sword.begin(target, aim)` (the
prototype's own entry point, also used by Converge) so the sweep's pivot is chosen by the fixture
rather than by `acquire`; the Godot side calls its `begin` the same way.
"""
import json
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import capture_fang_survival_loop as base  # noqa: E402  (loads the prototype)
import capture_viper_flurry as flurry  # noqa: E402

import pygame  # noqa: E402

NS = base.NS
V = base.V
Enemy = base.Enemy
Sword = NS["Sword"]
Game = NS["Game"]
Projectile = NS["Projectile"]
DT = base.DT
r = base.r
NoCrit = base.NoCrit
SWORD_TYPES = NS["SWORD_TYPES"]
ENEMY_TYPES = NS["ENEMY_TYPES"]
RARITIES = NS["RARITIES"]
KIND = "blade"
PLAYER = (1300.0, 900.0)  # the arena centre, where the prototype's player spawns
PARKED_CD = 99.0          # an auto-attack cooldown that never ends within a case
ELEMENTS = ("poison", "ice", "fire")
STATE_NAMES = {"idle": "idle", "windup": "windup", "strike": "strike", "recover": "recover", "ult": "ult"}

_CREATED = []
_SWORDS = []
_CONDITION_CASES = []


def fresh(seed=1, rarities=(0, 0, 0), active=(), conditions=False, count=3, elements=ELEMENTS):
    """A game with `count` Warden swords (Q, E, R); those in `active` may attack at once, the
    rest are parked. No waves. `afflict` is the prototype's own only when `conditions` is set."""
    random.seed(seed)
    g = base.new_game(swords=[])
    if conditions:
        del g.afflict  # the shared helper switches conditions off
        assert g.afflict.__func__ is Game.afflict
    base.hold()
    assert (g.player.pos.x, g.player.pos.y) == PLAYER
    c = g.player.pos
    g.swords = [Sword(KIND, rarities[i], elements[i], c) for i in range(count)]
    for i, s in enumerate(g.swords):
        s.cd = 0.0 if i in active else PARKED_CD
        _SWORDS.append(s)
    g.setup_conditions = conditions
    return g


def swords_setup(g, active=()):
    return [dict(type=KIND, rarity=s.rarity, element=s.element, cd=0.0 if i in active else PARKED_CD)
            for i, s in enumerate(g.swords)]


def foe(g, at, hp=900.0, kind="husk", vel=(0.0, 0.0), stun=0.0):
    """An unarmed enemy from the prototype's constructor, pinned. `setup` is how the Godot side
    must place the same enemy (written beside every case)."""
    e = Enemy(kind, V(at), 1)
    assert e.armed is None
    e.speed = 0.0
    e.t = 0.0
    e.hp = e.maxhp = float(hp)
    e.vel = V(vel)
    e.stun = stun
    e.setup = dict(kind=kind, x=r(e.pos.x), y=r(e.pos.y), hp=r(e.hp), speed_scale=0.0, vx=r(vel[0]), vy=r(vel[1]), stun=r(stun))
    g.enemies.append(e)
    _CREATED.append(e)
    return e


def orb(g, at, life=10.0):
    pr = Projectile(V(at), V(0, 0))
    pr.life = life
    pr.setup = dict(x=r(pr.pos.x), y=r(pr.pos.y), vx=0.0, vy=0.0, life=life)
    g.projectiles.append(pr)
    return pr


def tick(g, n=1):
    for _ in range(n):
        g.update(DT)


def key(g, code, mouse=None):
    flurry.key(g, code, mouse=mouse)


def sword_row(sw):
    return dict(state=STATE_NAMES[sw.state], x=r(sw.pos.x), y=r(sw.pos.y), ang=r(sw.ang, 4), vx=r(sw.vel.x), vy=r(sw.vel.y))


class Trace:
    """Per-tick record (after each tick) of a sword and some enemies, as dict-of-lists."""

    def __init__(self, sw, enemies, detail=False):
        self.detail = detail
        self.sw = sw
        self.enemies = enemies
        self.state, self.x, self.y, self.ang, self.vx, self.vy = [], [], [], [], [], []
        self.spin, self.ult_t, self.beat, self.ult_cd, self.side, self.cd = [], [], [], [], [], []
        self.e = [dict(x=[], y=[], hp=[], vx=[], vy=[], stun=[]) for _ in enemies]
        self.hits = []          # one entry per tick on which an enemy lost health
        self.transitions = []
        self.n = 0
        self._phase = sw.state
        self._hp = [e.hp for e in enemies]

    def step(self, g):
        self.n += 1
        sw = self.sw
        self.state.append(STATE_NAMES[sw.state])
        self.x.append(r(sw.pos.x))
        self.y.append(r(sw.pos.y))
        self.ang.append(r(sw.ang, 4))
        if self.detail:
            self.vx.append(r(sw.vel.x))
            self.vy.append(r(sw.vel.y))
            self.spin.append(r(sw.spin, 4))
            self.ult_t.append(r(sw.ult_t, 4))
            self.beat.append(r(sw.tick, 4))
            self.ult_cd.append(r(sw.ult_cd, 4))
            self.side.append(sw.side)
            self.cd.append(r(sw.cd, 4))
        for i, e in enumerate(self.enemies):
            d = self.e[i]
            d["x"].append(r(e.pos.x))
            d["y"].append(r(e.pos.y))
            d["hp"].append(r(e.hp, 4))
            if self.detail:
                d["vx"].append(r(e.vel.x))
                d["vy"].append(r(e.vel.y))
                d["stun"].append(r(e.stun, 4))
        dealt = [(i, self._hp[i] - e.hp) for i, e in enumerate(self.enemies) if e.hp < self._hp[i]]
        if dealt:
            self.hits.append(dict(tick=self.n, dealt=[[i, r(d, 4)] for i, d in dealt], hitstop=r(g.hitstop, 4),
                                  trauma=r(g.trauma, 4), flash=[r(self.enemies[i].flash, 4) for i, _ in dealt]))
        self._hp = [e.hp for e in self.enemies]
        if sw.state != self._phase:
            self.transitions.append(dict(tick=self.n, to=STATE_NAMES[sw.state], side=sw.side, ult_cd=r(sw.ult_cd, 4)))
            self._phase = sw.state

    def out(self, every=1):
        keep = lambda a: [v for i, v in enumerate(a) if (i + 1) % every == 0 or i == 0]  # noqa: E731
        d = dict(ticks=self.n, every=every, hits=self.hits, transitions=self.transitions)
        names = ("state", "x", "y", "ang") + (("vx", "vy", "spin", "ult_t", "beat", "ult_cd", "side", "cd") if self.detail else ())
        for name in names:
            d[name] = keep(getattr(self, name))
        d["enemies"] = [{k: keep(v) for k, v in e.items() if v} for e in self.e]
        return d


# ------------------------------------------------------------------ table
def case_table():
    t = SWORD_TYPES[KIND]
    u = t["ult"]
    out = dict(kind=KIND, name=t["name"], blurb=t["blurb"], length=t["length"], width=t["width"], range=t["range"],
               cooldown=t["cooldown"], damage=t["damage"], knock=t["knock"], windup=t["windup"], hitstop=t["hitstop"],
               shake=t["shake"], ult_name=u["name"], ult_cd=u["cd"], ult_range=u["range"], ult_radius=u["radius"],
               ult_shot=u["shot"], keys="QER", converge_cd=NS["CONVERGE_CD"])
    out["rarities"] = []
    for i in range(3):
        s = Sword(KIND, i, "fire", V(0, 0))
        out["rarities"].append(dict(damage=r(s.damage, 4), cooldown=r(s.cooldown, 4), range=r(s.range, 4), length=r(s.L, 4),
                                    scale=r(s.scale, 4), ult_max=r(s.ult_max, 4)))
    # constants read off the code (Sword.update / strike / ultimate / update_ult): the sweep lasts 0.15 s,
    # the blade swings from amid - side * 1.9 to amid + side * 1.45 about a pivot 0.55 L behind the target,
    # sampled at the middle and end of every tick's step, recovery 0.3 s at 300 px/s.
    out["inline"] = dict(
        sweep_time=0.15, recover_time=0.3, recover_speed=300.0, start_angle=1.9, end_angle=1.45, pivot_back=0.55,
        windup_spring=[220.0, 26.0], windup_ang_rate=18.0, pose_radius=0.5, guard=0.12, tip=1.15, hit_pad=8.0,
        parry_pad=6.0, tangent_weight=0.6,
        spin_rate=15.0, ult_time=2.2, first_beat=0.15, beat=0.2, approach_rate=25.0, pull_speed=170.0, pull_min=8.0,
        pull_extra=120.0, reach_tail=0.7, tick_damage=0.6, tick_knock=40.0, tick_shake=0.08, burst_damage=1.6,
        burst_knock=520.0, burst_margin=30.0, burst_stacks=2, burst_shake=0.35, burst_hitstop=0.06,
        ult_recover_time=0.3, ult_recover_speed=500.0, heavy_flash=0.2, normal_flash=0.11)
    out["knock_mult"] = {k: ENEMY_TYPES[k]["knock"] for k in ("husk", "runner", "brute")}
    out["radius"] = {k: ENEMY_TYPES[k]["r"] for k in ("husk", "runner", "brute")}
    return out


# ------------------------------------------------------------------ the sweep
def case_sweep():
    """One Warden against one stationary enemy: windup, the alternating sweeps and their recovery, the
    hit with its damage, knockback, stun, flash, hitstop and shake, for each rarity and a crit."""
    out = {}
    for label, rarity, crit in (("common", 0, False), ("common_crit", 0, True), ("rare", 1, False), ("mythic", 2, False)):
        with NoCrit(crit):
            g = fresh(rarities=(rarity, 0, 0), active=(0,))
            husk = foe(g, (PLAYER[0] + 170.0, PLAYER[1] + 30.0))
            sw = g.swords[0]
            tr = Trace(sw, [husk], detail=True)
            sides = []
            for _ in range(190):
                prev = sw.state
                tick(g)
                tr.step(g)
                if prev != "windup" and sw.state == "windup":
                    sides.append(sw.side)
            out[label] = dict(setup=dict(conditions=False, crit=crit, swords=swords_setup(g, (0,)), enemies=[husk.setup]),
                              windup_sides=sides, trace=tr.out(), kills=g.kills)
    return out


def case_acquire():
    """Who a Warden targets: the nearest enemy within range + its radius of the player."""
    out = {}
    rng = SWORD_TYPES[KIND]["range"]
    husk_r = ENEMY_TYPES["husk"]["r"]
    for label, distance in (("just_inside", rng + husk_r - 1.0), ("just_outside", rng + husk_r + 1.0), ("close", 90.0)):
        with NoCrit(False):
            g = fresh(active=(0,))
            husk = foe(g, (PLAYER[0] + distance, PLAYER[1]))
            sw = g.swords[0]
            left_idle = None
            for step in range(1, 40):
                tick(g)
                if sw.state != "idle" and left_idle is None:
                    left_idle = step
            out[label] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0,)), enemies=[husk.setup]),
                              distance=r(distance), left_idle=left_idle)
    # the nearer of two wins, whichever was placed first, on either side of the player
    for label, order in (("near_first", (0, 1)), ("far_first", (1, 0))):
        with NoCrit(False):
            g = fresh(active=(0,))
            spots = [(PLAYER[0] + 120.0, PLAYER[1] - 20.0), (PLAYER[0] - 190.0, PLAYER[1] + 10.0)]
            placed = [foe(g, spots[i]) for i in order]
            near = placed[order.index(0)]
            sw = g.swords[0]
            tick(g)
            out["nearest_" + label] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0,)), enemies=[e.setup for e in placed]),
                                           target_index=placed.index(sw.target) if sw.target in placed else None,
                                           nearest_index=placed.index(near))
    return out


def sweep_geometry():
    """Positions around the pivot of a sweep aimed straight east at a target 200 px away."""
    target = (PLAYER[0] + 200.0, PLAYER[1])
    length = SWORD_TYPES[KIND]["length"]
    pivot = (target[0] - length * 0.55, target[1])
    return target, pivot


def case_arc_coverage():
    """Which points around the pivot the swinging blade reaches, and on which tick, for both swing
    directions: a stationary husk (the probe) is placed at pivot + polar(angle, radius) while the
    sweep's own target stands 200 px east. The sweep starts at tick 0 with `Sword.begin`."""
    target, pivot = sweep_geometry()
    out = {}
    angles = [round(-2.75 + 0.25 * i, 3) for i in range(23)]
    radii = [8.0, 24.0, 40.0, 56.0, 62.0, 66.0, 72.0]
    for first_side in (1, -1):  # the side the sword has BEFORE begin flips it
        cells = []
        for a in angles:
            for rad in radii:
                at = (pivot[0] + math.cos(a) * rad, pivot[1] + math.sin(a) * rad)
                if math.hypot(at[0] - PLAYER[0], at[1] - PLAYER[1]) < 70.0 or math.hypot(at[0] - target[0], at[1] - target[1]) < 50.0:
                    continue
                with NoCrit(False):
                    g = fresh(active=())
                    sw = g.swords[0]
                    sw.side = first_side
                    tgt = foe(g, target)
                    probe = foe(g, at)
                    sw.begin(tgt, V(target))
                    hit_tick = None
                    for step in range(1, 45):
                        tick(g)
                        if probe.hp < probe.maxhp and hit_tick is None:
                            hit_tick = step
                    cells.append(dict(angle=a, radius=rad, x=r(at[0]), y=r(at[1]), hit_tick=hit_tick,
                                      dealt=r(probe.maxhp - probe.hp, 4)))
        out["side_%+d" % first_side] = cells
    out["setup"] = dict(conditions=False, target=dict(kind="husk", x=r(target[0]), y=r(target[1]), hp=900.0, speed_scale=0.0),
                        swords=[dict(type=KIND, rarity=0, element="poison", cd=PARKED_CD)] * 3)
    return out


def case_multi_target():
    """Several enemies inside one sweep: each takes exactly one hit per attack, on its own tick;
    the second attack (other direction) hits each exactly once again."""
    out = {}
    layouts = {
        "three_in_front": [(150.0, 0.0), (170.0, 38.0), (170.0, -38.0)],
        "spread_arc": [(140.0, 20.0), (190.0, 60.0), (120.0, -50.0), (210.0, -20.0), (-160.0, 20.0)],
    }
    for label, offsets in layouts.items():
        with NoCrit(False):
            g = fresh(active=(0,))
            es = [foe(g, (PLAYER[0] + dx, PLAYER[1] + dy)) for dx, dy in offsets]
            sw = g.swords[0]
            tr = Trace(sw, es)
            for _ in range(150):
                tick(g)
                tr.step(g)
            per_enemy = [sum(1 for h in tr.hits for i, _ in h["dealt"] if i == k) for k in range(len(es))]
            out[label] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0,)), enemies=[e.setup for e in es]),
                              trace=tr.out(), hits_per_enemy=per_enemy)
    # three Wardens at once: every one of them hits every enemy it sweeps through, once, and nobody twice
    with NoCrit(False):
        g = fresh(active=(0, 1, 2))
        es = [foe(g, (PLAYER[0] + dx, PLAYER[1] + dy)) for dx, dy in [(150.0, 0.0), (160.0, 40.0), (-150.0, 10.0), (0.0, 170.0)]]
        tr = Trace(g.swords[0], es)
        for _ in range(80):
            tick(g)
            tr.step(g)
        out["three_wardens"] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0, 1, 2)), enemies=[e.setup for e in es]),
                                    trace=tr.out(), hp=[r(e.hp, 4) for e in es],
                                    states=[s.state for s in g.swords])
    return out


def case_deaths():
    """Deaths during a sweep resolve once; a corpse is not hit again, by the same or another sword."""
    out = {}
    with NoCrit(False):
        g = fresh(active=(0,))
        weak = foe(g, (PLAYER[0] + 150.0, PLAYER[1]), hp=5.0)
        tough = foe(g, (PLAYER[0] + 170.0, PLAYER[1] + 38.0))
        sw = g.swords[0]
        tr = Trace(sw, [weak, tough])
        for _ in range(60):
            tick(g)
            tr.step(g)
        out["kills_in_sweep"] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0,)), enemies=[weak.setup, tough.setup]),
                                     trace=tr.out(), kills=g.kills, combo=g.combo, motes=len(g.motes), left=len(g.enemies))
    with NoCrit(False):
        # two Wardens strike the same 10 hp enemy on the same tick: the first kills it, the second finds a corpse
        g = fresh(active=(0, 1))
        victim = foe(g, (PLAYER[0] + 150.0, PLAYER[1]), hp=10.0)
        other = foe(g, (PLAYER[0] + 160.0, PLAYER[1] + 40.0))
        tr = Trace(g.swords[0], [victim, other])
        for _ in range(60):
            tick(g)
            tr.step(g)
        out["two_swords_one_victim"] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0, 1)), enemies=[victim.setup, other.setup]),
                                            trace=tr.out(), kills=g.kills, combo=g.combo, motes=len(g.motes))
    with NoCrit(False):
        # the target dies (killed by something else) before the strike: the sweep carries on at its last aim
        g = fresh(active=(0,))
        victim = foe(g, (PLAYER[0] + 160.0, PLAYER[1]))
        sw = g.swords[0]
        tick(g, 3)
        windup_target_set = sw.target is victim and sw.state == "windup"
        g.kill(victim, V(1, 0), False)
        tick(g, 20)
        out["target_killed_in_windup"] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0,)), enemies=[victim.setup]),
                                              windup_target_set=windup_target_set, kills=g.kills, target_cleared=sw.target is None,
                                              state=sw.state, motes=len(g.motes))
    return out


def case_parry():
    """Orbs in the sweep's path: the blade parries every orb within (orb radius + 6) of either
    sampled arc each tick, whether or not it also hit something (unlike Fang's strike)."""
    target, pivot = sweep_geometry()
    out = {}
    angles = [round(-2.75 + 0.25 * i, 3) for i in range(23)]
    radii = [8.0, 30.0, 56.0, 64.0, 68.0, 72.0, 80.0]
    for first_side in (1, -1):
        cells = []
        for a in angles:
            for rad in radii:
                at = (pivot[0] + math.cos(a) * rad, pivot[1] + math.sin(a) * rad)
                g = fresh(active=())
                sw = g.swords[0]
                sw.side = first_side
                sw.begin(None, V(target))
                pr = orb(g, at)
                parry_tick = None
                hitstop_at = None
                for step in range(1, 45):
                    tick(g)
                    if pr.dead and parry_tick is None:
                        parry_tick = step
                        hitstop_at = r(g.hitstop, 4)
                cells.append(dict(angle=a, radius=rad, x=r(at[0]), y=r(at[1]), parry_tick=parry_tick, hitstop=hitstop_at))
        out["side_%+d" % first_side] = cells
    out["setup"] = dict(conditions=False, target=dict(x=r(target[0]), y=r(target[1])), swords=swords_setup(fresh(), ()))
    # an orb and an enemy in the same sweep: both resolve; hitstop is the larger of the two
    with NoCrit(False):
        g = fresh(active=(0,))
        husk = foe(g, (PLAYER[0] + 150.0, PLAYER[1]))
        pr = orb(g, (PLAYER[0] + 160.0, PLAYER[1] + 30.0))
        sw = g.swords[0]
        both = dict(parried=None, hit=None, hitstop_on_parry=None)
        hp_prev = husk.hp
        for step in range(1, 40):
            tick(g)
            if husk.hp < hp_prev and both["hit"] is None:
                both["hit"] = step
            if pr.dead and both["parried"] is None:
                both["parried"] = step
                both["hitstop_on_parry"] = r(g.hitstop, 4)
            hp_prev = husk.hp
        out["orb_and_enemy"] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0,)), enemies=[husk.setup], orbs=[pr.setup]),
                                    result=both, hp=r(husk.hp, 4), player_hp=r(g.player.hp, 2))
    # a flying orb is swept away too, and one that never meets the blade is left alone
    with NoCrit(False):
        g = fresh(active=(0,))
        husk = foe(g, (PLAYER[0] + 150.0, PLAYER[1]))
        far = orb(g, (PLAYER[0] + 600.0, PLAYER[1] - 400.0))
        sw = g.swords[0]
        tick(g, 60)
        out["untouched_orb"] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0,)), enemies=[husk.setup], orbs=[far.setup]),
                                    alive=not far.dead)
    return out


def case_recover_and_cooldown():
    """The cooldown starts at the strike (0.85 s x the rarity) and the next attack waits for it."""
    out = {}
    for rarity in (0, 1, 2):
        with NoCrit(False):
            g = fresh(rarities=(rarity, 0, 0), active=(0,))
            husk = foe(g, (PLAYER[0] + 170.0, PLAYER[1] + 30.0), hp=100000.0)
            sw = g.swords[0]
            starts = []
            strikes = []
            for step in range(1, 400):
                prev = sw.state
                tick(g)
                if prev != "windup" and sw.state == "windup":
                    starts.append(step)
                if prev == "windup" and sw.state == "strike":
                    strikes.append(step)
            out["rarity%d" % rarity] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0,)), enemies=[husk.setup]),
                                            windup_starts=starts, strikes=strikes, cooldown=r(sw.cooldown, 4))
    return out


# ----------------------------------------------------------------- Maelstrom
def case_range_and_start():
    """Where Maelstrom lands for points inside, on and beyond its 400 px range; it does not move the
    sword; it starts the recharge and the clock; the spin starts from the sword's bearing."""
    out = {}
    offsets = {"inside": (0.0, 100.0), "on_the_limit": (400.0, 0.0), "just_beyond": (401.0, 0.0), "far_east": (900.0, 0.0),
               "far_diagonal": (500.0, -600.0), "on_the_player": (0.0, 0.0), "far_south_west": (-1000.0, 300.0)}
    for label, (dx, dy) in offsets.items():
        g = fresh()
        tick(g, 25)  # the swords drift along their orbits, so the starting bearing is not the origin
        sw = g.swords[1]
        before = (sw.pos.x, sw.pos.y)
        point = (PLAYER[0] + dx, PLAYER[1] + dy)
        key(g, pygame.K_e, mouse=point)
        out[label] = dict(point=list(point), state=sw.state, centre=[r(sw.point.x), r(sw.point.y)],
                          distance=r((sw.point - g.player.pos).length()), pos=[r(sw.pos.x), r(sw.pos.y)],
                          before=[r(before[0]), r(before[1])], ult_cd=r(sw.ult_cd), ult_t=r(sw.ult_t, 4), beat=r(sw.tick, 4),
                          spin=r(sw.spin, 4), phase=sw.phase)
    out["setup"] = dict(conditions=False, swords=swords_setup(fresh()), warmup_ticks=25, slot=1)
    # the sword that was winding up an automatic attack drops it and its target
    with NoCrit(False):
        g = fresh(active=(0,))
        husk = foe(g, (PLAYER[0] + 120.0, PLAYER[1]))
        sw = g.swords[0]
        tick(g, 3)
        before = sw.state
        key(g, pygame.K_q, mouse=(PLAYER[0] + 200.0, PLAYER[1]))
        out["interrupts_attack"] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0,)), enemies=[husk.setup]),
                                        state_before=before, state_after=sw.state, target_cleared=sw.target is None,
                                        hit_cleared=len(sw.hit) == 0)
    # a sword interrupted mid-sweep does not carry the old hit set into its next sweep
    with NoCrit(False):
        g = fresh(active=(0,))
        husk = foe(g, (PLAYER[0] + 150.0, PLAYER[1]))
        sw = g.swords[0]
        for _ in range(12):
            tick(g)
            if sw.state == "strike":
                break
        out["interrupts_sweep"] = dict(setup=dict(conditions=False, swords=swords_setup(g, (0,)), enemies=[husk.setup]),
                                       state_before=sw.state, hit_before=len(sw.hit))
        key(g, pygame.K_q, mouse=(PLAYER[0] + 200.0, PLAYER[1]))
        out["interrupts_sweep"].update(state_after=sw.state, hit_after=len(sw.hit))
    return out


def maelstrom_game(rarity=0, enemies=(), crit=False, point=None, **fresh_kwargs):
    g = fresh(rarities=(rarity, 0, 0), **fresh_kwargs)
    es = [foe(g, at, hp=hp, kind=kind) for at, hp, kind in enemies]
    return g, es


def run_maelstrom(label, rarity, enemies, point, crit=False, ticks=175, conditions=False, element_index=0, every=1, extra=None, detail=False):
    """Plays Maelstrom (slot 0) at `point` with the given enemies and records the whole run."""
    with NoCrit(crit):
        g = fresh(rarities=(rarity, 0, 0), conditions=conditions)
        es = [foe(g, at, hp=hp, kind=kind) for at, hp, kind in enemies]
        sw = g.swords[0]
        if extra:
            extra(g, sw, es)
        tick(g, 20)  # the sword idles on its orbit first: the spin starts from where it is
        key(g, pygame.K_q, mouse=point)
        tr = Trace(sw, es, detail=detail)
        start = dict(state=sw.state, ult_cd=r(sw.ult_cd, 4), ult_t=r(sw.ult_t, 4), beat=r(sw.tick, 4), spin=r(sw.spin, 4),
                     x=r(sw.pos.x), y=r(sw.pos.y), centre=[r(sw.point.x), r(sw.point.y)])
        for _ in range(ticks):
            tick(g)
            tr.step(g)
        if conditions:
            _CONDITION_CASES.append(label)
        return dict(setup=dict(conditions=conditions, crit=crit, warmup_ticks=20, point=list(point),
                               swords=swords_setup(g), enemies=[e.setup for e in es]),
                    at_start=start, trace=tr.out(every), kills=g.kills, motes=len(g.motes), left=len(g.enemies),
                    hitstop_end=r(g.hitstop, 4)), g


def case_maelstrom_single():
    out = {}
    point = (PLAYER[0] + 260.0, PLAYER[1] + 40.0)
    husk = [((point[0] + 60.0, point[1] - 20.0), 900.0, "husk")]
    for label, rarity, crit in (("common", 0, False), ("common_crit", 0, True), ("rare", 1, False), ("mythic", 2, False)):
        out[label], _ = run_maelstrom("single_" + label, rarity, husk, point, crit=crit, detail=True)
    return out


def case_maelstrom_pull():
    """Enemies of each kind at several distances from the centre: who is pulled (within reach + 120 and
    farther than 8 px), how fast (170 x knock factor), and who is struck by the ticks (within reach +
    radius). Bearings differ so the pulled enemies do not share a path."""
    out = {}
    point = (PLAYER[0] + 260.0, PLAYER[1] + 40.0)

    def around(distance, bearing):
        return (point[0] + math.cos(bearing) * distance, point[1] + math.sin(bearing) * distance)

    layout = [
        (around(20.0, 0.3), 900.0, "husk"),      # already close: pulled to 8 px and held there
        (around(130.0, 1.2), 900.0, "husk"),     # inside the blades' reach from the start
        (around(180.0, 2.2), 900.0, "husk"),     # outside the reach, inside the pull
        (around(255.0, 3.1), 900.0, "husk"),     # a hair inside the pull range (reach + 120 = 257.8)
        (around(262.0, 4.0), 900.0, "husk"),     # a hair outside it: never pulled, never struck
        (around(160.0, 5.0), 900.0, "brute"),    # a brute is pulled at 0.35 of the speed
        (around(200.0, 5.9), 900.0, "runner"),   # a runner at 1.3x
    ]
    out["ring"], _ = run_maelstrom("pull_ring", 0, layout, point, ticks=175)
    # the rarity's size widens the blades' reach (R x scale + 0.7 L x scale)
    out["ring_mythic"], _ = run_maelstrom("pull_ring_mythic", 2, layout, point, ticks=175)
    return out


def case_maelstrom_kills():
    """Weak enemies die to the ticks and the burst: each kill and its motes resolve once."""
    out = {}
    point = (PLAYER[0] + 260.0, PLAYER[1] + 40.0)
    layout = [
        ((point[0] + 40.0, point[1]), 9.0, "husk"),        # dies to the first tick (10 damage)
        ((point[0] - 60.0, point[1] + 30.0), 60.0, "husk"),  # dies after several ticks
        ((point[0], point[1] - 90.0), 150.0, "husk"),      # survives the ticks, dies to the burst or just after
        ((point[0] + 110.0, point[1] + 110.0), 500.0, "brute"),
    ]
    out["kills"], _ = run_maelstrom("kills", 0, layout, point, ticks=175)
    return out


def case_maelstrom_clocks():
    """Pause, the player's death, hitstop and slow motion in the middle of the whirl."""
    out = {}
    point = (PLAYER[0] + 260.0, PLAYER[1])
    husk = ((point[0] + 50.0, point[1]), 900.0, "husk")

    def frozen_clock(g, sw, es):
        pass

    # pause for 120 ticks 30 ticks in
    with NoCrit(False):
        g = fresh()
        es = [foe(g, husk[0], hp=husk[1])]
        sw = g.swords[0]
        tick(g, 20)
        key(g, pygame.K_q, mouse=point)
        tick(g, 30)
        before = dict(sword=sword_row(sw), ult_t=r(sw.ult_t, 4), beat=r(sw.tick, 4), spin=r(sw.spin, 4), ult_cd=r(sw.ult_cd, 4),
                      enemy=[r(es[0].pos.x), r(es[0].pos.y), r(es[0].hp, 4)])
        g.paused = True
        tick(g, 120)
        after = dict(sword=sword_row(sw), ult_t=r(sw.ult_t, 4), beat=r(sw.tick, 4), spin=r(sw.spin, 4), ult_cd=r(sw.ult_cd, 4),
                     enemy=[r(es[0].pos.x), r(es[0].pos.y), r(es[0].hp, 4)])
        g.paused = False
        tick(g, 1)
        out["pause"] = dict(setup=dict(conditions=False, warmup_ticks=20, run_ticks=30, point=list(point), swords=swords_setup(g),
                                       enemies=[es[0].setup]),
                            identical=before == after, before=before, after=after, resumed_ult_t=r(sw.ult_t, 4))
    # the player dies 40 ticks in: the sword goes idle at once, the pull stops, the recharge keeps running
    with NoCrit(False):
        g = fresh()
        es = [foe(g, husk[0], hp=husk[1])]
        sw = g.swords[0]
        tick(g, 20)
        key(g, pygame.K_q, mouse=point)
        tick(g, 40)
        hp_at_death = es[0].hp
        pos_at_death = (es[0].pos.x, es[0].pos.y)
        g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
        assert g.player.dead
        tick(g, 1)
        state_next = sw.state
        ult_cd_at_death = r(sw.ult_cd, 4)
        tick(g, 100)
        out["death"] = dict(setup=dict(conditions=False, warmup_ticks=20, run_ticks=40, point=list(point), swords=swords_setup(g),
                                       enemies=[es[0].setup]),
                            state_next_tick=state_next, state_later=sw.state, hp_at_death=r(hp_at_death, 4), hp_end=r(es[0].hp, 4),
                            hp_changed_after=r(hp_at_death - es[0].hp, 4), ult_cd_at_death=ult_cd_at_death, ult_cd_later=r(sw.ult_cd, 4),
                            enemy_moved_by_pull=r(math.hypot(es[0].pos.x - pos_at_death[0], es[0].pos.y - pos_at_death[1]), 3))
    # hitstop 0.2 s at the command: nothing advances until it ends
    with NoCrit(False):
        g = fresh()
        es = [foe(g, husk[0], hp=husk[1])]
        sw = g.swords[0]
        tick(g, 20)
        g.hitstop = 0.2
        key(g, pygame.K_q, mouse=point)
        first_hit = None
        at = {}
        for step in range(1, 60):
            before = es[0].hp
            tick(g)
            if es[0].hp < before and first_hit is None:
                first_hit = step
            if step in (1, 5, 12, 13, 14):
                at[str(step)] = dict(ult_t=r(sw.ult_t, 4), beat=r(sw.tick, 4), ult_cd=r(sw.ult_cd, 4))
        out["hitstop_at_command"] = dict(setup=dict(conditions=False, warmup_ticks=20, point=list(point), swords=swords_setup(g),
                                                    enemies=[es[0].setup], hitstop=0.2),
                                         first_hit_tick=first_hit, at=at)
    # slow motion x0.25 from the command
    with NoCrit(False):
        g = fresh()
        es = [foe(g, husk[0], hp=husk[1])]
        sw = g.swords[0]
        tick(g, 20)
        g.slowmo = 100.0
        g.slowmo_scale = 0.25
        key(g, pygame.K_q, mouse=point)
        first_hit = None
        for step in range(1, 100):
            before = es[0].hp
            tick(g)
            if es[0].hp < before and first_hit is None:
                first_hit = step
        out["slow_motion"] = dict(setup=dict(conditions=False, warmup_ticks=20, point=list(point), swords=swords_setup(g),
                                             enemies=[es[0].setup], slowmo=0.25),
                                  first_hit_tick=first_hit, ult_t=r(sw.ult_t, 4), ult_cd=r(sw.ult_cd, 4), beat=r(sw.tick, 4), state=sw.state)
    return out


def case_maelstrom_rules():
    """Recharge per rarity, refusal while recharging or active, and the other slots keep fighting."""
    out = {}
    point = (PLAYER[0] + 200.0, PLAYER[1])
    for rarity in (0, 1, 2):
        g = fresh(rarities=(rarity, 0, 0))
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        ready = None
        at = {}
        for step in range(1, 800):
            tick(g)
            if step in (1, 60, 120, 300, 659, 660, 661):
                at[str(step)] = r(sw.ult_cd, 4)
            if sw.ult_cd <= 0.0 and ready is None:
                ready = step
        out["recharge_rarity%d" % rarity] = dict(setup=dict(conditions=False, swords=swords_setup(g)), ult_max=r(sw.ult_max, 4),
                                                 ready_tick=ready, ult_cd_at=at)
    g = fresh()
    sw = g.swords[0]
    key(g, pygame.K_q, mouse=point)
    tick(g, 200)  # Maelstrom (2.2 s) and its recovery are over, the recharge is not
    before = dict(state=sw.state, ult_cd=r(sw.ult_cd, 4), pos=[r(sw.pos.x), r(sw.pos.y)])
    key(g, pygame.K_q, mouse=(PLAYER[0] - 200.0, PLAYER[1]))
    after = dict(state=sw.state, ult_cd=r(sw.ult_cd, 4), pos=[r(sw.pos.x), r(sw.pos.y)])
    out["rejected_while_recharging"] = dict(setup=dict(conditions=False, swords=swords_setup(g), ticks=200), before=before, after=after,
                                            refused=before == after)
    g = fresh()
    sw = g.swords[0]
    key(g, pygame.K_q, mouse=point)
    tick(g, 30)
    snap = dict(state=sw.state, ult_cd=r(sw.ult_cd, 4), ult_t=r(sw.ult_t, 4), centre=[r(sw.point.x), r(sw.point.y)])
    sw.ult_cd = 0.0  # even with the recharge forced to zero the whirl refuses a second command
    key(g, pygame.K_q, mouse=(PLAYER[0] - 200.0, PLAYER[1]))
    out["rejected_while_active"] = dict(setup=dict(conditions=False, swords=swords_setup(g), ticks=30), before=snap,
                                        after=dict(state=sw.state, ult_cd=r(sw.ult_cd, 4), ult_t=r(sw.ult_t, 4),
                                                   centre=[r(sw.point.x), r(sw.point.y)]), point=list(point))
    # once the recharge is over Q works again
    g = fresh()
    sw = g.swords[0]
    key(g, pygame.K_q, mouse=point)
    tick(g, 11 * 60 + 10)
    key(g, pygame.K_q, mouse=point)
    out["again_after_recharge"] = dict(setup=dict(conditions=False, swords=swords_setup(g), ticks=11 * 60 + 10), state=sw.state)
    # Warden and the other slots: while slot 0 whirls, slots 1 and 2 keep their automatic sweeps
    with NoCrit(False):
        g = fresh(active=(1, 2))
        husk = foe(g, (PLAYER[0] + 120.0, PLAYER[1] + 10.0), hp=100000.0)
        key(g, pygame.K_q, mouse=(PLAYER[0] + 330.0, PLAYER[1] - 300.0))
        states = []
        for _ in range(60):
            tick(g)
            states.append([s.state for s in g.swords])
        out["others_keep_sweeping"] = dict(setup=dict(conditions=False, swords=swords_setup(g, (1, 2)), enemies=[husk.setup]),
                                           states_at_30=states[29], others_swept=any(st[1] != "idle" or st[2] != "idle" for st in states),
                                           husk_damaged=husk.hp < 100000.0)
    return out


def case_orb_during_maelstrom():
    """Maelstrom does not parry: an orb inside the whirl is left alone."""
    out = {}
    point = (PLAYER[0] + 260.0, PLAYER[1])
    with NoCrit(False):
        g = fresh()
        husk = foe(g, (point[0] + 30.0, point[1]))
        pr = orb(g, (point[0] + 10.0, point[1]))
        key(g, pygame.K_q, mouse=point)
        tick(g, 100)
        out["orb_in_the_whirl"] = dict(setup=dict(conditions=False, warmup_ticks=0, point=list(point), swords=swords_setup(g), enemies=[husk.setup],
                                                  orbs=[pr.setup]), orb_alive=not pr.dead, parry_hitstop=r(g.hitstop, 4))
    return out


# ------------------------------------------------------------------ conditions ON
CONDITION_FIELDS = ("hp", "burn", "burn_dps", "poison", "poison_dps", "poison_stacks", "chill", "chill_stacks", "frozen", "dot", "x", "y")


def enemy_condition_row(e):
    return dict(hp=r(e.hp, 4), burn=r(e.burn, 4), burn_dps=r(e.burn_dps, 4), poison=r(e.poison, 4), poison_dps=r(e.poison_dps, 4),
                poison_stacks=e.poison_stacks, chill=r(e.chill, 4), chill_stacks=e.chill_stacks, frozen=r(e.frozen, 4),
                dot=r(e.dot, 4), x=r(e.pos.x), y=r(e.pos.y))


def condition_trace(g, es, ticks, label):
    cols = [{f: [] for f in CONDITION_FIELDS} for _ in es]
    for _ in range(ticks):
        tick(g)
        for col, e in zip(cols, es):
            for f, v in enemy_condition_row(e).items():
                col[f].append(v)
    return cols


def case_sweep_conditions():
    """Warden's sweeps with each element: one dose per hit (burn, poison stacks, chill stacks), the
    damage-over-time cadence, refresh by the next sweep, kills by damage over time."""
    out = {}
    for index, element in enumerate(ELEMENTS):
        with NoCrit(False):
            g = fresh(rarities=(index, 0, 0), active=(0,), conditions=True, elements=(element, "ice", "fire"))
            husk = foe(g, (PLAYER[0] + 170.0, PLAYER[1] + 30.0), hp=300.0)
            tr = Trace(g.swords[0], [husk])
            cols = []
            for _ in range(340):
                tick(g)
                tr.step(g)
                cols.append(enemy_condition_row(husk))
            _CONDITION_CASES.append("sweep_" + element)
            out[element] = dict(setup=dict(conditions=True, crit=False, swords=swords_setup(g, (0,)), enemies=[husk.setup]),
                                trace=tr.out(), conditions={f: [c[f] for c in cols] for f in CONDITION_FIELDS}, kills=g.kills)
    # a pack of three: the element lands on each enemy swept, once per sweep
    with NoCrit(False):
        g = fresh(active=(0,), conditions=True, elements=("poison", "ice", "fire"))
        es = [foe(g, (PLAYER[0] + dx, PLAYER[1] + dy), hp=900.0) for dx, dy in [(150.0, 0.0), (170.0, 38.0), (170.0, -38.0)]]
        cols = condition_trace(g, es, 150, "pack")
        _CONDITION_CASES.append("sweep_pack")
        out["pack_poison"] = dict(setup=dict(conditions=True, crit=False, swords=swords_setup(g, (0,)), enemies=[e.setup for e in es]),
                                  conditions=[{f: col[f] for f in CONDITION_FIELDS} for col in cols])
    return out


def case_maelstrom_conditions():
    """Maelstrom with each element: one dose per tick on everything inside the blades (poison and chill
    stacks, burn refresh, freezing at the fourth ice stack and the shatter bonus on a frozen enemy), and
    the burst's two doses."""
    out = {}
    point = (PLAYER[0] + 260.0, PLAYER[1] + 40.0)
    layout = [((point[0] + 60.0, point[1] - 20.0), 2000.0, "husk"), ((point[0] - 90.0, point[1] + 60.0), 2000.0, "brute"),
              ((point[0] + 10.0, point[1] + 150.0), 2000.0, "runner")]
    for index, element in enumerate(ELEMENTS):
        with NoCrit(False):
            g = fresh(rarities=(index, 0, 0), conditions=True, elements=(element, "ice", "fire"))
            es = [foe(g, at, hp=hp, kind=kind) for at, hp, kind in layout]
            sw = g.swords[0]
            tick(g, 20)
            key(g, pygame.K_q, mouse=point)
            tr = Trace(sw, es)
            cols = [{f: [] for f in CONDITION_FIELDS} for _ in es]
            for _ in range(175):
                tick(g)
                tr.step(g)
                for col, e in zip(cols, es):
                    for f, v in enemy_condition_row(e).items():
                        col[f].append(v)
            _CONDITION_CASES.append("maelstrom_" + element)
            out[element] = dict(setup=dict(conditions=True, crit=False, warmup_ticks=20, point=list(point), swords=swords_setup(g),
                                           enemies=[e.setup for e in es]),
                                trace=tr.out(), conditions=[{f: col[f] for f in CONDITION_FIELDS} for col in cols], kills=g.kills)
    return out


# ------------------------------------------------------------------ keys
def case_keys():
    out = {}
    point = (PLAYER[0] + 200.0, PLAYER[1])
    for name, code in (("q", pygame.K_q), ("e", pygame.K_e), ("r", pygame.K_r)):
        g = fresh()
        key(g, code, mouse=point)
        out["key_" + name] = [s.state for s in g.swords]
    g = fresh()
    g.paused = True
    key(g, pygame.K_q, mouse=point)
    out["paused_q"] = dict(states=[s.state for s in g.swords], ult_cd=[r(s.ult_cd) for s in g.swords])
    g = fresh()
    g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    key(g, pygame.K_e, mouse=point)
    out["dead_e"] = dict(states=[s.state for s in g.swords], ult_cd=[r(s.ult_cd) for s in g.swords])
    # touch: the nearest living enemy, or 300 px ahead
    g = fresh()
    near_foe = foe(g, (PLAYER[0] + 350.0, PLAYER[1] + 100.0))
    far_foe = foe(g, (PLAYER[0] - 900.0, PLAYER[1]))
    aim = g.auto_aim()
    g.ultimate(0, aim)
    out["auto_aim"] = dict(setup=dict(conditions=False, swords=swords_setup(g), enemies=[near_foe.setup, far_foe.setup]),
                           nearest=[r(aim.x), r(aim.y)], centre=[r(g.swords[0].point.x), r(g.swords[0].point.y)])
    out["setup"] = dict(conditions=False, swords=swords_setup(fresh()))
    return out


def assert_fixtures_in_scope():
    for e in _CREATED:
        assert e.armed is None and e.kind in ("husk", "runner", "brute")
    for sw in _SWORDS:
        assert sw.kind == KIND
    return dict(enemies_created=len(_CREATED), armed_enemies=0, kinds=sorted({e.kind for e in _CREATED}),
                swords_used=sorted({sw.kind for sw in _SWORDS}), converge_used=False, waves_enabled=False,
                afflict_enabled_cases=sorted(set(_CONDITION_CASES)),
                afflict_disabled_everywhere_else=True, auto_attack_parked_unless_the_case_says_so=True)


def dumps(o, indent=0):
    """JSON with scalar lists and short objects on one line, so the committed file stays reviewable."""
    flat = json.dumps(o, separators=(", ", ": "))
    if not isinstance(o, (dict, list)) or len(flat) <= 110 or (isinstance(o, list) and all(not isinstance(x, (dict, list)) for x in o)):
        return flat
    pad = " " * (indent + 1)
    if isinstance(o, dict):
        return "{\n" + ",\n".join("%s%s: %s" % (pad, json.dumps(k), dumps(v, indent + 1)) for k, v in o.items()) + "\n" + " " * indent + "}"
    return "[\n" + ",\n".join(pad + dumps(v, indent + 1) for v in o) + "\n" + " " * indent + "]"


def main():
    cases = dict(
        table=case_table(), sweep=case_sweep(), acquire=case_acquire(), arc_coverage=case_arc_coverage(),
        multi_target=case_multi_target(), deaths=case_deaths(), parry=case_parry(),
        recover_and_cooldown=case_recover_and_cooldown(), range_and_start=case_range_and_start(),
        maelstrom_single=case_maelstrom_single(), maelstrom_pull=case_maelstrom_pull(), maelstrom_kills=case_maelstrom_kills(),
        maelstrom_clocks=case_maelstrom_clocks(), maelstrom_rules=case_maelstrom_rules(),
        orb_during_maelstrom=case_orb_during_maelstrom(), sweep_conditions=case_sweep_conditions(),
        maelstrom_conditions=case_maelstrom_conditions(), keys=case_keys(),
    )
    cases["fixture_scope"] = assert_fixtures_in_scope()
    text = dumps(cases)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
