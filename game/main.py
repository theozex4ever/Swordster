"""SWORDSTER - prototype.

Three spirit swords hover around you and strike on their own.
Armed enemies carry a sword; kill them and it's yours to swap in.

Runs on desktop (python game/main.py) and in the browser via pygbag.
"""
import asyncio
import json
import math
import random
import sys
from array import array

import pygame

if sys.platform == "emscripten":
    import platform

W, H = 1280, 720
WORLD = pygame.Rect(0, 0, 2600, 1800)
V = pygame.Vector2
TAU = math.tau

BG = (9, 8, 14)
FLOOR_DARK = (14, 12, 20)
SHADOW = (7, 6, 11)


# ---------------------------------------------------------------- helpers
def clamp(x, a, b):
    return a if x < a else b if x > b else x


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(int(clamp(lerp(a, b, t), 0, 255)) for a, b in zip(c1, c2))


def dim(c, k):
    return tuple(int(clamp(v * k, 0, 255)) for v in c)


def ang_lerp(a, b, t):
    d = (b - a + math.pi) % TAU - math.pi
    return a + d * t


def ease_out(t):
    return 1 - (1 - t) ** 3


def polar(a, r=1.0):
    return V(math.cos(a) * r, math.sin(a) * r)


def seg_dist(p, a, b):
    ab = b - a
    l2 = ab.length_squared()
    if l2 == 0:
        return (p - a).length()
    t = clamp((p - a).dot(ab) / l2, 0, 1)
    return (p - (a + ab * t)).length()


def norm(v, fallback=None):
    if v.length_squared() < 1e-6:
        return V(fallback) if fallback is not None else polar(random.uniform(0, TAU))
    return v.normalize()


# ---------------------------------------------------------------- data
# Each sword type has one automatic attack and one ultimate the player triggers.
# Targeted ultimates land on the cursor; skill shots fire toward it.
SWORD_TYPES = {
    "fang": dict(
        name="Fang", blurb="close / rapid",
        length=34, width=6, range=175, cooldown=0.30, damage=7, knock=170,
        windup=0.06, speed=1700, hitstop=0.02, shake=0.07, sound="tick",
        ult=dict(name="Viper Flurry", cd=9.0, range=420, shot=False, radius=150),
    ),
    "blade": dict(
        name="Warden", blurb="mid / sweeping arc",
        length=54, width=8, range=245, cooldown=0.85, damage=17, knock=300,
        windup=0.16, hitstop=0.05, shake=0.16, sound="slash",
        ult=dict(name="Maelstrom", cd=11.0, range=400, shot=False, radius=100),
    ),
    "lance": dict(
        name="Pike", blurb="long / piercing thrust",
        length=74, width=6, range=430, cooldown=1.35, damage=24, knock=380,
        windup=0.32, speed=2400, hitstop=0.06, shake=0.2, sound="pierce",
        ult=dict(name="Skewer", cd=10.0, range=950, shot=True, speed=2600),
    ),
    "colossus": dict(
        name="Colossus", blurb="far / slow / crushing slam",
        length=88, width=15, range=330, cooldown=2.1, damage=50, knock=650,
        windup=0.55, hitstop=0.13, shake=0.6, aoe=118, sound="boom",
        ult=dict(name="Cataclysm", cd=14.0, range=480, shot=False, aoe=1.8),
    ),
}
DROP_WEIGHTS = [("fang", 3), ("blade", 3), ("lance", 2.5), ("colossus", 1.6)]
ULT_KEYS = "QER"
CONVERGE_CD = 2.5

# Every sword carries one element; its hits apply the matching condition.
ELEMENTS = {
    "fire": dict(name="Fire", adj="Ember", color=(255, 118, 44), tag="FIRE  burns, spreads"),
    "ice": dict(name="Ice", adj="Frost", color=(120, 205, 255), tag="ICE  chills, freezes"),
    "poison": dict(name="Poison", adj="Venom", color=(132, 230, 66), tag="POISON  stacking toxin"),
}
BURN_TIME, POISON_TIME, CHILL_TIME, FREEZE_TIME = 3.0, 4.5, 2.5, 1.6
POISON_MAX, FREEZE_STACKS = 6, 4
CHILL_SLOW, SHATTER = 0.5, 1.3

RARITIES = [
    dict(name="Common", color=(205, 205, 215), dmg=1.0, cd=1.0, rng=1.0, size=1.0),
    dict(name="Rare", color=(90, 175, 255), dmg=1.3, cd=0.87, rng=1.06, size=1.08),
    dict(name="Mythic", color=(255, 196, 60), dmg=1.75, cd=0.74, rng=1.12, size=1.18),
]

ENEMY_TYPES = {
    "husk": dict(r=16, hp=30, speed=92, dmg=10, color=(214, 72, 86), knock=1.0, armed=0.2),
    "runner": dict(r=11, hp=14, speed=178, dmg=6, color=(255, 140, 70), knock=1.3, armed=0.12),
    "spitter": dict(r=15, hp=24, speed=85, dmg=8, color=(130, 210, 90), knock=1.1, armed=0.22),
    "brute": dict(r=30, hp=170, speed=52, dmg=20, color=(170, 90, 220), knock=0.35, armed=0.75),
}


def weighted(pairs):
    total = sum(w for _, w in pairs)
    r = random.uniform(0, total)
    for k, w in pairs:
        r -= w
        if r <= 0:
            return k
    return pairs[-1][0]


# ---------------------------------------------------------------- render caches
_glow_cache = {}


def glow(radius, color):
    radius = max(2, int(radius) // 2 * 2)
    key = (radius, color)
    s = _glow_cache.get(key)
    if s is None:
        if len(_glow_cache) > 500:
            _glow_cache.clear()
        s = pygame.Surface((radius * 2, radius * 2))
        steps = min(radius, 20)
        for i in range(steps):
            t = i / steps
            r = int(radius * (1 - t))
            if r < 1:
                break
            pygame.draw.circle(s, dim(color, t * t), (radius, radius), r)
        _glow_cache[key] = s
    return s


def draw_glow(surf, pos, radius, color):
    g = glow(radius, color)
    r = g.get_width() // 2
    surf.blit(g, (pos[0] - r, pos[1] - r), special_flags=pygame.BLEND_ADD)


def make_floor_tile(seed):
    rng = random.Random(seed * 7919 + 3)
    s = pygame.Surface((256, 256))
    s.fill(FLOOR_DARK)
    for gy in range(4):
        for gx in range(4):
            c = 23 + rng.randint(-4, 4)
            rect = pygame.Rect(gx * 64 + 1, gy * 64 + 1, 62, 62)
            pygame.draw.rect(s, (c, c - 3, c + 9), rect)
            for _ in range(5):
                x, y = rect.x + rng.randint(2, 56), rect.y + rng.randint(2, 56)
                pygame.draw.rect(s, (c - 4, c - 7, c + 3), (x, y, rng.randint(2, 6), rng.randint(2, 5)))
            if rng.random() < 0.22:
                p = V(rect.x + rng.randint(8, 54), rect.y + rng.randint(8, 54))
                for _ in range(rng.randint(2, 4)):
                    q = p + polar(rng.uniform(0, TAU), rng.uniform(6, 16))
                    pygame.draw.line(s, (c - 9, c - 11, c - 2), p, q, 1)
                    p = q
    if rng.random() < 0.6:
        cx, cy = rng.randint(60, 196), rng.randint(60, 196)
        col = (31, 25, 46)
        rad = rng.randint(26, 44)
        pygame.draw.circle(s, col, (cx, cy), rad, 1)
        pygame.draw.circle(s, col, (cx, cy), rad - 6, 1)
        for k in range(rng.randint(3, 6)):
            a = k * TAU / 6 + rng.random()
            pygame.draw.line(s, col, (cx, cy) + polar(a, rad - 6), (cx, cy) + polar(a + 2.2, rad - 6), 1)
    return s


def make_vignette(color, strength):
    small = pygame.Surface((160, 90), pygame.SRCALPHA)
    small.fill((*color, strength))
    steps = 40
    for i in range(steps):
        t = i / steps
        a = int(strength * (1 - t) ** 1.6 * 0.95)
        rw = int(160 * (1.25 - t * 0.55))
        rh = int(90 * (1.25 - t * 0.5))
        pygame.draw.ellipse(small, (*color, a), (80 - rw // 2, 45 - rh // 2, rw, rh))
    pygame.draw.ellipse(small, (*color, 0), (80 - 40, 45 - 22, 80, 44))
    return pygame.transform.smoothscale(small, (W, H))


def draw_sword(surf, kind, pos, ang, scale=1.0, color=(255, 255, 255), flash=0.0):
    t = SWORD_TYPES[kind]
    L = t["length"] * scale
    w = t["width"] * scale
    d = polar(ang)
    n = V(-d.y, d.x)
    g = V(pos) - d * (L * 0.35)
    blade = mix(color, (255, 255, 255), 0.55 + 0.45 * flash)
    edge = dim(color, 0.5)
    if kind == "lance":
        tail = g - d * L * 0.28
        head = g + d * L * 0.6
        tip = g + d * L
        pygame.draw.line(surf, dim(color, 0.6), tail, head, max(2, int(w * 0.55)))
        pts = [head + n * w * 0.35, head + d * L * 0.13 + n * w * 1.35, tip,
               head + d * L * 0.13 - n * w * 1.35, head - n * w * 0.35]
        pygame.draw.polygon(surf, blade, pts)
        pygame.draw.polygon(surf, edge, pts, 1)
        pygame.draw.line(surf, color, head + n * w * 1.2, head - n * w * 1.2, 2)
        pygame.draw.circle(surf, color, tail, max(2, w * 0.6))
        return tip
    tip = g + d * L
    if kind == "fang":
        pts = [g + n * w * 0.5, g + d * L * 0.55 + n * w * 0.65, tip, g + d * L * 0.5 - n * w * 0.3, g - n * w * 0.5]
    elif kind == "colossus":
        pts = [g + n * w * 0.55, g + d * L * 0.84 + n * w * 0.5, tip, g + d * L * 0.84 - n * w * 0.5, g - n * w * 0.55]
    else:
        pts = [g + n * w * 0.45, g + d * L * 0.86 + n * w * 0.42, tip, g + d * L * 0.86 - n * w * 0.42, g - n * w * 0.45]
    pygame.draw.polygon(surf, blade, pts)
    pygame.draw.line(surf, edge, g + d * L * 0.08, g + d * L * 0.72, max(1, int(w * 0.2)))
    pygame.draw.polygon(surf, edge, pts, 1)
    gw = w * (1.25 if kind == "colossus" else 1.7)
    pygame.draw.line(surf, color, g + n * gw, g - n * gw, max(2, int(w * 0.45)))
    hilt = g - d * L * (0.3 if kind == "fang" else 0.22)
    pygame.draw.line(surf, dim(color, 0.45), g, hilt, max(2, int(w * 0.4)))
    pygame.draw.circle(surf, color, hilt, max(2, w * 0.42))
    return tip


# ---------------------------------------------------------------- audio
def synth(sr, dur, f0=0.0, f1=0.0, fdecay=10.0, adecay=10.0, tone=1.0, wave="sin",
          noise=0.0, nlp=0.3, ndecay=20.0, click=0.0, attack=0.0, drive=1.0):
    n = int(sr * dur)
    out = [0.0] * n
    ph = 0.0
    lp = 0.0
    rnd = random.random
    exp = math.exp
    sin = math.sin
    ncomp = 1 / math.sqrt(max(nlp, 0.03))
    for i in range(n):
        t = i / sr
        v = 0.0
        if tone:
            f = f1 + (f0 - f1) * exp(-t * fdecay)
            ph += TAU * f / sr
            s = sin(ph)
            if wave == "tri":
                s = 2 / math.pi * math.asin(s)
            elif wave == "sq":
                s = 0.6 if s >= 0 else -0.6
            v = tone * s * exp(-t * adecay)
        if noise:
            lp += nlp * ((rnd() * 2 - 1) - lp)
            v += noise * lp * ncomp * 0.5 * exp(-t * ndecay)
        if click:
            v += click * (rnd() * 2 - 1) * exp(-t * 160)
        if attack:
            v *= min(1.0, t / attack)
        out[i] = math.tanh(v * drive)
    fade = min(n, int(sr * 0.006))
    for i in range(fade):
        out[n - 1 - i] *= i / fade
    return out


SOUND_DEFS = {
    "tick": (dict(dur=0.09, f0=2600, f1=1100, fdecay=40, adecay=45, wave="tri", noise=0.7, nlp=0.6, ndecay=60), 0.35),
    "slash": (dict(dur=0.2, f0=900, f1=240, fdecay=25, adecay=20, noise=0.9, nlp=0.35, ndecay=20, drive=1.6), 0.45),
    "pierce": (dict(dur=0.24, f0=620, f1=160, fdecay=18, adecay=13, noise=0.7, nlp=0.25, ndecay=24, click=0.6, drive=1.4), 0.5),
    "boom": (dict(dur=0.95, f0=160, f1=34, fdecay=7, adecay=3.6, noise=1.3, nlp=0.06, ndecay=7, click=0.9, drive=2.4), 0.9),
    "thud": (dict(dur=0.14, f0=200, f1=60, fdecay=30, adecay=24, noise=0.5, nlp=0.15, ndecay=40, drive=1.8), 0.4),
    "whoosh": (dict(dur=0.18, tone=0, noise=1.0, nlp=0.12, ndecay=14, attack=0.05), 0.25),
    "heave": (dict(dur=0.45, f0=70, f1=150, fdecay=-1.5, adecay=2, tone=0.4, noise=0.9, nlp=0.05, ndecay=3, attack=0.3), 0.4),
    "hurt": (dict(dur=0.3, f0=240, f1=70, fdecay=10, adecay=9, wave="sq", noise=0.4, nlp=0.2, ndecay=12, drive=2.0), 0.5),
    "pop": (dict(dur=0.16, f0=900, f1=160, fdecay=30, adecay=20, noise=0.5, nlp=0.3, ndecay=30), 0.35),
    "chime": (dict(dur=0.55, f0=1320, f1=880, fdecay=25, adecay=6, wave="tri", noise=0.2, nlp=0.8, ndecay=40), 0.4),
    "dash": (dict(dur=0.2, tone=0, noise=1.0, nlp=0.25, ndecay=12, attack=0.03), 0.3),
    "gong": (dict(dur=1.3, f0=96, f1=88, fdecay=1, adecay=2.4, noise=0.3, nlp=0.04, ndecay=5, click=0.3, drive=1.4), 0.55),
    "parry": (dict(dur=0.18, f0=3200, f1=2400, fdecay=8, adecay=18, wave="tri", click=0.5), 0.3),
    "shot": (dict(dur=0.15, f0=500, f1=200, fdecay=20, adecay=18, noise=0.3, nlp=0.2, ndecay=25), 0.25),
}


class Sfx:
    def __init__(self):
        self.sounds = {}
        self.last = {}
        try:
            init = pygame.mixer.get_init()
            if not init:
                return
            sr, size, ch = init
            if size == -16:
                code, peak = "h", 32767
            elif size == 32:
                code, peak = "f", 1.0
            else:
                return
            pygame.mixer.set_num_channels(24)
            half = sr >= 44100
            gsr = sr // 2 if half else sr
            for name, (params, vol) in SOUND_DEFS.items():
                samples = synth(gsr, **params)
                buf = array(code)
                rep = (2 if half else 1) * ch
                for v in samples:
                    s = int(v * peak) if code == "h" else v
                    buf.extend([s] * rep)
                snd = pygame.mixer.Sound(buffer=buf.tobytes())
                snd.set_volume(vol)
                self.sounds[name] = snd
        except Exception:
            self.sounds = {}

    def play(self, name):
        s = self.sounds.get(name)
        if not s:
            return
        now = pygame.time.get_ticks()
        if now - self.last.get(name, -1000) > 40:
            self.last[name] = now
            s.play()


# ---------------------------------------------------------------- entities
class Particle:
    __slots__ = ("pos", "vel", "life", "max", "size", "color", "kind", "z", "vz", "drag", "grow")

    def __init__(self, pos, vel, life, size, color, kind="dot", drag=4.0, z=0.0, vz=0.0, grow=0.0):
        self.pos = V(pos)
        self.vel = V(vel)
        self.life = self.max = life
        self.size = size
        self.color = color
        self.kind = kind
        self.drag = drag
        self.z = z
        self.vz = vz
        self.grow = grow


class Text:
    def __init__(self, pos, surf, life=0.8, vel=(0, -70)):
        self.pos = V(pos)
        self.vel = V(vel)
        self.surf = surf
        self.life = self.max = life


class Mote:
    def __init__(self, pos):
        self.pos = V(pos)
        self.vel = polar(random.uniform(0, TAU), random.uniform(120, 260))
        self.t = 0.0


class Projectile:
    def __init__(self, pos, vel):
        self.pos = V(pos)
        self.vel = V(vel)
        self.r = 7
        self.life = 4.0
        self.dead = False


class Pickup:
    def __init__(self, kind, rarity, element, pos):
        self.kind = kind
        self.rarity = rarity
        self.element = element
        self.pos = V(pos)
        self.t = random.uniform(0, 5)
        self.life = 45.0


class Field:
    """Lingering elemental ground left by Cataclysm."""

    def __init__(self, pos, radius, element, power, life):
        self.pos = V(pos)
        self.radius = radius
        self.element = element
        self.power = power
        self.life = self.max = life
        self.tick = 0.0


class Marker:
    def __init__(self, kind, pos, armed):
        self.kind = kind
        self.pos = V(pos)
        self.armed = armed
        self.t = self.max = 0.7


class Player:
    def __init__(self, pos):
        self.pos = V(pos)
        self.vel = V()
        self.r = 14
        self.maxhp = 100.0
        self.hp = self.maxhp
        self.hp_shown = self.hp
        self.speed = 285
        self.move = V()
        self.facing = V(1, 0)
        self.iframes = 0.0
        self.dash_t = 0.0
        self.dash_cd = 0.0
        self.ghost_t = 0.0
        self.hurt_flash = 0.0
        self.dead = False

    def update(self, g, dt, keys):
        mv = V(
            (keys[pygame.K_d] or keys[pygame.K_RIGHT]) - (keys[pygame.K_a] or keys[pygame.K_LEFT]),
            (keys[pygame.K_s] or keys[pygame.K_DOWN]) - (keys[pygame.K_w] or keys[pygame.K_UP]),
        )
        if g.touch_move.length_squared() > 0:
            mv = V(g.touch_move)
        if self.dead:
            mv = V()
        if mv.length_squared() > 0:
            if mv.length_squared() > 1:
                mv = mv.normalize()
            self.facing = mv.normalize()
        self.move = mv
        self.iframes = max(0.0, self.iframes - dt)
        self.dash_cd = max(0.0, self.dash_cd - dt)
        self.hurt_flash = max(0.0, self.hurt_flash - dt * 2.5)
        if self.dash_t > 0:
            self.dash_t -= dt
            self.ghost_t -= dt
            if self.ghost_t <= 0:
                self.ghost_t = 0.018
                g.particles.append(Particle(self.pos, (0, 0), 0.25, self.r, (60, 150, 200), "ghost", 0))
        else:
            self.vel += (mv * self.speed - self.vel) * min(1.0, dt * 14)
        self.pos += self.vel * dt
        self.pos.x = clamp(self.pos.x, WORLD.left + self.r, WORLD.right - self.r)
        self.pos.y = clamp(self.pos.y, WORLD.top + self.r, WORLD.bottom - self.r)
        self.hp_shown = lerp(self.hp_shown, self.hp, min(1.0, dt * 3)) if self.hp_shown > self.hp else self.hp

    def dash(self, g):
        if self.dash_cd > 0 or self.dead:
            return
        d = self.move if self.move.length_squared() > 0 else self.facing
        d = d.normalize()
        self.vel = d * 1000
        self.dash_t = 0.14
        self.dash_cd = 0.65
        self.iframes = max(self.iframes, 0.24)
        g.sfx.play("dash")
        for _ in range(10):
            g.particles.append(Particle(self.pos, -d * random.uniform(80, 260) + polar(random.uniform(0, TAU), 60),
                                        0.4, random.uniform(3, 6), (90, 160, 210), "smoke", 3, grow=10))


class Enemy:
    def __init__(self, kind, pos, wave, armed=None):
        d = ENEMY_TYPES[kind]
        self.kind = kind
        self.pos = V(pos)
        self.vel = V()
        self.r = d["r"]
        self.maxhp = d["hp"] * (1 + 0.1 * (wave - 1)) * (1.35 if armed else 1.0)
        self.hp = self.maxhp
        self.speed = d["speed"] * random.uniform(0.9, 1.12)
        self.dmg = d["dmg"]
        self.color = d["color"]
        self.knock_mult = d["knock"]
        self.armed = armed
        self.flash = 0.0
        self.stun = 0.0
        self.squash = 0.0
        self.dead = False
        self.t = random.uniform(0, 10)
        self.shoot_cd = random.uniform(1.5, 3.0)
        self.charge = 0.0
        self.facing = V(1, 0)
        # conditions
        self.burn = self.burn_dps = 0.0
        self.poison = self.poison_dps = 0.0
        self.poison_stacks = 0
        self.chill = self.frozen = 0.0
        self.chill_stacks = 0
        self.dot = 0.0
        self.dot_t = 0.5

    def update(self, g, dt):
        if self.frozen <= 0:
            self.t += dt
        self.flash = max(0.0, self.flash - dt)
        self.squash = max(0.0, self.squash - dt * 5)
        p = g.player
        to = p.pos - self.pos
        dist = max(1.0, to.length())
        dirp = to / dist
        self.facing = dirp
        if self.stun > 0 or self.frozen > 0:
            self.stun -= dt
            self.vel *= math.exp(-dt * 5)
            self.charge = 0
        else:
            want = dirp * self.speed
            if p.dead:
                want = polar(self.t * 0.3 + id(self) % 7, self.speed * 0.3)
            elif self.kind == "spitter":
                if dist < 260:
                    want = -dirp * self.speed
                elif dist < 380:
                    want = V(-dirp.y, dirp.x) * self.speed * 0.6
                self.shoot_cd -= dt
                if self.shoot_cd <= 0 and dist < 620:
                    self.charge += dt
                    want *= 0.15
                    if self.charge >= 0.5:
                        g.projectiles.append(Projectile(self.pos + dirp * self.r, dirp * 270))
                        g.sfx.play("shot")
                        self.charge = 0
                        self.shoot_cd = random.uniform(2.0, 2.9)
            elif self.kind == "runner":
                want = (dirp + V(-dirp.y, dirp.x) * math.sin(self.t * 5) * 0.5) * self.speed
            if self.chill > 0:
                want *= CHILL_SLOW
            self.vel += (want - self.vel) * min(1.0, dt * 6)
        speed_before = self.vel.length()
        self.pos += self.vel * dt
        slammed = False
        if self.pos.x < WORLD.left + self.r or self.pos.x > WORLD.right - self.r:
            self.pos.x = clamp(self.pos.x, WORLD.left + self.r, WORLD.right - self.r)
            self.vel.x *= -0.35
            slammed = True
        if self.pos.y < WORLD.top + self.r or self.pos.y > WORLD.bottom - self.r:
            self.pos.y = clamp(self.pos.y, WORLD.top + self.r, WORLD.bottom - self.r)
            self.vel.y *= -0.35
            slammed = True
        if slammed and self.stun > 0 and speed_before > 380:
            g.wall_slam(self, speed_before)


class Sword:
    def __init__(self, kind, rarity=0, element="fire", pos=(0, 0)):
        self.kind = kind
        self.rarity = rarity
        self.element = element
        self.t = SWORD_TYPES[kind]
        self.ult = self.t["ult"]
        r = RARITIES[rarity]
        self.damage = self.t["damage"] * r["dmg"]
        self.cooldown = self.t["cooldown"] * r["cd"]
        self.range = self.t["range"] * r["rng"]
        self.ult_max = self.ult["cd"] * r["cd"]
        self.ult_cd = 0.0
        self.scale = r["size"]
        self.color = ELEMENTS[element]["color"]
        self.L = self.t["length"] * self.scale
        self.pos = V(pos)
        self.vel = V()
        self.z = 30.0
        self.ang = -math.pi / 2
        self.state = "idle"
        self.timer = 0.0
        self.cd = random.uniform(0.2, 0.6)
        self.target = None
        self.aim = V()
        self.dir = V(1, 0)
        self.pivot = V()
        self.a0 = self.a1 = 0.0
        self.side = 1
        self.vz = 0.0
        self.boost = 1.0
        self.hit = set()
        self.trail = []
        self.flash = 0.0
        self.jitter = 0.0
        # ultimate state
        self.phase = ""
        self.point = V()
        self.goal = V()
        self.ult_t = 0.0
        self.tick = 0.0
        self.spin = 0.0
        self.victim = None
        self.carried = []

    @property
    def name(self):
        return f"{RARITIES[self.rarity]['name']} {ELEMENTS[self.element]['adj']} {self.t['name']}"

    @property
    def ult_aoe(self):
        return self.t.get("aoe", 0) * self.ult.get("aoe", 0) * self.scale

    def spring(self, target, k, c, dt):
        self.vel += ((target - self.pos) * k - self.vel * c) * dt
        self.pos += self.vel * dt

    def guard_tip(self):
        d = polar(self.ang)
        return self.pos - d * self.L * 0.35, self.pos + d * self.L * 0.65

    # --- targeting
    def acquire(self, g):
        p = g.player.pos
        cands = [e for e in g.enemies if (e.pos - p).length() < self.range + e.r]
        if not cands:
            return None
        if self.kind == "colossus":
            aoe = self.t["aoe"]
            return max(cands, key=lambda e: sum(1 for o in g.enemies if (o.pos - e.pos).length() < aoe) * 1000
                       - (e.pos - p).length())
        if self.kind == "lance":
            far = [e for e in cands if (e.pos - p).length() > 130]
            if far:
                cands = far
        return min(cands, key=lambda e: (e.pos - p).length())

    def begin(self, target, aim, boost=1.0, fast=False):
        self.target = target
        self.aim = V(aim)
        self.boost = boost
        self.state = "windup"
        self.timer = self.t["windup"] * (0.6 if fast else 1.0)
        self.hit.clear()
        self.side = -self.side
        self.jitter = 0.0

    def command(self, g, point):
        if self.state in ("strike", "stuck", "ult"):
            return
        near = [e for e in g.enemies if (e.pos - point).length() < 90]
        tgt = min(near, key=lambda e: (e.pos - point).length()) if near else None
        self.begin(tgt, point, boost=1.5, fast=True)

    # --- update
    def update(self, g, dt, i, n):
        p = g.player
        self.flash = max(0.0, self.flash - dt * 3)
        self.cd -= dt
        self.ult_cd = max(0.0, self.ult_cd - dt)
        if self.target is not None:
            if self.target.dead:
                self.target = None
            else:
                self.aim = V(self.target.pos)

        if p.dead:
            self.vel *= math.exp(-dt * 3)
            self.pos += self.vel * dt
            self.z = max(0.0, self.z - dt * 120)
            self.ang = ang_lerp(self.ang, i * 1.3 + 0.4, min(1.0, dt * 4))
            self.state = "idle"
            self.carried = []
            self.record_trail()
            return

        if random.random() < dt * (30 if self.state == "ult" else 7):
            g.element_fx(self.element, self.pos - V(0, self.z), 1, 6 + self.L * 0.15)

        st = self.state
        kind = self.kind
        if st in ("idle", "recover"):
            orbit = g.time * 0.9 + i * TAU / n
            R = 46 + self.L * 0.22
            slot = p.pos + V(math.cos(orbit) * R, math.sin(orbit) * R * 0.55 - 6)
            if st == "recover":
                self.spring(slot, 90, 13, dt)
                self.timer -= dt
                if self.timer <= 0:
                    self.state = "idle"
            else:
                self.spring(slot, 55, 10, dt)
            zt = 34 + self.L * 0.15 + math.sin(g.time * 2.2 + i * 2.1) * 7
            self.z = lerp(self.z, zt, min(1.0, dt * 5))
            lean = clamp(self.vel.x / 600, -0.8, 0.8)
            self.ang = ang_lerp(self.ang, -math.pi / 2 + lean + math.sin(g.time * 1.7 + i) * 0.12, min(1.0, dt * 7))
            if st == "idle" and self.cd <= 0:
                tgt = self.acquire(g)
                if tgt is not None:
                    self.begin(tgt, tgt.pos)

        elif st == "windup":
            self.timer -= dt
            d0 = norm(self.aim - p.pos, (1, 0))
            if kind == "fang":
                d = norm(self.aim - self.pos, d0)
                self.spring(p.pos + (self.pos - p.pos) * 0.98 - d * 18, 160, 22, dt)
                self.ang = ang_lerp(self.ang, math.atan2(d.y, d.x), min(1.0, dt * 25))
                self.z = lerp(self.z, 14, min(1.0, dt * 12))
            elif kind == "blade":
                self.pivot = self.aim - d0 * (self.L * 0.55)
                amid = math.atan2(d0.y, d0.x)
                self.a0 = amid - self.side * 1.9
                self.a1 = amid + self.side * 1.45
                self.spring(self.pivot + polar(self.a0, self.L * 0.5), 220, 26, dt)
                self.ang = ang_lerp(self.ang, self.a0, min(1.0, dt * 18))
                self.z = lerp(self.z, 10, min(1.0, dt * 12))
            elif kind == "lance":
                self.spring(self.aim - d0 * (self.L * 0.5 + 120), 150, 20, dt)
                self.ang = ang_lerp(self.ang, math.atan2(d0.y, d0.x), min(1.0, dt * 16))
                self.z = lerp(self.z, 12, min(1.0, dt * 10))
                self.jitter = 1 - max(0.0, self.timer) / self.t["windup"]
            elif kind == "colossus":
                self.spring(self.aim, 120, 18, dt)
                self.z = lerp(self.z, 200, min(1.0, dt * 7))
                self.ang = ang_lerp(self.ang, math.pi / 2 + math.sin(g.time * 30) * 0.03, min(1.0, dt * 10))
            if self.timer <= 0:
                self.strike(g)

        elif st == "strike":
            self.timer -= dt
            if kind == "fang":
                prev = V(self.pos)
                d = norm(self.aim - self.pos, self.dir)
                self.dir = norm(self.dir.lerp(d, min(1.0, dt * 14)), d)
                self.vel = self.dir * self.t["speed"]
                self.pos += self.vel * dt
                self.ang = math.atan2(self.dir.y, self.dir.x)
                tip = self.pos + self.dir * self.L * 0.65
                for e in g.enemies:
                    if seg_dist(e.pos, prev, tip) < e.r + 6:
                        g.hit_enemy(e, self.damage * self.boost, self.dir, self.t["knock"], self)
                        self.state = "recover"
                        self.timer = 0.25
                        self.vel = -self.dir * 380 + polar(random.uniform(0, TAU), 160)
                        break
                else:
                    g.parry_projectiles(prev, tip, 8)
                    if self.timer <= 0 or (self.target is None and (self.aim - self.pos).length() < 12):
                        self.state = "recover"
                        self.timer = 0.2
            elif kind == "blade":
                u = 1 - max(0.0, self.timer) / self.dur
                prev_a = self.ang
                a = lerp(self.a0, self.a1, ease_out(u))
                new = self.pivot + polar(a, self.L * 0.5)
                self.vel = (new - self.pos) / max(dt, 1e-4)
                self.pos = new
                self.ang = a
                for aa in (lerp(prev_a, a, 0.5), a):
                    g0 = self.pivot + polar(aa, self.L * 0.12)
                    g1 = self.pivot + polar(aa, self.L * 1.15)
                    for e in g.enemies:
                        if e not in self.hit and seg_dist(e.pos, g0, g1) < e.r + 8:
                            self.hit.add(e)
                            tangent = polar(aa + self.side * math.pi / 2)
                            out = norm(e.pos - p.pos)
                            g.hit_enemy(e, self.damage * self.boost, tangent * 0.6 + out, self.t["knock"], self)
                    g.parry_projectiles(g0, g1, 6)
                if self.timer <= 0:
                    self.state = "recover"
                    self.timer = 0.3
                    self.vel = polar(a + self.side * math.pi / 2, 300)
            elif kind == "lance":
                prev = V(self.pos)
                self.pos += self.dir * self.t["speed"] * dt
                tail = prev - self.dir * self.L * 0.3
                tip = self.pos + self.dir * self.L * 0.65
                for e in g.enemies:
                    if e not in self.hit and seg_dist(e.pos, tail, tip) < e.r + 7:
                        self.hit.add(e)
                        g.hit_enemy(e, self.damage * self.boost, self.dir, self.t["knock"], self)
                g.parry_projectiles(tail, tip, 8)
                if self.timer <= 0:
                    self.state = "recover"
                    self.timer = 0.35
                    self.vel = self.dir * 420
            elif kind == "colossus":
                self.pos = self.pos.lerp(self.impact, min(1.0, dt * 30))
                self.vz += 9000 * dt
                self.z -= self.vz * dt
                if self.z <= 0:
                    self.z = 0
                    self.pos = V(self.impact)
                    g.slam(self, self.impact)
                    self.state = "stuck"
                    self.timer = 0.32

        elif st == "stuck":
            self.timer -= dt
            self.ang = math.pi / 2 + math.sin(self.timer * 60) * 0.08 * self.timer
            if self.timer <= 0:
                self.state = "recover"
                self.timer = 0.4
                self.vel = V(0, -60)

        elif st == "ult":
            self.update_ult(g, dt)

        self.record_trail()

    # --- ultimate
    def ultimate(self, g, point):
        """Start this sword's ultimate aimed at a world point."""
        p = g.player
        self.state = "ult"
        self.ult_cd = self.ult_max
        self.boost = 1.0
        self.jitter = 0.0
        self.hit.clear()
        self.carried = []
        self.victim = None
        self.target = None
        self.point = V(point)
        kind = self.kind
        if kind == "fang":
            # blink straight onto the target area
            g.ring(self.pos, 4, 40, 0.25, self.color, 2)
            self.pos = V(point)
            self.goal = V(point)
            self.phase = "flurry"
            self.ult_t = 1.25
            self.tick = 0.0
            g.ring(point, self.ult["radius"], 10, 0.3, self.color, 3)
            g.sfx.play("dash")
        elif kind == "blade":
            self.phase = "spin"
            self.ult_t = 2.2
            self.tick = 0.15
            self.spin = math.atan2(self.pos.y - point.y, self.pos.x - point.x)
            g.sfx.play("whoosh")
        elif kind == "lance":
            self.phase = "aim"
            self.dir = norm(point - p.pos, p.facing)
            self.ult_t = 0.38
            g.sfx.play("heave")
        elif kind == "colossus":
            self.phase = "rise"
            self.ult_t = 0.75
            g.sfx.play("heave")

    def update_ult(self, g, dt):
        p = g.player
        c = self.point
        kind = self.kind
        self.ult_t -= dt
        if kind == "fang":
            # dart between enemies in the area, striking one per tick
            self.tick -= dt
            if self.tick <= 0:
                self.tick = 0.08
                v = self.victim
                if v is not None and not v.dead:
                    d = norm(v.pos - c, self.dir)
                    g.hit_enemy(v, self.damage * 1.2, d, 120, self, heavy=True)
                    g.add_shake(0.05)
                    g.sfx.play("tick")
                R = self.ult["radius"]
                near = [e for e in g.enemies if not e.dead and (e.pos - c).length() < R + e.r]
                fresh = [e for e in near if e is not v] or near
                if fresh:
                    self.victim = random.choice(fresh)
                    d = norm(self.victim.pos - self.pos)
                    self.goal = self.victim.pos + d * (self.victim.r + 20)
                else:
                    self.victim = None
                    self.goal = c + polar(random.uniform(0, TAU), random.uniform(20, R * 0.7))
            prev = V(self.pos)
            self.pos = self.pos.lerp(self.goal, min(1.0, dt * 28))
            self.vel = (self.pos - prev) / max(dt, 1e-4)
            if self.vel.length_squared() > 400:
                self.dir = norm(self.vel)
                self.ang = math.atan2(self.dir.y, self.dir.x)
            self.z = lerp(self.z, 12, min(1.0, dt * 12))
            if self.ult_t <= 0:
                self.state = "recover"
                self.timer = 0.3
                self.vel = polar(random.uniform(0, TAU), 300)

        elif kind == "blade":
            # whirl around the point, dragging enemies into the blades
            self.spin += dt * 15
            R = self.ult["radius"] * self.scale
            reach = R + self.L * 0.7
            prev = V(self.pos)
            self.pos = self.pos.lerp(c + polar(self.spin, R), min(1.0, dt * 25))
            self.vel = (self.pos - prev) / max(dt, 1e-4)
            self.ang = self.spin
            self.z = lerp(self.z, 10, min(1.0, dt * 12))
            for e in g.enemies:
                to = c - e.pos
                dist = to.length()
                if 8 < dist < reach + 120:
                    e.pos += to / dist * 170 * e.knock_mult * dt
            self.tick -= dt
            if self.tick <= 0:
                self.tick = 0.2
                hit_any = False
                for e in g.enemies:
                    off = e.pos - c
                    if off.length() < reach + e.r:
                        tangent = V(-off.y, off.x)
                        g.hit_enemy(e, self.damage * 0.6, tangent, 40, self, heavy=True)
                        hit_any = True
                if hit_any:
                    g.sfx.play("slash")
                    g.add_shake(0.08)
                g.ring(c, reach * 0.6, reach, 0.2, self.color, 2)
            if self.ult_t <= 0:
                for e in g.enemies:
                    if (e.pos - c).length() < reach + 30 + e.r:
                        g.hit_enemy(e, self.damage * 1.6, e.pos - c, 520, self, heavy=True, stacks=2)
                g.ring(c, 20, reach * 1.6, 0.4, mix(self.color, (255, 255, 255), 0.4), 5)
                g.sparks(c, V(0, -1), 30, self.color, (300, 800), math.pi)
                g.sfx.play("slash")
                g.add_shake(0.35)
                g.hitstop = max(g.hitstop, 0.06)
                self.state = "recover"
                self.timer = 0.3
                self.vel = polar(self.spin + math.pi / 2, 500)

        elif kind == "lance":
            if self.phase == "aim":
                d = self.dir
                self.spring(p.pos - d * 40, 200, 24, dt)
                self.ang = math.atan2(d.y, d.x)
                self.z = lerp(self.z, 14, min(1.0, dt * 12))
                self.jitter = 1 - max(0.0, self.ult_t) / 0.38
                if self.ult_t <= 0:
                    self.phase = "fly"
                    self.jitter = 0.0
                    self.pos = p.pos + d * 10
                    self.ult_t = self.ult["range"] / self.ult["speed"]
                    g.sfx.play("pierce")
                    g.add_shake(0.2, d)
            else:
                d = self.dir
                step = d * self.ult["speed"] * dt
                prev = V(self.pos)
                self.pos += step
                self.vel = d * self.ult["speed"]
                tail = prev - d * self.L * 0.3
                tip = self.pos + d * self.L * 0.65
                for e in g.enemies:
                    if e not in self.hit and seg_dist(e.pos, tail, tip) < e.r + 18:
                        self.hit.add(e)
                        g.hit_enemy(e, self.damage * 2.2, d, 0, self, heavy=True, stacks=2)
                        g.add_shake(0.12, d)
                        if not e.dead:
                            self.carried.append(e)
                self.carried = [e for e in self.carried if not e.dead]
                for e in self.carried:
                    e.pos += step
                    e.vel = V()
                    e.stun = max(e.stun, 0.5)
                g.parry_projectiles(tail, tip, 14)
                at_wall = not WORLD.inflate(-20, -20).collidepoint(tip)
                if self.ult_t <= 0 or at_wall:
                    # fling everything still impaled; walls turn that into slams
                    for e in self.carried:
                        e.vel = d * (1100 if at_wall else 750)
                        e.stun = max(e.stun, 0.6)
                    self.carried = []
                    self.state = "recover"
                    self.timer = 0.35
                    self.vel = -d * 300 if at_wall else d * 420

        elif kind == "colossus":
            if self.phase == "rise":
                self.spring(c, 120, 18, dt)
                self.z = lerp(self.z, 420, min(1.0, dt * 5))
                self.ang = ang_lerp(self.ang, math.pi / 2 + math.sin(g.time * 40) * 0.04, min(1.0, dt * 10))
                self.jitter = 1 - max(0.0, self.ult_t) / 0.75
                if self.ult_t <= 0:
                    self.phase = "fall"
                    self.jitter = 0.0
                    self.vz = 600
            else:
                self.pos = self.pos.lerp(c, min(1.0, dt * 30))
                self.vz += 12000 * dt
                self.z -= self.vz * dt
                if self.z <= 0:
                    self.z = 0
                    self.pos = V(c)
                    aoe = self.ult_aoe
                    g.slam(self, c, aoe, power=2.2, stacks=3)
                    g.fields.append(Field(c, aoe * 1.1, self.element, self.damage, 5.0))
                    g.add_shake(0.4)
                    self.state = "stuck"
                    self.timer = 0.6

    def strike(self, g):
        self.state = "strike"
        self.cd = self.cooldown
        self.jitter = 0.0
        if self.kind == "fang":
            self.dir = norm(self.aim - self.pos)
            self.timer = 0.3
            g.sfx.play("whoosh")
        elif self.kind == "blade":
            self.dur = self.timer = 0.15
            g.sfx.play("whoosh")
        elif self.kind == "lance":
            self.dir = norm(self.aim - self.pos)
            dist = (self.aim - self.pos).length() + 170
            self.timer = dist / self.t["speed"]
            self.ang = math.atan2(self.dir.y, self.dir.x)
            g.sfx.play("whoosh")
        elif self.kind == "colossus":
            self.impact = V(self.aim)
            self.vz = 300
            self.timer = 1.0
            g.sfx.play("heave")

    def record_trail(self):
        gp, tp = self.guard_tip()
        speed = self.vel.length() + abs(self.vz if self.state == "strike" else 0)
        self.trail.append((tp, gp, self.z, clamp(speed / 1400, 0.12, 1.0)))
        if len(self.trail) > 9:
            self.trail.pop(0)


# ---------------------------------------------------------------- game
class Game:
    def __init__(self, screen):
        self.screen = screen
        self.fx = pygame.Surface((W, H))
        self.fonts = {s: pygame.font.Font(None, s) for s in (18, 22, 26, 32, 40, 56, 88)}
        self.sfx = Sfx()
        self.tiles = [make_floor_tile(i) for i in range(4)]
        self.vignette = make_vignette((0, 0, 0), 215)
        self.hurt_vig = make_vignette((170, 10, 30), 255)
        self.show_ranges = False
        self.paused = False
        self.running = True
        self.touch_move = V()
        self.mobile = False
        self.reset()

    def reset(self):
        self.player = Player(WORLD.center)
        c = self.player.pos
        self.swords = [Sword("fang", 0, "poison", c), Sword("blade", 0, "ice", c), Sword("colossus", 0, "fire", c)]
        self.enemies, self.particles, self.texts = [], [], []
        self.motes, self.projectiles, self.pickups = [], [], []
        self.markers, self.decals, self.fields = [], [], []
        self.spawn_queue = []
        self.spawn_timer = 0.0
        self.wave = 0
        self.in_wave = False
        self.break_t = 1.6
        self.time = 0.0
        self.real_time = 0.0
        self.hitstop = 0.0
        self.trauma = 0.0
        self.kick = V()
        self.slowmo = 0.0
        self.slowmo_scale = 1.0
        self.kills = 0
        self.combo = 0
        self.combo_t = 0.0
        self.best_combo = 0
        self.converge_cd = 0.0
        self.banner = None
        self.help_t = 14.0
        self.death_t = 0.0
        self.cam = V(self.player.pos)
        self.off = V()

    # --- helpers
    def w2s(self, p, z=0.0):
        return V(p[0] - self.cam.x + W / 2 + self.off.x, p[1] - self.cam.y + H / 2 + self.off.y - z)

    def mouse_world(self):
        m = pygame.mouse.get_pos()
        return V(m[0] + self.cam.x - W / 2, m[1] + self.cam.y - H / 2)

    def add_shake(self, amount, direction=None):
        self.trauma = min(1.0, self.trauma + amount)
        if direction is not None:
            self.kick += norm(direction) * amount * 16

    def text(self, pos, s, size=26, color=(255, 255, 255), life=0.8, vel=(0, -70)):
        if size not in self.fonts:
            self.fonts[size] = pygame.font.Font(None, size)
        f = self.fonts[size]
        fg = f.render(s, True, color)
        surf = pygame.Surface((fg.get_width() + 3, fg.get_height() + 3), pygame.SRCALPHA)
        surf.blit(f.render(s, True, (0, 0, 0)), (3, 3))
        surf.blit(fg, (0, 0))
        self.texts.append(Text(pos, surf, life, vel))

    def sparks(self, pos, direction, n, color, speed=(200, 650), spread=0.9, life=(0.15, 0.4)):
        base = math.atan2(direction.y, direction.x)
        for _ in range(n):
            a = base + random.uniform(-spread, spread)
            self.particles.append(Particle(pos, polar(a, random.uniform(*speed)), random.uniform(*life),
                                           random.uniform(1.5, 3), color, "spark", 7))

    def ring(self, pos, r0, r1, life, color, width=3):
        p = Particle(pos, (0, 0), life, r0, color, "ring", 0, grow=r1)
        p.z = width
        self.particles.append(p)

    # --- combat
    def hit_enemy(self, e, dmg, direction, knock, sword, heavy=False, stacks=1):
        if e.dead:
            return
        crit = random.random() < 0.12
        if crit:
            dmg *= 2
        if e.frozen > 0:
            dmg *= SHATTER
        dmg = max(1, round(dmg))
        e.hp -= dmg
        e.flash = 0.2 if heavy else 0.11
        e.squash = 1.0
        d = norm(direction)
        k = knock * e.knock_mult * (1.3 if crit else 1.0)
        e.vel = e.vel * 0.3 + d * k
        e.stun = max(e.stun, 0.08 + k / 1500)
        hs = sword.t["hitstop"] * (1.5 if crit else 1.0)
        if not heavy:
            self.hitstop = max(self.hitstop, hs)
            self.add_shake(sword.t["shake"] + (0.1 if crit else 0), d)
        col = mix(sword.color, (255, 255, 255), 0.4)
        self.sparks(e.pos, d, int(clamp(4 + dmg * 0.35, 4, 26)), col,
                    speed=(250, 900) if heavy else (200, 650))
        self.ring(e.pos, e.r * 0.6, e.r + 14 + dmg * 0.4, 0.18, col, 2)
        size = 22 if dmg < 12 else 32 if dmg < 35 else 40
        if crit:
            size = min(56, size + 10)
        self.text(e.pos + V(random.uniform(-10, 10), -e.r - 6), f"{dmg}{'!' if crit else ''}", size,
                  (255, 225, 90) if crit else (255, 255, 255), 0.75 if not crit else 1.0,
                  (d.x * 60, -90 - dmg))
        if not heavy:
            self.sfx.play(sword.t["sound"])
        self.sfx.play("thud")
        if e.hp <= 0:
            self.kill(e, d, heavy or crit)
        else:
            self.afflict(e, sword.element, sword.damage, stacks)

    def afflict(self, e, element, power, stacks=1):
        """Apply an elemental condition. `power` is the source sword's base damage."""
        col = ELEMENTS[element]["color"]
        if element == "fire":
            dps = (1.5 + power * 0.2) * stacks
            e.burn_dps = max(e.burn_dps, dps) if e.burn > 0 else dps
            e.burn = BURN_TIME
        elif element == "poison":
            dps = 1 + power * 0.06
            e.poison_dps = max(e.poison_dps, dps) if e.poison > 0 else dps
            e.poison_stacks = min(POISON_MAX, e.poison_stacks + stacks)
            e.poison = POISON_TIME
        elif element == "ice":
            e.chill = CHILL_TIME
            if e.frozen > 0:
                return
            e.chill_stacks += stacks
            if e.chill_stacks >= FREEZE_STACKS:
                e.chill_stacks = 0
                e.frozen = FREEZE_TIME * (0.6 if e.kind == "brute" else 1.0)
                e.vel *= 0.2
                self.ring(e.pos, e.r, e.r * 2.4, 0.3, col, 3)
                self.element_fx("ice", e.pos, 10, e.r)
                self.text(e.pos + V(0, -e.r - 20), "FROZEN", 22, col, 0.7)
                self.sfx.play("parry")

    def element_fx(self, element, pos, n=1, spread=8.0):
        col = ELEMENTS[element]["color"]
        for _ in range(n):
            q = V(pos) + polar(random.uniform(0, TAU), random.uniform(0, spread))
            if element == "fire":
                self.particles.append(Particle(q, (random.uniform(-25, 25), random.uniform(-150, -70)),
                                               random.uniform(0.3, 0.55), random.uniform(1.5, 3),
                                               mix(col, (255, 220, 90), random.random()), "spark", 2))
            elif element == "ice":
                self.particles.append(Particle(q, polar(random.uniform(0, TAU), random.uniform(10, 50)),
                                               random.uniform(0.4, 0.7), random.uniform(1, 2.5),
                                               mix(col, (255, 255, 255), 0.5), "dot", 3))
            else:
                self.particles.append(Particle(q, (random.uniform(-10, 10), random.uniform(-45, -15)),
                                               random.uniform(0.5, 0.9), random.uniform(1.5, 3.5),
                                               dim(col, random.uniform(0.6, 1.0)), "dot", 1))

    def update_conditions(self, dt):
        for e in self.enemies:
            if e.dead:
                continue
            e.frozen = max(0.0, e.frozen - dt)
            e.chill = max(0.0, e.chill - dt)
            if e.chill <= 0:
                e.chill_stacks = 0
            dps = 0.0
            if e.burn > 0:
                e.burn -= dt
                dps += e.burn_dps
                if random.random() < dt * 14:
                    self.element_fx("fire", e.pos, 1, e.r * 0.8)
            if e.poison > 0:
                e.poison -= dt
                dps += e.poison_dps * e.poison_stacks
                if e.poison <= 0:
                    e.poison_stacks = 0
                if random.random() < dt * (3 + 2 * e.poison_stacks):
                    self.element_fx("poison", e.pos, 1, e.r * 0.8)
            if e.chill > 0 and random.random() < dt * 5:
                self.element_fx("ice", e.pos, 1, e.r)
            if dps <= 0:
                e.dot = 0.0
                continue
            e.dot += dps * dt
            e.dot_t -= dt
            if e.dot_t <= 0:
                e.dot_t = 0.5
                dmg = int(e.dot)
                if dmg >= 1:
                    e.dot -= dmg
                    e.hp -= dmg
                    fire = e.burn > 0 and (e.poison <= 0 or e.burn_dps >= e.poison_dps * e.poison_stacks)
                    col = ELEMENTS["fire" if fire else "poison"]["color"]
                    self.text(e.pos + V(random.uniform(-12, 12), -e.r), str(dmg), 20, col, 0.6, (0, -60))
                    if e.hp <= 0:
                        self.kill(e, V(0, -1), False)

    def update_fields(self, dt):
        for f in self.fields:
            f.life -= dt
            f.tick -= dt
            if f.tick <= 0:
                f.tick = 0.5
                for e in self.enemies:
                    if not e.dead and (e.pos - f.pos).length() < f.radius + e.r:
                        self.afflict(e, f.element, f.power)
            if random.random() < dt * f.radius * 0.12:
                a = random.uniform(0, TAU)
                q = f.pos + V(math.cos(a), math.sin(a) * 0.6) * random.uniform(0, f.radius)
                self.element_fx(f.element, q, 1, 4)
        self.fields = [f for f in self.fields if f.life > 0]

    def kill(self, e, d, big):
        e.dead = True
        self.kills += 1
        self.combo += 1
        self.combo_t = 2.6
        self.best_combo = max(self.best_combo, self.combo)
        if self.combo in (10, 25, 50, 100):
            self.text(self.player.pos + V(0, -60), f"{self.combo} CHAIN!", 56, (255, 200, 90), 1.4, (0, -40))
        for _ in range(16 + (14 if big else 0)):
            v = polar(random.uniform(0, TAU), random.uniform(60, 360)) + d * random.uniform(100, 500)
            self.particles.append(Particle(e.pos, v, random.uniform(0.3, 0.7), random.uniform(2, 4.5),
                                           e.color, "dot", 5))
        for _ in range(6 + e.r // 3):
            v = polar(random.uniform(0, TAU), random.uniform(40, 220)) + d * 200
            self.particles.append(Particle(e.pos, v, random.uniform(0.6, 1.1), random.uniform(3, 6),
                                           dim(e.color, 0.4), "debris", 3, z=8, vz=random.uniform(150, 420)))
        self.ring(e.pos, e.r, e.r * 3.2, 0.3, mix(e.color, (255, 255, 255), 0.5), 3)
        if e.burn > 0:
            # burning foes ignite whoever stands next to them
            fire = ELEMENTS["fire"]["color"]
            for o in self.enemies:
                if o is not e and not o.dead and (o.pos - e.pos).length() < e.r + o.r + 70:
                    o.burn_dps = max(o.burn_dps if o.burn > 0 else 0.0, e.burn_dps * 0.6)
                    o.burn = max(o.burn, BURN_TIME * 0.7)
            self.ring(e.pos, e.r, e.r + 80, 0.3, fire, 3)
            self.element_fx("fire", e.pos, 14, e.r)
        if e.frozen > 0:
            self.element_fx("ice", e.pos, 18, e.r)
            self.sparks(e.pos, V(0, -1), 14, ELEMENTS["ice"]["color"], (150, 450), math.pi)
        for _ in range(3):
            self.motes.append(Mote(e.pos))
        self.sfx.play("pop")
        if e.armed:
            kind, rarity, element = e.armed
            self.pickups.append(Pickup(kind, rarity, element, e.pos))
            self.ring(e.pos, 10, 90, 0.5, RARITIES[rarity]["color"], 2)
            self.text(e.pos + V(0, -30),
                      f"{RARITIES[rarity]['name']} {ELEMENTS[element]['adj']} {SWORD_TYPES[kind]['name']}", 26,
                      RARITIES[rarity]["color"], 1.3, (0, -40))

    def slam(self, sword, point, aoe=None, power=1.0, stacks=1):
        aoe = aoe or sword.t["aoe"] * sword.scale
        hit_any = False
        for e in list(self.enemies):
            dist = (e.pos - point).length()
            if dist < aoe + e.r:
                fall = 1 - 0.45 * clamp(dist / aoe, 0, 1)
                self.hit_enemy(e, sword.damage * sword.boost * power * fall, e.pos - point,
                               sword.t["knock"] * fall, sword, heavy=True, stacks=stacks)
                hit_any = True
        for pr in self.projectiles:
            if (pr.pos - point).length() < aoe:
                pr.dead = True
        self.sfx.play("boom")
        self.hitstop = max(self.hitstop, sword.t["hitstop"] if hit_any else 0.04)
        self.add_shake(sword.t["shake"] if hit_any else 0.35, V(0, 1))
        col = sword.color
        self.ring(point, 10, aoe * 1.35, 0.35, mix(col, (255, 255, 255), 0.5), 6)
        self.ring(point, 6, aoe * 0.8, 0.22, (255, 255, 255), 3)
        for _ in range(26):
            a = random.uniform(0, TAU)
            self.particles.append(Particle(point + polar(a, aoe * 0.3), polar(a, random.uniform(200, 520)),
                                           random.uniform(0.5, 0.9), random.uniform(8, 14), (40, 34, 52),
                                           "smoke", 4, grow=30))
        for _ in range(18):
            a = random.uniform(0, TAU)
            self.particles.append(Particle(point, polar(a, random.uniform(80, 340)), random.uniform(0.7, 1.2),
                                           random.uniform(3, 7), (60, 52, 72), "debris", 2, z=4,
                                           vz=random.uniform(250, 600)))
        self.sparks(point, V(0, -1), 30, mix(col, (255, 255, 255), 0.3), (200, 800), math.pi, (0.2, 0.5))
        self.element_fx(sword.element, point, 20, aoe * 0.6)
        cracks = []
        for _ in range(random.randint(5, 8)):
            p = V(point)
            a = random.uniform(0, TAU)
            pts = [V(p)]
            for _ in range(random.randint(3, 5)):
                a += random.uniform(-0.6, 0.6)
                p = p + polar(a, random.uniform(14, 30))
                pts.append(V(p))
            cracks.append(pts)
        self.decals.append([cracks, 7.0])

    def wall_slam(self, e, speed):
        e.stun = min(e.stun, 0.15)
        dmg = round(6 + (speed - 380) * 0.04)
        e.hp -= dmg
        e.flash = 0.12
        self.text(e.pos + V(0, -e.r - 10), f"SLAM {dmg}", 26, (255, 150, 120), 0.8)
        self.add_shake(0.18)
        self.hitstop = max(self.hitstop, 0.04)
        self.sfx.play("thud")
        for _ in range(10):
            self.particles.append(Particle(e.pos, polar(random.uniform(0, TAU), random.uniform(80, 240)),
                                           0.5, random.uniform(5, 9), (40, 34, 52), "smoke", 4, grow=14))
        if e.hp <= 0 and not e.dead:
            self.kill(e, norm(-e.vel), True)

    def parry_projectiles(self, a, b, pad):
        for pr in self.projectiles:
            if not pr.dead and seg_dist(pr.pos, a, b) < pr.r + pad:
                pr.dead = True
                self.sparks(pr.pos, -pr.vel, 10, (200, 255, 160), (150, 450))
                self.ring(pr.pos, 4, 30, 0.2, (200, 255, 160), 2)
                self.sfx.play("parry")
                self.hitstop = max(self.hitstop, 0.025)

    def hurt_player(self, dmg, source):
        p = self.player
        if p.iframes > 0 or p.dead:
            return
        p.hp -= dmg
        p.iframes = 0.8
        p.hurt_flash = 1.0
        d = norm(p.pos - source)
        p.vel = d * 420
        self.add_shake(0.45, d)
        self.hitstop = max(self.hitstop, 0.07)
        self.sfx.play("hurt")
        self.text(p.pos + V(0, -30), f"-{dmg}", 32, (255, 90, 90), 0.8)
        self.sparks(p.pos, d, 14, (255, 110, 110))
        if p.hp <= 0:
            p.hp = 0
            p.dead = True
            self.slowmo = 1.4
            self.slowmo_scale = 0.25
            self.death_t = 0.0
            self.ring(p.pos, 10, 220, 0.8, (120, 220, 255), 4)

    def converge(self, point=None):
        if self.converge_cd > 0 or self.player.dead:
            return
        point = self.mouse_world() if point is None else V(point)
        to = point - self.player.pos
        if to.length() > 460:
            point = self.player.pos + to.normalize() * 460
        for s in self.swords:
            s.command(self, point)
        self.converge_cd = CONVERGE_CD
        self.ring(point, 60, 8, 0.35, (180, 220, 255), 2)
        self.sfx.play("chime")

    def ultimate(self, idx, point=None):
        p = self.player
        if p.dead or idx >= len(self.swords):
            return
        s = self.swords[idx]
        if s.state == "ult":
            return
        if s.ult_cd > 0:
            self.text(p.pos + V(0, -46), f"{s.ult['name']} {s.ult_cd:.0f}s", 22, (120, 110, 150), 0.5)
            return
        point = self.mouse_world() if point is None else V(point)
        to = point - p.pos
        if not s.ult["shot"] and to.length() > s.ult["range"]:
            point = p.pos + to.normalize() * s.ult["range"]
        s.ultimate(self, point)
        self.text(p.pos + V(0, -56), s.ult["name"].upper(), 32, mix(s.color, (255, 255, 255), 0.3), 1.0, (0, -50))

    def swap(self, idx):
        p = self.player
        near = [pk for pk in self.pickups if (pk.pos - p.pos).length() < 80]
        if not near or idx >= len(self.swords):
            return
        pk = min(near, key=lambda k: (k.pos - p.pos).length())
        old = self.swords[idx]
        new = Sword(pk.kind, pk.rarity, pk.element, pk.pos)
        # the slot keeps its ultimate recharge so swapping can't reset it
        new.ult_cd = new.ult_max * old.ult_cd / old.ult_max
        new.z = 10
        new.flash = 1.0
        new.cd = 0.4
        new.vel = V(0, -200)
        self.swords[idx] = new
        self.pickups.remove(pk)
        self.pickups.append(Pickup(old.kind, old.rarity, old.element, pk.pos + V(random.uniform(-20, 20), 24)))
        col = RARITIES[pk.rarity]["color"]
        self.ring(pk.pos, 8, 110, 0.45, col, 3)
        self.sparks(pk.pos, V(0, -1), 24, col, (150, 500), math.pi)
        self.text(p.pos + V(0, -50), new.name, 32, col, 1.2, (0, -50))
        self.sfx.play("chime")

    # --- waves
    def start_wave(self):
        self.wave += 1
        w = self.wave
        n = 5 + w * 3
        pool = [("husk", 6), ("runner", 2.5 if w >= 2 else 0), ("spitter", 2 if w >= 3 else 0),
                ("brute", 0.6 + 0.25 * w if w >= 2 else 0)]
        pool = [(k, v) for k, v in pool if v > 0]
        self.spawn_queue = []
        for j in range(n):
            kind = weighted(pool)
            armed = None
            chance = ENEMY_TYPES[kind]["armed"]
            if (w == 1 and j < 2) or random.random() < chance:
                skind = "lance" if (w == 1 and j == 0) else weighted(DROP_WEIGHTS)
                roll = random.random()
                bonus = 0.15 if kind == "brute" else 0.0
                rarity = 2 if roll < min(0.25, 0.02 + 0.02 * w) + bonus * 0.5 else \
                    1 if roll < min(0.55, 0.16 + 0.04 * w) + bonus else 0
                armed = (skind, rarity, random.choice(list(ELEMENTS)))
            self.spawn_queue.append((kind, armed))
        self.spawn_timer = 0.3
        self.in_wave = True
        self.banner = [f"WAVE {w}", "armed foes carry swords - kill them and claim one", 2.4]
        self.sfx.play("gong")

    def spawn_point(self):
        p = self.player.pos
        for _ in range(12):
            q = p + polar(random.uniform(0, TAU), random.uniform(420, 720))
            q.x = clamp(q.x, WORLD.left + 50, WORLD.right - 50)
            q.y = clamp(q.y, WORLD.top + 50, WORLD.bottom - 50)
            if (q - p).length() > 320:
                return q
        return q

    # --- events
    def auto_aim(self):
        """Touch aiming: the nearest enemy, or ahead of the player."""
        p = self.player
        targets = [e for e in self.enemies if not e.dead]
        if targets:
            return V(min(targets, key=lambda e: (e.pos - p.pos).length_squared()).pos)
        return p.pos + p.facing * 300

    def poll_touch(self):
        if sys.platform != "emscripten":
            return
        read_input = getattr(platform.window, "swordsterReadInput", None)
        if not read_input:
            return
        state = json.loads(read_input())
        self.mobile = state["enabled"]
        self.touch_move = V(state["move"])
        for action in state["actions"]:
            name = action["name"]
            if name == "pause":
                self.paused = not self.paused
            elif name == "suspend":
                self.paused = True
            elif name == "restart":
                self.reset()
                self.paused = False
            elif self.paused:
                continue
            elif name == "dash":
                # Use this frame's stick direction, even before Player.update.
                self.player.move = V(self.touch_move)
                self.player.dash(self)
            elif name == "converge":
                self.converge(self.auto_aim())
            elif name == "aim":
                self.converge(V(action["x"] + self.cam.x - W / 2,
                                action["y"] + self.cam.y - H / 2))
            elif name == "swap":
                self.swap(action["slot"])
            elif name == "ult":
                self.ultimate(action["slot"], self.auto_aim())
            elif name == "ranges":
                self.show_ranges = not self.show_ranges

    def handle(self, ev):
        if ev.type == pygame.QUIT:
            self.running = False
        elif ev.type == pygame.KEYDOWN:
            k = ev.key
            if k in (pygame.K_p, pygame.K_ESCAPE):
                self.paused = not self.paused
            elif self.player.dead:
                # R doubles as an ultimate key; only restart once the death screen is up
                if k == pygame.K_r and self.death_t > 0.8:
                    self.reset()
            elif self.paused:
                return
            elif k in (pygame.K_SPACE, pygame.K_LSHIFT, pygame.K_RSHIFT):
                self.player.dash(self)
            elif k in (pygame.K_q, pygame.K_e, pygame.K_r):
                self.ultimate({pygame.K_q: 0, pygame.K_e: 1, pygame.K_r: 2}[k])
            elif k in (pygame.K_1, pygame.K_2, pygame.K_3):
                self.swap(k - pygame.K_1)
            elif k in (pygame.K_TAB, pygame.K_g):
                self.show_ranges = not self.show_ranges
            elif k == pygame.K_h:
                self.help_t = 0 if self.help_t > 0 else 9999
        elif ev.type == pygame.MOUSEBUTTONDOWN and not self.paused and not self.mobile:
            if ev.button in (1, 3):
                self.converge()

    # --- update
    def update(self, dt):
        if self.paused:
            return
        self.real_time += dt
        self.trauma = max(0.0, self.trauma - dt * 1.6)
        self.kick *= math.exp(-dt * 12)
        if self.hitstop > 0:
            self.hitstop -= dt
            return
        if self.slowmo > 0:
            self.slowmo -= dt
            dt *= self.slowmo_scale
        self.time += dt
        self.help_t -= dt
        p = self.player
        if p.dead:
            self.death_t += dt

        p.update(self, dt, pygame.key.get_pressed())
        n = len(self.swords)
        for i, s in enumerate(self.swords):
            s.update(self, dt, i, n)

        for e in self.enemies:
            e.update(self, dt)
        self.separate()
        self.update_conditions(dt)
        self.update_fields(dt)
        for e in self.enemies:
            if not e.dead and e.frozen <= 0 and (e.pos - p.pos).length() < e.r + p.r:
                self.hurt_player(e.dmg, e.pos)
                e.vel = norm(e.pos - p.pos) * 200
                e.stun = 0.2
        self.enemies = [e for e in self.enemies if not e.dead]

        for pr in self.projectiles:
            pr.pos += pr.vel * dt
            pr.life -= dt
            if pr.life <= 0 or not WORLD.collidepoint(pr.pos):
                pr.dead = True
            elif (pr.pos - p.pos).length() < pr.r + p.r and p.iframes <= 0 and not p.dead:
                pr.dead = True
                self.hurt_player(8, pr.pos)
        self.projectiles = [pr for pr in self.projectiles if not pr.dead]

        self.update_particles(dt)

        for m in self.motes:
            m.t += dt
            to = p.pos - m.pos
            dist = to.length()
            if m.t > 0.25:
                m.vel += norm(to) * 2400 * dt
                m.vel *= math.exp(-dt * 2.5)
            else:
                m.vel *= math.exp(-dt * 5)
            m.pos += m.vel * dt
            if dist < 18 and m.t > 0.25:
                m.t = -1
                if not p.dead:
                    p.hp = min(p.maxhp, p.hp + 0.5)
        self.motes = [m for m in self.motes if m.t >= 0]

        for pk in self.pickups:
            pk.t += dt
            pk.life -= dt
        self.pickups = [pk for pk in self.pickups if pk.life > 0]

        for t in self.texts:
            t.pos += t.vel * dt
            t.vel *= math.exp(-dt * 4)
            t.life -= dt
        self.texts = [t for t in self.texts if t.life > 0]

        for dcl in self.decals:
            dcl[1] -= dt
        self.decals = [dcl for dcl in self.decals if dcl[1] > 0]

        self.combo_t -= dt
        if self.combo_t <= 0:
            self.combo = 0
        self.converge_cd = max(0.0, self.converge_cd - dt)
        if self.banner:
            self.banner[2] -= dt
            if self.banner[2] <= 0:
                self.banner = None

        self.update_waves(dt)

        target = p.pos + p.vel * 0.12
        self.cam += (target - self.cam) * (1 - math.exp(-dt * 7))
        self.cam.x = clamp(self.cam.x, WORLD.left + W / 2 - 140, WORLD.right - W / 2 + 140)
        self.cam.y = clamp(self.cam.y, WORLD.top + H / 2 - 140, WORLD.bottom - H / 2 + 140)

    def separate(self):
        es = self.enemies
        for i in range(len(es)):
            a = es[i]
            for j in range(i + 1, len(es)):
                b = es[j]
                d = b.pos - a.pos
                rr = a.r + b.r
                if abs(d.x) > rr or abs(d.y) > rr:
                    continue
                dist = d.length()
                if dist >= rr or dist == 0:
                    continue
                nrm = d / dist
                overlap = rr - dist
                ma, mb = a.r * a.r, b.r * b.r
                a.pos -= nrm * overlap * mb / (ma + mb)
                b.pos += nrm * overlap * ma / (ma + mb)
                # bowling: a launched enemy knocks into others
                for x, y, s in ((a, b, 1), (b, a, -1)):
                    sp = x.vel.length()
                    if x.stun > 0 and sp > 340 and x.vel.dot(nrm * s) > 0:
                        y.vel += x.vel * 0.55 * x.r / y.r * 0.6
                        y.stun = max(y.stun, 0.25)
                        y.flash = 0.08
                        y.hp -= 3
                        x.vel *= 0.6
                        self.add_shake(0.06)
                        self.sparks((a.pos + b.pos) / 2, x.vel, 5, (255, 220, 200), (120, 300))
                        if y.hp <= 0 and not y.dead:
                            self.kill(y, norm(x.vel), True)

    def update_particles(self, dt):
        alive = []
        for pt in self.particles:
            pt.life -= dt
            if pt.life <= 0:
                continue
            pt.pos += pt.vel * dt
            if pt.drag:
                pt.vel *= math.exp(-dt * pt.drag)
            if pt.kind == "debris":
                pt.vz -= 1400 * dt
                pt.z += pt.vz * dt
                if pt.z < 0:
                    pt.z = 0
                    pt.vz = -pt.vz * 0.35
                    pt.vel *= 0.6
            alive.append(pt)
        if len(alive) > 700:
            alive = alive[-700:]
        self.particles = alive

    def update_waves(self, dt):
        if self.player.dead:
            return
        if self.spawn_queue:
            self.spawn_timer -= dt
            if self.spawn_timer <= 0:
                kind, armed = self.spawn_queue.pop(0)
                self.markers.append(Marker(kind, self.spawn_point(), armed))
                self.spawn_timer = max(0.12, 0.42 - self.wave * 0.02)
        for m in self.markers:
            m.t -= dt
            if m.t <= 0:
                self.enemies.append(Enemy(m.kind, m.pos, self.wave, m.armed))
                self.ring(m.pos, 6, 50, 0.3, (200, 80, 120), 2)
                for _ in range(8):
                    self.particles.append(Particle(m.pos, polar(random.uniform(0, TAU), 120), 0.5, 7,
                                                   (36, 22, 40), "smoke", 3, grow=10))
        self.markers = [m for m in self.markers if m.t > 0]
        if self.in_wave and not self.spawn_queue and not self.markers and not self.enemies:
            self.in_wave = False
            self.break_t = 3.2
            self.slowmo = 0.7
            self.slowmo_scale = 0.3
            self.banner = ["WAVE CLEARED", "grab dropped swords: stand on one, press 1 / 2 / 3", 2.6]
        if not self.in_wave:
            self.break_t -= dt
            if self.break_t <= 0:
                self.start_wave()

    # --- draw
    def draw(self):
        scr, fx = self.screen, self.fx
        tr = self.trauma * self.trauma
        self.off = V(random.uniform(-1, 1), random.uniform(-1, 1)) * tr * 26 + self.kick
        scr.fill(BG)
        fx.fill((0, 0, 0))
        self.draw_floor()
        p = self.player

        # decals
        for cracks, life in self.decals:
            k = clamp(life / 7.0, 0, 1)
            col = mix(FLOOR_DARK, (4, 3, 6), k)
            for pts in cracks:
                spts = [self.w2s(q) for q in pts]
                pygame.draw.lines(scr, col, False, spts, 3)
                if life > 6.0:
                    pygame.draw.lines(fx, dim((255, 160, 60), (life - 6.0)), False, spts, 2)

        # spawn markers
        for m in self.markers:
            sp = self.w2s(m.pos)
            u = 1 - m.t / m.max
            pygame.draw.circle(scr, (30, 14, 28), sp, 8 + u * 20)
            pygame.draw.circle(scr, (130, 40, 80), sp, 8 + u * 20, 2)
            draw_glow(fx, sp, 20 + u * 30, (110, 30, 70))

        # elemental ground from Cataclysm
        for f in self.fields:
            k = clamp(f.life / f.max * 3, 0, 1)
            col = ELEMENTS[f.element]["color"]
            rect = pygame.Rect(0, 0, f.radius * 2, f.radius * 1.2)
            rect.center = self.w2s(f.pos)
            pygame.draw.ellipse(fx, dim(col, 0.16 * k), rect)
            pulse = 0.5 + 0.2 * math.sin(self.time * 6 + f.pos.x)
            pygame.draw.ellipse(scr, dim(col, pulse * k), rect, 2)

        # telegraphs
        for s in self.swords:
            if s.kind == "colossus" and s.state in ("windup", "strike"):
                tgt = s.aim if s.state == "windup" else s.impact
                u = 1 - clamp(s.timer / s.t["windup"], 0, 1) if s.state == "windup" else 1
                self.draw_impact(tgt, s.t["aoe"] * s.scale, u, s.color)
            elif s.state != "ult":
                continue
            elif s.kind == "colossus":
                u = 1 - clamp(s.ult_t / 0.75, 0, 1) if s.phase == "rise" else 1
                self.draw_impact(s.point, s.ult_aoe, u, s.color)
            elif s.kind == "lance" and s.phase == "aim":
                a = self.w2s(p.pos)
                b = self.w2s(p.pos + s.dir * s.ult["range"])
                u = 1 - clamp(s.ult_t / 0.38, 0, 1)
                pygame.draw.line(scr, dim(s.color, 0.25 + 0.35 * u), a, b, 2)
                pygame.draw.line(fx, dim(s.color, 0.15 + 0.25 * u), a, b, 24)
            elif s.kind in ("fang", "blade"):
                R = s.ult["radius"] * (1 if s.kind == "fang" else s.scale) + (0 if s.kind == "fang" else s.L * 0.7)
                rect = pygame.Rect(0, 0, R * 2, R * 1.2)
                rect.center = self.w2s(s.point)
                pygame.draw.ellipse(scr, dim(s.color, 0.45), rect, 2)
                pygame.draw.ellipse(fx, dim(s.color, 0.08), rect)

        # shadows
        self.shadow(p.pos, 16, 7)
        for e in self.enemies:
            self.shadow(e.pos, e.r * 1.05, e.r * 0.45)
        for s in self.swords:
            k = clamp(1 - s.z / 260, 0.3, 1)
            self.shadow(s.pos, s.L * 0.28 * k, 5 * k)

        # pickups
        for pk in self.pickups:
            self.draw_pickup(pk)

        # projectiles
        for pr in self.projectiles:
            sp = self.w2s(pr.pos, 10)
            pygame.draw.circle(scr, (170, 240, 120), sp, pr.r)
            pygame.draw.circle(scr, (240, 255, 220), sp, pr.r * 0.5)
            draw_glow(fx, sp, 22, (60, 120, 30))

        # enemies & player
        for e in sorted(self.enemies, key=lambda e: e.pos.y):
            self.draw_enemy(e)
        self.draw_player()

        # debris / smoke (world-space, normal blend)
        for pt in self.particles:
            u = pt.life / pt.max
            if pt.kind == "smoke":
                r = pt.size + pt.grow * (1 - u)
                pygame.draw.circle(scr, mix(FLOOR_DARK, pt.color, u), self.w2s(pt.pos), r)
            elif pt.kind == "debris":
                sp = self.w2s(pt.pos, pt.z)
                s = pt.size * (0.5 + 0.5 * u)
                pygame.draw.rect(scr, pt.color, (sp.x - s / 2, sp.y - s / 2, s, s))

        # additive FX: trails, glows, sparks, rings
        for s in self.swords:
            self.draw_trail(s)
            gp = self.w2s(s.pos, s.z)
            rcol = RARITIES[s.rarity]["color"] if s.rarity else s.color
            draw_glow(fx, gp, s.L * 0.75, dim(rcol, 0.22 + 0.3 * s.flash))
        for pt in self.particles:
            u = pt.life / pt.max
            if pt.kind == "spark":
                sp = self.w2s(pt.pos)
                pygame.draw.line(fx, dim(pt.color, u), sp, sp - pt.vel * 0.03, max(1, int(pt.size * u + 0.5)))
            elif pt.kind == "dot":
                pygame.draw.circle(fx, dim(pt.color, u), self.w2s(pt.pos), max(1, pt.size * u))
            elif pt.kind == "ring":
                r = lerp(pt.size, pt.grow, ease_out(1 - u))
                w = max(1, int(pt.z * u + 0.5))
                if r > w:
                    pygame.draw.circle(fx, dim(pt.color, u), self.w2s(pt.pos), r, w)
            elif pt.kind == "ghost":
                pygame.draw.circle(fx, dim(pt.color, u * 0.8), self.w2s(pt.pos, 10), pt.size)
        for m in self.motes:
            sp = self.w2s(m.pos, 12)
            draw_glow(fx, sp, 12, (60, 160, 200))
            pygame.draw.circle(fx, (180, 240, 255), sp, 2)
        scr.blit(fx, (0, 0), special_flags=pygame.BLEND_ADD)

        # swords on top
        for s in sorted(self.swords, key=lambda s: s.pos.y):
            sp = self.w2s(s.pos, s.z)
            if s.jitter:
                sp += V(random.uniform(-1, 1), random.uniform(-1, 1)) * s.jitter * 3
            draw_sword(scr, s.kind, sp, s.ang, s.scale, s.color, s.flash)

        if self.show_ranges and not p.dead:
            for s in self.swords:
                pygame.draw.circle(scr, dim(s.color, 0.6), self.w2s(p.pos), s.range, 1)

        for t in self.texts:
            u = t.life / t.max
            t.surf.set_alpha(int(255 * clamp(u * 2.5, 0, 1)))
            sp = self.w2s(t.pos)
            scr.blit(t.surf, (sp.x - t.surf.get_width() / 2, sp.y - t.surf.get_height() / 2))

        scr.blit(self.vignette, (0, 0))
        if p.hurt_flash > 0:
            self.hurt_vig.set_alpha(int(200 * p.hurt_flash))
            scr.blit(self.hurt_vig, (0, 0))
        elif p.hp < p.maxhp * 0.3 and not p.dead:
            self.hurt_vig.set_alpha(int(60 + 40 * math.sin(self.real_time * 5)))
            scr.blit(self.hurt_vig, (0, 0))
        self.draw_hud()

    def draw_impact(self, pos, aoe, u, color):
        sp = self.w2s(pos)
        rect = pygame.Rect(0, 0, aoe * 2, aoe * 1.2)
        rect.center = sp
        pygame.draw.ellipse(self.screen, dim(color, 0.3), rect, 2)
        r2 = rect.inflate(-aoe * 2 * (1 - u), -aoe * 1.2 * (1 - u))
        if r2.width > 4 and r2.height > 4:
            pygame.draw.ellipse(self.screen, dim(color, 0.6), r2, 2)
        draw_glow(self.fx, sp, aoe * 0.7, dim(color, 0.12 + 0.2 * u))

    def shadow(self, pos, rx, ry):
        sp = self.w2s(pos)
        pygame.draw.ellipse(self.screen, SHADOW,
                            (sp.x - rx, sp.y - ry, max(2, rx * 2), max(2, ry * 2)))

    def draw_floor(self):
        scr = self.screen
        left = self.cam.x - W / 2 - self.off.x
        top = self.cam.y - H / 2 - self.off.y
        tx0, ty0 = int(left // 256), int(top // 256)
        for ty in range(ty0, ty0 + H // 256 + 2):
            for tx in range(tx0, tx0 + W // 256 + 2):
                if tx < 0 or ty < 0 or tx * 256 >= WORLD.right or ty * 256 >= WORLD.bottom:
                    continue
                tile = self.tiles[(tx * 73856093 ^ ty * 19349663) % 4]
                scr.blit(tile, (tx * 256 - left, ty * 256 - top))
        r = pygame.Rect(0, 0, WORLD.width, WORLD.height)
        r.topleft = self.w2s(WORLD.topleft)
        # cover the parts of tiles past the world edge
        pygame.draw.rect(scr, BG, (r.right, r.top - 300, 400, r.height + 600))
        pygame.draw.rect(scr, BG, (r.left - 400, r.bottom, r.width + 800, 300))
        pygame.draw.rect(scr, (70, 46, 110), r, 3)
        pygame.draw.rect(self.fx, (40, 24, 70), r.inflate(6, 6), 4)

    def draw_pickup(self, pk):
        scr, fx = self.screen, self.fx
        col = RARITIES[pk.rarity]["color"]
        sc = SWORD_TYPES[pk.kind]
        ecol = ELEMENTS[pk.element]["color"]
        bob = math.sin(pk.t * 3) * 3
        L = sc["length"] * RARITIES[pk.rarity]["size"]
        ground = self.w2s(pk.pos)
        if pk.life < 6 and int(pk.life * 8) % 2 == 0:
            return
        rect = pygame.Rect(0, 0, 44, 18)
        rect.center = ground
        pygame.draw.ellipse(scr, dim(col, 0.35), rect, 2)
        if pk.rarity:
            beam_h = 120 + 60 * pk.rarity
            for k in range(6):
                w = 22 - k * 3
                pygame.draw.rect(fx, dim(col, 0.05 + 0.03 * k), (ground.x - w / 2, ground.y - beam_h, w, beam_h))
        draw_glow(fx, ground, 34 + 8 * pk.rarity, dim(col, 0.2))
        draw_glow(fx, ground, 26, dim(ecol, 0.3))
        sp = self.w2s(pk.pos, L * 0.6 + bob)
        draw_sword(scr, pk.kind, sp, math.pi / 2 + math.sin(pk.t * 1.3) * 0.08, RARITIES[pk.rarity]["size"],
                   ecol, 0.3 + 0.3 * math.sin(pk.t * 4))

    def draw_enemy(self, e):
        scr, fx = self.screen, self.fx
        sp = self.w2s(e.pos, 4 + math.sin(e.t * 8) * 1.5)
        sq = e.squash
        rx = e.r * (1 + 0.35 * sq)
        ry = e.r * (1 - 0.3 * sq)
        body = dim(e.color, 0.32)
        rim = e.color
        if e.poison > 0:
            body = mix(body, dim(ELEMENTS["poison"]["color"], 0.4), 0.2 + 0.1 * e.poison_stacks)
        if e.burn > 0:
            rim = mix(rim, ELEMENTS["fire"]["color"], 0.5 + 0.2 * math.sin(self.time * 20))
        if e.frozen > 0:
            body = mix(body, (150, 210, 245), 0.6)
            rim = (210, 240, 255)
        elif e.chill > 0:
            rim = mix(rim, ELEMENTS["ice"]["color"], 0.6)
        if e.flash > 0:
            body = rim = (255, 255, 255)
        rect = pygame.Rect(0, 0, rx * 2, ry * 2)
        rect.center = sp
        if e.kind == "runner":
            for k in range(5):
                a = e.t * 6 + k * TAU / 5
                pygame.draw.line(scr, rim, sp + polar(a, e.r * 0.8), sp + polar(a, e.r * 1.5), 2)
        pygame.draw.ellipse(scr, body, rect)
        pygame.draw.ellipse(scr, rim, rect, 3 if e.r > 20 else 2)
        if e.kind == "brute":
            inner = rect.inflate(-e.r * 0.8, -e.r * 0.8)
            pygame.draw.ellipse(scr, rim if e.flash else dim(e.color, 0.55), inner, 2)
            for s in (-1, 1):
                base = sp + V(s * e.r * 0.6, -e.r * 0.7)
                pygame.draw.line(scr, rim, base, base + V(s * 8, -12), 4)
        f = e.facing
        eye_c = (255, 240, 200) if e.kind != "spitter" else (220, 255, 160)
        for s in (-1, 1):
            ep = sp + f * e.r * 0.45 + V(-f.y, f.x) * s * e.r * 0.32 - V(0, e.r * 0.1)
            pygame.draw.circle(scr, eye_c, ep, max(2, e.r * 0.14))
        draw_glow(fx, sp + f * e.r * 0.4, e.r * 0.9, dim(e.color, 0.35))
        if e.burn > 0:
            draw_glow(fx, sp, e.r * 1.6, dim(ELEMENTS["fire"]["color"], 0.3))
        if e.frozen > 0:
            # ice shell
            R = e.r * 1.25
            pts = [sp + polar(k * TAU / 6 + 0.3, R * (1.0 if k % 2 else 0.8)) for k in range(6)]
            pygame.draw.polygon(scr, (220, 245, 255), pts, 2)
            draw_glow(fx, sp, e.r * 1.4, dim(ELEMENTS["ice"]["color"], 0.35))
        if e.kind == "spitter" and e.charge > 0:
            u = e.charge / 0.5
            draw_glow(fx, sp + f * e.r, 8 + 18 * u, dim((130, 230, 80), u))
        if e.armed:
            kind, rarity, element = e.armed
            sw = sp + V(-f.y, f.x) * (e.r + 12) - V(0, 10 + math.sin(e.t * 3) * 3)
            col = RARITIES[rarity]["color"]
            draw_glow(fx, sw, 22 + 6 * rarity, dim(col, 0.3))
            draw_sword(scr, kind, sw, math.atan2(f.y, f.x) - 0.6, 0.6 * RARITIES[rarity]["size"],
                       ELEMENTS[element]["color"])
        y = sp.y - e.r - 12
        if e.hp < e.maxhp:
            w = e.r * 2
            pygame.draw.rect(scr, (30, 10, 14), (sp.x - w / 2, y, w, 4))
            pygame.draw.rect(scr, (240, 70, 80), (sp.x - w / 2, y, w * max(0, e.hp) / e.maxhp, 4))
        # condition pips above the health bar
        pips = [(ELEMENTS["fire"]["color"], 1) if e.burn > 0 else None,
                (ELEMENTS["poison"]["color"], e.poison_stacks) if e.poison > 0 else None,
                (ELEMENTS["ice"]["color"], e.chill_stacks) if e.chill > 0 or e.frozen > 0 else None]
        pips = [pp for pp in pips if pp]
        x = sp.x - (len(pips) - 1) * 6
        for col, n in pips:
            pygame.draw.circle(scr, col, (x, y - 6), 4)
            if n > 1:
                pygame.draw.circle(scr, (255, 255, 255), (x, y - 6), 4, 1)
            x += 12

    def draw_player(self):
        p = self.player
        scr, fx = self.screen, self.fx
        moving = p.vel.length() > 30
        bob = math.sin(self.time * 12) * 2 if moving else math.sin(self.time * 3) * 1
        sp = self.w2s(p.pos, 8 + bob)
        if p.dead:
            pygame.draw.circle(scr, (30, 44, 56), self.w2s(p.pos, 2), p.r)
            return
        if p.iframes > 0 and p.dash_t <= 0 and int(p.iframes * 18) % 2 == 0:
            return
        draw_glow(fx, sp, 46, (30, 80, 110))
        pts = [sp + V(0, -p.r * 1.5), sp + V(p.r * 1.05, p.r * 0.9), sp + V(-p.r * 1.05, p.r * 0.9)]
        pygame.draw.polygon(scr, (24, 40, 56), pts)
        pygame.draw.polygon(scr, (110, 200, 240), pts, 2)
        head = sp + V(0, -p.r * 0.5)
        pygame.draw.circle(scr, (18, 30, 42), head, p.r * 0.7)
        pygame.draw.circle(scr, (110, 200, 240), head, p.r * 0.7, 2)
        f = p.facing
        for s in (-1, 1):
            ep = head + V(f.x * 4 + s * 4, f.y * 2 + 1)
            pygame.draw.circle(scr, (220, 250, 255), ep, 2)
        pulse = 0.6 + 0.4 * math.sin(self.real_time * 4)
        draw_glow(fx, sp + V(0, p.r * 0.2), 16, dim((90, 210, 255), pulse))

    def draw_trail(self, s):
        tr = s.trail
        if len(tr) < 2:
            return
        n = len(tr)
        fx = self.fx
        rcol = s.color
        for k in range(n - 1):
            t0, g0, z0, i0 = tr[k]
            t1, g1, z1, i1 = tr[k + 1]
            inten = (k + 1) / n * i1
            if inten < 0.05:
                continue
            quad = [self.w2s(t0, z0), self.w2s(t1, z1), self.w2s(g1, z1), self.w2s(g0, z0)]
            pygame.draw.polygon(fx, dim(rcol, inten * 0.55), quad)
            pygame.draw.line(fx, dim(mix(rcol, (255, 255, 255), 0.5), inten), quad[0], quad[1], 2)

    def draw_hud(self):
        scr = self.screen
        p = self.player
        F = self.fonts
        # health
        x, y, w, h = 24, 22, 280, 16
        pygame.draw.rect(scr, (20, 16, 28), (x - 3, y - 3, w + 6, h + 6), border_radius=4)
        pygame.draw.rect(scr, (255, 255, 255), (x, y, w * p.hp_shown / p.maxhp, h), border_radius=3)
        pygame.draw.rect(scr, (90, 210, 255), (x, y, w * p.hp / p.maxhp, h), border_radius=3)
        scr.blit(F[22].render(f"{int(p.hp)}", True, (230, 245, 255)), (x + w + 10, y))
        # dash / converge
        y2 = y + 28
        dash_ready = p.dash_cd <= 0
        scr.blit(F[22].render("DASH", True, (120, 220, 255) if dash_ready else (70, 80, 100)), (x, y2))
        pygame.draw.rect(scr, (40, 50, 70), (x + 52, y2 + 5, 60, 6))
        pygame.draw.rect(scr, (120, 220, 255), (x + 52, y2 + 5, 60 * (1 - p.dash_cd / 0.65), 6))
        cv_ready = self.converge_cd <= 0
        label = "CONVERGE" if self.mobile else "CONVERGE [click]"
        lt = F[22].render(label, True, (200, 230, 255) if cv_ready else (70, 80, 100))
        scr.blit(lt, (x + 130, y2))
        bx = x + 140 + lt.get_width()
        pygame.draw.rect(scr, (40, 50, 70), (bx, y2 + 5, 50, 6))
        pygame.draw.rect(scr, (200, 230, 255), (bx, y2 + 5, 50 * (1 - self.converge_cd / CONVERGE_CD), 6))

        # wave / kills
        wt = F[32].render(f"WAVE {max(1, self.wave)}", True, (220, 200, 255))
        scr.blit(wt, (W / 2 - wt.get_width() / 2, 16))
        kt = F[22].render(f"kills {self.kills}", True, (150, 140, 180))
        scr.blit(kt, (W / 2 - kt.get_width() / 2, 44))
        if self.combo >= 3:
            u = clamp(self.combo_t / 2.6, 0, 1)
            ct = F[56].render(f"x{self.combo}", True, mix((90, 80, 110), (255, 210, 110), u))
            scr.blit(ct, (W - ct.get_width() - 28, 18))
            pygame.draw.rect(scr, (255, 210, 110), (W - 128, 66, 100 * u, 3))

        # sword slots
        near = None
        if not p.dead:
            cands = [pk for pk in self.pickups if (pk.pos - p.pos).length() < 80]
            if cands:
                near = min(cands, key=lambda k: (k.pos - p.pos).length())
        cw, ch, gap = 236, 94, 14
        x0 = W / 2 - (cw * 3 + gap * 2) / 2
        y0 = H - ch - 14
        for i, s in enumerate(self.swords):
            cx = x0 + i * (cw + gap)
            rc = RARITIES[s.rarity]["color"]
            bg = mix((18, 16, 26), s.color, 0.12 + 0.35 * s.flash)
            pygame.draw.rect(scr, bg, (cx, y0, cw, ch), border_radius=8)
            pygame.draw.rect(scr, dim(rc, 0.7), (cx, y0, cw, ch), 2, border_radius=8)
            draw_sword(scr, s.kind, (cx + 34, y0 + 46), -0.8, 0.62 if s.kind != "colossus" else 0.5, s.color)
            scr.blit(F[18].render(str(i + 1), True, (150, 140, 170)), (cx + 8, y0 + 6))
            scr.blit(F[22].render(s.t["name"], True, rc), (cx + 64, y0 + 8))
            if s.rarity:
                tag = F[18].render(RARITIES[s.rarity]["name"].upper(), True, rc)
                scr.blit(tag, (cx + cw - tag.get_width() - 8, y0 + 6))
            scr.blit(F[18].render(ELEMENTS[s.element]["tag"], True, s.color), (cx + 64, y0 + 27))
            # normal attack recharge
            frac = 1 - clamp(s.cd / s.cooldown, 0, 1)
            pygame.draw.rect(scr, (40, 36, 54), (cx + 64, y0 + 44, cw - 76, 4), border_radius=2)
            pygame.draw.rect(scr, dim(s.color, 0.7), (cx + 64, y0 + 44, (cw - 76) * frac, 4), border_radius=2)
            # ultimate: key badge, name, recharge
            ready = s.ult_cd <= 0 and s.state != "ult"
            uf = 1 - clamp(s.ult_cd / s.ult_max, 0, 1)
            key = pygame.Rect(cx + 64, y0 + 56, 26, 26)
            pygame.draw.rect(scr, s.color if ready else (34, 30, 46), key, border_radius=5)
            if not ready:
                fill = key.copy()
                fill.height = int(key.height * uf)
                fill.bottom = key.bottom
                pygame.draw.rect(scr, dim(s.color, 0.35), fill, border_radius=5)
            pygame.draw.rect(scr, mix(s.color, (255, 255, 255), 0.4), key, 1, border_radius=5)
            kt = F[22].render(f"{i + 1}" if self.mobile else ULT_KEYS[i], True,
                              (16, 14, 24) if ready else (200, 200, 220))
            scr.blit(kt, kt.get_rect(center=key.center))
            ucol = (235, 235, 250) if ready else (130, 125, 150)
            shot = "  shot" if s.ult["shot"] else ""
            scr.blit(F[18].render(s.ult["name"] + shot, True, ucol), (cx + 98, y0 + 58))
            if not ready and s.ult_cd > 0:
                ct = F[18].render(f"{s.ult_cd:.0f}s", True, (150, 145, 170))
                scr.blit(ct, (cx + cw - ct.get_width() - 10, y0 + 58))
            pygame.draw.rect(scr, (40, 36, 54), (cx + 98, y0 + 76, cw - 110, 4), border_radius=2)
            pygame.draw.rect(scr, s.color, (cx + 98, y0 + 76, (cw - 110) * uf, 4), border_radius=2)
            if near:
                pygame.draw.rect(scr, (255, 255, 255), (cx - 2, y0 - 2, cw + 4, ch + 4), 1, border_radius=9)

        if near:
            self.draw_pickup_card(near)

        if self.banner:
            title, sub, t = self.banner
            a = clamp(t * 2, 0, 1)
            bt = F[88].render(title, True, (235, 220, 255))
            bt.set_alpha(int(255 * a))
            scr.blit(bt, (W / 2 - bt.get_width() / 2, H * 0.24))
            st = F[26].render(sub, True, (170, 160, 200))
            st.set_alpha(int(255 * a))
            scr.blit(st, (W / 2 - st.get_width() / 2, H * 0.24 + 74))

        if self.help_t > 0 and not p.dead:
            lines = ["WASD / arrows  move", "SPACE / SHIFT  dash (invulnerable)",
                     "click  CONVERGE: all swords strike the cursor",
                     "Q / E / R  ULTIMATE of sword 1 / 2 / 3 (cursor-targeted; shots fire toward it)",
                     "1 / 2 / 3  swap a dropped sword into that slot",
                     "TAB or G  show sword ranges     P  pause     H  hide help",
                     "swords attack automatically and apply their element: fire / ice / poison"]
            if self.mobile:
                lines = ["Left stick: move   DASH: evade", "STRIKE: target nearest enemy / tap arena to aim",
                         "ULT 1 / 2 / 3: sword ultimate at the nearest enemy",
                         "SLOT 1 / 2 / 3: swap a nearby dropped sword",
                         "Swords attack automatically   Rotate phone for a larger view"]
            a = clamp(self.help_t, 0, 1)
            for j, line in enumerate(lines):
                t = F[22].render(line, True, (170, 170, 200))
                t.set_alpha(int(220 * a))
                scr.blit(t, (24, 92 + j * 22))

        if p.dead and self.death_t > 0.8:
            a = clamp((self.death_t - 0.8) * 2, 0, 1)
            shade = pygame.Surface((W, H), pygame.SRCALPHA)
            shade.fill((0, 0, 0, int(150 * a)))
            scr.blit(shade, (0, 0))
            for text, size, col, yy in (("THE SWORDS FALL SILENT", 88, (230, 210, 255), H * 0.33),
                                        (f"wave {self.wave}   kills {self.kills}   best chain {self.best_combo}",
                                         32, (180, 170, 210), H * 0.33 + 80),
                                        ("tap RESTART to rise again" if self.mobile else "press R to rise again", 32,
                                         (140, 220, 255), H * 0.33 + 130)):
                t = F[size].render(text, True, col)
                t.set_alpha(int(255 * a))
                scr.blit(t, (W / 2 - t.get_width() / 2, yy))
        if self.paused:
            t = F[88].render("PAUSED", True, (230, 220, 255))
            scr.blit(t, (W / 2 - t.get_width() / 2, H * 0.4))

    def draw_pickup_card(self, pk):
        scr = self.screen
        F = self.fonts
        t = SWORD_TYPES[pk.kind]
        r = RARITIES[pk.rarity]
        el = ELEMENTS[pk.element]
        sp = self.w2s(pk.pos)
        cw, ch = 270, 152
        x = clamp(sp.x + 40, 10, W - cw - 10)
        y = clamp(sp.y - ch - 40, 10, H - ch - 124)
        pygame.draw.rect(scr, (16, 14, 24), (x, y, cw, ch), border_radius=8)
        pygame.draw.rect(scr, r["color"], (x, y, cw, ch), 2, border_radius=8)
        scr.blit(F[26].render(f"{r['name']} {el['adj']} {t['name']}", True, r["color"]), (x + 12, y + 10))
        scr.blit(F[18].render(t["blurb"], True, (160, 160, 180)), (x + 12, y + 34))
        stats = (f"DMG {t['damage'] * r['dmg']:.0f}   SPD {1 / (t['cooldown'] * r['cd']):.1f}/s   "
                 f"RNG {t['range'] * r['rng']:.0f}")
        scr.blit(F[18].render(stats, True, (220, 220, 235)), (x + 12, y + 56))
        scr.blit(F[18].render(el["tag"], True, el["color"]), (x + 12, y + 78))
        ult = t["ult"]
        ulabel = f"ULT  {ult['name']}{'  (skill shot)' if ult['shot'] else ''}   {ult['cd'] * r['cd']:.0f}s"
        scr.blit(F[18].render(ulabel, True, (220, 215, 240)), (x + 12, y + 98))
        scr.blit(F[22].render("press 1 / 2 / 3 to swap", True, (255, 255, 255)), (x + 12, y + 122))


async def main():
    pygame.mixer.pre_init(44100, -16, 2, 512)
    pygame.init()
    screen = pygame.display.set_mode((W, H))
    pygame.display.set_caption("Swordster - prototype")
    game = Game(screen)
    clock = pygame.time.Clock()
    while game.running:
        dt = min(clock.tick(60) / 1000.0, 1 / 30)
        game.poll_touch()
        for ev in pygame.event.get():
            game.handle(ev)
        game.update(dt)
        game.draw()
        pygame.display.flip()
        await asyncio.sleep(0)
    pygame.quit()


asyncio.run(main())
