#!/usr/bin/env python3
"""Captures focused reference cases for Colossus (the crushing slam), Cataclysm (its ultimate) and the
elemental ground fields Cataclysm leaves.

Usage:  python3 -I tools/reference/capture_colossus_cataclysm.py [out.json]
        (the committed copy is godot/tests/reference/colossus_cataclysm.json)

Slice #15 of the Godot port. Like the earlier captures (whose loader and helpers it reuses) it drives
the prototype's REAL classes -- `Game`, `Sword`, `Enemy`, `Player`, `Projectile`, `Field` from
game/main.py -- with fixed 1/60 s steps under SDL's dummy drivers. Colossus's internal sword type is
`"colossus"` (`SWORD_TYPES["colossus"]`; its ultimate is "Cataclysm"). Nothing here re-implements a
rule: the cluster targeting, the windup, the fall and its timing come from `Sword.acquire/begin/update/
strike`, the rise and fall of the ultimate from `Sword.ultimate`/`Sword.update_ult`, the area damage,
falloff, knockback, hitstop and projectile clearing from `Game.slam`, the heavy blow's rounding, crits
and conditions from `Game.hit_enemy`/`Game.afflict`, the field's life and dose cadence from
`Game.update_fields`, and the Q/E/R keys from the real `Game.handle`.

Every case writes its fixture (`setup`) into the JSON and the Godot checks build their scenarios from
it: the swords (type, rarity, element, starting cooldown), the enemies (kind, position, health,
walking or pinned), the orbs, the player, whether elemental conditions are ON and a short `script` of
timed commands (start an attack with `Sword.begin`, press a key at a world point, kill an enemy, hurt
the player). The physical cases run with `Game.afflict` switched off (`setup.conditions == false`, as
in the earlier slices); the cases whose subject is the conditions (fields, the slam's doses, deaths by
condition) leave the prototype's own `afflict` ON. The capture asserts which is which.

Mechanics outside this slice are off, and the capture asserts that: every enemy is an unarmed husk,
runner or brute (arming and drops are issue #17), only Colossus swords are equipped (the default
loadout is issue #16), Converge is never commanded (#16) and the wave machine is off (#18). Per-case
controls: the auto-attack cooldown of a sword that is not meant to fight is parked at 99 s, and crits
are forced off (or on, where a case asks) by pinning `random.random`.

Randomness: a slam hits an enemy standing EXACTLY on the impact point in a random direction (the
prototype's `norm` of a zero vector), which no port can reproduce. The capture finds those enemies
(`random_heading`: enemy index -> the tick of the slam) and the Godot checks compare nothing but health,
stun and death for them from that tick on; every other quantity is compared on every tick.
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
KIND = "colossus"
PLAYER = (1300.0, 900.0)  # the arena centre, where the prototype's player spawns
PARKED_CD = 99.0          # an auto-attack cooldown that never ends within a case
ELEMENTS = ("poison", "ice", "fire")
KEYS = {"q": pygame.K_q, "e": pygame.K_e, "r": pygame.K_r}
AOE = SWORD_TYPES[KIND]["aoe"]
ULT_AOE = AOE * SWORD_TYPES[KIND]["ult"]["aoe"]

_CREATED = []
_SWORDS = []
_CONDITION_CASES = []
_USED_KEYS = set()


def state_name(sw):
    return "ult_" + sw.phase if sw.state == "ult" else sw.state


# ------------------------------------------------------------------ fixtures
def fresh(seed=1, rarities=(0, 0, 0), active=(), conditions=False, count=3, elements=ELEMENTS, player=None, cds=None):
    """A game with `count` Colossus swords (Q, E, R); those in `active` may attack at once, the rest are
    parked (or take the cooldown in `cds`). No waves. `afflict` is the prototype's own only when
    `conditions` is set; either way it is wrapped to log every dose (who, which element, from what)."""
    random.seed(seed)
    g = base.new_game(swords=[])
    if conditions:
        del g.afflict  # the shared helper switches conditions off
        assert g.afflict.__func__ is Game.afflict
    base.hold()
    assert (g.player.pos.x, g.player.pos.y) == PLAYER
    if player is not None:
        g.player.pos = V(player)
    c = g.player.pos
    g.swords = [Sword(KIND, rarities[i], elements[i], c) for i in range(count)]
    for i, s in enumerate(g.swords):
        s.cd = (cds[i] if cds is not None else 0.0) if i in active else PARKED_CD
        _SWORDS.append(s)
    g.setup_conditions = conditions
    g.setup_player = None if player is None else [r(player[0]), r(player[1])]
    g.watch = set(active)
    g.n = 0
    g.es = []
    g.doses = []
    g.slams = []
    g.presses = []
    g.in_fields = False
    inner = g.afflict

    def logged(e, element, power, stacks=1):
        g.doses.append(dict(tick=g.n, src="field" if g.in_fields else "blow", enemy=g.es.index(e), element=element, power=r(power, 4), stacks=stacks))
        return inner(e, element, power, stacks)

    g.afflict = logged
    update_fields = g.update_fields

    def logged_fields(dt):
        g.in_fields = True
        try:
            update_fields(dt)
        finally:
            g.in_fields = False

    g.update_fields = logged_fields
    slam = g.slam

    def logged_slam(sword, point, aoe=None, power=1.0, stacks=1):
        radius = aoe or sword.t["aoe"] * sword.scale
        area = []
        for e in g.enemies:
            dist = (e.pos - point).length()
            if dist < radius + e.r:
                area.append(dict(enemy=g.es.index(e), dist=r(dist, 4), dead_before=bool(e.dead), centered=bool((e.pos - point).length_squared() < 1e-6)))
        g.slams.append(dict(tick=g.n, sword=g.swords.index(sword), x=r(point.x), y=r(point.y), radius=r(radius, 4), power=power, stacks=stacks, area=area))
        return slam(sword, point, aoe, power, stacks)

    g.slam = logged_slam
    return g


def foe(g, at, hp=900.0, kind="husk", vel=(0.0, 0.0), stun=0.0, walk=False):
    """An unarmed enemy from the prototype's constructor, pinned (or walking at its type's base speed)."""
    e = Enemy(kind, V(at), 1)
    assert e.armed is None
    e.speed = float(ENEMY_TYPES[kind]["speed"]) if walk else 0.0
    e.t = 0.0
    e.hp = e.maxhp = float(hp)
    e.vel = V(vel)
    e.stun = stun
    e.setup = dict(kind=kind, x=r(e.pos.x), y=r(e.pos.y), hp=r(e.hp), speed_scale=1.0 if walk else 0.0, vx=r(vel[0]), vy=r(vel[1]), stun=r(stun))
    g.enemies.append(e)
    g.es.append(e)
    _CREATED.append(e)
    return e


def orb(g, at, life=10.0):
    pr = Projectile(V(at), V(0, 0))
    pr.life = life
    pr.setup = dict(x=r(pr.pos.x), y=r(pr.pos.y), vx=0.0, vy=0.0, life=life)
    g.projectiles.append(pr)
    g.orbs = getattr(g, "orbs", []) + [pr]
    return pr


def setup_of(g, active=(), cds=None, crit=False, script=(), **extra):
    """The fixture, as the Godot side must rebuild it."""
    out = dict(conditions=g.setup_conditions, crit=crit,
               swords=[dict(type=KIND, rarity=s.rarity, element=s.element,
                            cd=(cds[i] if cds is not None else 0.0) if i in active else PARKED_CD) for i, s in enumerate(g.swords)],
               enemies=[e.setup for e in g.es], orbs=[o.setup for o in getattr(g, "orbs", [])], script=list(script))
    if g.setup_player is not None:
        out["player"] = g.setup_player
    out.update(extra)
    return out


# ------------------------------------------------------------------ driving
def key(g, code, mouse=None):
    flurry.key(g, code, mouse=mouse)


def apply_op(g, op):
    kind = op["op"]
    if kind == "begin":
        target = None if op.get("target") is None else g.es[op["target"]]
        g.swords[op["sword"]].begin(target, V(op["aim"]))
    elif kind == "key":
        _USED_KEYS.add(op["key"])
        sw = g.swords["qer".index(op["key"])]
        before = (state_name(sw), r(sw.ult_cd, 4))
        key(g, KEYS[op["key"]], mouse=op["point"])
        g.presses.append(dict(tick=g.n, key=op["key"], before=before[0], ult_cd_before=before[1], after=state_name(sw), started=bool(sw.state == "ult" and before[0] != state_name(sw))))
    elif kind == "kill":
        g.kill(g.es[op["enemy"]], V(0, -1), False)
    elif kind == "hurt":
        g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    elif kind == "pause":
        g.paused = True
    elif kind == "resume":
        g.paused = False
    else:
        raise AssertionError(kind)


COND_FIELDS = ("burn", "burn_dps", "poison", "poison_dps", "poison_stacks", "chill", "chill_stacks", "frozen", "dot")


class Trace:
    """Per-tick record (after each tick) of the swords, every enemy, the orbs, the fields and the run's
    shared counters, as dict-of-lists."""

    def __init__(self, g, conditions):
        self.g = g
        self.conditions = conditions
        self.n = 0
        self.run = dict(hitstop=[], trauma=[], kick_x=[], kick_y=[], kills=[], combo=[], motes=[], player_x=[], player_y=[], player_hp=[], fields=[],
                        slam_n=[], slam_radius=[], pulses=[], cond_doses=[])
        self.field = [dict(life=[], tick=[]) for _ in range(3)]
        self.watch = sorted(g.watch)
        self.swords = [dict(state=[], x=[], y=[], ang=[], vx=[], vy=[], z=[], vz=[], ult_t=[], ult_cd=[], cd=[], ix=[], iy=[]) if i in g.watch else None for i in range(len(g.swords))]
        self.enemies = [dict(x=[], y=[], hp=[], vx=[], vy=[], stun=[], flash=[], dead=[], **({f: [] for f in COND_FIELDS} if conditions else {})) for _ in g.es]
        self.orbs = [[] for _ in getattr(g, "orbs", [])]
        self.transitions = [[] for _ in g.swords]
        self._state = [state_name(s) for s in g.swords]

    def step(self):
        g = self.g
        self.n += 1
        run = self.run
        run["hitstop"].append(r(g.hitstop, 4))
        run["trauma"].append(r(g.trauma, 4))
        run["kick_x"].append(r(g.kick.x, 3))
        run["kick_y"].append(r(g.kick.y, 3))
        run["kills"].append(g.kills)
        run["combo"].append(g.combo)
        run["motes"].append(len(g.motes))
        run["player_x"].append(r(g.player.pos.x))
        run["player_y"].append(r(g.player.pos.y))
        run["player_hp"].append(r(g.player.hp, 3))
        run["fields"].append(len(g.fields))
        slams = [s for s in g.slams if s["tick"] == self.n]
        run["slam_n"].append(sum(len(s["area"]) for s in slams) if slams else -1)
        run["slam_radius"].append(r(slams[-1]["radius"], 4) if slams else 0.0)
        doses = [d for d in g.doses if d["tick"] == self.n and d["src"] == "field"]
        run["pulses"].append(len(doses))
        run["cond_doses"].append(sum(1 for d in g.doses if d["tick"] == self.n and d["src"] == "blow"))
        for i in range(3):
            f = g.fields[i] if i < len(g.fields) else None
            self.field[i]["life"].append(r(f.life, 4) if f else -1.0)
            self.field[i]["tick"].append(r(f.tick, 4) if f else -1.0)
        for sw, col, i in zip(g.swords, self.swords, range(len(g.swords))):
            if col is None:
                continue
            col["state"].append(state_name(sw))
            col["x"].append(r(sw.pos.x))
            col["y"].append(r(sw.pos.y))
            col["ang"].append(r(sw.ang, 4))
            col["vx"].append(r(sw.vel.x))
            col["vy"].append(r(sw.vel.y))
            col["z"].append(r(sw.z, 4))
            col["vz"].append(r(sw.vz, 4))
            col["ult_t"].append(r(sw.ult_t, 4))
            col["ult_cd"].append(r(sw.ult_cd, 4))
            col["cd"].append(r(sw.cd, 4))
            impact = getattr(sw, "impact", V(0, 0))
            col["ix"].append(r(impact.x))
            col["iy"].append(r(impact.y))
            if state_name(sw) != self._state[i]:
                self.transitions[i].append(dict(tick=self.n, to=state_name(sw)))
                self._state[i] = state_name(sw)
        for e, col in zip(g.es, self.enemies):
            col["x"].append(r(e.pos.x))
            col["y"].append(r(e.pos.y))
            col["hp"].append(r(e.hp, 4))
            col["vx"].append(r(e.vel.x))
            col["vy"].append(r(e.vel.y))
            col["stun"].append(r(e.stun, 4))
            col["flash"].append(r(e.flash, 4))
            col["dead"].append(1 if e.dead else 0)
            if self.conditions:
                for f in COND_FIELDS:
                    col[f].append(r(getattr(e, f), 4))
        for pr, col in zip(getattr(g, "orbs", []), self.orbs):
            col.append(1 if pr.dead else 0)

    def out(self):
        return dict(ticks=self.n, watch=self.watch, run=self.run, fields=self.field, swords=self.swords, enemies=self.enemies, orbs=self.orbs,
                    transitions=self.transitions)


def play(g, ticks, script=(), crit=False, record=True):
    """Plays `ticks` fixed ticks, executing each scripted op after `op["t"]` completed ticks, recording a trace (unless `record` is off:
    the case then keeps only its slams, doses and key presses)."""
    for op in script:
        g.watch.add(op["sword"] if op["op"] == "begin" else "qer".index(op["key"]) if op["op"] == "key" else 0) if op["op"] in ("begin", "key") else None
    tr = Trace(g, g.setup_conditions)
    g.ticks_played = ticks
    pending = sorted(script, key=lambda o: o["t"])
    with NoCrit(crit):
        for n in range(ticks + 1):
            while pending and pending[0]["t"] == n:
                apply_op(g, pending.pop(0))
            if n == ticks:
                break
            g.n += 1
            g.update(DT)
            if record:
                tr.step()
    assert not pending
    return tr


def random_heading(g):
    """Enemies that stood exactly on an impact point (hit in a random direction): index -> tick."""
    out = {}
    for s in g.slams:
        for a in s["area"]:
            if a["centered"] and not a["dead_before"] and str(a["enemy"]) not in out:
                out[str(a["enemy"])] = s["tick"]
    return out


def case_of(g, tr, active=(), cds=None, crit=False, script=(), keep=(), **extra):
    """One finished case: its fixture, the trace, what the slams and doses did, and the random-heading enemies."""
    out = dict(ticks=g.ticks_played, setup=setup_of(g, active, cds, crit, script, **extra), trace=tr.out() if tr.n else None, slams=g.slams, doses=g.doses, presses=g.presses, random_heading=random_heading(g),
               kills=g.kills, combo=g.combo, motes=len(g.motes), left=len(g.enemies), player_hp=r(g.player.hp, 3))
    if g.setup_conditions:
        _CONDITION_CASES.append(keep)
    return out


def run_case(ticks, enemies=(), orbs=(), active=(0,), script=(), crit=False, rarity=0, rarities=None, conditions=False, elements=ELEMENTS, count=3,
             player=None, cds=None, name=None, record=True, **extra):
    """A fixture of Colossus swords against `enemies` -- (dx, dy, kind, hp[, walk]) relative to the player -- and `orbs`
    ((dx, dy)), played for `ticks` ticks."""
    g = fresh(rarities=rarities or (rarity, 0, 0), active=active, conditions=conditions, elements=elements, count=count, player=player, cds=cds)
    c = g.player.pos
    for spec in enemies:
        dx, dy, kind, hp = spec[:4]
        walk = len(spec) > 4 and spec[4]
        foe(g, (c.x + dx, c.y + dy), kind=kind, hp=hp, walk=walk)
    for dx, dy in orbs:
        orb(g, (c.x + dx, c.y + dy))
    tr = play(g, ticks, script, crit, record)
    return case_of(g, tr, active, cds, crit, script, keep=name or "?", **extra)


def begin_op(t, sword, aim, target=None):
    return dict(t=t, op="begin", sword=sword, aim=[float(aim[0]), float(aim[1])], target=target)


def key_op(t, k, point):
    return dict(t=t, op="key", key=k, point=[float(point[0]), float(point[1])])


def transitions_of(case, sword, to):
    return [t["tick"] for t in case["trace"]["transitions"][sword] if t["to"] == to]


# ------------------------------------------------------------------ table
def case_table():
    t = SWORD_TYPES[KIND]
    u = t["ult"]
    out = dict(kind=KIND, name=t["name"], blurb=t["blurb"], length=t["length"], width=t["width"], range=t["range"], cooldown=t["cooldown"],
               damage=t["damage"], knock=t["knock"], windup=t["windup"], hitstop=t["hitstop"], shake=t["shake"], aoe=t["aoe"],
               ult_name=u["name"], ult_cd=u["cd"], ult_range=u["range"], ult_aoe=u["aoe"], ult_shot=u["shot"], keys="QER", converge_cd=NS["CONVERGE_CD"])
    out["rarities"] = []
    for i in range(3):
        s = Sword(KIND, i, "fire", V(0, 0))
        out["rarities"].append(dict(damage=r(s.damage, 4), cooldown=r(s.cooldown, 4), range=r(s.range, 4), length=r(s.L, 4), scale=r(s.scale, 4),
                                    ult_max=r(s.ult_max, 4), slam_radius=r(s.t["aoe"] * s.scale, 4), ult_aoe=r(s.ult_aoe, 4)))
    # constants read off the code (Sword.__init__ / update / strike / ultimate / update_ult, Game.slam, Game.update_fields)
    out["inline"] = dict(
        start_altitude=30.0, rest_base=34.0, rest_length=0.15, rest_bob_rate=2.2, rest_bob_slot=2.1, rest_bob=7.0, rest_rate=5.0, sink_rate=120.0,
        windup_spring=[120.0, 18.0], windup_altitude=200.0, windup_rate=7.0, windup_tremble_rate=30.0, windup_tremble=0.03, windup_turn=10.0,
        glide_rate=30.0, strike_fall_speed=300.0, strike_gravity=9000.0, falloff=0.45, empty_hitstop=0.04, empty_shake=0.35,
        stuck_time=0.32, stuck_tremble_rate=60.0, stuck_tremble=0.08, recover_time=0.4, recover_velocity=[0.0, -60.0],
        rise_time=0.75, rise_altitude=420.0, rise_rate=5.0, ult_tremble_rate=40.0, ult_tremble=0.04, ult_fall_speed=600.0, ult_gravity=12000.0,
        ult_damage=2.2, ult_stacks=3, ult_shake=0.4, ult_stuck_time=0.6, field_radius_factor=1.1, field_life=5.0, field_period=0.5,
        heavy_flash=0.2, normal_flash=0.11)
    out["knock_mult"] = {k: ENEMY_TYPES[k]["knock"] for k in ("husk", "runner", "brute")}
    out["radius"] = {k: ENEMY_TYPES[k]["r"] for k in ("husk", "runner", "brute")}
    out["world"] = [WORLD.left, WORLD.top, WORLD.right, WORLD.bottom]
    return out


# ------------------------------------------------------------------ the automatic slam
def case_slam():
    """One Colossus against two walking husks: acquire, windup, the fall, the slam's area damage, falloff, knockback,
    hitstop and shake, the stuck pause, recovery, the cooldown and a second slam, for each rarity and a crit."""
    out = {}
    foes = [(250.0, 40.0, "husk", 900.0, True), (310.0, 70.0, "husk", 900.0, True)]
    for label, rarity, crit in (("common", 0, False), ("common_crit", 0, True), ("rare", 1, False), ("mythic", 2, False)):
        out[label] = run_case(260 if label == "common" else 110, enemies=foes, rarity=rarity, crit=crit, name="slam_" + label)
    return out


def case_acquire():
    """Who a Colossus targets: of the enemies within range + radius of the player, the one with the most enemies
    (itself included) within 118 px of it, the nearer one on equal counts, the first in the run's order on a tie."""
    out = {}
    rng = SWORD_TYPES[KIND]["range"]
    husk_r = ENEMY_TYPES["husk"]["r"]
    for label, distance in (("just_inside", rng + husk_r - 1.0), ("just_outside", rng + husk_r + 1.0), ("close", 90.0)):
        g = fresh(active=(0,))
        e = foe(g, (PLAYER[0] + distance, PLAYER[1]))
        tr = play(g, 60)
        left = next((i + 1 for i, s in enumerate(tr.swords[0]["state"]) if s != "idle"), None)
        out[label] = dict(setup=setup_of(g, (0,), None), distance=r(distance), left_idle=left)
    layouts = {
        "cluster_beats_nearest": [(120.0, 0.0, "husk"), (280.0, 10.0, "husk"), (310.0, 40.0, "husk"), (250.0, -30.0, "husk")],
        "nearest_of_the_cluster": [(300.0, 0.0, "husk"), (270.0, 20.0, "husk"), (330.0, -10.0, "husk")],
        "lone_nearest": [(200.0, 0.0, "husk"), (-300.0, 0.0, "husk")],
        "tie_goes_to_the_first": [(250.0, 0.0, "husk"), (-250.0, 0.0, "husk")],
        "tie_goes_to_the_first_swapped": [(-250.0, 0.0, "husk"), (250.0, 0.0, "husk")],
        "neighbours_out_of_range_count": [(150.0, 0.0, "husk"), (320.0, 0.0, "husk"), (420.0, 20.0, "husk"), (430.0, -30.0, "husk")],
        "neighbours_behind_count": [(-200.0, 0.0, "husk"), (-150.0, 60.0, "husk"), (-260.0, -50.0, "husk"), (200.0, 0.0, "husk")],
        "edge_of_the_cluster_117": [(180.0, 0.0, "husk"), (180.0, 117.0, "husk"), (-250.0, 0.0, "husk"), (-250.0, -100.0, "husk")],
        "edge_of_the_cluster_118": [(180.0, 0.0, "husk"), (180.0, 118.0, "husk"), (-250.0, 0.0, "husk"), (-250.0, -100.0, "husk")],
        "brute_and_runner": [(300.0, 0.0, "brute"), (340.0, 30.0, "runner"), (-100.0, 0.0, "husk"), (-130.0, 20.0, "husk")],
        "far_but_out_of_range": [(100.0, 0.0, "husk"), (400.0, 0.0, "husk"), (420.0, 20.0, "husk"), (410.0, -20.0, "husk")],
    }
    for label, placed in layouts.items():
        g = fresh(active=(0,))
        es = [foe(g, (PLAYER[0] + dx, PLAYER[1] + dy), kind=k) for dx, dy, k in placed]
        play(g, 1)
        sw = g.swords[0]
        out["target_" + label] = dict(setup=setup_of(g, (0,), None), target_index=es.index(sw.target) if sw.target in es else None)
    # the radius `acquire` counts neighbours with is the type's, not the rarity's: a Mythic's slam is wider, its count is not
    g = fresh(active=(0,), rarities=(2, 0, 0))
    es = [foe(g, (PLAYER[0] + 150.0, PLAYER[1])), foe(g, (PLAYER[0] + 150.0, PLAYER[1] + 130.0)), foe(g, (PLAYER[0] - 250.0, PLAYER[1])), foe(g, (PLAYER[0] - 250.0, PLAYER[1] - 100.0))]
    play(g, 1)
    out["target_mythic_counts_the_plain_radius"] = dict(setup=setup_of(g, (0,), None), target_index=es.index(g.swords[0].target) if g.swords[0].target in es else None)
    return out


def case_timing():
    """The same slam started at different moments of the sword's idle bob: the fall's length depends on the altitude
    the windup began from, so the strike and impact ticks differ by a tick or two between them."""
    out = {}
    cases = []
    cds = (0.0, 0.07, 0.15, 0.23, 0.31, 0.4, 0.5, 0.6)
    for i, cd in enumerate(cds):
        cases.append(run_case(100, enemies=[(260.0, 20.0, "husk", 900.0)], cds=[cd, 0.0, 0.0], name="timing_%d" % i))
    out["runs"] = cases
    out["cds"] = list(cds)
    out["impact_ticks"] = [transitions_of(c, 0, "stuck")[0] for c in cases]
    out["strike_ticks"] = [transitions_of(c, 0, "strike")[0] for c in cases]
    return out


def case_geometry():
    """What a slam reaches and for how much: a probe husk or brute stands `dist` px east of the impact (a slam started with
    `Sword.begin(None, point)`); it is struck when it is within aoe + its radius, for `damage x (1 - 0.45 x dist / aoe)`
    with that much knockback. Common and Mythic (a wider slam)."""
    out = {}
    target = (PLAYER[0] + 200.0, PLAYER[1] - 60.0)
    dists = [0.5, 30.0, 60.0, 90.0, 117.0, 118.0, 119.0, 133.0, 134.0, 135.0, 147.0, 148.0, 149.0, 160.0]
    for rarity in (0, 2):
        for kind in ("husk", "brute"):
            cells = []
            for d in dists:
                g = fresh(active=(), rarities=(rarity, 0, 0))
                probe = foe(g, (target[0] + d, target[1]), kind=kind)
                tr = play(g, 60, [begin_op(0, 0, target)])
                slam_tick = transitions_of(dict(trace=tr.out()), 0, "stuck")[0]
                after = lambda col: col[slam_tick - 1]
                cells.append(dict(dist=d, hit=probe.hp < probe.maxhp, dealt=r(probe.maxhp - probe.hp, 4), slam_tick=slam_tick,
                                  vx=after(tr.enemies[0]["vx"]), vy=after(tr.enemies[0]["vy"]), stun=after(tr.enemies[0]["stun"]),
                                  flash=after(tr.enemies[0]["flash"]), x=after(tr.enemies[0]["x"]), y=after(tr.enemies[0]["y"]),
                                  hitstop=after(tr.run["hitstop"]), trauma=after(tr.run["trauma"]), kick_y=after(tr.run["kick_y"])))
            out["probe_%s_r%d" % (kind, rarity)] = cells
    g = fresh(active=())
    foe(g, target)
    out["setup"] = dict(conditions=False, swords=setup_of(g)["swords"], target=[target[0], target[1]], dists=dists)
    return out


def case_empty_slam():
    """A slam with nothing in its area: the short hitstop (0.04) and shake (0.35) instead of the sword's own; and the
    same slam with only a corpse inside (killed earlier in the tick by another Colossus), which counts as something hit."""
    out = {}
    target = (PLAYER[0] + 200.0, PLAYER[1] - 60.0)
    g = fresh(active=())
    foe(g, (target[0] + 400.0, target[1]))
    tr = play(g, 60, [begin_op(0, 0, target)])
    out["empty"] = case_of(g, tr, (), None, False, [begin_op(0, 0, target)])
    g = fresh(active=())
    foe(g, (target[0] + 60.0, target[1]), hp=30.0)
    tr = play(g, 60, [begin_op(0, 0, target)])
    out["one_kill"] = case_of(g, tr, (), None, False, [begin_op(0, 0, target)])
    # two Colossi slam on the same tick, 100 px apart: the first one's kills are corpses when the second one's slam looks
    # around, so the second still "hits" (the sword's hitstop and shake) though nothing lives in its area
    a = (PLAYER[0] + 200.0, PLAYER[1] - 200.0)
    b = (a[0] + 100.0, a[1] + 100.0)
    for label, victims in (("two_slams_corpse", [(a[0] + 50.0, a[1] + 45.0, 30.0), (a[0] + 45.0, a[1] + 55.0, 30.0)]),
                           ("two_slams_corpse_far", [(a[0] - 60.0, a[1] - 50.0, 30.0), (a[0] - 70.0, a[1] - 30.0, 30.0)])):
        g = fresh(active=())
        for vx, vy, hp in victims:
            foe(g, (vx, vy), hp=hp)
        script = [begin_op(0, 0, a), begin_op(0, 1, b)]
        tr = play(g, 60, script)
        out[label] = case_of(g, tr, (), None, False, script)
    return out


def case_orbs():
    """Orbs a slam clears: every orb whose centre is within the slam's radius of the impact (no padding for the orb's own
    radius), sparks and parry feedback none; a Cataclysm's area is wider."""
    out = {}
    target = (PLAYER[0] + 250.0, PLAYER[1] - 100.0)
    cells = []
    for rarity in (0, 2):
        for d in (0.0, 60.0, 117.0, 118.0, 119.0, 139.0, 140.0, 150.0, 212.0, 213.0):
            for side in ("east", "north"):
                g = fresh(active=(), rarities=(rarity, 0, 0))
                at = (target[0] + d, target[1]) if side == "east" else (target[0], target[1] - d)
                pr = orb(g, at)
                foe(g, (target[0] + 400.0, target[1]))
                tr = play(g, 60, [begin_op(0, 0, target)])
                stuck = transitions_of(dict(trace=tr.out()), 0, "stuck")[0]
                cells.append(dict(rarity=rarity, dist=d, side=side, x=r(at[0]), y=r(at[1]), cleared=bool(pr.dead), hitstop=tr.run["hitstop"][stuck - 1]))
    out["grid"] = cells
    # a Cataclysm's wider area
    ult_cells = []
    point = (PLAYER[0] + 300.0, PLAYER[1] - 150.0)
    for rarity in (0, 2):
        for d in (200.0, 212.0, 212.5, 213.0, 240.0, 250.0, 251.0):
            g = fresh(active=(), rarities=(rarity, 0, 0))
            at = (point[0] + d, point[1])
            pr = orb(g, at)
            foe(g, (point[0] - 400.0, point[1]))
            tr = play(g, 120, [key_op(0, "q", point)])
            ult_cells.append(dict(rarity=rarity, dist=d, x=r(at[0]), y=r(at[1]), cleared=bool(pr.dead)))
    out["cataclysm_grid"] = ult_cells
    out["setup"] = dict(conditions=False, target=[target[0], target[1]], point=[point[0], point[1]])
    # the shared quirk: an orb the slam destroyed this tick is still moved and, overlapping the player, still hurts in the prototype.
    # The player is invulnerable until the very tick of the slam (`iframes` runs out on it), so the orb waits beside him unharmed.
    aim = (PLAYER[0] + 100.0, PLAYER[1] - 20.0)
    probe_g = fresh(active=())
    foe(probe_g, aim)
    play(probe_g, 80, [begin_op(0, 0, aim)], record=False)
    landing = probe_g.slams[0]["tick"]
    g = fresh(active=())
    iframes = r((landing - 0.5) * DT, 6)
    g.player.iframes = iframes
    pr = orb(g, (PLAYER[0] + 15.0, PLAYER[1]))
    foe(g, aim)
    script = [begin_op(0, 0, aim)]
    tr = play(g, 80, script)
    out["destroyed_orb_still_hurts_in_the_prototype"] = case_of(g, tr, (), None, False, script, iframes=iframes)
    out["destroyed_orb_still_hurts_in_the_prototype"]["player_hp_prototype"] = r(g.player.hp, 3)
    out["destroyed_orb_still_hurts_in_the_prototype"]["orb_dead"] = bool(pr.dead)
    out["destroyed_orb_still_hurts_in_the_prototype"]["landing_tick"] = landing
    # orbs in flight and a slam among them (an orb flying through the area)
    g = fresh(active=(0,))
    es = [foe(g, (PLAYER[0] + 280.0, PLAYER[1] + 10.0), walk=True)]
    shots = []
    for i in range(4):
        p = Projectile(V(PLAYER[0] + 380.0, PLAYER[1] + 120.0 - 70.0 * i), V(-270.0, 0.0))
        p.life = 4.0
        p.setup = dict(x=r(p.pos.x), y=r(p.pos.y), vx=-270.0, vy=0.0, life=4.0)
        g.projectiles.append(p)
        g.orbs = getattr(g, "orbs", []) + [p]
        shots.append(p)
    tr = play(g, 120)
    out["orbs_in_flight"] = case_of(g, tr, (0,), None, False, [])
    return out


def case_deaths():
    """Deaths in and around a slam resolve once; the loops include corpses as the prototype's do."""
    out = {}
    target = (PLAYER[0] + 220.0, PLAYER[1] - 40.0)
    # a slam kills the weak and leaves the strong, rewards counted once each
    placed = [(target[0] + 30.0, target[1] + 10.0, "husk", 30.0), (target[0] - 60.0, target[1] + 20.0, "runner", 14.0), (target[0] + 90.0, target[1] - 30.0, "husk", 900.0),
              (target[0] - 20.0, target[1] - 70.0, "brute", 40.0), (target[0] + 120.0, target[1] + 90.0, "husk", 30.0), (target[0] - 100.0, target[1] + 110.0, "husk", 70.0)]
    script = [begin_op(0, 0, target)]
    g = fresh(active=())
    for x, y, kind, hp in placed:
        foe(g, (x, y), kind=kind, hp=hp)
    tr = play(g, 80, script)
    out["kills_in_slam"] = case_of(g, tr, (), None, False, script)
    # the target dies in the windup (killed from outside): the sword drops it but still lands on the point it was going to
    g = fresh(active=(0,))
    es = [foe(g, (PLAYER[0] + 240.0, PLAYER[1] + 60.0)), foe(g, (PLAYER[0] + 290.0, PLAYER[1] + 50.0)), foe(g, (PLAYER[0] + 260.0, PLAYER[1] + 90.0))]
    script = [dict(t=12, op="kill", enemy=0)]
    tr = play(g, 120, script)
    out["target_killed_in_the_windup"] = case_of(g, tr, (0,), None, False, script)
    # two Colossi, the first's slam kills a cluster on the very tick the second (idle, off cooldown) looks for a target: the
    # corpses are still in the run's list, so they are candidates and neighbours, and it targets the dead cluster
    g = fresh(active=(0,))
    cluster = [(PLAYER[0] + 260.0, PLAYER[1] - 20.0), (PLAYER[0] + 300.0, PLAYER[1] + 10.0), (PLAYER[0] + 240.0, PLAYER[1] + 40.0), (PLAYER[0] + 285.0, PLAYER[1] - 45.0)]
    for at in cluster:
        foe(g, at, hp=20.0)
    lone = foe(g, (PLAYER[0] - 250.0, PLAYER[1] + 20.0), hp=900.0)
    script = [begin_op(0, 0, (PLAYER[0] + 270.0, PLAYER[1] - 5.0))]
    probe = play(g, 70, script)
    slam_tick = [s["tick"] for s in g.slams][0]
    g = fresh(active=(0, 1), cds=[0.0, (slam_tick - 0.5) * DT, 0.0])
    for at in cluster:
        foe(g, at, hp=20.0)
    foe(g, (PLAYER[0] - 250.0, PLAYER[1] + 20.0), hp=900.0)
    tr = play(g, 140, script)
    out["corpse_cluster_is_targeted"] = case_of(g, tr, (0, 1), [0.0, (slam_tick - 0.5) * DT, 0.0], False, script, slam_tick=slam_tick)
    out["corpse_cluster_is_targeted"]["second_windup_tick"] = transitions_of(out["corpse_cluster_is_targeted"], 1, "windup")
    # the player dies in the middle of a fall: the sword stops where it is (idle), no slam happens
    g = fresh(active=(0,))
    foe(g, (PLAYER[0] + 260.0, PLAYER[1] + 30.0))
    script = [dict(t=40, op="hurt")]
    tr = play(g, 140, script)
    out["player_dies_in_the_fall"] = case_of(g, tr, (0,), None, False, script)
    return out


# ------------------------------------------------------------------ Cataclysm
def case_start():
    """Cataclysm's start: a targeted ultimate lands on the cursor but is pulled back onto 480 px from the player; the sword
    does not move; it interrupts any phase of an automatic slam; a refusal while it runs or recharges."""
    out = {}
    points = {
        "inside": (PLAYER[0] + 300.0, PLAYER[1]), "at_range": (PLAYER[0] + 480.0, PLAYER[1]), "past_range": (PLAYER[0] + 700.0, PLAYER[1]),
        "diagonal_past": (PLAYER[0] + 500.0, PLAYER[1] + 500.0), "south": (PLAYER[0], PLAYER[1] + 200.0), "on_the_player": (PLAYER[0], PLAYER[1]),
        "west_past": (PLAYER[0] - 900.0, PLAYER[1] - 20.0),
    }
    cells = {}
    for label, point in points.items():
        g = fresh()
        sw = g.swords[0]
        before = V(sw.pos)
        play(g, 5)
        before = V(sw.pos)
        apply_op(g, key_op(0, "q", point))
        cells[label] = dict(point=[r(point[0]), r(point[1])], x=r(sw.point.x), y=r(sw.point.y), phase=state_name(sw), ult_t=r(sw.ult_t, 4), ult_cd=r(sw.ult_cd, 4),
                            moved=r((sw.pos - before).length(), 4), z=r(sw.z, 4))
    out["points"] = cells
    out["setup"] = setup_of(fresh())
    # interrupting each phase of an automatic slam
    for label, ticks in (("interrupts_windup", 15), ("interrupts_fall", 40), ("interrupts_stuck", 58)):
        g = fresh(active=(0,), cds=[0.0, 0.0, 0.0])
        foe(g, (PLAYER[0] + 260.0, PLAYER[1] + 30.0), walk=True)
        script = [key_op(ticks, "q", (PLAYER[0] + 300.0, PLAYER[1] + 40.0))]
        tr = play(g, 150, script)
        out[label] = case_of(g, tr, (0,), None, False, script)
        out[label]["state_before"] = tr.swords[0]["state"][ticks - 1]
    return out


def cataclysm_enemies():
    """Enemies around a Cataclysm's impact (relative to the player; the point is 300 px east): near, at the edge, beyond."""
    cx, cy = 300.0, -20.0
    return [(cx + 30.0, cy + 10.0, "husk", 900.0), (cx - 70.0, cy + 40.0, "runner", 900.0), (cx + 120.0, cy - 60.0, "husk", 900.0), (cx + 20.0, cy + 130.0, "brute", 900.0),
            (cx - 160.0, cy - 40.0, "husk", 900.0), (cx + 200.0, cy + 30.0, "husk", 900.0), (cx - 250.0, cy + 30.0, "husk", 900.0)]


def case_single():
    """One Cataclysm against a ring of enemies (each rarity and a crit): the rise (0.75 s), the fall, the slam
    (2.2 x damage, 650 knockback, falloff), the field, the extra shake and the stuck pause, tick by tick for the field's whole life."""
    out = {}
    point = (PLAYER[0] + 300.0, PLAYER[1] - 20.0)
    for label, rarity, crit in (("common", 0, False), ("common_crit", 0, True), ("rare", 1, False), ("mythic", 2, False)):
        out[label] = run_case(400 if label == "common" else 120, enemies=cataclysm_enemies(), rarity=rarity, crit=crit, active=(), script=[key_op(0, "q", point)], name="cataclysm_" + label)
    return out


def case_edge():
    """A Cataclysm's reach: a probe husk or brute `dist` px east of the point is struck when within 212.4 + its radius."""
    out = {}
    point = (PLAYER[0] + 300.0, PLAYER[1] - 80.0)
    for kind, dists in (("husk", (100.0, 200.0, 211.0, 212.0, 228.0, 229.0, 230.0)), ("brute", (100.0, 200.0, 242.0, 243.0, 245.0))):
        cells = []
        for d in dists:
            g = fresh(active=())
            probe = foe(g, (point[0] + d, point[1]), kind=kind)
            tr = play(g, 100, [key_op(0, "q", point)])
            slam_tick = transitions_of(dict(trace=tr.out()), 0, "stuck")[0]
            cells.append(dict(dist=d, hit=probe.hp < probe.maxhp, dealt=r(probe.maxhp - probe.hp, 4), slam_tick=slam_tick, vx=tr.enemies[0]["vx"][slam_tick - 1], vy=tr.enemies[0]["vy"][slam_tick - 1]))
        out["probe_" + kind] = cells
    out["setup"] = dict(point=[point[0], point[1]])
    return out


# ------------------------------------------------------------------ fields (conditions ON)
def field_enemies(hp=2000.0):
    """Three enemies that stay inside a Cataclysm's field for its whole life: a husk beside the point, two brutes (which a slam hardly moves)."""
    return [(300.0 + 25.0, -20.0 + 15.0, "husk", hp), (300.0 - 60.0, -20.0 - 20.0, "brute", hp), (300.0 + 70.0, -20.0 + 50.0, "brute", hp)]


def case_conditions():
    """The slam's doses and the field's cadence, per element, on conditions' state of every enemy every tick: the slam's three
    doses on the impact tick, the field's first dose on the same tick (the field is made during the sword's update and ticks
    in the same update), then one dose every 0.5 s until the field expires."""
    out = {}
    point = (PLAYER[0] + 300.0, PLAYER[1] - 20.0)
    for index, element in enumerate(ELEMENTS):
        out[element] = run_case(380, enemies=field_enemies(), rarity=index, conditions=True, elements=(element, "ice", "fire"), active=(), script=[key_op(0, "q", point)], name="field_" + element)
    return out


def case_field_reach():
    """Which enemies a field doses: the centre of a probe husk (radius 16) or brute (30) within the field's radius (212.4 x 1.1)
    plus its own; probes stand outside the slam's area so only the field acts on them."""
    out = {}
    point = (PLAYER[0] + 300.0, PLAYER[1] - 80.0)
    reach = ULT_AOE * 1.1
    for kind, ds in (("husk", (246.0, 249.0, 249.5, 249.75, 250.0, 253.0)), ("brute", (260.0, 263.0, 263.5, 263.75, 264.0, 267.0))):
        radius = ENEMY_TYPES[kind]["r"]
        cells = []
        for d in ds:
            g = fresh(active=(), conditions=True, elements=("poison", "ice", "fire"))
            probe = foe(g, (point[0] + d, point[1]), kind=kind, hp=2000.0)
            tr = play(g, 70, [key_op(0, "q", point)])
            cells.append(dict(dist=d, offset=r(d - (reach + radius), 4), doses=[x["tick"] for x in g.doses if x["src"] == "field"], poison=probe.poison_stacks,
                              poison_rows=tr.enemies[0]["poison_stacks"]))
        out["probe_" + kind] = cells
    out["setup"] = dict(point=[point[0], point[1]], reach=r(reach, 4))
    return out


def case_overlap():
    """Overlapping fields: two Cataclysms in one place dose an enemy standing in both (each field has its own clock), when made on
    the same tick (the first slot's dose comes first) and twenty ticks apart; and three elements at once."""
    out = {}
    point = (PLAYER[0] + 300.0, PLAYER[1] - 20.0)
    other = (PLAYER[0] + 340.0, PLAYER[1] - 40.0)
    es = [(300.0 + 25.0, -20.0 + 15.0, "husk", 4000.0), (300.0 - 60.0, -20.0 - 20.0, "brute", 4000.0), (300.0 + 70.0, -20.0 + 50.0, "brute", 4000.0)]
    out["same_tick"] = run_case(120, enemies=es, conditions=True, elements=("poison", "fire", "ice"), active=(), script=[key_op(0, "q", point), key_op(0, "e", other)], name="overlap_same_tick")
    out["twenty_ticks_apart"] = run_case(160, enemies=es, conditions=True, elements=("poison", "fire", "ice"), active=(), script=[key_op(0, "q", point), key_op(20, "e", other)], name="overlap_apart")
    out["three_elements"] = run_case(220, enemies=es, conditions=True, elements=("poison", "ice", "fire"), active=(), script=[key_op(0, "q", point), key_op(7, "e", other), key_op(31, "r", (PLAYER[0] + 260.0, PLAYER[1] - 10.0))], name="overlap_three")
    return out


def case_field_deaths():
    """Deaths while a field is down: enemies that survive the slam burn or are poisoned to death inside it (corpses are not dosed, a burning
    death ignites its neighbours), a corpse of this very tick is skipped by the field's loop, and a field outlives the player."""
    out = {}
    point = (PLAYER[0] + 300.0, PLAYER[1] - 20.0)
    ring = [(300.0 + 30.0, -20.0 + 10.0, "husk", 190.0), (300.0 - 50.0, -20.0 + 40.0, "husk", 170.0), (300.0 + 90.0, -20.0 - 40.0, "runner", 175.0), (300.0 - 20.0, -20.0 - 100.0, "husk", 210.0),
            (300.0 - 130.0, -20.0 - 10.0, "brute", 400.0)]
    for element in ("fire", "poison"):
        out["burn_down_" + element] = run_case(380, enemies=ring, conditions=True, elements=(element, "ice", "fire"), active=(), script=[key_op(0, "q", point)], name="deaths_" + element)
    # a corpse of the field's own tick: a second Colossus slams on a pulse tick and kills an enemy standing in the field
    victims = [(535.0, -20.0, "husk", 20.0), (530.0, -50.0, "husk", 20.0), (540.0, 10.0, "husk", 900.0)]
    aim = (PLAYER[0] + 535.0, PLAYER[1] - 30.0)
    # the pulse ticks of the first Cataclysm's field (the slam's hitstop stretches the first interval): the second slam must land on the second one
    g = fresh(active=(), conditions=True, elements=("poison", "ice", "fire"))
    c = g.player.pos
    for dx, dy, k, hp in victims:
        foe(g, (c.x + dx, c.y + dy), kind=k, hp=hp)
    play(g, 200, [key_op(0, "q", point)], record=False)
    pulse_ticks = sorted({d["tick"] for d in g.doses if d["src"] == "field"})
    chosen = None
    for begin_tick in range(30, 70):
        g = fresh(active=(), conditions=True, elements=("poison", "ice", "fire"))
        c = g.player.pos
        for dx, dy, k, hp in victims:
            foe(g, (c.x + dx, c.y + dy), kind=k, hp=hp)
        script = [key_op(0, "q", point), begin_op(begin_tick, 1, aim)]
        play(g, 200, script, record=False)
        second = [s["tick"] for s in g.slams if s["sword"] == 1]
        if second and second[0] == pulse_ticks[1]:
            chosen = (begin_tick, script)
            break
    assert chosen is not None
    g = fresh(active=(), conditions=True, elements=("poison", "ice", "fire"))
    c = g.player.pos
    for dx, dy, k, hp in victims:
        foe(g, (c.x + dx, c.y + dy), kind=k, hp=hp)
    tr = play(g, 200, chosen[1])
    out["corpse_on_a_pulse_tick"] = case_of(g, tr, (), None, False, chosen[1], keep="field_corpse", begin_tick=chosen[0])
    # the player dies while the field is down: it goes on ticking (nothing in the loop looks at the player)
    out["player_dies_field_goes_on"] = run_case(200, enemies=field_enemies(), conditions=True, elements=("poison", "ice", "fire"), active=(),
                                                 script=[key_op(0, "q", point), dict(t=80, op="hurt")], name="field_player_dies")
    return out


# ------------------------------------------------------------------ rules, keys, composites
def case_rules():
    """Recharge (14 s, x0.87 / x0.74 by rarity), refusal while it runs (ACTIVE: rise and fall) and while it recharges, firing again
    after the recharge to the very tick (it runs on gameplay time, so the slam's hitstop stretches it), the other Colossi keep slamming.
    The key presses are logged (what each sword did with them) and the swords' final state compared; no per-tick trace."""
    out = {}
    point = (PLAYER[0] + 300.0, PLAYER[1] - 20.0)
    es = [(300.0 + 25.0, -20.0 + 15.0, "husk", 4000.0), (300.0 - 60.0, -20.0 - 20.0, "brute", 4000.0)]
    for rarity in (0, 1, 2):
        # the ready tick: the first tick after which the recharge reads zero, found with a traced probe
        g = fresh(active=(), rarities=(rarity, 0, 0))
        c = g.player.pos
        for dx, dy, k, hp in es:
            foe(g, (c.x + dx, c.y + dy), kind=k, hp=hp)
        tr = play(g, 1000, [key_op(0, "q", point)])
        ready = next(i + 1 for i, v in enumerate(tr.swords[0]["ult_cd"]) if v == 0.0)
        script = [key_op(0, "q", point), key_op(10, "q", point), key_op(60, "q", point), key_op(200, "q", point)]
        script += [key_op(ready - 3 + i, "q", point) for i in range(6)]
        case = run_case(ready + 120, enemies=es, rarity=rarity, active=(), script=script, name="rules_%d" % rarity, record=False)
        case["ready_tick"] = ready
        out["rarity_%d" % rarity] = case
    # the other two keep slamming while slot 0 is in its Cataclysm
    out["others_keep_slamming"] = run_case(200, enemies=[(260.0, 30.0, "husk", 4000.0, True), (-230.0, 20.0, "husk", 4000.0, True), (290.0, -60.0, "husk", 4000.0, True), (-250.0, -50.0, "runner", 4000.0, True)],
                                           active=(1, 2), script=[key_op(0, "q", point)], name="rules_others")
    return out


def case_keys():
    out = {}
    point = (PLAYER[0] + 300.0, PLAYER[1] - 20.0)
    for name in ("q", "e", "r"):
        g = fresh()
        key(g, KEYS[name], mouse=point)
        _USED_KEYS.add(name)
        out["key_" + name] = [state_name(s) for s in g.swords]
    g = fresh()
    g.paused = True
    key(g, pygame.K_q, mouse=point)
    out["paused_q"] = dict(states=[state_name(s) for s in g.swords], ult_cd=[r(s.ult_cd) for s in g.swords])
    g = fresh()
    g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    key(g, pygame.K_e, mouse=point)
    out["dead_e"] = dict(states=[state_name(s) for s in g.swords], ult_cd=[r(s.ult_cd) for s in g.swords])
    g = fresh()
    near_foe = foe(g, (PLAYER[0] + 350.0, PLAYER[1] + 100.0))
    far_foe = foe(g, (PLAYER[0] - 900.0, PLAYER[1]))
    aim = g.auto_aim()
    g.ultimate(0, aim)
    out["auto_aim"] = dict(setup=setup_of(g, (), None), nearest=[r(aim.x), r(aim.y)], point=[r(g.swords[0].point.x), r(g.swords[0].point.y)])
    g = fresh()
    aim = g.auto_aim()
    g.ultimate(0, aim)
    out["auto_aim_empty"] = dict(setup=setup_of(g, (), None), aim=[r(aim.x), r(aim.y)], point=[r(g.swords[0].point.x), r(g.swords[0].point.y)])
    out["setup"] = setup_of(fresh())
    return out


def case_pause_and_hitstop():
    """Hitstop freezes everything including the field's clock (slam hitstop 0.13 s = 8 ticks), pause too; the traces show the frozen ticks."""
    out = {}
    point = (PLAYER[0] + 300.0, PLAYER[1] - 20.0)
    script = [key_op(0, "q", point), dict(t=70, op="pause"), dict(t=100, op="resume")]
    out["pause_over_a_field"] = run_case(150, enemies=field_enemies(hp=900.0), conditions=True, elements=("poison", "ice", "fire"), active=(), script=script, name="pause_field")
    return out


def case_fight():
    """Three Colossi (poison / ice / fire, conditions on) against a ring of nine walking enemies for 480 ticks, one Cataclysm
    pressed on the way: a composite of everything above, compared tick by tick."""
    kinds = ["husk", "husk", "runner", "husk", "brute", "husk", "runner", "husk", "husk"]
    enemies = []
    for i, k in enumerate(kinds):
        ang = i * math.tau / len(kinds) + 0.3
        dist = 330.0 + 40.0 * (i % 3)
        enemies.append((math.cos(ang) * dist, math.sin(ang) * dist * 0.8, k, ENEMY_TYPES[k]["hp"], True))
    out = run_case(480, enemies=enemies, conditions=True, active=(0, 1, 2), cds=[0.2, 0.35, 0.5],
                   script=[key_op(150, "e", (PLAYER[0] + 120.0, PLAYER[1] - 60.0))], name="fight")
    return out


# ------------------------------------------------------------------ scope
def assert_fixtures_in_scope():
    for e in _CREATED:
        assert e.armed is None and e.kind in ("husk", "runner", "brute")
    for sw in _SWORDS:
        assert sw.kind == KIND
    return dict(enemies_created=len(_CREATED), armed_enemies=0, kinds=sorted({e.kind for e in _CREATED}), swords_used=sorted({sw.kind for sw in _SWORDS}),
                converge_used=False, waves_enabled=False, afflict_enabled_cases=sorted(set(_CONDITION_CASES)), afflict_disabled_everywhere_else=True,
                keys_used=sorted(_USED_KEYS), auto_attack_parked_unless_the_case_says_so=True)


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
        table=case_table(), slam=case_slam(), acquire=case_acquire(), timing=case_timing(), geometry=case_geometry(), empty_slam=case_empty_slam(),
        orbs=case_orbs(), deaths=case_deaths(), start=case_start(), single=case_single(), edge=case_edge(), conditions=case_conditions(),
        field_reach=case_field_reach(), overlap=case_overlap(), field_deaths=case_field_deaths(), rules=case_rules(), keys=case_keys(),
        pause_and_hitstop=case_pause_and_hitstop(), fight=case_fight(),
    )
    cases["fixture_scope"] = assert_fixtures_in_scope()
    text = dumps(cases)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
