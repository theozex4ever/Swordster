#!/usr/bin/env python3
"""Captures focused reference cases for runners, brutes, crowds and walls.

Usage:  python3 -I tools/reference/capture_crowd_and_walls.py [out.json]
        (the committed copy is godot/tests/reference/crowd_and_walls.json)

Slice #9 of the Godot port. Like capture_fang_survival_loop.py (whose loader and
helpers it reuses) it drives the prototype's REAL classes -- `Game`, `Enemy`,
`Player`, `Sword` from game/main.py -- with fixed 1/60 s steps under SDL's dummy
drivers. Nothing here re-implements a rule: separation, bowling and wall slams
are read off the prototype's own `Game.update`.

Mechanics outside this slice are switched off, and the capture asserts that:
  * `afflict` (elemental conditions) is a no-op,
  * every enemy it creates is unarmed (`armed is None`) -- armed foes carry a
    1.35x health bonus and drop swords (issue #17),
  * only husks, runners and brutes appear (spitters and projectiles are #10),
  * the player never holds a sword in these cases, so no ultimate or Converge
    can run.
Per-case controls: enemy speed and `t` are pinned (the prototype draws
uniform(0.9, 1.12) and uniform(0, 10)); crit rolls are forced where a hit is made.
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
WORLD = base.WORLD
DT = base.DT
r = base.r
hold = base.hold
new_game = base.new_game
NoCrit = base.NoCrit
ENEMY_TYPES = NS["ENEMY_TYPES"]
KINDS = ("husk", "runner", "brute")
PLAYER = (1300.0, 900.0)  # the arena centre, where the prototype's player spawns

# Everything created in a case is recorded here so the capture can prove the
# fixture really was unarmed and spitter-free.
_CREATED = []


def foe(g, kind, at, wave=1, vel=(0.0, 0.0), stun=0.0, t=0.0, hp=None, speed=None):
    """An enemy built by the prototype's own constructor, then pinned."""
    assert kind in KINDS, kind
    e = Enemy(kind, V(at), wave)
    assert e.armed is None
    e.speed = float(ENEMY_TYPES[kind]["speed"] if speed is None else speed)
    e.t = float(t)
    e.vel = V(vel)
    e.stun = float(stun)
    if hp is not None:
        e.hp = float(hp)
    # How the Godot side must place the same enemy; written beside every case so
    # the fixtures come from this file rather than from numbers copied twice.
    e.setup = dict(kind=kind, x=r(e.pos.x), y=r(e.pos.y), vx=r(e.vel.x), vy=r(e.vel.y), stun=r(e.stun),
                   hp=r(e.hp), t=r(e.t), wave=wave, speed_scale=0.0 if e.speed == 0.0 else 1.0)
    g.enemies.append(e)
    _CREATED.append(e)
    return e


def snap(e):
    return dict(kind=e.kind, x=r(e.pos.x), y=r(e.pos.y), vx=r(e.vel.x), vy=r(e.vel.y), hp=r(e.hp),
                stun=r(e.stun), dead=bool(e.dead))


def fresh():
    random.seed(1)
    g = new_game(swords=[])
    hold()
    assert (g.player.pos.x, g.player.pos.y) == PLAYER
    return g


def tick(g, n=1):
    for _ in range(n):
        g.update(DT)


# ------------------------------------------------------------------ cases
def case_table():
    out = dict(types={}, wave_health={})
    for kind in KINDS:
        d = ENEMY_TYPES[kind]
        out["types"][kind] = dict(r=d["r"], hp=d["hp"], speed=d["speed"], dmg=d["dmg"], knock=d["knock"])
        out["wave_health"][kind] = {str(w): r(Enemy(kind, V(0, 0), w).maxhp) for w in (1, 2, 3, 5)}
    return out


def case_movement():
    """Enemy alone chasing a stationary player 700 px away; `t` pins the weave phase."""
    out = {}
    marks = {15: "0.25", 30: "0.5", 60: "1.0", 120: "2.0", 180: "3.0"}
    for kind in KINDS:
        for t0 in (0.0, 1.3):
            g = fresh()
            e = foe(g, kind, (PLAYER[0] - 700.0, PLAYER[1] + 120.0), t=t0)
            trace = {}
            for step in range(1, 181):
                tick(g)
                if step in marks:
                    trace[marks[step]] = dict(x=r(e.pos.x - PLAYER[0]), y=r(e.pos.y - PLAYER[1]), vx=r(e.vel.x),
                                              vy=r(e.vel.y), fx=r(e.facing.x, 4), fy=r(e.facing.y, 4))
            out["%s_t%.1f" % (kind, t0)] = dict(setup=[e.setup], trace=trace)
    return out


def case_contact():
    out = {}
    for kind in KINDS:
        g = fresh()
        e = foe(g, kind, (PLAYER[0] + 20.0, PLAYER[1]))
        tick(g)
        first = dict(hp=r(g.player.hp), iframes=r(g.player.iframes), player_vx=r(g.player.vel.x),
                     player_vy=r(g.player.vel.y), enemy_vx=r(e.vel.x), enemy_vy=r(e.vel.y), enemy_stun=r(e.stun),
                     hitstop=r(g.hitstop), trauma=r(g.trauma))
        # a second contact tick during the invulnerability window: no damage, but the enemy is still shoved
        e.pos = V(g.player.pos + V(8, 0))
        e.vel = V(0, 0)
        e.stun = 0.0
        g.hitstop = 0.0
        tick(g)
        refused = dict(hp=r(g.player.hp), enemy_vx=r(e.vel.x), enemy_stun=r(e.stun))
        out[kind] = dict(setup=[e.setup], first_contact=first, refused_contact=refused)
        # parked on the player for 4 s: when does each hit land?
        g = fresh()
        e = foe(g, kind, (PLAYER[0] + 20.0, PLAYER[1]))
        hits = []
        last = g.player.hp
        for step in range(1, 241):
            tick(g)
            if g.player.hp < last:
                hits.append(dict(tick=step, hp=r(g.player.hp)))
                last = g.player.hp
            e.pos = V(g.player.pos + V(20, 0))
            e.stun = 0.0
            if g.player.dead:
                break
        out[kind]["parked_hits"] = hits
    # a lethal brute blow
    g = fresh()
    g.player.hp = 15.0
    lethal = foe(g, "brute", (PLAYER[0] + 30.0, PLAYER[1]))
    tick(g)
    out["brute_lethal"] = dict(setup=[lethal.setup], start_health=15.0, hp=r(g.player.hp), dead=bool(g.player.dead), slowmo=g.slowmo, slowmo_scale=g.slowmo_scale)
    return out


def case_hits():
    """Knockback resistance: the same Fang hit and a heavy Colossus knock on each kind."""
    out = {}
    fang = NS["SWORD_TYPES"]["fang"]
    colossus = NS["SWORD_TYPES"]["colossus"]
    for crit in (False, True):
        for kind in KINDS:
            with NoCrit(crit):
                g = fresh()
                sw = NS["Sword"]("fang", 0, "fire", g.player.pos)
                e = foe(g, kind, (PLAYER[0] + 60.0, PLAYER[1]))
                g.hit_enemy(e, sw.damage, V(1, 0), fang["knock"], sw)
                out["fang_%s_%s" % ("crit" if crit else "hit", kind)] = dict(
                    setup=[e.setup], dealt=r(e.maxhp - e.hp), vx=r(e.vel.x), vy=r(e.vel.y), stun=r(e.stun), hitstop=r(g.hitstop),
                    trauma=r(g.trauma))
    # a launch: the knockback of a heavy Colossus blow, damage removed again
    for kind in KINDS:
        with NoCrit(False):
            g = fresh()
            sw = NS["Sword"]("colossus", 0, "fire", g.player.pos)
            e = foe(g, kind, (PLAYER[0] + 60.0, PLAYER[1]), vel=(0.0, 0.0))
            g.hit_enemy(e, 1.0, V(1, 0), colossus["knock"], sw, heavy=True)
            out["colossus_launch_%s" % kind] = dict(setup=[e.setup], vx=r(e.vel.x), vy=r(e.vel.y), stun=r(e.stun))
    # a launch of an enemy that is already moving (the old velocity keeps 30 %)
    with NoCrit(False):
        g = fresh()
        sw = NS["Sword"]("colossus", 0, "fire", g.player.pos)
        e = foe(g, "husk", (PLAYER[0], PLAYER[1] + 60.0), vel=(100.0, -50.0), stun=0.4)
        g.hit_enemy(e, 1.0, V(0, 1), colossus["knock"], sw, heavy=True)
        out["relaunch_moving_husk"] = dict(setup=[e.setup], vx=r(e.vel.x), vy=r(e.vel.y), stun=r(e.stun))
    return out


def case_fang_vs_brute():
    """One Fang against one brute walking at it: the whole fight, tick by tick."""
    out = {}
    for kind in ("brute", "runner"):
        random.seed(3)
        with NoCrit(False):
            g = base.fang_game(1)
            hold()
            e = foe(g, kind, (PLAYER[0] + 190.0, PLAYER[1]))
            hit_ticks, hp_prev, death = [], e.hp, None
            for step in range(1, 60 * 20 + 1):
                tick(g)
                if e.hp < hp_prev:
                    hit_ticks.append(dict(tick=step, dealt=r(hp_prev - e.hp), hp=r(e.hp)))
                    hp_prev = e.hp
                if e.dead and death is None:
                    death = step
                    break
            out[kind] = dict(setup=[e.setup], hits=hit_ticks, death_tick=death, kills=g.kills, motes=len(g.motes),
                             player_hp=r(g.player.hp))
    return out


def case_separation():
    """Two enemies overlapping, nothing else acting (speed 0, player far away)."""
    out = {}

    def pair(kind_a, kind_b, offset, label, ticks=(1, 2, 30)):
        g = fresh()
        a = foe(g, kind_a, (600.0, 400.0), speed=0.0)
        b = foe(g, kind_b, (600.0 + offset[0], 400.0 + offset[1]), speed=0.0)
        trace = {}
        for step in range(1, max(ticks) + 1):
            tick(g)
            if step in ticks:
                trace[str(step)] = dict(a=snap(a), b=snap(b), distance=r((b.pos - a.pos).length(), 4))
        out[label] = dict(setup=[a.setup, b.setup], trace=trace)

    pair("husk", "husk", (24.0, 0.0), "husk_husk_overlap_8")
    pair("husk", "brute", (30.0, 0.0), "husk_brute_overlap_16")
    pair("brute", "husk", (30.0, 0.0), "brute_husk_overlap_16")
    pair("runner", "brute", (28.0, 12.0), "runner_brute_diagonal")
    pair("runner", "husk", (20.0, -9.0), "runner_husk_diagonal")
    pair("brute", "brute", (50.0, 0.0), "brute_brute_overlap_10")
    pair("husk", "brute", (46.0, 0.0), "husk_brute_exactly_touching")
    pair("husk", "husk", (0.0, 0.0), "husk_husk_coincident")
    pair("husk", "husk", (31.99, 0.0), "husk_husk_just_inside")
    pair("husk", "husk", (32.01, 0.0), "husk_husk_just_outside")
    # a packed crowd resolves over several ticks
    g = fresh()
    crowd = [foe(g, k, (600.0 + 9.0 * (i % 4), 400.0 + 8.0 * (i // 4)), speed=0.0)
             for i, k in enumerate(("husk", "husk", "runner", "brute", "husk", "runner", "husk", "brute", "runner",
                                    "husk", "husk", "runner"))]
    trace = {}
    for step in range(1, 61):
        tick(g)
        if step in (1, 5, 20, 60):
            trace[str(step)] = [snap(e) for e in crowd]
    out["packed_crowd_12"] = dict(setup=[e.setup for e in crowd], trace=trace)
    return out


def case_bowling():
    out = {}

    def launch(kind_l, kind_t, speed, label, stun=0.3, gap=-4.0, away=False, ticks=(1, 2, 10), hp_t=None):
        g = fresh()
        rl, rt = ENEMY_TYPES[kind_l]["r"], ENEMY_TYPES[kind_t]["r"]
        sx = -1.0 if away else 1.0
        launched = foe(g, kind_l, (600.0, 400.0), vel=(speed, 0.0), stun=stun, speed=0.0)
        target = foe(g, kind_t, (600.0 + sx * (rl + rt + gap), 400.0), hp=hp_t, speed=0.0)
        trace = {}
        for step in range(1, max(ticks) + 1):
            tick(g)
            if step in ticks:
                trace[str(step)] = dict(launched=snap(launched), target=snap(target), trauma=r(g.trauma),
                                        hitstop=r(g.hitstop))
        out[label] = dict(setup=[launched.setup, target.setup], trace=trace)

    for kl in KINDS:
        for kt in KINDS:
            launch(kl, kt, 700.0, "%s_into_%s" % (kl, kt))
    # thresholds: the speed is tested after one tick of stun drag (x0.92) and movement
    launch("husk", "husk", 366.0, "just_under_340")
    launch("husk", "husk", 373.0, "just_over_340")
    launch("husk", "husk", 700.0, "not_stunned", stun=0.0)
    launch("husk", "husk", 700.0, "moving_away", away=True)
    launch("husk", "brute", 700.0, "stun_just_left", stun=1 / 60 + 0.001)
    return out


def case_chain_deaths():
    """A launched enemy ploughs into a line of weak ones: every death resolves once.

    Each line is (launcher kind, launch speed, start x, victims as (kind, hp, gap)).
    The wall case ends against the east wall, so a bowled victim is then slammed.
    """
    out = {}
    lines = (
        ("brute_through_runners", "brute", 900.0, 400.0, [("runner", 3, -3), ("runner", 3, -3), ("husk", 3, -3),
                                                         ("runner", 3, -3), ("husk", 3, -3), ("brute", 3, -3)]),
        ("husk_through_runners", "husk", 900.0, 400.0, [("runner", 3, -3)] * 4),
        ("brute_through_spaced_husks", "brute", 1200.0, 400.0, [("husk", 4, 10)] * 8),
        ("brute_through_spaced_runners", "brute", 900.0, 400.0, [("runner", 4, 12)] * 8),
        ("brute_bowls_husk_into_wall", "brute", 1200.0, 2300.0, [("husk", 5, -3), ("husk", 5, 60)]),
    )
    for label, launcher, speed, x0, victims in lines:
        g = fresh()
        kills_log = []
        now = [0]
        original_kill = g.kill

        def logged_kill(e, d, big, _orig=original_kill):
            kills_log.append(dict(tick=now[0], kind=e.kind, already_dead=bool(e.dead)))
            return _orig(e, d, big)

        g.kill = logged_kill
        head = foe(g, launcher, (x0, 400.0), vel=(speed, 0.0), stun=0.6, speed=0.0)
        line = []
        px, pr = x0, head.r
        for kind, hp, gap in victims:
            rr = ENEMY_TYPES[kind]["r"]
            px += pr + rr + gap
            pr = rr
            line.append(foe(g, kind, (px, 400.0), hp=float(hp), speed=0.0))
        record = {}
        for step in range(1, 181):
            now[0] = step
            tick(g)
            if step == 12:
                record = dict(kills_at_12=g.kills, motes_at_12=len(g.motes), combo_at_12=g.combo)
        out[label] = dict(setup=[e.setup for e in [head] + line], **record,
                          kills=g.kills, combo=g.combo, best_combo=g.best_combo, kill_log=kills_log,
                          survivors=len(g.enemies), final=[snap(e) for e in [head] + line])
    return out


def case_wall_slam():
    out = {}
    def inner(rad):
        return dict(west=rad, east=2600.0 - rad, north=rad, south=1800.0 - rad)

    def slam(kind, wall, speed, label, stun=0.6, hp=500.0):
        g = fresh()
        rad = ENEMY_TYPES[kind]["r"]
        edge = inner(rad)
        sx, sy, x, y = 0.0, 0.0, 1000.0, 700.0
        if wall == "east":
            sx, x, y = 1.0, edge["east"] - 1.0, 700.0
        elif wall == "west":
            sx, x, y = -1.0, edge["west"] + 1.0, 700.0
        elif wall == "south":
            sy, x, y = 1.0, 1000.0, edge["south"] - 1.0
        elif wall == "north":
            sy, x, y = -1.0, 1000.0, edge["north"] + 1.0
        elif wall == "corner":
            sx, sy, x, y = 0.7071067811865476, 0.7071067811865476, edge["east"] - 1.0, edge["south"] - 1.0
        e = foe(g, kind, (x, y), vel=(sx * speed, sy * speed), stun=stun, hp=hp, speed=0.0)
        tick(g)
        out[label] = dict(setup=[e.setup], after=snap(e), kills=g.kills,
                          hitstop=r(g.hitstop), trauma=r(g.trauma), motes=len(g.motes))

    for speed in (380.0, 400.0, 410.0, 412.0, 414.0, 420.0, 500.0, 800.0, 1200.0):
        slam("husk", "east", speed, "husk_east_%d" % speed)
    for kind in ("runner", "brute"):
        slam(kind, "east", 800.0, "%s_east_800" % kind)
    for wall in ("west", "south", "north", "corner"):
        slam("husk", wall, 800.0, "husk_%s_800" % wall)
    slam("husk", "east", 800.0, "husk_east_800_not_stunned", stun=0.0)
    slam("husk", "east", 800.0, "husk_east_800_stun_0.05", stun=0.05)
    slam("husk", "east", 800.0, "husk_east_800_stun_5", stun=5.0)
    slam("husk", "east", 800.0, "husk_east_800_lethal", hp=5.0)
    slam("brute", "east", 800.0, "brute_east_800_lethal", hp=10.0)
    slam("runner", "corner", 800.0, "runner_corner_800_lethal", hp=3.0)
    return out


def case_crowd_encounter():
    """The composite: a crowd pinned between the player and the east wall, shoved at tick 0."""
    out = {}
    random.seed(5)
    g = fresh()
    g.player.pos = V(2250.0, 900.0)
    g.cam = V(g.player.pos)
    formation = [
        ("brute", (2420.0, 900.0)), ("brute", (2470.0, 990.0)), ("husk", (2450.0, 815.0)), ("husk", (2500.0, 860.0)),
        ("husk", (2510.0, 945.0)), ("husk", (2420.0, 760.0)), ("runner", (2490.0, 1010.0)), ("runner", (2540.0, 885.0)),
        ("runner", (2442.0, 1045.0)), ("runner", (2435.0, 815.0)), ("runner", (2550.0, 1000.0)),
        ("husk", (2380.0, 1090.0)), ("runner", (2515.0, 925.0)), ("runner", (2530.0, 835.0)),
    ]
    foes = [foe(g, kind, at) for kind, at in formation]
    # the shove: what the Godot slice's dev command applies, built from the prototype's own hit_enemy
    colossus = NS["SWORD_TYPES"]["colossus"]
    sw = NS["Sword"]("colossus", 0, "fire", g.player.pos)
    for e in foes:
        if (e.pos - g.player.pos).length() <= 320.0:
            hp = e.hp
            with NoCrit(False):
                g.hit_enemy(e, 1.0, (e.pos - g.player.pos).normalize(), colossus["knock"], sw, heavy=True)
            e.hp = hp
    g.hitstop = 0.0
    g.trauma = 0.0
    events = []
    index = {id(e): i for i, e in enumerate(foes)}
    orig_kill, orig_slam = g.kill, g.wall_slam
    now = [0]

    def kill(e, d, big):
        events.append(dict(tick=now[0], event="kill", enemy=index[id(e)], already_dead=bool(e.dead)))
        return orig_kill(e, d, big)

    def wall_slam(e, speed):
        events.append(dict(tick=now[0], event="wall_slam", enemy=index[id(e)], speed=r(speed, 2)))
        return orig_slam(e, speed)

    g.kill, g.wall_slam = kill, wall_slam
    marks = (10, 30, 60, 120, 240)
    snaps = {}
    for step in range(1, 241):
        now[0] = step
        tick(g)
        if step in marks:
            snaps[str(step)] = dict(enemies=[snap(e) for e in foes], kills=g.kills, motes=len(g.motes),
                                    player_hp=r(g.player.hp))
    out = dict(player=[2250.0, 900.0], setup=[e.setup for e in foes],
               shove_knock=colossus["knock"], shove_radius=320.0, snapshots=snaps, events=events,
               final_kills=g.kills)
    return out


def assert_fixtures_in_scope():
    for e in _CREATED:
        assert e.armed is None, "armed enemy in an unarmed fixture"
        assert e.kind in KINDS, e.kind
    return dict(enemies_created=len(_CREATED), armed_enemies=0, kinds=list(KINDS), afflict_disabled=True,
                swords_equipped=0)


def main():
    cases = dict(
        table=case_table(), movement=case_movement(), contact=case_contact(), hits=case_hits(),
        fang_vs_one_foe=case_fang_vs_brute(), separation=case_separation(), bowling=case_bowling(),
        chain_deaths=case_chain_deaths(), wall_slam=case_wall_slam(), crowd_encounter=case_crowd_encounter(),
    )
    cases["fixture_scope"] = assert_fixtures_in_scope()
    text = json.dumps(cases, indent=2, sort_keys=False)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
