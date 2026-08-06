# v-sport

Physical training for FiveM, built for QBCore and running on ESX and ox_core too.

Every sport prop in the map becomes usable. A rhythm minigame drives the workout, three
stats - strength, lung capacity and stamina - are trained, decay when they are not, and can
be pushed around by any other resource on the server. There is no NUI: the whole interface is
drawn with the game's own natives, so there is no browser process and nothing to keep painting
when nobody is training.

## Features

- **Finds the equipment itself** - the object pool around the player is matched against a
  catalogue of 18 exercises over 31 verified prop models: benches, dumbbells, pull-up bars,
  heavy bags, treadmills, yoga mats, rowing machines, battle ropes. `/vsportscan` prints
  what your own map actually has, including anything inside a custom MLO, ready to paste
  into the config.
- **A rhythm QTE, not a progress bar** - each rep asks for a short sequence of random keys
  on a timing band. Press inside the perfect zone, the good zone, or miss. A clean rep builds
  a streak; four misses in a row ends the session. Four difficulty presets, and any piece of
  equipment can override any of it.
- **Three stats that mean something** - and they are the three GTA already models. Strength,
  stamina and lung capacity are written to the real character stats the engine reads, so a
  trained character behaves the way the base game intended, plus a small configured layer of
  melee damage, underwater time and sprint speed on top.
- **Deliberately not superhero** - at 100% in everything a character has a quarter more
  punch, holds their breath for 75 seconds instead of 45, and sprints 12% faster. Two knobs
  scale or disable the lot. See [CONFIG.md](CONFIG.md) for the exact table.
- **A recovery system, not a grind** - a character may gain 24 points across all stats per
  25 hour cycle, and no more than 12 into any one of them. Once it is spent they are
  blocked until they recover. Whey cuts the 25 hour wait to 8.
- **Fatigue on top of that** - the first three workouts of an afternoon are worth more than
  the next twenty combined. Grinding is not forbidden, it is pointless, which works better
  than a refusal.
- **Decay** - 5 points a day of absence, after one free day, computed from a timestamp so it
  runs while the player is offline. Per-stat rates, a floor, and optional peak protection.
- **Passive training** - running, cycling, swimming and diving all pay out, capped at 11% of a
  dedicated gym day and stopped partway up each stat, so they never replace the equipment.
- **Built to be driven from outside** - seventy-two exports so a drug script can boost gains, apply
  debuffs, drain stamina, stop decay, refund the recovery timer or bypass it entirely. That
  is the whole of [API.md](API.md).
- **Native UI** - the workout HUD and the stats panel are DrawRect and DrawText. No
  `ui_page`, no CEF, no NUI focus to get stuck, nothing to unstick.

## Compatibility

Everything below is detected at runtime and optional. Nothing is required.

| Capability | Detected |
|---|---|
| Framework | qb-core, qbx_core, es_extended (ESX), ox_core - first one detected wins, `Config.Compat.forceFramework` overrides. Anything else runs standalone against the Rockstar licence. |
| Target | ox_target, qb-target, qtarget. None installed falls back to the built-in key prompt, which also handles static spots on servers that do have one. |
| Notifications | ox_lib, qb-core, ESX, okokNotify, or this resource's own native toast. |
| Inventory (item gates, whey) | ox_inventory, qb-core, ESX. |
| Storage | oxmysql, mysql-async, ghmattimysql. Without one, training works and nothing is saved - and it says so, once, in the console and to the player. |
| Sounds | The game's own frontend banks, optionally routed through interact-sound. |

**What differs by framework.** ESX has no gang and no citizenid, so `gang:` keys in
`Config.Decay.exemptJobs` never match and the character key is the identifier; the job grade
stands in for the job type. ox_core uses groups instead of jobs and ships no notification
system, so notifications fall through to this resource's own toast. Handcuff detection is
read from the player's state bag first on every framework, because that is where every modern
resource puts it. Everything else behaves identically.

Run `/vsportinfo` in game to print what was actually detected.

## Installation

1. Drop `v-sport` into your `resources/` folder (any category folder works).
2. `ensure v-sport` in `server.cfg`, after your framework.
3. Install [oxmysql](https://github.com/overextended/oxmysql) if you have not already. The
   table is created on first start; `sql/v_sport.sql` is shipped for operators who would
   rather import a schema by hand.
4. Optional: `setr sport_locale "fr"` for French. It follows `qb_locale` otherwise.
5. Optional but recommended: add the whey item to your inventory. Two minutes, and
   [ITEMS.md](ITEMS.md) has the exact block to paste for qb-core, ESX and ox_inventory.

There is no build step. Everything ships as Lua source.

### Then, in game

Stand in your gym and run `/vsportscan`. It lists every object around you, says whether the
catalogue already knows it, and names the ones it does. Anything marked `-` is a prop your
map has and this resource does not - add it to `Config.ExtraEquipment` and it becomes usable.

For gym equipment that is baked into an MLO rather than placed as an object, stand on the
spot and run `/vsportspot pull_ups` to get a `Config.Spots` line to paste.

## Usage

Every command is prefixed `vsport` so nothing here can collide with a `/vsport` from another
resource. Rename any of them in `Config.Commands`.

| Command | Effect |
|---|---|
| `/vsport` | Open the stats panel |
| `/vsportinfo` | Print what was detected, and your current numbers, to F8 |
| `/vsportscan [radius]` | List the props around you and whether they are usable |
| `/vsportspot <equipment>` | Print a `Config.Spots` line for where you stand |
| `/vsportoffset` | Print a `modelOverrides` offset for the prop you are facing |
| `/vsportadmin ...` | Admin: get, set, add, reset, buff, allowance, whey, block, top |
| `E` (configurable) | Start a workout at the equipment you are looking at |
| `G` (configurable) | Cycle exercises when a prop offers more than one |
| Hold `RETOUR`/`BACKSPACE` | Stop a workout in progress; you keep what you earned |

The panel also opens from an event, so it drops into **qb-radialmenu** or any other menu with
no glue code — see [API.md](API.md#client-events-for-a-radial-menu).

### The QTE keys

Six keys, all under the left hand, and nothing else — reaching for `SPACE` mid-sequence means
missing the next prompt for a reason that has nothing to do with timing.

| Layout | Keys |
|---|---|
| AZERTY | `A` `Z` `E` `Q` `S` `D` |
| QWERTY | `Q` `W` `E` `A` `S` `D` |

Those are the **same six physical keys**: GTA binds a control to a key position, so only the
printed letter differs. `Config.Minigame.keyboardLayout` decides which letters are drawn, and
`auto` picks AZERTY when the locale is French.

## How the progression actually works

Four mechanisms, each doing a different job. They are meant to be read together.

| | What it does | Where |
|---|---|---|
| **Sessions to max** | 100 perfect sessions take one stat from 0 to 100 | `Config.Stats.*.sessionsToMax` |
| **Fatigue** | The 5th workout in 90 minutes is worth 15% of the 1st | `Config.Progression.fatigue` |
| **Allowance** | 24 points per 25h cycle, 12 max into any one stat, then blocked | `Config.Allowance` |
| **Decay** | -5 a day of absence, after one free day | `Config.Decay` |

### What that works out to

Measured by simulating the real progression functions day by day, with the allowance ledger and
the decay rules in play. **All three stats to 100%:**

| Player | Sessions/day | Form | Days |
|---|---|---|---|
| Casual, one rest day in three | 9 | 85% | ~59 |
| Dedicated, one rest day a week | 18 | 90% | ~22 |
| Dedicated, every day | 21 | 90% | ~16 |
| **Dedicated, every day, plays the QTE well** | **21** | **100%** | **~16** |
| Tries to grind it | 60 requested, 28 fit | 100% | ~15 |

So **a fortnight** is the target for somebody who trains daily and hits their prompts. The last
row is the one that matters most: **grinding buys one day**, because the allowance stops paying long
before the day runs out and only about 28 sessions fit into 24 hours at a realistic pace. One stat on
its own is roughly a third of those figures.

The last row is what grinding actually buys: **one day.** A player attempting sixty sessions a day
measures at fifteen days against the dedicated player's sixteen, because the 24-point allowance
stops paying long before the day runs out - most of those sessions are refused. That is the whole
point of the allowance, and `Config.Allowance.total` is the knob. Section 5b of `config.lua`
explains the trade-off before you touch it.

Holding it is its own job - decay takes back 5 per day of absence, bounded by
`Config.Decay.peakProtection` (20 by default) so a fortnight away costs a known, recoverable
amount rather than everything.

Three ready-made balances (arcade, default, hardcore) are written out in section 5 of
`config.lua`, each internally consistent, ready to paste over the defaults.

## For server owners, in one minute

Everything is in `config.lua`, in nineteen commented sections. The four numbers that matter:

```lua
-- How many DAYS a maxed character takes. This is the big one.
Config.Allowance.total   = 24.0          -- points per cycle, across all stats
Config.Allowance.perStat = 12.0          -- ...and into any single stat
Config.Allowance.window  = 25 * 3600     -- how long a spent allowance takes to come back

-- How hard it is to keep. -5 a day of absence, after one free day.
Config.Decay.amount = 5.0
Config.Decay.grace  = 24 * 3600

-- How much of an advantage a maxed character actually gets.
Config.Effects.globalScale = 1.0         -- 0.5 halves every bonus, 0.0 makes them cosmetic
Config.Effects.enabled     = true        -- false makes the stats pure roleplay
```

## For developers

The point of this resource is that other resources drive it. A drug script can:

```lua
-- Boost what training is worth
exports['v-sport']:ApplyMultiplier(source, nil, 2.0, 1800)        -- double gains, 30 min

-- Hand out temporary points, or take them away
exports['v-sport']:ApplyBuff(source, 'strength', 15, 300)         -- +15 strength, 5 min
exports['v-sport']:ApplyDebuff(source, 'stamina', 20, 600)        -- -20 stamina, 10 min

-- Stop the 10-a-day decay for a while
exports['v-sport']:SetDecayImmunity(source, 48 * 3600)

-- Bypass the recovery timer, partly or entirely
exports['v-sport']:AddAllowance(source, 15)                       -- 15 points back
exports['v-sport']:ResetAllowance(source)                         -- the whole cycle
exports['v-sport']:ReduceRecovery(source, 25 * 3600)              -- what whey does

-- Act on the body directly
exports['v-sport']:Exhaust(source, 0.0, 45)                       -- cannot sprint for 45s
exports['v-sport']:RestoreStamina(source, 1.0)
exports['v-sport']:SetEffectOverride(source, 'sprintSpeed', 0.8, 60, 'multiply')

-- Model a HABIT rather than an event. This is the part most resources need and
-- most training scripts do not have.
exports['v-sport']:SetStatCeiling(source, 'breath', 55, 0)        -- a smoker stops at 55
exports['v-sport']:AddDrain(source, 'stamina', 1.5, 3600)         -- -1.5/hour while it lasts
exports['v-sport']:SetDecayMultiplier(source, 2.0, 86400)         -- loses 20/day, not 10

-- Or a whole drug in one call, undoable in one call
local applied = exports['v-sport']:ApplyPackage(source, { ... })
exports['v-sport']:ClearPackage(source, applied)
```

**A habit is not an event.** `RemoveStat(src, 'stamina', 5)` models somebody who had one bad
cigarette; it does not model a smoker. What models a smoker is being held back for as long as
they smoke - which is what the three condition exports above are for. None of them touches a
stat at the moment it is applied, so they read as a consequence rather than as a fine.

Seventy-two exports, plus state bags and the events this resource fires. Everything in
`server/api.lua` also answers to `vsport:server:<Name>` as an event, for a resource that would
rather not depend on load order.
All of it, with complete worked examples for smoking, drug abuse and a x2 booster with a
comedown, is in [API.md](API.md).

## Documentation

| File | What is in it |
|---|---|
| [CONFIG.md](CONFIG.md) | Server owner's guide: balancing, the effect table, finding your props. |
| [PROPS.md](PROPS.md) | Every supported prop model, and how to add your own. Generated from the catalogue. |
| [API.md](API.md) | Every export, event and state bag another resource can use. |
| [ITEMS.md](ITEMS.md) | Adding whey and the other consumables, per framework, with the blocks to paste. |
| [images/README.md](images/README.md) | The item icons, and converting them to PNG for your inventory. |
| [CHANGELOG.md](CHANGELOG.md) | What changed, English then French. |
| [ERROR_LOG.md](ERROR_LOG.md) | Problems hit, root causes, and the rule that stops each recurring. |
| [RULES.md](RULES.md) | Conventions for anyone working on the resource. |

## What it costs

Nothing runs when nothing is happening. Three tiers, switched automatically:

| Tier | When | Cost |
|---|---|---|
| Idle | No equipment in range | One loop at 1s, a distance check |
| Nearby | Equipment in range | One loop at 250ms plus a draw loop inside marker range |
| Session | A workout is running | One loop per frame, for that one player, for a couple of minutes |

The object-pool scan is skipped entirely when the player has not moved, compares squared
distances, reuses its result table and stops at 400 objects. On the server there is no
per-player loop at all: one timer flushes dirty rows in batches, one sweeps expired buffs, one
re-checks decay every fifteen minutes. Everything else is event-driven.

If you are chasing frame time, the two knobs are `Config.Detection.interval` and
`Config.Detection.radius`, in that order.

## Licence

MIT with an attribution requirement. See [LICENSE](LICENSE). Use it, change it, sell it, ship
it on a paid server - with one condition:

**Leave the credit in.** The stats panel names its author. You may translate it and restyle it
to match your server. You may not remove it, hide it, or replace the name.

## Credits

Author: vyrriox

---

# v-sport (Version Française)

Un système d'entraînement physique pour FiveM, conçu pour QBCore et fonctionnant aussi sur ESX
et ox_core.

Tous les props de sport de la carte deviennent utilisables. Un minijeu rythmique conduit la
séance, trois statistiques - force, apnée et endurance - se travaillent, se perdent quand on
ne s'entraîne plus, et peuvent être manipulées par n'importe quelle autre ressource du
serveur. Aucune NUI : toute l'interface est dessinée avec les natives du jeu, donc pas de
processus navigateur et rien à rafraîchir quand personne ne s'entraîne.

## Caractéristiques

- **Il trouve le matériel tout seul** - le pool d'objets autour du joueur est comparé à un
  catalogue de 20 exercices répartis sur 94 modèles de props : bancs, haltères, barres de
  traction, sacs de frappe, tapis de course, tapis de yoga, rameurs, cordes ondulatoires.
  `/vsportscan` affiche ce que votre carte contient réellement, y compris dans un MLO
  personnalisé, prêt à coller dans la configuration.
- **Un QTE rythmique, pas une barre de progression** - chaque répétition demande une courte
  séquence de touches aléatoires sur une bande de timing. Zone parfaite, zone correcte, ou
  raté. Une répétition propre construit un combo ; quatre ratés d'affilée arrêtent la séance.
- **Trois stats qui comptent** - et ce sont les trois que GTA modélise déjà. Force, endurance
  et capacité pulmonaire sont écrites dans les vraies stats de personnage que le moteur lit,
  plus une petite couche configurable de dégâts au corps à corps, de temps sous l'eau et de
  vitesse de sprint.
- **Volontairement pas des super-héros** - à 100 % partout, un personnage frappe un quart plus
  fort, tient 75 secondes en apnée au lieu de 45, et sprinte 12 % plus vite. Deux réglages
  permettent de tout diminuer ou de tout désactiver.
- **Un système de récupération, pas du farm** - un personnage peut gagner 24 points toutes
  statistiques confondues par cycle de 25 heures, et pas plus de 12 dans une seule. Une fois
  épuisé, il est bloqué jusqu'à récupération. La whey ramène les 25 heures à 8.
- **De la fatigue par-dessus** - les trois premières séances d'un après-midi valent plus que
  les vingt suivantes réunies. Le farm n'est pas interdit, il est inutile, ce qui fonctionne
  mieux qu'un refus.
- **Perte de niveau** - 5 points par jour d'absence, après un jour de grâce, calculée depuis
  un horodatage : elle tourne donc aussi hors ligne.
- **Entraînement passif** - le sprint travaille l'endurance et l'apnée sous l'eau travaille
  les poumons, assez peu pour ne jamais remplacer la salle.
- **Fait pour être piloté de l'extérieur** - cinquante exports pour qu'un script de drogue
  puisse booster les gains, appliquer des malus, vider l'endurance, arrêter la perte,
  rembourser ou contourner le temps de récupération.
- **Interface native** - le HUD de séance et le panneau de stats sont du DrawRect et du
  DrawText. Pas de `ui_page`, pas de CEF, pas de focus NUI à débloquer.

**Ce qui diffère selon le framework.** ESX n'a ni gang ni citizenid : les clés `gang:` ne
s'appliquent jamais et la clé de personnage est l'identifier. ox_core utilise des groupes au
lieu des métiers et ne fournit aucun système de notification, donc les messages passent par
les toasts de cette ressource. Tapez `/vsportinfo` en jeu pour voir ce qui a été détecté.

## Installation

1. Déposez `v-sport` dans votre dossier `resources/`.
2. `ensure v-sport` dans `server.cfg`, après votre framework.
3. Installez [oxmysql](https://github.com/overextended/oxmysql). La table se crée toute seule
   au premier démarrage ; `sql/v_sport.sql` est fourni pour importer le schéma à la main.
4. Optionnel : `setr sport_locale "fr"` pour le français. Sinon il suit `qb_locale`.
5. Optionnel mais recommandé : ajoutez l'item whey à votre inventaire. Deux minutes, et
   [ITEMS.md](ITEMS.md) contient le bloc exact à coller pour qb-core, ESX et ox_inventory.

Aucune étape de build.

### Ensuite, en jeu

Placez-vous dans votre salle et tapez `/vsportscan`. La commande liste tous les objets autour
de vous, indique si le catalogue les connaît déjà, et nomme ceux qu'il connaît. Tout ce qui
est marqué `-` est un prop que votre carte possède et que la ressource ignore : ajoutez-le à
`Config.ExtraEquipment` et il devient utilisable.

Pour le matériel intégré au modèle d'un MLO plutôt que posé en objet, placez-vous dessus et
tapez `/vsportspot pull_ups` pour obtenir une ligne `Config.Spots` à coller.

## Comment fonctionne réellement la progression

Quatre mécanismes, chacun avec un rôle différent. Ils se lisent ensemble.

| | Rôle | Où |
|---|---|---|
| **Séances pour le max** | 100 séances parfaites font passer une stat de 0 à 100 | `Config.Stats.*.sessionsToMax` |
| **Fatigue** | La 5e séance en 90 minutes vaut 15 % de la 1re | `Config.Progression.fatigue` |
| **Quota** | 24 points par cycle de 25 h, 12 max dans une seule stat, puis bloqué | `Config.Allowance` |
| **Perte** | -5 par jour d'absence, après un jour de grâce | `Config.Decay` |

### Ce que ça donne concrètement

Mesuré en simulant les vraies fonctions de progression jour par jour, quota et pertes compris.
**Les trois statistiques à 100 % :**

| Joueur | Séances/jour | Forme | Jours |
|---|---|---|---|
| Occasionnel, un jour de repos sur trois | 9 | 85 % | ~59 |
| Assidu, un jour de repos par semaine | 18 | 90 % | ~22 |
| Assidu, tous les jours | 21 | 90 % | ~16 |
| **Assidu, tous les jours, joue bien le QTE** | **21** | **100 %** | **~13** |
| Ne fait rien d'autre | 60 | 100 % | ~5 |

**Deux semaines** est donc la cible pour qui s'entraîne chaque jour et réussit ses touches, et
bien jouer le minijeu vaut environ trois jours. Une seule statistique représente à peu près le
tiers de ces chiffres.

La dernière ligne montre ce que le farm rapporte réellement : **un jour.** Qui tente soixante
séances par jour mesure quinze jours contre seize pour le joueur assidu, parce que le quota de 24
points cesse de payer bien avant la fin de la journée et refuse la plupart de ces séances. C'est
tout l'objet du quota. `Config.Allowance.total` est le réglage, et la section 5b explique avant d'y
toucher.

Les conserver est un travail à part : la perte reprend 5 par jour d'absence, bornée par
`Config.Decay.peakProtection` (20 par défaut) pour qu'une absence de deux semaines coûte un
montant connu et récupérable plutôt que tout.

Trois équilibrages prêts à l'emploi (arcade, défaut, hardcore) sont écrits dans la section 5
de `config.lua`, chacun cohérent, prêt à coller par-dessus les valeurs par défaut.

## Pour les propriétaires de serveur

Tout est dans `config.lua`, en dix-neuf sections commentées. Les quatre nombres qui comptent :

```lua
-- Combien de JOURS pour un personnage au maximum. C'est le réglage principal.
Config.Allowance.total   = 50.0          -- points par cycle, toutes stats confondues
Config.Allowance.perStat = 25.0          -- ...et dans une seule stat
Config.Allowance.window  = 25 * 3600     -- temps de récupération du quota

-- La difficulté à le conserver.
Config.Decay.amount = 10.0
Config.Decay.grace  = 24 * 3600

-- L'avantage réel d'un personnage au maximum.
Config.Effects.globalScale = 1.0         -- 0.5 divise par deux, 0.0 rend tout cosmétique
Config.Effects.enabled     = true        -- false : les stats deviennent du pur roleplay
```

## Pour les développeurs

L'intérêt de cette ressource est que d'autres ressources la pilotent. Un script de drogue
peut :

```lua
-- Booster ce que rapporte l'entrainement
exports['v-sport']:ApplyMultiplier(source, nil, 2.0, 1800)        -- gains x2, 30 min

-- Donner des points temporaires, ou en retirer
exports['v-sport']:ApplyBuff(source, 'strength', 15, 300)         -- +15 force, 5 min
exports['v-sport']:ApplyDebuff(source, 'stamina', 20, 600)        -- -20 endurance, 10 min

-- Empecher la perte de 5 par jour
exports['v-sport']:SetDecayImmunity(source, 48 * 3600)

-- Contourner le temps de recuperation, en partie ou totalement
exports['v-sport']:AddAllowance(source, 15)
exports['v-sport']:ResetAllowance(source)
exports['v-sport']:ReduceRecovery(source, 25 * 3600)              -- ce que fait la whey

-- Agir directement sur le corps
exports['v-sport']:Exhaust(source, 0.0, 45)                       -- ne peut plus sprinter
exports['v-sport']:RestoreStamina(source, 1.0)

-- Modeliser une HABITUDE, pas un evenement
exports['v-sport']:SetStatCeiling(source, 'breath', 55, 0)        -- un fumeur plafonne a 55
exports['v-sport']:AddDrain(source, 'stamina', 1.5, 3600)         -- -1,5/heure tant que ca dure
exports['v-sport']:SetDecayMultiplier(source, 2.0, 86400)         -- perd 20/jour au lieu de 10

-- Ou toute une drogue en un appel, annulable en un appel
local applied = exports['v-sport']:ApplyPackage(source, { ... })
exports['v-sport']:ClearPackage(source, applied)
```

**Une habitude n'est pas un événement.** `RemoveStat(src, 'stamina', 5)` modélise quelqu'un qui a
mal fumé une fois ; ça ne modélise pas un fumeur. Ce qui modélise un fumeur, c'est d'être bridé
tant qu'il fume, et c'est à ça que servent les trois exports de condition ci-dessus. Aucun ne
touche une statistique au moment où il est posé : ils se lisent comme une conséquence, pas comme
une amende.

Soixante-douze exports, plus les state bags et les événements
émis. Tout, avec des exemples complets pour la fumette, l'abus de drogue et un booster x2 avec sa
descente, est dans [API.md](API.md).

## Documentation

| Fichier | Contenu |
|---|---|
| [CONFIG.md](CONFIG.md) | Guide du propriétaire : équilibrage, tableau des effets, trouver vos props. |
| [PROPS.md](PROPS.md) | Tous les props compatibles, et comment ajouter les vôtres. Généré depuis le catalogue. |
| [API.md](API.md) | Chaque export, événement et state bag utilisable par une autre ressource. |
| [ITEMS.md](ITEMS.md) | Ajouter la whey et les autres consommables, par framework. |
| [images/README.md](images/README.md) | Les icones des items, et leur conversion en PNG. |
| [CHANGELOG.md](CHANGELOG.md) | Ce qui a changé. |
| [ERROR_LOG.md](ERROR_LOG.md) | Problèmes rencontrés, causes, et la règle qui évite la récidive. |

## Ce que ça coûte

Rien ne tourne quand il ne se passe rien. Trois paliers, commutés automatiquement :

| Palier | Quand | Coût |
|---|---|---|
| Repos | Aucun équipement à portée | Une boucle à 1 s, un test de distance |
| Proche | Équipement à portée | Une boucle à 250 ms plus le dessin dans le rayon du marqueur |
| Séance | Une séance tourne | Une boucle par frame, pour ce joueur, quelques minutes |

Le scan du pool d'objets est entièrement sauté quand le joueur n'a pas bougé, compare des
distances au carré, réutilise sa table de résultat et s'arrête à 400 objets. Côté serveur il
n'y a aucune boucle par joueur : un minuteur écrit les lignes modifiées par lots, un balaie
les buffs expirés, un revérifie la perte toutes les quinze minutes.

## Licence

MIT avec obligation d'attribution. Voir [LICENSE](LICENSE). Utilisez-le, modifiez-le,
vendez-le, faites-le tourner sur un serveur payant, à une condition :

**Laissez le crédit.** Le panneau de statistiques nomme son auteur. Vous pouvez le traduire et
l'habiller aux couleurs de votre serveur. Vous ne pouvez pas le supprimer, le masquer ni
remplacer le nom.

## Credits

Author: vyrriox
