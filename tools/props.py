"""
Generate PROPS.md from the real catalogue.

WHY THIS IS GENERATED AND NOT WRITTEN BY HAND: a hand-written list of 30 model names across 18
exercises is wrong the first time somebody adds a prop, and nothing makes it complain. This reads
shared/equipment.lua through a real Lua interpreter, so the document cannot disagree with the code.

    python tools/props.py            writes PROPS.md
    python tools/props.py --check    fails if PROPS.md is out of date, for the check script
"""
import re
import sys
from pathlib import Path

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "PROPS.md"

# Which models the whole-map sweep actually found placed somewhere. Shared with alignment.py; a
# model can be real, supported and placed nowhere, and that distinction is the whole reason the
# "where to find one" column exists.
LOCATED = {
    "prop_freeweight_01", "prop_freeweight_02",
    "prop_barbell_01", "prop_barbell_02", "prop_curl_bar_01",
    "prop_barbell_20kg", "prop_barbell_30kg", "prop_barbell_60kg", "prop_barbell_100kg",
    "prop_weight_squat",
    "prop_beach_bars_01", "prop_beach_bars_02", "prop_beach_rings_01",
    "prop_beach_dip_bars_01",
    "prop_yoga_mat_01", "prop_yoga_mat_02", "prop_yoga_mat_03",
    "prop_exer_bike_01", "prop_skip_rope_01",
    "prop_beach_volball01", "prop_beach_volball02",
    "prop_bench_01a", "prop_bench_02", "prop_bench_03", "prop_bench_04", "prop_bench_05",
    "prop_bench_06", "prop_bench_07", "prop_bench_08", "prop_bench_09", "prop_bench_10",
    "prop_bench_11", "prop_fib_3b_bench",
    "prop_muscle_bench_03", "prop_muscle_bench_05", "prop_muscle_bench_06",
}

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("""
    function GetHashKey(s)
        local h = 5381
        for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 4294967296 end
        return h
    end
    joaat = GetHashKey
    function IsDuplicityVersion() return true end
    function GetCurrentResourceName() return 'v-sport' end
    function GetConvar(_, d) return d end
    function CreateThread(fn) end
    function Wait(_) end
    function vector3(x, y, z) return setmetatable({x=x,y=y,z=z}, {__name='vector3'}) end
    json = { encode = function() return '{}' end, decode = function() return {} end }
""")

for rel in ("bridge/shared/sport.lua", "bridge/shared/locale.lua", "locales/en.lua",
            "locales/fr.lua", "config.lua", "shared/equipment.lua"):
    src = (ROOT / rel).read_text(encoding="utf-8")
    lua.execute(re.sub(r"`([A-Za-z0-9_]+)`", r'GetHashKey("\1")', src))


def seq(table):
    if table is None:
        return []
    out, index = [], 1
    while table[index] is not None:
        out.append(table[index])
        index += 1
    return out


def label_of(entry):
    key = entry.label
    if not isinstance(key, str):
        return "?"
    text = lua.eval(f"L('{key}')")
    return text if isinstance(text, str) and text and text != key else key


def gains_of(entry, key):
    gains = lua.eval(f"Equipment.catalogue['{key}'].gains")
    if gains is None:
        return "-"
    parts = []
    for stat, amount in gains.items():
        short = {"strength": "force", "breath": "lungs", "stamina": "stamina"}.get(stat, stat)
        parts.append(f"{short} {amount:g}")
    return ", ".join(sorted(parts))


# Every entry, including the disabled ones - a document that silently omits the four exercises
# somebody switched off is how "why does my punchbag do nothing" support requests happen.
all_keys = seq(lua.eval("Equipment.keys"))
catalogue = lua.eval("Equipment.catalogue")
every_key = sorted({k for k, _ in catalogue.items()},
                   key=lambda k: catalogue[k].order or 999)

enabled = [k for k in every_key if catalogue[k].enabled is not False]
disabled = [k for k in every_key if catalogue[k].enabled is False]

model_count = len({m for k in enabled for m in seq(catalogue[k].models)})


def rows_for(keys):
    lines = []
    for key in keys:
        entry = catalogue[key]
        models = seq(entry.models)
        mlo_only = entry.mloOnly is True

        if mlo_only or not models:
            where = "your MLO only - no base-game model"
            listed = "-"
        else:
            placed = [m for m in models if m in LOCATED]
            listed = "<br>".join(f"`{m}`" for m in models)
            if not placed:
                where = "supported, none found placed on the map"
            elif len(placed) == len(models):
                where = "all placed on the map"
            else:
                where = f"{len(placed)} of {len(models)} placed on the map"

        lines.append(f"| **{label_of(entry)}** | `{key}` | {gains_of(entry, key)} "
                     f"| {listed} | {where} |")
    return lines


HEADER = f"""# Compatible props

Which props v-sport recognises, and how to add your own.

**{len(enabled)} exercises over {model_count} prop models.** Every model name here was verified
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
Config.ExtraEquipment = {{ treadmill = {{ models = {{ 1234567890 }} }} }}
```

---

## Adding a prop by editing the config instead

If you would rather not do it in game, one line in your own `config.lua`. An entry whose key
already exists **patches** the shipped one, so three extra bench models is three names rather than
a restated block:

```lua
Config.ExtraEquipment = {{
    bench_press = {{
        models = {{ 'mygym_bench_a', 'mygym_bench_b', 'prop_gym_bench_01' }},
    }},
}}
```

**A model name that does not exist costs nothing.** It hashes to a number no entity will ever
carry, so be generous - including with alternate spellings.

---

## Adding a whole new exercise

```lua
Config.ExtraEquipment = {{
    squat_rack = {{
        order = 14,
        label = 'Squat rack',              -- plain text, or a locale key if you added one
        description = 'Heavy compound lifting.',
        models = {{ 'mygym_squatrack' }},

        gains = {{ strength = 1.2 }},        -- in SESSIONS, not points. 1.0 = one full session.
        reps = 6,
        difficulty = 'hard',               -- a key from Config.Minigame.difficulties
        cooldown = 120,

        anim = {{ dict = 'amb@world_human_muscle_free_weights@male@barbell@base',
                 clip = 'base' }},
        placeAnim = true,
        animOffset = vector3(0.0, -0.8, 0.09),
        animHeading = 0.0,

        require = {{ stats = {{ strength = 40 }} }},
    }},
}}
```

`gains` is in **sessions**, not points: `{{ strength = 1.0 }}` is one full session of strength.
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
"""

FOOTER_DISABLED = """
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
"""

FOOTER = """
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
"""


def build():
    # rstrip on every block before joining: a block that ends in a newline plus the join's own
    # newline puts a blank line between a markdown table's header and its first row, which stops
    # it being a table at all. The first generated file had two empty tables for that reason.
    parts = [HEADER.rstrip("\n")]
    parts.extend(rows_for(enabled))
    if disabled:
        parts.append(FOOTER_DISABLED.rstrip("\n"))
        parts.extend(rows_for(disabled))
    parts.append(FOOTER)
    return "\n".join(parts).rstrip("\n") + "\n"


text = build()

if "--check" in sys.argv:
    current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    if current != text:
        print("PROPS.md is out of date - run: python tools/props.py")
        sys.exit(1)
    print(f"  PROPS.md: current, {len(enabled)} exercises over {model_count} models  OK")
else:
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {OUT.name}: {len(enabled)} exercises, {model_count} models, "
          f"{len(disabled)} disabled")
