--[[
    locales/fr.lua

    Francais. Doit rester identique cle pour cle a locales/en.lua : toute cle absente d'ici
    retombe sur l'anglais, ce qui donne une interface a moitie traduite plutot qu'une erreur.

    Pas d'accents dans les cles, seulement dans les valeurs.
]]

Locale.register('fr', {

    -- --- Stats -----------------------------------------------------------------------
    ['stat.strength']           = 'Force',
    ['stat.strength_desc']      = 'Degats au corps a corps et resistance aux coups',
    ['stat.breath']             = 'Apnee',
    ['stat.breath_desc']        = 'Temps sous l\'eau et vitesse de nage',
    ['stat.stamina']            = 'Endurance',
    ['stat.stamina_desc']       = 'Vitesse de sprint, recuperation et regeneration',

    -- --- Equipement ------------------------------------------------------------------
    ['equip.bench_press']       = 'Developpe couche',
    ['equip.bench_press_desc']  = 'Du lourd pour les pectoraux. La base de la force.',
    ['equip.free_weights']      = 'Poids libres',
    ['equip.free_weights_desc'] = 'Halteres et barres. Regulier, fiable.',
    ['equip.weight_rack']       = 'Rack a charge',
    ['equip.weight_rack_desc']  = 'Mouvements lourds sous la barre. Dur, mais ca paie.',
    ['equip.kettlebell']        = 'Kettlebells',
    ['equip.kettlebell_desc']   = 'Swings explosifs. Force et souffle en meme temps.',

    ['equip.pull_ups']          = 'Tractions',
    ['equip.pull_ups_desc']     = 'Votre propre poids, encore et encore.',
    ['equip.dip_bars']          = 'Barres paralleles',
    ['equip.dip_bars_desc']     = 'Triceps et epaules aux dips.',
    ['equip.push_ups']          = 'Pompes',
    ['equip.push_ups_desc']     = 'Aucun materiel. Partout ou il y a du sol.',
    ['equip.sit_ups']           = 'Abdominaux',
    ['equip.sit_ups_desc']      = 'Le gainage. Plus de souffle que de muscle.',
    ['equip.muscle_flex']       = 'Poser devant le miroir',
    ['equip.muscle_flex_desc']  = 'Ce n\'est pas vraiment du sport. Mais ca fait du bien.',

    ['equip.punching_bag']      = 'Sac de frappe',
    ['equip.punching_bag_desc'] = 'Des rounds au sac. Puissance, souffle et poumons.',
    ['equip.speed_bag']         = 'Poire de vitesse',
    ['equip.speed_bag_desc']    = 'Rythme et timing. Sans repit.',

    ['equip.treadmill']         = 'Tapis de course',
    ['equip.treadmill_desc']    = 'Du kilometre. La meilleure endurance de la salle.',
    ['equip.exercise_bike']     = 'Velo d\'appartement',
    ['equip.exercise_bike_desc']= 'Sans impact, sur la duree.',
    ['equip.rowing_machine']    = 'Rameur',
    ['equip.rowing_machine_desc']= 'Tout d\'un coup. Jambes, dos, poumons.',
    ['equip.skipping_rope']     = 'Corde a sauter',
    ['equip.skipping_rope_desc']= 'Pieds rapides et respiration courte.',
    ['equip.battle_ropes']      = 'Cordes ondulatoires',
    ['equip.battle_ropes_desc'] = 'Intervalles brutaux. Les bras et les poumons lachent ensemble.',

    ['equip.yoga']              = 'Yoga',
    ['equip.yoga_desc']         = 'Controle du souffle. Rien ne travaille l\'apnee aussi vite a terre.',
    ['equip.stretching']        = 'Etirements',
    ['equip.stretching_desc']   = 'De la recuperation. Doux, et ca compte quand meme.',

    ['equip.leg_press']         = 'Presse a cuisses',
    ['equip.leg_press_desc']    = 'Des jambes chargees. Du lourd sans l\'equilibre.',
    ['equip.cable_machine']     = 'Machine a poulies',
    ['equip.cable_machine_desc']= 'Resistance controlee sur toute l\'amplitude.',

    -- --- Interaction -----------------------------------------------------------------
    ['prompt.key']              = '[%s] %s',
    ['prompt.choose']           = '[%s] %s   ([%s] changer)',
    ['prompt.busy']             = 'Quelqu\'un s\'en sert deja',
    ['prompt.cooldown']         = 'Disponible dans %s',

    -- --- Seance ----------------------------------------------------------------------
    ['session.rep']             = 'REP %d / %d',
    ['session.quality']         = 'FORME',
    ['session.cancel']          = 'Maintenir [%s] pour arreter',
    ['session.perfect']         = 'PARFAIT',
    ['session.good']            = 'BIEN',
    ['session.miss']            = 'RATE',
    ['session.streak']          = 'x%.2f',
    ['session.aborted']         = 'Vous n\'avez pas tenu le rythme',
    ['session.nothing_gained']  = 'Ca n\'etait pas une seance',

    -- --- Notifications ---------------------------------------------------------------
    ['notify.gained']           = '+%.2f %s',
    ['notify.gained_multi']     = 'Seance terminee : %s',
    ['notify.lost']             = '-%.1f %s',
    ['notify.decay_applied']    = 'Vous n\'avez pas mis les pieds a la salle : %s',
    ['notify.milestone']        = '%s atteint %d%%',
    ['notify.maxed']            = '%s est au maximum',
    ['notify.buff_applied']     = '%s %+.1f pendant %s',
    ['notify.buff_expired']     = '%s revient a la normale',
    ['notify.multiplier_applied']= 'Entrainement %s : x%.2f pendant %s',
    ['notify.cooldown']         = 'Il faut souffler. %s',
    ['notify.too_tired']        = 'Vous etes trop fatigue pour que ca serve a grand-chose',
    ['notify.no_permission']    = 'Vous n\'avez pas le droit',
    ['notify.blocked']          = 'Vous ne pouvez pas vous entrainer maintenant',
    ['notify.requirement_stat'] = 'Il vous faut %s a %d%% pour ca',
    ['notify.requirement_job']  = 'Ce n\'est pas pour vous',
    ['notify.requirement_item'] = 'Il vous faut : %s',
    ['notify.not_saved']        = 'Votre progression n\'est pas sauvegardee : aucune base de donnees',

    -- --- Quota d'entrainement --------------------------------------------------------
    ['allowance.blocked']       = 'Votre corps a son compte. Reposez-vous %s.',
    ['allowance.blocked_stat']  = 'Vous ne pouvez plus pousser %s aujourd\'hui',
    ['allowance.restored']      = 'Vous etes remis et pouvez reprendre l\'entrainement',
    ['allowance.remaining']     = '%.0f / %.0f restant',
    ['allowance.resets_in']     = 'Recuperation dans %s',
    ['allowance.reduced']       = 'Temps de recuperation reduit a %s',
    ['panel.allowance']         = 'QUOTA D\'ENTRAINEMENT',

    -- --- Objets ----------------------------------------------------------------------
    ['item.whey_used']          = 'Whey. Votre corps recupere en %s au lieu du delai normal.',
    ['item.protein_used']       = 'Barre proteinee. %.0f de quota recupere.',
    ['item.preworkout_used']    = 'Pre-workout. Gains x%.2f pendant %s.',
    ['item.drink_used']         = 'Boisson energetique. Vous reprenez votre souffle.',
    ['item.cooldown']           = 'Pas tout de suite. Attendez %s.',
    ['item.no_effect']          = 'Ca ne servirait a rien maintenant',

    -- --- Refus -----------------------------------------------------------------------
    ['refuse.in_vehicle']       = 'Pas depuis un vehicule',
    ['refuse.dead']             = 'Pas maintenant',
    ['refuse.cuffed']           = 'Pas avec les mains comme ca',
    ['refuse.swimming']         = 'Pas dans l\'eau',
    ['refuse.combat']           = 'Rangez d\'abord votre arme',
    ['refuse.ragdoll']          = 'Relevez-vous d\'abord',
    ['refuse.falling']          = 'Posez les pieds par terre',
    ['refuse.distance']         = 'Trop loin',
    ['refuse.rate_limit']       = 'Vous vous etes assez entraine pour une heure',

    -- --- Panneau de stats ------------------------------------------------------------
    ['panel.title']             = 'CONDITION PHYSIQUE',
    ['panel.close']             = '[%s] Fermer',
    ['panel.total_sessions']    = 'Seances totales : %d',
    ['panel.next_decay']        = 'Perd %.0f dans %s',
    ['panel.no_decay']          = 'Se maintient',
    ['panel.decay_paused']      = 'Perte en pause',
    ['panel.buffed']            = '%+.1f actif',
    ['panel.effects']           = 'EFFETS ACTUELS',
    ['panel.effect_melee']      = 'Degats au corps a corps',
    ['panel.effect_defense']    = 'Resistance aux coups',
    ['panel.effect_underwater'] = 'Souffle retenu',
    ['panel.effect_swim']       = 'Vitesse de nage',
    ['panel.effect_sprint']     = 'Vitesse de sprint',
    ['panel.effect_regen']      = 'Regeneration de vie',
    ['panel.effect_recovery']   = 'Recuperation d\'endurance',
    ['panel.effect_health']     = 'Vie maximale',
    ['panel.effect_none']       = 'Les stats sont cosmetiques sur ce serveur',
    ['panel.seconds']           = '%.0fs',
    ['panel.percent']           = '%+.0f%%',
    ['panel.fatigue']           = 'Fatigue : gains a %d%%',
    ['panel.rested']            = 'Bien repose',
    ['panel.empty']             = 'Vous ne vous etes jamais entraine',

    -- --- Commandes -------------------------------------------------------------------
    ['cmd.stats']               = 'Afficher votre condition physique',
    ['cmd.info']                = 'Afficher ce que v-sport a detecte',
    ['cmd.scan']                = 'Lister les props de sport autour de vous',
    ['cmd.spot']                = 'Afficher une ligne Config.Spots pour votre position',
    ['cmd.admin']               = 'Definir, ajouter ou reinitialiser l\'entrainement d\'un joueur',
    ['cmd.admin_usage']         = 'Usage : /%s <get|set|add|reset|buff> <id> [stat] [valeur] [secondes]',
    ['cmd.spot_usage']          = 'Usage : /%s <cle d\'equipement>',
    ['cmd.no_player']           = 'Aucun joueur avec cet ID',
    ['cmd.no_stat']             = 'Aucune stat nommee "%s". Connues : %s',
    ['cmd.no_equipment']        = 'Aucun equipement nomme "%s"',
    ['cmd.done']                = 'Fait',
    ['cmd.admin_set']           = '%s : %s vaut maintenant %.2f',
    ['cmd.admin_reset']         = '%s a ete reinitialise',
})
