# Items

Adding whey and the other consumables to your inventory.

**This is a manual step and it has to be.** v-sport registers the *use handler* for each item
in `Config.Items`. It cannot create the item, because creating an item means writing into
qb-core's `items.lua`, or ESX's `items` table, or ox_inventory's `data/items.lua` - files that
belong to other resources. A script that edited one of those behind your back would break on
their next update and leave you wondering why.

It takes about two minutes. Pick your inventory below and paste the block.

## Or let the resource write the block for you

```
/vsportitems
```

It detects your inventory and prints the exact block to paste, **generated from `Config.Items`**.
Pass `qb-core`, `ox_inventory`, `esx` or `all` to get a specific one.

Use it rather than copying from the sections below if you have changed anything: the blocks here are
written for the shipped names and weights, and the command's output follows your config. Rename
`whey` to `proteine`, change a weight, add a fifth item - run the command again and the block is
correct. That is the whole reason `label`, `description`, `weight` and `image` live in `config.lua`
rather than only in this document.

The command is admin only, and it prints to both the server console and your own F8.

An item configured in `Config.Items` that does not exist in your inventory costs nothing: the
handler is registered, nobody can ever hold one, and it is never called. So you can add whey
now and the other three later, or never.

---

## What the items do

| Config key | Item name | Effect |
|---|---|---|
| `whey` | `whey` | Cuts the training-allowance recovery window from 25 hours to 8, for the next 25 hours |
| `protein_bar` | `protein_bar` | Gives 10 points of spent allowance straight back |
| `pre_workout` | `pre_workout` | Training gains x1.5 for 30 minutes |
| `sports_drink` | `sports_drink` | Refills the sprint bar |

All four are defined in section 5c of `config.lua`, where the amounts, durations, cooldowns
and messages can be changed. The `effect` field is what decides behaviour; the rest is
numbers.

Each entry also carries the inventory metadata - `label`, `description`, `weight` and `image`. This
resource never reads those; `/vsportitems` does, to generate your registration block. Keeping them in
the config is what stops a rename from meaning two edits in two files.

## Images

`images/` holds an icon for each of the four, **as PNG ready to use** at 100x100 with a transparent
background, plus the SVG sources they were drawn from. Copy the four PNGs into your inventory's image
folder - `images/README.md` has the path for five common inventories, and `python tools/icons.py`
rebuilds them if you edit anything.

If you would rather not bother, point the config at an image your inventory already ships:

```lua
Config.Items.whey.image = 'protein.png'
```

A missing image is not fatal either. Inventories fall back to a placeholder and the item still works.

**Whey is the important one.** The recovery mechanic in section 5b is what stops a player
maxing out in a weekend, and whey is the intended way to speed it up. Everything else is
optional flavour.

---

## qb-core / qbx_core

### 1. Declare the items

Open `qb-core/shared/items.lua` and add these inside the `QBShared.Items` table:

```lua
['whey'] = {
    name = 'whey',
    label = 'Whey Protein',
    weight = 500,
    type = 'item',
    image = 'whey.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Recover from training in eight hours instead of twenty-five.'
},

['protein_bar'] = {
    name = 'protein_bar',
    label = 'Protein Bar',
    weight = 150,
    type = 'item',
    image = 'protein_bar.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'A little of your training allowance back.'
},

['pre_workout'] = {
    name = 'pre_workout',
    label = 'Pre-Workout',
    weight = 300,
    type = 'item',
    image = 'pre_workout.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Everything you train for the next half hour is worth more.'
},

['sports_drink'] = {
    name = 'sports_drink',
    label = 'Sports Drink',
    weight = 400,
    type = 'item',
    image = 'sports_drink.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Get your breath back.'
},
```

`useable = true` is the one that matters - without it qb-core never calls the handler.

### 2. Images

Drop four PNGs into `qb-inventory/html/images/` named `whey.png`, `protein_bar.png`,
`pre_workout.png` and `sports_drink.png`. A missing image is a broken-image icon in the
inventory and nothing worse; the item still works.

### 3. Restart

```
refresh
restart qb-core
restart v-sport
```

Then give yourself one:

```
/giveitem 1 whey 1
```

### 4. Check

The server console should print `[v-sport] registered 4 usable items` a few seconds after
start. Use the whey and the panel's recovery line should drop to 8 hours.

---

## ESX (es_extended)

### 1. Insert the items

ESX keeps items in the database. Run this against your database:

```sql
INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('whey',         'Whey Protein', 1, 0, 1),
    ('protein_bar',  'Protein Bar',  1, 0, 1),
    ('pre_workout',  'Pre-Workout',  1, 0, 1),
    ('sports_drink', 'Sports Drink', 1, 0, 1);
```

Some ESX forks have a different `items` schema - older ones have no `weight`, newer ones add
`limit`. Match whatever columns your own table has; the only one v-sport cares about is
`name`.

### 2. Restart

```
restart es_extended
restart v-sport
```

### 3. Check

```
/giveitem 1 whey 1
```

`[v-sport] registered 4 usable items` in the console means the handlers are attached.

---

## ox_inventory

ox_inventory owns its own item definitions and its own use flow, and v-sport listens for its
`usedItem` event rather than registering a handler with the framework.

### 1. Declare the items

Open `ox_inventory/data/items.lua` and add:

```lua
['whey'] = {
    label = 'Whey Protein',
    weight = 500,
    stack = true,
    close = true,
    description = 'Recover from training in eight hours instead of twenty-five.',
    client = {
        status = { thirst = -5000 },
        anim = 'eating',
        prop = 'burger',
        usetime = 3000,
    },
    consume = 1,
},

['protein_bar'] = {
    label = 'Protein Bar',
    weight = 150,
    stack = true,
    close = true,
    description = 'A little of your training allowance back.',
    client = { anim = 'eating', prop = 'burger', usetime = 2500 },
    consume = 1,
},

['pre_workout'] = {
    label = 'Pre-Workout',
    weight = 300,
    stack = true,
    close = true,
    description = 'Everything you train for the next half hour is worth more.',
    client = { anim = 'eating', prop = 'burger', usetime = 2000 },
    consume = 1,
},

['sports_drink'] = {
    label = 'Sports Drink',
    weight = 400,
    stack = true,
    close = true,
    description = 'Get your breath back.',
    client = {
        status = { thirst = 40000 },
        anim = 'drinking',
        prop = 'water_bottle',
        usetime = 2000,
    },
    consume = 1,
},
```

**`consume = 1` matters.** ox_inventory removes the item itself, so v-sport does not - set
`consume = false` in `Config.Items` for that item if you would rather it were not eaten, or
just leave both alone and it behaves the way you expect.

### 2. Images

`ox_inventory/web/images/whey.png`, and so on for the other three.

### 3. Restart

```
refresh
restart ox_inventory
restart v-sport
```

### 4. Check

```
/giveitem 1 whey 1
```

The console prints `[v-sport] listening for ox_inventory:usedItem` when debug is on, and
`registered N usable items` for whatever the framework also accepted.

---

## Any other inventory

If your inventory is none of the above, call the export from your own use handler and you get
identical behaviour:

```lua
-- In your inventory's use handler, wherever it lives:
local shouldConsume = exports['v-sport']:UseItem(source, 'whey')

if shouldConsume then
    -- remove one, however your inventory does that
end
```

`UseItem` takes the **config key** (`'whey'`), not the item name - they happen to be the same
in the shipped config, and do not have to be. It returns whether the item should be consumed,
which is `false` when the effect did not apply: taking whey when you are already on the short
window refuses rather than quietly eating the item.

To see what is configured:

```lua
local items = exports['v-sport']:GetItems()
-- { whey = { item = 'whey', effect = 'recovery', duration = 90000, cooldown = 300 }, ... }
```

---

## Adding your own item

`Config.Items` in section 5c takes as many entries as you like. Six effects are available:

| `effect` | What it does | Uses |
|---|---|---|
| `recovery` | Shortened allowance window for `duration` | `duration` |
| `allowance` | Give back `amount` points of spent allowance | `amount` |
| `multiplier` | Training gains x`amount` for `duration` | `amount`, `duration`, `stat` |
| `buff` | `amount` points onto a stat's effective value | `amount`, `duration`, `stat` |
| `decay_pause` | No decay for `duration` | `duration` |
| `stamina` | Refill the sprint bar by `amount` (0..1) | `amount` |

A steroid that grants strength and then costs it back:

```lua
Config.Items.steroids = {
    item = 'steroids',
    effect = 'buff',
    stat = 'strength',
    amount = 25.0,
    duration = 900,
    consume = true,
    cooldown = 3600,
    notify = 'You feel enormous.',
}
```

`notify` is a locale key when one exists and plain text otherwise, so you do not have to add
a translation to use your own message.

For the comedown, listen for the expiry event in your own resource:

```lua
AddEventHandler('vsport:server:BuffExpired', function(src, id, stat)
    if id == 'item:steroids' then
        exports['v-sport']:ApplyDebuff(src, 'strength', 10, 600)
        exports['v-sport']:Exhaust(src, 0.2, 120)
    end
end)
```

Buffs applied by an item carry the id `item:<config key>`, which is what makes that check
possible.

Anything more involved than the six effects belongs in your own resource, calling the exports
in [API.md](API.md) directly. That is what they are for.

---
---

# Items (Version Française)

Ajouter la whey et les autres consommables à votre inventaire.

**C'est une étape manuelle, et elle doit l'être.** v-sport enregistre le *gestionnaire
d'utilisation* de chaque item de `Config.Items`. Il ne peut pas créer l'item, car cela
signifierait écrire dans le `items.lua` de qb-core, la table `items` d'ESX ou le
`data/items.lua` d'ox_inventory : des fichiers qui appartiennent à d'autres ressources. Un
script qui modifierait l'un d'eux en douce casserait à leur prochaine mise à jour.

Comptez deux minutes. Choisissez votre inventaire ci-dessous et collez le bloc.

Un item déclaré dans `Config.Items` mais absent de votre inventaire ne coûte rien : le
gestionnaire est enregistré, personne ne peut en posséder, il n'est jamais appelé.

## Ce que font les items

| Clé de config | Nom de l'item | Effet |
|---|---|---|
| `whey` | `whey` | Ramène la récupération du quota de 25 heures à 8, pour les 25 heures suivantes |
| `protein_bar` | `protein_bar` | Rend 10 points de quota consommé |
| `pre_workout` | `pre_workout` | Gains d'entraînement x1,5 pendant 30 minutes |
| `sports_drink` | `sports_drink` | Remplit la barre de sprint |

Les quatre sont définis en section 5c de `config.lua` : montants, durées, temps de rechargement
et messages s'y modifient.

**La whey est l'item important.** Le système de récupération de la section 5b est ce qui
empêche un joueur d'arriver au maximum en un week-end, et la whey est le moyen prévu pour
l'accélérer. Le reste est facultatif.

## qb-core / qbx_core

Ajoutez les quatre entrées de la section anglaise ci-dessus dans `QBShared.Items`
(`qb-core/shared/items.lua`). `useable = true` est le champ indispensable : sans lui, qb-core
n'appelle jamais le gestionnaire.

Déposez les images dans `qb-inventory/html/images/`, puis :

```
refresh
restart qb-core
restart v-sport
```

Vérifiez avec `/giveitem 1 whey 1`. La console doit afficher
`[v-sport] registered 4 usable items` quelques secondes après le démarrage.

## ESX (es_extended)

ESX stocke les items en base. Exécutez la requête `INSERT INTO items` de la section anglaise,
en adaptant les colonnes à votre propre schéma - certains forks n'ont pas `weight`, d'autres
ajoutent `limit`. La seule colonne dont v-sport a besoin est `name`.

Puis `restart es_extended` et `restart v-sport`.

## ox_inventory

ox_inventory gère ses propres définitions. Ajoutez les quatre entrées de la section anglaise
dans `ox_inventory/data/items.lua`.

**`consume = 1` est important** : ox_inventory retire l'item lui-même, donc v-sport ne le fait
pas.

Images dans `ox_inventory/web/images/`, puis `refresh`, `restart ox_inventory`,
`restart v-sport`.

## N'importe quel autre inventaire

Appelez l'export depuis votre propre gestionnaire :

```lua
local shouldConsume = exports['v-sport']:UseItem(source, 'whey')
if shouldConsume then
    -- retirez-en un, comme votre inventaire le fait
end
```

`UseItem` prend la **clé de config**, pas le nom de l'item. Elle retourne si l'item doit être
consommé : `false` quand l'effet ne s'est pas appliqué, par exemple prendre de la whey quand
on est déjà sur la fenêtre courte.

## Ajouter votre propre item

`Config.Items` accepte autant d'entrées que vous voulez, avec six effets disponibles :
`recovery`, `allowance`, `multiplier`, `buff`, `decay_pause`, `stamina`. Voir le tableau de la
section anglaise et l'exemple des stéroïdes, y compris la descente branchée sur l'événement
`vsport:server:BuffExpired`.

Les buffs posés par un item portent l'identifiant `item:<clé de config>`, ce qui rend ce test
possible.

Tout ce qui dépasse ces six effets appartient à votre propre ressource, en appelant
directement les exports de [API.md](API.md).
