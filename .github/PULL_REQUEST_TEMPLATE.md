<!--
Thanks for contributing. Keep the description short but concrete — what changed, and why.
Merci de contribuer. Gardez la description courte mais concrète — ce qui change, et pourquoi.
-->

## What this changes / Ce que ça change

<!-- One paragraph. / Un paragraphe. -->

## Why / Pourquoi

<!-- The problem it solves. Link the issue: Fixes #123 -->

## How it was tested / Comment ça a été testé

<!--
Say what you actually ran. "It should work" is not a test.
Dites ce que vous avez réellement lancé. « Ça devrait marcher » n'est pas un test.
-->

- Framework tested on / Framework testé :
- `python tools/check.py` passes / passe :
- Steps you ran in game / Étapes jouées en jeu :

## Checklist

- [ ] `python tools/check.py` passes. It parses every Lua file, loads the shared chain in a real
      Lua interpreter, simulates the balance, and asserts the guards. **A change that breaks it will
      not be merged**, and if your change makes an assertion obsolete, change the assertion in the
      same PR and say why. / Il analyse chaque fichier Lua, charge la chaîne partagée dans un vrai
      interpréteur, simule l'équilibrage et vérifie les gardes.
- [ ] If I touched `shared/equipment.lua`, I ran `python tools/props.py` to regenerate `PROPS.md`.
      / Si j'ai touché `shared/equipment.lua`, j'ai régénéré `PROPS.md`.
- [ ] New locale keys are in **both** `locales/en.lua` and `locales/fr.lua`. They must stay
      key-for-key identical, and the check script enforces it. / Les nouvelles clés de locale sont
      dans **les deux** fichiers.
- [ ] New exports are documented in `API.md`. The check script fails otherwise. / Les nouveaux
      exports sont documentés dans `API.md`.
- [ ] New `Config` sections are documented in `CONFIG.md`. The check script fails otherwise. / Les
      nouvelles sections `Config` sont documentées dans `CONFIG.md`.
- [ ] No hardcoded gameplay number. If an operator might want to change it, it belongs in
      `config.lua`. / Aucun nombre de gameplay codé en dur.
- [ ] Comments explain **why**, not what. The code already says what it does. / Les commentaires
      expliquent le **pourquoi**.
- [ ] Documentation is bilingual: English section, then French. / La documentation est bilingue.
- [ ] No personal information anywhere — no email addresses, real names, IDs, keys or endpoints, in
      the code, the comments or the commit message. / Aucune information personnelle nulle part.

## If this is a new prop or exercise / S'il s'agit d'un nouveau prop ou exercice

- [ ] Every model name was checked with `IsModelValid` in game. A name that does not exist hashes to
      a number nothing will ever carry, so it fails silently and forever. / Chaque nom de modèle a
      été vérifié avec `IsModelValid` en jeu.
- [ ] `placeAnim` offsets were **measured** with `/vsportprop`, not guessed, and I said which model
      they were measured against (`tunedAgainst`). / Les offsets ont été **mesurés**, pas devinés.
- [ ] I looked at the animation in game and it matches the equipment. Four exercises are switched
      off in this resource precisely because no shipped clip fits them, and a body doing visibly the
      wrong thing is worse than no option at all. / J'ai regardé l'animation en jeu et elle
      correspond au matériel.

## If this changes balance / Si ça change l'équilibrage

- [ ] I pasted the before and after of the `days to take ALL THREE stats to 100%` block from
      `tools/check.py`. / J'ai collé l'avant/après du bloc de simulation.
