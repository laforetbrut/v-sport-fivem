# Compatible props

Which props v-sport recognises, and how to add your own.

**17 exercises over 30 prop models.** Every model name here was verified
against the game with `IsModelValid` - 85 names that circulate on community prop lists do not
exist in the base files at all and were removed rather than left in to pad the count. A whole-map
sweep then recorded which of the survivors are actually placed somewhere, which is what the last
column reports: a model can be real, fully supported, and sit nowhere in Los Santos.

This file is GENERATED from `shared/equipment.lua` by `tools/props.py`. Do not edit it by hand -
edit the catalogue, or your config, and regenerate.

---

## Adding a prop: the whole thing, in game, in about a minute

**No file to edit and no restart.** Stand in your own gym MLO, look at the machine, and:

```
/vsportadd treadmill
```

That is the entire first step. It takes the prop you are **looking at** - not a name you typed -
confirms the game really has that model, and adds it to the treadmill exercise live, for every
player on the server.

Then align the body on it:

```
/vsportprop treadmill
```

You are put in the sky with a copy of the prop, a floor grid and an orbit camera. Nudge the body
with the arrows, and press **K** to save it for everyone. Also live, also no restart.

Finally, when it works and you want it permanent:

```
/vsportexport
```

That prints everything you have added as a `Config.ExtraEquipment` block. Paste it into
`config.lua`, run `/vsportreset`, and it is in version control where it belongs.

### The rest of the commands

| Command | What it does |
|---|---|
| `/vsportmissing` | **Ask the game whether any sport prop is missing from the catalogue** |
| `/vsportscan [radius]` | Every object nearby, whether v-sport knows it, and what it offers |
| `/vsportadd <exercise> [model]` | Add the prop you face. A model name is optional |
| `/vsportremove <exercise> [model]` | Take one back out. Works on shipped models too |
| `/vsportcustom` | List everything added in game, and whether each model exists in this build |
| `/vsportprop <exercise> [model]` | The alignment studio. **K** saves |
| `/vsportexport` | Print it all as a `config.lua` block |
| `/vsportreload` | Re-read `data/custom.json`, for a hand edit or a restored backup |
| `/vsportreset [exercise]` | Forget one exercise's additions, or all of them |
| `/vsportitems [inventory]` | The item blocks to paste into your inventory |

All of them are **admin only**, checked server-side. See CONFIG.md.

### "Have we missed a prop?"

```
/vsportmissing
```

This is the one that answers the question properly, and it does it by **asking the game** rather
than trusting a list. Every published GTA prop dump is incomplete - the one used to build the
candidate list in `Config.Debug.candidateModels` contains neither `prop_weight_squat` nor
`prop_pris_bench_01`, and both are real and in use here. Only `IsModelValid` knows what your build
actually has.

It reports in **both** directions, and the second is the one that gets forgotten:

| | Meaning |
|---|---|
| exists here, not in the catalogue | a real gap - the command prints the `/vsportadd` line for it |
| in the catalogue, does not exist | a dead entry. Harmless, but worth knowing |

That second column is how the original 85 phantom model names were found. A name that does not
exist hashes to a number no object will ever carry, so it fails silently and forever.

**Add your MLO's model names to `Config.Debug.candidateModels`** and run it again: the game will
tell you which of them it really has, which beats guessing at spellings in a config file.

### Where it is kept

`data/custom.json`, written by the server and pushed to every client. Safe to delete: you lose the
in-game additions and nothing else. It is **not** version control, which is what `/vsportexport` is
for - an addition that has proven itself belongs in `config.lua`.

If the folder is read-only the change still applies live, and the console says it will be lost on
restart.

### When the prop has no name

Some server builds will not expose a model name for a prop the catalogue has never seen - only a
hash. `/vsportadd` says so and prints the hash, and a hash works everywhere a name does:

```lua
Config.ExtraEquipment = { treadmill = { models = { 1234567890 } } }
```

---

## Adding a prop by editing the config instead

If you would rather not do it in game, one line in your own `config.lua`. An entry whose key
already exists **patches** the shipped one, so three extra bench models is three names rather than
a restated block:

```lua
Config.ExtraEquipment = {
    bench_press = {
        models = { 'mygym_bench_a', 'mygym_bench_b', 'prop_gym_bench_01' },
    },
}
```

**A model name that does not exist costs nothing.** It hashes to a number no entity will ever
carry, so be generous - including with alternate spellings.

---

## Adding a whole new exercise

```lua
Config.ExtraEquipment = {
    squat_rack = {
        order = 14,
        label = 'Squat rack',              -- plain text, or a locale key if you added one
        description = 'Heavy compound lifting.',
        models = { 'mygym_squatrack' },

        gains = { strength = 1.2 },        -- in SESSIONS, not points. 1.0 = one full session.
        reps = 6,
        difficulty = 'hard',               -- a key from Config.Minigame.difficulties
        cooldown = 120,

        anim = { dict = 'amb@world_human_muscle_free_weights@male@barbell@base',
                 clip = 'base' },
        placeAnim = true,
        animOffset = vector3(0.0, -0.8, 0.09),
        animHeading = 0.0,

        require = { stats = { strength = 40 } },
    },
}
```

`gains` is in **sessions**, not points: `{ strength = 1.0 }` is one full session of strength.
More `reps` is not more reward - reps are how long the session lasts and how many chances there
are to miss.

---

## Equipment baked into an MLO

Some gym equipment is part of the map model rather than placed as an object, so there is no entity
for a scan to find. Those need a coordinate instead. Stand where the player should be and run
`/vsportspot pull_ups`; paste the printed line into `Config.Spots`.

Eight exercises ship with **no base-game model at all** for exactly this reason - kettlebells,
speed bags, treadmills, rowing machines, battle ropes, leg press, cable machines and mirror work.
Every name they used to list was rejected by `IsModelValid`. They are kept because gym MLOs really
do ship this equipment: add your model names and they start working immediately.

---

## The catalogue

`force` is strength, `lungs` is lung capacity. The numbers are what one PERFECT session is worth,
measured in sessions of that stat.

| Exercise | Config key | One session is worth | Models | Where to find one |
|---|---|---|---|---|
| **Bench press** | `bench_press` | force 1, stamina 0.15 | `prop_muscle_bench_01`<br>`prop_muscle_bench_03`<br>`prop_pris_bench_01`<br>`prop_weight_bench_02` | 1 of 4 placed on the map |
| **Free weights** | `free_weights` | force 0.85, stamina 0.1 | `prop_freeweight_01`<br>`prop_freeweight_02`<br>`prop_barbell_01`<br>`prop_barbell_02`<br>`prop_curl_bar_01`<br>`prop_barbell_10kg`<br>`prop_barbell_20kg`<br>`prop_barbell_30kg`<br>`prop_barbell_40kg`<br>`prop_barbell_50kg`<br>`prop_barbell_60kg`<br>`prop_barbell_80kg`<br>`prop_barbell_100kg` | 9 of 13 placed on the map |
| **Weight rack** | `weight_rack` | force 1.1 | `prop_weight_squat`<br>`prop_weight_rack_01`<br>`prop_weight_rack_02` | 1 of 3 placed on the map |
| **Kettlebells** | `kettlebell` | force 0.6, stamina 0.4 | - | your MLO only - no base-game model |
| **Pull-ups** | `pull_ups` | force 0.9, stamina 0.25 | `prop_beach_bars_01`<br>`prop_beach_bars_02`<br>`prop_beach_rings_01`<br>`prop_pris_bars_01` | 3 of 4 placed on the map |
| **Push-ups** | `push_ups` | force 0.55, stamina 0.45 | `prop_yoga_mat_01`<br>`prop_yoga_mat_02`<br>`prop_yoga_mat_03` | all placed on the map |
| **Sit-ups** | `sit_ups` | force 0.4, stamina 0.6 | `prop_yoga_mat_01`<br>`prop_yoga_mat_02`<br>`prop_yoga_mat_03` | all placed on the map |
| **Pose in the mirror** | `muscle_flex` | force 0.1 | - | your MLO only - no base-game model |
| **Heavy bag** | `punching_bag` | force 0.5, lungs 0.2, stamina 0.5 | `prop_beach_punchbag`<br>`prop_punch_bag_l` | supported, none found placed on the map |
| **Speed bag** | `speed_bag` | force 0.2, stamina 0.4 | - | your MLO only - no base-game model |
| **Treadmill** | `treadmill` | lungs 0.35, stamina 1 | - | your MLO only - no base-game model |
| **Exercise bike** | `exercise_bike` | lungs 0.3, stamina 0.9 | `prop_exer_bike_01` | all placed on the map |
| **Rowing machine** | `rowing_machine` | force 0.35, lungs 0.25, stamina 0.7 | - | your MLO only - no base-game model |
| **Battle ropes** | `battle_ropes` | force 0.45, lungs 0.2, stamina 0.6 | - | your MLO only - no base-game model |
| **Yoga** | `yoga` | lungs 1, stamina 0.15 | `prop_yoga_mat_01`<br>`prop_yoga_mat_02`<br>`prop_yoga_mat_03` | all placed on the map |
| **Stretching** | `stretching` | lungs 0.35, stamina 0.2 | `prop_yoga_mat_01`<br>`prop_yoga_mat_02`<br>`prop_yoga_mat_03` | all placed on the map |
| **Cable machine** | `cable_machine` | force 0.7, stamina 0.2 | - | your MLO only - no base-game model |

---

## Off by default

These are complete and correct entries, switched off for one of two reasons.

**Five of them because no animation the base game ships matches the equipment**, and a body doing
visibly the wrong thing reads worse than no option at all: nothing in GTA V does a dip, skips a
rope, throws a basketball or spikes a volleyball, and training on a street bench you would normally
sit on reads as absurd.

**The leg press because the body lands in the wrong place on it.** Not a mistake in the numbers: an
`animOffset` is measured from the prop's ORIGIN, and how high that origin sits above the ground is
decided by whoever placed the prop in your map, not by the model. The alignment studio spawns its
own copy to measure against, so its vertical is only right for a copy placed the way the studio
places it. If your map puts this machine somewhere those numbers fit, turn it on and measure it
yourself with `/vsportprop leg_press prop_muscle_bench_06`. Only the offset's Z should need changing.

Each is one line away from coming back:

```lua
Config.ExtraEquipment = {
    dip_bars      = { enabled = true },
    skipping_rope = { enabled = true },
    basketball    = { enabled = true },
    volleyball    = { enabled = true },
    park_bench    = { enabled = true },
    leg_press     = { enabled = true },
}
```

| Exercise | Config key | One session is worth | Models | Where to find one |
|---|---|---|---|---|
| **Dip bars** | `dip_bars` | force 0.75, stamina 0.2 | `prop_beach_dip_bars_01`<br>`prop_beach_dip_bars_02` | 1 of 2 placed on the map |
| **Bench sit-ups** | `park_bench` | force 0.45, stamina 0.35 | `prop_bench_08`<br>`prop_bench_01a`<br>`prop_bench_01b`<br>`prop_bench_01c`<br>`prop_bench_02`<br>`prop_bench_03`<br>`prop_bench_04`<br>`prop_bench_05`<br>`prop_bench_06`<br>`prop_bench_07`<br>`prop_bench_09`<br>`prop_bench_10`<br>`prop_bench_11`<br>`prop_fib_3b_bench`<br>`prop_wait_bench_01` | 12 of 15 placed on the map |
| **Skipping rope** | `skipping_rope` | lungs 0.45, stamina 0.65 | `prop_skip_rope_01` | all placed on the map |
| **Shoot hoops** | `basketball` | lungs 0.25, stamina 0.55 | `prop_bskball_01`<br>`prop_basketball_net` | supported, none found placed on the map |
| **Beach volleyball** | `volleyball` | lungs 0.2, stamina 0.5 | `prop_beach_volball01`<br>`prop_beach_volball02` | all placed on the map |
| **Leg press** | `leg_press` | force 0.8, stamina 0.3 | `prop_muscle_bench_06` | all placed on the map |

---

## Props compatibles (francais)

Ce fichier est **genere** depuis `shared/equipment.lua` par `tools/props.py`. Ne le modifiez pas a
la main : modifiez le catalogue ou votre config, puis regenerez.

**Ajouter un prop, entierement en jeu, en une minute.** Aucun fichier a modifier, aucun
redemarrage. Placez-vous dans votre salle, regardez la machine :

```
/vsportadd treadmill
```

C'est toute la premiere etape. La commande prend le prop que vous **regardez**, pas un nom que vous
tapez, verifie que le modele existe vraiment, et l'ajoute a l'exercice en direct pour tous les
joueurs. Ensuite `/vsportprop treadmill` vous met dans le ciel avec une copie du prop, une grille au
sol et une camera orbitale : vous ajustez le corps aux fleches, et **K** enregistre pour tout le
monde. Enfin `/vsportexport` affiche le tout comme bloc `Config.ExtraEquipment` a coller dans
`config.lua`, pour que ce soit definitif et versionne.

| Commande | Role |
|---|---|
| `/vsportscan [rayon]` | Les objets a proximite, ce que v-sport en sait, ce qu'ils proposent |
| `/vsportadd <exercice> [modele]` | Ajouter le prop que vous regardez |
| `/vsportremove <exercice> [modele]` | En retirer un, y compris un modele fourni |
| `/vsportcustom` | Lister les ajouts faits en jeu |
| `/vsportprop <exercice> [modele]` | Le studio d'alignement. **K** enregistre |
| `/vsportexport` | Afficher le tout comme bloc `config.lua` |
| `/vsportreload` | Relire `data/custom.json` |
| `/vsportreset [exercice]` | Oublier les ajouts d'un exercice, ou tous |
| `/vsportitems [inventaire]` | Les blocs d'items a coller dans votre inventaire |

Toutes reservees aux admins, verifie cote serveur.

Le stockage est `data/custom.json`, ecrit par le serveur et pousse a chaque client. Supprimable sans
risque : vous perdez les ajouts faits en jeu et rien d'autre. Ce n'est **pas** du versionnement,
c'est a ca que sert `/vsportexport`.

Si le prop n'a pas de nom exploitable sur votre build, la commande le dit et affiche le hash. Un
hash fonctionne partout ou un nom fonctionne : `models = { 1234567890 }`.

**Par la config plutot qu'en jeu** : une ligne dans votre `config.lua`. Une entree dont la cle
existe deja **complete** celle fournie.

```lua
Config.ExtraEquipment = {
    bench_press = { models = { 'mygym_bench_a', 'mygym_bench_b' } },
}
```

Un nom de modele inexistant ne coute rien : il se hache en un nombre qu'aucune entite ne portera.
Soyez genereux, y compris avec plusieurs orthographes.

**Materiel integre a un MLO** : il fait partie du modele de la carte, donc aucune entite a
detecter. Placez-vous dessus et tapez `/vsportspot pull_ups` pour obtenir une ligne
`Config.Spots`. Huit exercices sont livres sans aucun modele de base pour cette raison : tous les
noms qu'ils listaient ont ete rejetes par `IsModelValid`. Ajoutez les votres et ils fonctionnent.

**Les exercices desactives par defaut** le sont pour deux raisons. Cinq parce qu'aucune animation du
jeu de base ne correspond a l'equipement, et qu'un corps qui fait visiblement autre chose est pire
que pas d'option du tout. La presse a cuisses parce que le corps se place au mauvais endroit dessus :
un `animOffset` se mesure depuis l'ORIGINE du prop, et la hauteur de cette origine au-dessus du sol
est decidee par celui qui a pose le prop dans la carte, pas par le modele. Le studio d'alignement
mesure sur sa propre copie, donc sa verticale n'est juste que pour une copie posee comme lui la pose.

Chacun se reactive en une ligne, voir la section anglaise ci-dessus.
