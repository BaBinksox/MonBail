# Audit du prototype (état réel au 14-15/10/2026)

Ce document est généré à partir de l'audit approfondi des sources. Cinq analystes indépendants ont lu chaque fichier en entier. Les données brutes complètes sont dans `docs/audit_raw.json`.

Il décrit le prototype **avant** les évolutions « Les Échos du Néant ». L'architecture cible est dans `docs/ARCHITECTURE.md`.

## Synthèse

- **54 scripts, environ 9 700 lignes**, tous câblés par `Server/Main.server.luau` et par les LocalScripts. Aucun doublon de module.
- **ProfileStore** : la version présente dans ce dépôt est la version verrouillée (`UpdateAsync` + verrou de session, sauvegarde automatique, `BindToClose`). La version présente dans **l'export Studio du 14/10** est l'**ancienne** (214 lignes, `GetAsync`/`SetAsync`, sans verrou). Les deux utilisent le même `STORE_NAME` (`PlayerProfiles_v4`) et le même format `{ version = 1, avatar }` : elles sont compatibles.
- **Pouvoirs** : exactement 5 (`antimatter`, `pyromancy`, `lightning`, `ice`, `shadow`). Aucun 6e pouvoir n'existe dans le code, les sauvegardes ou l'historique : **Gravité est ajouté**.
- **L'introduction** (3 phrases + musique `rbxassetid://1839911004`) est dans `Client/AvatarCreator/AvatarCreatorController`.
- **Partiels ou provisoires** :
  - les assets d'`AvatarConfig` sont des placeholders signalés par le code ;
  - les ultimes partagent une seule chorégraphie visuelle teintée par la palette ;
  - le son du vent est vide ;
  - l'attribut `CombatState` n'est jamais écrit ;
  - le boss doit être posé à la main (tag `Boss`) et ne réapparaît pas.
- **Débogage actif** : `TimeLoopConfig.DEBUG_FREE_REWIND = true` (R utilisable hors anomalie) ; `DEBUG_LOGS = true` dans CombatConfig, MovementConfig, TimeLoopConfig, WorldMapConfig et BossConfig.
- **Export Studio du 14/10** : trois scripts ont des espaces finaux dans leur nom (`WorldMapView   `, `NPCInteraction `, `BossEffectsController   `). `WorldMapController` attend donc indéfiniment `WorldMapView`, et la carte ne s'ouvre pas. Le module `KeyboardLayout` est absent de cet export.

## Risques majeurs relevés (et traitement prévu)

| Risque | Traitement |
|---|---|
| Le rembobinage réécrit la santé d'un Humanoid déjà mort : un ennemi « mort » redevient frappable, d'où doubles éliminations | `EntitySnapshot` n'écrit plus la santé d'un mort ; `DamageService` marque l'élimination une fois pour toutes ; clés de récompense `kill:<uid>` |
| Rembobinage **global** : un joueur rembobine tous les joueurs et PNJ du serveur ; glitch sur tous les écrans | Sessions par rencontre + sessions personnelles (`EncounterService`) ; Remotes envoyés aux seuls membres de la session |
| Farm de Tension et d'ultimes avec le rembobinage libre (PV du boss restaurés, Tension conservée) | Dans une rencontre, le rembobinage n'est permis que pendant l'anomalie ; le rembobinage libre de test ne touche que le joueur lui-même |
| Conflits d'ancrage entre Hub, anomalie, rembobinage et charge du boss (chacun mémorise son propre `wasAnchored`) | Ancrage compté par raison (`AnchorService`) |
| Issue de l'anomalie devinée par polling dans BossService | Signal `AnomalyResolved(player, outcome)` |
| Dialogues 100 % client : aucun crochet de quête possible | Le serveur fournit les dialogues contextuels (quêtes, missions) ; repli sur DialogueConfig |
| La hitbox client signale tout Humanoid (villageois compris) et joue l'impact avant validation | Filtre des cibles valides côté client |
| Ultime : cibles figées et invulnérables incluses, brûlure non attribuée | Dégâts via `DamageService` avec revérification ; lanceur passé aux comportements |
| `PlayerRemoving` et `ProfileStore.load` ne sont appelés que par AvatarService | Conservé (compatibilité), complété par les signaux `ProfileLoaded` / `ProfileReleasing` |

## Création de personnage, introduction, sauvegarde

Périmètre « création de personnage + introduction » : 11 fichiers lus en entier, tous RÉELLEMENT câblés. Main.server.luau démarre ProfileStore puis AvatarService. AvatarService fait load() du profil. Si profile.avatar existe, il réapplique l'apparence et publie l'attribut "InnateMagic". Sinon (nouveau joueur), il ancre le HumanoidRootPart à l'endroit où le personnage apparaît (il n'existe pas de lieu « Hub » dédié ni de téléportation) et envoie OpenCreator. L'INTRODUCTION NARRATIVE + MUSIQUE se trouve entièrement dans src/client/AvatarCreator/AvatarCreatorController.client.luau : INTRO_LINES (3 phrases, l.34-38), playIntro() (l.223-230), open() (l.232-274). La musique vient de AvatarConfig.HUB_MUSIC_ID = "rbxassetid://1839911004" (« Nursery Crime 60 », APM), volume 0.4 ; Sound "HubMusic" créé par le client dans SoundService, fondu d'entrée 2.5 s, de sortie 1.5 s. Ambiance : ColorCorrection + DepthOfField dans Lighting. Déroulé : voile noir, 3 phrases (environ 7.5 s), puis 3 s pendant lesquelles le voile se lève et la caméra avance de 17 à 9.5 studs ; le panneau apparaît, interactif après environ 10.3 s. CATÉGORIES (page ÉVEIL, 7 sélecteurs « < valeur > ») : CORPS (2 : man/woman, sert de genre), VISAGE (5), CICATRICES ET TATOUAGES (7 dont "none" : 5 cicatrices + 1 tatouage "curse_seal"), CHEVELURE (22), TENUE (3, chemise + pantalon + cape), TAILLE (0.90→1.15, pas de 0.05 : 6 crans), CARRURE (0.75→1.10 : 8 crans). Page DESTIN : 5 magies. Pas de couleur de peau (héritée de l'avatar Roblox), pas de couleur de cheveux ni de profondeur. APERÇU : calculé CÔTÉ SERVEUR à chaque clic (PreviewAvatar), donc répliqué à tous les joueurs. File d'attente : une seule application à la fois, seule la dernière demande compte. Le serveur part de humanoid:GetAppliedDescription(), modifie la HumanoidDescription et appelle ApplyDescription, puis remplace la tête par une tête classique (ReplaceBodyPartR15) qui reçoit un Decal "face" et la marque (SurfaceGui sur un Part "FaceCanvas"). Rig R15 supposé, mais jamais imposé par le code (réglage de la place). CAMÉRA : Scriptable, BindToRenderStep à Camera+1, FOV 40, recalculée à chaque frame devant le HumanoidRootPart, décalée de 2.2 studs pour laisser le panneau à droite, légère respiration ; aucune rotation ni zoom possible. VALIDATION (ApplyAvatar) : sanitizeSelection, publication de la magie, profile.avatar = toSaved() (des ids, pas des index), markDirty, puis save() lancé en tâche de fond (UpdateAsync avec verrou de session). Ensuite l'apparence est appliquée et CreatorClosed est envoyé. MagicConfig contient exactement 5 magies : "antimatter", "pyromancy", "lightning", "ice", "shadow". AUCUN 6e pouvoir Gravité n'existe, ni dans src, ni dans backups (.luau et .rbxmx), ni dans l'historique git (1 seul commit). Le seul « gravité » est un commentaire de DashController l.107 sans rapport. Pièges principaux : (1) ProfileStore.applyRecord() ne recopie que version et avatar ; un champ ajouté à PROFILE_FIELDS sans toucher applyRecord serait écrasé par sa valeur par défaut à la première sauvegarde. (2) Un rewind TimeLoop peut se croiser avec l'ancrage du Hub, et le rewind reste autorisé depuis le Hub (DEBUG_FREE_REWIND=true). Les fichiers du périmètre sont identiques à backups/studio-export-2026-10-14, sauf ProfileStore (le backup est une ancienne version de 214 lignes sans verrou ; même STORE_NAME "PlayerProfiles_v4" et même PROFILE_VERSION 1, donc compatible).

### Fichiers

| Fichier | Rôle |
|---|---|
| `src/shared/Avatar/AvatarConfig.luau` | Catalogue partagé client/serveur du créateur : types d'options, listes d'options (le client envoie des INDEX, la sauvegarde stocke les `id`), plages de taille et de largeur, nom de l'attribut du Hub, musique du Hub, drapeau de debug, dimensions du panneau des marques. Tous les assets sont marqués comme PLACEHOLDERS (l.16). |
| `src/shared/Avatar/AvatarRemotes.luau` | Point d'accès unique aux 4 RemoteEvents du créateur. Au premier require côté serveur, il crée ReplicatedStorage.AvatarRemotes (Folder) et ses RemoteEvents ; côté client, il les attend avec WaitForChild. |
| `src/shared/Magic/MagicConfig.luau` | Catalogue des Magies Innées (une par joueur, choisie dans la page DESTIN). Chaque magie définit son ultime (touche E) : nom, rayon, dégâts et palette. Elle est publiée par le serveur dans l'attribut Player "InnateMagic" (id). |
| `src/server/Avatar/AvatarService.luau` | Façade du Hub côté serveur. Elle charge le profil à la connexion et choisit entre réappliquer un personnage sauvegardé ou ouvrir le Hub. Elle gèle le personnage (ancrage du HumanoidRootPart, recalage au sol), reçoit les Remotes Preview/Apply, gère une file d'application (une seule à la fois, seule la dernière demande compte), publie la magie (attribut), écrit profile.avatar puis sauvegarde, ferme le Hub et libère le  |
| `src/server/Avatar/AvatarAppearance.luau` | Applique une Selection sur un personnage, en 3 étapes. (1) HumanoidDescription construite à partir de GetAppliedDescription(), ce qui conserve la couleur de peau et les autres réglages de l'avatar Roblox : SetAccessories({}, true), GraphicTShirt=0, 5 parties du corps, Head=0, Face=0, HairAccessory, BackAccessory, Shirt, Pants, HeightScale, WidthScale, puis ApplyDescription dans un pcall. (2) Remplacement de la tête p |
| `src/server/Avatar/AvatarSerializer.luau` | Validation des données envoyées par le client : index entiers compris dans les bornes, échelles numériques non NaN ramenées dans leur plage. Conversion Selection (index) <-> sauvegarde (id) ; un id introuvable retombe sur l'option 1. |
| `src/server/Data/ProfileStore.luau` | Sauvegarde DataStore "PlayerProfiles_v4", clé "Player_<UserId>". Profil en mémoire : { version, avatar }. Verrou de session "_session" vérifié dans chaque UpdateAsync ; modes lecture seule (loadFailed / locked / newerVersion / corrupt / lockLost / closing) ; migrations de schéma avec copie dans "_backups" ; sauvegarde automatique toutes les 60 s (renouvelle le verrou) ; écritures sérialisées par joueur ; BindToClose  |
| `src/server/Main.server.luau` | Unique point d'entrée serveur. Il fait require des 8 services et les démarre dans cet ordre : ProfileStore, WorldService, AvatarService, TimeLoopService, MovementService, CombatService, BossService, VillagerService. Aucune protection pcall : une erreur dans un start() bloque les services suivants. |
| `src/client/AvatarCreator/AvatarCreatorController.client.luau` | Chef d'orchestre côté client. Il construit la vue au chargement, crée le Sound "HubMusic", tient l'état local `selection`, et joue l'INTRODUCTION : voile noir, 3 phrases, travelling caméra, musique, ambiance. Il relie les flèches des sélecteurs (avec envoi d'un PreviewAvatar à chaque clic), gère les pages ÉVEIL et DESTIN, envoie ApplyAvatar et referme tout à la réception de CreatorClosed. Il ne modifie jamais le pers |
| `src/client/AvatarCreator/AvatarCreatorView.luau` | Construit en code le ScreenGui "AvatarCreatorGui" (DisplayOrder 50, IgnoreGuiInset, ResetOnSpawn=false, désactivé au départ). Panel (CanvasGroup, 34 % de largeur, à droite) avec Shade (dégradé) et Content (UIScale = min(1, hauteur/640)). AppearancePage contient le titre "É V E I L", 7 sélecteurs (Base "CORPS", Face "VISAGE", Mark "CICATRICES ET TATOUAGES", Hair "CHEVELURE", Outfit "TENUE", Height "TAILLE", Width "CAR |
| `src/client/AvatarCreator/AvatarCreatorCamera.luau` | Caméra Scriptable du créateur, recalculée à chaque frame (BindToRenderStep "AvatarCreatorCamera", priorité Camera+1) à partir du HumanoidRootPart. Elle se place devant le personnage (côté LookVector), le décale vers la gauche de l'écran (SIDE_OFFSET 2.2), ajoute une respiration verticale et un travelling avant (Quart Out). Elle reprend CameraType=Scriptable si les scripts par défaut le changent, et restaure le FOV pu |

### Remotes

| Nom | Sens | Charge | Validation serveur |
|---|---|---|---|
| `OpenCreator` | serveur -> 1 client (FireClient dans AvatarService.openCreator l.119) | aucun. Le client repart toujours des index 1 et des échelles par défaut ; le choix sauvegardé n'est pas transmis | sans objet (émis par le serveur). Envoyé à chaque apparition d'un personnage tant que state.isCustomizing est vrai (nouveau joueur ou mort pendant la création). Si le Hub est déjà ouvert, le client renvoie simplement un  |
| `PreviewAvatar` | client -> serveur (FireServer dans AvatarCreatorController.sendPreview l.147 : à l'ouverture et à chaque clic de flèche) | selection: Selection { baseIndex, faceIndex, markIndex, hairIndex, outfitIndex, heightScale, widthScale, magicIndex } | AvatarService.onPreviewRequested l.164. AvatarSerializer.sanitizeSelection : table obligatoire, index entiers dans [1, #liste] (#MagicConfig.MAGICS pour la magie), échelles numériques non NaN ramenées dans leur plage, sa |
| `ApplyAvatar` | client -> serveur (bouton Confirm, AvatarCreatorController l.390) | selection: Selection (même forme) | AvatarService.onApplyRequested l.176 : mêmes contrôles que PreviewAvatar. Utilisable une seule fois : isConfirmPending passe à true, puis isCustomizing à false à la fermeture. Effets : savedSelection, publishMagic (attri |
| `CreatorClosed` | serveur -> 1 client (AvatarService.closeCreator l.127) | aucun | sans objet. Envoyé quand la file d'application est vide après la confirmation, même si ApplyDescription a échoué (pour ne jamais enfermer le joueur dans le Hub) |

### Actif / partiel / mort

- ACTIF — Parcours complet : Main.server.luau démarre ProfileStore puis AvatarService ; onPlayerAdded fait load(). Avec un profil : publishMagic + réapplication à chaque apparition (onCharacterReady). Sans profil : openCreator -> OpenCreator -> intro client -> PreviewAvatar en direct -> ApplyAvatar -> sauvegarde -> CreatorClosed.
- ACTIF — Intro narrative : AvatarCreatorController l.32-41 (INTRO_ENABLED = true, 3 lignes : « Le froid. Puis le silence. » / « Vous êtes mort... et pourtant, vos yeux s'ouvrent. » / « Avant que le temps ne reprenne son cours, souvenez-vous de qui vous étiez. »), playIntro l.223-230, open() l.232-274. Ordre : voile opaque + CoreGui masqué + ambiance + Camera.start + musique + premier aperçu ; 3 × (0.7 + 1.3 + 0.5 s) ; puis dollyIn(3) avec le voile qui se lève en 3 s ; après 1.8 s, le panneau apparaît en 1 s. Aucun autre script d'intro ou de cinématique dans src.
- ACTIF — Musique : Sound "HubMusic" (client, SoundService), Looped, fondu d'entrée de 0 à 0.4 en 2.5 s, fondu de sortie en 1.5 s puis Stop si le Hub n'a pas été rouvert entre-temps.
- ACTIF — 7 catégories de la page ÉVEIL + 5 magies de la page DESTIN, validées côté serveur, sauvegardées par id.
- ACTIF — Les 4 Remotes ; les attributs IsCustomizing et InnateMagic (lus par Combat, World, NPC) ; AvatarService.isCustomizing (Boss, Movement, Combat).
- ACTIF — ProfileStore : verrou de session, sauvegarde automatique 60 s, release au départ, BindToClose.
- PARTIEL / PROVISOIRE — Tous les assets d'AvatarConfig sont des placeholders (l.16) ; les 6 marques ont un placement par défaut (0,0,1,0) non réglé ; curse_seal est à remplacer (fan art).
- PARTIEL — MIGRATIONS = {} (exemple commenté seulement) ; BACKUP_FIELD "_backups" n'est utilisé que pendant une migration, donc inactif tant que PROFILE_VERSION = 1.
- PARTIEL — Ultimes : côté client, CombatEffects.ULTIMATE_PLAYERS = {} (l.500), donc les 5 magies jouent la même chorégraphie playEruption, distinguées par palette et rayon. Côté serveur, UltimateBehaviors.BEHAVIORS donne 5 effets distincts (antimatter : aspiration, pyromancy : brûlure, lightning : paralysie, ice : ralentissement, shadow : drain).
- MORT / INUTILISÉ — Valeur de retour de AvatarAppearance.apply ignorée (AvatarService l.146) ; Stepper.counterLabel jamais rempli pour TAILLE et CARRURE ; type SavedAvatar non utilisé hors du module ; ScaleRange.step utilisé seulement côté client (le serveur n'arrondit pas au pas).
- DEBUG — AvatarConfig.DEBUG_ALWAYS_OPEN_CREATOR = false ; INTRO_ENABLED = true (constante locale du controller, pas dans la config).
- ABSENT — Pouvoir Gravité / 6e magie : introuvable dans src, backups/*.luau, backups/*.rbxmx et l'historique git (1 seul commit 7cda454). « gravité » n'apparaît que dans un commentaire de DashController l.107, sans rapport.
- ABSENT — Couleur de peau (héritée de l'avatar Roblox via GetAppliedDescription), couleur des cheveux ou des yeux, profondeur, échelle de la tête, catégorie tatouages séparée des cicatrices, nom du personnage, vignettes, récapitulatif, rotation ou zoom de la caméra, support manette, adaptations mobiles, réouverture ou modification d'un personnage existant (pas de Remote, openCreator est local), changement de magie.
- BACKUPS — backups/studio-export-2026-10-14 : les 10 autres fichiers du périmètre sont identiques à src ; seul ProfileStore diffère (ancienne version de 214 lignes, sans _session ni migrations, même STORE_NAME et même PROFILE_VERSION).

### Risques et bugs

- CONFIRMÉ, perte de données — ProfileStore.applyRecord() (l.290-293) ne recopie que `version` et `avatar`. Or la procédure documentée (l.9 : « l'ajouter au type Profile, à newProfile() et à PROFILE_FIELDS ») oublie applyRecord. Si l'on ajoute `progression` à PROFILE_FIELDS et à newProfile() seulement, le chargement ignore record.progression, le profil garde la valeur par défaut, et la sauvegarde suivante (writeSession, qui recopie chaque champ de PROFILE_FIELDS) écrase la vraie donnée dans le DataStore.
- PLAUSIBLE — Croisement rewind TimeLoop / gel du Hub. TimeLoopSession.freeze mémorise wasAnchored = true pour un joueur figé dans le Hub ; si le Hub se ferme pendant le rewind, AvatarService.unfreeze met Anchored à false, puis TimeLoopSession.unfreeze le remet à true : le joueur reste ancré après la création, jusqu'à sa réapparition. Inversement, un personnage qui apparaît pendant un rewind est désancré par TimeLoopSession.unfreeze (wasAnchored = false par défaut) alors qu'il est dans le Hub ; le gel repose uniquement sur l'ancrage, sans WalkSpeed à 0, donc il peut marcher. Aggravant : TimeLoopConfig.DEBUG_FREE_REWIND = true, et ni TimeLoopService.canRewind ni TimeLoopController (touche R) ne vérifient IsCustomizing : un joueur dans le Hub peut déclencher un rewind global.
- PLAUSIBLE — Mort ou Reset (le menu Échap reste accessible) pendant la confirmation. processApplyQueue applique la sélection à l'ancien personnage ; le nouveau déclenche openCreator ; la file se vide (pendingSelection = nil), puis closeCreator libère le nouveau personnage SANS lui appliquer l'apparence, qui ne reviendra qu'à la réapparition suivante.
- Incohérence — Pendant ProfileStore.load (jusqu'à LOCK_WAIT_TIME = 30 s si le profil est verrouillé), l'attribut IsCustomizing vaut true (interfaces masquées), mais AvatarService.isCustomizing() renvoie false et le personnage n'est pas figé : combat, dash et ciblage par le boss restent possibles, avec l'avatar Roblox complet visible.
- ApplyDescription est tout ou rien : un seul asset invalide, retiré ou modéré (vêtements classiques de tiers, coiffures) fait échouer toute l'apparence (warn l.279). Le look précédent est conservé ; seuls le visage et la marque sont posés. Le Hub se ferme malgré tout à la confirmation.
- GetAppliedDescription() conserve, depuis l'avatar Roblox du joueur, la couleur de peau, BodyTypeScale, ProportionScale, DepthScale, HeadScale et les packs d'animation : l'apparence finale varie d'un joueur à l'autre, et aucune option de peau n'existe dans l'UI.
- Client — Si le serveur ignore ApplyAvatar (rejet de validation, état incohérent), le bouton reste sur ". . ." avec isInteractive = false, sans délai d'expiration ni nouvel essai : le joueur est bloqué.
- Client — close() appelle SetCoreGuiEnabled(All, true) sans tenir compte de l'état antérieur ; open() remet toujours la sélection à 1 (OpenCreator n'a pas de payload), donc en mode DEBUG_ALWAYS_OPEN_CREATOR le joueur ne revoit pas son personnage sauvegardé.
- R15 non imposé par le code (voir workspaceExpectations) : en R6, ni visage, ni marque, ni recalage au sol, sans aucun avertissement.
- Validation — sanitizeScale ramène dans la plage sans arrondir au pas (un client modifié peut envoyer 0.913) ; effet purement cosmétique. PreviewAvatar n'a pas de limite de fréquence, mais la file fusionne les demandes (une application à la fois, uniquement pendant le Hub).
- Profil en lecture seule (Studio sans accès API, DataStore en panne) : le Hub se rouvre à chaque connexion et rien n'est sauvegardé, sans aucun message au joueur. En mode "locked", un profil modifié (isDirty) ne retente jamais de prendre le verrou (retryAcquire sort si isDirty) ; un profil verrouillé d'ancienne version est appliqué sans migration.
- Mobile — Panneau à 34 % de la largeur, UIScale calculé sur la hauteur seule (référence 640 px). Sur un téléphone en paysage de 390 px de haut, échelle 0.61 : les flèches de 34 px font environ 21 px, sous la taille tactile recommandée. bindHover ne réagit qu'à la souris. Aucune navigation manette (ni GuiService.SelectedObject, ni NextSelection*, ni ContextActionService). IgnoreGuiInset = true.
- Mise en page — La page ÉVEIL occupe 584 px sur les 640 de référence (7 sélecteurs de 52 px, espacement de 10). Un 8e sélecteur (+62 px) donne 646 px, au-delà du CanvasGroup qui découpe : toute nouvelle catégorie impose des onglets ou un défilement. La page DESTIN avec 6 magies tiendrait (environ 610 px).
- Couplage — ProfileStore.load et release ne sont appelés QUE par AvatarService (onPlayerAdded / onPlayerRemoving) : le cycle de vie des données dépend du module avatar. Main.server.luau n'a pas de pcall : une erreur dans un start() empêche les services suivants de démarrer.
- Aperçu calculé côté serveur : chaque clic coûte un ApplyDescription au serveur, avec latence réseau et chargement d'assets, et le résultat est visible par tous les joueurs proches du point d'apparition.

### Identifiants d'assets

- src/shared/Avatar/AvatarConfig.luau:225 — HUB_MUSIC_ID "rbxassetid://1839911004" : musique du Hub et de l'intro (« Nursery Crime 60 », APM sous licence Roblox). PROVISOIRE (marqué « >>> » / Placeholder). Alternatives en commentaire l.224 : 1837786350 « Music Box Of Death 30 », 1840004224 « Twinkle (a 30) ».
- src/shared/Avatar/AvatarConfig.luau:104-108 — base "man" (bundle Roblox « Man ») : torso 86500008, rightArm 86500036, leftArm 86500054, leftLeg 86500064, rightLeg 86500078. Placeholder (l.16).
- src/shared/Avatar/AvatarConfig.luau:113-117 — base "woman" (bundle « Woman ») : torso 86499666, rightArm 86499698, leftArm 86499716, leftLeg 86499753, rightLeg 86499793. Placeholder.
- src/shared/Avatar/AvatarConfig.luau:122-126 — visages, via image() en rbxassetid : stoic 83017053 (texture « Man Face »), serene 83022608 (« Woman Face »), defiant 7074780 (« Check It »), detached 7074749 (« Chill »), freckles 12145059 (« Freckles »). Placeholders.
- src/shared/Avatar/AvatarConfig.luau:154-158 — marques, via decalThumbnail() en rbxthumb 420x420, decals gratuits de la série « [FACE] Extras » de morscore : scar_eye 3524093836, scar_slash 3524095179, scar_cheek 3524096392, scar_cross 3524097066, scar_claw 3524097803. Placeholders, toutes avec offset (0,0), scale 1, rotation 0 : aucune position réglée.
- src/shared/Avatar/AvatarConfig.luau:160 — curse_seal 16324571137 (decalThumbnail) : tatouage dessiné par un fan, inspiré d'un manga. Explicitement « à remplacer avant de publier » (risque de propriété intellectuelle).
- src/shared/Avatar/AvatarConfig.luau:165-186 — 22 coiffures (accessoires Hair) : pal 63690008, spiked 376524487, brown 62234425, bun 62724852, ninja_updo 2907260402, princess 13477162, azure 164482409, long_pale 727320877, vagabond 65941324, duelist 30332157, bed_head 20372960, dragon_heir 2804642677, abyss 4041570918, specter 1425141074, crimson 259423003, cinnamon 13745548, ember 77359955, eccentric 61885694, azure_fringe 293316132, hazel_fringe 323476364, librarian 319642720, bat_queen 1074737868. Placeholders du catalogue.
- src/shared/Avatar/AvatarConfig.luau:193-195 — tenue midnight_traveler : shirt 3267725621, pants 3267727546, back 878915975 « Cape of Midnight's Wisdom ». Placeholder.
- src/shared/Avatar/AvatarConfig.luau:200-202 — tenue black_iron_knight : shirt 8991866831, pants 8991863926, back 2163546691 « Black Iron Cape ». Placeholder.
- src/shared/Avatar/AvatarConfig.luau:207-209 — tenue oathbreaker : shirt 560184638, pants 560182503, back 1772350677 « Sinister Cape ». Placeholder. Les vêtements classiques de créateurs tiers peuvent être retirés ou modérés, ce qui ferait échouer tout l'ApplyDescription.
- Aucun autre asset dans les fichiers du périmètre : View et Camera n'en utilisent pas (polices Enum.Font.Garamond / GothamMedium), et MagicConfig ne contient que des couleurs.

### Ce que le code attend dans la scène

- Aucun modèle, tag ou position codée en dur n'est requis par ce périmètre. Le « Hub » n'est PAS un lieu : le personnage est figé (HumanoidRootPart.Anchored = true) là où il apparaît (SpawnLocation), et les autres joueurs le voient changer d'apparence en direct.
- Le sol doit se trouver à moins de 50 studs sous le HumanoidRootPart (GROUND_RAY_LENGTH, raycast qui exclut le personnage) pour que snapToGround recale les pieds après un changement de taille. Sinon groundY = nil et aucun recalage n'a lieu.
- L'orientation de la SpawnLocation détermine le cadrage : la caméra se place devant le personnage, côté LookVector, à 9.5 studs et 1 stud au-dessus. Le décor visible en arrière-plan est donc ce qui se trouve derrière le personnage, flouté par le DepthOfField (FocusDistance 10, InFocusRadius 5, FarIntensity 0.8).
- Avatars R15 OBLIGATOIRES, réglés dans la place (Game Settings > Avatar) ; le Rojo default.project.json ne définit aucune propriété de StarterPlayer. Avec un rig R6 : pas de tête classique, donc ni visage ni marque (ensureClassicHead renvoie nil), pas de recalage au sol, et pas d'épée (CombatService exige RightHand).
- Le chargement de l'apparence Roblox doit être actif, car le Hub s'ouvre sur Player.CharacterAppearanceLoaded (ou sur HasAppearanceLoaded()).
- DataStore "PlayerProfiles_v4" : jeu publié et « Enable Studio Access to API Services » coché. Sinon le profil est vide en lecture seule et le Hub se rouvre à chaque connexion.
- Le client ajoute 2 effets dans Lighting et 1 Sound dans SoundService ; aucun effet n'est prévu dans la scène.

## Combat et mouvement

Périmètre audité intégralement (16 fichiers, 2701 lignes, racine /home/user/RobloxRPG). Les fichiers sont identiques à backups/studio-export-2026-10-14 (diff vide). Tout ce périmètre est câblé : Main.server.luau L21 MovementService.start() puis L22 CombatService.start() ; les LocalScripts CombatController et DashController tournent seuls.

FLUX D'UNE ATTAQUE À L'ÉPÉE
1) Entrée (CombatController L289-299). UserInputService.InputBegan, MouseButton1, sans gameProcessed, appelle onAttackInput (L167). Un clic pendant un coup est mémorisé (hasBufferedInput). getReadyCharacter (L65) exige : Humanoid, RootPart, enfant "Sword", Health > 0 et RootPart non ancré. Le coup suivant vient de getNextComboIndex (L115) : il passe à +1 si le dernier coup est fini depuis 0,5 s au plus, sinon il repart au coup 1.
2) performAttack (L144, YIELD) enchaîne : soft-lock (SoftLock.findTarget rayon 15, puis face, puis AutoRotate=false), Remotes.RequestAttack:FireServer(comboIndex), SwingAnimator.play, task.wait(hitStart), traînée de lame (CombatEffects.playBladeTrail), puis SpatialHitbox:start(hitEnd-hitStart, HITBOX_SIZE + (0,0,reachBonus), onHitboxHit).
3) Hitbox CLIENT (SpatialHitbox). À chaque Heartbeat, GetPartBoundsInBox sur une boîte 6x6x6 posée devant le RootPart. Chaque pièce remonte au premier Model ancêtre qui a un Humanoid. Ce personnage compte s'il est vivant, pas déjà touché pendant cette activation et sans décor CanCollide entre les deux (raycast). Pour chacun, onHitboxHit (L104) joue tout de suite CombatEffects.playSwordHit (impact, hit-stop 0,05 s, secousse) puis appelle Remotes.ReportHit:FireServer(target).
4) Validation SERVEUR.
   - onAttackRequested (L163) : comboIndex est un nombre et COMBO[comboIndex] existe ; personnage vivant ; joueur pas hors combat (isOutOfCombat = AvatarService.isCustomizing, TimeLoopService.isInAnomaly ou TimeLoopService.isRewinding) ; isComboStepAllowed (L145). Le serveur stocke ensuite attacks[player] = {comboIndex, startClock = os.clock(), hitTargets = {}} et envoie AttackStarted aux AUTRES clients.
   - onHitReported (L276) : target est un Model ; un attack existe ; l'attaquant est vivant et en combat ; elapsed est dans [hitStart-0.25, hitEnd+0.25] ; la cible n'est ni l'attaquant ni déjà dans hitTargets, et elle est vivante.
   - isTargetAllowed (L206) : la cible n'a pas l'attribut Invulnerable. Si c'est un joueur, il faut PVP_ENABLED, qu'il soit en combat et que MovementService.isDashing soit faux. Sinon il faut le tag CollectionService "TimeLoopEntity".
   - isInRange (L227) : distance entre RootParts, moins le rayon tiré de GetExtentsSize, au plus getMaxHitDistance (≈ 9,71 studs pour les coups 1-2 et ≈ 12,01 pour le coup 3).
   - hasLineOfSight (L235) : raycast serveur. L'orientation de l'attaquant n'est PAS vérifiée (choix assumé, L16-18).
5) Effets d'un coup validé (L318-324) : hitTargets[target] = true ; targetHumanoid:TakeDamage(step.damage) ; applyKnockback si knockback > 0 (seul le coup 3 : LinearVelocity "KnockbackVelocity" à 55 studs/s plus une montée de 14, pendant 0,2 s, ignorée si le RootPart est ancré) ; setTension(+20) ; Remotes.HitConfirmed:FireAllClients(attacker, target, damage). Côté client, HitConfirmed ne sert qu'aux VFX : l'attaquant local est ignoré car il a déjà joué l'effet.

CIBLES
Le jeu identifie une cible par son Humanoid ET par un tag. Le client prend tout Model qui a un Humanoid. Le serveur exige pour un PNJ le tag "TimeLoopEntity" (BossService.registerBoss L367 le pose automatiquement sur les Models taggés "Boss"), et pour un joueur que le PvP soit actif.

TENSION
C'est l'attribut Player "Tension" (number), écrit uniquement par CombatService.setTension (L94, clamp 0..100). Elle gagne +20 par coup d'épée validé, rien d'autre. Elle retombe à 0 à PlayerAdded, à chaque CharacterAdded (mort) et quand l'ultime part. Elle n'est ni sauvegardée, ni rembobinée, et ne baisse pas avec le temps. Le client la lit via GetAttributeChangedSignal pour remplir la jauge (TensionView).

ULTIMES
Touche E (onUltimateInput L212) : si la Tension locale est à 100 et le personnage prêt, le client envoie RequestUltimate. Le serveur (onUltimateRequested L349, YIELD) vérifie que le lanceur est vivant, en combat et à Tension ≥ 100. Il remet la Tension à 0 AVANT tout le reste. La magie vient de MagicConfig.getById(player:GetAttribute("InnateMagic")), écrite par AvatarService ; une valeur inconnue donne "antimatter". Les cibles sont calculées par findUltimateTargets : uniquement des Models taggés TimeLoopEntity, vivants, dont le centre est à moins de magic.radius. Pas de PvP, pas de ligne de vue. Le serveur envoie UltimateFired à tous, attend 0,2 s, abandonne si un rewind est en cours, puis inflige TakeDamage(magic.damage) aux cibles non invulnérables (damageDealt cumulé). Enfin il lance task.spawn(UltimateBehaviors.run). Effets propres à chaque magie :
   - antimatter (rayon 30, 60 dégâts) : PullVelocity à 45 studs/s pendant 0,3 s vers l'origine, pour les cibles à plus de 5 studs.
   - pyromancy (26, 70) : 5 ticks de 6 dégâts toutes les 1 s.
   - lightning (34, 50) : WalkSpeed à 0 pendant 1,5 s.
   - ice (30, 55) : WalkSpeed x0,35 pendant 5 s.
   - shadow (24, 80) : le lanceur récupère 40 % de damageDealt.
Côté client, les 5 ultimes jouent la même chorégraphie playEruption, teintée par la palette de la magie : ULTIMATE_PLAYERS est vide.

DASH / ESQUIVE
LeftShift déclenche DashController.onDashInput : cooldown local de 2 s, puis RequestDash, puis une LinearVelocity en mode Plane à 85 studs/s pendant 0,18 s, posée par le client, plus la traînée. Le serveur (MovementService.onDashRequested) vérifie canAct et un cooldown de 2 - 0,25 s, enregistre lastDashClock et envoie DashStarted aux autres clients. Les i-frames sont : MovementService.isDashing(player) vrai pendant 0,3 s après l'acceptation serveur. Seuls deux endroits les consultent : CombatService.isTargetAllowed (épée PvP) et BossService.performAttack L208. Le déplacement lui-même n'est jamais vérifié.

DÉGÂTS, KILL, ATTAQUANT
Qui applique des dégâts :
   - CombatService L319 (épée) et L385 (ultime) ;
   - UltimateBehaviors L136 (brûlure) et L166 (soin du drain) ;
   - BossService L213 (boss vers joueur) ;
   - TimeLoopService L68 (Health = 0 quand l'anomalie expire) ;
   - EntitySnapshot L59 (Health réécrit pendant un rewind).
AUCUNE détection de kill : pas de Humanoid.Died, pas de tag "creator", pas de table de contributeurs. La seule notion d'attaquant est éphémère : attacks[player].hitTargets (une touche par coup), le payload attacker de HitConfirmed et Context.casterHumanoid (pour le drain). BossService remarque la mort de son boss uniquement par la boucle runBoss (L285 while isAlive), puis pose BossState = "Dead".

### Fichiers

| Fichier | Rôle |
|---|---|
| `/home/user/RobloxRPG/src/shared/Combat/CombatConfig.luau` | Constantes du combat : combo à l'épée (dégâts, timings, allonge, knockback, animations), hitbox, soft-lock, knockback, noms des instances de l'épée, validation serveur (latence, PvP, attribut d'invulnérabilité), Tension et ultime. |
| `/home/user/RobloxRPG/src/shared/Combat/CombatRemotes.luau` | Point d'accès unique aux 6 RemoteEvents du combat. Au premier require, le serveur crée le dossier ReplicatedStorage.CombatRemotes et les RemoteEvents ; le client les attend par WaitForChild. |
| `/home/user/RobloxRPG/src/shared/Combat/SpatialHitbox.luau` | Zone de frappe spatiale : une boîte devant le RootPart, interrogée par workspace:GetPartBoundsInBox à chaque Heartbeat pendant une durée donnée. Chaque personnage (Model + Humanoid) vivant et non masqué par le décor n'est signalé qu'une fois par activation. Elle ne sert en pratique que côté client. |
| `/home/user/RobloxRPG/src/server/Combat/CombatService.luau` | Autorité du combat. Équipe l'épée à chaque spawn. Valide RequestAttack (état du joueur, combo) et ReportHit (fenêtre de frappe, cible autorisée, portée, ligne de vue, une touche par coup). Applique les dégâts d'épée et le knockback. Tient la Tension. Valide et exécute l'ultime : dégâts de zone puis UltimateBehaviors. |
| `/home/user/RobloxRPG/src/server/Combat/SwordFactory.luau` | Fabrique l'épée : clone de ServerStorage.Assets.Sword s'il est valide (PrimaryPart, BladeStart, BladeEnd), sinon une épée provisoire en Parts soudées par Weld. Ajoute un Trail "BladeTrail" éteint. Rend toutes les pièces non collidables, CanQuery/CanTouch false et Massless. La fixe dans la main par un Motor6D "SwordGrip". |
| `/home/user/RobloxRPG/src/server/Combat/UltimateBehaviors.luau` | Effets secondaires serveur des 5 ultimes, appliqués après les dégâts de zone communs, rangés dans la table BEHAVIORS par id de magie. |
| `/home/user/RobloxRPG/src/shared/Magic/MagicConfig.luau` | Catalogue des 5 Magies Innées : id sauvegardé, noms, description, rayon et dégâts de l'ultime, palette. Nom de l'attribut Player qui porte la magie choisie. |
| `/home/user/RobloxRPG/src/client/Combat/CombatController.client.luau` | Chef d'orchestre client : entrée clic gauche (combo avec mémoire d'un clic), soft-lock, animation, traînée, hitbox locale, envoi de RequestAttack et ReportHit ; touche E (RequestUltimate) ; jauge de Tension ; réactions VFX à AttackStarted, HitConfirmed et UltimateFired. |
| `/home/user/RobloxRPG/src/client/Combat/CombatEffects.luau` | VFX purement locaux, sans aucun effet sur le jeu : traînée de lame, impact (Highlight + étincelles), hit-stop (AdjustSpeed(0) sur les AnimationTracks), secousse de caméra (BindToRenderStep "CombatCameraShake"), ColorCorrection, coup de FOV, chorégraphie de l'ultime. |
| `/home/user/RobloxRPG/src/client/Combat/SoftLock.luau` | Visée assistée : trouve l'ennemi vivant le plus proche (PNJ taggés TimeLoopEntity, plus les autres joueurs si PVP_ENABLED) et tourne le RootPart vers lui, à plat. |
| `/home/user/RobloxRPG/src/client/Combat/SwingAnimator.luau` | Charge et met en cache, par Animator, les pistes d'animation des coups (Priority Action, non bouclées), puis les joue avec fondu et vitesse issus de la config. |
| `/home/user/RobloxRPG/src/client/Combat/TensionView.luau` | Construit par code le ScreenGui "TensionGui" (Container > Prompt, Caption "TENSION", Bar > Fill + UIGradient, UIStroke) et en expose les références. |
| `/home/user/RobloxRPG/src/shared/Movement/MovementConfig.luau` | Constantes du dash. |
| `/home/user/RobloxRPG/src/shared/Movement/MovementRemotes.luau` | Le serveur crée le dossier ReplicatedStorage.MovementRemotes et ses 2 RemoteEvents ; le client les attend. |
| `/home/user/RobloxRPG/src/server/Movement/MovementService.luau` | Valide chaque dash annoncé (joueur en état d'agir, cooldown), prévient les autres clients pour la traînée et accorde une invulnérabilité de 0,3 s, consultée par les sources de dégâts via isDashing. |
| `/home/user/RobloxRPG/src/client/Movement/DashController.client.luau` | Sur LeftShift : cooldown local, propulsion par LinearVelocity en mode Plane sur le HumanoidRootPart (le client simule son propre personnage), RequestDash au serveur, traînée locale. Joue aussi la traînée des dashs des autres joueurs (DashStarted). |

### Remotes

| Nom | Sens | Charge | Validation serveur |
|---|---|---|---|
| `RequestAttack` | client -> serveur (CombatController.performAttack L149) | (comboIndex: number) | CombatService.onAttackRequested L163 : type(comboIndex) == "number" et Config.COMBO[comboIndex] ~= nil ; personnage vivant (getLivingParts) ; pas isOutOfCombat (isCustomizing, isInAnomaly, isRewinding) ; isComboStepAllow |
| `ReportHit` | client -> serveur (CombatController.onHitboxHit L107) | (target: Model) | CombatService.onHitReported L276 : typeof Instance et IsA("Model") ; attacks[player] existe ; attaquant vivant et pas hors combat ; elapsed dans [hitStart - 0.25, hitEnd + 0.25] ; target ~= attaquant ; pas déjà dans hitT |
| `RequestUltimate` | client -> serveur (CombatController.onUltimateInput L216) | () | CombatService.onUltimateRequested L349 : lanceur vivant et pas hors combat ; getTension(player) >= TENSION_MAX (100) ; Tension remise à 0 avant tout le reste (anti double déclenchement) ; magie lue dans l'attribut serveu |
| `AttackStarted` | serveur -> autres clients (FireClient sur chaque joueur sauf l'attaquant, CombatService L189-193) | (attacker: Model, comboIndex: number) | N/A (émis après validation de RequestAttack). Client L309 : step et "Sword" doivent exister, puis task.wait(hitStart) et playBladeTrail. |
| `HitConfirmed` | serveur -> tous les clients (FireAllClients) | (attacker: Model, target: Model, damage: number) | N/A. Émis par CombatService L324 (coup d'épée validé) et BossService L215 (coup du boss sur un joueur). Côté client (L322), VFX seulement, ignoré si attacker == personnage local ; secousse si target == personnage local ; |
| `UltimateFired` | serveur -> tous les clients (FireAllClients, CombatService L369) | (caster: Model, origin: Vector3, targets: { Model }, magicId: string) | N/A. Émis AVANT le task.wait(0.2) et les dégâts. targets peut contenir des cibles Invulnerable (non filtrées à la sélection). Client L331 : typeof(origin) == "Vector3" et type(targets) == "table", puis CombatEffects.play |
| `RequestDash` | client -> serveur (DashController.onDashInput L144) | () | MovementService.onDashRequested L38 : canAct (vivant, ni isCustomizing, ni isInAnomaly, ni isRewinding) ; cooldown now - last >= 2 - 0.25 s. Le déplacement lui-même n'est jamais vérifié : accepter un dash ne fait qu'ouvr |
| `DashStarted` | serveur -> autres clients (FireClient sauf le dasheur, MovementService L54-58) | (character: Model) | N/A. Client L160 : nil-check puis playDashTrail. |

### Actif / partiel / mort

- ACTIF : combo à l'épée en 3 coups, du bout à bout (clic, RequestAttack, validation, hitbox client, ReportHit, validation, TakeDamage), démarré par Main.server.luau L22.
- ACTIF : hitbox SpatialHitbox côté client uniquement (Heartbeat pendant hitEnd - hitStart : 0.20 s, 0.18 s, 0.33 s). Le serveur ne fait pas de requête spatiale : il revérifie seulement distance et ligne de vue.
- ACTIF : soft-lock au départ de chaque coup (rayon 15, AutoRotate coupé jusqu'à hitEnd).
- ACTIF : knockback serveur sur le coup 3 seulement (knockback 55, montée 14, 0.2 s).
- ACTIF (purement visuel) : hit-stop client de 0.05 s, secousse caméra et étincelles. Aucun gel réel côté serveur.
- ACTIF : Tension (+20 par coup d'épée validé, remise à 0 à la mort et à l'ultime), jauge TensionView qui clignote quand elle est pleine, invite "[E]  <ultimateName>" aux couleurs de la magie.
- ACTIF : ultime des 5 magies (dégâts de zone sur PNJ taggés), effets UltimateBehaviors tous implémentés (antimatter, pyromancy, lightning, ice, shadow).
- PARTIEL : VFX de l'ultime. CombatEffects.ULTIMATE_PLAYERS = {} (L500) est vide, donc les 5 magies jouent playEruption teintée par leur palette.
- ACTIF : épée Motor6D par SwordFactory, réattachée à chaque nouveau RightHand ; traînée allumée localement pendant la fenêtre de frappe (chez l'attaquant et chez les autres via AttackStarted).
- ACTIF : dash (LinearVelocity client, 85 studs/s pendant 0.18 s, cooldown 2 s) et i-frames serveur de 0.3 s consultées par CombatService L213 (PvP) et BossService L208.
- ACTIF : HitConfirmed réutilisé par BossService L215 pour les VFX des coups du boss.
- PROVISOIRE : le coup 2 "Revers" reprend l'animation du coup 1 ; épée provisoire en Parts ; DEBUG_LOGS = true dans CombatConfig et MovementConfig (print à chaque coup ou refus).
- INCOHÉRENT : PVP_ENABLED = true ne vaut que pour l'épée (et le soft-lock). L'ultime ne touche jamais les joueurs (findUltimateTargets ne parcourt que TimeLoopEntity).
- MORT / NON UTILISÉ : SpatialHitbox.getBoxCFrame exportée mais seulement utilisée en interne ; paramètre damage de HitConfirmed ignoré côté client ; attribut "CombatState" restauré par le TimeLoop mais jamais écrit ; EntitySnapshot.humanoidState capturé mais jamais réappliqué.
- ABSENT : détection de kill (aucun Humanoid.Died), attribution attaquant/contributeur, XP, parade/blocage, hitbox serveur pour les attaques des PNJ (le boss se contente d'un test de distance), validation serveur du déplacement du dash, sauvegarde de la Tension, interactions des pouvoirs avec le décor ou les objets, retour au client quand une attaque est refusée.

### Risques et bugs

- Faux retours visuels : la hitbox client signale TOUT Model qui a un Humanoid (SpatialHitbox.getCharacterFromPart L35-44, sans filtre de tag). onHitboxHit (CombatController L104-108) joue impact, hit-stop et secousse AVANT la validation serveur. Résultat : on voit des coups « porter » sur les villageois (tag Villager, non TimeLoopEntity), sur le boss invulnérable pendant sa charge, sur des joueurs qui dashent ou sont dans le Hub, alors que le serveur les refuse.
- Refus silencieux : dans onHitReported, les rejets de l'étape 2 (cible non autorisée, déjà touchée, morte : L298-306) ne passent pas par logRejection, ce qui complique le debug.
- Désynchronisation du combo : le serveur ne renvoie aucun refus. Si RequestAttack est refusé (ex. rewind, latence), le client continue son combo (coups 2, 3), joue animations et VFX et envoie ReportHit, tous rejetés, avec une cascade de « le combo doit commencer par le coup 1 ».
- Pas de contrôle d'orientation (assumé, L16-18) : un exploit peut frapper à 360° toute cible à moins de ~9.71 studs (coups 1-2) ou ~12.01 studs (coup 3) bord à bord. GetExtentsSize de la cible inclut accessoires et épée, ce qui gonfle encore la portée.
- Ultime : la liste des cibles est figée au lancement et les dégâts tombent 0.2 s plus tard sans revérifier la distance. Après le task.wait, seul isRewinding est revérifié (L377) : ni la mort ni l'anomalie du lanceur. Les cibles Invulnerable ne sont pas exclues à la sélection : elles sont envoyées aux clients dans UltimateFired, qui jouent l'impact (CombatEffects L484-486) sans aucun dégât.
- Rewind et morts : EntitySnapshot.applyInterpolated (L52-60) réécrit Health même sur un Humanoid déjà mort, car le buffer garde les snapshots d'avant la mort. Un PNJ tué dans les 5 dernières secondes peut donc retrouver Health > 0 tout en restant en état Dead (irréversible). getLivingParts et SoftLock le jugent alors vivant : il peut être re-frappé, redonner de la Tension, réapparaître dans les cibles d'ultime, et un comptage de kills basé sur Health compterait deux fois. Côté boss, la boucle runBoss est déjà terminée (bosses[model] = nil).
- Brûlure (pyromancy) : isRewinding n'est vérifié qu'au moment de chaque tick (UltimateBehaviors L129-131). Un rewind qui commence et finit entre deux ticks laisse la brûlure continuer après le retour en arrière. Le lanceur n'est pas connu (le Context n'a que casterHumanoid) : impossible d'attribuer ces dégâts.
- Paralysie (lightning) et gel (ice) ne touchent que WalkSpeed. BossService.performAttack ne regarde pas WalkSpeed et chase peut faire `humanoid.Jump = true` (L169) : un boss paralysé à portée continue de frapper.
- Antimatière : l'aspiration plafonne à 45 × 0.3 = 13.5 studs, vers l'origine du lancement et non vers la position actuelle du lanceur. Avec un rayon de 30, la promesse « aspire les survivants jusqu'à vous, à portée de lame » (MagicConfig L40) n'est pas tenue pour les cibles lointaines. En mode Vector, la LinearVelocity impose aussi Y = 0 pendant 0.3 s.
- Tension gagnée même quand TakeDamage n'inflige rien (ForceField de spawn : Humanoid:TakeDamage ignore les dégâts s'il y a un ForceField) et en PvP. HitConfirmed est quand même émis.
- I-frames sans dash réel : le serveur ne vérifie pas le déplacement. Un exploit peut envoyer RequestDash toutes les 1.75 s sans bouger et rester invulnérable 0.3/1.75 ≈ 17 % du temps. Le cooldown serveur (1.75 s) est plus court que celui du client (2 s). Les i-frames partent de la réception serveur, environ RTT/2 après le début réel du dash.
- DEBUG_LOGS = true (CombatConfig L124, MovementConfig L21) : un client peut spammer RequestAttack ou RequestDash et faire déborder la console serveur de print.
- Si le personnage n'a pas de RightHand (R6, rig sans main), pas d'épée, donc ni attaque ni ultime côté client (getReadyCharacter exige "Sword"), alors que le serveur n'exige pas l'épée.
- Aucun nettoyage des morts : les PNJ tués restent dans Workspace avec le tag TimeLoopEntity (toujours enregistrés à 10 Hz par TimeLoopSession). Aucun Humanoid.Died n'est connecté nulle part dans src.
- SoftLock (client) peut se verrouiller sur un joueur dans le Hub, en anomalie ou sur un PNJ Invulnerable : getEnemies ne filtre que la vie et la présence dans Workspace.
- Si un dossier "CombatRemotes" ou "MovementRemotes" existe déjà dans ReplicatedStorage du fichier de place (restes d'un export Studio), le serveur en crée un second et le client peut récupérer le mauvais par WaitForChild. Les deux modules Remotes créent sans vérifier l'existant.
- isOutOfCombat est local à CombatService (non exporté) : BossService refait ses propres vérifications, partiellement. getTargetParts ne regarde ni le rewind ni l'anomalie au moment du ciblage, seulement après le windup.

### Identifiants d'assets

- src/shared/Combat/CombatConfig.luau:26 — SWORD_SLASH_ANIMATION = "rbxassetid://522635514" ("R15 Sword Slash", animation officielle Roblox), utilisée par les coups 1 "Entaille" et 2 "Revers". PROVISOIRE : L42 dit « même animation en attendant un vrai slash inversé ».
- src/shared/Combat/CombatConfig.luau:27 — SWORD_LUNGE_ANIMATION = "rbxassetid://522638767" ("R15 Sword Lunge", officielle Roblox), coup 3 "Brise-ciel". Placeholder officiel en attendant des animations propres au jeu (en-tête L7-11).
- src/client/Combat/CombatEffects.luau:30 — SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds" (texture livrée avec le client, pas un asset ID : définitif, sans import).
- src/client/Combat/CombatEffects.luau:31 — SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" (texture intégrée).
- Aucun asset dans MagicConfig, MovementConfig, SwordFactory (épée provisoire en Parts), DashController, TensionView, SoftLock ni SwingAnimator. Aucun son de combat.
- Hors périmètre mais lié : src/shared/Boss/BossConfig.luau:50 ATTACK_ANIMATION_ID réutilise "rbxassetid://522635514" ; :49 WALK_ANIMATION_ID = "rbxassetid://507777826".

### Ce que le code attend dans la scène

- Joueurs : rig R15 avec "RightHand" et "RightGripAttachment". CombatService attend la main jusqu'à 10 s (L127). Sans main, warn L131 et pas d'épée : le client refuse alors toute attaque ET l'ultime, car getReadyCharacter (L69-71) exige l'enfant "Sword".
- Optionnel : ServerStorage.Assets.Sword (Model, PrimaryPart = poignée dont l'axe Y pointe vers la pointe, pièces soudées, Attachments BladeStart et BladeEnd quelque part dans le modèle). Absent ou invalide : épée provisoire générée, avec un warn si invalide.
- Ennemi frappable à l'épée : un Model dans Workspace, répliqué au client ; un Humanoid ENFANT DIRECT du Model (FindFirstChildOfClass) dont Humanoid.RootPart n'est pas nil ; Health > 0 ; le tag "TimeLoopEntity" ; pas d'attribut Invulnerable = true ; des pièces CanQuery = true (GetPartBoundsInBox côté client) ; pas de décor CanCollide entre lui et l'attaquant ; RootPart non ancré s'il doit subir knockback ou aspiration.
- Un Model taggé "Boss" doit avoir un Humanoid avec RootPart. BossService force alors MaxHealth/Health 600, WalkSpeed 14, désancre toutes les pièces, prend la propriété réseau et ajoute TimeLoopEntity.
- Enregistrement par tag : BossService et TimeLoopService ignorent les modèles hors Workspace au moment de l'ajout du tag (IsDescendantOf(workspace)). Pour faire apparaître un ennemi, il faut faire Clone() puis Parent = workspace : déplacer dans Workspace un modèle déjà taggé rangé dans ServerStorage ne redéclenche pas GetInstanceAddedSignal.
- StarterPlayer.EnableMouseLockOption doit être décoché, sinon LeftShift déclenche aussi le Shift Lock (MovementConfig L8-9).
- DashController.playDashTrail cherche un enfant nommé exactement "HumanoidRootPart" (L76).
- Aucune position codée en dur dans le combat ou le mouvement : tout est relatif au RootPart de l'attaquant ou à l'origine de l'ultime. CombatEffects suppose une caméra par défaut (FieldOfView de repos lu sur la caméra) ; restingFieldOfView vaut 70 tant qu'aucun coup de FOV n'a eu lieu.

## Boucle temporelle et boss

Le périmètre monde/ambiance/carte/PNJ compte 16 fichiers : les 15 attendus, plus src/shared/World/RegionConfig.luau, apparu pendant l'audit (écrit à 23:53, alors que tout le reste date de 22:24) et utilisé par aucun code.

Principe actif : le SERVEUR décide, le CLIENT met en image. WorldService (démarré par Main.server l.18) écrit deux attributs sur Workspace, 'WorldWeather' (clear/mist/gale, nouveau tirage pondéré toutes les 150 à 330 s, jamais deux fois la même météo de suite) et 'WorldMood' (Normal/Anomaly, via setAnomaly(source, bool) appelé par BossService l.245/265/308). Il envoie aussi de temps en temps un présage (RemoteEvent WorldRemotes.Omen, toutes les 240 à 540 s, seulement en humeur Normal).

L'heure n'est transmise par aucun attribut : WorldConfig.getClockTime() la calcule depuis workspace:GetServerTimeNow(), avec une journée de 900 s, identique sur tous les serveurs. Côté client, WorldAtmosphere.client applique toutes les 0,5 s (à chaque frame pendant une bascule) :
- LightingPresets (images clés NIGHT/DAWN/DAY/DUSK, interpolées) ;
- plus la météo lissée (constante de 12 s) ;
- plus le mélange vers le préréglage ANOMALY (0,35 s pour entrer, 4 s pour sortir ; ClockTime forcé à 0 au-delà de la moitié).

Il pilote aussi GlobalWind, les particules (dust/fireflies/embers) et deux sons : un bourdon d'anomalie (asset provisoire) et le vent (ID vide, donc muet). Effets créés : Atmosphere (réutilisée si elle existe), Terrain.Clouds, ColorCorrectionEffect 'WorldColorCorrection' et 'WorldOmenVeil', BloomEffect 'WorldBloom', SunRaysEffect 'WorldSunRays'.

La carte (lettre M, reconnue par KeyboardLayout pour marcher en AZERTY) est purement 2D et statique : 5 continents placés en fractions codées en dur, 3 mers, une rose des vents et un panneau de lore. 'Vous êtes ici' vient de la constante CURRENT_CONTINENT_ID='human'. Il n'y a ni point d'intérêt, ni marqueur du joueur, ni lien avec Workspace.

PNJ : rien n'est créé par code. Ce sont des Models posés à la main et tagués 'Villager', avec les attributs facultatifs NpcName, DialogueId et Wanders. Le serveur les fait se promener (Humanoid:MoveTo, sans pathfinding) et, sur TalkStarted, les arrête et les tourne vers le joueur. La validation serveur se limite à : villageois inscrit, et distance de 16 studs au plus. Chaque client pose un ProximityPrompt local (touche F, 10 studs) et joue un dialogue linéaire en machine à écrire, défini par { name?, lines }, entièrement local. Le serveur ignore donc quel dialogue a été lu : aucun crochet de quête n'existe. Points faibles principaux : un villageois parlant à deux joueurs repart dès que l'un des deux termine ; le dialogue générique est choisi d'après le nom du Model, donc tous les rigs 'Rig' disent la même chose ; la météo et l'anomalie sont globales au serveur ; aucun setter de météo. Enfin, l'export Studio contient des noms avec espaces finaux ('WorldMapView   '), qui cassent la carte si la place n'est pas synchronisée par Rojo.

Branchements prévus (détails dans extensionPoints) :
- getTargetWeather et apply de WorldAtmosphere ;
- pickWeather et runWeatherCycle de WorldService ;
- des Signals à ajouter dans onTalkStarted et onTalkEnded de VillagerService ;
- getDialogue, openDialogue et closeDialogue de NPCInteraction ;
- WorldMapView.create et WorldMapController.open, branchés sur RegionConfig.POIS, toLocal et LAYOUT.playableMin/Max.

### Fichiers

| Fichier | Rôle |
|---|---|
| `/home/user/RobloxRPG/src/shared/World/WorldConfig.luau` | Constantes partagées du monde : noms d'attributs Workspace, humeurs, heure (getClockTime), météos, présages, IDs de sons d'ambiance. |
| `/home/user/RobloxRPG/src/shared/World/WorldMapConfig.luau` | Contenu statique de la carte (touche M) : touche, titre, emplacements d'images (tous vides), continent courant codé en dur, 5 continents (position/taille en fractions de la zone de carte, silhouettes en taches), 3 mers. |
| `/home/user/RobloxRPG/src/shared/World/WorldRemotes.luau` | Le serveur crée ReplicatedStorage.WorldRemotes (Folder) et le RemoteEvent 'Omen' au premier require ; le client fait un WaitForChild sans timeout. |
| `/home/user/RobloxRPG/src/shared/World/RegionConfig.luau` | Contrat prévu entre un futur générateur (Workspace.World) et les systèmes : ORIGIN, positions clés locales, régions (boîtes, ambiance, météos autorisées, découvertes), POI de carte, portes, ancres attendues (tag WorldAnchor + AnchorId), fonctions de conversion local/monde. |
| `/home/user/RobloxRPG/src/server/World/WorldService.luau` | Décide de l'état du monde sans toucher au Lighting : boucle météo (attribut Workspace WorldWeather), humeur (WorldMood, comptage des sources d'anomalie), boucle de présages (Omen:FireAllClients). |
| `/home/user/RobloxRPG/src/client/World/AmbientParticles.luau` | Volume invisible local 'AmbientParticleVolume' (90x34x90) dans Workspace, recentré sur la caméra, avec 3 ParticleEmitters : dust (jour), fireflies (nuit), embers (anomalie). Un seul allumé à la fois. |
| `/home/user/RobloxRPG/src/client/World/LightingPresets.luau` | Préréglages complets de rendu (groupes Lighting, Atmosphere, ColorCorrection, Bloom, SunRays, Clouds) et interpolation sur la journée (KEYFRAMES : 0 NIGHT, 5.2 NIGHT, 6.5 DAWN, 9 DAY, 16.5 DAY, 18.3 DUSK, 20 NIGHT, 24 NIGHT). |
| `/home/user/RobloxRPG/src/client/World/WorldAtmosphere.client.luau` | Met en image l'état du monde : crée et met à jour l'Atmosphere, les nuages et les effets post-process, interpole lumière, météo et anomalie, règle GlobalWind, les particules, les sons (bourdon, vent) et l'affichage des présages. |
| `/home/user/RobloxRPG/src/client/World/WorldMapController.client.luau` | Ouvre ou ferme la carte sur la lettre M (via KeyboardLayout), gère la sélection d'un continent au clic, le survol, le pied de carte (heure et météo lues à l'ouverture) et un log de démarrage. Purement local, aucun remote. |
| `/home/user/RobloxRPG/src/client/World/WorldMapView.luau` | Construit par code le ScreenGui 'WorldMapGui' (DisplayOrder 40, Enabled=false) : Backdrop, CanvasGroup 'Sheet' en parchemin, titre, pied de carte, bouton Close 'X', MapArea (mers, rose des vents, un cadre par continent), InfoPanel. |
| `/home/user/RobloxRPG/src/shared/Input/KeyboardLayout.luau` | Désigne une touche par la lettre imprimée dessus, quelle que soit la disposition (AZERTY : la touche 'M' envoie KeyCode.Semicolon). |
| `/home/user/RobloxRPG/src/shared/NPC/DialogueConfig.luau` | Réglages des villageois : tag, attributs, touche et distance d'interaction, machine à écrire, son de bip, dialogues, promenade, animation de marche. |
| `/home/user/RobloxRPG/src/shared/NPC/NPCRemotes.luau` | Crée ReplicatedStorage.NPCRemotes avec les RemoteEvents 'TalkStarted' et 'TalkEnded' (le serveur au premier require ; le client fait un WaitForChild sans timeout). |
| `/home/user/RobloxRPG/src/server/NPC/VillagerService.luau` | Inscrit les Models tagués 'Villager' (dans workspace, avec Humanoid et RootPart), les fait se promener autour de leur point de pose (une seule boucle, toutes les 0,5 s), et les arrête/tourne vers le joueur sur TalkStarted. |
| `/home/user/RobloxRPG/src/client/NPC/DialogueView.luau` | Construit le ScreenGui 'DialogueGui' (DisplayOrder 60, Enabled=false) : ClickCatcher plein écran, et une boîte 'Box' avec NamePlate, Line et Hint. |
| `/home/user/RobloxRPG/src/client/NPC/NPCInteraction.client.luau` | Pose un ProximityPrompt local 'TalkPrompt' sur chaque Model tagué Villager, ouvre la boîte de dialogue (texte lettre par lettre, bip, pauses sur la ponctuation), immobilise le joueur (PlayerModule:GetControls():Disable()), neutralise E, LeftShift et la touche carte, et prévient le serveur (TalkStarted/TalkEnded). |

### Remotes

| Nom | Sens | Charge | Validation serveur |
|---|---|---|---|
| `Omen` | serveur -> tous les clients (WorldService.runOmenCycle l.68, FireAllClients) | text: string (une entrée de WorldConfig.OMENS) | Sans objet (le serveur émet). Il n'émet que si WorldMood == 'Normal' et s'il y a au moins un joueur. Le client ignore le message si le Player a IsCustomizing == true ou si un présage est encore affiché (TextTransparency  |
| `TalkStarted` | client -> serveur (NPCInteraction.openDialogue l.228) | (villager: Model) | VillagerService.onTalkStarted l.140-167 : typeof(target) == 'Instance' ; target doit être une clé de `villagers`, donc un Model tagué Villager, descendant de workspace, avec Humanoid et RootPart ; character.HumanoidRootP |
| `TalkEnded` | client -> serveur (NPCInteraction.closeDialogue l.194) | () aucun argument | VillagerService.onTalkEnded l.169-176 : si talkingWith[player] existe, l'efface, remet talkingUntil = 0 et nextMoveClock = now + 4. Aucun paramètre à valider. Aussi branché sur Players.PlayerRemoving (l.197). |

### Actif / partiel / mort

- ACTIF : WorldService.start (Main l.18), avec les boucles météo et présages ; setAnomaly appelé par BossService au début de la charge de l'attaque fatale (l.245) et relâché après le rewind ou la mort du boss (l.265, l.308).
- ACTIF : WorldAtmosphere : cycle jour/nuit continu (journée de 900 s, horloge serveur absolue, aucun attribut d'heure), météo lissée, bascule d'anomalie, GlobalWind, particules (jour = dust, nuit de 19.6 à 5.8 = fireflies, anomalie au-delà de 0.5 = embers), bourdon d'anomalie, présages avec voile désaturé.
- ACTIF : carte M (WorldMapController + WorldMapView) avec reconnaissance AZERTY (KeyboardLayout), mais contenu 100 % statique.
- ACTIF : NPCInteraction (prompts locaux, touche F, 10 studs, dialogue machine à écrire, immobilisation, neutralisation de E, LeftShift et M ; R volontairement laissée libre) et VillagerService (promenade, arrêt et orientation). Ne fait réellement quelque chose que si la place contient des Models tagués Villager.
- PARTIEL : son de vent câblé mais muet (WIND_SOUND_ID vide).
- PROVISOIRE : ID du bourdon d'anomalie, toutes les images de la carte, son de bip par défaut, DEBUG_LOGS = true (print au démarrage de la carte).
- MORT : les valeurs Clouds.Cover de DAY, DAWN, DUSK et NIGHT (LightingPresets) sont toujours écrasées par weather.cloudCover (WorldAtmosphere l.155) ; seule celle d'ANOMALY compte, via le mélange.
- STATIQUE : CURRENT_CONTINENT_ID = 'human' ('Vous êtes ici' ne suit pas le joueur) ; le pied de carte n'est rafraîchi qu'à l'ouverture ; le Backdrop absorbe les clics sans fermer la carte.
- PARTIEL : les dialogues sont linéaires ({ name?, lines }), sans choix, condition ni action. Le serveur ne sait pas quel dialogue a été lu ni s'il a été fini : TalkEnded ne porte rien, et le dialogue générique est calculé côté client.
- INUTILISÉ : RegionConfig.luau (apparu pendant l'audit) n'est requis par aucun fichier. Ses clés d'ambiance, météos par région, POI, portes et ancres n'ont aucun consommateur.
- ABSENT (prévu dans ARCHITECTURE.md) : RegionService, NpcSpawner, InteractionService, RegionAmbience, WorldBuilder, EncounterMood, Input/KeyBindings, UI/Theme, Grimoire, QuestService, MissionService.

### Risques et bugs

- Export Studio (backups/studio-export-2026-10-14) : des instances ont des noms avec espaces finaux ('WorldMapView   ', 'NPCInteraction ', 'BossEffectsController   ', vérifié dans le .rbxmx). Dans cette place, `script.Parent:WaitForChild('WorldMapView')` (WorldMapController l.27) attend indéfiniment et la carte ne s'ouvre jamais. L'export n'a pas non plus Shared/Input/KeyboardLayout (correctif AZERTY). Les noms dans src sont propres : il faut synchroniser par Rojo et supprimer les anciennes instances.
- VillagerService.onTalkEnded l.169-176 : si deux joueurs parlent au même villageois, le premier qui termine remet talkingUntil à 0 et le villageois repart pendant que l'autre lit encore. De même, un TalkStarted vers un villageois B écrase talkingWith[player] : A reste figé jusqu'au délai de 45 s.
- TalkStarted sans limite de fréquence ni contrôle (vivant, IsCustomizing) : un client peut figer et faire pivoter en boucle tout villageois à 16 studs ou moins. Contraire aux principes 2 et 3 d'ARCHITECTURE.md (RateLimiter, état du joueur).
- Le serveur ignore le contenu des dialogues : DialogueId n'est lu que côté client, et le dialogue générique est tiré côté client d'un hash de Model.Name (NPCInteraction l.82-89). Tous les rigs portant le nom par défaut 'Rig' du Rig Builder ont donc le même dialogue générique, et la plaque affiche 'Rig' si NpcName est absent. Aucun crochet de quête n'est possible en l'état.
- NPCInteraction : ObjectText du prompt calculé une seule fois (l.283). Un NpcName ou DialogueId posé après le tag (par un futur spawner) n'est pas pris en compte. Un DialogueId invalide retombe en silence sur un générique.
- TALK_TIMEOUT = 45 s : le villageois reprend sa promenade même si le dialogue est encore ouvert (le dialogue, lui, ne se ferme pas). Le dialogue ne se ferme pas non plus si la distance augmente.
- Promenade sans pathfinding : Humanoid:MoveTo vers un point aléatoire à 14 studs au plus, à la hauteur home.Y (l.114-119). Le villageois peut foncer dans un mur, tomber d'une butte ou entrer dans l'eau. Gênant dans une région générée avec reliefs.
- Wanders=false sur un rig NON ancré : SetNetworkOwner(nil) n'est pas appelé (l.84-91), un client proche peut posséder la physique, et le CFrame.lookAt fait par le serveur peut saccader.
- Météo et anomalie globales au serveur : un seul attribut WorldWeather et un seul WorldMood. Aucun setter de météo (currentId est une variable locale de la boucle), donc impossible de forcer une météo pour une quête. ARCHITECTURE §6 veut une anomalie locale par rencontre (EncounterMood), non implémentée.
- WorldService.setAnomaly appelé avant start() : start() réécrit WorldMood='Normal' même si des sources sont actives (l'ordre de Main le protège). anomalySources garde des références fortes sans délai d'expiration : une source jamais relâchée laisse le monde en anomalie pour toujours.
- WorldAtmosphere.newEffect (l.60-65) crée toujours de nouveaux effets, sans réutiliser l'existant : les effets placés dans Studio s'additionnent. La réécriture des propriétés de Lighting toutes les 0,5 s écrase tout autre script qui voudrait les modifier (une ambiance de région doit donc passer par apply()).
- LightingPresets : les valeurs Clouds.Cover des préréglages de journée ne servent à rien (écrasées par la météo, l.155).
- Lighting.ClockTime n'est réglé que côté client ; côté serveur il garde la valeur de Studio. Une logique serveur 'il fait nuit' doit utiliser WorldConfig.getClockTime() et WorldConfig.NIGHT_START/NIGHT_END. L'heure est absolue (GetServerTimeNow) et commune à tous les serveurs ; impossible de la mettre en pause ou de l'avancer sans changer CLOCK_OFFSET (local, non exporté).
- Carte : n'intercepte ni E ni LeftShift (ultime et dash restent possibles carte ouverte ; seuls les clics sont absorbés par le Backdrop). Un prompt F peut s'ouvrir par-dessus la carte (Dialogue 60 > Carte 40). DEBUG_LOGS = true fait un print en production.
- KeyboardLayout.findKeyCode appelle GetStringForKeyCode (pcall) sur toutes les valeurs d'Enum.KeyCode à chaque openDialogue (NPCInteraction l.242) : coût faible mais inutile, la valeur peut être mise en cache.
- DialogueView : tailles fixes en pixels (BOX_SIZE hauteur 150 px, marge 96 px, Hint 260x18, TextSize 25), contraire à la convention 'tailles Scale' d'ARCHITECTURE §1. Risque sur mobile. Le texte d'aide '[F] ou clic' est codé en dur (NPCInteraction l.132), pas dérivé de INTERACT_KEY, et ne mentionne pas la manette.
- typeLine compte les points de code (utf8.codes) alors que MaxVisibleGraphemes compte des graphèmes : décalage possible avec des caractères combinants ou des emoji (le français précomposé passe).
- Gel superficiel : WEATHERS, OMENS, DIALOGUES, CONTINENTS, REGIONS, POIS, ANCHORS restent modifiables à l'exécution.
- Anciens modules *Remotes : le client fait WaitForChild sans timeout. Si le serveur ne requiert jamais le module, l'attente est infinie et silencieuse (RemoteFolder, lui, avertit au bout de 30 s).
- RegionConfig (nouveau) : non câblé. Les PNJ npc_bellkeeper, npc_quartermaster, npc_guildmaster, npc_trainer, npc_wanderer et npc_villager_1..3 n'ont aucun dialogue dans DialogueConfig ; les portes référencent la quête 'bell_silent' et le rang 'C', qui n'existent pas ; les clés d'ambiance n'ont aucun consommateur.

### Identifiants d'assets

- src/shared/World/WorldConfig.luau:81 ANOMALY_DRONE_ID = 'rbxassetid://9043359885' : bourdon joué en boucle pendant l'anomalie (son 'WorldAnomalyDrone', volume 0.55 x moodAlpha). PROVISOIRE : le commentaire le présente comme placeholder 'DARK DRONE 13' (APM Music).
- src/shared/World/WorldConfig.luau:85 WIND_SOUND_ID = '' : emplacement vide pour une boucle de vent. Le code est câblé (WorldAtmosphere l.95 et l.183) mais ne joue rien tant que l'ID est vide.
- src/shared/NPC/DialogueConfig.luau:96 BLIP_SOUND_ID = 'rbxasset://sounds/electronicpingshort.wav' : bip de la machine à écrire. Fichier livré avec le client Roblox (pas un rbxassetid) ; valeur par défaut que le commentaire invite à remplacer.
- src/shared/NPC/DialogueConfig.luau:112 WALK_ANIMATION_ID = 'rbxassetid://507777826' : animation officielle 'R15Walk' de Roblox, jouée par le serveur sur les villageois R15. Définitive (R6 : pcall, le villageois glisse sans animation).
- src/client/World/AmbientParticles.luau:14 SPARK_TEXTURE = 'rbxasset://textures/particles/sparkles_main.dds' : texture des 3 émetteurs. Fichier livré avec le client, pas un placeholder.
- src/shared/World/WorldMapConfig.luau:136 PARCHMENT_IMAGE = '' : texture du parchemin, vide (dégradé dessiné par code à la place).
- src/shared/World/WorldMapConfig.luau:49-50, 66-67, 82-83, 98-99, 114-115 : image = '' et illustration = '' pour les 5 continents. Vides : silhouettes en taches de couleur, et texte 'Illustration à venir'.

### Ce que le code attend dans la scène

- Villageois : Models posés à la main dans Workspace (n'importe où dessous) avec le tag 'Villager'. Aucun code ne les fait apparaître, et aucune position n'est codée en dur : le point d'attache 'home' est rootPart.Position au moment de l'inscription. Pour qu'il se promène et se tourne vers le joueur : Humanoid + RootPart (HumanoidRootPart), non ancré, R15 de préférence (animation de marche). Sans Humanoid (statue, panneau), le client affiche quand même un prompt et joue le dialogue, mais le serveur l'ignore. Le dépôt ne permet pas de vérifier qu'il en existe dans la place : l'export Studio ne contient que les scripts.
- Un villageois rangé dans ServerStorage puis déplacé dans Workspace n'est pas inscrit (le signal de tag ne se redéclenche pas). Un clone parenté dans Workspace l'est.
- Terrain : doit exister (WorldAtmosphere l.84 crée ou réutilise Terrain.Clouds).
- Lighting : une Atmosphere existante est réutilisée. Les autres effets déjà présents (Bloom, ColorCorrection, SunRays) ne sont pas supprimés et s'additionnent aux effets World*. Lighting.Technology = Future est à régler à la main dans Studio (commentaire l.16-18). Toutes les 0,5 s, le client réécrit Lighting.Ambient, OutdoorAmbient, Brightness, ColorShift_Top, ExposureCompensation et ClockTime : un réglage fait dans Studio est donc écrasé.
- StarterPlayerScripts.PlayerModule (celui de Roblox par défaut) : utilisé pour immobiliser le joueur pendant un dialogue ; s'il manque, le joueur peut bouger.
- Le code de ce périmètre ne lit pas Workspace.World et ne cherche aucune ancre ni coordonnée 3D. Les seules 'positions' sont des fractions 2D d'interface dans WorldMapConfig.
- RegionConfig (nouveau, non utilisé) prévoit une région construite autour de ORIGIN = (3000, 0, 0), dans Workspace.World/{Static, Anchors, EchoPaths, Dynamic}, avec des ancres taguées WorldAnchor (dont npc_elder, npc_blacksmith, npc_child, npc_bellkeeper, npc_quartermaster, npc_guildmaster, npc_trainer, npc_wanderer, npc_villager_1..3).
- Créés localement par le client : Workspace.AmbientParticleVolume (CanQuery=false, suit la caméra).

## Monde, ambiance, carte, PNJ

Périmètre audité intégralement (12 fichiers, 1980 lignes) : shared/TimeLoop/{TimeLoopConfig,TimeLoopRemotes}, server/TimeLoop/{TimeLoopService,TimeLoopSession,SnapshotBuffer,EntitySnapshot}, client/TimeLoopController.client.luau, client/TimeLoop/{GlitchOverlay,TimeLoopAudio}, shared/Boss/BossConfig, server/Boss/BossService, client/Boss/BossEffectsController.client.luau. J'ai aussi lu par grep les fichiers qui les utilisent : Main, CombatService, UltimateBehaviors, MovementService, WorldService, AvatarService, SoftLock, CombatController, CombatEffects.

ENREGISTREMENT. Il n'y a qu'UNE session globale pour tout le serveur : `local session = TimeLoopSession.new()` au niveau module de TimeLoopService.luau, l.31. Elle enregistre deux sortes d'entités : tous les personnages joueurs (via CharacterAdded) et tous les Model taggés "TimeLoopEntity" présents sous workspace. Le boss reçoit ce tag automatiquement. Les villageois (tag "Villager") ne sont pas enregistrés. Cadence : un Heartbeat accumule le temps et prend un snapshot toutes les RECORD_INTERVAL = 0.1 s (10 Hz), en un seul snapshot même après un lag grâce au modulo. Chaque entité a un buffer circulaire de capacité ceil(6/0.1)+2 = 62, soit environ 6 s. Contenu d'un snapshot : timestamp en « temps de timeline », CFrame du RootPart, Health, humanoidState (jamais réappliqué) et attribut "CombatState" (que personne n'écrit). Une entité morte n'est pas capturée. L'horloge de timeline s'arrête pendant un rewind et tant qu'au moins une anomalie est ouverte (pause globale).

REMBOBINAGE. Le client presse R et envoie RequestRewind sans argument. Le serveur vérifie, dans canRewind : aucun rewind en cours, joueur vivant, puis soit anomalie ouverte pour ce joueur (cooldown ignoré), soit DEBUG_FREE_REWIND=true avec le cooldown global de 3 s respecté. Ensuite, dans l'ordre : toutes les anomalies sont fermées, RewindStarted part à tous les clients, puis session:rewind(5, 1.5), qui YIELD. Ce rewind capture l'instant présent, ancre le RootPart de toutes les entités, puis fait reculer un curseur de 5 s de timeline en 1.5 s réelles, soit 3,33 fois la vitesse normale. À chaque frame, le CFrame et la Health sont interpolés et les snapshots « futurs » sont dépilés. À l'atterrissage : application de CombatState, désancrage avec vitesses remises à zéro, reprise de la propriété réseau des PNJ, puis un snapshot. Enfin RewindEnded part à tous les clients.

Ce qui est RESTAURÉ : uniquement le CFrame du RootPart, la Health et l'attribut CombatState. Ce qui NE l'est PAS : les morts (un Humanoid mort le reste), la Tension, les cooldowns en os.clock (boss, dash, combo), BossState, Invulnerable, les effets de vitesse BaseWalkSpeed/SpeedEffectToken, les LinearVelocity de knockback, le WorldMood, le décor.

ANOMALIE. Elle n'est ouverte que par BossService.performUltimate, qui appelle TimeLoopService.openAnomaly(target) (durée par défaut ANOMALY_WINDOW = 4 s ; le paramètre duration n'est jamais passé). Effets : RootPart du joueur ancré, timeline en pause globale, AnomalyOpened(window) envoyé à ce client seulement, et task.delay(window, onAnomalyExpired). Fermeture par l'une de ces voies : n'importe quel rewind (qui ferme toutes les anomalies), l'expiration (closeAnomaly puis Health = 0, vraie mort), CharacterRemoving ou PlayerRemoving. Le rewind hors anomalie est une config de test ACTIVE : DEBUG_FREE_REWIND = true, avec DEBUG_LOGS à true aussi. N'importe quel joueur peut donc rembobiner tout le serveur toutes les 3 s.

MULTIJOUEUR. Une timeline globale. Les anomalies sont stockées par joueur (`{[Player]: Anomaly}`), mais la pause et la résolution sont globales : un rewind sauve tout le monde. RewindStarted et RewindEnded partent en FireAllClients, donc tous les écrans glitchent, même loin du combat. La synchro repose sur la réplication physique des RootPart ancrés et déplacés par le serveur. Le compteur « REW » est calculé localement à partir de playbackDuration. Les autres joueurs ne reçoivent pas AnomalyOpened.

BOSS. Il est trouvé via le tag "Boss" (BossConfig.TAG), sur un Model sous workspace au moment où le tag est ajouté. registerBoss règle PV 600, WalkSpeed 14 et DisplayName, désancre toutes les BaseParts, crée l'Animator si besoin, ajoute le tag TimeLoopEntity et lance runBoss. Pas de respawn. IA, toutes les 0.2 s :
- si un rewind est en cours, il ne décide rien ;
- sans cible dans un rayon de 150 studs, il passe en Idle ;
- si PV ≤ 20 % et cooldown de 25 s écoulé, il lance performUltimate : charge de 1.5 s, ancré, Invulnerable=true, BossState=Charging, WorldMood=Anomaly ; puis openAnomaly sur le joueur le plus proche ; il attend l'issue en scrutant isRewinding (polling) ; si c'était un rewind, Staggered puis 3 s sans agir ;
- à 6 studs ou moins, performAttack : préparation 0.35 s, 8 dégâts si la cible est toujours à 7.5 studs ou moins, sans dash et hors anomalie, puis HitConfirmed ;
- sinon, poursuite par PathfindingService.

À sa mort : BossState=Dead, Invulnerable=false, setAnomaly(false), retrait de la table. Le Model n'est PAS détruit et le tag TimeLoopEntity n'est PAS retiré. Côté client, BossEffectsController habille Charging (particules aspirées, cœur néon, PointLight, Highlight rouge) et Staggered (Highlight pâle).

RISQUES MAJEURS.
1. Le cadavre du boss (et un joueur mort avant son respawn) reste dans la session. Chaque rewind lui réapplique son dernier snapshot vivant, Health > 0 comprise. Il redevient une cible valide pour CombatService, SoftLock et les ultimes : on peut farmer la Tension, c'est le « double kill ».
2. La Tension n'est pas rembobinée alors que les PV du boss le sont : farm d'ultimes avec le rewind libre.
3. Quatre systèmes ancrent et désancrent le RootPart (AvatarService, anomalie, rewind, charge du boss), chacun avec son propre wasAnchored. Selon l'ordre des opérations, un joueur peut rester ancré pour de bon.
4. Rewind global déclenchable par n'importe qui.
5. La pause globale pendant l'anomalie crée des téléportations dans la relecture.
6. L'issue de l'anomalie est devinée par polling de isRewinding, sujet à des faux positifs et faux négatifs.

POINTS D'EXTENSION. SnapshotBuffer et EntitySnapshot.capture sont réutilisables pour des échos temporels, mais avec un buffer dédié qui ne soit pas consommé par le rewind (popNewest), d'une capacité supérieure à 62, une fonction d'application qui ne touche que le CFrame (applyInterpolated écrit aussi la Health), et en tenant compte du temps de timeline non monotone. Les modules sont côté serveur, il faut les déplacer dans shared pour un rendu client. Les énigmes (restaurer un pont) demandent de généraliser TimeLoopSession au-delà des Model avec Humanoid, ou d'ajouter des Signals serveur (shared/Util/Signal existe mais n'est utilisé nulle part) et un getter de temps de timeline. L'arbitrage multijoueur se branche dans canRewind et onRewindRequested, avec une session par arène. Les phases du boss se branchent dans runBoss et BossConfig ; l'attribut CombatState, seul attribut rembobiné, peut porter la phase.

### Fichiers

| Fichier | Rôle |
|---|---|
| `src/shared/TimeLoop/TimeLoopConfig.luau` | Constantes du Time-Loop : enregistrement (RECORD_INTERVAL 0.1, BUFFER_DURATION 6), rewind (REWIND_WINDOW 5, REWIND_PLAYBACK_DURATION 1.5, REWIND_COOLDOWN 3), ANOMALY_WINDOW 4, flags de test DEBUG_FREE_REWIND=true / DEBUG_LOGS=true, ENTITY_TAG "TimeLoopEntity", COMBAT_STATE_ATTRIBUTE "CombatState", REWIND_KEY R, son du rewind (ID, volume 0.7, END_OCTAVE 0.5, FADE_OUT 1.6, fatigue 90 s / x0.75 / min 0.35), GLITCH_IMAGE |
| `src/shared/TimeLoop/TimeLoopRemotes.luau` | Côté serveur, crée au premier require le dossier ReplicatedStorage.TimeLoopRemotes et 5 RemoteEvent, sans FindFirstChild : il ne réutilise pas un dossier existant. Côté client, WaitForChild sans timeout. N'utilise pas shared/Net/RemoteFolder. |
| `src/server/TimeLoop/TimeLoopService.luau` | Seul point d'entrée du Time-Loop pour le reste du jeu. Possède la session globale unique (l.31), la table anomalies: {[Player]: Anomaly} (l.32) et lastRewindEndClock, un cooldown global (l.33). Inscrit les personnages joueurs (CharacterAdded/CharacterRemoving) et les Model taggés TimeLoopEntity sous workspace. Ouvre et ferme les anomalies (ancrage du RootPart, pause globale de l'enregistrement, mort à l'expiration).  |
| `src/server/TimeLoop/TimeLoopSession.luau` | Timeline partagée par un groupe d'entités. Data logger : à chaque Heartbeat, si ni rewind ni pause, avance _timelineTime et prend un snapshot de chaque entité tous les RECORD_INTERVAL (avec modulo). Rewind : capture du présent, freeze (ancrage + mémorisation de wasAnchored), curseur reculant à la vitesse window/playbackDuration, scrub (dépile les snapshots plus récents que le curseur et interpole CFrame et Health), l |
| `src/server/TimeLoop/SnapshotBuffer.luau` | Buffer circulaire de capacité fixe, push et pop en O(1). Les offsets comptent depuis le plus récent. Typé strictement sur EntitySnapshot.Snapshot (pas générique). Pas de getter public du nombre d'éléments (_count est privé) ni d'itérateur : pour parcourir, on appelle peek jusqu'à obtenir nil. |
| `src/server/TimeLoop/EntitySnapshot.luau` | Définit le Snapshot et sait le lire et l'écrire sur un personnage Humanoid. capture renvoie nil si le personnage est incomplet ou mort. applyInterpolated écrit le CFrame du RootPart et la Health. applyDiscreteState écrit l'attribut CombatState (nil le supprime). humanoidState est capturé mais jamais réappliqué. |
| `src/client/TimeLoopController.client.luau` | Envoie RequestRewind:FireServer() sur InputBegan R (sauf gameProcessed), sans aucune garde côté client. Met en scène AnomalyOpened (message et glitch « anomaly » ; windowDuration ignoré, pas de compte à rebours), AnomalyClosed (efface le message et stop(0.3) si pas de rewind en cours), RewindStarted (glitch « rewind », TimeLoopAudio.playRewind, compteur « << REW -x.x s » rafraîchi toutes les 0.05 s, YIELD jusqu'à Rew |
| `src/client/TimeLoop/GlitchOverlay.luau` | Effet de « rupture de la réalité » à l'écran. Crée une fois ColorCorrectionEffect "TimeLoopColorCorrection" et BlurEffect "TimeLoopBlur" dans Lighting, et une ScreenGui "TimeLoopGlitchGui" (ResetOnSpawn=false, IgnoreGuiInset, DisplayOrder 100) contenant des ImageLabel de neige en mosaïque, 14 tranches, un flash, un label Message (GothamBlack, rouge 255,70,70) et un label Caption (police Code, 34 px). Deux profils, "a |
| `src/client/TimeLoop/TimeLoopAudio.luau` | Au require, crée un Sound local "TimeLoopRewindSound" dans SoundService, avec un PitchShiftSoundEffect. playRewind : vitesse, point de départ et hauteur tirés au hasard, fondu d'entrée de 0.15 s jusqu'au volume réduit par la lassitude, hauteur qui glisse vers 0.5 octave pendant toute la durée. fadeOut : fondu de 1.6 s puis Stop. |
| `src/shared/Boss/BossConfig.luau` | Constantes d'UN SEUL type de boss : TAG "Boss", STATE_ATTRIBUTE "BossState", STATES gelés (Idle, Chasing, Attacking, Charging, Staggered, Dead), stats (600 PV, WalkSpeed 14), perception (AGGRO_RANGE 150, THINK_INTERVAL 0.2), corps-à-corps (6 studs, tolérance 1.5, préparation 0.35 s, cooldown 1.4 s, 8 dégâts), attaque fatale (seuil 20 % des PV, charge 1.5 s, cooldown 25 s, stagger 3 s), IDs d'animation, DEBUG_LOGS=tru |
| `src/server/Boss/BossService.luau` | Inscrit tout Model taggé "Boss" sous workspace : PV, vitesse, désancrage de toutes les BaseParts, Animator, deux pistes d'animation chargées côté serveur, Path de PathfindingService (AgentRadius 2, AgentHeight 5, saut autorisé, WaypointSpacing 6), ajout du tag TimeLoopEntity, puis task.spawn(runBoss). La boucle de décision runBoss (l.284-310) choisit dans cet ordre : rewind en cours, puis Idle, puis performUltimate,  |
| `src/client/Boss/BossEffectsController.client.luau` | Suit les Model taggés "Boss" côté client et écoute l'attribut BossState. Charging : sphère invisible "BossChargeSphere" de 18 studs avec particules d'étincelles et de fumée aspirées vers l'intérieur (textures rbxasset intégrées), PointLight rouge pulsée, cœur néon "BossChargeCore" qui grossit de 0.5 à 5 studs en CHARGE_DURATION, Highlight rouge pulsé ; l'effet est posé au pivot du boss au départ de la charge. Stagger |

### Remotes

| Nom | Sens | Charge | Validation serveur |
|---|---|---|---|
| `RequestRewind` | client -> serveur (FireServer depuis TimeLoopController l.63, touche R) | aucun (les arguments éventuels sont ignorés) | TimeLoopService.canRewind (l.113-138), dans l'ordre : session:isRewinding() doit être false ; le personnage doit avoir un Humanoid avec Health > 0 ; si anomalies[player] existe, c'est accepté sans cooldown ; sinon il fau |
| `AnomalyOpened` | serveur -> 1 client (FireClient dans openAnomaly, l.231) | windowDuration: number (ANOMALY_WINDOW = 4 par défaut) ; ignoré par le client (_windowDuration) | n/a (émis par le serveur) |
| `AnomalyClosed` | serveur -> 1 client (FireClient dans closeAnomaly, l.57) | aucun ; émis quelle que soit l'issue (rewind, expiration, CharacterRemoving, PlayerRemoving). Pour un rewind, il part AVANT RewindStarted. | n/a |
| `RewindStarted` | serveur -> tous les clients (FireAllClients, l.156) | playbackDuration: number (REWIND_PLAYBACK_DURATION = 1.5) | n/a |
| `RewindEnded` | serveur -> tous les clients (FireAllClients, l.159) | aucun | n/a |
| `HitConfirmed (réutilisé par le boss)` | serveur -> tous les clients (BossService.performAttack l.215) | (attacker: Model = boss.model, target: Model = target.Character, damage: number = 8) | n/a ; côté client, CombatController l.322 joue l'impact et une secousse si la cible est le joueur local |

### Actif / partiel / mort

- ACTIF : TimeLoopService.start() (Main l.20). L'enregistrement à 10 Hz de tous les personnages joueurs et des Model taggés TimeLoopEntity tourne en permanence dès le démarrage, même sans boss.
- ACTIF : le rewind via R. Avec DEBUG_FREE_REWIND = true (TimeLoopConfig l.24), le rewind HORS anomalie est accepté pour n'importe quel joueur, avec un cooldown global de 3 s. C'est une config de TEST active (le commentaire demande de la passer à false pour le vrai jeu). DEBUG_LOGS=true dans TimeLoopConfig et BossConfig.
- ACTIF : l'anomalie, ouverte UNIQUEMENT par BossService.performUltimate (l.252). Aucun autre appelant d'openAnomaly dans le projet. L'expiration tue réellement (Health = 0, l.68).
- ACTIF : les gardes isInAnomaly/isRewinding consommées par CombatService (attaque, impact, ultime ; dégâts de l'ultime annulés si un rewind démarre pendant le hit-stop, l.377), MovementService (dash interdit), UltimateBehaviors (brûlure interrompue) et BossService.
- ACTIF, sous condition qu'un Model taggé "Boss" existe dans la place : BossService.start() (Main l.23), l'IA complète, l'ultime vers l'anomalie, le stagger, et WorldService.setAnomaly (bascule du ciel pour tous).
- ACTIF : client TimeLoopController, GlitchOverlay (profils anomaly et rewind), TimeLoopAudio (chœur déformé, lassitude) et BossEffectsController (Charging, Staggered).
- PARTIEL / MORT : l'attribut CombatState est lu et restauré mais jamais écrit par le jeu, donc la restauration discrète est inerte.
- PARTIEL / MORT : Snapshot.humanoidState est capturé à chaque snapshot mais jamais réappliqué (commentaire : « conservé pour l'étape combat/animation »).
- MORT : TimeLoopSession.stop() n'est jamais appelée. La valeur de retour de session:rewind() est ignorée (TimeLoopService l.157).
- PARTIEL : le paramètre duration d'openAnomaly n'est jamais fourni (BossService passe seulement target). Le payload windowDuration d'AnomalyOpened est ignoré côté client, donc pas de compte à rebours visible.
- PARTIEL : « Prototype : une seule session globale » (TimeLoopService l.10-11). Le multi-arène n'est pas implémenté ; TimeLoopSession est instanciable mais n'est instanciée qu'une fois.
- CODE MORT DE FAIT : la garde `if not isRewinding` dans AnomalyClosed (TimeLoopController l.81) ne se déclenche jamais sur le chemin du rewind, car le serveur envoie AnomalyClosed AVANT RewindStarted (TimeLoopService l.152-156). Le client fait stop(0.3) puis start("rewind") à la suite (sans conséquence visible, mais le commentaire est faux).
- ABSENT : respawn du boss, récompense ou loot à la mort, effet client de mort (Dead efface seulement les effets), destruction du cadavre, retrait du tag TimeLoopEntity à la mort.
- ABSENT : Signals serveur pour le Time-Loop (rewind démarré/fini, anomalie résolue). shared/Util/Signal.luau existe mais n'est requis par AUCUN fichier. shared/Net/RemoteFolder.luau n'est utilisé par aucun module de Remotes existant.
- ABSENT : phases du boss, plusieurs types de boss (BossConfig ne décrit qu'un boss), IA d'ennemis ordinaires.

### Risques et bugs

- [ÉLEVÉ] Le cadavre est « ressuscité » par le rewind (santé seulement) et un double kill devient possible. EntitySnapshot.capture ignore les entités mortes, mais l'entité reste dans session._entities. Le boss mort n'est jamais retiré : runBoss l.306-309 ne détruit pas le Model et ne retire pas le tag TimeLoopEntity. Un joueur mort reste aussi jusqu'à CharacterRemoving (environ 5 s). À CHAQUE rewind ultérieur, même longtemps après la mort, scrub (TimeLoopSession l.86-110) tombe sur alpha = 0 parce que le dernier snapshot est plus vieux que le curseur, et applyInterpolated (EntitySnapshot l.58-59) réécrit son dernier CFrame vivant et sa Health > 0. Le Humanoid reste en état Dead (Roblox ne ressuscite pas, BossState reste "Dead", l'IA ne redémarre pas), mais Health > 0 suffit pour qu'il redevienne une cible valide : CombatService.getLivingParts plus le tag (onHitReported l.297-303), findUltimateTargets (l.338), SoftLock, et BossService.getTargetParts pour un joueur mort. Conséquences : coups et HitConfirmed sur un cadavre, Tension gagnée (+TENSION_PER_HIT à chaque coup, l.323), et toute future récompense branchée sur HealthChanged <= 0 serait versée deux fois. Humanoid.Died, lui, ne refire pas. Le RootPart du cadavre est aussi ancré puis déplacé à chaque rewind.
- [ÉLEVÉ] Farm de Tension et d'ultimes avec le rewind libre. La Tension (attribut Player) et les cooldowns en os.clock ne sont pas rembobinés, alors que les PV du boss le sont. Boucle possible : frapper le boss, rembobiner (PV du boss restaurés, Tension conservée), recommencer. C'est répétable toutes les 3 s tant que DEBUG_FREE_REWIND = true.
- [ÉLEVÉ, multijoueur] Le rewind est global et déclenchable par n'importe qui. Une seule TimeLoopSession pour tout le serveur. Avec DEBUG_FREE_REWIND = true, tout joueur vivant téléporte TOUS les joueurs (ceux du village, ceux du Hub avatar) et tous les PNJ 5 s en arrière, les fige 1.5 s et fait glitcher tous les écrans (FireAllClients, l.156 et l.159). Le cooldown est global (lastRewindEndClock). Même avec le flag à false, un rewind d'anomalie rembobine tout le serveur.
- [MOYEN] Conflits d'ancrage. AvatarService.freeze/unfreeze (AvatarService.luau l.96-105), l'anomalie (TimeLoopService l.222/228/56), le rewind (TimeLoopSession.freeze/unfreeze l.66-82) et la charge du boss (BossService l.241/269) écrivent tous rootPart.Anchored, chacun avec son propre wasAnchored. Exemple : un joueur dans le Hub au début d'un rewind (wasAnchored=true) qui valide son avatar pendant les 1.5 s ; AvatarService désancre, puis unfreeze du rewind remet Anchored=true et le joueur reste bloqué. Cas inverse : ouvrir le créateur pendant un rewind fait que AvatarService mémorise true.
- [MOYEN] La pause globale pendant une anomalie fausse l'historique. Tant qu'une anomalie est ouverte, les autres joueurs et PNJ continuent de bouger sans être enregistrés. La capture de début de rewind a presque le même timestamp que le dernier snapshot d'avant la pause, donc la relecture les téléporte d'un coup vers leur pose d'avant l'anomalie. Après une expiration, il reste un « trou » spatial entre deux snapshots consécutifs, qui produit une téléportation dans les relectures suivantes.
- [MOYEN] Issue de l'anomalie devinée par polling (BossService.waitForAnomalyOutcome l.219-226) : le boss regarde isRewinding() 0.1 s au plus après la fermeture. Faux positif : l'anomalie expire (joueur mort), puis un autre joueur lance un rewind libre dans les 0.1 s, et le boss se met en Staggered. Faux négatif : un rewind sans yield, quand targetTime == startTime faute d'historique (la boucle l.271 n'itère pas), donne un boss non sonné.
- [MOYEN] Rewind pendant la charge, avant openAnomaly. ultimateReadyClock est déjà consommé (l.236). Si le rewind est encore en cours à la fin de la charge, il n'y a pas d'anomalie : l'ultime est perdu pour 25 s. Le RootPart ancré du boss est déplacé par le scrub vers ses positions passées, alors que l'effet de charge client reste au pivot initial (BossEffectsController l.77) : décalage visuel.
- [MOYEN] Anomalies concurrentes. La table par joueur empêche d'en ouvrir deux sur le même joueur, mais findNearestPlayer n'exclut pas un joueur déjà en anomalie : un deuxième boss qui le vise obtient openAnomaly = false et gaspille son ultime. Un seul rewind ferme TOUTES les anomalies (l.152-154) et sauve tout le monde. La pause d'enregistrement dure tant qu'au moins une anomalie est ouverte. Les expirations restent indépendantes par joueur.
- [FAIBLE] Avec BUFFER_DURATION 6 et REWIND_WINDOW 5, il ne reste qu'environ 1 s d'historique après un rewind. Un rewind d'anomalie, qui ignore le cooldown, lancé dans les secondes suivantes remonte donc moins de 5 s. De plus, getOldestTimestamp (l.148-157) inclut les buffers figés des cadavres.
- [FAIBLE] Une entité ajoutée pendant un rewind (respawn, PNJ taggé) n'est pas gelée, mais unfreeze lui applique wasAnchored = false (valeur par défaut, l.218) : un PNJ volontairement ancré se fait désancrer.
- [FAIBLE] land() (l.113-132) peut appliquer l'état discret d'un snapshot qu'il vient de dépiler, si tout le buffer était plus récent que targetTime.
- [FAIBLE] BossService : unregisterBoss en pleine charge laisse le RootPart ancré (return l.266-268 avant le désancrage). La fin de runBoss pose BossState=Dead même sur un simple dé-tag. Pendant les 3 s de stagger (task.wait l.276) et pendant chase (ComputeAsync, qui yield, puis MoveTo possible juste au début d'un rewind), la boucle ne voit ni la mort ni le rewind. registerBoss désancre aussi le décor ancré volontairement. Le cooldown d'attaque affiche Idle (l.185).
- [FAIBLE] BossEffectsController : untrackBoss ne déconnecte pas GetAttributeChangedSignal (l.180), d'où une fuite, et un re-tag duplique les connexions. Limite Roblox de 31 Highlight par client avec plusieurs boss.
- [FAIBLE] Client : pas de garde ni de limite de débit sur R, et chaque refus serveur est loggé (spam possible avec DEBUG_LOGS). Le compteur « REW » compte toujours jusqu'à -5.0 s même si l'historique réel est plus court. Trois systèmes écrivent camera.FieldOfView (GlitchOverlay, CombatEffects.punchFieldOfView, AvatarCreatorCamera) : un FOV « de repos » faussé est possible si un ultime tombe pendant le glitch.
- [FAIBLE] TimeLoopRemotes crée son dossier sans FindFirstChild : un dossier "TimeLoopRemotes" déjà présent dans la place donnerait des doublons, et le client pourrait attendre le mauvais.

### Identifiants d'assets

- src/shared/TimeLoop/TimeLoopConfig.luau:39 : REWIND_SOUND_ID = "rbxassetid://9125602726", chœur du rewind ("Heavenly Presence Eerie Choral Tones Dark", ProSoundEffects). Marqué explicitement comme PLACEHOLDER dans le commentaire des l.35-38.
- src/shared/TimeLoop/TimeLoopConfig.luau:38 (commentaire seulement) : 9125439864, "Choral Drone Eerie Tones Hollow Reverberant", piste alternative suggérée, non utilisée.
- src/shared/TimeLoop/TimeLoopConfig.luau:54 : "rbxthumb://type=Asset&id=16174602951&w=420&h=420", image de neige cathodique pour GlitchOverlay. PLACEHOLDER (decal gratuit lu par sa miniature, l.52).
- src/shared/TimeLoop/TimeLoopConfig.luau:55 : "rbxthumb://type=Asset&id=15455049436&w=420&h=420", bruit de pixels pour GlitchOverlay. PLACEHOLDER.
- src/shared/Boss/BossConfig.luau:49 : WALK_ANIMATION_ID = "rbxassetid://507777826", R15Walk officielle Roblox (celle du script Animate). Définitif ; un rig R6 échoue silencieusement (pcall, l.90).
- src/shared/Boss/BossConfig.luau:50 : ATTACK_ANIMATION_ID = "rbxassetid://522635514", toolslash R15 officielle ("R15 Sword Slash"). Utilisable telle quelle, mais générique : provisoire pour un boss qui aurait son identité propre.
- src/client/Boss/BossEffectsController.client.luau:29-30 : "rbxasset://textures/particles/sparkles_main.dds" et "rbxasset://textures/particles/smoke_main.dds", textures intégrées au client Roblox (pas des asset IDs). Définitives.

### Ce que le code attend dans la scène

- Au moins un Model taggé "Boss" doit se trouver sous Workspace pour que le boss existe. Aucun boss n'est fourni par le code : tout dépend du fichier de place. Rig R15 attendu (animations R15), avec un Humanoid dont RootPart (HumanoidRootPart) est défini, sinon un warn (l.325). Toutes ses BaseParts sont désancrées à l'inscription, décor compris (l.334-338).
- Le boss doit être sous workspace AU MOMENT où son tag est vu. Un Model cloné depuis ServerStorage puis parenté à Workspace déclenche InstanceAdded et fonctionne. Un Model taggé déplacé (sans Clone) de ServerStorage vers Workspace n'est inscrit ni par BossService (l.318) ni par TimeLoopService (l.81).
- Les PNJ ennemis et rembobinables doivent être des Model taggés "TimeLoopEntity" avec Humanoid et RootPart. Sans Humanoid, ils sont inscrits dans la session mais ignorés par le logger (getParts renvoie nil). Les villageois (tag "Villager") ne sont ni enregistrés ni frappables.
- Un terrain navigable pour PathfindingService, avec un agent de rayon 2 et de hauteur 5 codés en dur (l.352-357). Un boss plus grand se bloquerait ou couperait les coins. Sans chemin trouvé, repli en ligne droite par MoveTo.
- Aucune position codée en dur dans le périmètre. Les distances sont relatives : AGGRO_RANGE 150 (sans test de ligne de vue), ATTACK_RANGE 6 plus une tolérance de 1.5.
- Les personnages joueurs sont enregistrés automatiquement via CharacterAdded. Le respawn Roblox par défaut (CharacterAutoLoads) est supposé : le personnage mort reste dans la session jusqu'à CharacterRemoving.
- Côté client, les GUI et effets sont créés dynamiquement (rien à poser dans StarterGui ni dans Lighting).

## Conventions d'interface et d'architecture client

Audit des conventions d'interface et d'architecture côté client (20 fichiers dans src/client/**, 7 modules *Remotes, Net/RemoteFolder, Input/KeyBindings, Input/KeyboardLayout), tous lus en entier. Les handlers serveur des Remotes ont été vérifiés. Aucun fichier n'a été modifié.

Construction des UI : tout est fait par code. Il n'y a rien dans StarterGui : le sourcemap ne contient aucun StarterGui et les sauvegardes Studio .rbxmx non plus. Chaque fonction se décline en deux modules :
- une Vue (ModuleScript) qui ne contient aucune logique et expose `create(parent): View` avec `export type View` ;
- un Controller (LocalScript) qui anime l'interface et câble les entrées.

Il y a 6 ScreenGui, avec ces DisplayOrder : TensionGui 10, OmenGui 30, WorldMapGui 40, AvatarCreatorGui 50, DialogueGui 60, TimeLoopGlitchGui 100.

Style dark fantasy : les couleurs (fond 6,6,9 ; texte 226,220,208 ; atténué 128,122,114 ; or terni 176,146,96) et les polices (Enum.Font.Garamond, Enum.Font.GothamMedium) sont dupliquées dans 3 vues. Le module Client/UI/Theme annoncé par docs/ARCHITECTURE.md n'existe pas, et Font.new n'est utilisé nulle part. Les tailles mélangent Scale et Offset :
- un seul UIScale réellement adaptatif (AvatarCreatorView), qui ne fait que rétrécir l'interface ;
- un seul UIAspectRatioConstraint (WorldMapView) ;
- aucun UISizeConstraint.

Masquage pendant le Hub : il repose sur l'attribut booléen `IsCustomizing` du Player (AvatarConfig.CUSTOMIZING_ATTRIBUTE), écrit par AvatarService. La doc l'appelle à tort `Customizing`. Il est lu par CombatController, WorldMapController, NPCInteraction et WorldAtmosphere. Il n'est lu ni par TimeLoopController ni par GlitchOverlay. AvatarCreatorController coupe aussi tout le CoreGui pendant le Hub.

Entrées :
- UserInputService partout (clic gauche/E dans CombatController, R dans TimeLoopController, Maj gauche dans DashController, lettre M dans WorldMapController via KeyboardLayout) ;
- ContextActionService uniquement dans le dialogue (NPCInteraction, priorité 3000, qui absorbe aussi E, Maj gauche et la touche de la carte) ;
- F via le ProximityPrompt des villageois.

Le mobile et la manette ne sont pas gérés pour le combat, le dash, le rembobinage ni la carte. Seuls le dialogue (ButtonA, clic plein écran), les ProximityPrompt et les boutons Activated fonctionnent.

Les Remotes suivent deux patrons :
- les 6 modules historiques (getFolder/getRemote, RemoteEvent uniquement) ;
- `Shared/Net/RemoteFolder`, le patron à copier pour les nouveaux systèmes. Il n'est utilisé que par SpawnRemotes, que personne ne require.

KeyBindings (Parade Q/L1, Grimoire J/Select, Interagir F/X) n'est importé nulle part : touches réservées mais non câblées. Tous les fichiers commencent par `--!strict`. Commentaires et textes affichés sont en français, identifiants en anglais.

Principaux risques :
- R est accepté pendant le Hub, côté client comme serveur ;
- avec DEBUG_FREE_REWIND = true, n'importe quel joueur qui appuie sur R déclenche le glitch et le son de rembobinage sur tous les écrans, Hub compris ;
- trois systèmes modifient Camera.FieldOfView ;
- la doc diverge du code (IsCustomizing, UI/Theme, AUDIT.md, UISizeConstraint) ;
- sourcemap.json est périmé.

### Fichiers

| Fichier | Rôle |
|---|---|
| `src/client/AvatarCreator/AvatarCreatorController.client.luau` | Chef d'orchestre du Hub de création. Ouvre le Hub sur OpenCreator : narration INTRO_LINES, caméra, ColorCorrection 'AvatarCreatorColor' et DepthOfField 'AvatarCreatorDepthOfField' dans Lighting, musique 'HubMusic' dans SoundService, StarterGui:SetCoreGuiEnabled(All,false). Gère deux pages : ÉVEIL (7 sélecteurs, PreviewAvatar à chaque clic) et DESTIN (choix de magie). Envoie ApplyAvatar. Referme tout sur CreatorClosed |
| `src/client/AvatarCreator/AvatarCreatorView.luau` | Construit par code le ScreenGui 'AvatarCreatorGui' (DisplayOrder 50, IgnoreGuiInset true, ResetOnSpawn false, ZIndexBehavior Sibling, Enabled false). Contenu : un CanvasGroup 'Panel' à droite (34 % de la largeur), un dégradé 'Shade', 'Content' avec UIScale = min(1, AbsoluteSize.Y/640), les pages AppearancePage/DestinyPage et le voile 'Fade' avec IntroLabel. Aucune logique. |
| `src/client/AvatarCreator/AvatarCreatorCamera.luau` | Caméra Scriptable du Hub : FOV 40, décalage latéral, travelling avant (Quart Out), légère respiration verticale. BindToRenderStep('AvatarCreatorCamera', Camera+1). Rétablit le FOV sauvegardé et CameraType.Custom à l'arrêt. |
| `src/client/Boss/BossEffectsController.client.luau` | Effets locaux des boss. Suit le tag CollectionService 'Boss' et l'attribut 'BossState' du Model. État Charging : particules, cœur Neon, PointLight et Highlight rouges. État Staggered : Highlight pâle. Pas d'UI. C'est le patron à reprendre pour les futurs effets pilotés par tag et attribut (une table de nettoyage par Model). |
| `src/client/Combat/CombatController.client.luau` | Combat côté client : - combo au clic gauche (UserInputService.InputBegan, CombatConfig.ATTACK_INPUT = MouseButton1, avec mémorisation d'un clic) ; - soft-lock, SpatialHitbox, puis ReportHit ; - ultime sur la touche E (CombatConfig.ULTIMATE_INPUT) ; - jauge de Tension (attribut 'Tension') et invite '[E] <ultimateName>' à la couleur palette.glow ; - masquage de TensionGui pendant le Hub (attribut IsCustomizing, L273-28 |
| `src/client/Combat/CombatEffects.luau` | VFX du combat, tous locaux : traînée de lame, impact (Highlight et étincelles), hit-stop, secousse caméra (RenderStep 'CombatCameraShake' à Camera+1), coup de FOV, ColorCorrection 'CombatColorCorrection', dossier Workspace 'CombatEffects'. Chorégraphie d'ultime commune, teintée par la palette de la magie. |
| `src/client/Combat/SoftLock.luau` | Visée assistée : trouve l'ennemi le plus proche (tag 'TimeLoopEntity', plus les joueurs si PVP_ENABLED) et oriente le RootPart à plat vers lui. |
| `src/client/Combat/SwingAnimator.luau` | Charge (avec cache par Animator) et joue l'animation d'un coup du COMBO, priorité Action. |
| `src/client/Combat/TensionView.luau` | Construit le ScreenGui 'TensionGui' (DisplayOrder 10, ResetOnSpawn false, ZIndexBehavior Sibling, IgnoreGuiInset non défini donc false, Enabled true par défaut). Container de 340x52 px en Offset, centré en bas à 36 px du bord. Barre de 10 px, dégradé violet. Aucune logique. |
| `src/client/Movement/DashController.client.luau` | Dash sur Maj gauche (MovementConfig.DASH_INPUT), via UserInputService. Applique une LinearVelocity locale sur le HRP et un Trail 'DashTrail', puis envoie RequestDash. Joue aussi la traînée des autres joueurs (DashStarted). Ne lit pas IsCustomizing : il refuse si le RootPart est ancré, ce qui est le cas pendant le Hub. |
| `src/client/NPC/DialogueView.luau` | Construit le ScreenGui 'DialogueGui' (DisplayOrder 60, IgnoreGuiInset true, ResetOnSpawn false, Sibling, Enabled false). Contenu : un TextButton plein écran 'ClickCatcher', une Box de UDim2.new(0.62,0,0,150) à 96 px du bas, NamePlate, Line et Hint. Aucune logique. |
| `src/client/NPC/NPCInteraction.client.luau` | Dialogue avec les villageois : - ProximityPrompt local 'TalkPrompt' sur les Models taggés 'Villager' (touche F via DialogueConfig.INTERACT_KEY ; GamepadKeyCode non défini, donc ButtonX par défaut) ; - texte affiché lettre par lettre avec un son 'DialogueBlip' ; - contrôles du joueur désactivés (PlayerModule:GetControls():Disable()) ; - deux actions ContextActionService : DialogueAdvance (F, Espace, Entrée, ButtonA) e |
| `src/client/TimeLoop/GlitchOverlay.luau` | Rupture de réalité à l'écran. Construit le ScreenGui 'TimeLoopGlitchGui' (DisplayOrder 100, IgnoreGuiInset true, ResetOnSpawn false, Enabled false, ZIndexBehavior non défini). Couches : neige (ImageLabel en mosaïque), tranches, flash, Message (Enum.Font.GothamBlack, rouge 255,70,70) et Caption (Enum.Font.Code). Crée aussi 'TimeLoopColorCorrection' et 'TimeLoopBlur' dans Lighting, et fait trembler le FOV. Une seule bo |
| `src/client/TimeLoop/TimeLoopAudio.luau` | Chœur du rembobinage 'TimeLoopRewindSound' dans SoundService, avec PitchShift, variations aléatoires et lassitude (volume réduit quand les rembobinages se rapprochent). |
| `src/client/TimeLoopController.client.luau` | Touche R (TimeLoopConfig.REWIND_KEY) via UserInputService, puis RequestRewind. Met en scène AnomalyOpened/Closed et RewindStarted/Ended avec GlitchOverlay et TimeLoopAudio. Compteur '<< REW -x.x s'. Ne vérifie pas IsCustomizing. |
| `src/client/World/AmbientParticles.luau` | Volume invisible 'AmbientParticleVolume' (Workspace) qui suit la caméra, avec trois émetteurs : dust, fireflies, embers. |
| `src/client/World/LightingPresets.luau` | Préréglages de lumière DAY, DAWN, DUSK, NIGHT et ANOMALY, avec des KEYFRAMES horaires et l'interpolation entre eux. |
| `src/client/World/WorldAtmosphere.client.luau` | Rendu de l'état du monde : Lighting, Atmosphere, Terrain.Clouds, et les effets 'WorldColorCorrection', 'WorldBloom', 'WorldSunRays', 'WorldOmenVeil'. Gère le vent, les sons 'WorldAnomalyDrone' et 'WorldWind', et les particules. Lit les attributs 'WorldMood' et 'WorldWeather' du Workspace. Crée le ScreenGui 'OmenGui' (DisplayOrder 30, IgnoreGuiInset true, ResetOnSpawn false, Enabled true, ZIndexBehavior non défini). L |
| `src/client/World/WorldMapController.client.luau` | Carte du monde. S'ouvre et se ferme avec la touche portant la LETTRE 'M' (KeyboardLayout.isLetter, clavier uniquement). Refuse d'ouvrir si gameProcessed ou si IsCustomizing est vrai ; ferme même si gameProcessed. Gère la sélection des continents et le pied de carte (heure et météo). |
| `src/client/World/WorldMapView.luau` | Construit le ScreenGui 'WorldMapGui' (DisplayOrder 40, IgnoreGuiInset true, ResetOnSpawn false, Sibling, Enabled false). Contenu : un TextButton 'Backdrop' qui absorbe les clics et un CanvasGroup 'Sheet' (Scale 0.86, UIAspectRatioConstraint 1.6, UIScale 0.94). Style parchemin, polices GrenzeGotisch et Fondamento, tout en Scale avec TextScaled et UITextSizeConstraint. |
| `src/shared/Avatar/AvatarRemotes.luau` | Dossier ReplicatedStorage.AvatarRemotes et 4 RemoteEvent du Hub. |
| `src/shared/Combat/CombatRemotes.luau` | Dossier ReplicatedStorage.CombatRemotes et 6 RemoteEvent. La Tension ne transite par aucun Remote : c'est un attribut. |
| `src/shared/Movement/MovementRemotes.luau` | Dossier ReplicatedStorage.MovementRemotes. |
| `src/shared/NPC/NPCRemotes.luau` | Dossier ReplicatedStorage.NPCRemotes. |
| `src/shared/TimeLoop/TimeLoopRemotes.luau` | Dossier ReplicatedStorage.TimeLoopRemotes. |
| `src/shared/World/WorldRemotes.luau` | Dossier ReplicatedStorage.WorldRemotes. La météo et l'humeur passent par des attributs du Workspace. |
| `src/shared/World/SpawnRemotes.luau` | Déclare les Remotes de l'arrivée dans le monde, pour un futur SpawnService : ArrivalCinematic et CreatorStageReady. |
| `src/shared/Net/RemoteFolder.luau` | Côté serveur : FindFirstChild ou création du dossier dans ReplicatedStorage et des objets dedans. Côté client : WaitForChild avec un avertissement après 30 s, puis attente sans fin. Gère RemoteEvent, UnreliableRemoteEvent et RemoteFunction. |
| `src/shared/Input/KeyBindings.luau` | Touches des nouveaux systèmes : Parry (KeyCode.Q, manette ButtonL1), Grimoire (lettre 'J', secours KeyCode.J, manette ButtonSelect), Interact (KeyCode.F, ButtonX). Constantes PROMPT_KEY et PROMPT_GAMEPAD_KEY. |
| `src/shared/Input/KeyboardLayout.luau` | Résout une LETTRE imprimée en KeyCode, quelle que soit la disposition du clavier (AZERTY : la touche M envoie KeyCode.Semicolon). Passe par UserInputService:GetStringForKeyCode dans un pcall. |

### Remotes

| Nom | Sens | Charge | Validation serveur |
|---|---|---|---|
| `OpenCreator` | serveur -> 1 client (AvatarService.openCreator L119) | () | Sans objet (envoyé par le serveur). Côté client, open() : un deuxième appel alors que le Hub est ouvert renvoie seulement l'aperçu (cas d'une réapparition). |
| `PreviewAvatar` | client -> serveur | (selection: Selection), une table de 8 nombres : baseIndex, faceIndex, markIndex, hairIndex, outfitIndex, heightScale, widthScale, magicIndex | AvatarSerializer.sanitizeSelection :
- type table ;
- index entiers dans [1, #options] ;
- échelles numériques, NaN refusé, bornées par math.clamp.
Puis état du joueur : state.isCustomizing vrai et isConfirmPending faux. |
| `ApplyAvatar` | client -> serveur | (selection: Selection) | Même validation que PreviewAvatar. Ensuite : publishMagic (attribut InnateMagic), sauvegarde du profil en arrière-plan, puis closeCreator quand l'application est terminée. |
| `CreatorClosed` | serveur -> 1 client (AvatarService.closeCreator L127) | () | Sans objet. Côté client : close(), avec fondu au noir et rétablissement du CoreGui. |
| `RequestAttack` | client -> serveur | (comboIndex: number) | CombatService.onAttackRequested L163 :
- type number et COMBO[comboIndex] existant ;
- personnage vivant ;
- hors combat interdit (isCustomizing, isInAnomaly, isRewinding) ;
- enchaînement vérifié par isComboStepAllowed  |
| `ReportHit` | client -> serveur | (target: Model) | CombatService.onHitReported L276 :
- typeof Instance et IsA Model ;
- une attaque en cours et un attaquant vivant, hors anomalie ou Hub ;
- dans la fenêtre hitStart/hitEnd, à la tolérance près ;
- cible différente de l'a |
| `RequestUltimate` | client -> serveur | () | CombatService.onUltimateRequested L349 :
- personnage vivant, hors combat interdit ;
- Tension >= TENSION_MAX ;
- Tension remise à 0 avant tout le reste ;
- magie lue dans l'attribut serveur InnateMagic. |
| `AttackStarted` | serveur -> autres clients (FireClient en boucle, CombatService L191) | (attacker: Model, comboIndex: number) | Sans objet. Côté client (CombatController L309) : vérifie que le coup et l'épée existent, puis task.wait(hitStart) et traînée de lame. |
| `HitConfirmed` | serveur -> tous les clients (CombatService L324, BossService L215) | (attacker: Model, target: Model, damage: number) | Sans objet. Côté client (L322) : ignoré si l'attaquant est le joueur local ; la caméra tremble si la cible est le joueur local. |
| `UltimateFired` | serveur -> tous les clients (CombatService L369) | (caster: Model, origin: Vector3, targets: { Model }, magicId: string) | Sans objet. Côté client (L331) : vérifie typeof(origin) == 'Vector3' et type(targets) == 'table'. |
| `RequestDash` | client -> serveur | () | MovementService.onDashRequested :
- canAct : vivant, et ni Hub, ni anomalie, ni rembobinage ;
- délai de recharge : DASH_COOLDOWN - LATENCY_TOLERANCE.
Ouvre la fenêtre isDashing (invulnérabilité de 0,3 s). |
| `DashStarted` | serveur -> autres clients | (character: Model) | Sans objet. Côté client : `if character then playDashTrail`. |
| `TalkStarted` | client -> serveur | (villager: Model) | VillagerService.onTalkStarted L140 :
- typeof Instance ;
- doit être un villageois enregistré (tag Villager) ;
- HRP du joueur présent ;
- distance <= INTERACT_DISTANCE (10) + 6.
Aucune vérification de IsCustomizing côté |
| `TalkEnded` | client -> serveur | () | Aucune nécessaire : libère seulement talkingWith[player]. |
| `RequestRewind` | client -> serveur | () | TimeLoopService.canRewind L113 :
- pas de rembobinage en cours ;
- joueur vivant ;
- en anomalie : toujours accepté ;
- sinon : DEBUG_FREE_REWIND requis (actuellement true) et REWIND_COOLDOWN.
Ne vérifie PAS AvatarServic |
| `AnomalyOpened` | serveur -> 1 client (TimeLoopService.openAnomaly L231, appelé par BossService L252) | (windowDuration: number) | Sans objet. Côté client : la durée est ignorée (_windowDuration) ; GlitchOverlay en profil 'anomaly'. |
| `AnomalyClosed` | serveur -> 1 client | () | Sans objet. |
| `RewindStarted` | serveur -> TOUS les clients | (playbackDuration: number) | Sans objet. Côté client : glitch 'rewind', son et compteur, pour tout le monde, y compris les joueurs dans le Hub. |
| `RewindEnded` | serveur -> tous les clients | () | Sans objet. |
| `Omen` | serveur -> tous les clients (WorldService L68) | (text: string) | Sans objet. Côté client : ignoré si IsCustomizing est vrai ou si un présage est déjà affiché. |
| `ArrivalCinematic` | serveur -> client (prévu) | (cameraCFrame: CFrame, focus: Vector3, regionName: string) | MORT : aucun émetteur, aucun récepteur. Le dossier n'est jamais créé, car personne ne require SpawnRemotes côté serveur. |
| `CreatorStageReady` | serveur -> client (prévu) | (stageCFrame: CFrame, cameraCFrame: CFrame?) | MORT : aucun émetteur, aucun récepteur. |

### Actif / partiel / mort

- ACTIFS et câblés de bout en bout : - Hub de création (AvatarCreatorController, View et Camera, avec AvatarRemotes et AvatarService) ; - combat (CombatController, CombatEffects, SoftLock, SwingAnimator, TensionView, avec CombatRemotes) ; - dash (DashController et MovementRemotes) ; - dialogue (NPCInteraction, DialogueView, NPCRemotes) ; - Time-Loop (TimeLoopController, GlitchOverlay, TimeLoopAudio, TimeLoopRemotes) ; - monde (WorldAtmosphere, AmbientParticles, LightingPresets, WorldRemotes.Omen) ; - carte (WorldMapController et WorldMapView, purement locale) ; - effets de boss (BossEffectsController).
- ACTIF : Shared/Input/KeyboardLayout (utilisé par la carte et par l'absorption de touches du dialogue).
- MORT ou PRÉVU, non câblé : - Shared/Input/KeyBindings : aucun require ; Parade sur Q, Grimoire sur J et Interagir sur F restent théoriques ; - Shared/World/SpawnRemotes : aucun require, ni serveur ni client ; SpawnService n'existe pas ; - Shared/Net/RemoteFolder : utilisé seulement par SpawnRemotes, donc jamais exécuté.
- MORT ou PRÉVU, autres modules partagés : - Shared/Util/Signal n'est requis nulle part ; - Shared/Data/DataConfig, World/RegionConfig, World/MechanismConfig et World/EchoConfig ne sont requis par aucun script client ; - RegionConfig n'est utilisé que par WorldBuilder, lui-même jamais requis par Main.server.luau.
- ABSENTS bien que décrits dans docs/ARCHITECTURE.md (§2 Client) : Client/UI/Theme, State/PlayerStateClient, UI/Hud, UI/Grimoire, MissionBoardView, GuildView, PartyView, Combat/ParryController, Enemy/EnemyEffectsController, World/EchoRenderer, RegionAmbience, MechanismEffects. docs/AUDIT.md, cité en L5, n'existe pas.
- PARTIEL : - CombatEffects.ULTIMATE_PLAYERS (L500) est vide : les 5 ultimes jouent playEruption avec leur palette ; - WorldMapConfig : images vides, dessin par défaut ; - WIND_SOUND_ID vide, donc aucun son de vent.
- DEBUG actifs : TimeLoopConfig.DEBUG_FREE_REWIND = true (R utilisable partout) ; DEBUG_LOGS = true dans CombatConfig, MovementConfig, TimeLoopConfig, WorldMapConfig (print au démarrage de la carte) et BossConfig.
- Les sauvegardes dans backups/studio-export-2026-10-14 sont hors de l'arbre Rojo : ce sont d'anciennes versions. NPCInteraction et WorldMapController y sont antérieurs à KeyboardLayout, et des noms d'instance y portent des espaces finaux.

### Risques et bugs

- Le rembobinage est accepté pendant le Hub. TimeLoopController (L58-65) ne teste pas IsCustomizing, et le serveur TimeLoopService.canRewind (L113-138) ne teste pas AvatarService.isCustomizing. Avec DEBUG_FREE_REWIND = true, un joueur dans le Hub peut rembobiner toute la session, y compris son propre personnage figé.
- RewindStarted et RewindEnded sont envoyés à tous les clients (TimeLoopService L156 et L159), et GlitchOverlay (DisplayOrder 100) ne vérifie pas IsCustomizing. Un rembobinage déclenché par n'importe qui pendant DEBUG_FREE_REWIND affiche donc le glitch, le chœur et le compteur sur tous les écrans, par-dessus le Hub (DisplayOrder 50) et sa narration.
- Trois systèmes modifient Camera.FieldOfView : - AvatarCreatorCamera sauvegarde puis restaure le FOV (40) ; - CombatEffects.punchFieldOfView mémorise un restingFieldOfView ; - GlitchOverlay mémorise un baseFieldOfView. Un ultime pendant un glitch, ou l'inverse, peut mémoriser un FOV déjà modifié et le rétablir de travers. Deux BindToRenderStep tournent aussi à la même priorité Camera+1 ('AvatarCreatorCamera' et 'CombatCameraShake').
- À la fermeture du Hub, AvatarCreatorController L289 appelle `StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)`, ce qui réactive TOUT le CoreGui. Un futur HUD qui masquerait Backpack, PlayerList ou Health serait écrasé.
- La doc diverge du code : docs/ARCHITECTURE.md §1 nomme l'attribut `Customizing` alors que le code utilise 'IsCustomizing' (AvatarConfig L219). Elle impose aussi `Client/UI/Theme` et UISizeConstraint, qui n'existent pas, et renvoie à docs/AUDIT.md, absent.
- La palette et les polices sont dupliquées dans trois vues, plus WorldAtmosphere. Le helper `new()` est dupliqué dans GlitchOverlay et WorldMapView. Sans module Theme, toute nouvelle UI risque une dérive de style.
- UI peu adaptative : - TensionGui est entièrement en Offset (340x52), sans UIScale ; - la boîte de dialogue mesure 150 px de haut avec un texte de 25 px fixe ; - le présage a un TextSize 32 fixe dans une zone de 0.8x0.08, sans TextWrapped ni TextScaled, donc débordement possible sur petit écran ; - l'UIScale du Hub ne fait que réduire et ne tient compte que de la hauteur : sur mobile en portrait, le panneau à 34 % de la largeur devient très étroit ; - ScreenInsets et la zone sûre ne sont jamais gérés.
- Pas de support du mobile ni de la manette pour les actions principales : - CombatController ne teste que MouseButton1 (L294) ; - la carte exige UserInputType.Keyboard (L139) ; - aucun bouton ContextActionService tactile ; - le texte d'aide du dialogue est écrit en dur, '[F] ou clic : continuer' (NPCInteraction L132), sans dériver de Config.INTERACT_KEY ni s'adapter à la manette ou au tactile.
- Quand la carte est ouverte, son fond absorbe les clics (pas d'attaque), mais E, Maj gauche et R restent actifs : on peut lancer l'ultime, dasher ou rembobiner carte ouverte. Un ProximityPrompt (F) peut aussi ouvrir un dialogue (DisplayOrder 60) par-dessus la carte (40).
- Grimoire prévu sur la manette ButtonSelect (KeyBindings L37) : ce bouton bascule par défaut la navigation d'UI de Roblox (GuiService.AutoSelectGuiEnabled). Conflit à traiter (désactiver AutoSelectGuiEnabled ou absorber l'entrée via ContextActionService).
- Maj gauche (dash) entre en conflit avec le Shift Lock de Roblox tant que StarterPlayer.EnableMouseLockOption n'est pas décoché (réglage manuel, MovementConfig L8-9).
- RemoteFolder.getOrCreate (L58-70) : si un enfant porte déjà le même nom avec une autre classe, un doublon de même nom est créé. Le WaitForChild du client peut alors renvoyer la mauvaise instance, castée sans vérification.
- Patron historique : le serveur crée toujours un nouveau Folder sans FindFirstChild. Un second require dans un autre environnement Luau (Actor) créerait des dossiers en double. Le client utilise WaitForChild sans délai maximal : il bloque silencieusement (seul l'avertissement 'Infinite yield' de Roblox apparaît) si le serveur ne require pas le module.
- SpawnRemotes est déclaré mais personne ne le require. Si un script client le require avant qu'un service serveur ne le fasse, le client attend sans fin (avec un avertissement à 30 s).
- sourcemap.json est périmé (il ne contient ni KeyBindings ni SpawnRemotes) : luau-lsp peut mal résoudre les types. Il est ignoré par git et se régénère avec `rojo sourcemap`.
- Dans la sauvegarde Studio (eae1db5d-StarterPlayer-StarterPlayerScripts.rbxmx), des instances portent des espaces finaux : 'BossEffectsController   ', 'WorldMapView   ', 'NPCInteraction '. Dans cet état, `script.Parent:WaitForChild("WorldMapView")` bloquerait indéfiniment. Vérifier que la synchronisation Rojo a bien remplacé ces instances et qu'il ne reste pas de doublons.
- Les attributs posés par le serveur à PlayerAdded (IsCustomizing = true) peuvent arriver après l'exécution des LocalScripts. TensionGui peut alors apparaître brièvement avant d'être masquée par le signal de changement.
- TimeLoopController.client.luau est à la racine de Client alors que ses modules sont dans Client/TimeLoop : rangement incohérent avec les autres systèmes (un dossier par système).
- Le pied de la carte affiche la LETTRE '[M]', ce qui est correct. En revanche l'invite d'ultime affiche `Config.ULTIMATE_INPUT.Name`, c'est-à-dire le nom du KeyCode et non le libellé du clavier. Sans conséquence pour E, mais une future touche placée près du bloc de déplacement (Q pour la parade) devra passer par KeyboardLayout.getLabel.

### Identifiants d'assets

- Musique du Hub : src/shared/Avatar/AvatarConfig.luau:225, HUB_MUSIC_ID = 'rbxassetid://1839911004' ('Nursery Crime 60', APM). Lue par AvatarCreatorController L72 ('HubMusic'). Provisoire (commentaire >>> MUSIQUE DU HUB).
- Chœur du rembobinage : src/shared/TimeLoop/TimeLoopConfig.luau:39, REWIND_SOUND_ID = 'rbxassetid://9125602726'. Lu par TimeLoopAudio L36. Provisoire.
- Images de glitch : src/shared/TimeLoop/TimeLoopConfig.luau:54-55, 'rbxthumb://type=Asset&id=16174602951&w=420&h=420' et '...id=15455049436...' (neige). Lues par GlitchOverlay L152-163. Provisoires.
- Bourdon d'anomalie : src/shared/World/WorldConfig.luau:81, ANOMALY_DRONE_ID = 'rbxassetid://9043359885' ('DARK DRONE 13'). Lu par WorldAtmosphere L94. Provisoire.
- src/shared/World/WorldConfig.luau:85 : WIND_SOUND_ID = '' (emplacement vide, son de vent désactivé).
- Animations d'épée : src/shared/Combat/CombatConfig.luau:26-27, 'rbxassetid://522635514' (R15 Sword Slash) et 'rbxassetid://522638767' (R15 Sword Lunge), animations officielles Roblox. Jouées par SwingAnimator L66.
- Son des dialogues : src/shared/NPC/DialogueConfig.luau:96, BLIP_SOUND_ID = 'rbxasset://sounds/electronicpingshort.wav' (fourni avec le client). Lu par NPCInteraction L48.
- Textures de particules fournies avec le client : 'rbxasset://textures/particles/sparkles_main.dds' et 'smoke_main.dds', dans BossEffectsController L29-30, CombatEffects L30-31 et AmbientParticles L14 (sparkles seulement). Définitives.
- Emplacements vides de la carte : src/shared/World/WorldMapConfig.luau:136 PARCHMENT_IMAGE = '', plus `image = ''` et `illustration = ''` pour chacun des 5 continents (L49-50, L66-67, L82-83, L98-99, L114-115). Remplacés par un dessin par code ; le texte 'Illustration à venir' s'affiche.
- Catalogue du Hub, src/shared/Avatar/AvatarConfig.luau : bundles (L104-117), visages (L122-126), marques en rbxthumb (L154-160), coiffures (L165-186), tenues et capes (L193-209). Tous déclarés PLACEHOLDERS (L16). 'curse_seal' 16324571137 (L160) est à remplacer avant publication. Côté client, seuls les noms et les compteurs sont lus ; les ID sont appliqués par le serveur (AvatarAppearance).
- Aucun ID d'asset dans les modules Remotes, ni dans les vues (aucune image d'UI : tout est fait avec des Frames, UIStroke, UIGradient et des polices).

### Ce que le code attend dans la scène

- Aucune UI dans StarterGui : les 6 ScreenGui sont créés par les LocalScripts dans PlayerGui, avec ResetOnSpawn=false.
- Le Workspace contient des Models taggés 'Villager' (rig avec HumanoidRootPart, PrimaryPart ou au moins une BasePart) et 'Boss' (rig R15, BossService ajoute TimeLoopEntity et BossState).
- Personnage R15 avec Humanoid, Animator et HumanoidRootPart. Il porte un Model 'Sword' (créé par SwordFactory côté serveur) contenant un Trail 'BladeTrail' en descendant (CombatEffects.playBladeTrail).
- PlayerScripts.PlayerModule (celui de Roblox) doit exister : NPCInteraction appelle GetControls() pour immobiliser le joueur pendant un dialogue.
- Le Terrain est requis : WorldAtmosphere L84 le caste en Instance et y crée ou récupère 'Clouds'.
- Réglages Studio manuels : Lighting.Technology = Future (WorldAtmosphere, en-tête) et StarterPlayer.EnableMouseLockOption décoché pour que Maj gauche ne serve qu'au dash (MovementConfig L8-9).
- Instances locales créées par le client (noms à ne pas réutiliser) : - Workspace : Folder 'CombatEffects', Part 'AmbientParticleVolume', Parts 'BossChargeSphere' et 'BossChargeCore' ; - Lighting : 'AvatarCreatorColor', 'AvatarCreatorDepthOfField', 'CombatColorCorrection', 'TimeLoopColorCorrection', 'TimeLoopBlur', 'WorldColorCorrection', 'WorldBloom', 'WorldSunRays', 'WorldOmenVeil', plus Atmosphere (récupérée ou créée) ; - SoundService : 'HubMusic', 'DialogueBlip', 'TimeLoopRewindSound', 'WorldAnomalyDrone', 'WorldWind' ; - sur le HRP : 'DashTrail', 'DashTrailTop', 'DashTrailBottom', 'DashAttachment', 'DashVelocity'.
- Noms RenderStep : 'AvatarCreatorCamera' et 'CombatCameraShake', tous deux à Enum.RenderPriority.Camera.Value + 1. Actions ContextActionService : 'DialogueAdvance' et 'DialogueSink' (priorité 3000).
- Aucune coordonnée codée en dur côté client : la caméra du Hub se place par rapport au HRP, la carte du monde en fractions (WorldMapConfig). Les seules valeurs en pixels sont celles des UI (TensionGui 340x52 à 36 px du bas, Box du dialogue à 96 px du bas, légende du glitch à (36,28)).
- Le chemin client suppose ReplicatedStorage.Shared/<Système>/<Module>, avec des WaitForChild en chaîne. Un module absent du Studio synchronisé bloque le script indéfiniment : la sauvegarde du 2026-10-14 n'avait ni Shared/Input, ni Net, ni Util, ni Data.
- Les ProximityPrompt des villageois sont créés localement par le client (pas par le serveur), parentés au HRP, sous le nom 'TalkPrompt'.
