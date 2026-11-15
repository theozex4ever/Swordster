#!/usr/bin/env python3
"""Captures focused reference cases for Pike (the long piercing thrust) and Skewer (its ultimate).

Usage:  python3 -I tools/reference/capture_pike_skewer.py [out.json]
        (the committed copy is godot/tests/reference/pike_skewer.json)

Slice #14 of the Godot port. Like the earlier captures (whose loader and helpers it reuses) it
drives the prototype's REAL classes -- `Game`, `Sword`, `Enemy`, `Player`, `Projectile` from
game/main.py -- with fixed 1/60 s steps under SDL's dummy drivers. Pike's internal sword type is
`"lance"` (`SWORD_TYPES["lance"]`, displayed "Pike"; its ultimate is "Skewer"); nothing here
re-implements a rule: the targeting preference, the thrust's geometry, hit set and parries come
from `Sword.acquire/begin/update/strike`, the aim, flight, impalement, carry and release from
`Sword.ultimate`/`Sword.update_ult`, the wall slam and bowling from `Enemy.update` and
`Game.separate`/`Game.wall_slam`, the damage, crits and conditions from `Game.hit_enemy` and
`Game.afflict`, and the Q/E/R keys from the real `Game.handle`.

Every case writes its fixture (`setup`) into the JSON and the Godot checks build their scenarios
from it, including the player's position and facing and whether elemental conditions are ON: the
physical cases run with `Game.afflict` switched off (`setup.conditions == false`, as in the earlier
slices), the cases whose subject is how the blows apply conditions (and the one whose carried
enemy burns to death) leave the prototype's own `afflict` ON. The capture asserts which is which.

Mechanics outside this slice are off, and the capture asserts that: every enemy is an unarmed
husk, runner or brute (arming and drops are issue #17); only Pike swords are equipped (Colossus is
#15) and Converge is never commanded (#16); the wave machine is off (#18). Per-case controls:
enemies stand still (speed 0), the auto-attack cooldown of a sword that is not meant to fight is
parked at 99 s, and crits are forced off (or on, where a case asks) by pinning `random.random`.
A few cases start an attack directly with `Sword.begin(target, aim)` (the prototype's own entry
point, also used by Converge) so the thrust line is chosen by the fixture rather than by `acquire`.
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
WORLD = NS["WORLD"]
DT = base.DT
r = base.r
NoCrit = base.NoCrit
SWORD_TYPES = NS["SWORD_TYPES"]
ENEMY_TYPES = NS["ENEMY_TYPES"]
KIND = "lance"
PLAYER = (1300.0, 900.0)  # the arena centre, where the prototype's player spawns
PARKED_CD = 99.0          # an auto-attack cooldown that never ends within a case
ELEMENTS = ("poison", "ice", "fire")
STATE_NAMES = {"idle": "idle", "windup": "windup", "strike": "strike", "recover": "recover", "ult": "ult"}

_CREATED = []
_SWORDS = []
_CONDITION_CASES = []


def fresh(seed=1, rarities=(0, 0, 0), active=(), conditions=False, count=3, elements=ELEMENTS, player=None, facing=None):
    """A game with `count` Pike swords (Q, E, R); those in `active` may attack at once, the rest are
    parked. No waves. `afflict` is the prototype's own only when `conditions` is set."""
    random.seed(seed)
    g = base.new_game(swords=[])
    if conditions:
        del g.afflict  # the shared helper switches conditions off
        assert g.afflict.__func__ is Game.afflict
    base.hold()
    assert (g.player.pos.x, g.player.pos.y) == PLAYER
    if player is not None:
        g.player.pos = V(player)
    if facing is not None:
        g.player.facing = V(facing)
    c = g.player.pos
    g.swords = [Sword(KIND, rarities[i], elements[i], c) for i in range(count)]
    for i, s in enumerate(g.swords):
        s.cd = 0.0 if i in active else PARKED_CD
        _SWORDS.append(s)
    g.setup_conditions = conditions
    g.setup_player = None if player is None else [r(player[0]), r(player[1])]
    g.setup_facing = None if facing is None else [r(facing[0]), r(facing[1])]
    return g


def setup_of(g, active=(), enemies=(), **extra):
    """The fixture, as the Godot side must rebuild it."""
    out = dict(conditions=g.setup_conditions, swords=[dict(type=KIND, rarity=s.rarity, element=s.element, cd=0.0 if i in active else PARKED_CD)
                                                       for i, s in enumerate(g.swords)], enemies=[e.setup for e in enemies])
    if g.setup_player is not None:
        out["player"] = g.setup_player
    if g.setup_facing is not None:
        out["facing"] = g.setup_facing
    out.update(extra)
    return out


def foe(g, at, hp=900.0, kind="husk", vel=(0.0, 0.0), stun=0.0):
    """An unarmed enemy from the prototype's constructor, pinned (it does not walk by itself)."""
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


def ult_phase(sw):
    return sw.phase if sw.state == "ult" else ""


class Trace:
    """Per-tick record (after each tick) of a sword and some enemies, as dict-of-lists."""

    def __init__(self, sw, enemies, detail=True):
        self.sw = sw
        self.enemies = enemies
        self.detail = detail
        self.state, self.x, self.y, self.ang = [], [], [], []
        self.vx, self.vy, self.ult_t, self.ult_cd, self.cd, self.phase, self.carried = [], [], [], [], [], [], []
        self.e = [dict(x=[], y=[], hp=[], vx=[], vy=[], stun=[], dead=[]) for _ in enemies]
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
        self.vx.append(r(sw.vel.x))
        self.vy.append(r(sw.vel.y))
        self.ult_t.append(r(sw.ult_t, 4))
        self.ult_cd.append(r(sw.ult_cd, 4))
        self.cd.append(r(sw.cd, 4))
        self.phase.append(ult_phase(sw))
        self.carried.append(len(sw.carried))
        for i, e in enumerate(self.enemies):
            d = self.e[i]
            d["x"].append(r(e.pos.x))
            d["y"].append(r(e.pos.y))
            d["hp"].append(r(e.hp, 4))
            d["vx"].append(r(e.vel.x))
            d["vy"].append(r(e.vel.y))
            d["stun"].append(r(e.stun, 4))
            d["dead"].append(1 if e.dead else 0)
        dealt = [(i, self._hp[i] - e.hp) for i, e in enumerate(self.enemies) if e.hp < self._hp[i]]
        if dealt:
            self.hits.append(dict(tick=self.n, dealt=[[i, r(d, 4)] for i, d in dealt], hitstop=r(g.hitstop, 4),
                                  trauma=r(g.trauma, 4), flash=[r(self.enemies[i].flash, 4) for i, _ in dealt]))
        self._hp = [e.hp for e in self.enemies]
        if sw.state != self._phase:
            self.transitions.append(dict(tick=self.n, to=STATE_NAMES[sw.state], ult_cd=r(sw.ult_cd, 4)))
            self._phase = sw.state

    def out(self):
        d = dict(ticks=self.n, hits=self.hits, transitions=self.transitions)
        for name in ("state", "x", "y", "ang", "vx", "vy", "ult_t", "ult_cd", "cd", "phase", "carried"):
            d[name] = getattr(self, name)
        d["enemies"] = [dict(e) for e in self.e]
        return d


def run_trace(g, sw, es, ticks):
    tr = Trace(sw, es)
    for _ in range(ticks):
        tick(g)
        tr.step(g)
    return tr


# ------------------------------------------------------------------ table
def case_table():
    t = SWORD_TYPES[KIND]
    u = t["ult"]
    out = dict(kind=KIND, name=t["name"], blurb=t["blurb"], length=t["length"], width=t["width"], range=t["range"],
               cooldown=t["cooldown"], damage=t["damage"], knock=t["knock"], windup=t["windup"], speed=t["speed"],
               hitstop=t["hitstop"], shake=t["shake"], ult_name=u["name"], ult_cd=u["cd"], ult_range=u["range"],
               ult_speed=u["speed"], ult_shot=u["shot"], keys="QER", converge_cd=NS["CONVERGE_CD"])
    out["rarities"] = []
    for i in range(3):
        s = Sword(KIND, i, "fire", V(0, 0))
        out["rarities"].append(dict(damage=r(s.damage, 4), cooldown=r(s.cooldown, 4), range=r(s.range, 4), length=r(s.L, 4),
                                    scale=r(s.scale, 4), ult_max=r(s.ult_max, 4)))
    # constants read off the code (Sword.acquire / update / strike / ultimate / update_ult)
    out["inline"] = dict(
        far_min=130.0, windup_standoff_length=0.5, windup_standoff_extra=120.0, windup_spring=[150.0, 20.0], windup_ang_rate=16.0,
        overshoot=170.0, tail=0.3, tip=0.65, hit_pad=7.0, parry_pad=8.0, recover_time=0.35, recover_speed=420.0,
        ult_aim_time=0.38, ult_aim_standoff=40.0, ult_aim_spring=[200.0, 24.0], launch_ahead=10.0, launch_shake=0.2,
        ult_tail=0.3, ult_tip=0.65, ult_hit_pad=18.0, ult_damage=2.2, ult_stacks=2, ult_hit_shake=0.12, carry_stun=0.5,
        ult_parry_pad=14.0, wall_margin=10.0, release_range=750.0, release_wall=1100.0, release_stun=0.6,
        ult_recover_time=0.35, recover_range=420.0, recover_wall=300.0, heavy_flash=0.2, normal_flash=0.11)
    out["knock_mult"] = {k: ENEMY_TYPES[k]["knock"] for k in ("husk", "runner", "brute")}
    out["radius"] = {k: ENEMY_TYPES[k]["r"] for k in ("husk", "runner", "brute")}
    out["world"] = [WORLD.left, WORLD.top, WORLD.right, WORLD.bottom]
    return out


# ------------------------------------------------------------------ the thrust
def case_thrust():
    """One Pike against one stationary enemy: windup, the thrust, its recovery, the cooldown and a second
    thrust, with damage, knockback, stun, flash, hitstop and shake, for each rarity and a crit."""
    out = {}
    for label, rarity, crit in (("common", 0, False), ("common_crit", 0, True), ("rare", 1, False), ("mythic", 2, False)):
        with NoCrit(crit):
            g = fresh(rarities=(rarity, 0, 0), active=(0,))
            husk = foe(g, (PLAYER[0] + 300.0, PLAYER[1] + 40.0))
            tr = run_trace(g, g.swords[0], [husk], 260)
            out[label] = dict(setup=setup_of(g, (0,), [husk], crit=crit), trace=tr.out(), kills=g.kills)
    return out


def case_acquire():
    """Who a Pike targets: the nearest enemy within range + its radius of the player, but a candidate
    farther than 130 px from the player wins over every nearer one."""
    out = {}
    rng = SWORD_TYPES[KIND]["range"]
    husk_r = ENEMY_TYPES["husk"]["r"]
    for label, distance in (("just_inside", rng + husk_r - 1.0), ("just_outside", rng + husk_r + 1.0), ("close", 90.0)):
        with NoCrit(False):
            g = fresh(active=(0,))
            husk = foe(g, (PLAYER[0] + distance, PLAYER[1]))
            left_idle = None
            for step in range(1, 60):
                tick(g)
                if g.swords[0].state != "idle" and left_idle is None:
                    left_idle = step
            out[label] = dict(setup=setup_of(g, (0,), [husk]), distance=r(distance), left_idle=left_idle)
    # (label, [(dx, dy, kind)], note): which of the placed enemies is the target after the first tick
    layouts = {
        "far_preferred": [(90.0, -20.0, "husk"), (-250.0, 10.0, "husk")],
        "far_preferred_swapped": [(-250.0, 10.0, "husk"), (90.0, -20.0, "husk")],
        "near_only": [(100.0, 0.0, "husk"), (-60.0, 80.0, "runner")],
        "just_inside_130": [(130.0, 0.0, "husk"), (-60.0, 80.0, "husk")],
        "just_beyond_130": [(131.0, 0.0, "husk"), (-60.0, 80.0, "husk")],
        "nearest_of_the_far": [(300.0, 20.0, "husk"), (-240.0, 0.0, "husk"), (60.0, 360.0, "brute")],
        "far_but_out_of_range": [(90.0, 0.0, "husk"), (480.0, 0.0, "husk")],
        "far_runner_in_range": [(90.0, 0.0, "husk"), (440.0, 0.0, "runner")],
        "far_brute_in_range": [(90.0, 0.0, "husk"), (455.0, 0.0, "brute")],
        "far_at_the_edge": [(90.0, 0.0, "husk"), (445.0, 0.0, "husk")],
    }
    for label, placed in layouts.items():
        with NoCrit(False):
            g = fresh(active=(0,))
            es = [foe(g, (PLAYER[0] + dx, PLAYER[1] + dy), kind=k) for dx, dy, k in placed]
            tick(g)
            sw = g.swords[0]
            out["target_" + label] = dict(setup=setup_of(g, (0,), es), target_index=es.index(sw.target) if sw.target in es else None)
    return out


def thrust_line():
    """A thrust aimed straight east at a target 300 px from the player."""
    return (PLAYER[0] + 300.0, PLAYER[1])


def case_geometry():
    """Which points around a thrust it reaches, and on which tick: a stationary husk (the probe) is
    placed at `along` px east of the player and `lateral` px off the line while the thrust's own target
    stands 300 px east. The thrust starts at tick 0 with `Sword.begin`. Husk and brute probes."""
    out = {}
    target = thrust_line()
    alongs = [-60.0, -20.0, 40.0, 120.0, 200.0, 260.0, 340.0, 420.0, 470.0, 490.0, 520.0, 560.0, 700.0]
    laterals = [0.0, 6.0, 14.0, 20.0, 22.0, 24.0, 28.0, 36.0, 45.0, 52.0]
    for kind in ("husk", "brute"):
        cells = []
        for along in alongs:
            for lat in laterals:
                at = (PLAYER[0] + along, PLAYER[1] + lat)
                if abs(at[0] - target[0]) < 45.0 and abs(at[1] - target[1]) < 45.0:
                    continue
                with NoCrit(False):
                    g = fresh(active=())
                    sw = g.swords[0]
                    tgt = foe(g, target)
                    probe = foe(g, at, kind=kind)
                    sw.begin(tgt, V(target))
                    hit_tick = None
                    for step in range(1, 70):
                        tick(g)
                        if probe.hp < probe.maxhp and hit_tick is None:
                            hit_tick = step
                    cells.append(dict(along=along, lateral=lat, x=r(at[0]), y=r(at[1]), hit_tick=hit_tick, dealt=r(probe.maxhp - probe.hp, 4)))
        out["probe_" + kind] = cells
    g = fresh(active=())
    tgt = foe(g, target)
    out["setup"] = dict(conditions=False, swords=setup_of(g)["swords"], target=tgt.setup)
    return out


def case_piercing():
    """Several enemies on one thrust: each takes exactly one hit per attack, on its own tick, and the
    Pike does not stop at the first. A dense line (no gaps for a fast thrust to jump), a spread pack, a
    brute that stays in the path across attacks, and three Pikes at once."""
    out = {}
    layouts = {
        "dense_line": [(130.0 + 38.0 * i, 0.0, "husk") for i in range(11)],
        "spread_pack": [(150.0, 20.0, "husk"), (230.0, -26.0, "runner"), (300.0, 4.0, "brute"), (360.0, 30.0, "husk"), (420.0, -10.0, "husk"), (-200.0, 30.0, "husk")],
    }
    for label, placed in layouts.items():
        with NoCrit(False):
            g = fresh(active=(0,))
            es = [foe(g, (PLAYER[0] + dx, PLAYER[1] + dy), kind=k) for dx, dy, k in placed]
            tr = run_trace(g, g.swords[0], es, 150)
            per_enemy = [sum(1 for h in tr.hits for i, _ in h["dealt"] if i == k) for k in range(len(es))]
            out[label] = dict(setup=setup_of(g, (0,), es), trace=tr.out(), hits_per_enemy=per_enemy)
    with NoCrit(False):
        g = fresh(active=(0,))
        brute = foe(g, (PLAYER[0] + 260.0, PLAYER[1]), kind="brute", hp=100000.0)
        tr = run_trace(g, g.swords[0], [brute], 330)
        out["brute_across_attacks"] = dict(setup=setup_of(g, (0,), [brute]), trace=tr.out())
    with NoCrit(False):
        g = fresh(active=(0, 1, 2))
        es = [foe(g, (PLAYER[0] + dx, PLAYER[1] + dy), kind=k) for dx, dy, k in
              [(180.0, 0.0, "husk"), (260.0, 30.0, "husk"), (-200.0, 10.0, "runner"), (20.0, 300.0, "husk"), (30.0, -330.0, "brute")]]
        tr = run_trace(g, g.swords[0], es, 240)
        out["three_pikes"] = dict(setup=setup_of(g, (0, 1, 2), es), trace=tr.out(), hp=[r(e.hp, 4) for e in es],
                                  states=[s.state for s in g.swords], kills=g.kills)
    return out


def case_deaths():
    """Deaths during a thrust resolve once; a corpse is not hit again, by the same or another sword."""
    out = {}
    with NoCrit(False):
        g = fresh(active=(0,))
        es = [foe(g, (PLAYER[0] + 200.0, PLAYER[1] + 4.0), hp=5.0), foe(g, (PLAYER[0] + 260.0, PLAYER[1] - 4.0)), foe(g, (PLAYER[0] + 330.0, PLAYER[1]), hp=9.0)]
        tr = run_trace(g, g.swords[0], es, 120)
        out["kills_in_thrust"] = dict(setup=setup_of(g, (0,), es), trace=tr.out(), kills=g.kills, combo=g.combo, motes=len(g.motes), left=len(g.enemies))
    with NoCrit(False):
        # two Pikes thrust at the same 10 hp enemy on the same tick: the first kills it, the second finds a corpse
        g = fresh(active=(0, 1))
        victim = foe(g, (PLAYER[0] + 240.0, PLAYER[1]), hp=10.0)
        tr = run_trace(g, g.swords[0], [victim], 90)
        out["two_swords_one_victim"] = dict(setup=setup_of(g, (0, 1), [victim]), trace=tr.out(), kills=g.kills, motes=len(g.motes))
    return out


def case_parry():
    """A thrust parries every orb its swept segment touches within 8 px (plus the orb's radius), hit or
    no hit, and an orb only brushing its tail or far beyond its tip survives. The probe orbs stand at
    `along` px east of the player and `lateral` px off the line of a thrust started with `Sword.begin`."""
    out = {}
    target = thrust_line()
    cells = []
    for along in (60.0, 200.0, 330.0, 470.0, 520.0, 600.0):
        for lat in (0.0, 8.0, 14.0, 15.0, 16.0, 20.0):
            with NoCrit(False):
                g = fresh(active=())
                sw = g.swords[0]
                tgt = foe(g, target)
                pr = orb(g, (PLAYER[0] + along, PLAYER[1] + lat))
                sw.begin(tgt, V(target))
                parried = None
                for step in range(1, 60):
                    tick(g)
                    if pr.dead and parried is None:
                        parried = step
                cells.append(dict(along=along, lateral=lat, x=r(pr.pos.x), y=r(pr.pos.y), parried_tick=parried))
    out["grid"] = cells
    g = fresh(active=())
    tgt = foe(g, target)
    out["setup"] = dict(conditions=False, swords=setup_of(g)["swords"], target=tgt.setup)
    # an orb with nothing to hit: the thrust at an enemy that stands off to the side still parries
    with NoCrit(False):
        g = fresh(active=(0,))
        husk = foe(g, (PLAYER[0] + 300.0, PLAYER[1]))
        pr = orb(g, (PLAYER[0] + 380.0, PLAYER[1] + 12.0))
        parried = None
        hitstop_at = None
        for step in range(1, 80):
            tick(g)
            if pr.dead and parried is None:
                parried = step
                hitstop_at = r(g.hitstop, 4)
        out["orb_in_the_path"] = dict(setup=setup_of(g, (0,), [husk], orbs=[pr.setup]), parried_tick=parried, hitstop=hitstop_at, hp=r(husk.hp, 4))
    return out


# ------------------------------------------------------------------ the Skewer start
def case_start():
    """Where a Skewer points for points inside, on and beyond its range (it is a skill shot, so the point
    only gives the heading), on the player (the player's facing) and for a moved facing; it does not move
    the sword yet; it starts the recharge and the aim clock; it interrupts a windup and a thrust."""
    out = {}
    offsets = {"east_near": (100.0, 0.0), "east_far": (900.0, 0.0), "just_beyond_range": (951.0, 0.0), "diagonal_far": (500.0, -600.0),
               "south": (0.0, 250.0), "south_west_far": (-1000.0, 300.0), "on_the_player": (0.0, 0.0)}
    for label, (dx, dy) in offsets.items():
        for facing in (None, (0.0, -1.0)):
            g = fresh(facing=facing)
            tick(g, 25)  # the swords drift along their orbits, so the starting position is not the origin
            sw = g.swords[1]
            before = (sw.pos.x, sw.pos.y)
            point = (g.player.pos.x + dx, g.player.pos.y + dy)
            key(g, pygame.K_e, mouse=point)
            out[label + ("" if facing is None else "_facing_north")] = dict(
                point=[r(point[0]), r(point[1])], state=sw.state, phase=sw.phase, dir=[r(sw.dir.x, 5), r(sw.dir.y, 5)],
                pos=[r(sw.pos.x), r(sw.pos.y)], before=[r(before[0]), r(before[1])], ult_cd=r(sw.ult_cd), ult_t=r(sw.ult_t, 4),
                facing=[r(g.player.facing.x, 4), r(g.player.facing.y, 4)])
    g = fresh()
    out["setup"] = setup_of(g, warmup_ticks=25, slot=1)
    out["setup_facing_north"] = setup_of(fresh(facing=(0.0, -1.0)), warmup_ticks=25, slot=1)
    with NoCrit(False):
        g = fresh(active=(0,))
        husk = foe(g, (PLAYER[0] + 300.0, PLAYER[1]))
        tick(g, 3)
        before = g.swords[0].state
        key(g, pygame.K_q, mouse=(PLAYER[0] + 200.0, PLAYER[1]))
        sw = g.swords[0]
        out["interrupts_windup"] = dict(setup=setup_of(g, (0,), [husk]), state_before=before, state_after=sw.state, phase=sw.phase,
                                        target_cleared=sw.target is None, hit_cleared=len(sw.hit) == 0)
    with NoCrit(False):
        g = fresh(active=(0,))
        husk = foe(g, (PLAYER[0] + 300.0, PLAYER[1]))
        for _ in range(60):
            tick(g)
            if g.swords[0].state == "strike":
                break
        sw = g.swords[0]
        hit_before = len(sw.hit)
        state_before = sw.state
        key(g, pygame.K_q, mouse=(PLAYER[0] - 200.0, PLAYER[1]))
        out["interrupts_thrust"] = dict(setup=setup_of(g, (0,), [husk]), state_before=state_before, hit_before=hit_before, state_after=sw.state,
                                        hit_after=len(sw.hit), dir=[r(sw.dir.x, 5), r(sw.dir.y, 5)])
    return out


# ------------------------------------------------------------------ the Skewer flight
def skewer_run(player=None, point=None, rarity=0, element_conditions=False, enemies=(), ticks=160, crit=False, elements=ELEMENTS,
               extra_orbs=(), warmup=0, active=(), count=3, facing=None):
    """A Skewer from slot 0 along the line to `point` (default: east), tracing the sword and every enemy
    given as (dx, dy, kind, hp) relative to the player."""
    with NoCrit(crit):
        g = fresh(rarities=(rarity, 0, 0), conditions=element_conditions, elements=elements, player=player, active=active, count=count, facing=facing)
        c = g.player.pos
        es = [foe(g, (c.x + dx, c.y + dy), kind=k, hp=hp) for dx, dy, k, hp in enemies]
        orbs = [orb(g, (c.x + dx, c.y + dy)) for dx, dy in extra_orbs]
        sw = g.swords[0]
        tick(g, warmup)
        if point is None:
            point = (c.x + 400.0, c.y)
        key(g, pygame.K_q, mouse=point)
        tr = run_trace(g, sw, es, ticks)
        setup = setup_of(g, active, es, crit=crit, point=[r(point[0]), r(point[1])], warmup_ticks=warmup,
                         orbs=[o.setup for o in orbs])
        return g, sw, es, orbs, tr, setup


def case_skewer_single():
    """One Skewer through one enemy (each rarity and a crit): the aim, the launch, the heavy blow, the
    carry and the release at the range limit, then the release's flight."""
    out = {}
    for label, rarity, crit in (("common", 0, False), ("common_crit", 0, True), ("rare", 1, False), ("mythic", 2, False)):
        g, sw, es, _, tr, setup = skewer_run(rarity=rarity, crit=crit, enemies=[(420.0, 10.0, "husk", 900.0)], ticks=110)
        out[label] = dict(setup=setup, trace=tr.out(), kills=g.kills)
    return out


def line_layout():
    return [(250.0, 0.0, "husk", 900.0), (330.0, 12.0, "runner", 900.0), (420.0, -8.0, "brute", 900.0), (520.0, 14.0, "husk", 900.0),
            (700.0, -4.0, "husk", 900.0), (400.0, 60.0, "husk", 900.0), (420.0, -70.0, "husk", 900.0), (-120.0, 0.0, "husk", 900.0),
            (1150.0, 0.0, "husk", 900.0)]


def case_skewer_carry():
    """Several enemies on one Skewer: those the segment touches (radius + 18 off the line) are struck once,
    impaled and carried together, ones beside the line, behind the player and beyond the range are left alone."""
    out = {}
    g, sw, es, _, tr, setup = skewer_run(enemies=line_layout(), ticks=130)
    per = [sum(1 for h in tr.hits for i, _ in h["dealt"] if i == k) for k in range(len(es))]
    out["line"] = dict(setup=setup, trace=tr.out(), hits_per_enemy=per, kills=g.kills)
    # enemies close to the player's side of the launch: the first flight tick's segment reaches behind the sword
    muzzle = [(-60.0, 0.0, "husk", 900.0), (-35.0, 30.0, "husk", 900.0), (-20.0, 0.0, "husk", 900.0), (5.0, -34.0, "runner", 900.0), (30.0, 0.0, "husk", 900.0), (70.0, 10.0, "brute", 900.0)]
    g, sw, es, _, tr, setup = skewer_run(enemies=muzzle, ticks=90)
    out["muzzle"] = dict(setup=setup, trace=tr.out(), kills=g.kills)
    # a crowd that overlaps itself: the crowd separation pushes carried enemies apart while they are carried
    crowd = [(260.0 + 20.0 * (i % 4), -30.0 + 22.0 * (i // 4) + 6.0 * (i % 3), "husk" if i % 5 else "runner", 900.0) for i in range(12)]
    g, sw, es, _, tr, setup = skewer_run(enemies=crowd, ticks=130)
    out["crowd"] = dict(setup=setup, trace=tr.out(), kills=g.kills)
    # three Skewers from three Pikes on one tick, with enemies on each line: separate hit sets and carries
    with NoCrit(False):
        g = fresh()
        es = [foe(g, (PLAYER[0] + 300.0, PLAYER[1])), foe(g, (PLAYER[0] - 300.0, PLAYER[1] + 10.0)), foe(g, (PLAYER[0] + 20.0, PLAYER[1] - 300.0)),
              foe(g, (PLAYER[0] + 120.0, PLAYER[1] + 200.0))]
        key(g, pygame.K_q, mouse=(PLAYER[0] + 400.0, PLAYER[1]))
        key(g, pygame.K_e, mouse=(PLAYER[0] - 400.0, PLAYER[1]))
        key(g, pygame.K_r, mouse=(PLAYER[0] + 20.0, PLAYER[1] - 400.0))
        tr = run_trace(g, g.swords[0], es, 110)
        out["three_skewers"] = dict(setup=setup_of(g, (), es, points=[[PLAYER[0] + 400.0, PLAYER[1]], [PLAYER[0] - 400.0, PLAYER[1]], [PLAYER[0] + 20.0, PLAYER[1] - 400.0]]),
                                    trace=tr.out(), kills=g.kills, states=[s.state for s in g.swords], hp=[r(e.hp, 4) for e in es])
    return out


def case_skewer_empty():
    """A Skewer with nothing to hit: it still aims, flies, ends at its range (or the wall) and recovers."""
    out = {}
    for label, player, point in (("range", None, (PLAYER[0] + 400.0, PLAYER[1])), ("wall", (2150.0, 900.0), (2400.0, 900.0)),
                                 ("diagonal_range", None, (PLAYER[0] + 300.0, PLAYER[1] + 300.0))):
        g, sw, es, _, tr, setup = skewer_run(player=player, point=point, enemies=[], ticks=100)
        out[label] = dict(setup=setup, trace=tr.out())
    return out


def wall_layout(dx, dy):
    """Enemies along a heading (dx, dy): near the sword, mid, beside the line, and one pinned just in
    front of the wall, as offsets from the player."""
    ux, uy = dx / math.hypot(dx, dy), dy / math.hypot(dx, dy)
    nx, ny = -uy, ux
    pts = [(170.0, 0.0, "husk"), (240.0, 14.0, "runner"), (300.0, -10.0, "brute"), (370.0, 6.0, "husk"), (260.0, 40.0, "husk"), (330.0, -45.0, "husk")]
    return [(ux * a + nx * b, uy * a + ny * b, k, 900.0) for a, b, k in pts]


def case_skewer_walls():
    """A Skewer whose tip leaves the arena (shrunk by 20 px in each dimension): whatever is still impaled is flung at 1100 px/s
    and, stunned, slams into the wall (wall slam damage, bowling the enemies it meets); the sword is kicked
    back. East, west, north and south walls and a corner, each with a pinned enemy right at the wall."""
    out = {}
    cases = {
        "east": ((2150.0, 900.0), (1.0, 0.0)), "west": ((450.0, 900.0), (-1.0, 0.0)),
        "north": ((1300.0, 700.0), (0.0, -1.0)), "south": ((1300.0, 1300.0), (0.0, 1.0)),
        "corner_north_east": ((2100.0, 500.0), (1.0, -1.0)), "corner_south_west": ((480.0, 1350.0), (-1.0, 1.0)),
    }
    for label, (player, heading) in cases.items():
        layout = wall_layout(*heading)
        # an enemy pinned right at the wall the Skewer drives into
        ux, uy = heading[0] / math.hypot(*heading), heading[1] / math.hypot(*heading)
        px, py = player
        # distance along the heading to the wall
        to_wall = min((WORLD.right - 40.0 - px) / ux if ux > 0 else (40.0 - px) / ux if ux < 0 else 1e9,
                      (WORLD.bottom - 40.0 - py) / uy if uy > 0 else (40.0 - py) / uy if uy < 0 else 1e9)
        layout = layout + [(ux * to_wall, uy * to_wall, "husk", 900.0)]
        g, sw, es, _, tr, setup = skewer_run(player=player, point=(px + heading[0] * 400.0, py + heading[1] * 400.0), enemies=layout, ticks=110)
        out[label] = dict(setup=setup, trace=tr.out(), kills=g.kills, slams=sum(1 for h in tr.hits if h["tick"] > 0))
    # a bowling pile-up against the wall: others stand where the released enemy slams
    pile = [(300.0, 0.0, "husk", 900.0), (540.0, 20.0, "husk", 900.0), (590.0, -14.0, "husk", 900.0), (560.0, 60.0, "runner", 900.0), (610.0, 30.0, "brute", 900.0)]
    g, sw, es, _, tr, setup = skewer_run(player=(1950.0, 900.0), point=(2350.0, 900.0), enemies=pile, ticks=110)
    out["pile_up"] = dict(setup=setup, trace=tr.out(), kills=g.kills)
    return out


def case_skewer_boundary():
    """The wall test is the sword's tip against the arena shrunk by 20 px in each dimension (`WORLD.inflate(-20, -20)`: 10 px per side): just inside (0.01 px) the
    sword flies on one more tick, just outside it ends at once, on each of the four walls. The sword is
    put in flight directly (state, phase, position, clock) a tick before the boundary."""
    out = {}
    length = SWORD_TYPES[KIND]["length"]
    step = 2600.0 / 60.0
    tipoff = length * 0.65
    headings = {"east": (1.0, 0.0, WORLD.right - 10.0), "west": (-1.0, 0.0, WORLD.left + 10.0),
                "south": (0.0, 1.0, WORLD.bottom - 10.0), "north": (0.0, -1.0, WORLD.top + 10.0)}
    for label, (ux, uy, edge) in headings.items():
        axis = ux + uy  # +1 toward the larger coordinate, -1 toward the smaller
        for side, delta in (("inside", -0.01), ("outside", 0.01)):
            with NoCrit(False):
                g = fresh()
                sw = g.swords[0]
                # the tip after the next tick's step sits `delta` beyond (outside) or short of (inside) the edge
                along = edge + axis * delta - axis * (tipoff + step)
                start = V(along, 900.0) if ux != 0.0 else V(1300.0, along)
                victim_at = (edge - 20.0 * axis, 900.0) if ux != 0.0 else (1300.0, edge - 20.0 * axis)
                victim = foe(g, victim_at)
                sw.state = "ult"
                sw.phase = "fly"
                sw.dir = V(ux, uy)
                sw.pos = V(start)
                sw.ult_t = 0.3
                sw.ult_cd = sw.ult_max
                sw.hit.clear()
                tr = Trace(sw, [victim])
                for _ in range(6):
                    tick(g)
                    tr.step(g)
                out["%s_%s" % (label, side)] = dict(
                    setup=setup_of(g, (), [victim], heading=[ux, uy], start=[r(start.x, 4), r(start.y, 4)], ult_t=0.3),
                    trace=tr.out(), left_tick=next((i + 1 for i, s in enumerate(tr.state) if s == "recover"), None))
    return out


def case_skewer_range():
    """The range limit: the flight lasts range / speed seconds (22 ticks) from the launch and releases
    everything still impaled at 750 px/s; an enemy that would be reached by tick 23 is not."""
    out = {}
    for label, dxs in (("near_the_end", (650.0, 780.0, 880.0, 900.0, 940.0)), ("beyond", (1010.0, 1080.0))):
        g, sw, es, _, tr, setup = skewer_run(enemies=[(dx, 8.0 * i, "husk", 900.0) for i, dx in enumerate(dxs)], ticks=110)
        out[label] = dict(setup=setup, trace=tr.out())
    return out


# ------------------------------------------------------------------ deaths while impaled
def case_skewer_deaths():
    """What happens to enemies that die during a Skewer. The prototype's loops iterate every enemy of the
    update, corpses included, and drop the dead from the carry list only at the next flight tick."""
    out = {}
    # a fragile enemy dies of the blow itself: it joins the hit set, is not carried, and the Skewer goes on
    g, sw, es, _, tr, setup = skewer_run(enemies=[(260.0, 0.0, "husk", 40.0), (300.0, 20.0, "husk", 900.0), (340.0, -6.0, "runner", 30.0), (390.0, 6.0, "husk", 900.0)], ticks=100)
    out["killed_by_the_blow"] = dict(setup=setup, trace=tr.out(), kills=g.kills, motes=len(g.motes), left=len(g.enemies))
    # killed from outside between two ticks while impaled, with living enemies overlapping it: the corpse
    # leaves the carry list at the next flight tick but still moves and is separated until its tick ends
    for label, extra in (("killed_while_carried_at_once", 0), ("killed_while_carried_later", 5)):
        with NoCrit(False):
            g = fresh()
            es = [foe(g, (PLAYER[0] + 250.0, PLAYER[1])), foe(g, (PLAYER[0] + 262.0, PLAYER[1] + 14.0)), foe(g, (PLAYER[0] + 258.0, PLAYER[1] - 20.0), kind="runner"),
                  foe(g, (PLAYER[0] + 330.0, PLAYER[1] + 4.0))]
            sw = g.swords[0]
            key(g, pygame.K_q, mouse=(PLAYER[0] + 400.0, PLAYER[1]))
            tr = Trace(sw, es)
            armed_at = None
            for n in range(1, 101):
                tick(g)
                tr.step(g)
                if armed_at is None and es[0] in sw.carried and es[1] in sw.carried:
                    armed_at = n
                if armed_at is not None and n == armed_at + extra:
                    g.kill(es[0], V(0, -1), False)
            assert armed_at is not None
            out[label] = dict(setup=setup_of(g, (), es, point=[PLAYER[0] + 400.0, PLAYER[1]], kill_after_ticks=extra, kill_index=0),
                              trace=tr.out(), kills=g.kills, motes=len(g.motes), left=len(g.enemies), armed_at=armed_at)
    # burning to death while carried (conditions ON): the Skewer's two doses of fire outlast the carried enemy
    with NoCrit(False):
        g = fresh(conditions=True, elements=("fire", "fire", "fire"))
        es = [foe(g, (PLAYER[0] + 300.0, PLAYER[1]), hp=55.0), foe(g, (PLAYER[0] + 322.0, PLAYER[1] + 12.0)), foe(g, (PLAYER[0] + 360.0, PLAYER[1] - 6.0), kind="brute")]
        key(g, pygame.K_q, mouse=(PLAYER[0] + 400.0, PLAYER[1]))
        tr = run_trace(g, g.swords[0], es, 110)
        _CONDITION_CASES.append("skewer_burn_dies_carried")
        out["burns_while_carried"] = dict(setup=setup_of(g, (), es, point=[PLAYER[0] + 400.0, PLAYER[1]]), trace=tr.out(), kills=g.kills, motes=len(g.motes),
                                          died_tick=next((i + 1 for i, d in enumerate(tr.e[0]["dead"]) if d), None))
    # a Pike (slot 0, which acts before the Skewer's slot 1) thrusts through a 20 hp enemy on the very tick the
    # Skewer's segment reaches it: the thrust kills it first, so the Skewer finds a corpse. The corpse joins the
    # Skewer's hit set (the prototype adds it before `hit_enemy` returns early) and is not impaled. The thrust's
    # start is searched for (the first tick on which that happens), and recorded as the fixture.
    found = None
    for begin_delay in range(1, 40):
        with NoCrit(False):
            g = fresh()
            es = [foe(g, (PLAYER[0] + 270.0, PLAYER[1]), hp=20.0), foe(g, (PLAYER[0] + 292.0, PLAYER[1] + 22.0)),
                  foe(g, (PLAYER[0] + 340.0, PLAYER[1] - 18.0), kind="runner")]
            sk, th = g.swords[1], g.swords[0]
            key(g, pygame.K_e, mouse=(PLAYER[0] + 400.0, PLAYER[1]))
            tr = Trace(sk, es)
            joined_dead = None
            for n in range(1, 111):
                if n == begin_delay:
                    th.begin(es[0], V(es[0].pos))
                was_in_set = es[0] in sk.hit
                tick(g)
                tr.step(g)
                if joined_dead is None and not was_in_set and es[0] in sk.hit and es[0].dead:
                    joined_dead = n
        if joined_dead is not None:
            found = (begin_delay, joined_dead, g, es, tr)
            break
    assert found is not None
    begin_delay, joined_dead, g, es, tr = found
    out["corpse_joins_the_hit_set"] = dict(setup=setup_of(g, (), es, skewer_slot=1, thrust_slot=0, thrust_begin_tick=begin_delay, point=[PLAYER[0] + 400.0, PLAYER[1]]),
                                           trace=tr.out(), kills=g.kills, motes=len(g.motes), left=len(g.enemies), joined_tick=joined_dead,
                                           carried_at_end=len(g.swords[1].carried), hit_size=len(g.swords[1].hit), impaled_corpse=es[0] in g.swords[1].carried)
    # corpses in the carry list at a wall: an impaled enemy beside others, and the one pinned against the wall,
    # are killed from outside on the tick before the Skewer's tip leaves the arena. They are dead (still in
    # the run until the tick ends, and in `carried` until the flight tick drops them) when the release happens.
    player, heading = (2150.0, 900.0), (1.0, 0.0)
    layout = wall_layout(*heading) + [(WORLD.right - 40.0 - player[0], 0.0, "husk", 900.0)]
    probe_g, probe_sw, _, _, probe_tr, _ = skewer_run(player=player, point=(player[0] + 400.0, player[1]), enemies=layout, ticks=60)
    release_tick = next(i + 1 for i, st in enumerate(probe_tr.state) if st == "recover")
    kill_indices = [3, len(layout) - 1]
    with NoCrit(False):
        g = fresh(player=player)
        c = g.player.pos
        es = [foe(g, (c.x + dx, c.y + dy), kind=k, hp=hp) for dx, dy, k, hp in layout]
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=(player[0] + 400.0, player[1]))
        tr = Trace(sw, es)
        for n in range(1, 111):
            tick(g)
            tr.step(g)
            if n == release_tick - 1:
                for index in kill_indices:
                    g.kill(es[index], V(0, -1), False)
        out["corpses_at_the_wall"] = dict(setup=setup_of(g, (), es, point=[player[0] + 400.0, player[1]], kill_after_tick=release_tick - 1, kill_indices=kill_indices),
                                          trace=tr.out(), kills=g.kills, motes=len(g.motes), left=len(g.enemies), release_tick=release_tick)
    # the player dies in the middle of the flight: the sword goes idle and lets go
    with NoCrit(False):
        g = fresh()
        es = [foe(g, (PLAYER[0] + 300.0, PLAYER[1])), foe(g, (PLAYER[0] + 340.0, PLAYER[1] + 10.0))]
        key(g, pygame.K_q, mouse=(PLAYER[0] + 400.0, PLAYER[1]))
        tr = Trace(g.swords[0], es)
        for n in range(1, 120):
            if n == 28:
                g.hurt_player(1000, V(PLAYER[0] - 50.0, PLAYER[1]))
            tick(g)
            tr.step(g)
        out["player_dies_in_flight"] = dict(setup=setup_of(g, (), es, point=[PLAYER[0] + 400.0, PLAYER[1]], die_after_ticks=27), trace=tr.out(),
                                            state=g.swords[0].state, carried=len(g.swords[0].carried))
    return out


# ------------------------------------------------------------------ rules: recharge, rejection, others
def case_skewer_rules():
    out = {}
    point = (PLAYER[0] + 400.0, PLAYER[1])
    for rarity in (0, 1, 2):
        g = fresh(rarities=(rarity, 0, 0))
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        ready = None
        at = {}
        for step in range(1, 800):
            tick(g)
            if step in (1, 60, 120, 300, 599, 600, 601):
                at[str(step)] = r(sw.ult_cd, 4)
            if sw.ult_cd <= 0.0 and ready is None:
                ready = step
        out["recharge_rarity%d" % rarity] = dict(setup=setup_of(g), ult_max=r(sw.ult_max, 4), ready_tick=ready, ult_cd_at=at)
    g = fresh()
    sw = g.swords[0]
    key(g, pygame.K_q, mouse=point)
    tick(g, 120)  # the aim, the flight and the recovery are over, the recharge is not
    before = dict(state=sw.state, ult_cd=r(sw.ult_cd, 4), pos=[r(sw.pos.x), r(sw.pos.y)])
    key(g, pygame.K_q, mouse=(PLAYER[0] - 200.0, PLAYER[1]))
    after = dict(state=sw.state, ult_cd=r(sw.ult_cd, 4), pos=[r(sw.pos.x), r(sw.pos.y)])
    out["rejected_while_recharging"] = dict(setup=setup_of(g, ticks=120), before=before, after=after, refused=before == after)
    g = fresh()
    sw = g.swords[0]
    key(g, pygame.K_q, mouse=point)
    tick(g, 30)
    snap = dict(state=sw.state, phase=sw.phase, ult_cd=r(sw.ult_cd, 4), ult_t=r(sw.ult_t, 4), dir=[r(sw.dir.x, 5), r(sw.dir.y, 5)])
    sw.ult_cd = 0.0  # even with the recharge forced to zero a flying Skewer refuses a second command
    key(g, pygame.K_q, mouse=(PLAYER[0] - 200.0, PLAYER[1]))
    out["rejected_while_active"] = dict(setup=setup_of(g, ticks=30), before=snap,
                                        after=dict(state=sw.state, phase=sw.phase, ult_cd=r(sw.ult_cd, 4), ult_t=r(sw.ult_t, 4), dir=[r(sw.dir.x, 5), r(sw.dir.y, 5)]))
    g = fresh()
    sw = g.swords[0]
    key(g, pygame.K_q, mouse=point)
    tick(g, 10 * 60 + 10)
    key(g, pygame.K_q, mouse=(PLAYER[0] - 300.0, PLAYER[1]))
    out["again_after_recharge"] = dict(setup=setup_of(g, ticks=10 * 60 + 10), state=sw.state, dir=[r(sw.dir.x, 5), r(sw.dir.y, 5)])
    # the other slots keep thrusting while slot 0 skewers
    with NoCrit(False):
        g = fresh(active=(1, 2))
        husk = foe(g, (PLAYER[0] - 300.0, PLAYER[1] + 10.0), hp=100000.0)
        key(g, pygame.K_q, mouse=(PLAYER[0] + 400.0, PLAYER[1]))
        states = []
        for _ in range(80):
            tick(g)
            states.append([s.state for s in g.swords])
        out["others_keep_thrusting"] = dict(setup=setup_of(g, (1, 2), [husk]), states_at_30=states[29], others_thrust=any(st[1] != "idle" or st[2] != "idle" for st in states),
                                            husk_damaged=husk.hp < 100000.0)
    return out


def case_skewer_parry():
    """A Skewer parries every orb its segment touches within 14 px (plus the orb's radius): none during the
    aim, and none behind the tail, off the side or beyond the range. Orbs at `along` px east of the player
    and `lateral` px off the line."""
    out = {}
    cells = []
    for along in (-40.0, 150.0, 400.0, 800.0, 960.0, 1010.0, 1100.0):
        for lat in (0.0, 14.0, 20.0, 24.0, 28.0, 34.0):
            with NoCrit(False):
                g = fresh()
                pr = orb(g, (PLAYER[0] + along, PLAYER[1] + lat))
                key(g, pygame.K_q, mouse=(PLAYER[0] + 400.0, PLAYER[1]))
                parried = None
                for step in range(1, 90):
                    tick(g)
                    if pr.dead and parried is None:
                        parried = step
                cells.append(dict(along=along, lateral=lat, x=r(pr.pos.x), y=r(pr.pos.y), parried_tick=parried))
    out["grid"] = cells
    out["setup"] = setup_of(fresh(), point=[PLAYER[0] + 400.0, PLAYER[1]])
    with NoCrit(False):
        g = fresh()
        pr = orb(g, (PLAYER[0] + 60.0, PLAYER[1]))
        key(g, pygame.K_q, mouse=(PLAYER[0] + 400.0, PLAYER[1]))
        tick(g, 20)
        out["orb_during_aim"] = dict(setup=setup_of(g, orbs=[pr.setup], point=[PLAYER[0] + 400.0, PLAYER[1]], ticks=20), alive=not pr.dead)
    return out


# ------------------------------------------------------------------ conditions ON
CONDITION_FIELDS = ("hp", "burn", "burn_dps", "poison", "poison_dps", "poison_stacks", "chill", "chill_stacks", "frozen", "dot", "x", "y")


def enemy_condition_row(e):
    return dict(hp=r(e.hp, 4), burn=r(e.burn, 4), burn_dps=r(e.burn_dps, 4), poison=r(e.poison, 4), poison_dps=r(e.poison_dps, 4),
                poison_stacks=e.poison_stacks, chill=r(e.chill, 4), chill_stacks=e.chill_stacks, frozen=r(e.frozen, 4),
                dot=r(e.dot, 4), x=r(e.pos.x), y=r(e.pos.y))


def condition_columns(g, es, ticks):
    cols = [{f: [] for f in CONDITION_FIELDS} for _ in es]
    for _ in range(ticks):
        tick(g)
        for col, e in zip(cols, es):
            for f, v in enemy_condition_row(e).items():
                col[f].append(v)
    return cols


def case_conditions():
    """The conditions the blows leave: the thrust one dose on each enemy it pierces, the Skewer two doses
    on each enemy it impales (and its carried enemies keep burning, poisoned or chilling)."""
    out = {"thrust": {}, "skewer": {}}
    for index, element in enumerate(ELEMENTS):
        with NoCrit(False):
            g = fresh(rarities=(index, 0, 0), active=(0,), conditions=True, elements=(element, "ice", "fire"))
            es = [foe(g, (PLAYER[0] + 200.0, PLAYER[1] + 4.0), hp=2000.0), foe(g, (PLAYER[0] + 260.0, PLAYER[1] - 6.0), kind="brute", hp=2000.0),
                  foe(g, (PLAYER[0] + 340.0, PLAYER[1]), kind="runner", hp=2000.0)]
            cols = condition_columns(g, es, 260)
            _CONDITION_CASES.append("thrust_" + element)
            out["thrust"][element] = dict(setup=setup_of(g, (0,), es), conditions=cols, kills=g.kills)
        with NoCrit(False):
            g = fresh(rarities=(index, 0, 0), conditions=True, elements=(element, "ice", "fire"))
            es = [foe(g, (PLAYER[0] + 250.0, PLAYER[1] + 4.0), hp=2000.0), foe(g, (PLAYER[0] + 330.0, PLAYER[1] - 6.0), kind="brute", hp=2000.0),
                  foe(g, (PLAYER[0] + 420.0, PLAYER[1]), kind="runner", hp=2000.0)]
            key(g, pygame.K_q, mouse=(PLAYER[0] + 400.0, PLAYER[1]))
            cols = condition_columns(g, es, 130)
            _CONDITION_CASES.append("skewer_" + element)
            out["skewer"][element] = dict(setup=setup_of(g, (), es, point=[PLAYER[0] + 400.0, PLAYER[1]]), conditions=cols, kills=g.kills)
    return out


# ------------------------------------------------------------------ keys
def case_keys():
    out = {}
    point = (PLAYER[0] + 400.0, PLAYER[1])
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
    # touch: the nearest living enemy, or 300 px ahead; the Skewer's heading comes from it
    g = fresh()
    near_foe = foe(g, (PLAYER[0] + 350.0, PLAYER[1] + 100.0))
    far_foe = foe(g, (PLAYER[0] - 900.0, PLAYER[1]))
    aim = g.auto_aim()
    g.ultimate(0, aim)
    out["auto_aim"] = dict(setup=setup_of(g, (), [near_foe, far_foe]), nearest=[r(aim.x), r(aim.y)], dir=[r(g.swords[0].dir.x, 5), r(g.swords[0].dir.y, 5)])
    g = fresh()
    aim = g.auto_aim()
    g.ultimate(0, aim)
    out["auto_aim_empty"] = dict(setup=setup_of(g), aim=[r(aim.x), r(aim.y)], dir=[r(g.swords[0].dir.x, 5), r(g.swords[0].dir.y, 5)])
    out["setup"] = setup_of(fresh())
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
        table=case_table(), thrust=case_thrust(), acquire=case_acquire(), geometry=case_geometry(), piercing=case_piercing(),
        deaths=case_deaths(), parry=case_parry(), start=case_start(), skewer_single=case_skewer_single(),
        skewer_carry=case_skewer_carry(), skewer_empty=case_skewer_empty(), skewer_walls=case_skewer_walls(),
        skewer_boundary=case_skewer_boundary(), skewer_range=case_skewer_range(), skewer_deaths=case_skewer_deaths(),
        skewer_rules=case_skewer_rules(), skewer_parry=case_skewer_parry(), conditions=case_conditions(), keys=case_keys(),
    )
    cases["fixture_scope"] = assert_fixtures_in_scope()
    text = dumps(cases)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
