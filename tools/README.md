# Outils du projet « Les Échos du Néant »

Ces outils tournent **hors de Roblox Studio** (Linux, macOS ou Windows avec un terminal Bash). Ils ne
remplacent pas un essai dans Studio : ils attrapent les erreurs de code, d'intégration et de logique
avant d'ouvrir Studio.

## Prérequis

| Outil | Version utilisée | Où le trouver |
|---|---|---|
| Rojo | 7.4.4 | https://github.com/rojo-rbx/rojo/releases (binaire `rojo`) |
| Luau (CLI) | 0.7xx | https://github.com/luau-lang/luau/releases (binaire `luau`) |
| luau-lsp | 1.x | https://github.com/JohnnyMorganz/luau-lsp/releases (binaire `luau-lsp`) |
| Définitions Roblox | — | `globalTypes.d.luau` : https://github.com/JohnnyMorganz/luau-lsp (dossier `scripts/`) |
| Python 3 + matplotlib | 3.10+ | uniquement pour les rendus de la carte (`pip install matplotlib`) |

Les scripts cherchent `rojo`, `luau` et `luau-lsp` dans le `PATH`. On peut aussi les désigner :
`ROJO=/chemin/rojo LUAU=/chemin/luau LUAU_LSP=/chemin/luau-lsp ROBLOX_DEFS=/chemin/globalTypes.d.luau`.

## Commandes

| Commande | Ce qu'elle fait |
|---|---|
| `tools/typecheck.sh` | Vérification de types stricte de `src/` (luau-lsp + définitions Roblox + sourcemap Rojo). Les « Unknown require » des `WaitForChild` côté client sont filtrés : ce ne sont pas des erreurs du jeu. |
| `tools/sim/run_all.sh` | Lance toutes les simulations et affiche leur verdict (voir ci-dessous). |
| `tools/sim/run.sh <test>` | Lance une simulation (`boot_test`, `creator_test`, `quest_test`, `multiplayer_test`, `client_test`, `powers_test`). |
| `tools/sim/map.sh [zone]` | Construit la carte dans la simulation, vérifie le contrat (ancres, interactables, objets dynamiques, trajets d'échos, doublons), l'idempotence, et produit `tools/sim/out/<zone>_top.png` (vue de dessus) et `<zone>_iso.png` (perspective). Zones : `all`, `village`, `forest`, `north`, `crypt` ou `x0,z0,x1,z1`. |
| `tools/export.sh` | Construit `build/Shared.rbxmx`, `build/Server.rbxmx`, `build/Client.rbxmx` (Rojo) à importer dans Studio. |
| `python3 tools/require_graph.py` | Graphe des `require` (détection des cycles de chargement). |

## Les simulations (`tools/sim`)

`mock.luau` + `runtime.luau` imitent l'API Roblox nécessaire au projet : instances, attributs, tags et
leurs signaux, `task` avec un **temps virtuel** (on avance de 60 s en une fraction de seconde),
`Heartbeat` à 30 Hz, DataStore **en mémoire** (avec panne simulable), MessagingService, TextService
(filtre factice), Pathfinding simplifié, joueurs et personnages R15 simplifiés. `client.luau` ajoute un
joueur local (PlayerGui, caméra, remotes client ↔ serveur, touches) pour exécuter les LocalScripts.
`bundle.py` assemble les sources d'après le `sourcemap.json` de Rojo.

| Test | Vérifie |
|---|---|
| `boot_test` | Démarrage complet de `Main.server` : aucun service en échec, ennemis et villageois apparus, invites posées, profil v2 chargé et verrouillé, `BindToClose` qui sauvegarde et libère. |
| `creator_test` | Créateur réel côté client : introduction, étapes au clavier, confirmation unique malgré double clic, sauvegarde, arrivée au belvédère, respawn et reconnexion sans réouverture. |
| `quest_test` | « La Cloche Muette » de bout en bout, puis reconnexion sans perte ni double paiement. |
| `multiplayer_test` | Pouvoirs et ancre temporelle, groupe + contrats partagés, rembobinage pendant un boss à deux, départ pendant une sauvegarde, panne du DataStore, guilde (nom unique, officiers concurrents). |
| `client_test` | Les 14 LocalScripts ensemble ; HUD, Grimoire piloté par ses boutons, parade, télégraphes. |
| `powers_test` | Les six Magies Innées dans le monde, coffres payés une seule fois, retour à l'état initial. |

**Ce que la simulation ne sait pas faire** (à vérifier dans Studio) : physique et collisions réelles
(un passage praticable, une marche franchissable, une chute), rendu, sons et animations, latence
réseau réelle, plusieurs serveurs en même temps (messagerie inter-serveurs des guildes), vrais
DataStores et limites de requêtes Roblox, chargement des assets (IDs).

## Isolation des données

Les DataStores des nouveaux systèmes (guildes, index des noms, messagerie) sont préfixés `TEST_` dans
Studio (`Shared/Data/DataConfig`) : un test ne touche jamais aux guildes de production. Le profil joueur
garde son nom historique `PlayerProfiles_v4` pour ne perdre aucun personnage existant ; la migration v1
→ v2 conserve une copie de l'ancien profil (`_backups.v1`). Aucune simulation n'écrit dans un vrai
DataStore.
