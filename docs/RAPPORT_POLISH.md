# Les Échos du Néant — Passe de polissage, corrections et extension du gameplay

État du dépôt avant la passe : tag git **`avant-polish-pass`** (commit `f652147`). Rien n'a été
réinitialisé ni supprimé ; chaque étape a son commit (`git log avant-polish-pass..HEAD`).

> **Important — honnêteté des tests.** Je n'ai pas accès à Roblox Studio. Tout ce qui est marqué
> « vérifié » l'a été dans le **simulateur du dépôt** (`tools/sim`, Luau hors Roblox, avec un vrai
> raycast contre les pièces et le relief) et par l'analyse de types (`luau-lsp`). La physique réelle
> du moteur, le rendu, le son et les assets du catalogue **doivent être vérifiés dans Studio** avec la
> procédure de la section 7.

---

## 1. Corrections terminées (P0)

| # | Problème signalé | Cause trouvée | Correction |
|---|---|---|---|
| 1 | Le personnage tombe à travers le sol / se couche pendant la cinématique d'arrivée | Les ancres étaient bonnes (mesurées à 3,00 studs au-dessus du sol réel). Le vrai coupable : `Humanoid.HipHeight` **recalculé de travers** après l'échange de tête classique + `BuildRigFromAttachments`, et un placement fixe « ancre + 3 » sans sonde du sol ni remise à zéro de la vitesse. | Nouveau module `Core/CharacterPlacement` : raycast du sol praticable (CanCollide respecté, personnages/ennemis/PNJ ignorés), hauteur du RootPart **mesurée sur les pieds**, vitesses à zéro, sortie des états couchés (`GettingUp`), `PivotTo` du modèle entier, sans ancrage permanent. HipHeight réparé après la tête classique. Utilisé à l'arrivée, au créateur, au respawn, à la reconnexion — et maintenant aussi pour poser les PNJ. |
| 2 | Créateur : personnage enterré jusqu'au cou | Même HipHeight faux, utilisé par `snapToGround` ; la caméra cadrait les pieds d'après HipHeight. | `snapToGround` et la caméra mesurent les vrais pieds (`LeftFoot`/`RightFoot`). Ordre de fermeture corrigé (placement au belvédère encore figé, puis libération). |
| 3 | Des éléments de la carte projettent le joueur | Audit des scripts : aucune force involontaire sur un joueur qui marche. Audit géométrique (`tools/sim/geometry_audit.luau`) : **45 petites pièces solides inclinées** au ras du sol (rochers, troncs morts) et 1 pièce très fine (sablier) — exactement ce qui éjecte un Humanoid par dépénétration. Les corps des PNJ et des ennemis pouvaient aussi pousser. Les mécanismes (portes, ponts, blocs) pouvaient se refermer sur un joueur. | Décor incliné rendu non solide + **colliders droits invisibles** (`Kit.collider`) ; groupes de collision `Players`/`Npcs`/`Enemies` (`Core/CollisionGroups` : joueurs ↔ PNJ et joueurs ↔ ennemis ne se poussent plus ; **décor, murs et joueurs entre eux restent solides**) ; MechanismService attend qu'aucun joueur ne soit dans la zone avant de fermer/faire apparaître. Audit final : **0 / 0 / 0**. Mode diagnostic Studio : voir §1 bis. |
| 4 | Portes fermées mais fenêtres ouvertes ; barreaux mal construits | Les maisons « intactes » étaient creuses : seule la porte était close. | Intérieurs des maisons fermées bloqués par un volume invisible (`InteriorBlock`), barreaux de fer aux fenêtres (3 verticaux + 1 traverse), portes condamnées par des planches sur les maisons abîmées. Les ruines effondrées restent ouvertes ; chapelle, mausolée et tour vérifiés (entrées voulues et passages secrets intacts). |
| 5 | Objet plat cyan carré/losange sur la place | Le **sceau néon du couvercle du puits** (objet dynamique `WellCover` du mécanisme `well_cover`). | Remplacé par un sceau de pierre gravé (anneau, rainures, cœur teinté). Mécanisme, `DynamicId` et ancres inchangés. Les anneaux temporels au sol (arène, sanctuaire) ne sont plus en néon non plus. |
| 6 | Le Grimoire se ferme quand on clique dedans | `screen.safe` (qui contient le livre) était créé **avant** le fond cliquable, au même ZIndex en mode Sibling : le fond passait **par-dessus le livre**, captait tous les clics… et l'assombrissait de 45 % (c'est aussi la cause du point 7). | Fond en ZIndex 0 sous le livre ; `Theme.bindBackdropDismiss` : ne ferme que pour un clic **commencé et fini hors du livre** (souris ou doigt) ; le fond n'est plus sélectionnable à la manette ; **B** ferme le Grimoire. Même défaut d'empilement corrigé sur l'écran de parade ; le créateur et la carte étaient déjà corrects. |
| 7 | Grimoire trop sombre / transparent, lisibilité | Voir 6, plus des panneaux à 16–42 % de transparence et des gris trop foncés. | Thème commun : panneaux quasi opaques, fonds un peu plus clairs, textes secondaires, désactivés, erreurs et réussites plus contrastés, boutons secondaires plus pleins. Dialogues alignés sur le thème. S'applique au HUD, Grimoire, contrats, dialogues et créateur. |

### 1 bis. Diagnostic des projections (Studio uniquement)

`src/client/World/FlingDiagnostic.client.luau` ne fait **rien en production** (arrêt immédiat hors
Studio). En Studio, pendant un Play, dans la barre de commande :

```lua
workspace:SetAttribute("DebugFling", true)
```

Lorsqu'une vitesse anormale survient **sans** dash, éjection de combat ni ultime (ces poussées passent
par une `LinearVelocity`), la sortie affiche une fois (au plus toutes les 2 s) les pièces solides qui
touchent le personnage : chemin complet, position, taille, ancrage, attributs et `DynamicId` du
modèle parent. `false` pour l'arrêter.

---

## 2. Nouvelles fonctionnalités

### Lumière (P1)
- **Cycle de 38 min réelles : 28 min de jour, 10 min de nuit**, réglé à un seul endroit
  (`WorldConfig` : `DAY_REAL_SECONDS`, `NIGHT_REAL_SECONDS`). L'heure reste continue et partagée
  (horloge du serveur) ; le soleil avance simplement plus vite la nuit.
- **Nuit au clair de lune** jouable : ambiantes, exposition et brouillard relevés dans
  `LightingPresets.NIGHT`, sans lampe ajoutée. Aucune correction cumulée d'une image à l'autre
  (le préréglage est recalculé à neuf à chaque mise à jour — vérifié par test).

### Audio (P1)
- `Shared/Audio/AudioConfig` : **toute** la musique au même endroit (pistes par contexte et par
  région, variantes de nuit, régions futures elfe/naine, chœur, petits sons de retour).
- `MusicDirector` : **une seule musique à la fois**, fondus croisés, priorité du créateur sur la
  région, la piste en cours n'est jamais relancée (changer de page ou retraverser une frontière).
- `MusicController` : musique de la région publiée par le serveur, délai anti-oscillation de 2 s.
- `AudioMixer` : groupes **Musique / Ambiance / Effets** pilotés par les réglages du joueur.
- **Chœur du rembobinage** : court (3 s max), volume modéré, fondus, jamais deux à la fois, joué
  uniquement sur l'événement serveur `RewindStarted`, coupé par le réglage « Effets ».
- L'ancienne musique du créateur (comptine d'horreur `rbxassetid://1839911004`) est **retirée**.
  **Aucun ID n'a été inventé** : les pistes attendent un choix vérifié (section 5).

### Créateur de personnage (P1)
- **Peuples** (`Shared/Avatar/RaceConfig`) — étape « Origine » en premier :

  | Peuple | Avantage | Inconvénient | Identité visuelle | Origine |
  |---|---|---|---|---|
  | Humain | +10 % de Tension par coup | +5 % de dégâts reçus | — | Village des Cendres (**disponible**) |
  | Elfe | +8 % de vitesse | −10 % de vie max | plus grand, plus fin, **oreilles effilées** | Forêts d'Ellendor (*à venir*) |
  | Nain | +15 % de vie max | −7 % de vitesse | plus petit, plus large | Monts de Brasegrise (*à venir*) |
  | Enfant de l'Ombre | −12 % de dégâts la nuit | +6 % de dégâts le jour | **voile d'ombre** discret | Marches d'Ombre (*à venir*) |

  Effets appliqués **côté serveur** (`Server/Avatar/RaceService` : vie, vitesse, dégâts, Tension),
  sans cumul au respawn, conservés à la reconnexion. Les origines non construites sont
  **marquées indisponibles** et le joueur commence au Belvédère (le texte le dit) ; un point
  d'arrivée introuvable retombe toujours sur `spawn_village`. Aucun continent vide n'a été créé.
- **Teint** : 12 options (dont 2 surnaturelles), appliquées à la tête **et** à tout le corps visible ;
  « Teint de votre avatar » garde le teint Roblox (c'est celui des personnages existants).
- **Éclairage du visage** : lumières de studio éloignées (4,5 studs mini — elles collaient au visage
  en plan serré), clé moins forte et de côté (elle dessine le relief des cicatrices), étalonnage
  moins délavé ; sur peau foncée, la marque reçoit un peu de lumière propre pour rester lisible.
- **Roulette du Destin** : bouton « Laisser le destin choisir » → confirmation explicite → la roue
  tourne, ralentit et s'arrête **sur le verdict du serveur**. Le **serveur** tire (chances égales),
  enregistre tout de suite (`creation.destinyRoll`), renvoie toujours le même verdict (demandes
  rapprochées, reconnexion, nouvel essai) et **scelle** la magie à la validation. Gratuite, règles
  affichées. Ne pas tourner la roue = choisir librement.
- **Cartes de pouvoir** : chaque magie affiche son point fort et son point faible (`MagicConfig`).
- **Profil v3** : migration **non destructive** (peuple « humain » et teint « natif » pour les
  personnages existants, champ `creation`) ; copie complète conservée dans `_backups.v2`. Un
  serveur plus ancien ouvre un profil v3 en lecture seule (il ne l'écrase jamais).

### PNJ (P1)
- `Server/NPC/NpcCostume` : détails médiévaux sculptés en pièces simples (tablier de forge, robe
  d'archiviste, robe d'ancienne, armure + cape de garde, cape de voyage, besace d'herboriste,
  écharpe de marchand, étole de guilde, châle, ceinture, tenue de deuil). Proportionnés au corps,
  **sans collision, sans masse, invisibles aux raycasts**. Configurés par PNJ dans `NpcConfig`
  (`look.details`), avec un visage dessiné du catalogue (`look.face`). PNJ posés sur le sol réel.

### Options (P2) — Grimoire (J) > onglet **Options**
Musique, Ambiance, Effets sonores, Taille de l'interface, **Effets réduits**. Aperçu immédiat,
enregistrement automatique, restauration à la connexion. Effets réduits : secousses à 30 %,
particules d'ambiance à 35 %, bloom et rayons atténués, glitch moins fréquent, voiles d'ombre
masqués, lueurs des mécanismes adoucies.

### Finitions d'immersion
- Nom et devise de la région en fondu à l'entrée d'une zone (jamais pendant le créateur ou
  l'arrivée, une fois toutes les 2 min par région).
- Secrets annoncés sobrement (« Un secret se dévoile… »).
- Quand un mécanisme répond : lueur douce à cet endroit + carillon (si un son est fourni).

---

## 3. Partiel ou non fait (et pourquoi)

- **Vent et Lumière** (pouvoirs optionnels) : **non ajoutés.** La consigne exigeait une intégration
  complète (créateur, sauvegarde, ultime serveur, VFX, avantages, mécanismes du monde, récompenses) ;
  je ne l'ai pas commencée pour ne pas livrer une moitié de pouvoir. Les 6 pouvoirs sont conservés.
- **Tenues médiévales** : je n'ai **ajouté aucun ID** (impossible de vérifier un asset sans Studio).
  Fait : champ `style` sur les tenues, et `AvatarConfig.OUTFIT_WISHLIST` liste les 11 familles à
  pourvoir (vagabond, aventurier, mage, noble, chevalier, garde, guérisseur/érudit, manteau de
  voyage, elfique, naine, ombre). Ajouter une tenue = une ligne.
- **Musiques, chœur, sons de retour** : emplacements **vides** + critères (section 5). Le jeu est
  silencieux là où rien n'est choisi, sans erreur.
- **Origines elfe / naine / ombre** : marquées indisponibles (aucune zone construite). Prévu :
  renseigner `startAnchorId` le jour où la région existe.
- **Ambiances d'intérieur** (son/lumière différents dans les maisons) : non faites.
- **Physique, rendu, éclairage du visage, oreilles et costumes** : vérifiés en simulation
  (positions, collisions, absence d'erreur), **pas visuellement** : à contrôler dans Studio.

---

## 4. Fichiers créés et modifiés (`git diff --name-status avant-polish-pass..HEAD`)

**Créés**
```
src/client/Audio/AudioMixer.luau
src/client/Audio/MusicController.client.luau
src/client/Audio/MusicDirector.luau
src/client/State/ClientSettings.luau
src/client/UI/SettingsController.client.luau
src/client/World/FlingDiagnostic.client.luau
src/client/World/WorldFeedback.client.luau
src/server/Avatar/RaceService.luau
src/server/Core/CharacterPlacement.luau
src/server/Core/CollisionGroups.luau
src/server/NPC/NpcCostume.luau
src/shared/Audio/AudioConfig.luau
src/shared/Avatar/RaceConfig.luau
tools/sim/audio_test.luau  tools/sim/daynight_test.luau  tools/sim/geometry_audit.luau
tools/sim/placement_test.luau  tools/sim/race_test.luau
docs/RAPPORT_POLISH.md
```

**Modifiés**
```
src/client/AvatarCreator/AvatarCreatorCamera.luau        src/server/Avatar/AvatarAppearance.luau
src/client/AvatarCreator/AvatarCreatorCatalog.luau       src/server/Avatar/AvatarSerializer.luau
src/client/AvatarCreator/AvatarCreatorController.client.luau  src/server/Avatar/AvatarService.luau
src/client/AvatarCreator/AvatarCreatorView.luau          src/server/Combat/CombatService.luau
src/client/Combat/CombatEffects.luau                     src/server/Combat/DamageService.luau
src/client/Combat/ParryController.client.luau            src/server/Data/ProfileSchema.luau
src/client/NPC/DialogueView.luau                         src/server/Data/ProfileStore.luau
src/client/NPC/NPCInteraction.client.luau                src/server/Main.server.luau
src/client/TimeLoop/GlitchOverlay.luau                   src/server/NPC/NpcSpawner.luau
src/client/TimeLoop/TimeLoopAudio.luau                   src/server/State/StateSync.luau
src/client/UI/Grimoire.client.luau                       src/server/World/MechanismService.luau
src/client/UI/HudController.client.luau                  src/server/World/SpawnService.luau
src/client/UI/Theme.luau                                 src/server/WorldBuild/Kit.luau
src/client/UI/UIBus.luau                                 src/server/WorldBuild/Overlook.luau
src/client/World/AmbientParticles.luau                   src/server/WorldBuild/Palette.luau
src/client/World/ArrivalController.client.luau           src/server/WorldBuild/PropsBuildings.luau
src/client/World/LightingPresets.luau                    src/server/WorldBuild/PropsNature.luau
src/client/World/WorldAtmosphere.client.luau             src/server/WorldBuild/PropsSacred.luau
src/shared/Avatar/AvatarConfig.luau                      src/server/WorldBuild/Training.luau
src/shared/Avatar/AvatarRemotes.luau                     src/server/WorldBuild/Village.luau
src/shared/Magic/MagicConfig.luau                        src/server/WorldBuild/WorldBuildConfig.luau
src/shared/NPC/NpcConfig.luau                            src/shared/State/StateRemotes.luau
src/shared/TimeLoop/TimeLoopConfig.luau                  src/shared/World/WorldConfig.luau
src/shared/World/WorldRemotes.luau
tools/sim/boot_test.luau  tools/sim/client.luau  tools/sim/client_test.luau  tools/sim/creator_test.luau
tools/sim/helpers.luau  tools/sim/run_all.sh  tools/sim/runtime.luau
```

---

## 5. ID à renseigner (aucun n'a été inventé)

Tous dans **`src/shared/Audio/AudioConfig.luau`** (format `"rbxassetid://123456"`, `""` = silence).
Pour chacun : Toolbox > Audio, filtrer par durée et genre, puis **écouter en Play** — une piste
visible dans la Toolbox peut être privée ou bloquée pour l'expérience.

| Champ | Ce qu'il faut chercher |
|---|---|
| `TRACKS.creator` | Thème principal : piano solo ou piano + cordes, lent, mélancolique et lumineux, chœur féminin très discret ; 2–4 min, boucle propre. **Pas** l'opening d'une œuvre existante ni une imitation proche. |
| `TRACKS.overlook` | Harpe ou piano clair, sentiment d'arrivée. |
| `TRACKS.village` / `village_night` | Luth, flûte, harpe, cordes douces / piano lent, cordes en sourdine. |
| `TRACKS.forest` / `forest_night` | Cordes et bois, mystère doux / nappe aérienne, harpe espacée. |
| `TRACKS.crypt` | Nappe grave, chœur lointain, cloches feutrées ; tension mesurée. |
| `TRACKS.lake` | Piano cristallin, célesta, cordes froides (pas de comptine). |
| `TRACKS.elf_village`, `TRACKS.dwarf_halls` | Pour les régions futures. |
| `REWIND_CHOIR.id` | « Choir Aah female », « Angelic choir short », « Soprano choir swell » : 2–5 s, sans paroles. (L'ancien chœur sombre `rbxassetid://9125602726` peut y être remis si vous le préférez.) |
| `FEEDBACK_SOUNDS.mechanism` / `.secret` / `.regionEnter` | Sons courts et doux (0,5–2 s) : carillon, petit glissando de harpe, souffle léger. |

Autres emplacements existants (inchangés) : `WorldConfig.WIND_SOUND_ID`, `Theme` (sons
d'interface), et les tenues (`AvatarConfig.OUTFIT_OPTIONS` + `OUTFIT_WISHLIST`).

---

## 6. Tests réellement exécutés (simulateur `tools/sim`, hors Roblox)

`tools/typecheck.sh` : **0 erreur** (2 avertissements anciens : `ApplyDescription` déprécié,
fonction inutilisée dans Overlook). `tools/sim/run_all.sh` : **10 suites, 293 vérifications, 0 échec**.

| Suite | Vérifications | Ce qui est couvert (nouveau en gras) |
|---|---|---|
| boot_test | 16 | démarrage complet, profil **v3**, **PNJ habillés, costumes sans collision** |
| creator_test | 36 | créateur au clavier, **étape Origine, Roulette (confirmation, une seule demande, verdict serveur, carte scellée refusée, magie publiée = verdict)**, arrivée, respawn, reconnexion |
| quest_test | 35 | quête de la cloche de bout en bout |
| multiplayer_test | 54 | groupes, contrats, guildes, boss à plusieurs |
| client_test | 42 | tous les LocalScripts, HUD, contrats, guilde, **clics dans le livre (souris, toucher, glisser, manette, onglet) qui ne ferment pas, clic hors du livre qui ferme, onglet Options (volume enregistré et appliqué, effets réduits)** |
| powers_test | 22 | les 6 pouvoirs et leurs mécanismes |
| placement_test | 27 | **ancres à 3,00 studs du sol réel, pieds à ±0,05 au créateur / arrivée / respawn / reconnexion, HipHeight −1,2 réparé à 2,0** |
| daynight_test | 9 | **cycle 38 min, jour ≥ 2× nuit, heure continue, nuit ≥ 70 % de la lumière extérieure du jour, pas de cumul** |
| audio_test | 19 | **une seule musique audible, pas de relance, créateur → région, piste vide = silence, volumes enregistrés et appliqués, chœur sans doublon et court** |
| race_test | 33 | **migration v2 → v3 sans perte (+ `_backups`), nain/elfe/ombre (vie, vitesse, dégâts), sans cumul au respawn, reconnexion, oreilles, voile, arrivée de repli, roulette stable (rafales, reconnexion), magie scellée, 100 tirages couvrant les 6 magies** |

Hors suite : `tools/sim/geometry_audit.luau` → **AUDIT OK** (0 pièce non ancrée, 0 petite pièce
solide inclinée, 0 pièce fine au sol, sur 1 339 pièces solides) ; `tools/sim/map.sh all` →
**CONTRAT OK**, idempotence OK (8 603 → 8 603 descendants).

**Non testé** (impossible sans Studio) : physique réelle du moteur, rendu, sons, chargement des
assets du catalogue, réseau réel entre plusieurs machines.

---

## 7. Synchroniser avec Roblox Studio

**Avant tout : enregistrez une copie de votre place.** Pour les tests, utilisez une **place de
test séparée** (copie privée) : ses DataStores sont distincts de ceux de la production. La migration
v3 ne supprime rien (copie dans `_backups`), mais un profil passé en v3 ne doit pas être rouvert par
un serveur de production plus ancien (il le lirait en lecture seule).

*Option A — Rojo (recommandée)* : `rojo serve default.project.json`, puis connecter le plugin.

*Option B — fichiers `.rbxmx`* (dans `build/`) : supprimez (ou renommez en `_old`) les dossiers
`Shared`, `Server` et `Client`, puis clic droit > **Insérer à partir du fichier** :
`Shared.rbxmx` → **ReplicatedStorage**, `Server.rbxmx` → **ServerScriptService**,
`Client.rbxmx` → **StarterPlayer > StarterPlayerScripts**.

**Reconstruire la carte** (le générateur a changé, `BUILD_VERSION` passe à **3**) :
- automatique : au démarrage, `WorldBuilder.ensureBuilt()` reconstruit `Workspace.World` s'il porte
  une version inférieure à 3 ;
- ou manuellement (pour l'enregistrer dans la place) : barre de commande
  `require(game.ServerScriptService.Server.WorldBuild.WorldBuilder).build()` — aucune ligne
  « Contrat incomplet » ne doit apparaître — puis Fichier > Enregistrer.

Rappels : Paramètres du jeu > Sécurité > **Accès de Studio aux services API** (sauvegardes) ;
Lighting > Technology = **Future**.

---

## 8. Vérifications à faire dans Studio, puis en multijoueur

**Solo (Play)** — chaque point correspond à un défaut signalé :
1. Nouveau personnage : au créateur, **corps entier visible**, pieds sur la plateforme ; plans corps,
   visage, destin corrects.
2. Teints clair / moyen / foncé × aucune marque / cicatrice / tatouage : marque lisible, visage pas
   brûlé.
3. Valider : à l'arrivée au belvédère, **debout**, pas de chute ni de position couchée.
4. Marcher partout (rochers, troncs, place, chemins, autour des PNJ et des ennemis) : **aucune
   projection**. En cas de doute : `workspace:SetAttribute("DebugFling", true)`.
5. Maisons : fenêtres barrées, pas d'entrée par les fenêtres ; entrées voulues et passages secrets
   toujours praticables. Plus de losange cyan sur la place (sceau de pierre sur le puits).
6. Grimoire (J) : cliquer sur les textes, les cartes, les onglets, Accepter / Abandonner / Rendre,
   Compagnons : **il ne se ferme pas** ; un clic sur le fond sombre ou ✕ (ou B) le ferme. Texte
   lisible.
7. Laisser passer une journée : le jour dure nettement plus que la nuit ; la nuit, le relief reste lisible.
8. Musique : jamais deux pistes en même temps (une fois des ID renseignés) ; R : chœur bref.
9. Options : changer les volumes, la taille d'interface, les effets réduits ; quitter, revenir :
   tout est restauré.

**Multijoueur** (Test > Clients et serveurs > serveur local, 2–3 joueurs) :
1. Créer un **elfe**, un **nain** et un **Enfant de l'Ombre** : oreilles, proportions et voile
   visibles par les autres joueurs ; vitesse / vie différentes.
2. Joueur 1 : tourner la Roulette ; fermer le client avant de valider, revenir : **même verdict**,
   cartes verrouillées ; valider : la magie est celle de la roue.
3. Joueurs côte à côte et au contact des PNJ / ennemis : personne n'est poussé ni projeté ; les
   joueurs restent solides entre eux.
4. Contrats en groupe : accepter, combattre, rendre (second « Rendre » refusé) ; Grimoire ouvert
   pendant ce temps : les clics ne le ferment pas.
5. Un joueur active un mécanisme (runes du puits, braseros…) : lueur visible chez les joueurs
   proches ; un mécanisme ne se referme pas sur un joueur qui s'y tient.
6. Arrêter puis relancer le serveur : peuples, teints, magies, options, progression conservés.
7. Ancien profil (créé avant cette passe) : il revient **humain**, même teint, même apparence,
   même pouvoir ; le créateur ne se rouvre pas.

---

## 9. Sources consultées

La documentation officielle de Roblox était inaccessible depuis l'environnement (échec DNS) ; le
diagnostic HipHeight s'appuie sur ces discussions du DevForum :
- https://devforum.roblox.com/t/hip-height-refusing-to-change/1404480
- https://devforum.roblox.com/t/improvements-to-humanoid-scaling/128642
- https://devforum.roblox.com/t/a-little-help-on-resizing-humanoids/295227
- Référence : https://create.roblox.com/docs/reference/engine/classes/Humanoid
