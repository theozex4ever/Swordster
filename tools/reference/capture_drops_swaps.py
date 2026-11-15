#!/usr/bin/env python3
"""Captures focused reference cases for armed enemies, sword drops, rarity modifiers and swaps.

Usage:  python3 -I tools/reference/capture_drops_swaps.py [out.json]
        (the committed copy is godot/tests/reference/drops_swaps.json)

Slice #17 of the Godot port. Like the earlier captures (whose loader and helpers it reuses) it drives the
prototype's REAL classes -- `Game`, `Sword`, `Enemy`, `Pickup` from game/main.py -- under SDL's dummy drivers
with fixed 1/60 s steps. Nothing here re-implements a rule: the rarity modifiers come from `Sword.__init__`, the
armed health from `Enemy.__init__`, the drop from `Game.kill`, the arming rolls from `Game.start_wave` (driven with
a scripted random source, so every branch and boundary is pinned without relying on any seed), the pickup's life and
removal from `Game.update`, the swap from `Game.swap`, the keys from `Game.handle`, and the pickup card's numbers
from `Game.draw_pickup_card` itself (its drawing calls are recorded through a stand-in font).

Randomness: `Game.swap` draws the returned sword's sideways offset from `random.uniform(-20, 20)` and a new
`Sword`'s starting cooldown (overwritten by the swap) and a `Pickup`'s bobbing phase, which no port can reproduce.
The capture records the offset of every swap it makes (the Godot checks demand the same range and the fixed 24 px
drop) and leaves the cosmetic phase out. Every case seeds `random` first, so the file is byte-identical on every run.

Mechanics outside this slice are off, and the capture asserts that: no wave is running (the wave machine is #18;
`start_wave` is only called in the arming cases, on a game that never updates), Converge is never commanded (#16), and
the swords of a swap case are parked (auto-attack cooldown 99 s) so no enemy or hit is involved.
"""
import json
import math
import random
import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import capture_fang_survival_loop as base  # noqa: E402  (loads the prototype)
import capture_viper_flurry as flurry  # noqa: E402

import pygame  # noqa: E402

NS = base.NS
V = base.V
Game = NS["Game"]
Sword = NS["Sword"]
Enemy = NS["Enemy"]
Pickup = NS["Pickup"]
WORLD = NS["WORLD"]
DT = base.DT
r = base.r
SWORD_TYPES = NS["SWORD_TYPES"]
ENEMY_TYPES = NS["ENEMY_TYPES"]
RARITIES = NS["RARITIES"]
ELEMENTS = NS["ELEMENTS"]
DROP_WEIGHTS = NS["DROP_WEIGHTS"]
KINDS = ("fang", "blade", "lance", "colossus")  # the prototype's own keys; Warden is "blade", Pike is "lance"
ENEMY_KINDS = ("husk", "runner", "spitter", "brute")
ELEMENT_ORDER = list(ELEMENTS)
PLAYER = (1300.0, 900.0)
PARKED_CD = 99.0
K = {1: pygame.K_1, 2: pygame.K_2, 3: pygame.K_3}


# ------------------------------------------------------------------ fixtures
_GAME = []


def fresh(seed=1, specs=(("fang", 0, "poison"), ("blade", 0, "ice"), ("colossus", 0, "fire")), player=None):
    """A game with the given swords (kind, rarity, element) in slots 0..2, all parked, no enemies, no waves. Building a
    `Game` synthesises its sounds and takes seconds, so one is built and put back to its starting state by the prototype's
    own `Game.reset` for every case (plus the few things `reset` leaves alone)."""
    random.seed(seed)
    if not _GAME:
        game = base.new_game(swords=[])
        _GAME.append((game, game.fonts))
    g, fonts = _GAME[0]
    g.reset()
    g.fonts = fonts
    g.paused = False
    g.in_wave = False
    g.break_t = 1e9
    base.hold()
    assert (g.player.pos.x, g.player.pos.y) == PLAYER
    if player is not None:
        g.player.pos = V(player)
    c = g.player.pos
    g.swords = [Sword(k, ra, el, c) for k, ra, el in specs]
    for s in g.swords:
        s.cd = PARKED_CD
    return g


def put(g, spec, dx, dy, life=None):
    """A pickup `dx`, `dy` from the player (its bobbing phase is cosmetic: pinned to zero)."""
    pk = Pickup(spec[0], spec[1], spec[2], V(g.player.pos.x + dx, g.player.pos.y + dy))
    pk.t = 0.0
    if life is not None:
        pk.life = life
    g.pickups.append(pk)
    return pk


def sword_state(sw):
    return dict(kind=sw.kind, rarity=sw.rarity, element=sw.element, name=sw.name, damage=r(sw.damage, 4), cooldown=r(sw.cooldown, 4),
                range=r(sw.range, 4), ult_max=r(sw.ult_max, 4), ult_cd=r(sw.ult_cd, 4), scale=r(sw.scale, 4), length=r(sw.L, 4),
                ult_aoe=r(sw.ult_aoe, 4), cd=r(sw.cd, 4), z=r(sw.z, 4), flash=r(sw.flash, 4), vx=r(sw.vel.x), vy=r(sw.vel.y),
                x=r(sw.pos.x), y=r(sw.pos.y), state=sw.state)


def pickup_state(pk, player):
    return dict(kind=pk.kind, rarity=pk.rarity, element=pk.element, dx=r(pk.pos.x - player.x), dy=r(pk.pos.y - player.y), life=r(pk.life, 4))


def spec_of(sw):
    return [sw.kind, sw.rarity, sw.element]


def swap(g, slot, via_key=False):
    """The prototype's swap, through its own key handler when asked, returning what changed."""
    p = g.player.pos
    before_swords = [spec_of(s) for s in g.swords]
    before_pickups = [pickup_state(pk, p) for pk in g.pickups]
    old = g.swords[slot] if slot < len(g.swords) else None
    old_ult = None if old is None else (r(old.ult_cd, 4), r(old.ult_max, 4))
    if via_key:
        flurry.key(g, K[slot + 1])
    else:
        g.swap(slot)
    after_swords = [spec_of(s) for s in g.swords]
    swapped = slot < len(g.swords) and g.swords[slot] is not old
    out = dict(slot=slot, swapped=swapped, swords_before=before_swords, swords_after=after_swords, pickups_before=before_pickups,
               pickups_after=[pickup_state(pk, p) for pk in g.pickups], ult_before=old_ult)
    if swapped and slot < len(g.swords):
        out["new"] = sword_state(g.swords[slot])
    return out


# ------------------------------------------------------------------ the table
def case_table():
    out = dict(rarities=[dict(name=ra["name"], color=list(ra["color"]), dmg=ra["dmg"], cd=ra["cd"], rng=ra["rng"], size=ra["size"]) for ra in RARITIES],
               elements=[dict(key=k, name=v["name"], adj=v["adj"], color=list(v["color"]), tag=v["tag"]) for k, v in ELEMENTS.items()],
               drop_weights=[[k, w] for k, w in DROP_WEIGHTS],
               types=[dict(kind=k, name=SWORD_TYPES[k]["name"], blurb=SWORD_TYPES[k]["blurb"], damage=SWORD_TYPES[k]["damage"],
                           cooldown=SWORD_TYPES[k]["cooldown"], range=SWORD_TYPES[k]["range"], ult_name=SWORD_TYPES[k]["ult"]["name"],
                           ult_cd=SWORD_TYPES[k]["ult"]["cd"], ult_shot=SWORD_TYPES[k]["ult"]["shot"]) for k in KINDS],
               armed_chance={k: ENEMY_TYPES[k]["armed"] for k in ENEMY_KINDS})
    # a pickup's constants, from the real class
    random.seed(1)
    pk = Pickup("fang", 0, "fire", V(10, 20))
    out["pickup"] = dict(life=pk.life)
    # the armed health factor: the real constructor, armed against unarmed, over kinds and waves
    out["armed_hp"] = [dict(kind=k, wave=w, unarmed=r(Enemy(k, V(0, 0), w).maxhp, 4), armed=r(Enemy(k, V(0, 0), w, ("fang", 0, "fire")).maxhp, 4))
                       for k in ENEMY_KINDS for w in (1, 2, 5)]
    # what a swap does to the new sword and to the replaced one's drop, over many swaps (the offsets are random)
    dxs, dys, news = [], [], []
    for seed in range(400):
        g = fresh(seed=seed)
        pk = put(g, ("fang", 1, "ice"), 10.0, 10.0)
        g.swords[0].ult_cd = g.swords[0].ult_max * 0.5
        g.swap(0)
        back = g.pickups[-1]
        dxs.append(back.pos.x - pk.pos.x)
        dys.append(back.pos.y - pk.pos.y)
        if seed == 0:
            news.append(sword_state(g.swords[0]))
            out["returned_life"] = r(back.life, 4)
    out["swap"] = dict(returned_dx_min=r(min(dxs), 3), returned_dx_max=r(max(dxs), 3), returned_dy=sorted({r(v, 4) for v in dys}), swaps=len(dxs),
                       new_cd=news[0]["cd"], new_z=news[0]["z"], new_flash=news[0]["flash"], new_vx=news[0]["vx"], new_vy=news[0]["vy"],
                       reach=80.0)
    return out


def case_matrix():
    """Every type x rarity x element: what a sword carries (`Sword.__init__`) and the pickup card's text, recorded from
    `Game.draw_pickup_card` through a stand-in font."""
    out = []
    for kind in KINDS:
        for rarity in range(3):
            for element in ELEMENT_ORDER:
                random.seed(1)
                sw = Sword(kind, rarity, element, V(0, 0))
                entry = sword_state(sw)
                entry["color"] = list(sw.color)
                entry["card"] = card_lines(kind, rarity, element)
                out.append(entry)
    return out


class _Font:
    def __init__(self, size, log):
        self.size, self.log = size, log

    def render(self, text, aa, color, *rest):
        self.log.append(dict(size=self.size, text=text, color=list(color)))
        return pygame.Surface((1, 1))

    def get_height(self):
        return self.size

    def size_of(self, text):
        return (len(text) * self.size // 2, self.size)


class _Fonts(dict):
    def __init__(self, log):
        super().__init__()
        self.log = log

    def __missing__(self, size):
        return _Font(size, self.log)


def card_lines(kind, rarity, element):
    """The texts `Game.draw_pickup_card` draws for a pickup, in drawing order."""
    g = fresh()
    log = []
    g.fonts = _Fonts(log)
    pk = put(g, (kind, rarity, element), 10.0, 0.0)
    g.draw_pickup_card(pk)
    return [e["text"] for e in log]


# ------------------------------------------------------------------ arming
class Script:
    """A scripted stand-in for the random module's three functions `Game.start_wave` uses. Every call must be one the
    case expected: a call with nothing queued (or values left over afterwards) fails the capture."""

    def __init__(self):
        self.uniform_values, self.random_values, self.choice_indices = deque(), deque(), deque()
        self.calls = []

    def uniform(self, a, b):
        v = self.uniform_values.popleft()
        assert a <= v <= b, (a, v, b)
        self.calls.append("uniform")
        return v

    def random(self):
        self.calls.append("random")
        return self.random_values.popleft()

    def choice(self, seq):
        self.calls.append("choice")
        return seq[self.choice_indices.popleft()]

    def empty(self):
        return not (self.uniform_values or self.random_values or self.choice_indices)


def kind_draw(pool, kind):
    """The `random.uniform(0, total)` value that makes `weighted(pool)` return `kind` (the middle of its share)."""
    total = sum(w for _, w in pool)
    before = 0.0
    for k, w in pool:
        if k == kind:
            return before + w / 2.0, total
        before += w
    raise AssertionError(kind)


def wave_pool(w):
    pool = [("husk", 6), ("runner", 2.5 if w >= 2 else 0), ("spitter", 2 if w >= 3 else 0), ("brute", 0.6 + 0.25 * w if w >= 2 else 0)]
    return [(k, v) for k, v in pool if v > 0]


def run_wave(wave, probes):
    """`Game.start_wave` for `wave` with a scripted random source. `probes` maps an enemy index to its scripted draws
    (kind, arm_roll, drop_draw, rarity_roll, element_index); every other enemy is a husk that misses its arming roll
    (or, on the first wave, one of the two guaranteed). Returns the queue the prototype built: (kind, armed) entries."""
    g = fresh()
    g.wave = wave - 1
    pool = wave_pool(wave)
    n = 5 + wave * 3
    script = Script()
    expected = []
    for j in range(n):
        p = probes.get(j)
        kind = p["kind"] if p else "husk"
        draw, total = kind_draw(pool, kind)
        script.uniform_values.append(draw)
        guaranteed = wave == 1 and j < 2
        arm_roll = p["arm_roll"] if p else 0.99
        if not guaranteed:
            script.random_values.append(arm_roll)
        armed = guaranteed or arm_roll < ENEMY_TYPES[kind]["armed"]
        if armed:
            if not (wave == 1 and j == 0):
                script.uniform_values.append(p["drop_draw"] if p else 5.0)
            script.random_values.append(p["rarity_roll"] if p else 0.99)
            script.choice_indices.append(p["element_index"] if p else 0)
    orig = (random.uniform, random.random, random.choice)
    random.uniform, random.random, random.choice = script.uniform, script.random, script.choice
    try:
        g.start_wave()
    finally:
        random.uniform, random.random, random.choice = orig
    assert script.empty(), "the capture's model of start_wave's random calls is wrong"
    return g.spawn_queue


def arming_probe(wave, index, kind, arm_roll, drop_draw, rarity_roll, element_index):
    # Rolls are rounded to nine places: the JSON round trip through Godot's parser is only good to about 1e-15, so a roll
    # sitting exactly on a threshold would not survive it. What the prototype does with the rounded value is what is recorded.
    arm_roll, drop_draw, rarity_roll = round(arm_roll, 9), round(drop_draw, 9), round(rarity_roll, 9)
    queue = run_wave(wave, {index: dict(kind=kind, arm_roll=arm_roll, drop_draw=drop_draw, rarity_roll=rarity_roll, element_index=element_index)})
    got_kind, armed = queue[index]
    assert got_kind == kind
    return dict(wave=wave, index=index, kind=kind, arm_roll=arm_roll, drop_draw=drop_draw, rarity_roll=rarity_roll, element_index=element_index,
                armed=None if armed is None else list(armed))


def case_arming():
    probes = []
    # the arming chance of each kind: just under, exactly at, just over, and the extremes (wave 3: every kind is in the pool)
    for kind in ENEMY_KINDS:
        chance = ENEMY_TYPES[kind]["armed"]
        for roll in (0.0, chance - 0.001, chance, chance + 0.001, 0.999):
            probes.append(arming_probe(3, 5, kind, roll, 4.0, 0.5, 1))
    # which type a draw picks: at, just under and just over every cumulative weight (the total is 10.1)
    total = sum(w for _, w in DROP_WEIGHTS)
    cumulative = 0.0
    edges = [0.0]
    for _, w in DROP_WEIGHTS:
        cumulative += w
        edges.append(cumulative)
    for edge in edges[:-1] + [total]:
        for draw in (edge - 0.001, edge, edge + 0.001):
            if 0.0 <= draw <= total:
                probes.append(arming_probe(4, 7, "husk", 0.0, draw, 0.9, 2))
    # the element of every index (random.choice over the prototype's element order)
    for index in range(3):
        probes.append(arming_probe(2, 6, "runner", 0.0, 4.0, 0.9, index))
    # the rarity thresholds of each wave and for a brute (its bonus), at, just under and just over each
    for wave in range(1, 13):
        for kind in ("husk", "brute"):
            if wave == 1 and kind == "brute":
                continue
            bonus = 0.15 if kind == "brute" else 0.0
            for threshold in (min(0.25, 0.02 + 0.02 * wave) + bonus * 0.5, min(0.55, 0.16 + 0.04 * wave) + bonus):
                for roll in (threshold - 1e-6, threshold, threshold + 1e-6):
                    probes.append(arming_probe(wave, 7, kind, 0.0, 6.0, roll, 0))
    # the first wave: its first two enemies are armed whatever they roll, the first always with a Pike, the rest by chance
    first = []
    for index in range(4):
        for arm_roll in (0.0, 0.99):
            first.append(arming_probe(1, index, "husk", arm_roll, 9.0, 0.5, 2))
    for p in probes + first:
        pass
    # a whole first wave and a later one with every enemy unarmed except the scripted ones: the queue's length and kinds
    queue = run_wave(1, {})
    shape = dict(first_wave_length=len(queue), first_wave_kinds=sorted({k for k, _ in queue}), first_wave_armed=[a is not None for _, a in queue],
                 first_wave_first=list(queue[0][1]), second_wave_length=len(run_wave(2, {})))
    return dict(probes=probes, first_wave=first, shape=shape, element_order=ELEMENT_ORDER, total_weight=total)


# ------------------------------------------------------------------ drops on death
def case_drops():
    out = {}
    kills = []
    for kind in ENEMY_KINDS:
        for i, spec in enumerate((("fang", 0, "fire"), ("blade", 1, "ice"), ("lance", 2, "poison"), ("colossus", 1, "fire"))):
            g = fresh()
            e = Enemy(kind, V(PLAYER[0] + 300.0, PLAYER[1] + 40.0), 1, spec)
            e.speed = 0.0
            g.enemies.append(e)
            sw = g.swords[0]
            with base.NoCrit(False):
                g.hit_enemy(e, 5000.0, V(1, 0), 100.0, sw)
                after_first = len(g.pickups)
                g.hit_enemy(e, 5000.0, V(1, 0), 100.0, sw)  # a dead enemy ignores further hits: the drop is not repeated
            pk = g.pickups[0]
            kills.append(dict(kind=kind, spec=list(spec), maxhp=r(e.maxhp, 4), pickups=len(g.pickups), after_first=after_first, kills=g.kills,
                              pickup=dict(kind=pk.kind, rarity=pk.rarity, element=pk.element, x=r(pk.pos.x), y=r(pk.pos.y), life=pk.life),
                              enemy=dict(x=r(e.pos.x), y=r(e.pos.y))))
    out["kills"] = kills
    # an unarmed enemy drops nothing
    g = fresh()
    e = Enemy("brute", V(PLAYER[0] + 300.0, PLAYER[1]), 1)
    g.enemies.append(e)
    with base.NoCrit(False):
        g.hit_enemy(e, 5000.0, V(1, 0), 100.0, g.swords[0])
    out["unarmed"] = dict(pickups=len(g.pickups), kills=g.kills)
    # two armed enemies killed in the same tick: two drops, in the order they died
    g = fresh()
    a = Enemy("husk", V(PLAYER[0] + 300.0, PLAYER[1]), 1, ("fang", 0, "fire"))
    b = Enemy("husk", V(PLAYER[0] - 300.0, PLAYER[1]), 1, ("lance", 2, "poison"))
    g.enemies += [a, b]
    with base.NoCrit(False):
        g.hit_enemy(b, 5000.0, V(1, 0), 100.0, g.swords[0])
        g.hit_enemy(a, 5000.0, V(1, 0), 100.0, g.swords[0])
    out["same_tick"] = [dict(kind=pk.kind, rarity=pk.rarity, element=pk.element, x=r(pk.pos.x)) for pk in g.pickups]
    return out


# ------------------------------------------------------------------ pickup life
def case_life():
    """A pickup's life under the real `Game.update`: it counts down on gameplay time (frozen by pause and hitstop, slowed by slow
    motion) and is removed once it reaches zero (the tick at which it does is recorded for each script)."""
    out = {}

    def run(name, script=(), ticks=3200, life=None):
        g = fresh()
        pk = put(g, ("lance", 2, "ice"), 400.0, 0.0, life=life)
        trace = []
        gone = None
        for n in range(ticks):
            for op in script:
                if op[0] == n:
                    op[1](g)
            g.update(DT)
            trace.append(r(pk.life, 4))
            if pk not in g.pickups and gone is None:
                gone = n + 1
                break
        out[name] = dict(gone_at=gone, trace=trace[:420], life_at=[[i, trace[i]] for i in range(0, len(trace), 100)], count=len(trace))

    run("plain")
    run("hitstop", [(100, lambda g: setattr(g, "hitstop", 0.5))])
    run("slowmo", [(200, lambda g: (setattr(g, "slowmo", 1.4), setattr(g, "slowmo_scale", 0.25)))])
    run("paused", [(50, lambda g: setattr(g, "paused", True)), (110, lambda g: setattr(g, "paused", False))])
    run("short", life=1.0)
    run("nearly_gone", life=1.0 / 60.0)
    run("dead_player", [(30, lambda g: g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1])))])
    return out


# ------------------------------------------------------------------ swapping
def case_reach():
    """Which pickup a swap claims: the nearest one strictly within 80 px, the first of equals; nothing otherwise."""
    out = {}
    single = []
    for dist in (0.0, 40.0, 79.95, 80.0, 80.05, 120.0, 400.0):
        for direction in ((1.0, 0.0), (0.0, -1.0), (-1.0, 0.0)):
            g = fresh()
            put(g, ("blade", 1, "fire"), direction[0] * dist, direction[1] * dist)
            res = swap(g, 1)
            single.append(dict(dist=dist, direction=list(direction), swapped=res["swapped"], pickups_after=len(g.pickups)))
    out["single"] = single
    cases = []

    def multi(name, placements, slot=0):
        g = fresh()
        for spec, dx, dy in placements:
            put(g, spec, dx, dy)
        res = swap(g, slot)
        res["name"] = name
        res["placements"] = [dict(spec=list(spec), dx=dx, dy=dy) for spec, dx, dy in placements]
        res["claimed"] = None if not res["swapped"] else list(res["new"]["kind"] and [res["new"]["kind"], res["new"]["rarity"], res["new"]["element"]])
        cases.append(res)

    A, B, C = ("fang", 0, "fire"), ("lance", 1, "ice"), ("colossus", 2, "poison")
    multi("nearest_of_three", [(A, 70.0, 0.0), (B, 30.0, 0.0), (C, 60.0, 0.0)])
    multi("tie_first_wins", [(A, 50.0, 0.0), (B, -50.0, 0.0)])
    multi("tie_first_wins_reversed", [(B, -50.0, 0.0), (A, 50.0, 0.0)])
    multi("tie_three_way", [(C, 0.0, 60.0), (A, 60.0, 0.0), (B, 0.0, -60.0)])
    multi("far_one_ignored", [(A, 500.0, 0.0), (B, 79.0, 0.0)])
    multi("all_far", [(A, 500.0, 0.0), (B, 80.0, 0.0), (C, -90.0, 0.0)])
    multi("exactly_at_the_player", [(A, 0.0, 0.0), (B, 1.0, 0.0)])
    multi("diagonal_just_inside", [(B, 56.5, 56.5)])
    multi("diagonal_just_outside", [(B, 56.7, 56.7)])
    out["multi"] = cases
    # a slot that holds no sword (the prototype guards idx against len(swords)); and no pickups at all
    g = fresh()
    put(g, A, 10.0, 0.0)
    out["no_such_slot"] = swap(g, 5)
    out["no_pickups"] = swap(fresh(), 0)
    return out


def case_swaps():
    """Every type x rarity x element swapped into a slot of a different sword with a ready, a part-spent and a full recharge."""
    old_specs = [("fang", 0, "poison"), ("blade", 1, "ice"), ("lance", 2, "fire"), ("colossus", 1, "poison"), ("colossus", 2, "ice"), ("fang", 2, "fire")]
    fractions = (0.0, 0.37, 1.0)
    cases = []
    n = 0
    for kind in KINDS:
        for rarity in range(3):
            for element in ELEMENT_ORDER:
                old = old_specs[n % len(old_specs)]
                fraction = fractions[n % len(fractions)]
                slot = n % 3
                specs = [("fang", 0, "poison"), ("blade", 0, "ice"), ("colossus", 0, "fire")]
                specs[slot] = old
                g = fresh(seed=100 + n, specs=specs)
                g.swords[slot].ult_cd = g.swords[slot].ult_max * fraction
                put(g, (kind, rarity, element), 20.0, -30.0)
                res = swap(g, slot, via_key=True)
                res["setup"] = dict(old=list(old), fraction=fraction, slot=slot, pickup=[kind, rarity, element])
                res["other_slots_untouched"] = all(spec_of(g.swords[i]) == specs[i] for i in range(3) if i != slot)
                res["returned"] = res["pickups_after"][-1]
                cases.append(res)
                n += 1
    return cases


def case_repeated():
    """Swapping again and again (the sword you put back lies at your feet): the slot keeps its recharge FRACTION through every
    swap, whatever the rarity (so the full time) of the sword in it; the other slots and the pickups in reach are untouched."""
    g = fresh(seed=7)
    sw = g.swords[1]
    sw.ult_cd = sw.ult_max * 0.6
    chain = []
    specs = [("lance", 2, "ice"), ("fang", 0, "fire"), ("colossus", 1, "poison"), ("blade", 2, "fire"), ("fang", 1, "ice"), ("colossus", 0, "ice"), ("lance", 0, "poison"),
             ("blade", 1, "poison"), ("fang", 2, "poison"), ("colossus", 2, "fire")]
    for i, spec in enumerate(specs):
        put(g, spec, 15.0, 0.0)
        # the earlier returned drops are at 24 px or so below the last: stand on the new one by taking the nearest
        before = [spec_of(s) for s in g.swords]
        pk_before = len(g.pickups)
        res = swap(g, 1)
        chain.append(dict(spec=list(spec), swapped=res["swapped"], new=res["new"] if "new" in res else None, slot_fraction=r(g.swords[1].ult_cd / g.swords[1].ult_max, 4),
                          pickups=len(g.pickups), pickups_before=pk_before, others=[spec_of(g.swords[0]), spec_of(g.swords[2])], before=before))
        # let the recharge run a little so the chain is not a single fraction
        for _ in range(30):
            g.update(DT)
    return chain


def case_trace():
    """The swapped-in sword's flight after the swap, tick by tick: it starts where the pickup lay, rising at 200 px/s, and settles onto
    its orbit around the (stationary) player; a Colossus starts at height 10. The recharge keeps counting down."""
    out = {}
    for kind in KINDS:
        g = fresh(seed=3)
        sw = g.swords[0]
        sw.ult_cd = sw.ult_max * 0.5
        for _ in range(40):
            g.update(DT)
        put(g, (kind, 1, "ice"), 30.0, -40.0)
        g.swap(0)
        sw = g.swords[0]
        trace = dict(x=[], y=[], vx=[], vy=[], ang=[], cd=[], ult_cd=[], z=[], state=[], flash=[])
        for _ in range(150):
            g.update(DT)
            trace["x"].append(r(sw.pos.x))
            trace["y"].append(r(sw.pos.y))
            trace["vx"].append(r(sw.vel.x))
            trace["vy"].append(r(sw.vel.y))
            trace["ang"].append(r(sw.ang, 4))
            trace["cd"].append(r(sw.cd, 4))
            trace["ult_cd"].append(r(sw.ult_cd, 4))
            trace["z"].append(r(sw.z, 4))
            trace["state"].append(sw.state)
            trace["flash"].append(r(sw.flash, 4))
        out[kind] = dict(ticks_before_swap=40, pickup=[30.0, -40.0], trace=trace)
    return out


def case_rules():
    """Keys 1, 2 and 3 through the real key handler; refused while paused or dead; a restart clears the pickups."""
    out = {}
    for slot in range(3):
        g = fresh()
        put(g, ("lance", 1, "fire"), 10.0, 0.0)
        out["key_%d" % (slot + 1)] = swap(g, slot, via_key=True)
    g = fresh()
    put(g, ("lance", 1, "fire"), 10.0, 0.0)
    g.paused = True
    out["paused"] = swap(g, 0, via_key=True)
    g = fresh()
    put(g, ("lance", 1, "fire"), 10.0, 0.0)
    g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    out["dead"] = swap(g, 0, via_key=True)
    g = fresh()
    put(g, ("lance", 1, "fire"), 10.0, 0.0)
    put(g, ("fang", 2, "ice"), 500.0, 0.0)
    swap(g, 0)
    before = len(g.pickups)
    g.reset()
    out["reset"] = dict(pickups_before=before, pickups_after=len(g.pickups), swords_after=[spec_of(s) for s in g.swords])
    return out


# ------------------------------------------------------------------ output
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
    cases = dict(table=case_table(), matrix=case_matrix(), arming=case_arming(), drops=case_drops(), life=case_life(), reach=case_reach(),
                 swaps=case_swaps(), repeated=case_repeated(), trace=case_trace(), rules=case_rules())
    cases["fixture_scope"] = dict(waves_running=False, converge_used=False, auto_attack_parked=True, start_wave_only_in_arming_cases=True,
                                  armed_enemies_only_in_drops_cases=True)
    text = dumps(cases)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
