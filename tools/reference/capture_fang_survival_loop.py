#!/usr/bin/env python3
"""Captures focused reference cases from the Python prototype (the oracle).

Usage:  python3 -I tools/reference/capture_fang_survival_loop.py [out.json]
        (the committed copy is godot/tests/reference/fang_survival_loop.json)

It loads `game/main.py` without starting its main loop (the module source is cut
at `async def main`), drives the real `Game`/`Player`/`Sword`/`Enemy` classes with
fixed timesteps under SDL's dummy video/audio drivers, and prints the numbers
quoted in `docs/reference/fang-survival-loop.md`. Needs `pygame`. Randomness
that the prototype consumes (crit rolls, spawn positions, sword start cooldowns)
is controlled per case so the numbers are repeatable.
"""
import json
import math
import os
import random
import sys
from pathlib import Path

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")

import pygame  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def load_prototype():
    source = (ROOT / "game" / "main.py").read_text()
    cut = source.index("async def main():")
    namespace = {"__name__": "swordster_reference"}
    exec(compile(source[:cut], "game/main.py", "exec"), namespace)
    return namespace


NS = load_prototype()
V = NS["V"]
Game = NS["Game"]
Sword = NS["Sword"]
Enemy = NS["Enemy"]
WORLD = NS["WORLD"]
W, H = NS["W"], NS["H"]
DT = 1.0 / 60.0


class Keys(dict):
    def __missing__(self, key):
        return 0


def new_game(swords=None):
    pygame.init()
    screen = pygame.display.set_mode((W, H))
    game = Game(screen)
    game.sfx.sounds = {}
    # Elemental conditions (burn/poison/chill) are not part of this slice; the
    # reference measures the physical hit only.
    game.afflict = lambda *args, **kwargs: None
    # Keep the wave machine out of the way unless a case wants it.
    game.in_wave = False
    game.break_t = 1e9
    if swords is not None:
        c = game.player.pos
        game.swords = [Sword(kind, 0, element, c) for kind, element in swords]
    return game


KEYS = Keys()


def hold(*names):
    KEYS.clear()
    for name in names:
        KEYS[getattr(pygame, "K_" + name)] = 1
    pygame.key.get_pressed = lambda: KEYS


def run(game, seconds, dt=DT):
    n = round(seconds / dt)
    for _ in range(n):
        game.update(dt)


def r(x, n=3):
    return round(float(x), n)


# ------------------------------------------------------------------ cases
def case_movement():
    out = {}
    for dt in (1 / 60, 1 / 30, 1 / 120):
        g = new_game(swords=[])
        hold("d")
        trace = {}
        for step in range(1, round(2.0 / dt) + 1):
            g.update(dt)
            t = round(step * dt, 4)
            if t in (0.25, 0.5, 1.0, 2.0):
                trace[str(t)] = dict(x=r(g.player.pos.x - WORLD.centerx), vx=r(g.player.vel.x),
                                     cam_x=r(g.cam.x - WORLD.centerx), cam_lead=r(g.cam.x - g.player.pos.x))
        out["dt_%.4f" % dt] = trace
    # diagonal speed and facing
    g = new_game(swords=[])
    hold("d", "s")
    run(g, 2.0)
    out["diagonal_speed_after_2s"] = r(g.player.vel.length())
    out["diagonal_facing"] = [r(g.player.facing.x, 4), r(g.player.facing.y, 4)]
    # wall clamp and camera clamp at the east wall
    g = new_game(swords=[])
    hold("d")
    run(g, 12.0)
    out["east_wall"] = dict(player_x=r(g.player.pos.x), cam_x=r(g.cam.x), cam_x_limit=WORLD.right - W / 2 + 140)
    g = new_game(swords=[])
    hold("w", "a")
    run(g, 12.0)
    out["north_west_wall"] = dict(player=[r(g.player.pos.x), r(g.player.pos.y)], cam=[r(g.cam.x), r(g.cam.y)],
                                  cam_limit=[WORLD.left + W / 2 - 140, WORLD.top + H / 2 - 140])
    # stopping: velocity decay after releasing
    g = new_game(swords=[])
    hold("d")
    run(g, 1.0)
    hold()
    trace = {}
    for step in range(1, 61):
        g.update(DT)
        if step in (6, 12, 30):
            trace[str(round(step * DT, 3))] = r(g.player.vel.x)
    out["release_velocity"] = trace
    return out


def case_dash():
    out = {}
    for dt in (1 / 60, 1 / 30, 1 / 120):
        g = new_game(swords=[])
        hold()
        g.player.facing = V(1, 0)
        start = V(g.player.pos)
        g.player.dash(g)
        dash_ticks = 0
        trace = {}
        for step in range(1, round(1.0 / dt) + 1):
            g.update(dt)
            if g.player.dash_t > 0:
                dash_ticks = step
            t = round(step * dt, 4)
            if t in (0.14, 0.2, 0.3, 0.5, 1.0):
                trace[str(t)] = dict(dx=r(g.player.pos.x - start.x), vx=r(g.player.vel.x))
        out["dt_%.4f" % dt] = dict(trace=trace, dash_motion_ticks=dash_ticks + 1,
                                   iframes_after=r(g.player.iframes), dash_cd_after_1s=r(g.player.dash_cd))
    # direction: held movement wins over facing; without movement facing is used
    g = new_game(swords=[])
    hold("w", "a")
    run(g, 0.5)
    g.player.dash(g)
    v = g.player.vel
    out["dash_diagonal_velocity"] = [r(v.x), r(v.y)]
    g = new_game(swords=[])
    hold("a")
    run(g, 0.3)
    hold()
    run(g, 0.1)
    g.player.dash(g)  # no keys held now; facing is left
    out["dash_uses_facing_when_idle"] = [r(g.player.vel.x), r(g.player.vel.y)]
    # invulnerability window and cooldown gating
    g = new_game(swords=[])
    hold()
    g.player.dash(g)
    out["iframes_at_dash"] = r(g.player.iframes)
    out["cooldown_at_dash"] = r(g.player.dash_cd)
    gating = {}
    for secs in (0.5, 0.6, 0.64, 0.66, 0.7):
        g2 = new_game(swords=[])
        hold()
        g2.player.dash(g2)
        run(g2, secs)
        before = g2.player.dash_t
        g2.player.dash(g2)
        gating[str(secs)] = "accepted" if g2.player.dash_t > before else "refused"
    out["dash_gating"] = gating
    # dead players cannot dash
    g = new_game(swords=[])
    g.player.dead = True
    g.player.dash(g)
    out["dead_dash_cooldown"] = r(g.player.dash_cd)
    return out


def husk_at(game, offset, wave=1):
    e = Enemy("husk", game.player.pos + V(offset), wave)
    e.speed = 92.0  # remove the 0.9-1.12 random speed factor
    game.enemies.append(e)
    return e


def case_damage():
    out = {}
    g = new_game(swords=[])
    hold()
    husk_at(g, (20, 0))
    g.update(DT)
    out["first_contact"] = dict(hp=g.player.hp, iframes=r(g.player.iframes), hitstop=r(g.hitstop),
                                shake_trauma=r(g.trauma), player_vel=[r(g.player.vel.x), r(g.player.vel.y)])
    # time between hits while a husk keeps touching
    g = new_game(swords=[])
    hold()
    e = husk_at(g, (20, 0))
    hits = []
    last = g.player.hp
    t_real = 0.0
    for _ in range(round(4.0 / DT)):
        g.update(DT)
        t_real += DT
        if g.player.hp < last:
            hits.append(dict(t_real=r(t_real, 3), time=r(g.time, 3), hp=g.player.hp))
            last = g.player.hp
        # keep the husk parked on the player so every iframe expiry is a hit
        e.pos = V(g.player.pos + V(20, 0))
        e.stun = 0
        if g.player.dead:
            break
    out["contact_hit_sequence_first_6"] = hits[:6]
    # death
    g = new_game(swords=[])
    hold()
    e = husk_at(g, (20, 0))
    g.player.hp = 10.0
    death_real = None
    t_real = 0.0
    for _ in range(round(6.0 / DT)):
        g.update(DT)
        t_real += DT
        if g.player.dead and death_real is None:
            death_real = t_real
            out["death"] = dict(hp=g.player.hp, slowmo=g.slowmo, slowmo_scale=g.slowmo_scale, death_t=g.death_t,
                                hitstop=r(g.hitstop))
        if g.player.dead and g.death_t > 0.8 and "restart_eligible_real_s_after_death" not in out:
            out["restart_eligible_real_s_after_death"] = r(t_real - death_real, 3)
    # frozen/dead contact: after death enemies do not hurt again
    out["hp_after_death"] = g.player.hp
    return out


def case_death_wander():
    """After the player dies, husks stop chasing and drift (game/main.py Enemy.update).

    The drift direction is polar(t * 0.3 + id(self) % 7, speed * 0.3): its phase
    depends on object identity, so the case records only quantities that do not
    depend on that phase (speed, distance from the start, and how far the heading
    turns), which is also all a port can reproduce.
    """
    out = {}
    g = new_game(swords=[])
    hold()
    e = husk_at(g, (300, 0))
    e.t = 0.0
    g.player.dead = True
    start = V(e.pos)
    checkpoints = {30: "0.5", 60: "1.0", 120: "2.0", 180: "3.0"}
    samples = {}
    headings = {}
    for i in range(1, 181):
        e.update(g, DT)
        if i in checkpoints:
            samples[checkpoints[i]] = dict(speed=r(e.vel.length(), 4), distance=r((e.pos - start).length(), 4))
            headings[checkpoints[i]] = math.atan2(e.vel.y, e.vel.x)
    out["samples"] = samples
    turn = headings["3.0"] - headings["1.0"]
    out["heading_turn_1s_to_3s_rad"] = r((turn + math.pi) % (2 * math.pi) - math.pi, 4)
    out["target_speed"] = r(e.speed * 0.3, 4)
    return out


def case_hitstop_slowmo():
    out = {}
    g = new_game(swords=[])
    hold("d")
    g.hitstop = 0.05
    t0 = g.time
    frozen = 0
    while g.hitstop > 0:
        g.update(DT)
        frozen += 1
    out["hitstop_0.05_frozen_updates"] = frozen
    out["time_advanced_during_hitstop"] = r(g.time - t0)
    g = new_game(swords=[])
    hold()
    g.hitstop = 0.02
    n = 0
    while g.hitstop > 0:
        g.update(DT)
        n += 1
    out["hitstop_0.02_frozen_updates"] = n
    # slowmo: scaled time vs real time, 0.5 s of real time
    g = new_game(swords=[])
    hold()
    g.slowmo, g.slowmo_scale = 1.4, 0.25
    run(g, 0.5)
    out["slowmo_0.5s_real"] = dict(real_time=r(g.real_time), scaled_time=r(g.time), slowmo_left=r(g.slowmo))
    g = new_game(swords=[])
    hold()
    g.slowmo, g.slowmo_scale = 1.4, 0.25
    run(g, 2.0)
    out["slowmo_2s_real"] = dict(real_time=r(g.real_time), scaled_time=r(g.time), slowmo_left=r(g.slowmo))
    # paused: nothing advances
    g = new_game(swords=[])
    hold("d")
    g.paused = True
    run(g, 1.0)
    out["paused_1s"] = dict(real_time=r(g.real_time), time=r(g.time), x=r(g.player.pos.x - WORLD.centerx))
    # trauma decays in real time even during hitstop
    g = new_game(swords=[])
    g.trauma = 1.0
    g.hitstop = 0.5
    run(g, 0.25)
    out["trauma_after_0.25s_hitstop"] = r(g.trauma)
    return out


def case_motes():
    out = {}
    g = new_game(swords=[])
    hold()
    g.player.hp = 50.0
    for _ in range(3):
        g.motes.append(NS["Mote"](g.player.pos + V(60, 0)))
    run(g, 2.0)
    out["three_motes_from_50"] = dict(hp=g.player.hp, motes_left=len(g.motes))
    g = new_game(swords=[])
    hold()
    g.player.hp = 99.8
    for _ in range(3):
        g.motes.append(NS["Mote"](g.player.pos + V(60, 0)))
    run(g, 2.0)
    out["three_motes_from_99.8"] = dict(hp=g.player.hp, motes_left=len(g.motes))
    g = new_game(swords=[])
    hold()
    g.player.hp = 100.0
    g.motes.append(NS["Mote"](g.player.pos + V(40, 0)))
    run(g, 2.0)
    out["mote_at_full_health"] = dict(hp=g.player.hp, motes_left=len(g.motes))
    g = new_game(swords=[])
    hold()
    g.player.hp = 0.0
    g.player.dead = True
    g.motes.append(NS["Mote"](g.player.pos + V(40, 0)))
    run(g, 2.0)
    out["mote_when_dead"] = dict(hp=g.player.hp, motes_left=len(g.motes))
    return out


def fang_game(n_swords=3):
    g = new_game(swords=[("fang", "poison"), ("fang", "ice"), ("fang", "fire")][:n_swords])
    for s in g.swords:
        s.cd = 0.4  # controlled start (the prototype draws uniform(0.2, 0.6))
    return g


class NoCrit:
    """Context manager forcing every crit roll to fail (or always succeed)."""

    def __init__(self, crit):
        self.crit = crit

    def __enter__(self):
        self.orig = random.random
        random.random = (lambda: 0.0) if self.crit else (lambda: 0.99)

    def __exit__(self, *exc):
        random.random = self.orig


def case_fang():
    out = {}
    fang = NS["SWORD_TYPES"]["fang"]
    out["fang_constants"] = {k: v for k, v in fang.items() if k != "ult"}
    # one Fang, one stationary husk 100 px away: strike timeline
    runs = []
    for seed in range(1, 9):
        random.seed(seed)
        with NoCrit(False):
            g = fang_game(1)
            e = husk_at(g, (100, 0))
            e.speed = 0.0
            hold()
            s = g.swords[0]
            log = []
            hit_times = []
            prev_state = s.state
            hp_prev = e.hp
            t_real = 0.0
            for _ in range(round(4.0 / DT)):
                g.update(DT)
                t_real += DT
                if s.state != prev_state:
                    log.append(dict(t=r(t_real, 3), state=f"{prev_state}->{s.state}"))
                    prev_state = s.state
                if e.hp != hp_prev:
                    log.append(dict(t=r(t_real, 3), hit=hp_prev - e.hp, hp=e.hp))
                    hit_times.append(r(t_real, 3))
                    hp_prev = e.hp
                if e.dead:
                    log.append(dict(t=r(t_real, 3), event="dead", kills=g.kills, motes=len(g.motes)))
                    break
            runs.append(dict(seed=seed, hit_times=hit_times, death_time=r(t_real, 3), log=log))
    out["one_fang_one_husk_timeline_seed1"] = runs[0]["log"]
    out["one_fang_one_husk_hit_times_by_seed"] = {str(x["seed"]): x["hit_times"] for x in runs}
    out["one_fang_one_husk_death_times"] = [x["death_time"] for x in runs]
    intervals = [b - a for x in runs for a, b in zip(x["hit_times"], x["hit_times"][1:])]
    out["one_fang_hit_interval_min_max"] = [r(min(intervals), 3), r(max(intervals), 3)]
    out["one_fang_first_hit_times"] = sorted({x["hit_times"][0] for x in runs})
    # damage values
    with NoCrit(False):
        g = fang_game(1)
        e = husk_at(g, (30, 0))
        g.hit_enemy(e, g.swords[0].damage, V(1, 0), fang["knock"], g.swords[0])
        out["common_hit"] = dict(damage=30 - e.hp, vel=[r(e.vel.x), r(e.vel.y)], stun=r(e.stun),
                                 hitstop=r(g.hitstop), trauma=r(g.trauma))
    with NoCrit(True):
        g = fang_game(1)
        e = husk_at(g, (30, 0))
        g.hit_enemy(e, g.swords[0].damage, V(1, 0), fang["knock"], g.swords[0])
        out["crit_hit"] = dict(damage=30 - e.hp, vel=[r(e.vel.x), r(e.vel.y)], stun=r(e.stun),
                               hitstop=r(g.hitstop), trauma=r(g.trauma))
    rounding = {}
    with NoCrit(False):
        for rarity in (0, 1, 2):
            g = fang_game(1)
            sw = Sword("fang", rarity, "fire", g.player.pos)
            e = husk_at(g, (30, 0))
            e.hp = e.maxhp = 1000.0
            g.hit_enemy(e, sw.damage, V(1, 0), fang["knock"], sw)
            rounding["rarity%d" % rarity] = dict(sword_damage=r(sw.damage), dealt=1000 - e.hp)
    with NoCrit(True):
        for rarity in (0, 1, 2):
            g = fang_game(1)
            sw = Sword("fang", rarity, "fire", g.player.pos)
            e = husk_at(g, (30, 0))
            e.hp = e.maxhp = 1000.0
            g.hit_enemy(e, sw.damage, V(1, 0), fang["knock"], sw)
            rounding["rarity%d_crit" % rarity] = dict(sword_damage=r(sw.damage), dealt=1000 - e.hp)
    out["rounding"] = rounding
    # acquisition range
    ranges = {}
    with NoCrit(False):
        for dist in (150, 190, 192, 195):
            g = fang_game(1)
            e = husk_at(g, (dist, 0))
            e.speed = 0.0
            hold()
            run(g, 1.0)
            ranges[str(dist)] = "engaged" if e.hp < e.maxhp else "ignored"
    out["acquire_range_175_plus_radius_16_is_191"] = ranges
    # the whole small wave against three Fangs, no player movement
    return out


def case_wave():
    out = {}
    random.seed(7)
    g = new_game(swords=[("fang", "poison"), ("fang", "ice"), ("fang", "fire")])
    g.in_wave = False
    g.break_t = 1.6
    hold()
    g.sfx.sounds = {}
    t_real = 0.0
    markers_seen = {}
    spawn_t = []
    start_t = None
    seen_enemies = set()
    for _ in range(round(8.0 / DT)):
        g.update(DT)
        t_real += DT
        if g.wave == 1 and start_t is None:
            start_t = t_real
            out["wave1_queue_kinds"] = [k for k, _a in g.spawn_queue]
            out["wave1_armed_first_two"] = [bool(a) for _k, a in g.spawn_queue][:2]
        for m in g.markers:
            markers_seen.setdefault(id(m), t_real)
        for e in g.enemies:
            if id(e) not in seen_enemies:
                seen_enemies.add(id(e))
                spawn_t.append(r(t_real, 3))
    out["wave1_start_real_s"] = r(start_t or -1, 3)
    out["wave1_marker_times"] = sorted(r(v, 3) for v in markers_seen.values())
    out["wave1_enemy_spawn_times"] = spawn_t
    out["wave1_enemy_hp_if_unarmed"] = 30.0
    out["marker_telegraph_s"] = 0.7
    out["spawn_spacing_formula"] = "max(0.12, 0.42 - wave*0.02)"
    out["enemy_count_wave1"] = 5 + 1 * 3
    return out


def disarm_waves(game):
    """Make the prototype's wave spawner produce unarmed foes only.

    `start_wave` arms the first two foes of wave 1 unconditionally and the rest
    by `ENEMY_TYPES[kind]["armed"]`; an armed foe has 1.35x health and drops a
    sword, none of which exists in the Godot slice yet. The prototype rolls
    that arming first, so the random stream is consumed exactly as in the game;
    only the result is discarded, before any marker or enemy is created.
    """
    original = game.start_wave

    def start_wave():
        original()
        game.spawn_queue = [(kind, None) for kind, _armed in game.spawn_queue]

    game.start_wave = start_wave


def assert_all_unarmed(game, wave_one_husk_hp):
    """The fixture must really be unarmed: stop the capture if anything is not."""
    for marker in game.markers:
        assert marker.armed is None, "armed spawn marker in the unarmed fixture"
    for enemy in game.enemies:
        assert enemy.armed is None, "armed enemy in the unarmed fixture"
        assert enemy.kind == "husk" and enemy.maxhp == wave_one_husk_hp, (enemy.kind, enemy.maxhp)


def case_survival():
    """Three Fangs vs the first wave (husks only, nothing armed), player stationary."""
    out = {}
    results = []
    for seed in range(1, 9):
        random.seed(seed)
        g = new_game(swords=[("fang", "poison"), ("fang", "ice"), ("fang", "fire")])
        disarm_waves(g)
        g.in_wave = False
        g.break_t = 1.6
        hold()
        t_real = 0.0
        cleared_at = None
        husks_seen = set()
        for _ in range(round(60.0 / DT)):
            g.update(DT)
            t_real += DT
            assert_all_unarmed(g, 30.0)
            husks_seen.update(id(e) for e in g.enemies)
            if g.wave >= 1 and not g.in_wave and g.banner and g.banner[0] == "WAVE CLEARED" and cleared_at is None:
                cleared_at = t_real
                break
            if g.player.dead:
                break
        results.append(dict(seed=seed, cleared_at=None if cleared_at is None else r(cleared_at, 2),
                            died=g.player.dead, hp=r(g.player.hp, 1), kills=g.kills,
                            husks_spawned=len(husks_seen), armed_enemies=0))
    out["wave1_three_fangs_stationary_player"] = results
    return out


def main():
    cases = dict(
        movement=case_movement(), dash=case_dash(), damage=case_damage(), death_wander=case_death_wander(), time_scale=case_hitstop_slowmo(),
        motes=case_motes(), fang=case_fang(), wave=case_wave(), survival=case_survival(),
    )
    text = json.dumps(cases, indent=2, sort_keys=False)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
