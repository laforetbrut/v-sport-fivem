# Changelog

All notable changes to v-sport. Newest first. English, then French.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
uses [semantic versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-08-06

First release.

### Added

- **Automatic equipment detection.** The object pool around the player is matched against a
  catalogue of 20 exercises spread over 94 prop models: benches, dumbbells, weight and squat
  racks, kettlebells, pull-up and dip bars, mats, heavy and speed bags, treadmills, exercise
  bikes, rowing machines, skipping ropes, battle ropes, yoga, stretching, leg press and cable
  machines.
- **`/sportscan` and `/sportspot`.** No shipped catalogue can know what a custom MLO contains,
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
- **The training allowance.** A character may gain 50 points across every stat per 25 hour
  cycle, and no more than 25 into any single one. Once spent they are blocked until they
  recover. Rolling or block recovery modes.
- **Whey**, and three other consumables. Whey cuts the 25 hour recovery wait to 8. Also a
  protein bar (refunds spent allowance), a pre-workout (multiplies gains) and a sports drink
  (refills the sprint bar). Items are registered as usable on qb-core, ESX and ox_inventory;
  adding them to the inventory is a documented manual step.
- **Fatigue.** The gain multiplier falls with each session in a 90 minute window and recovers
  with rest, so the first three workouts of an afternoon are worth more than the next twenty.
- **Decay.** 10 points per day of not training, after one free day, computed from a timestamp
  so it runs while the player is offline. Per-stat rates, an absolute floor, optional peak
  protection, and job exemptions.
- **Passive training.** Sprinting builds stamina and holding your breath underwater builds lung
  capacity, both reported in batches and capped daily.
- **Fifty server exports and their event twins**, covering reading, the allowance and recovery
  bypass, stat changes, buffs and debuffs, training multipliers, decay immunity, training
  blocks, direct effect overrides and exhaustion. Plus client exports and state bags.
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

## [1.0.0] — 2026-08-06

Première version.

### Ajouté

- **Détection automatique du matériel.** Le pool d'objets autour du joueur est comparé à un
  catalogue de 20 exercices répartis sur 94 modèles de props : bancs, haltères, racks à charge
  et à squat, kettlebells, barres de traction et de dips, tapis, sacs de frappe et poires de
  vitesse, tapis de course, vélos d'appartement, rameurs, cordes à sauter, cordes
  ondulatoires, yoga, étirements, presse à cuisses et machines à poulies.
- **`/sportscan` et `/sportspot`.** Aucun catalogue fourni ne peut connaître le contenu d'un MLO
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
- **Le quota d'entraînement.** Un personnage peut gagner 50 points toutes statistiques
  confondues par cycle de 25 heures, et pas plus de 25 dans une seule. Une fois épuisé, il est
  bloqué jusqu'à récupération. Modes de récupération glissant ou par bloc.
- **La whey**, et trois autres consommables. La whey ramène l'attente de 25 heures à 8. Aussi
  une barre protéinée (rembourse du quota), un pre-workout (multiplie les gains) et une boisson
  énergétique (remplit la barre de sprint). Les items sont enregistrés comme utilisables sur
  qb-core, ESX et ox_inventory ; les ajouter à l'inventaire est une étape manuelle documentée.
- **Fatigue.** Le multiplicateur de gain baisse à chaque séance dans une fenêtre de 90 minutes et
  remonte au repos : les trois premières séances d'un après-midi valent plus que les vingt
  suivantes.
- **Perte de niveau.** 10 points par jour sans entraînement, après un jour de grâce, calculée
  depuis un horodatage : elle tourne donc hors ligne. Taux par statistique, plancher absolu,
  protection du record optionnelle, et exemptions par métier.
- **Entraînement passif.** Le sprint travaille l'endurance et l'apnée sous l'eau travaille les
  poumons, tous deux rapportés par lots et plafonnés quotidiennement.
- **Cinquante exports serveur et leurs équivalents en événements**, couvrant la lecture, le
  quota et le contournement de la récupération, les changements de statistiques, les bonus et
  malus, les multiplicateurs d'entraînement, l'immunité à la perte, le blocage de
  l'entraînement, les surcharges d'effet directes et l'épuisement. Plus les exports client et
  les state bags.
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
