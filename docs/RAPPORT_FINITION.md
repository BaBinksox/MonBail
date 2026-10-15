# Les Échos du Néant — Rapport de la passe de finition et d'intégration

Date : 15 octobre 2026. Dépôt : branche `main`, du commit `9840b99` (état laissé par les agents
interrompus) au dernier commit de cette passe.

**Ce qui a été réellement exécuté :** analyse statique (types stricts, graphe des `require`), et des
**simulations** du moteur Roblox écrites pour le projet (`tools/sim`). **Aucun essai dans Roblox Studio
n'a été possible** depuis cet environnement : rien dans ce rapport ne prétend le contraire. Les points
qui ne peuvent se vérifier que dans Studio sont listés en section 5.

---

## 1. État des fonctionnalités

### Terminées (code complet, intégré, vérifié en simulation)

| Domaine | Ce qui fonctionne |
|---|---|
| Démarrage | `Main.server` démarre les 25 services dans un ordre cohérent, chacun protégé (un service en échec n'arrête pas les autres). Aucun cycle de chargement. Remotes créés avant usage. |
| Sauvegarde | `ProfileStore` : `UpdateAsync` + verrou de session, autosauvegarde, `BindToClose`, migration v1 → v2 avec copie de l'ancien profil. Départ pendant une sauvegarde et panne du DataStore testés : rien de ce qui était sauvegardé n'est perdu, le joueur peut revenir. |
| Créateur de personnage | Introduction narrative + musique, 7 catégories (Corps, Visage, Cicatrices et tatouages, Chevelure, Tenue, Proportions — taille et carrure —, Destin = pouvoir), aperçu serveur en direct, caméra dédiée et rotation, récapitulatif, confirmation **une seule fois** (double clic + Entrée testés), sauvegarde, cinématique d'arrivée au belvédère, restauration au respawn et à la reconnexion (le créateur ne se rouvre pas). |
| Six pouvoirs | Antimatière, Pyromancie, Foudre, Glace, Ombre et **Gravité (6e, confirmée)** : ultime de combat côté serveur, et chacun a son mécanisme du monde (voile du mausolée, trois braseros → Sanctuaire des Flammes, conduit → herse de la tour, mur sans ombre → alcôve, étang gelé → îlot, bloc gravé → corniche). Un mécanisme ne répond qu'à sa magie et revient seul à son état initial. |
| Carte (Région 1) | Générateur **idempotent** (2e construction : 8 242 → 8 242 descendants, un seul `World`). Village des Cendres réellement construit (place de l'Horloger, 14 maisons, taverne, forge, tableaux, puits aux runes + escalier vers la crypte, Salle des Serments + Archives, portes, cimetière + mausolée), chapelle et clocher, crypte, cour d'entraînement + Cercle du Gardien, début de la Forêt des Murmures (ravin, pont, clairière, sanctuaire, étang, tour, ruines, grotte), rives et Portail Englouti. **Contrat complet** : toutes les ancres, interactables, objets dynamiques et trajets d'échos, sans doublon. 7 619 Parts, 34 lumières (budget 58). Rendus : `docs/renders/`. |
| Quête « La Cloche Muette » | Parcours complet testé : dialogue d'Aldric, trois indices, écho d'Odile, runes du puits (3-1-4-2, une erreur éteint tout), crypte, Veilleur de Cendre, battant, retour par l'échelle, cloche, récompense **unique** (clé `quest:bell_silent`), reconnexion sans perte ni double paiement. |
| Temps | Écho exploitable (il montre l'ordre des runes), ancre temporelle du pont (R → le pont redevient praticable 15 s), rembobinage par rencontre de boss : participants identifiés, anomalie sur l'un d'eux, rembobinage pour tous les participants, pas de résurrection du boss mort ni de double récompense. |
| Combat | Parade parfaite (client : A en AZERTY / Q en QWERTY, L1, bouton tactile ; serveur : fenêtre + compensation de latence), ennemis distincts (Rôdeur, Gardien de Pierre, Murmure, Veilleur élite, mannequins, boss) avec télégraphes au sol visibles et barres de vie, récompenses par participation (deux joueurs crédités pour le même ennemi). |
| Progression | Rang d'aventurier sauvegardé, XP, réputation, découvertes, inventaire. |
| Contrats | Tableau du village : accepter, abandonner, rendre ; objectifs kill / item / explore / echo / mechanism / examine ; contrats quotidiens et hebdomadaires à clé de cycle ; contrat de groupe refusé à un joueur seul ; récompense une seule fois par cycle. |
| Groupes | Invitation, acceptation, chef, exclusion ; contrats coopératifs crédités à chaque membre. |
| Guildes | Création, **nom unique** (insensible à la casse), invitations, rôles et permissions vérifiés côté serveur, modifications concurrentes de deux officiers sans perte, exclusion avec réconciliation du profil, contrats collectifs. DataStores **et messagerie inter-serveurs** isolés de la production dans Studio (préfixe `TEST_`). |
| Interfaces | HUD (rang, suivi de quête, notifications, panneau de lecture des textes examinés), Grimoire (J / croix haut / bouton tactile : Journal, Contrats, Compagnons, Progression + inventaire), invites réservées à une autre magie masquées, ambiance de la région (crypte, forêt, lac). |

### Partielles

| Élément | Ce qui manque |
|---|---|
| Guildes entre serveurs | Le code est complet (écritures `UpdateAsync`, messagerie `MessagingService`), mais la simulation ne fait tourner **qu'un serveur** : la propagation réelle entre deux serveurs est à tester dans un jeu publié. |
| Accessibilité physique de la carte | Positions, hauteurs et contrat vérifiés ; la physique (marches, rampes, sauts, collisions) ne peut l'être qu'en jouant dans Studio. |
| Interfaces | Fonctionnelles et testées par leurs boutons en simulation, mais **jamais vues à l'écran** : mise en page à valider dans Studio (ordinateur, téléphone, manette). |
| Sons | Aucun son pour les nouveaux systèmes : aucun identifiant d'asset n'a été inventé. La musique du créateur reprend votre `HUB_MUSIC_ID`. |
| Ombres portées | 0 des 5 lumières à ombres autorisées sont utilisées (rendu correct mais moins dramatique). |

### Absentes

- Panneau d'options (volume, taille de l'interface) : le Remote `UpdateSettings` existe côté serveur, pas l'interface.
- Intérieur de la Cathédrale Engloutie et rangs B, A, S : volontairement « à venir » (le portail le dit au joueur).

---

## 2. Fichiers créés et modifiés pendant cette passe (`git diff 9840b99..HEAD`)

**Créés — jeu :**
`src/server/World/{SpawnService, InteractionService, EchoService}`, `src/server/Mission/MissionService`,
`src/server/WorldBuild/{Forest, CathedralShore}`, `src/shared/Mission/{MissionDefinitions, MissionRemotes}`,
`src/shared/World/EchoRemotes`, `src/client/World/EchoRenderer.client`, `src/client/State/PlayerState`,
`src/client/UI/{HudController.client, Grimoire.client}`, `src/client/Combat/ParryController.client`,
`src/client/Enemy/EnemyEffectsController.client`.

**Modifiés — jeu :**
`src/server/Main.server` (démarrage complet), `src/server/WorldBuild/{Village, Chapel, Crypt, Training}`
(squelettes vides → zones complètes), `WorldBuildConfig` (ennemis, version 2), `World/MechanismService`
(runes et braises visibles), `Avatar/{AvatarService, AvatarAppearance}`, `Enemy/{EnemyService, EnemyBrain,
EnemyFactory}`, `World/WorldService`, `Guild/GuildMessaging` (isolation), `Shared/Data/DataConfig`
(commentaire), `client/Combat/{CombatController, CombatEffects}`, `client/World/{ArrivalController,
WorldAtmosphere}`, `client/UI/Grimoire`.

**Créés — outils et documents :** `tools/sim/*` (simulation et 6 tests), `tools/{README.md, typecheck.sh,
export.sh, require_graph.py}`, `tools/export/*.project.json`, `docs/renders/*.png`, ce rapport ;
`docs/ARCHITECTURE.md` mis à jour (section client conforme au code).

---

## 3. Tests exécutés et résultats exacts

| Test | Type | Résultat |
|---|---|---|
| `tools/typecheck.sh` | statique, Luau strict (luau-lsp + définitions Roblox) | **0 erreur** sur 144 fichiers (les `require` via `WaitForChild` côté client ne sont pas résolus par l'outil) |
| `tools/require_graph.py` | statique | 144 modules, 417 `require` résolus, **0 cycle réel** (1 faux positif : un exemple dans un commentaire) |
| `tools/sim/map.sh` | simulation | **CONTRAT OK**, idempotence OK (8 242 → 8 242) |
| `boot_test` | simulation | **14 / 14** |
| `creator_test` | simulation (client + serveur) | **26 / 26** |
| `quest_test` | simulation | **35 / 35** |
| `multiplayer_test` | simulation, 3 joueurs | **54 / 54** (2 avertissements attendus : la panne de DataStore volontaire) |
| `client_test` | simulation, 14 LocalScripts | **24 / 24** |
| `powers_test` | simulation, 6 joueurs | **22 / 22** |
| Roblox Studio | moteur réel | **non exécuté** (pas d'accès) |

Total : 175 vérifications de simulation, toutes réussies. Commande : `tools/sim/run_all.sh`.

Régressions trouvées et corrigées pendant ces tests : runes allumées invisibles pour les joueurs ;
identifiants d'ennemis périmés dans le générateur ; erreurs de types (appels protégés, tables
optionnelles) ; messagerie des guildes non isolée en Studio ; Grimoire sans bouton tactile ; zones
Village, Chapelle, Crypte et Entraînement vides.

---

## 4. Erreurs restantes connues et conséquences

Aucune erreur Luau connue dans les parcours simulés. Risques qui ne se lèvent que dans Studio :

1. **Physique et collisions** : escalier en colimaçon du puits (marches de 1 stud), rampes, pont,
   plaques de glace, corniche du bloc gravé. Conséquence possible : un passage plus difficile que prévu.
2. **Construction de la carte au démarrage** : si `Workspace.World` manque, le serveur la construit
   (≈ 7 600 Parts + terrain), ce qui retarde le premier joueur. Recommandé : construire une fois dans
   Studio et enregistrer la place (voir 6).
3. **Apparence** : les ID d'assets du catalogue viennent de votre configuration ; un ID invalide est
   signalé dans la sortie et n'empêche pas de jouer.
4. **Mise en page** des nouvelles interfaces sur petits écrans, à vérifier.

---

## 5. Synchroniser avec Roblox Studio

**Avant tout : sauvegardez votre place** (Fichier > Enregistrer une copie).

*Option A — Rojo (recommandée)* : installez Rojo 7.4 et son plugin Studio, récupérez le dépôt,
lancez `rojo serve default.project.json`, puis connectez le plugin. Les dossiers
`ReplicatedStorage.Shared`, `ServerScriptService.Server` et `StarterPlayerScripts.Client` sont synchronisés.

*Option B — fichiers .rbxmx* : supprimez (ou renommez en `_old`) les dossiers `Shared`, `Server` et
`Client` actuels, puis clic droit > **Insérer à partir du fichier** :
`Shared.rbxmx` dans **ReplicatedStorage**, `Server.rbxmx` dans **ServerScriptService**,
`Client.rbxmx` dans **StarterPlayer > StarterPlayerScripts**.

Ensuite :
1. Barre de commande : `require(game.ServerScriptService.Server.WorldBuild.WorldBuilder).build()`
   — la sortie ne doit afficher aucun « Contrat incomplet ». Puis Fichier > Enregistrer.
2. Paramètres du jeu > Sécurité > **Activer l'accès de Studio aux services API** (sauvegardes).
3. Lighting > Technology = **Future** (le seul réglage qu'un script ne peut pas faire).

---

## 6. Tester la version finale en multijoueur (Studio)

Test > Clients et serveurs > **Serveur local, 2 ou 3 joueurs** > Démarrer. Puis :

1. **Création** : sur chaque client, créer un personnage avec une magie différente ; vérifier la
   cinématique au belvédère, puis J (Grimoire).
2. **Groupe et contrats** : joueur 1 > Grimoire > Compagnons > inviter joueur 2 ; joueur 2 accepte.
   Au tableau des contrats (place du village) : accepter « Cendres errantes » et « Briser la pierre »,
   combattre ensemble dans la forêt (les compteurs montent pour les deux), rendre ; un second « Rendre »
   doit être refusé.
3. **Quête** : parler à Aldric (F), examiner les trois indices de la chapelle, attendre l'écho sur le
   parvis, toucher les runes 3-1-4-2, descendre le puits, vaincre le Veilleur (parer avec A quand le
   télégraphe est orange), prendre le battant, remonter par l'échelle, sonner la cloche, revoir Aldric.
   Quitter puis revenir : rien ne doit être perdu ni repayé.
4. **Boss** : à deux dans le Cercle du Gardien, l'amener sous 20 % ; quand l'écran vire au rouge,
   R : les deux joueurs voient le rembobinage. Le vaincre : chacun est récompensé une fois.
5. **Pouvoirs** : Pyromancie (trois braseros de la clairière), Glace (étang), Gravité (bloc des
   ruines), Antimatière (voile du mausolée), Foudre (conduit de la tour), Ombre (mur ouest de la chapelle).
6. **Guilde** : fonder, inviter, nommer deux officiers, les faire modifier la devise en même temps,
   exclure un membre ; le Grimoire doit se mettre à jour pour tous.
7. **Arrêt du serveur** : arrêter le test puis relancer : les profils sont conservés.
8. **Entre serveurs** (guildes) : publier une place de test privée et ouvrir deux serveurs.

Pour revoir la création d'un personnage déjà créé : `AvatarConfig.DEBUG_ALWAYS_OPEN_CREATOR = true`
(à remettre à `false` ensuite).
