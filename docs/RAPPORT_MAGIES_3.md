# Rapport Magies 3.0 : livraisons C, D et E (et rappel A, B)

**Ce que je peux affirmer.** Typage strict sans erreur, et les 14 suites de simulation passent.
Les tests vérifient les points suivants :
- bons objets au bon moment, calés sur les événements du serveur ;
- aucune pièce d'effet solide, nettoyage complet ;
- budget de pièces avec 22 sorts et 3 ultimes simultanés ;
- sons uniques par impact, réglages audio, musique approuvée jouée hors Studio.

**Ce que je ne peux pas affirmer.** Le rendu à l'écran, le son entendu et les performances
réelles sur téléphone : tout cela se vérifie dans Studio (§7).

Sauvegardes : branches `sauvegarde-avant-magies-3` (avant A) et `sauvegarde-avant-magies-3c`
(avant C), sur le dépôt distant.

## 1. Statut

| Élément | Statut |
|---|---|
| Glace, Antimatière (A, B) | **terminé**, validé par toi ; non modifiés depuis, sauf les sons |
| Pyromancie, Foudre, Ombre, Gravité (C) | **terminé côté code et tests** ; rendu **à juger dans Studio** |
| Volume du rembobinage R | **terminé** (+3 dB) ; ressenti à confirmer à l'écoute |
| Curseurs Musique / Ambiance / Effets | **vérifié** : tous les sons du jeu passent par ces trois groupes |
| Réglages après reconnexion | **vérifié** (test de reconnexion) |
| Sons distincts pour les six magies | **partiel** : sons livrés avec Roblox, différenciés par fichier et hauteur ; leur présence et leur qualité restent à confirmer dans Studio, et de meilleurs sons demandent un import (`docs/MUSIQUE_PUBLICATION.md` §7) |
| Un seul son par impact et par ultime | **terminé** (un doublon existant a été supprimé) |
| Musiques pour le jeu publié | **en attente de toi** : je ne peux ni charger ni écouter les pistes. Procédure et tableau dans `docs/MUSIQUE_PUBLICATION.md` |

## 2. Livraison C : ce qui change à l'écran

Même base que la Glace et l'Antimatière : un module par magie dans `src/client/Magic/Vfx/`, avec
budget, niveau de détail selon la distance, mode « effets réduits », aucune collision et nettoyage
garanti. Dégâts, coûts en Mana, altérations, recharges et logique serveur sont inchangés. Chaque
sort a désormais une préparation dans la main du lanceur.

### Pyromancie : de vraies flammes animées (effet Fire de Roblox) et des particules de feu
| | Ce qu'on voit |
|---|---|
| **Braise Ardente** (*Projectile · Brûle*) | une flamme naît dans la paume ; boule de feu à noyau incandescent, flammes qui traînent, étincelles ; petite explosion ardente, sol roussi, flamme brève |
| **Cercle Incandescent** (*Zone autour de soi · Brûle, Repousse*) | le sol chauffe, des braises montent, de petites flammes s'allument une à une sur la limite de la zone ; puis des langues de feu de hauteurs variées jaillissent du centre vers le bord, avec sol incandescent et souffle de chaleur |
| Durée réelle | la zone n'agit qu'à l'impact (serveur) : les flammes retombent en ~1,2 s ; la brûlure continue sur les cibles, qui portent désormais de **vraies flammes** (plus hautes à chaque cran) |
| **Brasier du Parjure** | cercle de flammes qui monte autour du lanceur, fissures de lave, braises en spirale ; colonne de feu, trois vagues de flammes jusqu'au bord, sol de lave |

### Foudre : des éclairs ramifiés, tracés brisés avec branches, cœur blanc et halo
| | Ce qu'on voit |
|---|---|
| **Arc Électrique** (*Instantané · Interrompt*) | crépitement et petits arcs dans la main ; éclair ramifié jusqu'au point réellement touché, éclat et étincelles ; sans cible, il s'éteint dans le vide |
| **Chaîne Foudroyante** (*Chaîne · Interrompt, 4 cibles*) | aura et arcs sur les bras ; l'éclair saute de cible en cible **dans l'ordre et aux positions envoyées par le serveur**, chaque rebond plus fin (-20 % de force) |
| **Jugement Céleste** | ciel assombri, électricité statique autour du lanceur, lueur au-dessus de chaque cible ; éclairs tombés du ciel sur chacune, éclair central massif, onde d'étincelles, flash bref |

### Ombre : matière sombre qui assombrit, filaments mouvants, énergie rendue au lanceur
| | Ce qu'on voit |
|---|---|
| **Trait Obscur** (*Projectile · Draine la vie*) | volutes sombres vers la main ; cœur sombre cerclé de rouge, filaments qui se tordent, fumée ; à l'impact, des lueurs de vie **reviennent au lanceur** (soin réel du serveur) |
| **Voile des Ombres** (*Sur soi · Protège*) | l'ombre monte du sol ; filaments sombres qui tournent autour du corps, fumée aux pieds ; le voile dure **exactement** tant que le serveur le maintient, laisse le joueur visible, puis se disperse |
| **Marée d'Ombres** | flaque d'ombre, formes sombres qui s'élèvent et glissent vers les cibles, vrilles ondulantes ; les formes se referment et éclatent, vague sombre, vie qui revient au lanceur |

### Gravité : rochers en lévitation, poussière, ondes de pression
| | Ce qu'on voit |
|---|---|
| **Pression Gravitationnelle** (*Zone ciblée · Ralentit, use la garde*) | compression dans la main ; au point visé, des cailloux se soulèvent et la poussière converge ; l'espace s'écrase (lentille aplatie), les cailloux retombent, onde rasante, fissures |
| **Champ Gravitationnel** (*Zone persistante · Ralentit, use la garde*) | pierres en suspension en orbite lente, poussière attirée, dôme presque invisible qui marque la limite ; à chaque impulsion du serveur, les pierres plongent ; à la fin réelle (même anticipée), elles retombent |
| **Effondrement Stellaire** | débris de toute la zone qui s'élèvent, colonnes de poussière, dôme qui se contracte ; onde de pression ; les débris montent avec les cibles soulevées, puis tout s'abat **à l'instant de l'écrasement du serveur** : fissures, poussière, secousse |

### Différences entre les deux sorts (affichées dans le HUD et sur les fiches)
- Pyromancie : projectile qui brûle / zone autour de soi qui repousse.
- Foudre : une cible instantanée / chaîne de quatre cibles.
- Ombre : projectile qui draine / protection sur soi.
- Gravité : zone instantanée / zone persistante à impulsions.

Les étiquettes sont calculées depuis les règles du serveur (`SpellTags`).

### Performances
- Test de charge : douze lanceurs, les 22 sorts et trois ultimes au même endroit et au même
  instant, soit un pic de 659 pièces d'effet, toutes détruites ensuite. Le budget réduit les
  détails au-delà de 180 pièces vivantes, puis encore au-delà de 320.
- Lumières seulement en détail élevé ; détail réduit au-delà de 90 puis 200 studs.
- Flashs et secousses seulement pour les joueurs proches, moins forts en « effets réduits ».

## 3. Livraison D : audio

| Point | Résultat |
|---|---|
| Rembobinage R | volume 0,32 → **0,45** (+3 dB), plafond 0,6 ; un seul chœur par rembobinage (pas de déclenchements multiples) ; son 2D, donc sans atténuation à distance ; groupe « Effets », donc 0 = muet ; l'atténuation des ultimes ne touche pas les effets |
| Curseurs | tous les sons créés par le jeu sont rangés dans Musique, Ambiance ou Effets (vérifié dans le code) ; seuls les sons par défaut du personnage Roblox (pas, saut) n'en dépendent pas |
| Reconnexion | musique, ambiance et effets retrouvés (test) |
| Sons des magies | lancement + impact distincts pour les six magies, à partir de sons livrés avec Roblox ; volumes ≤ 0,45, hauteurs modérées |
| Superpositions | un impact de sort jouait son son deux fois (au message du serveur puis au moment visible) : corrigé, il n'est joué qu'au moment visible ; chaque ultime joue un seul son d'impact (test) |

**Aucun identifiant audio n'a été inventé.** Les sons « livrés avec Roblox » sont des fichiers de
l'installation (`rbxasset://sounds/…`). Leur présence est vérifiée par `A.run()`.

## 4. Livraison E : musiques

- Ce que tu entends dans Studio vient de l'essai automatique, et **le jeu publié reste
  silencieux** tant qu'aucune piste n'est approuvée.
- Tableau complet des candidats, par contexte, avec la ligne exacte d'`AudioConfig` :
  `docs/MUSIQUE_PUBLICATION.md` §3.
- **Ce que j'attends de toi** (§2 de ce document) :
  1. le rapport de `A.run()` ;
  2. les lignes `[Musique]` de la sortie après une partie ;
  3. ton verdict par contexte.

  J'inscrirai alors les pistes approuvées. Une piste inscrite joue en publié (testé).

## 5. Fichiers modifiés (C, D, E)

- Nouveaux :
  - `src/client/Magic/Vfx/Pyromancy.luau`, `Lightning.luau`, `Shadow.luau`, `Gravity.luau` ;
  - `docs/MUSIQUE_PUBLICATION.md`, `docs/RAPPORT_MAGIES_3.md`.
- Modifiés côté magie : `src/client/Magic/VfxKit.luau` (éclairs, flammes, rochers, filaments,
  taches au sol), `SpellEffects.luau` (anciens effets retirés), `UltimateChoreographies.luau`
  (aiguillage), `SpellController.client.luau` (son d'impact unique).
- Modifiés côté audio et altérations :
  - `src/client/Combat/StatusEffects.client.luau` (flammes de brûlure) ;
  - `src/client/TimeLoop/TimeLoopAudio.luau` (plafond) ;
  - `src/shared/Audio/AudioConfig.luau` (chœur, sons des magies) ;
  - `AudioCandidates.luau` (alternatives), `AudioAudit.luau` (vérification des sons livrés).
- Tests : `tools/sim/spells_test.luau`, `tools/sim/audio_test.luau`.
- Serveur : **aucun changement.**

## 6. Ce qui reste impossible à vérifier sans toi

- Le rendu des flammes (effet Fire), des éclairs, de la fumée sombre et du verre.
- L'existence et la qualité des sons livrés avec Roblox (à confirmer avec `A.run()` et à l'oreille).
- L'autorisation et le chargement des musiques pour ton expérience.
- Les performances réelles sur téléphone.

## 7. Test dans Studio (pas à pas)

1. **Import** : remplace `ReplicatedStorage > Shared` par `Shared.rbxmx`,
   `ServerScriptService > Server` par `Server.rbxmx`, et
   `StarterPlayer > StarterPlayerScripts > Client` par `Client.rbxmx`.
2. **Créateur** : clique **Aperçu** sur Pyromancie, Foudre, Ombre puis Gravité. Chaque fiche
   enchaîne les deux sorts puis l'ultime.
3. **Pyromancie** en jeu (touches 1, 2, E) : boule de feu en flammes ; anneau de flammes qui
   s'allument puis langues de feu qui retombent vite ; ennemi touché qui brûle visiblement.
4. **Foudre** : arc ramifié jusqu'à l'ennemi. Pour la chaîne, place-toi devant **trois ennemis
   espacés** : l'éclair doit sauter de l'un à l'autre. Ultime : éclairs tombés du ciel.
5. **Ombre** : trait sombre et lueurs qui reviennent vers toi ; voile de filaments autour de toi
   pendant 4 s (tu dois rester visible) ; ultime : formes sombres qui convergent.
6. **Gravité** : cailloux soulevés puis écrasés ; champ de pierres en suspension pendant ~4 s ;
   ultime : débris qui montent puis s'abattent au moment où l'ennemi est plaqué au sol.
7. **Glace et Antimatière** : relance un sort de chaque pour vérifier qu'elles n'ont pas changé
   (seuls leurs sons sont nouveaux).
8. **Audio** :
   - touche R : le chœur doit être un peu plus présent qu'avant, sans couvrir la musique ;
   - Grimoire > Options > Effets à 0 : plus aucun son de sort ni de chœur, la musique continue ;
   - remets à ta valeur, quitte, reviens : les curseurs doivent être conservés.
9. **Effets réduits** (Options) : refais un sort par magie ; il doit y avoir moins de particules
   et pas de secousse forte.
10. **Workspace** : quelques secondes après chaque sort, `UltimateEffects` et `SpellEffects`
    doivent être vides.
11. **Musiques** : suis `docs/MUSIQUE_PUBLICATION.md` §2 et envoie-moi les résultats.

Si une forme paraît fausse (pointes creuses, flammes absentes, éclairs invisibles), dis-moi
laquelle : chaque magie est isolée dans son module.
