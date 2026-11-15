#!/usr/bin/env python3
"""Captures focused reference cases for Converge (the player's coordinated command) and the default loadout.

Usage:  python3 -I tools/reference/capture_converge.py [out.json]
        (the committed copy is godot/tests/reference/converge.json)

Slice #16 of the Godot port. Like the earlier captures (whose loader and helpers it reuses) it drives the
prototype's REAL classes -- `Game`, `Sword`, `Enemy`, `Player` from game/main.py -- with fixed 1/60 s steps
under SDL's dummy drivers. Nothing here re-implements a rule: the click, its cooldown, the pause and death
refusals and the range clamp come from the real `Game.handle` (a synthetic MOUSEBUTTONDOWN with a patched
mouse position) and `Game.converge`; what each sword does with the command comes from `Sword.command`,
`Sword.begin` (`fast`, `boost=1.5`), `Sword.update` and `Sword.strike`; the damage from `Game.hit_enemy`
and `Game.slam`; the keys Q/E/R and Tab/G from the real `Game.handle`; the touch Converge from
`Game.auto_aim`; and the default loadout and its numbers from `Game.reset` and `Sword.__init__`.

Every case writes its fixture (`setup`: swords, enemies, the player, whether conditions are on, a short
`script` of timed ops) into the JSON and the Godot checks build their scenarios from it. The capture wraps
`Sword.command` (every sword that is offered a command, with its state before and after and the target it
chose) and `Game.ring` (where the Converge ring landed: the range-clamped point), and logs every click.

Mechanics outside this slice are off, and the capture asserts that: every enemy is an unarmed husk, runner or
brute (arming and drops are issue #17), the wave machine is off (#18) and `Game.afflict` is switched off except
in the cases whose subject is a default-loadout fight with its elements. Per-case controls: enemies stand still
(speed 0), the auto-attack cooldown of a sword that is not meant to fight is parked at 99 s, and crits are
forced off by pinning `random.random`.

Randomness. The prototype draws a few numbers no port can reproduce: a Fang's recoil heading after a hit (and
at the end of its flurry) and a slam's knock heading for an enemy standing exactly on the impact point. The
capture finds them (`random_sword`: sword index -> the first tick its pose is no longer comparable;
`random_enemy`: enemy index -> the tick of the slam) and the Godot checks compare nothing but state, timers,
health and death for them from that tick on; every other quantity is compared on every tick.
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
WORLD = NS["WORLD"]
DT = base.DT
r = base.r
NoCrit = base.NoCrit
SWORD_TYPES = NS["SWORD_TYPES"]
ENEMY_TYPES = NS["ENEMY_TYPES"]
CONVERGE_CD = NS["CONVERGE_CD"]
KINDS = ("fang", "blade", "lance", "colossus")
PLAYER = (1300.0, 900.0)  # the arena centre, where the prototype's player spawns
PARKED_CD = 99.0          # an auto-attack cooldown that never ends within a case
ELEMENTS = ("poison", "ice", "fire")
KEYS = {"q": pygame.K_q, "e": pygame.K_e, "r": pygame.K_r}
REFUSED = ("strike", "stuck", "ult")
COND_FIELDS = ("burn", "burn_dps", "poison", "poison_dps", "poison_stacks", "chill", "chill_stacks", "frozen", "dot")

_CREATED = []
_SWORDS = []
_USED_KEYS = set()
_CONDITION_CASES = []


def P(dx, dy):
    return (PLAYER[0] + dx, PLAYER[1] + dy)


# Where the eligibility cases aim their ultimates: a few pixels off the enemy at P(200, -30), because a Fang that
# blinks onto an enemy's exact centre, and a Maelstrom whose centre is an enemy's, draw a random heading.
ULT_POINT = P(190, -22)


def state_name(sw):
    return "ult_" + sw.phase if sw.state == "ult" else sw.state


# ------------------------------------------------------------------ fixtures
def fresh(kinds=("fang", "blade", "colossus"), cds=None, conditions=False, elements=ELEMENTS, rarities=(0, 0, 0), seed=1, player=None):
    """A game with one sword per entry of `kinds` (Q, E, R), each with the auto-attack cooldown `cds[i]` (parked
    at 99 s by default). No waves. `afflict` is the prototype's own only when `conditions` is set."""
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
    g.swords = [Sword(kind, rarities[i], elements[i], c) for i, kind in enumerate(kinds)]
    for i, s in enumerate(g.swords):
        s.cd = PARKED_CD if cds is None else cds[i]
        _SWORDS.append(s)
    g.setup_conditions = conditions
    g.setup_player = None if player is None else [r(player[0]), r(player[1])]
    g.setup_cds = [PARKED_CD if cds is None else cds[i] for i in range(len(kinds))]
    g.n = 0
    g.reset_tick = None
    g.es = []
    g.clicks = []
    g.commands = []
    g.rings = []
    g.slams = []
    g.fang_hits = []
    for i, sw in enumerate(g.swords):
        sw.command = _logged_command(g, i, sw)
    ring = g.ring

    def logged_ring(pos, r0, r1, life, color, width=3):
        if tuple(color) == (180, 220, 255) and r0 == 60:
            g.rings.append(dict(tick=g.n, x=r(pos.x), y=r(pos.y)))
        return ring(pos, r0, r1, life, color, width)

    g.ring = logged_ring
    slam = g.slam

    def logged_slam(sword, point, aoe=None, power=1.0, stacks=1):
        radius = aoe or sword.t["aoe"] * sword.scale
        area = [dict(enemy=g.es.index(e), dead_before=bool(e.dead), centered=bool((e.pos - point).length_squared() < 1e-6))
                for e in g.enemies if (e.pos - point).length() < radius + e.r]
        g.slams.append(dict(tick=g.n, sword=g.swords.index(sword), x=r(point.x), y=r(point.y), radius=r(radius, 4), area=area))
        return slam(sword, point, aoe, power, stacks)

    g.slam = logged_slam
    return g


def _logged_command(g, i, sw):
    inner = sw.command

    def logged(game, point):
        before = state_name(sw)
        inner(game, point)
        after = state_name(sw)
        taken = before.split("_")[0] not in REFUSED
        assert taken == (after == "windup"), (before, after)
        if not taken:
            assert after == before
        target = -1 if sw.target is None else g.es.index(sw.target)
        g.commands.append(dict(tick=g.n, sword=i, x=r(point.x), y=r(point.y), before=before, after=after, taken=taken, target=target,
                               boost=r(sw.boost), timer=r(sw.timer, 4), windup=r(sw.t["windup"], 4)))

    return logged


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


def setup_of(g, crit=False, script=(), **extra):
    """The fixture, as the Godot side must rebuild it."""
    out = dict(conditions=g.setup_conditions, crit=crit,
               swords=[dict(type=s.kind, rarity=s.rarity, element=s.element, cd=g.setup_cds[i]) for i, s in enumerate(g.swords)],
               enemies=[e.setup for e in g.es], script=list(script))
    if g.setup_player is not None:
        out["player"] = g.setup_player
    out.update(extra)
    return out


# ------------------------------------------------------------------ driving
def mouse_at(g, world):
    """Puts the mouse at the screen point whose world position is `world` (world = screen + cam - (W/2, H/2))."""
    sx = world[0] - g.cam.x + base.W / 2
    sy = world[1] - g.cam.y + base.H / 2
    pygame.mouse.get_pos = lambda sx=sx, sy=sy: (sx, sy)


def click(g, point, button=1):
    """A real MOUSEBUTTONDOWN through `Game.handle` (the prototype's click -> Converge path), logged."""
    mouse_at(g, point)
    before = g.converge_cd
    states = [state_name(s) for s in g.swords]
    seen = len(g.commands)
    g.handle(pygame.event.Event(pygame.MOUSEBUTTONDOWN, button=button, pos=(0, 0)))
    after = g.converge_cd
    g.clicks.append(dict(tick=g.n, button=button, x=r(point[0]), y=r(point[1]), cd_before=r(before, 4), cd_after=r(after, 4), states_before=states,
                         accepted=bool(before <= 0 and after == CONVERGE_CD), commanded=[c["sword"] for c in g.commands[seen:] if c["taken"]],
                         offered=len(g.commands) - seen, paused=bool(g.paused), dead=bool(g.player.dead)))


def apply_op(g, op):
    kind = op["op"]
    if kind == "begin":
        target = None if op.get("target") is None else g.es[op["target"]]
        g.swords[op["sword"]].begin(target, V(op["aim"]))
    elif kind == "click":
        click(g, op["point"], op.get("button", 1))
    elif kind == "key":
        _USED_KEYS.add(op["key"])
        flurry.key(g, KEYS[op["key"]], mouse=op["point"])
    elif kind == "tab":
        g.handle(pygame.event.Event(pygame.KEYDOWN, key=pygame.K_TAB if op.get("key", "tab") == "tab" else pygame.K_g))
        g.ranges_log.append(dict(tick=g.n, key=op.get("key", "tab"), shown=bool(g.show_ranges)))
    elif kind == "touch_converge":
        before = g.converge_cd
        seen = len(g.commands)
        point = g.auto_aim()
        g.converge(point)
        g.clicks.append(dict(tick=g.n, button=0, x=r(point.x), y=r(point.y), cd_before=r(before, 4), cd_after=r(g.converge_cd, 4), states_before=[],
                             accepted=bool(before <= 0 and g.converge_cd == CONVERGE_CD), commanded=[c["sword"] for c in g.commands[seen:] if c["taken"]],
                             offered=len(g.commands) - seen, paused=bool(g.paused), dead=bool(g.player.dead)))
    elif kind == "kill":
        g.kill(g.es[op["enemy"]], V(0, -1), False)
    elif kind == "corpse":
        # A dead enemy still in the list: it is only taken out at the end of the tick that killed it, so a command
        # never sees one in a real run; the prototype's own loop would pick it as a target.
        g.es[op["enemy"]].dead = True
    elif kind == "hurt":
        g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    elif kind == "pause":
        g.paused = True
    elif kind == "resume":
        g.paused = False
    elif kind == "reset":
        g.reset()
        g.reset_tick = g.n + 1  # the swords' starting cooldowns are drawn at random
    else:
        raise AssertionError(kind)


class Trace:
    """Per-tick record (after each tick) of the swords, every enemy and the run's shared counters, as dict-of-lists."""

    def __init__(self, g, conditions):
        self.g = g
        self.conditions = conditions
        self.n = 0
        self.run = dict(hitstop=[], trauma=[], kills=[], player_x=[], player_y=[], player_hp=[], converge_cd=[], ranges=[])
        self.swords = [dict(state=[], x=[], y=[], ang=[], vx=[], vy=[], z=[], vz=[], timer=[], cd=[], ult_cd=[], ult_t=[], boost=[], aim_x=[], aim_y=[], target=[])
                       for _ in g.swords]
        self.enemies = [dict(x=[], y=[], hp=[], vx=[], vy=[], stun=[], flash=[], dead=[], **({f: [] for f in COND_FIELDS} if conditions else {})) for _ in g.es]
        self.random_sword = {}
        self.second_attack = {}
        self._state = [state_name(s) for s in g.swords]

    def step(self):
        g = self.g
        self.n += 1
        run = self.run
        run["hitstop"].append(r(g.hitstop, 4))
        run["trauma"].append(r(g.trauma, 4))
        run["kills"].append(g.kills)
        run["player_x"].append(r(g.player.pos.x))
        run["player_y"].append(r(g.player.pos.y))
        run["player_hp"].append(r(g.player.hp, 3))
        run["converge_cd"].append(r(g.converge_cd, 4))
        run["ranges"].append(1 if g.show_ranges else 0)
        for i, (sw, col) in enumerate(zip(g.swords, self.swords)):
            name = state_name(sw)
            if sw.kind == "fang" and str(i) not in self.random_sword:
                # A Fang's recoil after a hit, and the end of its flurry, take a random heading (the strike's own
                # end without a hit does not): its pose is not comparable from that tick on.
                if self._state[i] == "strike" and name == "recover" and abs((sw.vel + sw.dir * 380).length() - 160.0) < 0.5:
                    self.random_sword[str(i)] = self.n
                if self._state[i].startswith("ult") and name == "recover":
                    self.random_sword[str(i)] = self.n
            if sw.kind == "fang" and str(i) in self.random_sword and self._state[i] == "idle" and name == "windup" and str(i) not in self.second_attack:
                # a recoiled Fang's next automatic attack starts from a pose the port cannot reproduce
                self.second_attack[str(i)] = self.n
            self._state[i] = name
            col["state"].append(name)
            col["x"].append(r(sw.pos.x))
            col["y"].append(r(sw.pos.y))
            col["ang"].append(r(sw.ang, 4))
            col["vx"].append(r(sw.vel.x))
            col["vy"].append(r(sw.vel.y))
            col["z"].append(r(sw.z, 4) if sw.kind == "colossus" else 0.0)
            col["vz"].append(r(sw.vz, 4) if sw.kind == "colossus" else 0.0)
            col["timer"].append(r(sw.timer, 4))
            col["cd"].append(r(sw.cd, 4))
            col["ult_cd"].append(r(sw.ult_cd, 4))
            col["ult_t"].append(r(sw.ult_t, 4))
            col["boost"].append(r(sw.boost, 4))
            col["aim_x"].append(r(sw.aim.x))
            col["aim_y"].append(r(sw.aim.y))
            col["target"].append(-1 if sw.target is None else g.es.index(sw.target))
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

    def compare_until(self):
        """Ticks after which a Fang's second attack (from its random recoil pose) would no longer be comparable: the
        enemies it hits are knocked along a slightly different heading. None when no Fang has attacked twice."""
        return min(self.second_attack.values()) + 3 if self.second_attack else None

    def out(self):
        return dict(ticks=self.n, run=self.run, swords=self.swords, enemies=self.enemies)


def play(g, ticks, script=(), crit=False):
    """Plays `ticks` fixed ticks, executing each scripted op after `op["t"]` completed ticks, recording a trace."""
    g.ranges_log = []
    tr = Trace(g, g.setup_conditions)
    pending = sorted(script, key=lambda o: o["t"])
    with NoCrit(crit):
        for n in range(ticks + 1):
            while pending and pending[0]["t"] == n:
                apply_op(g, pending.pop(0))
            if n == ticks:
                break
            g.n += 1
            g.update(DT)
            tr.step()
    assert not pending
    g.ticks_played = ticks
    return tr


def random_heading(g):
    """Enemies that stood exactly on an impact point (hit in a random direction): index -> tick."""
    out = {}
    for s in g.slams:
        for a in s["area"]:
            if a["centered"] and not a["dead_before"] and str(a["enemy"]) not in out:
                out[str(a["enemy"])] = s["tick"]
    return out


def case_of(g, tr, crit=False, script=(), keep=False, **extra):
    """One finished case: its fixture, the trace, every click and command, and what the prototype drew at random."""
    out = dict(ticks=g.ticks_played, setup=setup_of(g, crit, script, **extra), trace=tr.out(), clicks=g.clicks, commands=g.commands, rings=g.rings,
               random_sword=tr.random_sword, random_enemy=random_heading(g), kills=g.kills, ranges=g.ranges_log)
    if tr.compare_until() is not None:
        out["compare_until"] = tr.compare_until()
    if g.reset_tick is not None:
        out["random_cd_from"] = g.reset_tick
    if g.setup_conditions:
        _CONDITION_CASES.append(keep)
    return out


def run_case(ticks, kinds, enemies=(), script=(), cds=None, conditions=False, crit=False, player=None, name="", **kw):
    g = fresh(kinds=kinds, cds=cds, conditions=conditions, player=player, **kw)
    for spec in enemies:
        foe(g, spec[0], **(spec[1] if len(spec) > 1 else {}))
    tr = play(g, ticks, script, crit=crit)
    return case_of(g, tr, crit=crit, script=script, name=name)


def click_op(t, point, button=1):
    return dict(t=t, op="click", point=[r(point[0]), r(point[1])], button=button)


def key_op(t, key, point):
    return dict(t=t, op="key", key=key, point=[r(point[0]), r(point[1])])


# ------------------------------------------------------------------ cases
def case_table():
    out = dict(converge_cd=CONVERGE_CD, buttons_that_converge=[1, 3], clamp=460, target_radius=90, boost=1.5, windup_factor=0.6)
    swords = [Sword(k, 0, "fire", V(0, 0)) for k in KINDS]
    out["types"] = {s.kind: dict(damage=r(s.damage, 4), cooldown=r(s.cooldown, 4), range=r(s.range, 4), length=r(s.L, 4), windup=r(s.t["windup"], 4),
                                 ult_name=s.ult["name"], ult_max=r(s.ult_max, 4)) for s in swords}
    out["rarity"] = {k: [dict(damage=r(Sword(k, i, "fire", V(0, 0)).damage, 4), range=r(Sword(k, i, "fire", V(0, 0)).range, 4)) for i in range(3)] for k in KINDS}
    return out


def case_start():
    """The prototype's normal start (`Game.reset`): the default loadout and its numbers."""
    random.seed(5)
    g = base.new_game()
    g.reset()
    out = dict(swords=[dict(type=s.kind, rarity=s.rarity, element=s.element, damage=r(s.damage, 4), cooldown=r(s.cooldown, 4), range=r(s.range, 4),
                            ult_name=s.ult["name"], ult_max=r(s.ult_max, 4), ult_cd=r(s.ult_cd, 4), state=s.state, x=r(s.pos.x), y=r(s.pos.y)) for s in g.swords],
               converge_cd=r(g.converge_cd), player=[r(g.player.pos.x), r(g.player.pos.y)], show_ranges=bool(g.show_ranges), count=len(g.swords),
               start_cd_band=[0.2, 0.6], start_cds_in_band=all(0.2 <= s.cd <= 0.6 for s in g.swords))
    return out


# --- what each type does with a command ---------------------------------------------------------------
def commanded_cases():
    out = {}
    for kind in KINDS:
        k3 = (kind, kind, kind)
        # on an enemy: the nearest within 90 px of the click is the target
        out["commanded_" + kind] = run_case(
            150, k3, [(P(260, -40),), (P(300, 60),)], [click_op(4, P(250, -30))], name="commanded_" + kind)
        # on an empty point: nothing within 90 px, the swords strike the point itself
        out["empty_" + kind] = run_case(
            150, k3, [(P(300, 150),), (P(210, 250),)], [click_op(4, P(200, 150))], name="empty_" + kind)
        # far beyond the range: the point is pulled back to 460 px; the enemy beside the pulled-back point is the target
        out["far_" + kind] = run_case(
            150, k3, [(P(470, 30),), (P(700, 0),)], [click_op(4, P(900, 0), 3)], name="far_" + kind)
        # near the player
        out["near_" + kind] = run_case(
            120, k3, [(P(60, 8),), (P(-70, 30),)], [click_op(4, P(40, 14))], name="near_" + kind)
        # right on the player
        out["on_player_" + kind] = run_case(
            120, k3, [(P(80, 0),), (P(-80, 10),)], [click_op(4, P(0, 0))], name="on_player_" + kind)
    return out


# --- eligibility: a sword in each state --------------------------------------------------------------
def prep_script(kind, state):
    """The ops that put sword 0 into `state` (and the tick to find it by), against the enemy at P(200, -30)."""
    target = P(200, -30)
    if state == "idle":
        return []
    if state == "ult":
        return [key_op(0, "q", ULT_POINT)]
    if kind in ("fang", "colossus"):
        # A Fang that hits recoils in a random heading, which would make its next strike incomparable, and a slam
        # centred on an enemy knocks it in a random heading: these are sent at an empty point (a Fang misses, which
        # recovers deterministically; a slam there reaches nobody)
        return [dict(t=0, op="begin", sword=0, target=None, aim=[r(P(110, 110)[0]), r(P(110, 110)[1])])]
    return [dict(t=0, op="begin", sword=0, target=0, aim=[r(target[0]), r(target[1])])]


def eligibility_click(kind):
    """Where the eligibility cases click: on the enemy, but for Colossus 91 px from it (no target: the slam is centred on the point,
    never exactly on an enemy, which would be knocked in a random heading)."""
    return P(190, -120) if kind == "colossus" else P(230, -10)


def eligibility_enemies(kind):
    # A Fang's flurry strikes a random victim among the enemies in its area and its recoil is random: a single
    # enemy keeps the flurry's strike deterministic. The others fight two.
    first = (P(200, -30),)
    return [first] if kind == "fang" else [first, (P(260, 40),)]


def find_state_tick(kind, state):
    """The number of ticks after which sword 0, prepared with `prep_script`, first is in `state` (searching a throwaway game)."""
    g = fresh(kinds=(kind,) * 3)
    for spec in eligibility_enemies(kind):
        foe(g, spec[0])
    script = prep_script(kind, state)
    pending = sorted(script, key=lambda o: o["t"])
    g.ranges_log = []
    with NoCrit(False):
        for n in range(400):
            while pending and pending[0]["t"] == n:
                apply_op(g, pending.pop(0))
            if not pending and state_name(g.swords[0]) == state and (state != "idle" or n >= 2):
                return n
            g.n += 1
            g.update(DT)
    raise AssertionError((kind, state))


def eligibility_cases():
    out = {}
    for kind in KINDS:
        states = ["idle", "windup", "strike", "recover", "ult"] + (["stuck"] if kind == "colossus" else [])
        for state in states:
            if state == "idle":
                at = 3
            elif state == "ult":
                at = 6
            else:
                at = find_state_tick(kind, state) + 1  # the sword has been in the state for a tick
            script = prep_script(kind, state) + [click_op(at, eligibility_click(kind))]
            length = at + (70 if kind == "fang" else 110)
            case = run_case(length, (kind,) * 3, eligibility_enemies(kind), script, name="eligibility_%s_%s" % (kind, state))
            first = case["commands"][0]
            assert first["sword"] == 0 and first["before"].split("_")[0] == state, (kind, state, first)
            assert first["taken"] == (state not in REFUSED), (kind, state, first)
            out["eligibility_%s_%s" % (kind, state)] = case
        # the three swords all busy: nothing takes the command, the cooldown starts anyway
        script = [key_op(0, "q", ULT_POINT), key_op(0, "e", ULT_POINT), key_op(0, "r", ULT_POINT), click_op(6, eligibility_click(kind)), click_op(40, eligibility_click(kind))]
        out["all_busy_" + kind] = run_case(70 if kind == "fang" else 100, (kind,) * 3, eligibility_enemies(kind), script, name="all_busy_" + kind)
    return out


def dead_target_cases():
    """The commanded sword's target dies while the sword winds up or strikes: it keeps the point it last saw."""
    out = {}
    for kind in KINDS:
        script = [click_op(4, P(250, -30)), dict(t=6, op="kill", enemy=0)]
        out["dead_target_" + kind] = run_case(130, (kind,) * 3, [(P(260, -40),), (P(300, 60),)], script, name="dead_target_" + kind)
        script = [click_op(4, P(250, -30)), dict(t=5, op="kill", enemy=0)]
        out["dead_target_early_" + kind] = run_case(130, (kind,) * 3, [(P(260, -40),), (P(300, 60),)], script, name="dead_target_early_" + kind)
    return out


def corpse_cases():
    """What the prototype's own targeting loop does with a dead enemy still in the list (it does not skip it)."""
    out = {}
    for kind in KINDS:
        # the corpse is the nearest enemy to the click (14 px); a live enemy stands 78 px away: the prototype's sword
        # takes the corpse, loses it on its next update and strikes the point; a sword that skipped corpses would follow the live one
        script = [dict(t=3, op="corpse", enemy=0), click_op(3, P(250, -30))]
        out["corpse_" + kind] = run_case(110, (kind,) * 3, [(P(260, -40),), (P(300, 30),)], script, name="corpse_" + kind)
    return out


def case_cooldown():
    """The shared cooldown: accepted at once, refused until 2.5 s have passed, middle button ignored, then accepted again."""
    kinds = ("blade", "lance", "colossus")
    enemies = [(P(220, 0),), (P(260, 90),), (P(-200, 40),)]
    script = [click_op(5, P(230, 10)), click_op(40, P(-190, 40), 3), click_op(90, P(230, 10)), click_op(140, P(230, 10)), click_op(154, P(230, 10)),
              click_op(156, P(-190, 40), 3), click_op(158, P(230, 10), 2), click_op(177, P(230, 10)), click_op(181, P(-190, 40), 3), click_op(300, P(230, 10), 1),
              click_op(420, P(230, 10), 1), click_op(460, P(-190, 40), 3)]
    return run_case(500, kinds, enemies, script, name="cooldown")


def case_spam():
    """A click every 5 ticks for 5 s: only every 2.5 s one is accepted; the swords keep fighting on their own."""
    kinds = ("blade", "lance", "colossus")
    enemies = [(P(220, 0),), (P(260, 90),), (P(-200, 40),), (P(100, -150),)]
    script = [click_op(t, P(230, 10) if (t // 5) % 2 == 0 else P(-190, 40), 1 if (t // 5) % 3 else 3) for t in range(5, 300, 5)]
    return run_case(330, kinds, enemies, script, cds=[0.2, 0.35, 0.5], name="spam")


def case_paused_dead():
    out = {}
    kinds = ("blade", "lance", "colossus")
    enemies = [(P(220, 0),), (P(260, 90),)]
    out["paused"] = run_case(120, kinds, enemies, [dict(t=2, op="pause"), click_op(4, P(230, 10)), dict(t=10, op="resume"), click_op(12, P(230, 10))], name="paused")
    out["dead"] = run_case(120, kinds, enemies, [dict(t=2, op="hurt"), click_op(10, P(230, 10)), click_op(60, P(230, 10), 3)], name="dead")
    return out


def case_ultimates():
    """Converge and the slot ultimates side by side: an ultimate does not wait for the Converge cooldown and the
    Converge does not wait for the ultimate recharge; a sword in its ultimate ignores the command, one still winding
    up for it takes the ultimate over."""
    kinds = ("blade", "lance", "colossus")
    enemies = [(P(220, 0),), (P(260, 90),), (P(-200, 40),)]
    script = [click_op(5, P(230, 10)), key_op(8, "q", P(230, 10)), key_op(30, "e", P(230, 10)), key_op(50, "r", P(-190, 40)), click_op(60, P(230, 10)), click_op(160, P(230, 10)),
              click_op(300, P(230, 10))]
    return run_case(420, kinds, enemies, script, name="ultimates")


def case_default_loadout():
    """The prototype's default loadout (Fang poison, Warden ice, Colossus fire) commanded at a cluster with the
    prototype's own conditions on: all three types answer one Converge at once."""
    enemies = [(P(250, -20),), (P(285, 30),), (P(230, 55),), (P(300, -50),), (P(265, 5),)]
    out = {}
    out["default_converge"] = run_case(240, ("fang", "blade", "colossus"), enemies, [click_op(4, P(262, 0))], conditions=True, name="default_converge")
    out["default_converge_far"] = run_case(240, ("fang", "blade", "colossus"), [(P(440, 60),), (P(470, 20),), (P(420, 10),)], [click_op(4, P(900, 120), 3)],
                                           conditions=True, name="default_converge_far")
    out["default_converge_rarity"] = run_case(200, ("fang", "blade", "colossus"), enemies, [click_op(4, P(262, 0))], conditions=True, rarities=(1, 2, 1), name="default_converge_rarity")
    return out


def case_touch_and_ranges():
    out = {}
    kinds = ("blade", "lance", "colossus")
    out["touch_nearest"] = run_case(120, kinds, [(P(350, 100),), (P(-600, 0),)], [dict(t=4, op="touch_converge")], name="touch_nearest")
    out["touch_empty"] = run_case(120, kinds, [], [dict(t=4, op="touch_converge")], name="touch_empty")
    # Tab / G: toggles while alive and running, ignored while paused or dead, kept by a restart
    script = [dict(t=2, op="tab", key="tab"), dict(t=4, op="tab", key="g"), dict(t=6, op="tab", key="tab"), dict(t=8, op="pause"), dict(t=9, op="tab", key="tab"),
              dict(t=12, op="resume"), dict(t=14, op="tab", key="g"), dict(t=16, op="hurt"), dict(t=20, op="tab", key="tab"), dict(t=24, op="reset"), dict(t=28, op="tab", key="g")]
    out["ranges"] = run_case(40, ("fang", "blade", "colossus"), [], script, name="ranges")
    return out


def case_default_wave():
    """The normal start against the first wave (husks only, nothing armed), the prototype's own default loadout with its
    conditions on, the player standing still: once with no input and once with a Converge at the nearest enemy every 3 s
    (what a player who only clicks does). Spawn points and the Fang's recoil are random, so the Godot checks compare a band."""
    out = {}
    for name, converge_every in (("no_input", 0), ("converge_every_3s", 180)):
        results = []
        for seed in range(1, 9):
            random.seed(seed)
            g = base.new_game()
            del g.afflict  # the shared helper switches conditions off; this case plays the prototype's own
            assert g.afflict.__func__ is Game.afflict
            base.disarm_waves(g)
            g.in_wave = False
            g.break_t = 1.6
            base.hold()
            assert [s.kind for s in g.swords] == ["fang", "blade", "colossus"]
            for sw in g.swords:
                _SWORDS.append(sw)
            t_real = 0.0
            cleared_at = None
            converged = 0
            with NoCrit(False):
                for n in range(round(60.0 / DT)):
                    if converge_every and n % converge_every == converge_every - 1 and g.enemies:
                        before = g.converge_cd
                        g.converge(g.auto_aim())
                        converged += 1 if before <= 0 else 0
                    g.update(DT)
                    t_real += DT
                    base.assert_all_unarmed(g, 30.0)
                    if g.wave >= 1 and not g.in_wave and g.banner and g.banner[0] == "WAVE CLEARED" and cleared_at is None:
                        cleared_at = t_real
                        break
                    if g.player.dead:
                        break
            results.append(dict(seed=seed, cleared_at=None if cleared_at is None else r(cleared_at, 2), died=g.player.dead, hp=r(g.player.hp, 1), kills=g.kills,
                                converged=converged, armed_enemies=0))
        out[name] = results
    return out


# ------------------------------------------------------------------ scope
def assert_fixtures_in_scope():
    for e in _CREATED:
        assert e.armed is None and e.kind in ("husk", "runner", "brute")
    return dict(enemies_created=len(_CREATED), armed_enemies=0, kinds=sorted({e.kind for e in _CREATED}), swords_used=sorted({sw.kind for sw in _SWORDS}),
                waves_enabled=False, afflict_enabled_cases=len(_CONDITION_CASES), afflict_disabled_everywhere_else=True, keys_used=sorted(_USED_KEYS),
                auto_attack_parked_unless_the_case_says_so=True)


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
    cases = dict(table=case_table(), start=case_start())
    cases["types"] = commanded_cases()
    cases["eligibility"] = eligibility_cases()
    cases["dead_targets"] = dead_target_cases()
    cases["corpses"] = corpse_cases()
    cases["cooldown"] = case_cooldown()
    cases["spam"] = case_spam()
    cases["refusals"] = case_paused_dead()
    cases["ultimates"] = case_ultimates()
    cases["default"] = case_default_loadout()
    cases["default_wave"] = case_default_wave()
    cases["touch_and_ranges"] = case_touch_and_ranges()
    cases["fixture_scope"] = assert_fixtures_in_scope()
    text = dumps(cases)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
