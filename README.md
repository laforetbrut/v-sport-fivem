# v-sport

Physical training for FiveM, built for QBCore and running on ESX and ox_core too.

Every sport prop in the map becomes usable. A rhythm minigame drives the workout, three
stats - strength, lung capacity and stamina - are trained, decay when they are not, and can
be pushed around by any other resource on the server. There is no NUI: the whole interface is
drawn with the game's own natives, so there is no browser process and nothing to keep painting
when nobody is training.

## Features

- **Finds the equipment itself** - the object pool around the player is matched against a
  catalogue of 20 exercises spread over 94 prop models: benches, dumbbells, pull-up bars,
  heavy bags, treadmills, yoga mats, rowing machines, battle ropes. `/sportscan` prints
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
- **A recovery system, not a grind** - a character may gain 50 points across all stats per
  25 hour cycle, and no more than 25 into any one of them. Once it is spent they are
  blocked until they recover. Whey cuts the 25 hour wait to 8.
- **Fatigue on top of that** - the first three workouts of an afternoon are worth more than
  the next twenty combined. Grinding is not forbidden, it is pointless, which works better
  than a refusal.
- **Decay** - 10 points a day of absence, after one free day, computed from a timestamp so it
  runs while the player is offline. Per-stat rates, a floor, and optional peak protection.
- **Passive training** - sprinting builds stamina and holding your breath underwater builds
  lung capacity, both small enough that they never replace the gym.
- **Built to be driven from outside** - fifty exports so a drug script can boost gains, apply
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

Run `/sportinfo` in game to print what was actually detected.

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

Stand in your gym and run `/sportscan`. It lists every object around you, says whether the
catalogue already knows it, and names the ones it does. Anything marked `-` is a prop your
map has and this resource does not - add it to `Config.ExtraEquipment` and it becomes usable.

For gym equipment that is baked into an MLO rather than placed as an object, stand on the
spot and run `/sportspot pull_ups` to get a `Config.Spots` line to paste.

## Usage

| Command | Effect |
|---|---|
| `/sport` | Open the stats panel |
| `/sportinfo` | Print what was detected, and your current numbers, to F8 |
| `/sportscan [radius]` | List the props around you and whether they are usable |
| `/sportspot <equipment>` | Print a `Config.Spots` line for where you stand |
| `/sportadmin ...` | Admin: get, set, add, reset, buff, allowance, whey, block, top |
| `E` (configurable) | Start a workout at the equipment you are looking at |
| `G` (configurable) | Cycle exercises when a prop offers more than one |
| Hold `BACKSPACE` | Stop a workout in progress; you keep what you earned |

## How the progression actually works

Four mechanisms, each doing a different job. They are meant to be read together.

| | What it does | Where |
|---|---|---|
| **Sessions to max** | 100 perfect sessions take one stat from 0 to 100 | `Config.Stats.*.sessionsToMax` |
| **Fatigue** | The 5th workout in 90 minutes is worth 15% of the 1st | `Config.Progression.fatigue` |
| **Allowance** | 50 points per 25h cycle, 25 max into any one stat, then blocked | `Config.Allowance` |
| **Decay** | -10 a day of absence, after one free day | `Config.Decay` |

At the shipped defaults, a committed player reaches 100% in one stat in **about three weeks**
and in all three in **seven to eight**, and they have to keep showing up to hold it - decay
takes back 10 a day against a realistic 6 to 9 a day of gains.

Three ready-made balances (arcade, default, hardcore) are written out in section 5 of
`config.lua`, each internally consistent, ready to paste over the defaults.

## For server owners, in one minute

Everything is in `config.lua`, in nineteen commented sections. The four numbers that matter:

```lua
-- How many DAYS a maxed character takes. This is the big one.
Config.Allowance.total   = 50.0          -- points per cycle, across all stats
Config.Allowance.perStat = 25.0          -- ...and into any single stat
Config.Allowance.window  = 25 * 3600     -- how long a spent allowance takes to come back

-- How hard it is to keep. -10 a day of absence, after one free day.
Config.Decay.amount = 10.0
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
```

Fifty exports, every one with an event twin, plus state bags and the events this resource
fires. All of it, with worked examples, is in [API.md](API.md).

## Documentation

| File | What is in it |
|---|---|
| [CONFIG.md](CONFIG.md) | Server owner's guide: balancing, the effect table, finding your props. |
| [API.md](API.md) | Every export, event and state bag another resource can use. |
| [ITEMS.md](ITEMS.md) | Adding whey and the other consumables, per framework, with the blocks to paste. |
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
  `/sportscan` affiche ce que votre carte contient réellement, y compris dans un MLO
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
- **Un système de récupération, pas du farm** - un personnage peut gagner 50 points toutes
  statistiques confondues par cycle de 25 heures, et pas plus de 25 dans une seule. Une fois
  épuisé, il est bloqué jusqu'à récupération. La whey ramène les 25 heures à 8.
- **De la fatigue par-dessus** - les trois premières séances d'un après-midi valent plus que
  les vingt suivantes réunies. Le farm n'est pas interdit, il est inutile, ce qui fonctionne
  mieux qu'un refus.
- **Perte de niveau** - 10 points par jour d'absence, après un jour de grâce, calculée depuis
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
les toasts de cette ressource. Tapez `/sportinfo` en jeu pour voir ce qui a été détecté.

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

Placez-vous dans votre salle et tapez `/sportscan`. La commande liste tous les objets autour
de vous, indique si le catalogue les connaît déjà, et nomme ceux qu'il connaît. Tout ce qui
est marqué `-` est un prop que votre carte possède et que la ressource ignore : ajoutez-le à
`Config.ExtraEquipment` et il devient utilisable.

Pour le matériel intégré au modèle d'un MLO plutôt que posé en objet, placez-vous dessus et
tapez `/sportspot pull_ups` pour obtenir une ligne `Config.Spots` à coller.

## Comment fonctionne réellement la progression

Quatre mécanismes, chacun avec un rôle différent. Ils se lisent ensemble.

| | Rôle | Où |
|---|---|---|
| **Séances pour le max** | 100 séances parfaites font passer une stat de 0 à 100 | `Config.Stats.*.sessionsToMax` |
| **Fatigue** | La 5e séance en 90 minutes vaut 15 % de la 1re | `Config.Progression.fatigue` |
| **Quota** | 50 points par cycle de 25 h, 25 max dans une seule stat, puis bloqué | `Config.Allowance` |
| **Perte** | -10 par jour d'absence, après un jour de grâce | `Config.Decay` |

Avec les valeurs par défaut, un joueur assidu atteint 100 % dans une stat en **environ trois
semaines** et dans les trois en **sept à huit**, et il doit continuer à venir pour les garder :
la perte reprend 10 par jour contre 6 à 9 par jour de gains réalistes.

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

-- Empecher la perte de 10 par jour
exports['v-sport']:SetDecayImmunity(source, 48 * 3600)

-- Contourner le temps de recuperation, en partie ou totalement
exports['v-sport']:AddAllowance(source, 15)
exports['v-sport']:ResetAllowance(source)
exports['v-sport']:ReduceRecovery(source, 25 * 3600)              -- ce que fait la whey

-- Agir directement sur le corps
exports['v-sport']:Exhaust(source, 0.0, 45)                       -- ne peut plus sprinter
exports['v-sport']:RestoreStamina(source, 1.0)
```

Cinquante exports, chacun avec un équivalent en événement, plus les state bags et les
événements émis. Tout est dans [API.md](API.md).

## Documentation

| Fichier | Contenu |
|---|---|
| [CONFIG.md](CONFIG.md) | Guide du propriétaire : équilibrage, tableau des effets, trouver vos props. |
| [API.md](API.md) | Chaque export, événement et state bag utilisable par une autre ressource. |
| [ITEMS.md](ITEMS.md) | Ajouter la whey et les autres consommables, par framework. |
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
