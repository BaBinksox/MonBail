# Les Échos du Néant : architecture de référence

Ce document est la référence de l'architecture **cible** du jeu. Tout script nouveau ou modifié s'y conforme.
Il fixe les noms, les responsabilités, les données et les contrats entre systèmes.
Il ne décrit pas l'état du prototype de départ : l'inventaire réel est dans `docs/AUDIT.md`.

## 0. Principes non négociables

1. **Le serveur décide, le client affiche.** Dégâts, morts, récompenses, XP, rangs, quêtes, missions, déblocages,
   guildes, permissions et états des mécanismes sont calculés par le serveur. Un client ne fait que
   DEMANDER (« j'interagis avec l'objet X », « je pare », « j'accepte la mission Y »). Il n'envoie ni montant,
   ni résultat, ni position faisant foi.
2. **Toute requête client est validée** :
   - type et bornes des paramètres ;
   - existence de l'identifiant dans une configuration serveur ;
   - distance au joueur ;
   - état du joueur (vivant, hors Hub, hors anomalie) ;
   - prérequis, permissions et temps de recharge ;
   - limite de fréquence (`Server/Net/RateLimiter`).
3. **Jamais d'identifiant d'instance arbitraire fourni par le client.** Un client désigne une chose par un
   identifiant de configuration (`InteractableId`, `questId`, `missionId`). Il peut aussi passer un Model que le
   serveur revérifie : tag, distance, appartenance.
4. **Les récompenses sont idempotentes.** Chaque récompense a une clé stable (`quest:bell_silent`,
   `mission:wolves:2026-10-14`...). `RewardService` refuse une clé déjà présente dans `profile.ledger`. La clé et
   la récompense sont écrites dans le même profil, donc sauvegardées ensemble.
5. **Le rembobinage ne touche jamais aux données persistantes.** Il ne restaure que des états de combat :
   position, PV et attribut `CombatState` des entités d'une même rencontre. Une entité morte ne revient jamais
   (le Humanoid mort est irréversible, et `DamageService` marque l'élimination une fois pour toutes).
6. **Aucun identifiant d'asset inventé.** On réutilise les ID déjà présents dans le projet ou des ressources
   officielles Roblox déjà référencées. Ailleurs, on construit en Parts / Terrain / effets natifs. Les sons
   manquants sont des champs `""` documentés (`>>> SON : ...`).
7. **Les configurations sont séparées de la logique.** Pouvoirs, ennemis, rangs, quêtes, missions, guildes,
   secrets et régions sont des tables de données dans `Shared/**/...Config` ou `...Definitions`. Les seuils ne
   sont jamais écrits en dur dans la logique.
8. **Les fonctionnalités existantes restent compatibles.** Les appels existants (`ProfileStore.load/get/
   markDirty/save/release`, `TimeLoopService.openAnomaly/isInAnomaly/isRewinding`, `AvatarService.isCustomizing`,
   Remotes du combat et du Hub) gardent leur signature et leur sens.

## 1. Conventions de code (reprises du prototype)

- `--!strict` en tête. Commentaires et textes affichés en français ; identifiants en anglais.
- Un service serveur est un **singleton** : table module, état local, `Service.start()` idempotent (garde
  `isStarted`), appelé une seule fois par `Server/Main.server.luau` dans l'ordre documenté.
- Les Remotes d'un système sont dans `Shared/<Système>/<Système>Remotes.luau`. Les nouveaux systèmes utilisent
  `Shared/Net/RemoteFolder` : le serveur crée les objets, le client les attend.
- Communication serveur ↔ serveur par **Signal** (`Shared/Util/Signal`), jamais par BindableEvent ou par
  attribut détourné.
- Communication serveur → client de l'état du joueur par **StateSync** (voir §4). Pas de RemoteEvent ad hoc
  par service pour la progression.
- Attributs répliqués : ils servent aux états visibles. Les seuls attributs posés par le serveur sur le Player
  sont `Tension`, `InnateMagic`, `Customizing`, `Region`, `AdventurerRank`, `GuildName`, `GuildRole` et
  `PartyId`. Un client ne peut pas modifier ce que le serveur voit.
- UI : construite par code (ScreenGui créés par les LocalScripts). On utilise des tailles **Scale** avec
  `UISizeConstraint` / `UIAspectRatioConstraint` / `UIScale`, et les styles de `Client/UI/Theme`.

## 2. Carte des services

### Serveur (`ServerScriptService/Server`)

| Dossier | Module | Rôle |
|---|---|---|
| Data | `ProfileStore` (existant, étendu) | verrou de session, sauvegarde, schéma versionné (v2), signaux `ProfileLoaded` / `ProfileReleasing` |
| Data | `ProfileSchema` | type `Profile`, valeurs par défaut, migration v1 → v2, nettoyage des champs |
| Data | `PlayerData` | accès typés au profil chargé (`getProgression`, `getQuests`...), `mutate()` qui marque le profil modifié |
| Net | `RateLimiter` | limite de fréquence par joueur et par action |
| State | `StateSync` | pousse au client des tranches d'état (`progression`, `quests`, `missions`, `inventory`, `guild`, `party`, `discoveries`, `settings`) |
| Progression | `RewardService` | versement idempotent des récompenses (XP, réputation, objets, déblocages, découvertes) |
| Progression | `ProgressionService` | XP, rang d'aventurier, promotions (conditions de `RankConfig`) |
| Combat | `CombatService` (existant) | épée, Tension, ultimes ; ses dégâts passent par `DamageService` |
| Combat | `DamageService` | point unique des dégâts infligés aux ennemis : contributions, élimination unique, signal `EnemyDefeated` |
| Combat | `ParryService` | parade parfaite : fenêtre validée côté serveur, consultée par toute attaque ennemie avant dégâts |
| Enemy | `EnemyService` + `Behaviors/*` | apparition, IA par comportement, télégraphes, réapparition |
| Boss | `BossService` (existant, adapté) | boss d'entraînement et son attaque fatale qui ouvre l'anomalie |
| TimeLoop | `TimeLoopService` (existant, adapté) | sessions de rembobinage **par rencontre** (et personnelles), anomalies arbitrées |
| Encounter | `EncounterService` | rencontres de boss : participants, une seule anomalie à la fois, synchronisation |
| World | `WorldService` (existant) | météo, humeur, présages ; humeur d'anomalie désormais par rencontre |
| World | `SpawnService` | point d'apparition : scène du créateur ou belvédère du village |
| World | `RegionService` | région courante du joueur, portes de région (conditions), découvertes de lieux |
| World | `InteractionService` | ProximityPrompts serveur sur les ancres `Interactable`, validation, répartition vers les gestionnaires |
| World | `MechanismService` | mécanismes à états : pouvoirs (braseros, barrières...), ancres temporelles, portes, puzzle des runes |
| World | `EchoService` | échos temporels (silhouettes qui rejouent un trajet) et suivi « le joueur a vu l'écho » |
| World | `NpcSpawner` | fait apparaître les villageois sur les marqueurs de la carte |
| WorldBuild | `WorldBuilder` + modules | générateur idempotent de la région 1, lancé depuis la Command Bar (ou au démarrage si absent) |
| NPC | `VillagerService` (existant) | promenade et conversation ; s'ouvre aux fonctions (quêtes, missions) |
| Quest | `QuestService` | moteur de quêtes piloté par `QuestDefinitions` |
| Mission | `MissionService` | contrats : cycle disponible → acceptée → terminée → récompensée, rotations |
| Guild | `GuildService`, `GuildStore`, `GuildRules`, `GuildMessaging` | guildes persistantes multiserveurs |
| Party | `PartyService` | groupes sur un même serveur, progression partagée des missions de groupe |

### Partagé (`ReplicatedStorage/Shared`)

`Util/Signal`, `Net/RemoteFolder`, `Input/KeyBindings`, `Progression/RankConfig`, `Progression/ItemConfig`,
`Quest/QuestDefinitions`, `Mission/MissionDefinitions`, `Guild/GuildConfig`, `Party/PartyConfig`,
`Enemy/EnemyDefinitions`, `World/RegionConfig`, `World/MechanismConfig`, `World/EchoConfig`,
ainsi que les modules `*Remotes`.

### Client (`StarterPlayerScripts/Client`)

| Module | Rôle |
|---|---|
| `UI/Theme` | palette, polices, fabriques de cadres et boutons adaptatifs |
| `State/PlayerStateClient` | reçoit StateSync et expose l'état et des signaux aux interfaces |
| `UI/Hud` | suivi de quête, rang, notifications |
| `UI/Grimoire` | menu principal (J) : Carte, Journal, Missions, Progression, Inventaire, Guilde, Groupe, Options |
| `UI/MissionBoardView`, `UI/GuildView`, `UI/PartyView` | panneaux du Grimoire et du tableau de missions |
| `Combat/ParryController` | entrée de parade, effets anticipés |
| `Enemy/EnemyEffectsController` | télégraphes au sol, états visibles des ennemis |
| `World/EchoRenderer`, `World/RegionAmbience`, `World/MechanismEffects` | rendu local des échos, ambiance par région, effets des mécanismes |
| `AvatarCreator/*` (refonte) | créateur de personnage immersif, mêmes Remotes |

## 3. Touches (`Shared/Input/KeyBindings`)

Les touches sont désignées par leur **emplacement physique** (`KeyCode`). L'interface affiche le libellé réel
du clavier via `UserInputService:GetStringForKeyCode`, sauf pour les lettres hors du bloc de déplacement, qui
sont résolues par lettre (`KeyboardLayout`, comme la carte).

| Action | Clavier | Manette | Mobile | Propriétaire |
|---|---|---|---|---|
| Attaque | clic gauche | R2 | bouton | CombatController (existant) |
| Ultime | E | Y | bouton | CombatController (existant) |
| Rembobinage | R | L2 | bouton | TimeLoopController (existant) |
| Dash | Maj gauche | B | bouton | DashController (existant) |
| Carte | lettre « M » | — | bouton du Grimoire | WorldMapController (existant) |
| Interagir / parler | F (ProximityPrompt) | X | toucher l'invite | InteractionService / NPCInteraction |
| **Parade** | KeyCode.Q (« A » en AZERTY) | L1 | bouton | ParryController |
| **Grimoire** | lettre « J » | Select | bouton | Grimoire |

## 4. Données persistantes

### 4.1 Profil joueur, schéma v2 (`ProfileStore`, clé `Player_<UserId>` dans `PlayerProfiles_v4`)

```
{
  version = 2,
  avatar = <inchangé : écrit par AvatarSerializer>,
  progression = { xp = 0, rank = "E", reputation = 0, promotions = { [rankId] = os.time() } },
  quests = {
    active = { [questId] = { stage = 1, progress = { [objectiveId] = n }, startedAt = t } },
    completed = { [questId] = t },
  },
  missions = {
    active = { [missionId] = { progress = n, acceptedAt = t, cycle = "2026-10-14" } },
    completions = { [missionId] = n },
  },
  discoveries = { [discoveryId] = t },
  unlocks = { [unlockId] = t },
  inventory = { [itemId] = count },
  guild = { guildId = "G_..." | nil, joinedAt = t | nil },  -- pointeur ; la vérité est la guilde
  ledger = { [rewardKey] = t },                            -- récompenses déjà versées
  settings = { music = 1, sfx = 1, uiScale = 1, reducedEffects = false },
  stats = { kills = { [enemyId] = n }, deaths = 0 },
}
```

- La migration v1 → v2 ajoute les champs manquants avec leurs valeurs par défaut sans toucher `avatar`.
  `ProfileStore` garde une copie `_backups.v1` avant la migration.
- `PROFILE_FIELDS` liste tous ces champs. Un champ inconnu de l'enregistrement n'est jamais effacé.
- Le ledger ne garde que les récompenses uniques et celles du cycle en cours. Les clés de rotations
  anciennes (> 14 jours) sont élaguées par `RewardService`.

### 4.2 Guildes (`Guilds_v1`, clé `G_<id>`) et index de noms (`GuildNames_v1`, clé = nom normalisé)

```
{
  schema = 1, id = "G_...", name = "...", description = "...", createdAt = t, status = "active" | "dissolved",
  leaderId = userId,
  members = { ["<userId>"] = { role = "leader" | "officer" | "member", joinedAt = t, name = "..." } },
  invites = { ["<userId>"] = { by = userId, expiresAt = t } },
  xp = 0, level = 1,
  contracts = { [contractId] = { cycle = "...", progress = n, completedAt = t|nil, contributors = { ["<userId>"] = n } } },
  unlocks = { [unlockId] = t },
  log = { { t = t, kind = "...", by = userId, target = userId|nil } },  -- 30 derniers événements
  ops = { [opId] = t },                                                -- opérations déjà appliquées (idempotence)
}
```

- Toute écriture passe par `UpdateAsync`, et **les permissions sont revérifiées dans la fonction de transformation**
  avec l'état réellement stocké. Deux officiers qui agissent en même temps sur deux serveurs ne peuvent donc pas
  contourner les règles.
- **Source de vérité de l'appartenance : l'enregistrement de guilde.** `profile.guild` n'est qu'un pointeur.
  Au chargement du profil, puis à chaque relecture de la guilde, le pointeur est réconcilié :
  - si la guilde ne liste plus le joueur, le pointeur est effacé ;
  - si elle le liste mais que le profil l'ignore (opération interrompue), le pointeur est rétabli.
- Les opérations liées profil + guilde suivent un ordre fixe. On écrit d'abord la guilde (opération `opId`
  enregistrée dans `ops`), puis le pointeur du profil. La réconciliation répare toute interruption entre les
  deux. Aucune transaction multi-clés n'est supposée.
- Index des noms : une création réserve d'abord le nom (`UpdateAsync` sur `GuildNames_v1`, refus s'il est pris
  par une autre guilde active), puis crée la guilde. Un nom réservé sans guilde (création interrompue) est
  libéré au bout de 10 minutes.
- La dissolution est une **pierre tombale** (`status = "dissolved"`) et non une suppression. Elle n'est possible
  que pour le chef, seul membre restant, après avoir retapé le nom.
- `MessagingService`, sujet `GuildEvents` : `{ guildId, kind, opId }`. Une notification n'est qu'un signal de
  relecture : le serveur relit la guilde dans le DataStore avant d'agir. Les guildes chargées sont aussi relues
  toutes les 60 s.

### 4.3 Bacs à sable de test

`Shared/Data/DataConfig.luau` porte `USE_TEST_STORES`. Quand il est vrai (vrai par défaut dans Studio), toutes
les nouvelles clés DataStore sont préfixées `TEST_` et les guildes sont écrites dans `TEST_Guilds_v1`. Les profils
de production ne sont ni effacés ni réinitialisés par un test. Aucune commande de réinitialisation n'est
accessible aux joueurs.

## 5. Combat

- `DamageService.dealDamage(target: Model, amount: number, source: DamageSource): number` est le point
  unique des dégâts infligés **aux ennemis** :
  - il refuse une cible invulnérable ou déjà éliminée ;
  - il enregistre la contribution de `source.player` ;
  - quand les PV passent à 0, il marque l'ennemi `Defeated`, une seule fois, et émet
    `EnemyDefeated(enemy, enemyId, contributors)`.
- **Éligibilité aux récompenses d'une élimination** : un joueur doit avoir infligé au moins `ELIGIBLE_SHARE`
  (10 %) des PV max, ou au moins un coup dans les `ASSIST_WINDOW` (15 s) précédant la mort, et être à moins de
  `ELIGIBLE_RANGE` (120 studs) à la mort. Chaque joueur éligible reçoit l'XP complète de l'ennemi
  (coopération encouragée, aucune division punitive).
  - Clé de ledger d'une élimination : `kill:<enemyUid>`. L'uid est unique par apparition, donc une élimination
    ne paie jamais deux fois, même après un rembobinage.
- Les dégâts **reçus** par les joueurs (attaques ennemies) passent par `ParryService.tryParry(player, attacker)`
  avant d'être appliqués. Une parade réussie annule les dégâts, étourdit l'attaquant (`Staggered`) et donne de
  la Tension.
- **Fenêtre de parade** : le client envoie `RequestParry` à l'appui. Le serveur horodate la réception, et la
  parade est valide si l'impact a lieu dans
  `[reception - PING_COMP, reception + PERFECT_WINDOW + PING_COMP]`, avec
  `PING_COMP = min(player:GetNetworkPing(), MAX_PING_COMP)`. Elle a un temps de recharge (pas de spam), et une
  parade ratée laisse le joueur vulnérable un court instant.

## 6. Temps

- `TimeLoopSession` est réutilisé tel quel. `TimeLoopService` gère **plusieurs sessions** :
  - une **session personnelle** par joueur (uniquement son personnage) ;
  - une **session de rencontre** par combat de boss (le boss et ses ennemis, plus les joueurs participants).
- Un joueur appartient à une seule session à la fois. `EncounterService` le fait entrer dans la session d'un boss
  quand il franchit son rayon d'engagement, et le rend à sa session personnelle quand il en sort (jamais pendant
  un rembobinage ou une anomalie).
- Une anomalie concerne une rencontre : un seul joueur ciblé à la fois, tous les participants voient la phase
  rouge, et une demande concurrente est refusée.
  - Le rembobinage d'un participant rembobine **sa rencontre seulement**.
  - L'humeur `Anomaly` du monde devient locale : seuls les participants en voient les effets (attribut
    `EncounterMood` posé sur leur Player).
- Hors rencontre :
  - avec `DEBUG_FREE_REWIND`, R rembobine la session personnelle du joueur ;
  - sinon, R n'agit que près d'une **ancre temporelle** (mécanisme d'exploration).
- **Ancres temporelles** : R près d'une ancre restaure un état passé du monde pour une durée donnée (pont
  détruit reconstruit 15 s). C'est un état serveur partagé, et le joueur garde le contrôle pendant ce temps.
- **Échos** : un écho est une silhouette translucide qui rejoue un trajet (points `EchoPaths/<id>/1..n`) avec
  des actions (s'arrêter, toucher une rune). Le rendu est client ; le serveur sait qui a vu l'écho, car les
  quêtes l'exigent.

## 7. Région 1 et ancres de carte

La géométrie est produite par `WorldBuilder` dans `Workspace.World` :
- `Workspace.World.Static` contient la géométrie statique ;
- `Workspace.World.Anchors` contient les marqueurs.

Les systèmes ne connaissent **aucune coordonnée**. Ils cherchent leurs ancres par tag `WorldAnchor` et par
attribut `AnchorId`. La liste des ancres attendues est dans `Shared/World/RegionConfig.ANCHORS`. Le générateur
doit les créer toutes, et un test vérifie qu'il n'en manque aucune.

Le générateur est idempotent : il détruit puis reconstruit uniquement `Workspace.World` et la zone de terrain
de la région. Le reste du Workspace n'est jamais touché.

## 8. Ordre de démarrage (`Main.server.luau`)

1. `ProfileStore`
2. `StateSync`
3. `RewardService`
4. `ProgressionService`
5. `WorldBuilder.ensureBuilt()` (seulement si `Workspace.World` est absent et si `BUILD_AT_RUNTIME_IF_MISSING`)
6. `WorldService`
7. `RegionService`
8. `SpawnService`
9. `AvatarService`
10. `TimeLoopService`
11. `EncounterService`
12. `MovementService`
13. `DamageService`
14. `ParryService`
15. `CombatService`
16. `BossService`
17. `EnemyService`
18. `NpcSpawner`
19. `VillagerService`
20. `InteractionService`
21. `MechanismService`
22. `EchoService`
23. `QuestService`
24. `MissionService`
25. `PartyService`
26. `GuildService`
