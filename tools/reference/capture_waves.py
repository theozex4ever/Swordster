#!/usr/bin/env python3
"""Captures focused reference cases for the wave machine: composition, scaling, spawn timing and positions, armed
probabilities, rarity progression, completion, breaks, death and restart, and the counters a normal run shows.

Usage:  python3 -I tools/reference/capture_waves.py [out.json]
        (the committed copy is godot/tests/reference/waves.json)

Slice #18 of the Godot port. Like the earlier captures (whose loader and helpers it reuses) it drives the prototype's REAL
classes -- `Game`, `Enemy`, `Sword` from game/main.py -- under SDL's dummy drivers with fixed 1/60 s steps. Nothing here
re-implements a rule: the composition pools are read off the prototype's own `Game.start_wave` (the `weighted()` call it
makes is spied on, so the pool it builds is what is recorded), the kind a draw picks from the real `weighted`, the spawn
timing from the real `Game.update_waves` and `Game.update`, the positions from the real `Game.spawn_point`, the health from
`Enemy.__init__`, the counters from `Game.kill` and `Game.update`, the restart from `Game.reset`, and the heads-up text and
banner from `Game.draw` itself (its drawing calls are recorded through a stand-in font).

Randomness. The Godot port cannot reproduce Python's `random` stream, so no case here depends on one. Everything the port
must match exactly is recorded from SCRIPTED draws (a scripted `random.uniform` / `random.random` / `random.choice`, whose
use the capture asserts, so a call the case did not expect fails the capture) or from rules with no draw at all (the formulas,
the timing, the completion). What is random in the prototype is recorded as a DISTRIBUTION over many seeded waves (the share of
each kind, how many are armed, the rarity mix), which the Godot checks compare within sampling error, never value for value.
Every case seeds `random` first, so the file is byte-identical on every run.

Mechanics outside this slice are off, and the capture asserts that: no sword attacks (every auto-attack cooldown is parked at
99 s), Converge is never commanded, conditions are not applied, and enemies stand still unless a case moves them.
"""
import json
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import capture_fang_survival_loop as base  # noqa: E402  (loads the prototype)
import capture_drops_swaps as drops  # noqa: E402

import pygame  # noqa: E402

NS = base.NS
V = base.V
Game = NS["Game"]
Enemy = NS["Enemy"]
WORLD = NS["WORLD"]
DT = base.DT
r = base.r
ENEMY_TYPES = NS["ENEMY_TYPES"]
DROP_WEIGHTS = NS["DROP_WEIGHTS"]
ELEMENTS = NS["ELEMENTS"]
ELEMENT_ORDER = list(ELEMENTS)
ENEMY_KINDS = ("husk", "runner", "spitter", "brute")
KINDS = ("fang", "blade", "lance", "colossus")
PLAYER = drops.PLAYER
TABLE_WAVES = tuple(range(1, 31))
SAMPLE_WAVES = (1, 2, 3, 4, 5, 8, 12, 20, 30)
real_weighted = NS["weighted"]


def fresh(seed=1):
    """A prototype game at its starting state with no wave running (the drops capture's `fresh`), its break timer parked."""
    state = random.getstate()  # `drops.fresh` reseeds `random`; the case seeded it for its own purposes before this call
    g = drops.fresh(seed=seed)
    random.setstate(state)
    g.spawn_queue, g.markers, g.enemies = [], [], []
    return g


def spied_start_wave(g):
    """`Game.start_wave` on `g`, returning the pools it handed to `weighted()`: the kind pool of each queued enemy and the
    drop pool of each armed one, in call order."""
    calls = []

    def spy(pairs):
        calls.append(pairs)
        return real_weighted(pairs)

    NS["weighted"] = spy
    try:
        g.start_wave()
    finally:
        NS["weighted"] = real_weighted
    return calls


def pool_of(pairs):
    return [[k, w] for k, w in pairs]


# ------------------------------------------------------------------ the wave table
def case_table():
    """What `start_wave` builds for each wave: how many enemies, the weighted pool their kinds are drawn from, the banner."""
    out = []
    for w in TABLE_WAVES:
        random.seed(w)
        g = fresh()
        g.wave = w - 1
        calls = spied_start_wave(g)
        kind_pools = [c for c in calls if c is not DROP_WEIGHTS]
        assert len(kind_pools) == len(g.spawn_queue)
        assert all(c == kind_pools[0] for c in kind_pools), "the pool changed within a wave"
        pool = pool_of(kind_pools[0])
        out.append(dict(wave=w, count=len(g.spawn_queue), pool=pool, total_weight=r(sum(x[1] for x in pool), 6), wave_after=g.wave,
                        in_wave=g.in_wave, spawn_timer=g.spawn_timer, banner=[g.banner[0], g.banner[1], g.banner[2]],
                        drop_pool_is_drop_weights=all(c is DROP_WEIGHTS for c in calls if c is not kind_pools[0] and c not in kind_pools)))
    return out


def case_kind_draws():
    """Which kind the real `weighted()` returns for a draw `random.uniform(0, total)` gave it: at, just under and just over every
    cumulative weight of the pool, for the sampled waves (draws rounded to nine places, as the drops capture does)."""
    out = []
    for w in SAMPLE_WAVES:
        g = fresh()
        g.wave = w - 1
        random.seed(w)
        calls = spied_start_wave(g)
        pool = [c for c in calls if c is not DROP_WEIGHTS][0]
        total = sum(x[1] for x in pool)
        edges, acc = [0.0], 0.0
        for _, weight in pool:
            acc += weight
            edges.append(acc)
        cases = []
        original = random.uniform
        try:
            for edge in edges:
                for draw in (edge - 1e-6, edge, edge + 1e-6):
                    draw = round(draw, 9)
                    if 0.0 <= draw <= total:
                        random.uniform = (lambda a, b, d=draw: d)
                        cases.append([draw, real_weighted(pool)])
        finally:
            random.uniform = original
        out.append(dict(wave=w, total=r(total, 6), edges=[r(e, 6) for e in edges], draws=cases))
    return out


# ------------------------------------------------------------------ health per wave
def case_hp():
    """`Enemy.__init__`'s maximum health for every kind over the waves, unarmed and armed, and the speed it draws."""
    rows = []
    for kind in ENEMY_KINDS:
        for w in TABLE_WAVES:
            rows.append(dict(kind=kind, wave=w, unarmed=r(Enemy(kind, V(0, 0), w).maxhp, 6), armed=r(Enemy(kind, V(0, 0), w, ("fang", 0, "fire")).maxhp, 6)))
    random.seed(11)
    ratios = [Enemy("husk", V(0, 0), 1).speed / ENEMY_TYPES["husk"]["speed"] for _ in range(4000)]
    return dict(rows=rows, speed_factor_min=r(min(ratios), 3), speed_factor_max=r(max(ratios), 3), speed_factor_mean=r(sum(ratios) / len(ratios), 3))


# ------------------------------------------------------------------ spawn timing
def timing_run(wave, queue_len=8, ticks=420):
    """The real `update_waves` from the moment a wave starts: the tick at which each marker appears and at which each
    marker's enemy arrives (wave `wave`, no player, no swords: nothing kills or hurts anything in the window)."""
    random.seed(1000 + wave)
    g = fresh()
    g.wave = wave - 1
    g.in_wave = False
    g.break_t = 0.0
    marker_ticks, enemy_ticks, started = [], [], None
    seen_markers, seen_enemies = 0, 0
    for tick in range(1, ticks + 1):
        was = g.wave
        g.update(DT)
        if started is None and g.wave == wave:
            started = tick
            g.spawn_queue = g.spawn_queue[:queue_len]  # only the timing of the first few is recorded
            g.player.hp = 1e9
            g.player.iframes = 1e9
        if started is not None:
            total_markers = len(g.markers) + len(g.enemies) + (queue_len - len(g.spawn_queue))
            created = queue_len - len(g.spawn_queue)
            while seen_markers < created:
                marker_ticks.append(tick - started)
                seen_markers += 1
            while seen_enemies < len(g.enemies):
                enemy_ticks.append(tick - started)
                seen_enemies += 1
    return dict(wave=wave, started_at=started, marker_ticks=marker_ticks, enemy_ticks=enemy_ticks)


def case_timing():
    rows = [timing_run(w) for w in (1, 2, 3, 5, 10, 15, 19, 20, 21, 30)]
    g = fresh()
    g.wave = 4
    g.in_wave = True
    g.spawn_queue = [("husk", None)] * 3
    g.spawn_timer = 0.3
    marker = None
    random.seed(5)
    for _ in range(20):
        g.update_waves(DT)
        if g.markers:
            marker = g.markers[0]
            break
    return dict(runs=rows, marker_life=marker.max, marker_remaining_at_creation=r(marker.t, 6), first_spawn_delay=0.3)


# ------------------------------------------------------------------ spawn positions
class Script:
    """Scripted `random.uniform` for `spawn_point`: attempt after attempt of (angle, distance), asserted to be used exactly."""

    def __init__(self, attempts):
        self.values = [v for a in attempts for v in a]
        self.calls = 0

    def uniform(self, a, b):
        v = self.values[self.calls]
        assert a <= v <= b, (a, v, b)
        self.calls += 1
        return v


def spawn_point_with(player, attempts):
    g = fresh()
    g.player.pos = V(player)
    script = Script(attempts)
    original = random.uniform
    random.uniform = script.uniform
    try:
        q = g.spawn_point()
    finally:
        random.uniform = original
    assert script.calls % 2 == 0 and script.calls // 2 <= 12
    return dict(x=r(q.x, 4), y=r(q.y, 4), attempts=script.calls // 2)


def case_spawn_points():
    out = {}
    players = [PLAYER, (60.0, 60.0), (2540.0, 1740.0), (1300.0, 40.0), (40.0, 900.0), (2580.0, 900.0), (300.0, 1700.0), (2400.0, 120.0)]
    scripted = []
    for player in players:
        for k in range(16):
            angle = round(k * math.tau / 16.0, 6)
            for distance in (420.0, 570.0, 720.0):
                res = spawn_point_with(player, [(angle, distance)] * 12)
                scripted.append(dict(player=list(player), angle=angle, distance=distance, **res))
    out["single"] = scripted
    # a first attempt too near (the clamp pulls it in), then good ones: the first good attempt wins
    mixed = []
    for player in players[1:4]:
        toward_corner = math.atan2(-1.0 if player[1] < 900 else 1.0, -1.0 if player[0] < 1300 else 1.0) % math.tau
        away = (toward_corner + math.pi) % math.tau
        for bad in range(0, 12, 3):
            attempts = [(round(toward_corner, 6), 720.0)] * bad + [(round(away, 6), 500.0)] * 12
            res = spawn_point_with(player, attempts[:12])
            mixed.append(dict(player=list(player), bad_first=bad, toward=round(toward_corner, 6), away=round(away, 6), **res))
    out["mixed"] = mixed
    # twelve near attempts in a row: the twelfth is taken whatever it is (an inward attempt in a corner)
    corner = (60.0, 60.0)
    attempts = [(round(math.pi * (1.0 + 0.04 * i), 6), 420.0 + 20.0 * i) for i in range(12)]
    out["fallback"] = dict(player=list(corner), attempts_in=[list(a) for a in attempts], **spawn_point_with(corner, attempts))
    # the distribution of unscripted spawns: bounds and moments over many points, from a few places
    dist = []
    for player in (PLAYER, (60.0, 60.0), (2540.0, 900.0), (1300.0, 1760.0)):
        random.seed(77)
        g = fresh()
        g.player.pos = V(player)
        distances, near, xs, ys = [], 0, [], []
        n = 4000
        for _ in range(n):
            q = g.spawn_point()
            assert 50.0 <= q.x <= WORLD.right - 50.0 and 50.0 <= q.y <= WORLD.bottom - 50.0
            d = (q - g.player.pos).length()
            distances.append(d)
            near += d <= 320.0
            xs.append(q.x - player[0])
            ys.append(q.y - player[1])
        dist.append(dict(player=list(player), n=n, min=r(min(distances), 2), max=r(max(distances), 2), mean=r(sum(distances) / n, 1),
                         share_near_fallback=r(near / n, 4), mean_dx=r(sum(xs) / n, 1), mean_dy=r(sum(ys) / n, 1)))
    out["distribution"] = dist
    out["bounds"] = dict(margin=50.0, near_limit=320.0, min_distance=420.0, max_distance=720.0)
    return out


# ------------------------------------------------------------------ armed probabilities and rarity progression
def case_distribution():
    """What `start_wave` produces over many seeded waves: the share of each kind, how many enemies are armed (overall and by
    kind), the rarity mix of the armed ones, their types and elements. Statistical, never compared value for value."""
    out = []
    for w in SAMPLE_WAVES:
        n_waves = 1500 if w < 12 else 800
        random.seed(5000 + w)
        kinds = {k: 0 for k in ENEMY_KINDS}
        armed_by_kind = {k: 0 for k in ENEMY_KINDS}
        rarity = [0, 0, 0]
        brute_rarity = [0, 0, 0]
        types = {k: 0 for k in KINDS}
        elements = {e: 0 for e in ELEMENT_ORDER}
        total = armed = 0
        first_two_armed = first_is_lance = 0
        counts = []
        for _ in range(n_waves):
            g = fresh()
            g.wave = w - 1
            g.start_wave()
            counts.append(len(g.spawn_queue))
            for j, (kind, arm) in enumerate(g.spawn_queue):
                kinds[kind] += 1
                total += 1
                if arm is not None:
                    armed += 1
                    armed_by_kind[kind] += 1
                    rarity[arm[1]] += 1
                    if kind == "brute":
                        brute_rarity[arm[1]] += 1
                    types[arm[0]] += 1
                    elements[arm[2]] += 1
            if w == 1:
                first_two_armed += g.spawn_queue[0][1] is not None and g.spawn_queue[1][1] is not None
                first_is_lance += g.spawn_queue[0][1] is not None and g.spawn_queue[0][1][0] == "lance"
        entry = dict(wave=w, waves=n_waves, enemies=total, count=counts[0], counts_equal=len(set(counts)) == 1,
                     kind_share={k: r(kinds[k] / total, 4) for k in ENEMY_KINDS},
                     armed_share=r(armed / total, 4), armed_by_kind={k: r(armed_by_kind[k] / kinds[k], 4) if kinds[k] else None for k in ENEMY_KINDS},
                     kinds=kinds, armed_by_kind_counts=armed_by_kind, armed=armed,
                     rarity_share=[r(c / armed, 4) for c in rarity], rarity_counts=rarity,
                     brute_rarity_share=[r(c / max(1, sum(brute_rarity)), 4) for c in brute_rarity], brute_armed=sum(brute_rarity),
                     type_share={k: r(types[k] / armed, 4) for k in KINDS}, element_share={e: r(elements[e] / armed, 4) for e in ELEMENT_ORDER})
        if w == 1:
            entry.update(first_two_armed=first_two_armed, first_is_lance=first_is_lance)
        out.append(entry)
    return out


def case_first_wave():
    """The first wave's guarantee over many seeds, through the real `start_wave`: the first queued enemy is armed with a
    lance (Pike) and the second with some sword, whatever the dice say; later waves guarantee nothing."""
    first = []
    for seed in range(300):
        random.seed(seed)
        g = fresh()
        g.start_wave()
        first.append([g.spawn_queue[0][1] is not None and g.spawn_queue[0][1][0] == "lance", g.spawn_queue[1][1] is not None])
    later_unarmed_first = 0
    later_pike_first = 0
    for seed in range(300):
        random.seed(seed)
        g = fresh()
        g.wave = 1
        g.start_wave()
        later_unarmed_first += g.spawn_queue[0][1] is None
        later_pike_first += g.spawn_queue[0][1] is not None and g.spawn_queue[0][1][0] == "lance"
    return dict(seeds=300, first_wave_first_is_lance=sum(a for a, _ in first), first_wave_second_armed=sum(b for _, b in first),
                second_wave_first_unarmed=later_unarmed_first, second_wave_first_lance=later_pike_first)


# ------------------------------------------------------------------ completion, breaks, death and restart
def completion_state(g):
    return dict(in_wave=g.in_wave, wave=g.wave, queue=len(g.spawn_queue), markers=len(g.markers), enemies=len(g.enemies),
                break_t=r(g.break_t, 6), slowmo=r(g.slowmo, 6), slowmo_scale=g.slowmo_scale,
                banner=None if g.banner is None else [g.banner[0], g.banner[1], r(g.banner[2], 6)])


def case_waits():
    """Does one `update_waves` call complete the wave? For every combination of a spawn queue, a telegraphed marker and a living
    enemy standing: only none of the three completes it."""
    out = []
    for queue in (False, True):
        for marker in (False, True):
            for enemy in (False, True):
                random.seed(3)
                g = fresh()
                g.wave = 2
                g.in_wave = True
                g.spawn_timer = 5.0
                if queue:
                    g.spawn_queue = [("husk", None)]
                if marker:
                    g.markers.append(NS["Marker"]("husk", V(100, 100), None))
                if enemy:
                    e = Enemy("husk", V(2000, 1700), 3)
                    e.speed = 0.0
                    g.enemies.append(e)
                g.update_waves(DT)
                out.append(dict(queue=queue, marker=marker, enemy=enemy, in_wave=g.in_wave, wave=g.wave, banner=None if g.banner is None else g.banner[0]))
    # a dead enemy still in the list holds the wave (the list is only filtered after contacts in `update`)
    g = fresh()
    g.wave = 2
    g.in_wave = True
    corpse = Enemy("husk", V(2000, 1700), 3)
    corpse.dead = True
    g.enemies.append(corpse)
    g.update_waves(DT)
    corpse_holds = g.in_wave
    return dict(combinations=out, corpse_in_list_holds_wave=corpse_holds)


def case_clear_and_break():
    """A wave cleared by the last enemy's death under the real `Game.update`: the tick the wave completes (banner, slow motion,
    break), the tick the next wave starts and what it queues. Also the very first break of a fresh run."""
    out = {}
    random.seed(9)
    g = fresh()
    g.wave = 1
    g.in_wave = True
    e = Enemy("husk", V(2200.0, 1700.0), 1)
    e.speed = 0.0
    g.enemies.append(e)
    base.hold()
    for _ in range(30):
        g.update(DT)
    assert g.in_wave
    g.kills = 7
    g.kill(e, V(1, 0), False)
    cleared_at = next_wave_at = None
    trace = []
    for tick in range(1, 900):
        g.update(DT)
        if cleared_at is None and not g.in_wave:
            cleared_at = tick
            out["at_clear"] = completion_state(g)
        if cleared_at is not None and tick in (cleared_at, cleared_at + 30, cleared_at + 60, cleared_at + 120):
            trace.append([tick - cleared_at, r(g.break_t, 6), r(g.slowmo, 6)])
        if cleared_at is not None and g.wave == 2:
            next_wave_at = tick
            out["at_next_wave"] = completion_state(g)
            out["next_wave_queue"] = len(g.spawn_queue)
            out["next_wave_spawn_timer"] = g.spawn_timer
            break
    out["cleared_at_tick"] = cleared_at
    out["next_wave_after_ticks"] = next_wave_at - cleared_at
    out["break_trace"] = trace
    # a fresh run: the first wave waits 1.6 s
    random.seed(10)
    g = drops.fresh()
    g.reset()
    g.fonts = drops._GAME[0][1]
    g.paused = False
    first = None
    for tick in range(1, 400):
        g.update(DT)
        if g.wave == 1:
            first = tick
            out["first_wave_state"] = completion_state(g)
            break
    out["first_wave_after_ticks"] = first
    out["fresh_break_t"] = 1.6
    return out


def case_freeze():
    """Pause and hitstop freeze the wave machine: the spawn timer and the break timer do not move (real `Game.update`)."""
    out = {}
    random.seed(12)
    g = fresh()
    g.wave = 3
    g.in_wave = True
    g.spawn_queue = [("husk", None)] * 4
    g.spawn_timer = 1.0
    g.update(DT)
    base_timer = g.spawn_timer
    g.paused = True
    for _ in range(60):
        g.update(DT)
    paused_timer = g.spawn_timer
    g.paused = False
    g.hitstop = 0.5
    for _ in range(20):
        g.update(DT)
    hitstop_timer = g.spawn_timer
    g.hitstop = 0.0
    g.update(DT)
    out["spawn_timer"] = dict(before=r(base_timer, 6), paused=r(paused_timer, 6), hitstop=r(hitstop_timer, 6), after=r(g.spawn_timer, 6))
    g = fresh()
    g.wave = 3
    g.in_wave = False
    g.break_t = 2.0
    g.update(DT)
    before = g.break_t
    g.paused = True
    for _ in range(60):
        g.update(DT)
    paused = g.break_t
    g.paused = False
    g.hitstop = 0.5
    for _ in range(20):
        g.update(DT)
    hitstop = g.break_t
    g.hitstop = 0.0
    g.slowmo = 5.0
    g.slowmo_scale = 0.3
    g.update(DT)
    slowed = before - g.break_t
    out["break_timer"] = dict(before=r(before, 6), paused=r(paused, 6), hitstop=r(hitstop, 6), slowed_step=r(hitstop - g.break_t, 8), normal_step=r(DT, 8))
    return out


def case_death_and_restart():
    out = {}
    random.seed(13)
    g = fresh()
    g.wave = 3
    g.in_wave = True
    g.spawn_queue = [("husk", None)] * 5
    g.spawn_timer = 0.0
    g.markers.append(NS["Marker"]("husk", V(100, 100), None))
    e = Enemy("husk", V(2000, 1700), 3)
    e.speed = 0.0
    g.enemies.append(e)
    g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    queue_before, marker_t = len(g.spawn_queue), g.markers[0].t
    for _ in range(120):
        g.update(DT)
    out["dead"] = dict(dead=g.player.dead, queue_before=queue_before, queue_after=len(g.spawn_queue), marker_t_before=r(marker_t, 6),
                       marker_t_after=r(g.markers[0].t, 6), markers=len(g.markers), enemies=len(g.enemies), in_wave=g.in_wave, wave=g.wave)
    # the dead player's last enemy cannot complete a wave: nothing happens even with an empty field
    g = fresh()
    g.wave = 3
    g.in_wave = True
    g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    for _ in range(300):
        g.update(DT)
    out["dead_empty_field"] = dict(in_wave=g.in_wave, wave=g.wave, banner=None if g.banner is None else g.banner[0])
    # a restart (`Game.reset`): everything run-owned goes back to the start
    random.seed(14)
    g = fresh()
    g.wave = 6
    g.in_wave = True
    g.kills, g.combo, g.best_combo, g.combo_t = 40, 12, 18, 1.0
    g.spawn_queue = [("husk", None)] * 4
    g.markers.append(NS["Marker"]("husk", V(100, 100), None))
    g.enemies.append(Enemy("husk", V(2000, 1700), 6))
    g.projectiles.append(NS["Projectile"](V(10, 10), V(1, 0)))
    g.pickups.append(NS["Pickup"]("fang", 0, "fire", V(10, 10)))
    g.banner = ["WAVE 6", "x", 2.0]
    g.reset()
    out["reset"] = dict(wave=g.wave, in_wave=g.in_wave, break_t=g.break_t, kills=g.kills, combo=g.combo, best_combo=g.best_combo, combo_t=g.combo_t,
                        queue=len(g.spawn_queue), markers=len(g.markers), enemies=len(g.enemies), projectiles=len(g.projectiles),
                        pickups=len(g.pickups), motes=len(g.motes), banner=g.banner, spawn_timer=g.spawn_timer, hp=g.player.hp, dead=g.player.dead)
    return out


def case_normal_first_wave():
    """The prototype's own normal run against its first wave, ARMING ON (the earlier default-loadout capture, case `default_wave`
    in capture_converge.py, disarmed it): the default loadout with its conditions on, the player standing still, once with no
    input and once with a Converge at the nearest enemy every 3 s. The first wave arms its first two enemies for sure, so the
    run ends with swords lying about. Crits roll as in the game (12%). Spawn points, arming and the Fang's recoil are random, so the
    Godot checks compare a band."""
    out = {}
    for name, converge_every in (("no_input", 0), ("converge_every_3s", 180)):
        results = []
        for seed in range(1, 9):
            random.seed(seed)
            g = base.new_game()
            del g.afflict  # the shared helper switches conditions off; this case plays the prototype's own
            assert g.afflict.__func__ is Game.afflict
            g.in_wave = False
            g.break_t = 1.6
            base.hold()
            assert [sw.kind for sw in g.swords] == ["fang", "blade", "colossus"]
            t_real = 0.0
            cleared_at = None
            converged = 0
            armed_at_start = None
            for n in range(round(90.0 / DT)):
                if converge_every and n % converge_every == converge_every - 1 and g.enemies:
                    before = g.converge_cd
                    g.converge(g.auto_aim())
                    converged += 1 if before <= 0 else 0
                was_wave = g.wave
                g.update(DT)
                t_real += DT
                if g.wave == 1 and was_wave == 0:
                    armed_at_start = [a for _, a in g.spawn_queue if a is not None]
                    first = g.spawn_queue[0]
                if g.wave >= 1 and not g.in_wave and g.banner and g.banner[0] == "WAVE CLEARED" and cleared_at is None:
                    cleared_at = t_real
                    break
                if g.player.dead:
                    break
            results.append(dict(seed=seed, cleared_at=None if cleared_at is None else r(cleared_at, 2), died=g.player.dead, hp=r(g.player.hp, 1), kills=g.kills,
                                converged=converged, armed_enemies=len(armed_at_start), first_enemy_sword=first[1][0], first_enemy_armed=first[1] is not None,
                                swords_lying=len(g.pickups)))
        out[name] = results
    return out


# ------------------------------------------------------------------ kills, combos, chain text and healing
def kill_game():
    g = fresh()
    base.hold()
    return g


def case_kills():
    """`Game.kill` and the combo's decay: the counters after each kill, the chain announcement at 10, 25, 50 and 100, how long a
    chain lives, and that a later kill inside the window extends it."""
    out = {}
    random.seed(21)
    g = kill_game()
    chain_texts = []
    trace = []
    for n in range(1, 131):
        e = Enemy("husk", V(2200.0, 1700.0), 1)
        before = len(g.texts)
        g.kill(e, V(1, 0), False)
        if len(g.texts) > before:
            t = g.texts[-1]
            chain_texts.append(dict(combo=g.combo, life=r(t.life, 3), vx=r(t.vel.x), vy=r(t.vel.y), dx=r(t.pos.x - g.player.pos.x), dy=r(t.pos.y - g.player.pos.y), size=None))
        if n in (1, 2, 3, 9, 10, 11, 24, 25, 50, 99, 100, 130):
            trace.append(dict(n=n, kills=g.kills, combo=g.combo, best=g.best_combo, combo_t=g.combo_t, motes=len(g.motes)))
    out["trace"] = trace
    out["chain_texts"] = chain_texts
    # the sizes and colours of the announcement through the real `Game.text` (recorded through a stand-in font)
    log = []
    g = kill_game()
    g.fonts = drops._Fonts(log)
    g.combo = 9
    g.kill(Enemy("husk", V(2200.0, 1700.0), 1), V(1, 0), False)
    out["chain_text_draw"] = [e for e in log if "CHAIN" in e["text"]]
    # decay: a single kill, then ticks until the chain resets
    g = kill_game()
    g.kill(Enemy("husk", V(2200.0, 1700.0), 1), V(1, 0), False)
    reset_at = None
    for tick in range(1, 400):
        g.update(DT)
        if g.combo == 0 and reset_at is None:
            reset_at = tick
    out["decay"] = dict(combo_after_kill=1, reset_at_tick=reset_at, kills=g.kills, best=g.best_combo)
    # a second kill inside the window restarts the clock
    g = kill_game()
    g.kill(Enemy("husk", V(2200.0, 1700.0), 1), V(1, 0), False)
    for _ in range(120):
        g.update(DT)
    mid = g.combo
    g.kill(Enemy("husk", V(2200.0, 1700.0), 1), V(1, 0), False)
    out["extend"] = dict(combo_mid=mid, combo_after=g.combo, combo_t_after=g.combo_t)
    # best chain survives a decay
    g = kill_game()
    for _ in range(5):
        g.kill(Enemy("husk", V(2200.0, 1700.0), 1), V(1, 0), False)
    for _ in range(200):
        g.update(DT)
    out["best_kept"] = dict(combo=g.combo, best=g.best_combo, kills=g.kills)
    return out


def case_healing():
    """Healing in a run: each kill leaves three motes and a mote that reaches the player heals half a point (real `Game.kill`
    and `Game.update`), up to the maximum; none heals a dead player."""
    out = {}
    random.seed(22)
    g = kill_game()
    g.player.hp = 50.0
    e = Enemy("husk", V(PLAYER[0] + 40.0, PLAYER[1]), 1)
    g.kill(e, V(1, 0), False)
    motes = len(g.motes)
    for _ in range(240):
        g.update(DT)
    out["one_kill"] = dict(motes_per_kill=motes, hp_after=r(g.player.hp, 3), motes_left=len(g.motes))
    g = kill_game()
    g.player.hp = 99.8
    g.kill(Enemy("husk", V(PLAYER[0] + 40.0, PLAYER[1]), 1), V(1, 0), False)
    for _ in range(240):
        g.update(DT)
    out["capped"] = dict(hp_after=r(g.player.hp, 3), max=g.player.maxhp)
    g = kill_game()
    g.player.hp = 50.0
    g.kill(Enemy("husk", V(PLAYER[0] + 40.0, PLAYER[1]), 1), V(1, 0), False)
    g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    for _ in range(240):
        g.update(DT)
    out["dead_not_healed"] = dict(hp_after=r(g.player.hp, 3), dead=g.player.dead)
    return out


# ------------------------------------------------------------------ what the heads-up shows
class _Fonts(drops._Fonts):
    pass


def hud_texts(setup):
    g = fresh()
    log = []
    g.fonts = drops._Fonts(log)
    setup(g)
    g.help_t = 0.0
    try:
        g.draw()
    except Exception as exc:  # pragma: no cover - the capture says so rather than hiding it
        raise AssertionError("Game.draw failed through the stand-in font: %r" % (exc,))
    return log


def case_hud():
    """The wave, kill and chain texts `Game.draw` draws, the banner (title, line, fade) and the game-over statistics, recorded
    through a stand-in font so each text, its size and colour is the prototype's own."""
    out = {}

    def running(g):
        g.wave, g.kills, g.combo, g.combo_t = 7, 123, 5, 1.3

    log = hud_texts(running)
    out["running"] = [e for e in log if e["text"].startswith(("WAVE", "kills", "x"))]

    def no_combo(g):
        g.wave, g.kills, g.combo = 0, 0, 2

    log = hud_texts(no_combo)
    out["start"] = [e for e in log if e["text"].startswith(("WAVE", "kills", "x"))]

    def banner(g):
        g.wave = 4
        g.banner = ["WAVE 4", "armed foes carry swords - kill them and claim one", 2.4]

    log = hud_texts(banner)
    out["banner"] = [e for e in log if e["size"] in (88, 26) and (e["text"].startswith("WAVE") or "armed" in e["text"])]

    def dead(g):
        g.wave, g.kills, g.best_combo = 9, 211, 37
        g.player.hp = 0
        g.player.dead = True
        g.death_t = 2.0

    log = hud_texts(dead)
    out["game_over"] = [e for e in log if e["text"].startswith(("THE SWORDS", "wave", "press R", "tap"))]
    return out


def case_banners():
    """The two banners the wave machine sets, through the real `start_wave` and `update_waves`."""
    random.seed(30)
    g = fresh()
    g.start_wave()
    started = list(g.banner)
    g = fresh()
    g.wave = 3
    g.in_wave = True
    g.update_waves(DT)
    cleared = list(g.banner)
    return dict(started=started, cleared=cleared)


def main():
    cases = dict(table=case_table(), kind_draws=case_kind_draws(), hp=case_hp(), timing=case_timing(), spawn_points=case_spawn_points(),
                 distribution=case_distribution(), first_wave=case_first_wave(), waits=case_waits(), clear_and_break=case_clear_and_break(),
                 freeze=case_freeze(), death_and_restart=case_death_and_restart(), normal_first_wave=case_normal_first_wave(), kills=case_kills(), healing=case_healing(), hud=case_hud(),
                 banners=case_banners())
    cases["fixture_scope"] = dict(swords_parked=True, converge_used=False, conditions_applied=False, random_streams_matched=False,
                                  scripted_draws_used_for_exact_cases=True, distributions_are_statistical=True)
    text = drops.dumps(cases)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
