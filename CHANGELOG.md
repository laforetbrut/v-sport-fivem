# Changelog

All notable changes to v-sport. Newest first. English, then French.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.1] - 2026-08-07

A hardening release. Nothing was added for its own sake: an audit went through the resource across
six dimensions - framework compatibility, latent correctness, performance, server trust boundaries,
dead code, and documentation against reality - and every finding was adversarially re-checked before
being acted on. Fifty-seven survived that. These are the ones that mattered.

### Fixed

- **Every character on an account shared one body.** `Bridge.identifier` answered with the Rockstar
  licence when the framework had not finished loading the character, instead of nil - and the caller
  retries for twenty seconds ON NIL ONLY, so it never retried. The profile was keyed on the licence,
  and the framework's own load event arriving later with the real citizenid was dropped. The trigger
  was routine: the client announces itself as soon as a ped exists, which on qb-core is true while
  the multicharacter selector is still open. So `Config.Persistence.scope = 'character'`, the
  documented default, silently behaved as `'license'` on the one framework that had been tested.
- **A database hiccup could erase a character.** `Database.load` returned plain nil both for "this
  character has no row yet" and "the query failed", and the caller read that as a new character: it
  installed a blank profile and the next autosave wrote those zeroes over a real saved row. It now
  answers `row, ok`, and on a failure the session runs with no profile rather than with a false one.
- **The minigame was silent on any server with interact-sound installed.** Every cue is a GTA
  *frontend* sound with a soundset; interact-sound plays files from its own resource and takes no
  soundset. So routing them through it played nothing, and because a fired event counted as success
  the native fallback was never reached. `Config.Compat.soundResource` is gone with the routing.
- **No per-model placement was ever applied on a server with a target.** The target integration built
  its candidate without the `model` field, so `Equipment.staging` returned generic values and an
  incline bench got a flat bench's offset. `Session.start` now derives the model from the entity when
  a caller omits it, so no future integration can repeat it.
- **Stopping a workout teleported the player a metre into the air**, then dropped them - and put them
  down at the *bench's* position rather than their own. A ped's coordinates are its feet, so the
  `+ 1.0` was clearance it did not need. It now returns them to where they were standing.
- **Item registration died on ox_core, twice in the same file.** The core object there is an exports
  table, and reading a key it does not have RAISES rather than returning nil - so `core.Functions`
  threw and every item after it went unregistered. The second occurrence, ten lines below the comment
  explaining the hazard, was found by a new assertion rather than by reading.
- **`/vsportadmin` did not exist on ESX.** `object.RegisterCommand` is a method and was called
  without its object, so ESX read the command name as its own self and registered nothing.
- **Job-gated equipment was closed to everyone on ox_core** - `Compat.roles` had no ox branch at all -
  and a requirement written against a job *type* was refused by the client while passing on the
  server, because only the server read `jobType`.
- **A static spot's `job` restriction did nothing.** It was stored by the client and read by nobody,
  so a gym an operator believed was locked to the police was open to everyone. Now enforced on the
  server, which finds the spot from the coordinates rather than trusting the client.
- **`Config.Spots` were unreachable on any server with a target.** The prompt loop returned early, and
  a target has nothing to attach to for a coordinate - so equipment baked into an MLO could not be
  used at all. The loop now runs for spots and stays quiet about props, which is what the config had
  always promised.
- **`ApplyPackage` leaked multipliers.** An all-stat multiplier creates one per stat and returns the
  group; only the first id was recorded, so `ClearPackage` removed one of three and a drug's gain
  boost outlived the drug.
- **The tuner's centred hold never worked.** It saved `spec.centred` and every reader looks for
  `spec.centre`, so a long bar came back attached by its origin instead of its middle. One letter.
- **`/vsportadd` resurrected models that `/vsportremove` had taken out**, because it reseeded from the
  shipped list on every add.
- Also: the interaction prompt no longer duplicates a target resource; okokNotify is passed a type it
  recognises; `/vsportitems` detects ESX (`Bridge.framework()` answers `es_extended`, and the check
  was for `esx`); the per-frame draw loop is gated on the 6 m draw budget rather than the 20 m
  detection radius; and `Config.Persistence.saveInterval` is the field that actually drives the save
  cadence, which the documentation always said it was and which nothing read.

### Changed

- **Free weights are lifted where you stand.** Dumbbells and barbells on the ground no longer move or
  attach the player: the body turns to face the weight and lifts it in place. That deletes
  `animOffset` for all thirteen models, and with it the most fragile data in the resource - an offset
  measured from a prop's origin cannot be right unless you know how high the map put that origin, and
  the alignment studio, which spawns its own copy, cannot know. Benches and racks still attach,
  because being in the right place is what those exercises are.
- **A player's F8 is not a log file.** Client-side `Sport.print` and `Sport.warn` now reach admins
  only, or anybody with `Config.Debug.enabled`. Server output is untouched. Ordinary players were
  seeing diagnostics written for whoever runs the server.
- Three config fields that were declared, documented and read by nothing are gone rather than
  half-true: `Config.Detection.matchAttached`, `Config.Security.requireToken` and
  `Config.UI.workout.showStatGains`. `Config.Notifications.cooldownActive` is now read instead.
- Three `prop_muscle_bench` models removed. Two are incline benches and one is a pull-up frame, all
  named as if they were flat weight benches, and none could be measured reliably.

### Added

- **`tools/check.py` gained four assertions**, each for a class of defect found above: the framework
  object is never indexed raw, no raw `print()` sits on a gameplay client path, every `roles()` answer
  carries `jobType`, and `data/custom.json` ships empty. The first one caught a second live instance
  of its own bug on its first run.
- **`/vsportprop <exercise> here`** aligns against whatever object is in front of you, with no model
  filter, no search and no studio copy - and reports which model it turned out to be.

---

## [1.0.0] — 2026-08-06

First release.

### Added

- **Automatic equipment detection.** The object pool around the player is matched against a
  catalogue of 18 exercises over 31 prop models: benches, dumbbells and every loaded barbell,
  squat racks, pull-up bars and rings, mats, the heavy bag, exercise bikes, yoga and stretching,
  plus kettlebells, speed bags, treadmills, rowing machines, battle ropes, leg press, cable
  machines and mirror work for gyms whose MLO ships them.

  Every model name was verified against the game with `IsModelValid`: 85 that appear on the
  community prop lists do not exist in the base files at all and were removed rather than left in
  to look generous. A whole-map sweep then recorded which of the survivors are actually placed
  somewhere, since a model that exists and sits nowhere cannot be walked up to.
- **Every body placement measured in game, not guessed.** All 40 prop and exercise pairs, each one
  aligned with `/vsportprop` against the real prop and pasted back as a measurement, with
  `modelOverrides` where a sibling model genuinely differs - the two beach pull-up frames put their
  origins in different places, and the three weight racks sit at three different heights. Where a
  prop could not be measured reliably it was removed rather than shipped with a guess.
- **`/vsporttour` reviews every animation on every prop, one at a time.** It spawns each prop and
  exercise pair in turn with its real placement and waits for a verdict: `1` right, `2` wrong. F8 lists
  only the wrong ones at the end, with the command to fix each. The only way to know an animation looks
  right on a given prop is to look at it, and this is forty looks without forty commands.
- **`/vsportmissing` answers "have we missed a prop?" by asking the game.** It runs `IsModelValid`
  over a candidate list and reports both directions: models that exist in your build and are not in
  the catalogue, and models the catalogue claims that your build does not have. A list cannot answer
  this - every published GTA prop dump is incomplete, and the one used to seed the candidates
  contains neither `prop_weight_squat` nor `prop_pris_bench_01`, both of which are real and in use
  here. Add your MLO's names to `Config.Debug.candidateModels` and the game will confirm them.

  It found `prop_punch_bag_l`, the game's other heavy bag, which was not in the catalogue.
- **Add equipment from inside the game, with no file to edit and no restart.** Stand in your own gym
  MLO, look at the machine, and `/vsportadd treadmill`. It takes the prop you are **looking at** -
  not a name you typed - checks the game really has that model, and adds it live for every player.
  Then `/vsportprop treadmill` to align the body, and **K** saves that for everyone too.

  Additions live in `data/custom.json`, owned by the server and pushed to every client, and both
  sides rebuild the catalogue in place. `/vsportexport` prints the lot as a `Config.ExtraEquipment`
  block for when an addition has proven itself and belongs in version control; `/vsportcustom`,
  `/vsportremove`, `/vsportreload` and `/vsportreset` cover the rest. The client resolves and
  validates the model; the server re-checks `Bridge.isAdmin` on every event and re-validates the
  name, because that one ends up on disk.
- **`/vsportitems` writes your inventory block for you**, generated from `Config.Items` for qb-core,
  ox_inventory or ESX. Each item now carries its own `label`, `description`, `weight` and `image`, so
  renaming `whey` to `proteine` is one edit instead of two and the documented block can never be out
  of date with the config.
- **Item icons**, as SVG sources in `images/`, with a one-line conversion command and the image
  folder path for five common inventories. SVG because one source covers a 64 px ox_inventory slot
  and a 200 px custom one without the blur a resized PNG gets, and because changing the whey tub's
  colour to match your server is one hex value.
- **GitHub issue templates**, six of them: bug, unrecognised prop, compatibility, balance, feature
  and documentation. The prop template leads with `/vsportadd`, because most of those reports are
  something the reporter can fix in ten seconds without waiting for a release. Plus a security
  policy that says plainly what does and does not count as a vulnerability, and a pull request
  checklist tied to what the check script enforces.
- **The developer commands are admin-only, server-side.** `/vsportprop`, `/vsportgoto`,
  `/vsportfind`, `/vsportscan`, `/vsportspot`, `/vsportoffset` and `/vsportinfo` are gated by
  `Bridge.isAdmin`, checked on the server and pushed to the client, which refuses everything until
  an answer arrives. Two of them teleport, so left open they were a free teleport in every player's
  chat suggestions - `Config.Commands.restrictDevCommands` had shipped declared, documented and
  read by nothing. `/vsportdev` re-asks, for an admin promoted mid-session. The check script now
  fails the build if a dev command loses its gate, and refuses to pass if its own detection breaks.
- **The effect ceilings are provably hard.** No stack of buffs, drugs or admin commands can take an
  effect past its configured `max`: `Stats.bonus` clamps the stat to its own maximum before
  interpolating, and the check script asserts it against the buff overcap and against absurd
  values. `Config.Buffs.overcap` used to claim otherwise, which was a documentation error, not a
  behaviour one.
- **[PROPS.md](PROPS.md), generated from the catalogue.** Every supported prop model, what each
  exercise is worth, whether the model is actually placed anywhere on the map, and how to add your
  own. Generated by `tools/props.py` so it cannot drift, and the check script fails if it is stale.
- **Passive training from four real activities.** Sprinting on foot and riding a bicycle build
  stamina, swimming builds stamina and lung capacity, and diving is the best outdoor source of
  lung capacity there is. Every activity takes any number of stats, priced per kilometre or per
  minute, and is entirely configurable.

  Three separate mechanisms keep the equipment ahead, and the check script asserts the result
  rather than trusting it: the caps hold the best possible passive day to 11% of a dedicated gym
  day, a per-activity `ceiling` stops passive gains dead partway up each stat, and passive
  activity does not reset the decay clock - so a player who only cycles loses ground.
- **Five exercises deliberately off by default, and some props left out.** Dip bars, the skipping
  rope, volleyball, basketball and bench sit-ups: the props exist and align fine, but nothing shipped
  with the game does a dip, skips a rope or strikes a ball, so each fell back to a jog on the spot or a
  chin-up in mid-air. Two `prop_muscle_bench` models and a rolled-up yoga mat are left out of their
  exercises for the same reason.

  **With no animation that matches the equipment, nothing beats something that reads as broken.** Each
  is one `Config.ExtraEquipment` line away from coming back, with the reasoning written above it in
  `shared/equipment.lua`.
- **`/vsportscan` and `/vsportspot`.** No shipped catalogue can know what a custom MLO contains,
  so these print what your own map actually has and a ready-to-paste config line for it. An
  unknown model name costs nothing, so the shipped lists are deliberately generous.
- **`Config.ExtraEquipment`.** Add equipment, or patch what ships, without editing a file under
  `shared/`. A key that already exists patches the shipped entry.
- **`Config.Spots`.** Static positions for gym equipment baked into an MLO model, where there is
  no object for a scan to find.
- **Rhythm QTE.** Each rep asks for a short sequence of random keys on a timing band, judged
  against a perfect zone and a wider good zone. Clean reps build a streak; consecutive misses
  end the session early. Four difficulty presets, overridable per piece of equipment.
- **Three stats.** Strength, lung capacity and stamina - the three GTA already models. The real
  `MP0_STRENGTH`, `MP0_STAMINA` and `MP0_LUNG_CAPACITY` character stats are written, plus a
  small configured layer of melee damage, melee resistance, underwater time, swim speed, sprint
  speed, health regeneration and stamina recovery on top.
- **The training allowance.** A character may gain 24 points across every stat per 25 hour
  cycle, and no more than 12 into any single one. Once spent they are blocked until they
  recover. Rolling or block recovery modes.
- **Whey**, and three other consumables. Whey cuts the 25 hour recovery wait to 8. Also a
  protein bar (refunds spent allowance), a pre-workout (multiplies gains) and a sports drink
  (refills the sprint bar). Items are registered as usable on qb-core, ESX and ox_inventory;
  adding them to the inventory is a documented manual step.
- **Fatigue.** The gain multiplier falls with each session in a 90 minute window and recovers
  with rest, so the first three workouts of an afternoon are worth more than the next twenty.
- **Decay.** 5 points per day of not training, after one free day, computed from a timestamp
  so it runs while the player is offline. Per-stat rates, an absolute floor, optional peak
  protection, and job exemptions.
- **Seventy-two exports and their event twins**, covering reading, the allowance and recovery
  bypass, stat changes, buffs and debuffs, training multipliers, decay immunity, training
  blocks, direct effect overrides and exhaustion. Plus client exports and state bags.
- **Condition mechanics, for a smoking, addiction or injury script.** A habit is not an event,
  so alongside the buffs there are three ways to express being held back for as long as you have
  it: `SetStatCeiling` (train all you like, your lung capacity stops at 55), `AddDrain` (lose
  points per hour while it is in your system) and `SetDecayMultiplier` (a day off the gym costs
  twenty rather than ten). All bounded by `Config.Buffs`, and none of them touches a stat at the
  moment it is applied.
- **`ApplyPackage` and `ClearPackage`.** A drug is rarely one effect; hand it a table of buffs,
  multipliers, ceilings, drains, decay changes, exhaustion, allowance refunds and permanent stat
  changes, and get back a record that `ClearPackage` can undo.
- **A measured balance.** All three stats to 100% takes about a fortnight for a player who
  trains daily and hits their prompts, ~16 days at 90% form, ~22 with a rest day a week, and
  about five days for somebody who does nothing else - that last being the floor the allowance
  sets. The figures come from a day-by-day simulation of the real progression functions, which
  is part of the check script and fails if the headline moves.
- **Native UI.** The workout HUD and the stats panel are drawn with DrawRect and DrawText.
  There is no `ui_page`, no CEF process and no NUI focus to get stuck.
- **Three-tier performance model.** One loop at 1s when no equipment is near, one at 250ms when
  it is, one per frame only while a workout runs. The scan skips entirely when the player has
  not moved, compares squared distances, reuses its result table and caps at 400 objects. No
  per-player loop on the server.
- **Framework bridge.** qb-core, qbx_core, ESX and ox_core behind one adapter interface, plus a
  standalone fallback keyed on the Rockstar licence. ox_target, qb-target and qtarget for
  interaction; ox_lib, qb-core, ESX and okokNotify for notifications; oxmysql, mysql-async and
  ghmattimysql for storage. All detected at runtime, all optional.
- **Server-authoritative sessions.** Every workout is authorised with a single-use token, and a
  result is refused if it arrives faster than the reps could have been performed, if the player
  has walked away, if a cooldown or the rate limit is active, or if the allowance is spent.
  `vsport:server:CheatSuspected` fires after a threshold of rejections; this resource never
  kicks or bans anybody itself.
- **English and French**, key-for-key, with a checker that enforces both the key sets and the
  format specifiers.
- Documentation: README, CONFIG.md, API.md, ITEMS.md, RULES.md, ERROR_LOG.md.

### Notes

- Progress is not saved without a database resource. Training still works, and the resource
  says so once in the console and once to the player rather than failing quietly.
- Buffs and multipliers do not survive a server restart, by design.
- `Config.Effects.strength.maxHealth` ships **off**. Most frameworks, ambulance jobs and armour
  scripts assume 200 and will fight it.
- `Config.Progression.diminishing` ships **off**, because it silently breaks the promise that
  `sessionsToMax` sessions reach 100%.

---
---

# Journal des modifications (Version Française)

Toutes les modifications notables de v-sport. La plus récente en premier.

---

## [1.0.1] - 2026-08-07

Une version de consolidation. Un audit a parcouru la ressource sur six dimensions - compatibilite des
frameworks, correction latente, performance, frontieres de confiance serveur, code mort, et
documentation contre realite - et chaque trouvaille a ete re-verifiee de facon adverse avant d'etre
traitee. Cinquante-sept ont survecu.

### Corrige

- **Tous les personnages d'un compte partageaient un seul corps.** `Bridge.identifier` renvoyait la
  licence quand le framework n'avait pas fini de charger le personnage, au lieu de nil - et l'appelant
  ne reessaie QUE sur nil. Le profil etait donc cle sur la licence, et l'evenement de chargement du
  framework, arrivant plus tard avec le vrai citizenid, etait ignore. `scope = 'character'`, le defaut
  documente, se comportait silencieusement comme `'license'` sur le seul framework teste.
- **Un incident de base de donnees pouvait effacer un personnage.** `Database.load` renvoyait nil
  aussi bien pour « pas encore de ligne » que pour « la requete a echoue », et l'appelant y lisait un
  nouveau personnage : il installait un profil vide, et la sauvegarde suivante ecrivait ces zeros sur
  une vraie ligne. Elle repond maintenant `row, ok`.
- **Le minijeu etait muet sur tout serveur avec interact-sound.** Les cues sont des sons *frontend* de
  GTA avec un soundset ; interact-sound joue des fichiers et ne prend pas de soundset. Le routage ne
  jouait rien et empechait le native de s'executer.
- **Aucun placement par modele ne s'appliquait sur un serveur avec un target.** L'integration target
  construisait son candidat sans le champ `model`, donc un banc incline recevait l'offset d'un banc
  plat.
- **Arreter une seance teleportait le joueur un metre en l'air**, puis le laissait tomber, et le
  reposait a la position du *banc* plutot qu'a la sienne.
- **L'enregistrement des items mourait sur ox_core, deux fois dans le meme fichier.** L'objet core y
  est une table d'exports, et lire une cle absente **leve** au lieu de renvoyer nil.
- **`/vsportadmin` n'existait pas sur ESX** : la methode etait appelee sans son objet.
- **Le materiel restreint par metier etait ferme a tous sur ox_core**, et une restriction ecrite
  contre un *type* de metier etait refusee par le client tout en passant cote serveur.
- **La restriction `job` d'un spot statique ne faisait rien** : stockee par le client, lue par
  personne. Elle est maintenant appliquee cote serveur.
- **Les `Config.Spots` etaient inatteignables sur tout serveur avec un target**, donc le materiel
  integre a un MLO etait inutilisable.
- **`ApplyPackage` laissait fuir des multiplicateurs**, et **la prise centree de l'outil d'alignement
  n'a jamais fonctionne** - une lettre de difference entre ce qui etait ecrit et ce qui etait lu.
- **`/vsportadd` ressuscitait les modeles retires par `/vsportremove`.**

### Modifie

- **Les poids libres se soulevent la ou on est.** Le corps ne se deplace plus et ne s'attache plus :
  il se tourne vers l'haltere et le souleve sur place. Ca supprime l'`animOffset` des treize modeles,
  et avec lui la donnee la plus fragile de la ressource. Les bancs et les racks continuent de
  s'attacher, parce qu'y etre bien place *est* l'exercice.
- **Le F8 d'un joueur n'est pas un fichier de log.** Cote client, `Sport.print` et `Sport.warn` ne
  s'adressent plus qu'aux admins, ou a quiconque avec `Config.Debug.enabled`. La sortie serveur est
  inchangee.
- Trois champs de config declares, documentes et lus par rien ont ete retires plutot que laisses a
  moitie vrais. `Config.Notifications.cooldownActive` est desormais lu.
- Trois modeles `prop_muscle_bench` retires : deux bancs inclines et un portique de tractions, tous
  nommes comme des bancs plats, aucun mesurable de facon fiable.

### Ajoute

- **Quatre assertions dans `tools/check.py`**, une par classe de defaut ci-dessus. La premiere a
  attrape une seconde occurrence vivante de son propre bug des sa premiere execution.
- **`/vsportprop <exercice> here`** aligne contre l'objet devant vous, sans filtre de modele, sans
  recherche et sans copie studio.

---

## [1.0.0] — 2026-08-06

Première version.

### Ajouté

- **Détection automatique du matériel.** Le pool d'objets autour du joueur est comparé à un
  catalogue de 18 exercices répartis sur 31 modèles de props : bancs, haltères et toutes les barres
  chargées, racks à squat, barres de traction et anneaux, tapis, sac de frappe, vélos d'appartement,
  yoga et étirements, plus kettlebells, poires de vitesse, tapis de course, rameurs, cordes
  ondulatoires, presse à cuisses, machines à poulies et travail au miroir pour les salles dont le MLO
  les fournit.

  Chaque nom de modèle a été vérifié dans le jeu avec `IsModelValid` : 85 noms qui circulent sur les
  listes communautaires n'existent pas du tout dans les fichiers de base et ont été retirés plutôt que
  laissés pour faire nombre.
- **Chaque placement de corps mesuré en jeu, pas deviné.** Les 40 paires prop/exercice, chacune alignée
  avec `/vsportprop` contre le prop réel, avec un `modelOverrides` là où un modèle frère diffère
  vraiment : les deux portiques de plage placent leur origine à des endroits différents, et les trois
  racks sont à trois hauteurs différentes. Là où un prop ne pouvait pas être mesuré de façon fiable, il
  a été retiré plutôt que livré avec une approximation.
- **`/vsporttour` passe en revue chaque animation sur chaque prop, une par une.** Chaque paire apparaît
  à son tour avec son placement réel et attend un verdict : `1` correct, `2` faux. Le F8 ne liste que
  les mauvaises à la fin, avec la commande pour corriger chacune. La seule façon de savoir si une
  animation rend bien sur un prop est de la regarder, et voici quarante regards sans quarante commandes.
- **`/vsportmissing` répond à « a-t-on oublié un prop ? » en interrogeant le jeu.** La commande passe
  `IsModelValid` sur une liste de candidats et répond dans les deux sens : les modèles qui existent chez
  vous et ne sont pas au catalogue, et ceux que le catalogue revendique et que votre build n'a pas. Une
  liste ne peut pas répondre à ça, tous les dumps de props publiés étant incomplets. Ajoutez les noms de
  votre MLO dans `Config.Debug.candidateModels` et le jeu les confirmera.
- **Ajouter du matériel depuis le jeu, sans fichier à modifier ni redémarrage.** Placez-vous dans votre
  salle, regardez la machine, et `/vsportadd treadmill`. La commande prend le prop que vous **regardez**,
  pas un nom que vous tapez, vérifie que le jeu possède ce modèle, et l'ajoute en direct pour tous les
  joueurs. Puis `/vsportprop treadmill` pour aligner le corps, et **K** enregistre pour tout le monde.

  Les ajouts vivent dans `data/custom.json`, possédé par le serveur et poussé à chaque client.
  `/vsportexport` en fait un bloc `Config.ExtraEquipment` quand un ajout a fait ses preuves ;
  `/vsportcustom`, `/vsportremove`, `/vsportreload` et `/vsportreset` couvrent le reste.
- **`/vsportitems` écrit le bloc de votre inventaire**, généré depuis `Config.Items` pour qb-core,
  ox_inventory ou ESX. Chaque item porte son `label`, sa `description`, son `weight` et son `image` :
  renommer `whey` en `proteine` est une modification au lieu de deux, et le bloc documenté ne peut plus
  être en désaccord avec la config.
- **Les icônes des items**, en PNG prêtes à l'emploi et en sources SVG, avec le chemin du dossier
  d'images pour cinq inventaires courants et un script sans dépendance pour les régénérer.
- **Les commandes de développement sont réservées aux admins, côté serveur.** Deux d'entre elles
  téléportent, donc laissées ouvertes elles offraient un téléport gratuit à chaque joueur. Le contrôle
  passe par `Bridge.isAdmin`, décidé sur le serveur et poussé au client, qui refuse tout jusqu'à
  recevoir une réponse. Le script de vérification échoue si une commande perd sa protection.
- **Les plafonds d'effets sont durs, et c'est prouvé.** Aucun empilement de bonus, de drogues ou de
  commandes admin ne peut pousser un effet au-delà de son `max` configuré, et le script de vérification
  l'impose contre le dépassement de bonus comme contre des valeurs absurdes.
- **[PROPS.md](PROPS.md), généré depuis le catalogue.** Chaque modèle pris en charge, ce que vaut chaque
  exercice, si le modèle est réellement placé sur la carte, et comment ajouter les vôtres. Généré par
  `tools/props.py` pour qu'il ne puisse pas dériver.
- **`/vsportscan` et `/vsportspot`.** Aucun catalogue fourni ne peut connaître le contenu d'un MLO
  personnalisé : ces commandes affichent ce que votre carte contient réellement et une ligne de
  configuration prête à coller. Un nom de modèle inconnu ne coûte rien, les listes fournies sont
  donc volontairement généreuses.
- **`Config.ExtraEquipment`.** Ajouter du matériel, ou compléter celui fourni, sans toucher à un
  fichier de `shared/`. Une clé déjà existante complète l'entrée fournie.
- **`Config.Spots`.** Positions fixes pour le matériel intégré au modèle d'un MLO, là où aucun
  objet n'existe pour être détecté.
- **QTE rythmique.** Chaque répétition demande une courte séquence de touches aléatoires sur une
  bande de timing, jugée contre une zone parfaite et une zone correcte plus large. Les
  répétitions propres construisent un combo ; les ratés consécutifs arrêtent la séance. Quatre
  niveaux de difficulté, surchargeables par équipement.
- **Trois statistiques.** Force, apnée et endurance : les trois que GTA modélise déjà. Les
  vraies stats de personnage `MP0_STRENGTH`, `MP0_STAMINA` et `MP0_LUNG_CAPACITY` sont écrites,
  plus une petite couche configurable de dégâts au corps à corps, de résistance, de temps sous
  l'eau, de vitesse de nage, de sprint, de régénération et de récupération d'endurance.
- **Le quota d'entraînement.** Un personnage peut gagner 24 points toutes statistiques
  confondues par cycle de 25 heures, et pas plus de 12 dans une seule. Une fois épuisé, il est
  bloqué jusqu'à récupération. Modes de récupération glissant ou par bloc.
- **La whey**, et trois autres consommables. La whey ramène l'attente de 25 heures à 8. Aussi
  une barre protéinée (rembourse du quota), un pre-workout (multiplie les gains) et une boisson
  énergétique (remplit la barre de sprint). Les items sont enregistrés comme utilisables sur
  qb-core, ESX et ox_inventory ; les ajouter à l'inventaire est une étape manuelle documentée.
- **Fatigue.** Le multiplicateur de gain baisse à chaque séance dans une fenêtre de 90 minutes et
  remonte au repos : les trois premières séances d'un après-midi valent plus que les vingt
  suivantes.
- **Perte de niveau.** 5 points par jour sans entraînement, après un jour de grâce, calculée
  depuis un horodatage : elle tourne donc hors ligne. Taux par statistique, plancher absolu,
  protection du record optionnelle, et exemptions par métier.
- **Entraînement passif, sur quatre activités réelles.** Le sprint à pied et le vélo montent
  l'endurance, la nage monte l'endurance et l'apnée, et la plongée est la meilleure source d'apnée en
  extérieur. Chaque activité accepte autant de statistiques qu'on veut, tarifée au kilomètre ou à la
  minute, et reste entièrement configurable.

  Trois mécanismes distincts gardent l'équipement devant, et le script de vérification impose le
  résultat : les plafonds tiennent la meilleure journée passive possible à 11 % d'une journée de salle,
  un `ceiling` par activité arrête net les gains passifs à mi-parcours de chaque statistique, et
  l'activité passive ne remet pas à zéro le compteur de perte, donc qui ne fait que du vélo recule.
- **Soixante-douze exports et leurs équivalents en événements**, couvrant la lecture, le
  quota et le contournement de la récupération, les changements de statistiques, les bonus et
  malus, les multiplicateurs d'entraînement, l'immunité à la perte, le blocage de
  l'entraînement, les surcharges d'effet directes et l'épuisement. Plus les exports client et
  les state bags.
- **Mécanismes de condition, pour un script de fumette, d'addiction ou de blessure.** Une
  habitude n'est pas un événement : à côté des bonus, trois façons d'exprimer le fait d'être
  bridé tant qu'on l'a. `SetStatCeiling` (entraînez-vous tant que vous voulez, votre apnée
  plafonne à 55), `AddDrain` (perdre des points par heure tant que c'est dans le système) et
  `SetDecayMultiplier` (un jour sans salle coûte vingt au lieu de dix). Tous bornés par
  `Config.Buffs`, et aucun ne touche une statistique au moment où il est posé.
- **`ApplyPackage` et `ClearPackage`.** Une drogue est rarement un seul effet : passez une table
  de bonus, multiplicateurs, plafonds, drains, changements de perte, épuisement, remboursements
  de quota et modifications définitives, et récupérez un enregistrement que `ClearPackage` sait
  annuler.
- **Un équilibrage mesuré.** Les trois statistiques à 100 % demandent environ deux semaines à un
  joueur qui s'entraîne chaque jour et réussit ses touches, ~16 jours à 90 % de forme, ~22 avec
  un jour de repos par semaine, et environ cinq jours à qui ne fait rien d'autre - ce dernier
  étant le plancher fixé par le quota. Les chiffres viennent d'une simulation jour par jour des
  vraies fonctions de progression, intégrée au script de vérification, qui échoue si le chiffre
  principal bouge.
- **Interface native.** Le HUD de séance et le panneau de statistiques sont dessinés avec
  DrawRect et DrawText. Pas de `ui_page`, pas de processus CEF, pas de focus NUI à débloquer.
- **Modèle de performance à trois paliers.** Une boucle à 1 s quand aucun équipement n'est
  proche, une à 250 ms quand il y en a, une par frame uniquement pendant une séance. Le scan est
  entièrement sauté quand le joueur n'a pas bougé, compare des distances au carré, réutilise sa
  table de résultat et s'arrête à 400 objets. Aucune boucle par joueur côté serveur.
- **Pont framework.** qb-core, qbx_core, ESX et ox_core derrière une seule interface d'adaptateur,
  plus un mode autonome basé sur la licence Rockstar. ox_target, qb-target et qtarget pour
  l'interaction ; ox_lib, qb-core, ESX et okokNotify pour les notifications ; oxmysql,
  mysql-async et ghmattimysql pour le stockage. Tout détecté à l'exécution, tout optionnel.
- **Séances décidées par le serveur.** Chaque séance est autorisée par un jeton à usage unique,
  et un résultat est refusé s'il arrive plus vite que les répétitions ne pouvaient être
  effectuées, si le joueur s'est éloigné, si un temps de recharge ou la limite horaire est actif,
  ou si le quota est épuisé. `vsport:server:CheatSuspected` est émis après un seuil de rejets ;
  cette ressource n'expulse et ne bannit jamais personne elle-même.
- **Anglais et français**, clé pour clé, avec un vérificateur qui contrôle les jeux de clés et
  les spécificateurs de format.
- Documentation : README, CONFIG.md, API.md, ITEMS.md, RULES.md, ERROR_LOG.md.

### Notes

- La progression n'est pas sauvegardée sans ressource de base de données. L'entraînement
  fonctionne quand même, et la ressource le signale une fois en console et une fois au joueur
  plutôt que d'échouer en silence.
- Les bonus et multiplicateurs ne survivent pas à un redémarrage du serveur, volontairement.
- `Config.Effects.strength.maxHealth` est livré **désactivé**. La plupart des frameworks, des
  métiers ambulanciers et des scripts d'armure supposent 200 et entreront en conflit.
- `Config.Progression.diminishing` est livré **désactivé**, car il casse silencieusement la
  promesse que `sessionsToMax` séances suffisent pour atteindre 100 %.
