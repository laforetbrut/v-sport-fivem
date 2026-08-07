# Security Policy

## Supported versions

Only the latest release receives fixes. Update before reporting.

| Version | Supported |
| ------- | --------- |
| 1.0.x   | Yes       |
| < 1.0   | No        |

## Reporting a vulnerability

**Do not open a public issue for a security problem.** This resource writes to a server's database,
exposes 72 exports that other resources use to change a character, and hands admins commands that
teleport. A public report is an exploit handed to every server running it.

Use GitHub's private reporting instead:
**[Report a vulnerability](https://github.com/laforetbrut/v-sport-fivem/security/advisories/new)**

Please include the version, the framework, what an attacker can do, and the steps. A proof of concept
against your own test server is welcome; do not test against a server you do not own.

You will get a first answer within a few days. A fix ships in the next release, and the advisory is
published once servers have had time to update.

### What counts

- A client event that changes a stat, an allowance or a database row without a server-side check.
- A way to gain more than an honest player could - beyond the known limit below.
- A developer command reachable by a player who is not an admin. `/vsportgoto` and `/vsportprop`
  teleport, and they are gated server-side by `Bridge.isAdmin`; a way past that gate is a real bug.
- Anything a client can send that ends up written to `data/custom.json` or to the database
  unvalidated.
- Reading or changing another player's stats through any export or event.
- A crash or a freeze another player can cause.

### What does not count, and why

**A client can lie about its minigame score.** The minigame runs on the client, so the client knows
the result. No FiveM resource can change that, and reporting it as a vulnerability will get this
paragraph back rather than a fix.

What the server does enforce, and what a report should test against:

- A session must be **authorised**: no token, no payout.
- A token is **single-use and tied to one player**.
- A result that arrives **too quickly** for the reps claimed is rejected.
- A player who **moved away** from the equipment is rejected.
- Cooldowns, the hourly session limit and the 25-hour allowance are all checked server-side.
- Passive training amounts are clamped to what the reporting interval could physically contain.

So the ceiling on cheating is: a cheat gains, at most, what the best possible honest player would
have gained. **The allowance is what bounds the damage** - the cheat and the excellent player hit the
same wall. A report that shows a way past *that* is very much worth filing.

v-sport never kicks and never bans. It fires `vsport:server:CheatSuspected` after five rejections in
an hour and leaves the decision to your anticheat.

---

# Politique de sécurité (français)

## Versions prises en charge

Seule la dernière version reçoit des correctifs. Mettez à jour avant de signaler.

## Signaler une vulnérabilité

**N'ouvrez pas d'issue publique pour un problème de sécurité.** Cette ressource écrit en base de
données, expose 71 exports que d'autres ressources utilisent pour modifier un personnage, et donne
aux admins des commandes qui téléportent. Un signalement public est un exploit offert à tous les
serveurs qui l'utilisent.

Utilisez le signalement privé de GitHub :
**[Signaler une vulnérabilité](https://github.com/laforetbrut/v-sport-fivem/security/advisories/new)**

Indiquez la version, le framework, ce qu'un attaquant peut faire, et les étapes. Une preuve de
concept contre votre propre serveur de test est bienvenue ; ne testez pas contre un serveur qui ne
vous appartient pas.

### Ce qui compte

- Un event client qui modifie une stat, un quota ou une ligne en base sans vérification serveur.
- Un moyen de gagner plus qu'un joueur honnête ne pourrait, au-delà de la limite connue ci-dessous.
- Une commande de développement atteignable par un joueur non admin. `/vsportgoto` et `/vsportprop`
  téléportent et sont protégées côté serveur par `Bridge.isAdmin` ; un contournement est un vrai bug.
- Tout ce qu'un client peut envoyer et qui finit écrit dans `data/custom.json` ou en base sans
  validation.
- Lire ou modifier les stats d'un autre joueur via un export ou un event.
- Un crash ou un gel qu'un autre joueur peut provoquer.

### Ce qui ne compte pas, et pourquoi

**Un client peut mentir sur son score au minijeu.** Le minijeu tourne côté client, donc le client
connaît le résultat. Aucune ressource FiveM ne peut changer ça.

Ce que le serveur impose, et contre quoi un signalement doit être testé : une séance doit être
**autorisée**, un jeton est **à usage unique et nominatif**, un résultat **trop rapide** est rejeté,
un joueur qui **s'est éloigné** est rejeté, et les temps de recharge, la limite horaire et le quota
sont vérifiés côté serveur. Les quantités d'entraînement passif sont bornées à ce que l'intervalle
d'envoi peut physiquement contenir.

Le plafond du triche est donc : un tricheur gagne au mieux ce qu'aurait gagné le meilleur joueur
honnête possible. **C'est le quota qui borne les dégâts** : le tricheur et l'excellent joueur touchent
le même mur. Un signalement qui montre un moyen de passer *ce* mur mérite vraiment d'être posté.

v-sport n'expulse et ne bannit jamais. Il émet `vsport:server:CheatSuspected` après cinq rejets dans
l'heure et laisse la décision à votre anticheat.
