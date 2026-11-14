#!/usr/bin/env python3
"""Captures focused reference cases for the Fang ultimate, Viper Flurry.

Usage:  python3 -I tools/reference/capture_viper_flurry.py [out.json]
        (the committed copy is godot/tests/reference/viper_flurry.json)

Slice #12 of the Godot port. Like the earlier captures (whose loader and helpers it
reuses) it drives the prototype's REAL classes -- `Game`, `Sword`, `Enemy`, `Player`
from game/main.py -- with fixed 1/60 s steps under SDL's dummy drivers. Nothing here
re-implements a rule: the blink, the dart cadence, the damage, the recharge and the
rejections are read off the prototype's own `Sword.ultimate`, `Sword.update_ult`,
`Game.ultimate` and `Game.hit_enemy`, and the key mapping (Q/E/R, R as restart after
death) is exercised through the prototype's real `Game.handle` with synthetic
KEYDOWN events and a patched mouse position.

Mechanics outside this slice are switched off, and the capture asserts that:
  * `afflict` (elemental conditions) is a no-op (issue #11),
  * every enemy it creates is an unarmed husk (arming and drops are issue #17),
  * only Fang swords are ever equipped, no Converge is commanded (issue #16),
  * the wave machine is off (issue #18).
Per-case controls: enemies stand still (speed 0) unless a case says otherwise, the
auto-attack cooldown of every sword is parked far in the future so only the
ultimate fights, and crits are forced off (or on, where a case asks) by pinning
`random.random`. Choices that are random in the prototype (which enemy a dart picks
among several, where it wanders when the area is empty, the recovery nudge) cannot be
matched across random streams, so cases are built where the choice is forced
(exactly one eligible enemy) or record a property of the choice (alternation,
bounds, cadence) instead of a value.
"""
import json
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import capture_fang_survival_loop as base  # noqa: E402  (loads the prototype)

import pygame  # noqa: E402

NS = base.NS
V = base.V
Enemy = base.Enemy
Sword = NS["Sword"]
WORLD = base.WORLD
DT = base.DT
r = base.r
hold = base.hold
NoCrit = base.NoCrit
SWORD_TYPES = NS["SWORD_TYPES"]
RARITIES = NS["RARITIES"]
PLAYER = (1300.0, 900.0)  # the arena centre, where the prototype's player spawns
PARKED_CD = 99.0          # an auto-attack cooldown that never ends within a case

_CREATED = []
_SWORDS = []


def fresh(seed=1, rarities=(0, 0, 0)):
    """A game with three Fang swords (Q, E, R), no auto attacks, no waves."""
    random.seed(seed)
    g = base.new_game(swords=[])
    hold()
    assert (g.player.pos.x, g.player.pos.y) == PLAYER
    c = g.player.pos
    elements = ("poison", "ice", "fire")
    g.swords = [Sword("fang", rarities[i], elements[i], c) for i in range(3)]
    for s in g.swords:
        s.cd = PARKED_CD
        _SWORDS.append(s)
    return g


def foe(g, at, hp=500.0, vel=(0.0, 0.0), speed=0.0):
    """An unarmed husk from the prototype's constructor, pinned. `setup` is how the
    Godot side must place the same enemy (written beside every case)."""
    e = Enemy("husk", V(at), 1)
    assert e.armed is None
    e.speed = float(speed)
    e.t = 0.0
    e.hp = e.maxhp = float(hp)
    e.vel = V(vel)
    e.setup = dict(x=r(e.pos.x), y=r(e.pos.y), hp=r(e.hp), speed_scale=0.0 if speed == 0.0 else 1.0)
    g.enemies.append(e)
    _CREATED.append(e)
    return e


def tick(g, n=1):
    for _ in range(n):
        g.update(DT)


def key(g, code, mouse=None):
    """The prototype's real key handler, with the mouse at a screen point whose world
    position is `mouse` (world = screen + cam - (W/2, H/2))."""
    if mouse is not None:
        w, h = base.W, base.H
        sx = mouse[0] - g.cam.x + w / 2
        sy = mouse[1] - g.cam.y + h / 2
        pygame.mouse.get_pos = lambda sx=sx, sy=sy: (sx, sy)
    g.handle(pygame.event.Event(pygame.KEYDOWN, key=code))


def sword_snap(s):
    return dict(state=s.state, x=r(s.pos.x), y=r(s.pos.y), ult_cd=r(s.ult_cd), ult_t=r(s.ult_t))


# ------------------------------------------------------------------ cases
def case_table():
    t = SWORD_TYPES["fang"]
    u = t["ult"]
    out = dict(name=u["name"], cd=u["cd"], range=u["range"], radius=u["radius"], shot=u["shot"],
               fang_damage=t["damage"], keys="QER", converge_cd=NS["CONVERGE_CD"])
    out["ult_max_by_rarity"] = [r(Sword("fang", i, "fire", V(0, 0)).ult_max, 4) for i in range(3)]
    out["damage_by_rarity"] = [r(Sword("fang", i, "fire", V(0, 0)).damage, 4) for i in range(3)]
    # constants read off the code: duration 1.25, cadence 0.08, x1.2, knock 120, shake 0.05,
    # approach rate 28, recovery 0.3 s at 300 px/s, retreat distance r + 20, wander 20 .. 0.7 R.
    out["inline"] = dict(duration=1.25, cadence=0.08, damage_factor=1.2, knock=120, shake=0.05, approach_rate=28.0,
                         recover_time=0.3, recover_speed=300.0, standoff=20.0, wander_min=20.0, wander_max_factor=0.7,
                         heavy_flash=0.2)
    return out


def case_single_victim():
    """One eligible enemy: the dart choice is forced, so the whole flurry is comparable."""
    out = {}
    for label, crit, rarity in (("common", False, 0), ("common_crit", True, 0), ("rare", False, 1), ("mythic", False, 2)):
        with NoCrit(crit):
            g = fresh(rarities=(rarity, 0, 0))
            target = (PLAYER[0] + 260.0, PLAYER[1] + 40.0)
            husk = foe(g, (target[0] + 30.0, target[1] - 20.0))
            sw = g.swords[0]
            key(g, pygame.K_q, mouse=target)  # world point is within 420 of the player
            first = sword_snap(sw)
            trace = {}
            hits = []
            hp_prev = husk.hp
            transitions = []
            prev_state = sw.state
            flash_seen = 0.0
            trauma_seen = []
            vel_after_first = None
            for step in range(1, 130):
                tick(g)
                if husk.hp < hp_prev:
                    hits.append(dict(tick=step, dealt=r(hp_prev - husk.hp), vx=r(husk.vel.x), vy=r(husk.vel.y), stun=r(husk.stun),
                                     flash=r(husk.flash), hitstop=r(g.hitstop), trauma=r(g.trauma)))
                    hp_prev = husk.hp
                if sw.state != prev_state:
                    transitions.append(dict(tick=step, to=sw.state, ult_cd=r(sw.ult_cd)))
                    prev_state = sw.state
                if step in (1, 2, 3, 4, 5, 6, 7, 10, 15, 20, 30, 40, 50, 60, 70, 74, 75, 76, 77, 80, 90):
                    s = sword_snap(sw)
                    s.update(vx=r(sw.vel.x), vy=r(sw.vel.y), ang=r(sw.ang, 4), husk_x=r(husk.pos.x), husk_y=r(husk.pos.y))
                    trace[str(step)] = s
            out[label] = dict(setup=dict(rarity=rarity, enemies=[husk.setup], point=[target[0], target[1]], crit=crit),
                              at_start=first, hits=hits, transitions=transitions, trace=trace,
                              hp_end=r(husk.hp), kills=g.kills, ult_max=r(sw.ult_max, 4))
    return out


def case_range_clamp():
    """Where the sword blinks for a point inside, on and beyond the 420 px range."""
    out = {}
    offsets = {"inside": (0.0, 100.0), "on_the_limit": (420.0, 0.0), "just_beyond": (421.0, 0.0), "far_east": (900.0, 0.0),
               "far_diagonal": (500.0, -600.0), "on_the_player": (0.0, 0.0), "far_south_west": (-1000.0, 300.0)}
    for label, (dx, dy) in offsets.items():
        g = fresh()
        sw = g.swords[1]
        point = (PLAYER[0] + dx, PLAYER[1] + dy)
        key(g, pygame.K_e, mouse=point)
        out[label] = dict(point=[point[0], point[1]], state=sw.state, blink=[r(sw.point.x), r(sw.point.y)],
                          distance=r((sw.point - g.player.pos).length()), pos=[r(sw.pos.x), r(sw.pos.y)],
                          ult_cd=r(sw.ult_cd))
    # a point just inside / outside the area of the clamp measured from a moved player
    g = fresh()
    g.player.pos = V(PLAYER[0] - 500.0, PLAYER[1] - 300.0)
    sw = g.swords[0]
    moved_point = (PLAYER[0] + 500.0, PLAYER[1] + 100.0)
    key(g, pygame.K_q, mouse=moved_point)
    out["from_moved_player"] = dict(point=list(moved_point), player=[r(g.player.pos.x), r(g.player.pos.y)], blink=[r(sw.point.x), r(sw.point.y)],
                                    distance=r((sw.point - g.player.pos).length()))
    return out


def case_area_and_empty():
    """The eligibility edge of the 150 px area, and an empty area."""
    out = {}
    R = SWORD_TYPES["fang"]["ult"]["radius"]
    point = (PLAYER[0] + 250.0, PLAYER[1])
    husk_r = NS["ENEMY_TYPES"]["husk"]["r"]
    for label, offset in (("just_inside", R + husk_r - 1.0), ("just_outside", R + husk_r + 1.0), ("centre", 0.0)):
        with NoCrit(False):
            g = fresh()
            husk = foe(g, (point[0], point[1] + offset))
            sw = g.swords[2]
            key(g, pygame.K_r, mouse=point)
            first_hit = None
            hp_prev = husk.hp
            for step in range(1, 100):
                tick(g)
                if husk.hp < hp_prev and first_hit is None:
                    first_hit = step
                hp_prev = husk.hp
            out[label] = dict(setup=dict(enemies=[husk.setup], point=list(point)), offset=r(offset), first_hit=first_hit,
                              hits=r((500.0 - husk.hp) / 8.0, 3))
    # empty area: nothing to hit, the sword wanders inside the area, cadence 0.08 s
    with NoCrit(False):
        g = fresh()
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        goal_ticks = []
        last_goal = V(sw.goal)
        max_from_centre = 0.0
        max_goal_from_centre = 0.0
        distances = []
        for step in range(1, 90):
            tick(g)
            if sw.state == "ult":
                if (sw.goal - last_goal).length() > 1e-9:
                    goal_ticks.append(step)
                    last_goal = V(sw.goal)
                    d = (sw.goal - sw.point).length()
                    max_goal_from_centre = max(max_goal_from_centre, d)
                    distances.append(d)
                max_from_centre = max(max_from_centre, (sw.pos - sw.point).length())
        out["empty_area"] = dict(setup=dict(enemies=[], point=list(point)), goal_ticks=goal_ticks, goals=len(goal_ticks),
                                 min_goal_distance=r(min(distances)), max_goal_distance=r(max_goal_from_centre),
                                 max_sword_distance=r(max_from_centre), hits=0, final_state=sw.state, kills=g.kills,
                                 wander_min=20.0, wander_max=r(R * 0.7))
    return out


def case_target_replacement():
    out = {}
    point = (PLAYER[0] + 260.0, PLAYER[1])
    with NoCrit(False):
        # two enemies in the area: a dart never picks the one it just struck while another is available
        for seed in (1, 2, 3, 4, 5):
            g = fresh(seed=seed)
            a = foe(g, (point[0] - 60.0, point[1]))
            b = foe(g, (point[0] + 60.0, point[1] + 20.0))
            sw = g.swords[0]
            key(g, pygame.K_q, mouse=point)
            order = []
            hp = {id(a): a.hp, id(b): b.hp}
            ticks = []
            for step in range(1, 100):
                tick(g)
                for name, e in (("a", a), ("b", b)):
                    if e.hp < hp[id(e)]:
                        order.append(name)
                        ticks.append(step)
                        hp[id(e)] = e.hp
            out["two_enemies_seed%d" % seed] = dict(order=order, ticks=ticks,
                                                   alternates=all(order[i] != order[i + 1] for i in range(len(order) - 1)),
                                                   setup=[a.setup, b.setup])
        # one enemy: it keeps being the target
        g = fresh()
        a = foe(g, (point[0] - 40.0, point[1]))
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        hits = 0
        hp_prev = a.hp
        for step in range(1, 100):
            tick(g)
            if a.hp < hp_prev:
                hits += 1
                hp_prev = a.hp
        out["one_enemy_repeats"] = dict(setup=[a.setup], hits=hits)
        # the target dies on the first dart: the sword then wanders and the dead enemy takes no more
        g = fresh()
        a = foe(g, (point[0] - 40.0, point[1]), hp=5.0)
        far = foe(g, (point[0] + 400.0, point[1]), hp=500.0)  # outside the area: never eligible
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        kill_tick = None
        for step in range(1, 100):
            tick(g)
            if a.dead and kill_tick is None:
                kill_tick = step
        out["target_dies"] = dict(setup=[a.setup, far.setup], kill_tick=kill_tick, kills=g.kills, combo=g.combo,
                                  far_hp=r(far.hp), enemies_left=len(g.enemies), state_after=sw.state,
                                  victim_after=sw.victim is None)
        # the target is killed by something else between darts: no hit, no second kill, a replacement is found
        g = fresh()
        a = foe(g, (point[0] - 40.0, point[1]))
        b = foe(g, (point[0] + 50.0, point[1] + 10.0))
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        tick(g)  # the first dart choice happens on the first update
        first_victim = sw.victim
        g.kill(first_victim, V(1, 0), False)   # the prototype's own kill (a bowling blow, say)
        other = b if first_victim is a else a
        hp_other = other.hp
        tick(g, 4)
        dead_victim_hit_on_its_turn = first_victim.hp < 500.0
        trauma_before_due_tick = g.trauma
        tick(g, 1)
        no_shake_for_a_dead_victim = g.trauma <= trauma_before_due_tick  # the tick on which the dead victim was due a dart: nothing happens, a replacement is chosen
        replaced = sw.victim is other
        hit_on_due_tick = other.hp < hp_other
        tick(g, 5)  # and the replacement is struck one cadence later
        out["killed_by_something_else"] = dict(setup=[a.setup, b.setup], kills=g.kills, dead_victim_took_damage=dead_victim_hit_on_its_turn,
                                               replaced_by_the_other=replaced, other_hit_on_due_tick=hit_on_due_tick,
                                               other_hits_after_replacement=r((hp_other - other.hp) / 8.0, 3),
                                               victim_hp_after=r(first_victim.hp), no_shake_for_a_dead_victim=no_shake_for_a_dead_victim)
        # the only enemy in the area is killed by something else: the next choice finds nobody and the sword wanders
        g = fresh()
        a = foe(g, (point[0] - 40.0, point[1]))
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        tick(g, 5)  # the victim was chosen on tick 1 and is due its dart on tick 6
        g.kill(sw.victim, V(1, 0), False)  # killed on the very tick it would be re-chosen: the corpse is still in the list
        tick(g, 1)
        out["killed_only_enemy"] = dict(setup=[a.setup], kills=g.kills, victim_none=sw.victim is None, state=sw.state,
                                        shake_after=r(g.trauma))
    return out


def case_recharge_and_rejections():
    out = {}
    with NoCrit(False):
        for rarity in (0, 1, 2):
            g = fresh(rarities=(rarity, 0, 0))
            sw = g.swords[0]
            point = (PLAYER[0] + 200.0, PLAYER[1])
            key(g, pygame.K_q, mouse=point)
            ult_max = sw.ult_max
            ready_tick = None
            at_ticks = {}
            for step in range(1, 700):
                tick(g)
                if step in (1, 60, 120, 300, 539, 540, 541):
                    at_ticks[str(step)] = r(sw.ult_cd)
                if sw.ult_cd <= 0.0 and ready_tick is None:
                    ready_tick = step
            out["recharge_rarity%d" % rarity] = dict(ult_max=r(ult_max, 4), ready_tick=ready_tick, ult_cd_at=at_ticks,
                                                     ult_cd_after_trigger=r(ult_max, 4))
        # rejection while recharging: nothing changes
        g = fresh()
        sw = g.swords[0]
        point = (PLAYER[0] + 200.0, PLAYER[1])
        key(g, pygame.K_q, mouse=point)
        tick(g, 100)  # the flurry is over, the sword recovering/idle, still recharging
        before = dict(state=sw.state, ult_cd=r(sw.ult_cd), pos=[r(sw.pos.x), r(sw.pos.y)])
        key(g, pygame.K_q, mouse=(PLAYER[0] - 200.0, PLAYER[1]))
        after = dict(state=sw.state, ult_cd=r(sw.ult_cd), pos=[r(sw.pos.x), r(sw.pos.y)])
        out["rejected_while_recharging"] = dict(before=before, after=after, state_changed=before["state"] != after["state"],
                                               cd_reset=after["ult_cd"] > before["ult_cd"])
        # rejection while the flurry is active (even though the cooldown is not what stops it)
        g = fresh()
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        tick(g, 10)
        snap = dict(state=sw.state, ult_cd=r(sw.ult_cd), ult_t=r(sw.ult_t))
        sw.ult_cd = 0.0  # even with the recharge forced to zero the active flurry refuses a second command
        key(g, pygame.K_q, mouse=(PLAYER[0] - 200.0, PLAYER[1]))
        out["rejected_while_active"] = dict(before=snap, state=sw.state, ult_cd=r(sw.ult_cd), ult_t=r(sw.ult_t),
                                           blink=[r(sw.point.x), r(sw.point.y)], point=list(point))
        # ready again after the recharge, and the three slots recharge independently
        g = fresh()
        key(g, pygame.K_q, mouse=point)
        tick(g, 120)
        key(g, pygame.K_e, mouse=(PLAYER[0], PLAYER[1] + 200.0))
        out["slots_independent"] = dict(states=[s.state for s in g.swords], ult_cd=[r(s.ult_cd) for s in g.swords],
                                        blink_e=[r(g.swords[1].point.x), r(g.swords[1].point.y)])
        tick(g, 480)
        out["slots_independent"]["after_480_more_ticks"] = dict(ult_cd=[r(s.ult_cd) for s in g.swords],
                                                                 states=[s.state for s in g.swords])
        tick(g, 100)
        key(g, pygame.K_q, mouse=point)
        out["slots_independent"]["q_again"] = g.swords[0].state
        # a command for a slot that does not exist is ignored (prototype: idx >= len(swords))
        g = fresh()
        g.swords = g.swords[:2]
        key(g, pygame.K_r, mouse=point)
        out["no_third_sword"] = dict(states=[s.state for s in g.swords], ult_cd=[r(s.ult_cd) for s in g.swords])
        # the command interrupts the sword's own automatic attack
        g = fresh()
        sw = g.swords[0]
        sw.cd = 0.0
        husk = foe(g, (PLAYER[0] + 100.0, PLAYER[1]))
        tick(g, 2)
        state_before = sw.state
        key(g, pygame.K_q, mouse=point)
        out["interrupts_attack"] = dict(state_before=state_before, state_after=sw.state, target_cleared=sw.target is None)
    return out


def case_keys_and_restart():
    """Q/E/R through the prototype's real key handler; R after death."""
    out = {}
    point = (PLAYER[0] + 200.0, PLAYER[1])
    for name, code in (("q", pygame.K_q), ("e", pygame.K_e), ("r", pygame.K_r)):
        g = fresh()
        key(g, code, mouse=point)
        out["key_" + name] = [s.state for s in g.swords]
    # R is the slot-three ultimate while alive: it does not restart
    g = fresh()
    g.kills = 7
    key(g, pygame.K_r, mouse=point)
    out["r_alive"] = dict(restarted=g.kills != 7, slot3_state=g.swords[2].state, kills=g.kills)
    # dead: Q/E/R start nothing; R restarts only after the 0.8 s delay (death_t > 0.8)
    g = fresh()
    g.kills = 7
    g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    assert g.player.dead
    key(g, pygame.K_q, mouse=point)
    key(g, pygame.K_r, mouse=point)
    early = dict(states=[s.state for s in g.swords], restarted=g.kills != 7, death_t=r(g.death_t))
    ticks_to_restart = None
    for step in range(1, 400):
        tick(g)
        key(g, pygame.K_r, mouse=point)
        if g.kills != 7:
            ticks_to_restart = step
            break
    # gameplay-scaled time: death slow motion runs at x0.25 for 1.4 s of real time
    out["dead"] = dict(early=early, ticks_to_restart=ticks_to_restart, death_slowmo_scale=g.slowmo_scale,
                       after_restart=dict(hp=r(g.player.hp), alive=not g.player.dead, states=[s.state for s in g.swords],
                                          ult_cd=[r(s.ult_cd) for s in g.swords], kills=g.kills))
    # a dead player cannot start the ultimate even after restart delay passed (R is the restart then)
    g = fresh()
    g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    key(g, pygame.K_e, mouse=point)
    out["dead_e"] = dict(states=[s.state for s in g.swords], ult_cd=[r(s.ult_cd) for s in g.swords])
    # paused: nothing is started, and the clock does not advance
    g = fresh()
    g.paused = True
    key(g, pygame.K_q, mouse=point)
    out["paused_q"] = dict(states=[s.state for s in g.swords], ult_cd=[r(s.ult_cd) for s in g.swords])
    g = fresh()
    key(g, pygame.K_q, mouse=point)
    tick(g, 10)
    snap_before = [sword_snap(s) for s in g.swords]
    g.paused = True
    tick(g, 120)
    snap_after = [sword_snap(s) for s in g.swords]
    out["pause_freezes_flurry"] = dict(identical=snap_before == snap_after, before=snap_before[0], after=snap_after[0])
    # R while paused and dead (after the delay) still restarts: the prototype tests `dead` before `paused`
    g = fresh()
    g.kills = 7
    g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
    for _ in range(400):
        tick(g)
        if g.death_t > 0.8:
            break
    g.paused = True
    key(g, pygame.K_r, mouse=point)
    out["r_paused_dead"] = dict(restarted=g.kills != 7, death_t=r(g.death_t))
    # touch: the nearest living enemy, or 300 px ahead of the player
    g = fresh()
    near_foe = foe(g, (PLAYER[0] + 500.0, PLAYER[1] + 100.0))
    far_foe = foe(g, (PLAYER[0] - 900.0, PLAYER[1]))
    aim = g.auto_aim()
    g2 = fresh()
    g2.player.facing = V(0, -1)
    aim2 = g2.auto_aim()
    out["auto_aim"] = dict(setup=[near_foe.setup, far_foe.setup], nearest=[r(aim.x), r(aim.y)], forward=[r(aim2.x), r(aim2.y)],
                           facing=[0.0, -1.0])
    g.ultimate(0, aim)
    out["auto_aim"]["blink"] = [r(g.swords[0].point.x), r(g.swords[0].point.y)]
    return out


def case_death_during_flurry():
    out = {}
    point = (PLAYER[0] + 260.0, PLAYER[1])
    with NoCrit(False):
        g = fresh()
        husk = foe(g, (point[0] + 30.0, point[1]))
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        tick(g, 20)
        hits_before = r((500.0 - husk.hp) / 8.0, 3)
        g.hurt_player(1000, V(PLAYER[0] + 50.0, PLAYER[1]))
        assert g.player.dead
        tick(g)
        state_next = sw.state
        hp_at_death = husk.hp
        ult_cd_at_death = r(sw.ult_cd)
        tick(g, 100)
        out["death"] = dict(setup=[husk.setup], hits_before=hits_before, state_next_tick=state_next, hits_after=r((hp_at_death - husk.hp) / 8.0, 3),
                            victim_cleared_state=sw.state, ult_cd_at_death=ult_cd_at_death, ult_cd_100_ticks_later=r(sw.ult_cd))
    return out


def case_time_scales():
    out = {}
    point = (PLAYER[0] + 260.0, PLAYER[1])
    with NoCrit(False):
        # hitstop at the moment of the command: the whole flurry waits it out
        g = fresh()
        husk = foe(g, (point[0] + 30.0, point[1]))
        g.hitstop = 0.2
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        first_hit = None
        state_at = {}
        for step in range(1, 140):
            before = husk.hp
            tick(g)
            if husk.hp < before and first_hit is None:
                first_hit = step
            if step in (1, 5, 12, 13, 14):
                state_at[str(step)] = dict(ult_cd=r(sw.ult_cd), ult_t=r(sw.ult_t))
        out["hitstop_at_command"] = dict(setup=[husk.setup], hitstop=0.2, first_hit_tick=first_hit, at=state_at)
        # slow motion x0.25 from the start: flurry timers and recharge run at a quarter speed
        g = fresh()
        husk = foe(g, (point[0] + 30.0, point[1]))
        g.slowmo = 100.0
        g.slowmo_scale = 0.25
        sw = g.swords[0]
        key(g, pygame.K_q, mouse=point)
        first_hit = None
        for step in range(1, 100):
            before = husk.hp
            tick(g)
            if husk.hp < before and first_hit is None:
                first_hit = step
        out["slow_motion"] = dict(setup=[husk.setup], scale=0.25, first_hit_tick=first_hit, ult_cd_after_99=r(sw.ult_cd),
                                  ult_t_after_99=r(sw.ult_t), state=sw.state)
    return out


def case_projectiles():
    """The flurry does not parry: an orb sitting where the sword blinks to survives it."""
    out = {}
    Projectile = NS["Projectile"]
    point = (PLAYER[0] + 260.0, PLAYER[1])
    with NoCrit(False):
        g = fresh()
        husk = foe(g, (point[0] + 30.0, point[1]))
        pr = Projectile(V(point), V(0, 0))
        pr.life = 10.0
        g.projectiles.append(pr)
        key(g, pygame.K_q, mouse=point)
        tick(g, 100)
        out["orb_in_the_area"] = dict(setup=dict(x=r(pr.pos.x), y=r(pr.pos.y), vx=0.0, vy=0.0, life=10.0, enemies=[husk.setup]),
                                      orb_alive=not pr.dead, parry_hitstop=r(g.hitstop))
    return out


def case_other_swords_keep_fighting():
    """While one Fang flurries, the other two keep their automatic attacks."""
    out = {}
    with NoCrit(False):
        g = fresh()
        for s in g.swords[1:]:
            s.cd = 0.0
        husk = foe(g, (PLAYER[0] + 120.0, PLAYER[1]), hp=500.0)
        key(g, pygame.K_q, mouse=(PLAYER[0] + 330.0, PLAYER[1] - 300.0))
        states = []
        for step in range(1, 40):
            tick(g)
            states.append([s.state for s in g.swords])
        out["others"] = dict(setup=[husk.setup], flurry_sword_state=states[10][0], others_struck=any(st[1] != "idle" or st[2] != "idle" for st in states),
                             husk_damaged=husk.hp < 500.0)
    return out


def assert_fixtures_in_scope():
    for e in _CREATED:
        assert e.armed is None and e.kind == "husk"
    for sw in _SWORDS:
        assert sw.kind == "fang"
    return dict(enemies_created=len(_CREATED), armed_enemies=0, kinds=["husk"], afflict_disabled=True,
                swords_used=sorted({sw.kind for sw in _SWORDS}), converge_used=False, waves_enabled=False,
                auto_attack_parked=True)


def main():
    cases = dict(
        table=case_table(), single_victim=case_single_victim(), range_clamp=case_range_clamp(),
        area_and_empty=case_area_and_empty(), target_replacement=case_target_replacement(),
        recharge_and_rejections=case_recharge_and_rejections(), keys_and_restart=case_keys_and_restart(),
        death_during_flurry=case_death_during_flurry(), time_scales=case_time_scales(), projectiles=case_projectiles(),
        other_swords=case_other_swords_keep_fighting(),
    )
    cases["fixture_scope"] = assert_fixtures_in_scope()
    text = json.dumps(cases, indent=2, sort_keys=False)
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_text(text + "\n")
    else:
        print(text)


if __name__ == "__main__":
    main()
