# Configuration

The server owner's guide. `config.lua` itself is heavily commented and is the reference; this
file is the part that does not fit in comments - how the pieces interact, and what to change
when you want a particular outcome.

## Contents

- [The four numbers that decide everything](#the-four-numbers-that-decide-everything)
- [Balancing: how long should a maxed character take?](#balancing-how-long-should-a-maxed-character-take)
- [The effect table: what a maxed character actually gets](#the-effect-table-what-a-maxed-character-actually-gets)
- [Finding the sport props on your own map](#finding-the-sport-props-on-your-own-map)
- [Equipment baked into an MLO](#equipment-baked-into-an-mlo)
- [Adding or changing equipment](#adding-or-changing-equipment)
- [Adding a fourth stat](#adding-a-fourth-stat)
- [The minigame](#the-minigame)
- [Performance](#performance)
- [Anti-cheat, honestly](#anti-cheat-honestly)
- [Common recipes](#common-recipes)

---

## The four numbers that decide everything

Read these together. Changing one without the others is how a server ends up either trivial or
impossible.

```lua
Config.Allowance.total   = 50.0          -- points per cycle, across every stat
Config.Allowance.perStat = 25.0          -- ...and into any single stat
Config.Allowance.window  = 25 * 3600     -- how long a spent allowance takes to come back
Config.Decay.amount      = 10.0          -- points lost per day of not training
```

The relationship is the design:

- **The allowance is the ceiling on a day.** A player cannot out-grind it. Logging in for
  twelve hours is worth no more than logging in for one, which is the point.
- **Fatigue is the pace inside a day.** The first three workouts of an afternoon are worth
  more than the next twenty combined, so nobody realistically *reaches* the allowance ceiling
  in one sitting - they bank 6 to 9 points a day, not 50.
- **Decay is the pressure to keep coming back.** -10 a day against a realistic +6 to +9 a day
  means a player who trains every other day roughly stands still.

That last line is worth sitting with. At the defaults **the ceiling is something you hold, not
something you reach and bank.** If that is not what you want, raise `Config.Decay.grace`,
lower `Config.Decay.amount`, or turn on `Config.Decay.peakProtection`.

---

## Balancing: how long should a maxed character take?

`Config.Stats.*.sessionsToMax` decides the number of **sessions** (100 by default, so one
perfect session is worth one point). `Config.Allowance` decides the number of **days**, and
days are what players actually feel.

| `Allowance.total` / `perStat` | `window` | One stat to 100% | All three |
|---|---|---|---|
| 60 / 40 | 12h | ~1 week | ~2 weeks |
| 50 / 25 | 25h | **~3 weeks** | **~7-8 weeks** |
| 30 / 15 | 36h | ~7 weeks | ~4 months |

Those columns assume a committed player who trains most days. A casual player takes longer,
which is correct.

Three internally consistent presets - arcade, default, hardcore - are written out at the end of
section 5 in `config.lua`, ready to paste. Each one moves the allowance, the fatigue curve and
the decay together, because they only make sense together.

### Rolling or block recovery

```lua
Config.Allowance.mode = 'rolling'
```

- **`'rolling'`** - each point frees itself exactly `window` seconds after it was earned, so
  the allowance trickles back. A player is never fully locked out for a whole day. Fairer, and
  the default.
- **`'block'`** - the whole allowance resets at once, `window` after the first point of the
  cycle. Simpler to explain, harsher to be on the wrong side of.

### Whey

`Config.Allowance.reducedWindow` (8h by default) is the window a player gets after taking whey.
That is the entire mechanic: a consumable that turns a 25 hour wait into an 8 hour one. See
[ITEMS.md](ITEMS.md) to add the item, and `ReduceRecovery` in [API.md](API.md) to drive it from
your own resource.

### Turning the allowance off entirely

```lua
Config.Allowance.enabled = false
```

Fatigue then becomes the only limiter, and a determined player reaches 100% in roughly five
days of hard grinding. Not recommended, and stated plainly in the config so nobody does it by
accident.

---

## The effect table: what a maxed character actually gets

At the shipped defaults, a character at 100% in everything:

| | Vanilla | At 100% | Native |
|---|---|---|---|
| Unarmed and melee damage | 1.0 | **1.25** | `SetPlayerMeleeWeaponDamageModifier` |
| Melee damage taken | 1.0 | **/1.15** | `SetPlayerMeleeWeaponDefenseModifier` |
| Seconds underwater | ~45 | **75** | `SetPedMaxTimeUnderwater` |
| Swim speed | 1.0 | **1.12** | `SetSwimMultiplierForPlayer` |
| Sprint speed | 1.0 | **1.12** | `SetRunSprintMultiplierForPlayer` |
| Health regeneration | 1.0 | **1.30** | `SetPlayerHealthRechargeMultiplier` |
| Stamina recovery | - | **+20%/s** while stood still | `RestorePlayerStamina` |
| Max health | 200 | **off by default** | `SetEntityMaxHealth` |

That is a fit person, not a superhero. A trained character wins a fist fight against an
untrained one and does not one-shot a stranger.

**Two knobs move all of it:**

```lua
Config.Effects.enabled     = false   -- stats become a pure roleplay number, nothing else
Config.Effects.globalScale = 0.5     -- every bonus at half strength
```

`globalScale` interpolates back towards the vanilla value, so it can never push a multiplier
*below* what base GTA does.

### The GTA character stats

```lua
Config.Effects.writeGameStats = true
```

Separately from the table above, v-sport writes the real character stats the engine already
has: `MP0_STRENGTH`, `MP0_STAMINA`, `MP0_LUNG_CAPACITY` (and their `SP0_` twins, since which
slot is live depends on your framework).

This is the honest path and it is why the three stats are what they are: GTA already models
strength, stamina and lung capacity, so writing the real value gives the player exactly the
behaviour the base game intended for a maxed character. It is bounded by the game rather than
by this config, and it costs nothing.

### Engine ceilings you cannot raise

`SetSwimMultiplierForPlayer` and `SetRunSprintMultiplierForPlayer` are **ignored above 1.49**
by the engine. Setting `max = 2.0` gets you 1.49 and a config that lies about what it does. The
values are clamped before they are written so the resource does not pretend otherwise.

### Max health

Off by default and it should usually stay off. Most frameworks, every ambulance job and every
armour script assume 200 and will fight this. If you turn it on, test it against your medical
resource first.

---

## Finding the sport props on your own map

The shipped catalogue in `shared/equipment.lua` covers the base-game sport props and a spread
of names used by common gym MLOs - 20 exercises across 94 model names. **It cannot know what
your map has.** No shipped list can.

So: stand in your gym and run

```
/sportscan
```

It lists every object within 20 metres, nearest first, with:

- the distance
- `YES` or `-` for whether the catalogue already knows it
- the model name where it can be resolved, and the raw hash where it cannot
- which exercises it offers, for the known ones

Anything marked `-` is a prop your map has and this resource does not. Add it to
`Config.ExtraEquipment` (section 9b) and it becomes usable.

```
/sportscan 8
```

...for a tighter radius in a crowded interior.

**A model name that does not exist in your game costs nothing.** It hashes to a number no
entity will ever carry, so it simply never matches. That is why the shipped lists are
generous and include several spellings of the same idea - over-listing is free, under-listing
means a prop nobody can use. Be generous in your own additions too.

Where a name cannot be resolved, add the hash as a number instead of a string:

```lua
Config.ExtraEquipment = {
    bench_press = {
        models = { 'prop_gym_bench_01', 'prop_gym_bench_02', 'prop_gym_bench_03',
                   'mygym_bench_a', 1234567890 },
    },
}
```

Note that an entry with an existing key **patches** the shipped one, so three extra models is
three lines rather than a restated block. A key that does not exist creates new equipment.

### Seeing what was matched, in game

```lua
Config.Debug.drawDetected = true
```

Draws a label over every prop the scan matched, with its exercises and distance, and `[BUSY]`
when somebody else is on it. The fastest way to find out why a bench is offering nothing.

---

## Equipment baked into an MLO

Some gym equipment in a custom MLO is part of the map model rather than placed as an object.
There is no entity, so there is nothing for a scan to find. Those need a coordinate.

Stand where the player should be and run:

```
/sportspot pull_ups
```

It prints a ready-to-paste line:

```lua
{ equipment = 'pull_ups', coords = vector3(-1202.44, -1566.10, 3.62), heading = 35.0 },
```

Paste it into `Config.Spots` (section 9). The `z` is your position minus 1.0, which puts it on
the floor.

Static spots keep the built-in key prompt even on a server that uses ox_target or qb-target,
because a target has nothing to attach to. They can also carry their own label, radius, marker
and job restriction - see the field list in section 9.

```lua
Config.Debug.drawSpots = true
```

...draws them as spheres so you can see where they actually landed.

---

## Adding or changing equipment

Everything about a piece of equipment lives in one entry. The field list is at the top of
`shared/equipment.lua`. The fields that matter most:

```lua
Config.ExtraEquipment = {
    squat_rack = {
        order = 14,
        label = 'Squat rack',              -- plain text is fine; a locale key is used if it exists
        description = 'Heavy compound lifting.',
        models = { 'mygym_squatrack' },

        -- What one PERFECT session is worth, in SESSIONS of that stat.
        -- 1.0 = one full session = one point at the default sessionsToMax.
        gains = { strength = 1.2 },

        reps = 6,                          -- how many repetitions the minigame asks for
        difficulty = 'hard',               -- a key from Config.Minigame.difficulties
        cooldown = 120,                    -- seconds before the same player may use it again

        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
        offset = vector3(0.0, 0.6, 0.0),   -- where the player stands, in the PROP's space
        heading = 180.0,                   -- added to the prop's own heading
        snap = true,                       -- actually move them there

        require = { stats = { strength = 40 } },
    },
}
```

**`gains` is in sessions, not points.** `{ strength = 1.0 }` is one full session of strength.
`{ strength = 0.5, stamina = 0.5 }` is half a session of each - which is what the heavy bag
does, and why it is worth using for both. The totals do not have to add to 1.0: equipment that
is simply better can be worth more.

**More reps is not more reward.** Reps are how long the session is and how many chances there
are to miss. `gains` is the reward.

**`trains` caps a piece of equipment.** `trains = { strength = 60 }` makes a home dumbbell
useless above 60 strength and pushes players towards a real gym.

**Animations.** `anim` is preferred when it is set and its dictionary loads; `scenario`
otherwise. Both can fail on a given map or game build, and neither failing stops the session -
the minigame is the workout, the animation is the dressing. Scenarios are the safer choice
because they handle their own prop attachment.

---

## Adding a fourth stat

It is a config change, not a code change. Add an entry to `Config.Stats`:

```lua
flexibility = {
    order = 4,
    label = 'stat.flexibility',
    description = 'stat.flexibility_desc',
    colour = { 180, 120, 200 },
    icon = 'F',
    max = 100.0,
    start = 0.0,
    sessionsToMax = 100,
    gameStat = '',                 -- GTA has no flexibility stat; '' writes nothing
},
```

Then:

1. Add `stat.flexibility` and `stat.flexibility_desc` to **both** `locales/en.lua` and
   `locales/fr.lua`. They must stay key-for-key identical.
2. Give some equipment a gain for it: `gains = { flexibility = 1.0 }` on yoga or stretching.
3. Optionally add a `Config.Effects.flexibility` block, and read it in `client/effects.lua`.

It then appears in the stats panel, in every export, in the allowance and in the database with
no other change. The database stores stats as JSON precisely so that this is not a migration.

---

## The minigame

Four difficulty presets in `Config.Minigame.difficulties`. Each piece of equipment names one
and can override any field of it.

```lua
normal = {
    keys = { 2, 3 },                 -- keys per rep, picked randomly in this range
    window = 1250,                   -- ms the bar takes to fill for one key
    perfectZone = { 0.60, 0.80 },    -- fraction of the bar that scores 1.0
    goodZone    = { 0.42, 0.95 },    -- the wider band that scores Config.Minigame.goodScore
    restBetween = 750,               -- ms of animation between reps
},
```

`goodZone` **must contain** `perfectZone`. Yoga is the worked example of an override: a 2600ms
window, one key per rep and a very wide perfect band, so it feels like breathing rather than
button mashing.

`Config.Minigame.keyPool` is the set of keys sequences are drawn from. All of them are disabled
for the duration of a session and read back with `IsDisabledControlJustPressed`, so pressing W
to hit a prompt does not also walk the player off the bench. Keep the labels to one or two
characters - the box is drawn to fit.

To make sessions easier without touching the timing, raise `Config.Minigame.goodScore` (how
much a merely-good press is worth) or `Config.Minigame.maxMisses`.

---

## Performance

Nothing runs when nothing is happening. Three tiers, switched automatically:

| Tier | When | Cost |
|---|---|---|
| Idle | No equipment in range | One loop at `Config.Performance.idleTick` (1s) |
| Nearby | Equipment in range | One loop at `nearbyTick` (250ms) + drawing inside marker range |
| Session | A workout is running | One loop per frame, one player, a couple of minutes |

If you are chasing frame time, two knobs, in this order:

```lua
Config.Detection.interval = 750     -- ms between object-pool scans
Config.Detection.radius   = 20.0    -- metres
```

The scan already skips entirely when the player has not moved `Config.Detection.idleDistance`,
compares squared distances, reuses its result table, and stops at
`Config.Detection.maxObjects` (400). Raising `interval` to 1500 halves an already small number.

On the server there is no per-player loop at all: one timer flushes dirty rows in batches
(`Config.Performance.flushInterval`), one sweeps expired buffs, one re-checks decay every
`Config.Decay.onlineInterval`. Everything else is event-driven.

State bags are written only on a real change and at most every
`Config.Performance.stateBagInterval`. `stateBagReplicated` is off by default because it is one
network message per player per change; only turn it on if another resource needs to read *other*
players' stats on the client.

---

## Anti-cheat, honestly

The minigame runs on the client, so the client knows the score. No FiveM resource can change
that - judging frame-accurate input on the server would need a round trip per key press.
Anybody claiming their training script is cheat-proof is selling something.

What the server does enforce, all from its own clock and its own state:

- A session must have been **authorised**. No token, no payout - so firing the finish event in
  a loop pays nothing.
- A token is **single-use and owned**. It cannot be replayed or borrowed.
- A result that arrives **faster than the reps could have been performed** is rejected
  (`Config.Security.minDurationFactor`).
- A result from somebody who has since **walked away** is rejected (`maxDriftDistance`).
- Cooldowns, the per-hour rate limit and the allowance are all checked server-side.
- Reps are clamped to what the equipment actually has.

That leaves one hole: a cheater can play a plausibly-shaped session and lie about their
accuracy, gaining at most what an excellent player would have gained anyway. **The allowance is
what bounds the damage** - the best possible player and the cheater hit the same ceiling.

Every check fails closed. A session that cannot be verified pays nothing.

```lua
Config.Security.fireSuspicionEvent = true
Config.Security.suspicionThreshold = 5
```

v-sport never kicks or bans anybody. It fires `vsport:server:CheatSuspected` once a player has
collected five rejections inside an hour, and your anticheat decides what that means. One
rejection on its own is a desync and is not worth acting on.

---

## Common recipes

**"Training should be roleplay only, no mechanical advantage."**

```lua
Config.Effects.enabled = false
```

**"Halve every bonus but keep the progression."**

```lua
Config.Effects.globalScale = 0.5
```

**"Players should not lose everything when they go on holiday."**

```lua
Config.Decay.peakProtection = 25.0    -- never fall more than 25 below your best
Config.Decay.grace = 72 * 3600        -- three free days
```

**"Police and EMS train as part of the job."**

```lua
Config.Decay.exemptJobs = { ['police'] = true, ['ambulance'] = true }
```

**"Only one person per bench."** Already the default (`Config.General.exclusiveEquipment`).
It is enforced server-side by proximity, so it works on props with no network identity.

**"I want the target instead of the E prompt."** Automatic when ox_target, qb-target or
qtarget is installed. To force one way or the other:

```lua
Config.Interaction.mode = 'target'    -- or 'key', or 'auto'
Config.Compat.forceTarget = 'ox_target'
```

**"Keep the markers even though I use a target."**

```lua
Config.Interaction.marker.enabled = true
```

**"Test the progression without doing a hundred workouts."**

```lua
Config.Debug.autoPerfect = true       -- every press scores perfect
Config.Debug.gainMultiplier = 20.0    -- and each session is worth twenty
```

Both are debug switches. Turn them off before anybody plays on it.

---
---

# Configuration (Version Française)

Cette page est maintenue en anglais, comme le code. Voici les points essentiels.

## Les quatre nombres qui décident de tout

```lua
Config.Allowance.total   = 50.0          -- points par cycle, toutes stats confondues
Config.Allowance.perStat = 25.0          -- ...et dans une seule stat
Config.Allowance.window  = 25 * 3600     -- temps de récupération du quota
Config.Decay.amount      = 10.0          -- points perdus par jour sans entraînement
```

La relation entre eux **est** le design : le quota plafonne la journée (impossible de farmer
au-delà), la fatigue fixe le rythme à l'intérieur de la journée (les trois premières séances
valent plus que les vingt suivantes, donc on banque 6 à 9 points par jour, pas 50), et la perte
crée la pression de revenir (-10 par jour contre +6 à +9 réalistes : qui s'entraîne un jour sur
deux stagne).

Avec les valeurs par défaut, **le maximum est quelque chose qu'on maintient, pas quelque chose
qu'on atteint et qu'on garde.** Si ce n'est pas ce que vous voulez : augmentez
`Config.Decay.grace`, baissez `Config.Decay.amount`, ou activez
`Config.Decay.peakProtection`.

## Durée pour atteindre le maximum

| `total` / `perStat` | `window` | Une stat à 100 % | Les trois |
|---|---|---|---|
| 60 / 40 | 12 h | ~1 semaine | ~2 semaines |
| 50 / 25 | 25 h | **~3 semaines** | **~7-8 semaines** |
| 30 / 15 | 36 h | ~7 semaines | ~4 mois |

Trois préréglages cohérents (arcade, défaut, hardcore) sont écrits en fin de section 5 de
`config.lua`, prêts à coller. Chacun déplace le quota, la fatigue et la perte ensemble, car ils
n'ont de sens qu'ensemble.

## Ce qu'obtient réellement un personnage au maximum

Dégâts au corps à corps **1,25**, dégâts subis **/1,15**, apnée **75 s** au lieu de 45, nage
**1,12**, sprint **1,12**, régénération **1,30**, récupération d'endurance **+20 %/s** à
l'arrêt. Vie maximale désactivée par défaut.

Deux réglages déplacent tout : `Config.Effects.enabled = false` rend les stats purement
roleplay, `Config.Effects.globalScale = 0.5` divise chaque bonus par deux.

**Plafonds du moteur.** `SetSwimMultiplierForPlayer` et `SetRunSprintMultiplierForPlayer` sont
**ignorés au-delà de 1.49** par le jeu. Mettre `max = 2.0` donne 1.49 et une config qui ment.

**Les vraies stats GTA.** Séparément, v-sport écrit `MP0_STRENGTH`, `MP0_STAMINA` et
`MP0_LUNG_CAPACITY`. C'est la voie honnête, et c'est pourquoi les trois stats sont celles-là :
GTA les modélise déjà.

## Trouver les props de votre carte

Placez-vous dans votre salle et tapez `/sportscan`. La commande liste chaque objet dans un
rayon de 20 m avec sa distance, `YES` ou `-` selon que le catalogue le connaît, le nom du
modèle quand il est résoluble, et les exercices proposés.

Tout ce qui est marqué `-` s'ajoute à `Config.ExtraEquipment` (section 9b).

**Un nom de modèle inexistant ne coûte rien** : il se hache en un nombre qu'aucune entité ne
portera. Les listes fournies sont donc volontairement généreuses, y compris avec plusieurs
orthographes. Soyez généreux dans vos ajouts aussi.

Une entrée dont la clé existe déjà **complète** celle fournie : trois modèles de plus, c'est
trois lignes.

`Config.Debug.drawDetected = true` affiche une étiquette au-dessus de chaque prop reconnu.

## Matériel intégré à un MLO

Certain matériel fait partie du modèle de la carte, pas un objet : rien à trouver pour le scan.
Placez-vous dessus et tapez `/sportspot pull_ups` pour obtenir une ligne `Config.Spots` prête à
coller. `Config.Debug.drawSpots = true` les affiche en sphères.

## Ajouter une quatrième stat

C'est une modification de configuration, pas de code. Ajoutez l'entrée à `Config.Stats`, les
deux clés de locale dans **les deux** fichiers, et un `gains` sur un équipement. Elle apparaît
alors dans le panneau, dans tous les exports, dans le quota et en base. Les stats sont stockées
en JSON précisément pour que ce ne soit pas une migration.

## Anti-triche, honnêtement

Le minijeu tourne côté client, donc le client connaît le score. Aucune ressource FiveM ne peut
changer ça. Ce que le serveur impose : une séance doit être **autorisée** (pas de jeton, pas de
gain), un jeton est **à usage unique et nominatif**, un résultat **trop rapide** est rejeté, un
joueur qui **s'est éloigné** est rejeté, et les temps de recharge, la limite horaire et le quota
sont vérifiés côté serveur.

Il reste un trou : un tricheur peut mentir sur sa précision et gagner au mieux ce qu'un
excellent joueur aurait gagné. **Le quota borne les dégâts** : le meilleur joueur possible et
le tricheur touchent le même plafond.

v-sport n'expulse et ne bannit jamais. Il émet `vsport:server:CheatSuspected` après cinq rejets
dans l'heure, et votre anticheat décide.

## Recettes courantes

Voir la section anglaise : roleplay pur, bonus divisés par deux, protection des vacances,
métiers exemptés, forcer le target, et les deux interrupteurs de debug pour tester la
progression sans faire cent séances (`Config.Debug.autoPerfect` et
`Config.Debug.gainMultiplier`).
