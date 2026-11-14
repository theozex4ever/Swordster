#!/usr/bin/env python3
"""Captures focused reference cases for the elemental conditions (fire, poison, ice).

Usage:  python3 -I tools/reference/capture_elemental_conditions.py [out.json]
        (the committed copy is godot/tests/reference/elemental_conditions.json)

Slice #11 of the Godot port. Like the earlier captures (whose loader and helpers it reuses)
it drives the prototype's REAL classes -- `Game`, `Sword`, `Enemy`, `Player` from game/main.py --
with fixed 1/60 s steps under SDL's dummy drivers. Unlike them it LEAVES `Game.afflict` ON: the
burn, poison, chill, freeze, the damage-over-time cadence, the frozen bonus, the frozen contact
immunity and the fire spread are all read off the prototype's own `afflict`, `update_conditions`,
`hit_enemy`, `kill` and `Enemy.update`; nothing here re-implements a rule.

Every case is a SPEC the Godot checks replay on the real `GameRun`: the swords equipped
(rarity, element), the enemies standing in the arena, and a list of EVENTS that happen just
before a given tick (a sword's blow on an enemy through the prototype's own `hit_enemy`, a bare
`afflict`, a Viper Flurry command). The trace records, after the ticks in `watch`, the state of
every enemy (health, every condition timer, stack and accumulator, position, velocity, stun,
clock) and of the run (player health, kills, projectiles). Healing motes are left out: where they
scatter is random in both games, so when one reaches the player cannot be compared. The Godot side compares the
same trace field by field; it does not copy a starting number.

Choices that are random in the prototype (crits, which enemy a flurry dart picks among several,
cosmetic particles) are pinned or avoided, as in the earlier captures: crits are forced off (or on
for the one event that asks), blows are `heavy` (no hitstop, so time stays comparable) unless a
case is about the normal blow, and flurry cases have exactly one eligible enemy.

Mechanics outside this slice stay off, and the capture asserts that: the wave machine, armed
enemies and drops (issue #17), Converge (#16), the other sword types (#13, #14) and the
Cataclysm's fields (#15; the fields' tick would call the same `afflict`, exercised here by
`afflict` events).
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
DT = base.DT
r = base.r
NoCrit = base.NoCrit
SWORD_TYPES = NS["SWORD_TYPES"]
ENEMY_TYPES = NS["ENEMY_TYPES"]
PX, PY = 1300.0, 900.0  # the arena centre, where the prototype's player spawns
PARKED_CD = 99.0        # an auto-attack cooldown that never ends within a case
HEAVY_KNOCK = 0.0       # direct blows push nothing: the cases are about conditions, not knockback

_CREATED = []
_SWORDS = []


def make_game(swords):
    """The prototype's Game with `swords` ([rarity, element] each, all Fang), no waves, no
    automatic attacks and `afflict` ON."""
    g = base.new_game(swords=[])
    del g.afflict  # the shared helper switches conditions off; this slice is about them
    assert g.afflict.__func__ is Game.afflict
    base.hold()
    c = g.player.pos
    g.swords = [Sword("fang", rarity, element, c) for rarity, element in swords]
    for s in g.swords:
        s.cd = PARKED_CD
        _SWORDS.append(s)
    return g


def make_enemy(g, spec):
    kind = spec.get("kind", "husk")
    spec.setdefault("speed_scale", 0.0)  # written into the case so the Godot side needs no default of its own
    if kind == "spitter":
        spec.setdefault("shoot_cooldown", 2.0)
    e = Enemy(kind, V(spec["x"], spec["y"]), 1)
    assert e.armed is None
    e.speed = ENEMY_TYPES[kind]["speed"] * spec["speed_scale"]
    e.t = spec.get("phase", 0.0)
    e.hp = e.maxhp = float(spec.get("hp", 500.0))
    e.vel = V(*spec.get("velocity", (0.0, 0.0)))
    e.stun = spec.get("stun", 0.0)
    e.frozen = spec.get("frozen", 0.0)
    if kind == "spitter":
        e.shoot_cd = spec.get("shoot_cooldown", 2.0)
    g.enemies.append(e)
    _CREATED.append(e)
    return e


def snap_enemy(e):
    return dict(hp=r(e.hp, 4), dead=e.dead, burn=r(e.burn, 4), burn_dps=r(e.burn_dps, 4), poison=r(e.poison, 4),
                poison_dps=r(e.poison_dps, 4), poison_stacks=e.poison_stacks, chill=r(e.chill, 4),
                chill_stacks=e.chill_stacks, frozen=r(e.frozen, 4), dot=r(e.dot, 4), dot_t=r(e.dot_t, 4),
                x=r(e.pos.x), y=r(e.pos.y), vx=r(e.vel.x), vy=r(e.vel.y), stun=r(e.stun, 4), t=r(e.t, 4))


def snap_run(g, enemies):
    return dict(enemies=[snap_enemy(e) for e in enemies], player_hp=r(g.player.hp, 2), kills=g.kills,
                projectiles=len(g.projectiles), hitstop=r(g.hitstop, 4),
                swords=[dict(state=s.state, ult_cd=r(s.ult_cd, 4)) for s in g.swords])


def play(spec):
    """Runs a spec on the prototype and returns its trace. Events at step s happen before tick s;
    the snapshot labelled s is taken after tick s."""
    random.seed(spec.get("seed", 1))
    g = make_game(spec["swords"])
    if "sword_cooldowns" in spec:
        for s, cd in zip(g.swords, spec["sword_cooldowns"]):
            s.cd = cd
    if "player" in spec:
        g.player.pos = V(*spec["player"])
    enemies = [make_enemy(g, e) for e in spec["enemies"]]
    by_step = {}
    for ev in spec.get("events", []):
        by_step.setdefault(ev["step"], []).append(ev)
    watch = set(spec["watch"])
    trace = {}
    dealt = []
    crit_off = spec.get("crit", False)
    for step in range(1, spec["steps"] + 1):
        for ev in by_step.get(step, []):
            e = enemies[ev["enemy"]] if "enemy" in ev else None
            kind = ev["type"]
            if kind == "hit":
                before = e.hp
                with NoCrit(ev.get("crit", False)):
                    g.hit_enemy(e, ev["damage"], V(1, 0), HEAVY_KNOCK, g.swords[ev["sword"]], heavy=ev.get("heavy", True))
                dealt.append(dict(step=step, enemy=ev["enemy"], dealt=r(before - e.hp, 4)))
            elif kind == "afflict":
                g.afflict(e, ev["element"], ev["power"], ev.get("stacks", 1))
            elif kind == "ultimate":
                flurry.key(g, [pygame.K_q, pygame.K_e, pygame.K_r][ev["slot"]], mouse=tuple(ev["point"]))
            else:
                raise AssertionError(kind)
        with NoCrit(crit_off):
            g.update(DT)
        if step in watch:
            trace[str(step)] = snap_run(g, enemies)
    return dict(trace=trace, dealt=dealt)


def case(spec):
    out = dict(spec=spec)
    out.update(play(spec))
    return out


def husk(x=PX + 250.0, y=PY, hp=500.0, **extra):
    return dict(kind="husk", x=x, y=y, hp=hp, **extra)


def hit(step, enemy=0, sword=0, damage=7.0, **extra):
    return dict(type="hit", step=step, enemy=enemy, sword=sword, damage=damage, **extra)


def every(first, last, stride):
    return list(range(first, last + 1, stride))


# ------------------------------------------------------------------ table
def case_table():
    out = dict(burn_time=NS["BURN_TIME"], poison_time=NS["POISON_TIME"], chill_time=NS["CHILL_TIME"],
               freeze_time=NS["FREEZE_TIME"], poison_max=NS["POISON_MAX"], freeze_stacks=NS["FREEZE_STACKS"],
               chill_slow=NS["CHILL_SLOW"], shatter=NS["SHATTER"], brute_freeze_factor=0.6, freeze_velocity_keep=0.2,
               dot_period=0.5, spread_reach=70.0, spread_dps_factor=0.6, spread_time_factor=0.7,
               elements=sorted(NS["ELEMENTS"]))
    # Damage per second of one dose, read off the prototype's own afflict from each rarity's sword.
    g = make_game([[0, "fire"]])
    dps = {}
    for rarity in range(3):
        sword = Sword("fang", rarity, "fire", V(0, 0))
        row = dict(power=r(sword.damage, 4))
        for element in ("fire", "poison"):
            e = Enemy("husk", V(PX + 250, PY), 1)
            g.afflict(e, element, sword.damage, 1)
            row[element] = r(e.burn_dps if element == "fire" else e.poison_dps, 4)
        e = Enemy("husk", V(PX + 250, PY), 1)
        g.afflict(e, "fire", sword.damage, 3)
        row["fire_three_stacks"] = r(e.burn_dps, 4)
        dps[str(rarity)] = row
    out["dps_by_rarity"] = dps
    out["colors"] = {name: list(NS["ELEMENTS"][name]["color"]) for name in NS["ELEMENTS"]}
    return out


# ------------------------------------------------------------------ fire
def case_fire():
    out = {}
    fire_watch = sorted(set(every(1, 200, 15) + [2, 29, 30, 31, 59, 60, 61, 89, 90, 91, 119, 120, 121, 149, 150, 151,
                                                  178, 179, 180, 181, 182, 183, 200]))
    for rarity, label in ((0, "common"), (1, "rare"), (2, "mythic")):
        out["fire_" + label] = case(dict(swords=[[rarity, "fire"]], enemies=[husk()], events=[hit(1)], steps=200, watch=fire_watch))
    # a second application refreshes the timer; the stronger dps stays while it burns, and a burn that
    # ran out starts again at the new sword's dps instead of keeping the stale one
    out["fire_refresh"] = case(dict(
        swords=[[0, "fire"], [2, "fire"]], enemies=[husk()],
        events=[hit(1, sword=0), hit(61, sword=1), hit(100, sword=0), hit(300, sword=0)],
        steps=520, watch=sorted(set(every(1, 520, 20) + [60, 61, 62, 99, 100, 101, 279, 280, 281, 282, 283, 299, 300, 301]))))
    # fire stacks are doses: three stacks in one dose burn three times as hard
    out["fire_dose_stacks"] = case(dict(
        swords=[[0, "fire"]], enemies=[husk()], events=[dict(type="afflict", step=1, enemy=0, element="fire", power=7.0, stacks=3)],
        steps=60, watch=[1, 29, 30, 31, 60]))
    return out


# ------------------------------------------------------------------ poison
def case_poison():
    out = {}
    hits = [hit(1 + 10 * i) for i in range(9)]
    out["poison_stacks"] = case(dict(
        swords=[[0, "poison"]], enemies=[husk()], events=hits, steps=400,
        watch=sorted(set(every(1, 400, 10) + [2, 12, 22, 32, 42, 52, 62, 72, 82, 83, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360]))))
    out["poison_rarity"] = case(dict(
        swords=[[0, "poison"], [2, "poison"]], enemies=[husk()],
        events=[hit(1, sword=0), hit(30, sword=1), hit(60, sword=0), hit(400, sword=0)],
        steps=500, watch=sorted(set(every(1, 500, 25) + [29, 30, 31, 59, 60, 61, 329, 330, 331, 332, 333, 334, 335, 336, 400, 401]))))
    return out


# ------------------------------------------------------------------ ice
def case_ice():
    out = {}
    ice_hits = [hit(1), hit(11), hit(21), hit(31), hit(41), hit(51), hit(140), hit(150), hit(160), hit(170), hit(180)]
    watch = sorted(set(every(1, 400, 10) + [30, 31, 32, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135,
                                            140, 141, 170, 171, 172, 180, 181]))
    out["ice_freeze"] = case(dict(swords=[[0, "ice"]], enemies=[husk()], events=ice_hits, steps=400, watch=watch))
    out["ice_brute"] = case(dict(
        swords=[[0, "ice"]], enemies=[dict(kind="brute", x=PX + 250.0, y=PY, hp=1000.0)],
        events=[hit(1), hit(11), hit(21), hit(31), hit(60)], steps=160,
        watch=sorted(set(every(1, 160, 10) + [30, 31, 32, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102]))))
    out["ice_chill_expiry"] = case(dict(
        swords=[[0, "ice"]], enemies=[husk()], events=[hit(1), hit(11)], steps=200,
        watch=sorted(set(every(1, 200, 10) + [159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170]))))
    # a frozen enemy keeps its chill timer fresh but never gains stacks; two kinds of runner/spitter freeze like a husk
    out["ice_freeze_runner"] = case(dict(
        swords=[[0, "ice"]], enemies=[dict(kind="runner", x=PX + 250.0, y=PY, hp=500.0), dict(kind="spitter", x=PX - 250.0, y=PY, hp=500.0)],
        events=[hit(i, enemy=e) for i in (1, 11, 21, 31) for e in (0, 1)], steps=150, watch=[1, 31, 32, 60, 126, 127, 128, 129, 130]))
    return out


# ----------------------------------------------------------- frozen bonus
def case_frozen_bonus():
    out = {}
    # Each (raw damage, critical) pair strikes its own enemy, frozen or not, in one tick. Halves of the
    # shattered amount (5 x 1.3 = 6.5, 25 x 1.3 = 32.5 ...) fall on even numbers in Python's round().
    raws = [0.2, 2.5, 3.0, 3.5, 5.0, 7.0, 8.4, 9.1, 10.92, 12.25, 14.7, 15.0, 25.0, 35.0, 42.0]
    for label, frozen in (("frozen", 5.0), ("plain", 0.0)):
        enemies = []
        events = []
        for i, raw in enumerate(raws):
            for j, crit in enumerate((False, True)):
                index = len(enemies)
                col, row = index % 6, index // 6
                enemies.append(husk(x=PX - 500.0 + col * 150.0, y=PY - 500.0 + row * 150.0, hp=5000.0, frozen=frozen))
                events.append(hit(1, enemy=index, damage=raw, crit=crit))
        out[label] = case(dict(swords=[[0, "ice"]], enemies=enemies, events=events, steps=2, watch=[1, 2]))
        out[label]["raws"] = raws
    # the blow does not end the freeze; a blow that the bonus makes lethal kills; the ice sword's own hit on a
    # frozen enemy neither refreshes the freeze nor adds stacks
    out["kill_through_bonus"] = case(dict(
        swords=[[0, "ice"]], enemies=[husk(hp=6.0, frozen=5.0), husk(x=PX - 250.0, hp=6.0)], events=[hit(1, enemy=0, damage=5.0), hit(1, enemy=1, damage=5.0)],
        steps=3, watch=[1, 2, 3]))
    out["frozen_stays_frozen"] = case(dict(
        swords=[[0, "ice"]], enemies=[husk(hp=500.0, frozen=1.0)], events=[hit(1), hit(20), hit(40)], steps=70, watch=[1, 20, 21, 40, 41, 59, 60, 61, 62, 70]))
    return out


# ------------------------------------------------------------ frozen contact
def case_frozen_contact():
    out = {}
    # a husk overlapping the player hurts it at once; frozen for a second, it does not, and is not pushed away
    for label, frozen in (("plain", 0.0), ("frozen", 1.0)):
        out[label] = case(dict(
            swords=[[0, "ice"]], enemies=[husk(x=PX + 20.0, y=PY, hp=500.0, frozen=frozen)], steps=140,
            watch=sorted(set(every(1, 140, 10) + [2, 3, 58, 59, 60, 61, 62, 63, 64]))))
    # a frozen brute (barely pushed anyway) and a freshly thawed enemy
    out["frozen_then_thawed"] = case(dict(
        swords=[[0, "ice"]], enemies=[husk(x=PX + 20.0, y=PY, hp=500.0, frozen=0.5)], steps=60, watch=every(1, 60, 3)))
    return out


# ----------------------------------------------------- chill, motion and clocks
def case_motion():
    out = {}
    far = dict(x=PX + 400.0, y=PY, hp=500.0, speed_scale=1.0)
    watch = sorted(set(every(1, 260, 20) + [149, 150, 151, 152]))
    out["chilled_walk"] = case(dict(swords=[[0, "ice"]], enemies=[dict(kind="husk", **far)], events=[hit(1)], steps=260, watch=watch))
    out["plain_walk"] = case(dict(swords=[[0, "ice"]], enemies=[dict(kind="husk", **far)], steps=260, watch=watch))
    # a chilled runner keeps weaving at half speed; a chilled spitter
    out["chilled_runner"] = case(dict(
        swords=[[0, "ice"]], enemies=[dict(kind="runner", x=PX + 400.0, y=PY, hp=500.0, speed_scale=1.0)], events=[hit(1)], steps=200, watch=every(1, 200, 20)))
    # frozen: the enemy stops steering and its own clock stops; it coasts on its velocity as a stunned enemy does
    out["frozen_runner"] = case(dict(
        swords=[[0, "ice"]], enemies=[dict(kind="runner", x=PX + 400.0, y=PY, hp=500.0, speed_scale=1.0, velocity=[-120.0, 30.0], frozen=1.0)],
        steps=140, watch=sorted(set(every(1, 140, 10) + [59, 60, 61, 62]))))
    # a frozen spitter holds its fire: its cooldown and its wind-up wait for the thaw
    spitter = dict(kind="spitter", x=PX + 300.0, y=PY, hp=500.0, speed_scale=1.0, shoot_cooldown=0.1)
    out["spitter_plain"] = case(dict(swords=[[0, "ice"]], enemies=[dict(spitter)], steps=70, watch=every(1, 70, 5)))
    out["spitter_frozen"] = case(dict(swords=[[0, "ice"]], enemies=[dict(spitter, frozen=1.0)], steps=160, watch=sorted(set(every(1, 160, 10) + [59, 60, 61, 62]))))
    return out


# -------------------------------------------------- cadence and mixed conditions
def case_mixed():
    out = {}
    out["fire_poison_ice"] = case(dict(
        swords=[[0, "poison"], [0, "ice"], [1, "fire"]], enemies=[husk()],
        events=[hit(1, sword=0), hit(2, sword=0), hit(3, sword=0), hit(4, sword=2), hit(5, sword=1), hit(6, sword=1), hit(100, sword=0)],
        steps=420, watch=sorted(set(every(1, 420, 6) + [29, 30, 31, 59, 60, 61]))))
    # damage over time never crits, never gets the frozen bonus and never knocks back
    out["dot_on_frozen"] = case(dict(
        swords=[[0, "poison"]], enemies=[husk(frozen=3.0)], events=[hit(1), hit(2), hit(3)], steps=200, watch=every(1, 200, 5)))
    # nothing left to tick: the accumulator drops to zero with the conditions
    out["accumulator_resets"] = case(dict(
        swords=[[0, "poison"]], enemies=[husk()], events=[hit(1)], steps=330, watch=sorted(set([1, 29, 30, 31, 59, 60, 268, 269, 270, 271, 272, 273, 274, 275, 300, 330]))))
    return out


# -------------------------------------------------------- spread and deaths
def ring_at(center, distance, degrees):
    a = math.radians(degrees)
    return center[0] + math.cos(a) * distance, center[1] + math.sin(a) * distance


def case_spread():
    out = {}
    cx, cy = PX + 450.0, PY
    center = (cx, cy)
    ax, ay = ring_at(center, 101.0, 0.0)       # husk edge 101: inside 16 + 16 + 70 = 102
    bx, by = ring_at(center, 103.0, 45.0)      # husk 103: outside
    dxx, dyy = ring_at(center, 115.0, 90.0)    # brute 115: inside 16 + 30 + 70 = 116
    ex, ey = ring_at(center, 117.0, 135.0)     # brute 117: outside
    fx, fy = ring_at(center, 100.0, 180.0)     # burning harder already: keeps its own
    gx, gy = ring_at(center, 100.0, 225.0)     # burning weaker already: raised
    hx, hy = ring_at(center, 100.0, 270.0)     # already dead
    enemies = [
        husk(x=cx, y=cy, hp=500.0),                                  # 0: the burning victim
        husk(x=ax, y=ay, hp=500.0),                                  # 1: inside the reach
        husk(x=bx, y=by, hp=500.0),                                  # 2: outside
        dict(kind="brute", x=dxx, y=dyy, hp=500.0),                  # 3: brute, inside
        dict(kind="brute", x=ex, y=ey, hp=500.0),                    # 4: brute, outside
        husk(x=fx, y=fy, hp=500.0),                                  # 5: burning harder
        husk(x=gx, y=gy, hp=500.0),                                  # 6: burning weaker
        husk(x=hx, y=hy, hp=3.0),                                    # 7: dies first
    ]
    events = [
        dict(type="afflict", step=1, enemy=0, element="fire", power=7.0),
        dict(type="afflict", step=1, enemy=5, element="fire", power=30.0),
        dict(type="afflict", step=1, enemy=6, element="fire", power=1.0),
        hit(1, enemy=7, damage=50.0),
        hit(31, enemy=0, damage=9999.0),
    ]
    out["burning_death"] = case(dict(swords=[[0, "fire"]], enemies=enemies, events=events, steps=330,
                                     watch=sorted(set([1, 2, 30, 31, 32, 33, 60, 90, 91, 92, 93, 120, 121, 150, 180, 181, 182, 183, 184, 185, 186, 200, 220, 240, 300, 330]))))
    # a death that is not burning spreads nothing (poisoned and chilled does not count), and neither does
    # the fire sword's own killing blow: a blow that kills afflicts nothing, so the victim was never burning
    plain = [husk(x=cx, y=cy, hp=500.0), husk(x=ax, y=ay, hp=500.0)]
    out["poison_death_no_spread"] = case(dict(
        swords=[[0, "poison"], [0, "ice"]], enemies=[dict(e) for e in plain],
        events=[hit(1, sword=0), hit(2, sword=1), hit(10, enemy=0, damage=9999.0)], steps=120, watch=[1, 10, 11, 12, 60, 120]))
    out["killing_blow_no_ignite"] = case(dict(
        swords=[[0, "fire"]], enemies=[husk(x=cx, y=cy, hp=5.0), husk(x=ax, y=ay, hp=500.0)],
        events=[hit(1, enemy=0, damage=50.0)], steps=120, watch=[1, 2, 60, 120]))
    # two die on the same tick: a neighbour struck dead just before the burning one is still in the list
    # (corpses leave at the end of the tick) and is not ignited, a living one is
    out["corpse_neighbour"] = case(dict(
        swords=[[0, "fire"]], enemies=[husk(x=cx, y=cy, hp=500.0), husk(x=ax, y=ay, hp=3.0), husk(x=fx, y=fy, hp=500.0)],
        events=[dict(type="afflict", step=1, enemy=0, element="fire", power=7.0), hit(5, enemy=1, damage=50.0), hit(5, enemy=0, damage=9999.0)],
        steps=40, watch=[1, 4, 5, 6, 10, 40]))
    # a blow that leaves the victim alive ignites it, and its later death then spreads
    out["fire_blow_then_death"] = case(dict(
        swords=[[0, "fire"]], enemies=[husk(x=cx, y=cy, hp=500.0), husk(x=ax, y=ay, hp=500.0)],
        events=[hit(1, enemy=0, damage=7.0), hit(5, enemy=0, damage=9999.0)], steps=100, watch=[1, 4, 5, 6, 7, 60, 100]))
    return out


def case_chain():
    out = {}
    # five in a row, 90 px apart (each reaches only its neighbours): the first dies to a blow while burning,
    # the rest burn down in turn at 0.6 x the dps of the one before
    cx, cy = PX + 300.0, PY - 400.0
    hps = [500.0, 3.0, 2.0, 2.0, 1.0, 1.0]
    enemies = [husk(x=cx, y=cy + 90.0 * i, hp=hps[i]) for i in range(len(hps))]
    out["chain"] = case(dict(
        swords=[[0, "fire"]], enemies=enemies,
        events=[dict(type="afflict", step=1, enemy=0, element="fire", power=7.0), hit(2, enemy=0, damage=9999.0)],
        steps=420, watch=sorted(set(every(1, 420, 10) + [2, 3]))))
    return out


def case_deaths():
    out = {}
    # (a 0.4 blow still deals the minimum of 1 damage, so a 2-health enemy is left with 1 and one poison landing kills it)
    dying = [1, 2, 29, 30, 31, 58, 59, 60, 61, 62, 63, 90, 120]
    out["dot_kill"] = case(dict(
        swords=[[0, "poison"]], enemies=[husk(hp=2.0)], events=[hit(1, damage=0.4)], steps=120, watch=dying))
    # two die on the same tick; a blow kills just before the damage over time would have landed
    out["two_dot_kills"] = case(dict(
        swords=[[0, "poison"]], enemies=[husk(hp=2.0), husk(x=PX - 250.0, hp=2.0)], events=[hit(1, enemy=0, damage=0.4), hit(1, enemy=1, damage=0.4)], steps=120,
        watch=dying))
    out["hit_before_dot"] = case(dict(
        swords=[[0, "poison"]], enemies=[husk(hp=100.0)], events=[hit(1, damage=0.4), hit(60, damage=200.0)], steps=120,
        watch=dying))
    # poison finishes a frozen enemy, and a frozen enemy killed by a blow is killed once
    out["poison_kills_frozen"] = case(dict(
        swords=[[0, "poison"]], enemies=[husk(hp=2.0, frozen=3.0)], events=[hit(1, damage=0.4)], steps=120, watch=dying))
    # a burning enemy killed by poison still spreads its fire
    out["burning_poison_death"] = case(dict(
        swords=[[0, "poison"], [0, "fire"]], enemies=[husk(x=PX + 450.0, hp=4.0), husk(x=PX + 540.0, hp=500.0)],
        events=[hit(1, enemy=0, sword=1, damage=0.4), hit(1, enemy=0, sword=0, damage=0.4)], steps=150,
        watch=sorted(set(dying + every(1, 150, 5)))))
    return out


# ----------------------------------------------------------- swords end to end
def case_sword_hits():
    out = {}
    swords = [[0, "poison"], [0, "ice"], [0, "fire"]]
    for idx, label in enumerate(("poison", "ice", "fire")):
        cooldowns = [PARKED_CD] * 3
        cooldowns[idx] = 0.0
        spec = dict(swords=swords, sword_cooldowns=cooldowns, enemies=[husk(x=PX + 100.0, y=PY, hp=500.0)], steps=1, watch=[1])
        # find the first tick the sword lands its blow, then watch a window around it
        random.seed(1)
        g = make_game(swords)
        for s, cd in zip(g.swords, cooldowns):
            s.cd = cd
        e = make_enemy(g, spec["enemies"][0])
        first = None
        with NoCrit(False):
            for step in range(1, 80):
                g.update(DT)
                if e.hp < 500.0 and first is None:
                    first = step
                    break
        spec["steps"] = first + 2
        spec["watch"] = list(range(1, first + 3))
        out[label] = case(spec)
        out[label]["first_hit"] = first
    return out


def case_flurry():
    out = {}
    swords = [[0, "poison"], [0, "ice"], [0, "fire"]]
    target = [PX + 260.0, PY + 40.0]
    for slot, label in enumerate(("poison", "ice", "fire")):
        out[label] = case(dict(
            swords=swords, enemies=[husk(x=target[0] + 30.0, y=target[1] - 20.0, hp=5000.0)],
            events=[dict(type="ultimate", step=1, slot=slot, point=target)], steps=130, watch=every(1, 130, 3)))
    return out


# ---------------------------------------------------------------- survival
def case_survival():
    """Three Fangs vs the first wave (husks only, nothing armed), player stationary, conditions ON."""
    results = []
    for seed in range(1, 9):
        random.seed(seed)
        g = base.new_game(swords=[("fang", "poison"), ("fang", "ice"), ("fang", "fire")])
        del g.afflict
        base.disarm_waves(g)
        g.in_wave = False
        g.break_t = 1.6
        base.hold()
        t_real = 0.0
        cleared_at = None
        husks_seen = set()
        for _ in range(round(60.0 / DT)):
            g.update(DT)
            t_real += DT
            base.assert_all_unarmed(g, 30.0)
            husks_seen.update(id(e) for e in g.enemies)
            if g.wave >= 1 and not g.in_wave and g.banner and g.banner[0] == "WAVE CLEARED" and cleared_at is None:
                cleared_at = t_real
                break
            if g.player.dead:
                break
        results.append(dict(seed=seed, cleared_at=None if cleared_at is None else r(cleared_at, 2), died=g.player.dead,
                            hp=r(g.player.hp, 1), kills=g.kills, husks_spawned=len(husks_seen), armed_enemies=0))
    return dict(wave1_three_fangs_stationary_player=results)


def assert_scope():
    for e in _CREATED:
        assert e.armed is None
    for sw in _SWORDS:
        assert sw.kind == "fang"
    return dict(enemies_created=len(_CREATED), armed_enemies=0, kinds=sorted({e.kind for e in _CREATED}),
                afflict_enabled=True, swords_used=sorted({sw.kind for sw in _SWORDS}), converge_used=False,
                waves_enabled=False, auto_attack_parked_except="sword_hits")


def dump(value, depth=0):
    """JSON with the outer levels spread over lines (one line per case field and per traced tick) and
    the leaves compact, so the committed file stays reviewable and small."""
    if depth >= 4 or not isinstance(value, (dict, list)) or not value:
        return json.dumps(value, separators=(",", ":"))
    pad = " " * (depth + 1)
    if isinstance(value, dict):
        items = [pad + json.dumps(k) + ": " + dump(v, depth + 1) for k, v in value.items()]
        return "{\n" + ",\n".join(items) + "\n" + " " * depth + "}"
    items = [pad + dump(v, depth + 1) for v in value]
    return "[\n" + ",\n".join(items) + "\n" + " " * depth + "]"


def main():
    cases = dict(
        table=case_table(), fire=case_fire(), poison=case_poison(), ice=case_ice(), frozen_bonus=case_frozen_bonus(),
        frozen_contact=case_frozen_contact(), motion=case_motion(), mixed=case_mixed(), spread=case_spread(), chain=case_chain(),
        deaths=case_deaths(), sword_hits=case_sword_hits(), flurry=case_flurry(), survival=case_survival(),
    )
    cases["fixture_scope"] = assert_scope()
    text = dump(cases)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
