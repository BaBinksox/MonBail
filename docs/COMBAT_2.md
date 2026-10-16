# Combat 2.0 — animations, mobilité, ressources, magies, musique

Rapport de livraison de la passe « COMBAT 2.0, ANIMATIONS ANIME, MOBILITÉ ET IDENTITÉ MUSICALE ».

**À lire d'abord — ce qui a été vérifié, et comment.** Tout le travail a été vérifié par le contrôle de
types strict (aucune erreur) et par **14 suites de simulation (595 vérifications, toutes au vert)**, qui
exécutent le vrai code du jeu dans un moteur simulé, hors Roblox. **Je n'ai pas accès à Roblox Studio** :
rien n'a été essayé dans Studio. La physique réelle, le rendu des poses et des effets, le réseau (latence,
réplication) et le ressenti restent à valider en jeu (procédure en §9). Les simulations ne remplacent pas
ces essais.

Point de restauration : l'étiquette git `avant-combat-2` (sur GitHub) marque l'état d'avant cette passe.
Phases livrées, une par commit sur `main` : C1 (mobilité, poses), C2 (épée), C3 (Concentration),
C4 (altérations, sorts), C5 (musique), C6 (HUD, tactile), C7 (tests, rapport).

---

## 1. État des fonctionnalités

| Fonctionnalité | État | Remarques |
|---|---|---|
| Commandes centralisées (clavier AZERTY/QWERTY, manette, tactile) | opérationnelle | `Shared/Input/KeyBindings`, conflits vérifiés par test |
| Sprint progressif (0,65 s), décélération 0,25 s, FOV + traînées | opérationnelle | vitesse max contrôlée par le serveur, bonus de peuple conservés |
| Double saut (un seul, recharge au vrai contact du sol) | opérationnelle | hauteur 10,9 studs ; ne franchit ni le ravin ni l'étang (calculé) |
| Dash sur C / double appui / B | opérationnelle | esquive parfaite → Tension + élan |
| Combo de 5 coups distincts, mise en file sans spam | opérationnelle | cadence et fenêtres validées par le serveur |
| Attaque chargée (puissance mesurée par le serveur) | opérationnelle | ralenti, vulnérable, recharge ; pleine = brise les gardes |
| Parade parfaite → riposte | opérationnelle | fenêtre 1,1 s, entame la posture de l'attaquant |
| Attaque plongeante | opérationnelle | vérifiée en l'air par raycast serveur |
| Posture des ennemis (rupture) | opérationnelle | boss : rupture courte + recharge 12 s |
| Mana (100, régén. 7 hors combat / 3 en combat) | opérationnelle | non sauvegardé (voulu) |
| Tension (gains centralisés, ultime à 100, pas de régén.) | opérationnelle | `ResourceConfig.TENSION_SOURCES` |
| Concentration (G maintenu) | opérationnelle | ralenti x 0,25, dégâts reçus x 1,35, 4 s max, recharge 8 s |
| Altérations communes (11) + nettoyage | opérationnelle | durée max, cumul, boss, rendement décroissant |
| 12 sorts (2 par magie) | opérationnelle | PvE seulement |
| Réactions élémentaires | opérationnelle (2) | Éclatement, Choc thermique (dans les deux sens) |
| Musique dynamique (hostile, combat, boss, anomalie, victoire) | opérationnelle, **silencieuse** | aucune piste choisie (voir §4) |
| HUD de combat, boutons tactiles adaptés | opérationnelle | à contrôler visuellement sur appareil |
| **Animations** | **partielle** | poses procédurales jouables ; clips Studio à produire (§3) |
| Dash aérien, mur, armes futures | architecture seulement | voir §8 |

---

## 2. Fichiers

**Nouveaux — serveur** : `Combat/ResourceService`, `Combat/PostureService`, `Combat/StatusService`,
`Magic/SpellService`.
**Nouveaux — partagé** : `Input/KeyBindings`, `Movement/MovementConfig`, `Movement/MovementModel`,
`Animation/AnimationConfig`, `Combat/ResourceConfig`, `Combat/StatusConfig`, `Magic/SpellConfig`,
`Magic/SpellRemotes`.
**Nouveaux — client** : `Animation/PoseLibrary`, `Animation/CharacterAnimator`,
`Animation/AnimationDirector`, `Movement/MovementState`, `Movement/MovementEffects`,
`Movement/MovementController`, `Audio/SfxPlayer`, `Audio/CombatMusicController`,
`Combat/ConcentrationController`, `Combat/StatusEffects`, `Magic/SpellController`, `Magic/SpellEffects`,
`UI/CombatHud`, `Input/TouchLayout`.
**Réécrits** : `Combat/CombatService`, `Combat/CombatController`, `Movement/MovementService`,
`Movement/DashController`, `Combat/CombatConfig`.
**Modifiés** : `DamageService` (signaux `Damaged` / `Dodged`, modificateurs joueur, drapeau `blocked`),
`ParryService` (signal `Parried`, bloqueurs), `UltimateBehaviors` (passe par les altérations),
`EnemyBrain` et `BossService` (vitesse x altérations), `Behaviors/Guardian` (signale le coup bloqué),
`TimeLoopService` (signal `Rewound`), `RaceService`, `CombatEffects`, `ParryController`, `MusicDirector`,
`AudioConfig`, `TimeLoopController`, `Grimoire` (bouton tactile), `NPCInteraction`, `UIBus`, `Main.server`.
**Supprimés** (remplacés) : `Client/Combat/SwingAnimator` (→ `CharacterAnimator`, qui joue aussi les clips),
`Client/Combat/TensionView` (→ `CombatHud`).
**Non touchés** : sauvegarde (`Data/*`), progression, quêtes, missions, guildes, groupes, générateur de
carte (`WorldBuild/*`), créateur de personnage, Roulette du Destin.

---

## 3. Animations

### Ce qui existe

Chaque action animée a une entrée dans `Shared/Animation/AnimationConfig.ACTIONS`. Faute de pouvoir
publier de vrais assets Animation depuis cet environnement, chacune est jouée par une **pose procédurale**
(`Client/Animation/PoseLibrary` : images clés appliquées aux articulations R15 par code, en plus des
animations de base de Roblox). Ces poses sont réellement jouées en jeu, chez tous les clients, mais ce
sont des **approximations** : elles ne remplacent pas des clips faits main. Je ne les présente pas comme
des animations terminées.

### Clips à produire dans l'Animation Editor (R15)

Mettre l'ID publié dans `AnimationConfig.ACTIONS.<action>.animationId` (`"rbxassetid://…"`) : le clip
remplace aussitôt la pose (personnage local ; Roblox le réplique aux autres). **Garder la durée et
l'instant d'impact** ci-dessous, ou ajuster les nombres du serveur indiqués : il valide ses fenêtres de
frappe sur ces temps.

| Action | Durée | Impact | Calé sur (à ajuster si le clip change) |
|---|---|---|---|
| `sword_1` coup horizontal | 0,36 s | 42 % | `CombatConfig.COMBO[1]` hitStart 0,11 / hitEnd 0,25 |
| `sword_2` diagonale inverse | 0,34 s | 45 % | `COMBO[2]` 0,11 / 0,25 |
| `sword_3` vertical | 0,50 s | 50 % | `COMBO[3]` 0,20 / 0,34 |
| `sword_4` tourbillon contrôlé | 0,55 s | 50 % | `COMBO[4]` 0,12 / 0,42 |
| `sword_5` final spectaculaire | 0,70 s | 55 % | `COMBO[5]` 0,33 / 0,50 |
| `sword_charge` posture de charge (boucle) | 0,60 s | — | maintenue jusqu'au relâchement |
| `sword_charged` frappe chargée | 0,55 s | 30 % | `CHARGED` 0,10 / 0,30 |
| `sword_counter` riposte | 0,38 s | 40 % | `COUNTER` 0,10 / 0,26 |
| `sword_plunge_fall` chute (boucle) | 0,40 s | — | pendant la descente |
| `sword_plunge` impact au sol | 0,50 s | 15 % | atterrissage |
| `parry`, `parry_perfect` | 0,35 / 0,40 s | 15 / 25 % | — |
| `hit_react`, `stagger` | 0,32 / 1,20 s | — | rupture de posture : `POSTURE.BREAK_DURATION` 2 s |
| `dash`, `double_jump`, `land` | 0,24 / 0,48 / 0,30 s | — | — |
| `concentrate` (boucle) | 2,4 s | — | — |
| `cast_<magie>_base` / `_secondary` (12) | 0,30 à 1,05 s | 45 à 65 % | `SpellConfig.<sort>.castTime` |
| `cast_ultimate` | 0,90 s | 30 % | `CombatConfig.ULTIMATE_HIT_STOP` |

Marche, course, saut simple et chute restent ceux du script `Animate` de Roblox (le sprint ajoute une
inclinaison du buste ; la chute écarte les bras). Pour des clips de marche ou course propres : remplacer
les ID du script `Animate` du personnage.

Les deux clips officiels de Roblox déjà utilisés autrefois (épée : `rbxassetid://522635514` et
`rbxassetid://522638767`) sont conservés dans `AnimationConfig` comme repli possible ; **leur chargement
n'a pas pu être vérifié ici**.

---

## 4. Sons et musique : état des identifiants

**Aucun identifiant n'a été inventé.** Deux sortes de sources :

| Source | Où | État |
|---|---|---|
| `rbxasset://sounds/swordslash.wav`, `swordlunge.wav`, `unsheath.wav`, `action_jump.mp3` | `AudioConfig.SFX` : `swordSwing`, `swordSwingHeavy`, `parryPerfect`, `chargeReady`, `doubleJump` | sons **livrés avec Roblox** ; présence à confirmer en jeu (un fichier absent est silencieux, sans erreur) |
| `""` (vide, avec critères de recherche) | toutes les autres entrées de `AudioConfig.SFX` (impacts, garde, rupture, esquive, Mana, Concentration, sorts par élément, réaction, plongée…) | silence tant qu'un son vérifié n'est pas posé |
| `""` | `AudioConfig.TRACKS` : thème, régions (village, forêt, crypte, belvédère, lac, futurs elfe / nain), `hostile`, `combat`, `boss`, `anomaly`, `victory` | silence ; chaque piste a sa description |
| `""` | `AudioConfig.REWIND_CHOIR` | rembobinage silencieux tant qu'il est vide |

Identité musicale décrite dans `AudioConfig` : fantasy mélancolique façon bande originale d'anime (piano,
cordes, harpe, chœur féminin discret), **originale** — ni l'opening de Re:Zero, ni sa mélodie, ni une
imitation proche. Pour remplir une piste : Toolbox > Audio, filtrer par genre et durée, **écouter en jeu**
(une piste visible peut être bloquée pour l'expérience), coller l'ID dans le champ `id`.

**Points d'intégration** : musiques `AudioConfig.TRACKS.<clé>.id` ; sons `AudioConfig.SFX.<clé>.id` ;
chœur `AudioConfig.REWIND_CHOIR.id` ; épée `ServerStorage > Assets > Sword` (sinon épée générée).

---

## 5. Systèmes (valeurs de départ, toutes réglables)

**Mobilité** (`MovementConfig`) : sprint x 1,5 (24 studs/s pour un humain) atteint en 0,65 s, retour en
0,25 s, FOV +7° ; double saut 38 studs/s vers le haut (≈ 10,9 studs), un seul, rendu au vrai contact du
sol ; dash 85 studs/s pendant 0,18 s, recharge 2 s. Le serveur publie la vitesse de base (peuple x
effets), contrôle la vitesse mesurée deux fois par seconde (corrige au-delà de la marge) et la hauteur
depuis le dernier appui au sol (15 studs max). Un ralentissement (froid, charge, Concentration) s'applique
aussi au sprint. Calcul de portée : Elfe au sprint + double saut ≈ 20,7 studs à plat < ravin de 26 ;
≈ 17,8 vers l'îlot de l'étang < 20 : les passages réservés aux pouvoirs restent fermés.

**Épée** (`CombatConfig`) : Entaille 10, Revers 10, Fendoir 15, Tourbillon 12 (zone autour de soi),
Brise-ciel 26 (éjection, lourd) ; un clic n'est retenu pour le coup suivant que dans les 55 % finaux du
coup. Charge : 18 à 45 dégâts selon 0 à 1,1 s de charge, posture 20 à 60, recharge 2,5 s ; pendant la
charge : vitesse x 0,45, dégâts reçus x 1,25, ni sprint, ni parade, ni Concentration. Riposte 22 (lourde),
plongée 14 (zone). Arrêt sur image propre à chaque coup. Résultats d'impact distincts : franc, **bloqué**
par une garde (étincelles métalliques, son mat, recul) ou **posture brisée** (onde dorée).

**Posture** : max = PV x 0,6 (40 à 400 ; élite x 1,3, boss x 2,5) ; rupture = étourdi 2 s (boss 1,2 s,
puis 12 s sans rupture possible), dégâts reçus x 1,3 ; reconstitution après 3 s sans pression.

**Ressources** (`ResourceConfig`) : Mana 100, régénération 7/s hors combat, 3/s en combat (« en combat »
6 s après le dernier coup donné ou reçu). Tension : coup de combo 8, final 14, charge 12 (x 1,5 pleine),
riposte 16, parade parfaite 25, esquive parfaite 12, rupture 15, sort 4, réaction 10, multipliée par le
peuple ; une fois par attaque (frapper un groupe ne remplit pas la jauge d'un coup). Concentration :
24 Mana/s, 4 s max, recharge 8 s, rompue par le premier coup reçu ; aura propre à la magie.

**Altérations** (`StatusConfig`) : brûlure (3 crans, 4/s par cran), froid (x 0,75, -0,1 par cran), gel
(immobile + sans attaque ; boss : simple froid), électrisé (interrompt l'action en préparation ; un boss au
plus toutes les 8 s), drain (soigne le lanceur), voile, aspiration (bornée, boss immunisés), pression
(x 0,55, posture +25 %), et pour les ultimes paralysie, cloué, Hiver Éternel. Contrôles durs : 2e
application moitié moins longue, 3e refusée dans les 12 s. Effacées à la mort, à la disparition et au
rembobinage. Une seule altération par cible, alimentée par plusieurs joueurs : jamais de double
élimination ni de double récompense (`DamageService`).

**Sorts** (`SpellConfig`) :

| Magie | Sort de base (Mana) | Sort secondaire (Mana) | Force / faiblesse |
|---|---|---|---|
| Pyromancie | Braise Ardente (18) : brûlure | Cercle Incandescent (35) : zone autour de soi, brûlure x 2, éjection | dégâts dans le temps / courte portée |
| Glace | Éclat de Givre (16) : froid | Prison Cristalline (40) : gel en zone (boss : froid) | contrôle / peu de dégâts |
| Foudre | Arc Électrique (15) : instantané, interrompt | Chaîne Foudroyante (38) : 4 cibles, -20 % par rebond | vitesse, plusieurs cibles / dégâts dispersés |
| Ombre | Trait Obscur (18) : soin + drain | Voile des Ombres (30) : dégâts reçus -40 %, vitesse +15 % | survie / aucun contrôle |
| Antimatière | Fragment du Vide (20) : explosion | Singularité Mineure (42) : aspire 6 ennemis puis implose | regroupement / lente |
| Gravité | Pression Gravitationnelle (17) : pression | Champ Gravitationnel (36) : zone persistante, 8 impulsions | posture / dégâts modestes |

Le serveur vérifie la magie du joueur, le Mana (débité d'un seul geste), la recharge globale et celle du
sort, la portée, le premier mur, et simule projectiles, zones et chaînes. Le client n'envoie qu'un
identifiant de sort et un point visé. Lancer un sort arrête une Concentration en cours.

**Réactions** : **Éclatement** (Foudre sur cible froide ou gelée : +16 + 50 % du coup, posture 40,
étourdi 0,4 s) ; **Choc thermique** (Feu sur cible froide ou gelée, ou Glace sur cible qui brûle :
+12 + 60 % du coup, posture 20). Elles consomment l'altération et marchent entre joueurs.

**Musique dynamique** : couches créateur > anomalie > boss > combat > victoire > présence hostile > région,
avec hystérésis (entrée 1,5 s / sortie 6 s pour la présence hostile, 3 s après la fin de l'état « en
combat »). Une piste quittée reprend où elle en était (pas de redémarrage de l'exploration après chaque
combat) ; au plus deux pistes en fondu de sortie ; une piste vide = silence sans erreur.

**HUD** : PV, Mana, Tension (dégradé de la magie) ; emplacements des sorts et de la Concentration avec la
touche réelle selon l'appareil, le coût (rouge s'il manque du Mana) et la recharge ; pastilles
d'altérations ; invites « Riposte » et ultime ; Mana insuffisant signalé (clignotement + son).

---

## 6. Changements de commandes

| Action | Avant | Maintenant |
|---|---|---|
| **Maj gauche** | dash | **sprint maintenu** |
| **Dash** | Maj | **C**, ou double appui sur une direction (ZQSD / WASD, flèches), B |
| Attaque maintenue | — | attaque chargée |
| Clic en l'air | — | attaque plongeante |
| Clic juste après une parade parfaite | — | riposte |
| 1 / 2 (« & » / « é » en AZERTY) | — | sort de base / secondaire (R1 / L2) |
| G maintenu | — | Concentration (croix droite) |
| Rembobinage manette | — | croix bas ; tactile : bouton pendant une anomalie |

Studio : **décocher `StarterPlayer > EnableMouseLockOption`**, sinon Maj active aussi le « Shift Lock » de
Roblox. Boutons tactiles : deux dispositions (grand écran / téléphone) en arc autour du bouton de saut ;
stick et centre de l'écran libres ; Grimoire en haut à droite. Chevauchements vérifiés par calcul, **pas
sur appareil**.

---

## 7. Sauvegarde

**Aucun changement de sauvegarde** : ni nouveau DataStore, ni nouveau champ de profil, ni migration.
Mana, Tension, recharges et altérations vivent en mémoire serveur et repartent à zéro à la reconnexion
(vérifié : progression conservée, Mana plein, Tension à 0). Aucune donnée de joueur n'a été effacée.

---

## 8. Architecture prête pour la suite

- **Dash aérien, mur, plongée variée** : `MovementService` accepte des fournisseurs de vitesse et des
  bloqueurs ; `MovementModel` isole les calculs ; l'état aérien est publié (`MovementState`).
- **Armes futures** (épée longue, dague, bâton, lance, marteau nain) : `CombatConfig.WEAPON` et le type
  `AttackStep` (dégâts, fenêtres, allonge, largeur, zone centrée, posture, arrêt sur image, source de
  Tension) ; une arme = une table de coups.
- **Nouvelles réactions** : une entrée dans `StatusConfig.REACTIONS`.
- **Nouvelles altérations** : une entrée dans `StatusConfig.STATUSES` (affichage automatique).
- **Ultimes dédiés** : `CombatEffects.ULTIMATE_PLAYERS[magicId]`.

---

## 9. Procédure de test dans Studio

1. Importer (§10), décocher `EnableMouseLockOption`, Play avec un personnage R15.
2. **Sprint** : maintenir Maj en avançant : montée progressive (~0,65 s), FOV élargi, traînées ; relâcher :
   retour rapide. Pendant une attaque chargée (ralentissement), le sprint est coupé et la vitesse baisse ;
   elle revient exactement à la normale au relâchement.
3. **Double saut** : Espace puis Espace en l'air : un seul second saut ; impossible d'en refaire un sans
   toucher le sol ; au ravin de la forêt et à l'étang, le passage doit rester impossible sans le pouvoir.
4. **Dash** : C, double appui sur une direction, B à la manette ; esquiver un coup ennemi au dernier moment :
   « Esquive parfaite », Tension.
5. **Combo** : cliquer en rythme sur le mannequin : cinq coups différents ; marteler trop tôt ne doit rien
   enchaîner ; le 5e éjecte. Sur le Gardien de face : impact « bloqué » ; le coup final brise sa garde.
6. **Charge** : maintenir le clic après un coup : lame ramenée, lueur, son à pleine charge ; relâcher.
7. **Parade / riposte** : parer (A en AZERTY) au moment d'un coup ennemi, puis cliquer : riposte.
8. **Plongée** : sauter, cliquer en l'air au-dessus d'un ennemi.
9. **Posture** : enchaîner sur un ennemi : il finit étourdi (effet doré), plus vulnérable.
10. **Mana / Concentration** : lancer des sorts jusqu'à manquer de Mana (jauge qui clignote, coût rouge) ;
    maintenir G : posture, aura, Mana qui remonte vite, déplacement très lent ; un coup reçu la rompt.
11. **Six magies** : créer un personnage par magie (ou six joueurs en test local), essayer 1 et 2, puis
    les réactions à deux joueurs (Glace puis Foudre ; Glace puis Feu ; Feu puis Glace).
12. **Rembobinage** : pendant le boss, une anomalie ; rembobiner : altérations et posture effacées.
13. **Manette, tactile** : émulateur d'appareils de Studio (téléphone et tablette) : boutons visibles, sans
    chevauchement, centre dégagé ; libellés du HUD selon l'appareil.
14. **Options** : volumes Musique / Effets, « effets réduits » (secousses et particules réduites).

---

## 10. Import dans Studio

- **Rojo** (recommandé) : `rojo serve` sur `default.project.json`, puis connecter le plugin.
- **Exports** : `build/Shared.rbxmx` → `ReplicatedStorage` (remplacer le dossier `Shared`),
  `build/Server.rbxmx` → `ServerScriptService` (remplacer `Server`), `build/Client.rbxmx` →
  `StarterPlayer > StarterPlayerScripts` (remplacer `Client`). Supprimer d'abord les anciens dossiers.
  Régénérer : `tools/export.sh`.
- **Carte** : **aucune reconstruction nécessaire** (le générateur n'a pas changé).

---

## 11. Tests (simulation, hors Roblox)

`tools/sim/run_all.sh` — 14 suites, **595 vérifications, 0 échec** :

| Suite | Vérif. | Contenu principal |
|---|---|---|
| boot / creator / quest / multiplayer / client / powers / placement / daynight / race / arrival | 332 | non-régression des passes précédentes (créateur, quêtes, guildes, six pouvoirs d'exploration, placement, cinématique…) |
| movement_test | 47 | commandes, chevauchements tactiles, sprint R15, vitesse raciale, ralentissement et retour, pas de saut infini, portée face aux énigmes, garde du serveur, poses |
| combat_test | 98 | combo et fenêtres, spam refusé, charge (pleine, partielle, abandon), riposte, posture, élan, plongée, ultime unique, Mana et régénération, Concentration, deux joueurs / élimination unique, rembobinage, sauvegarde et reconnexion, contrôleurs client |
| spells_test | 83 | douze sorts, coûts, recharges, refus (magie, Mana), altérations, rendement décroissant, boss, réactions, multi-joueurs, nettoyage, rembobinage, ultimes, HUD |
| audio_test | 35 | musique unique, fondus, priorités, musique dynamique, reprise, silence des pistes vides, volumes, chœur |

Limites de ces tests : moteur simulé (physique simplifiée, pas de rendu, réseau sans latence réelle).
