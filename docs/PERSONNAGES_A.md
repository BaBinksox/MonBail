# Identité des personnages : livraison A (prototype visuel)

**Ce que je peux affirmer.** Typage strict sans erreur, et les 15 suites de simulation passent,
dont une nouvelle (`costume_test`). Elle mesure l'ajustement de chaque tenue sur un mannequin R15
aux dimensions standard, à la taille de chaque peuple et aux proportions extrêmes :
- rien sous les pieds ;
- aucune pièce qui flotte (écart maximal mesuré : 0,02 stud) ;
- aucune pièce solide ;
- toutes les pièces soudées ;
- HipHeight intacte.

J'ai aussi produit des **rendus de contrôle** (`docs/renders/costume_*.png`) pour juger les
proportions de face, de trois-quarts, de profil et de dos.

**Ce que je ne peux pas affirmer.** L'allure réelle dans Studio. Les rendus utilisent des corps en
blocs : les corps Roblox (bundles Homme / Femme) sont arrondis, et la lumière du jeu est différente.
Les cheveux y sont schématiques (calotte brune). C'est à toi de juger la qualité.

Point de restauration : branche `sauvegarde-avant-personnages`.

## 1. Le choix technique, et pourquoi

| Méthode | Verdict pour ce projet |
|---|---|
| Vêtements classiques (Shirt/Pants 2D) | dépendent d'IDs du catalogue que je ne peux pas vérifier d'ici (catalogue Roblox inaccessible depuis mon environnement) ; textures plaquées, pas de silhouette |
| Vêtements superposés (layered clothing) | demandent des maillages 3D publiés ; rien de vérifiable |
| **Pièces fabriquées dans le jeu, soudées aux membres** | **retenu** : aucun asset externe, visibles par tous, suivent les animations, s'adaptent à chaque taille |

Une tenue fabriquée a deux couches :

1. **Teinture des membres.** Le buste, les bras, les jambes et les pieds prennent la couleur
   **et la matière** du vêtement (Fabric, Leather), comme une étoffe ajustée. Les mains et la
   tête gardent le teint choisi, et les douze teints continuent de fonctionner.
2. **Pièces sculptées**, soudées aux membres et dimensionnées en proportion de chaque membre :
   pourpoint, plastron, épaulières, capes en deux pans, pans de tunique ou de manteau, ceinture,
   besace, gantelets, bottes, liserés.

Garanties techniques :
- aucune masse, collision, requête ni contact : rien ne pousse le joueur, rien n'arrête un coup ;
- tout est posé par le serveur, donc visible des autres joueurs ;
- la tenue est refaite au respawn ;
- elle est retirée avant chaque changement de corps (aucune pièce détachée).

Rien n'est placé sous la plante des pieds. Les capes et les pans pendent depuis la taille, en
deux segments, pour ne pas traverser les jambes à la marche.

## 2. Ce qui est équipable et visible en jeu

### Quatre tenues (créateur > Tenue : les quatre premières)

Toutes sont portables par les quatre peuples.

| Tenue | Inspiration | Silhouette |
|---|---|---|
| **Aventurier des Cendres** | Humains | pourpoint de cuir ouvert sur chemise de lin lacée, tunique bleu nuit, capuche rabattue et cape courte rouge brique (liseré d'or), bandoulière et besace, bourse, épaulière gauche, brassards, revers de bottes |
| **Veilleur d'Ellendor** | Elfes | tunique vert profond à quatre pans jusqu'au mollet (liserés or pâle), mantelet argent-vert, écharpe d'argent en diagonale, broche en feuille, cape de brume légèrement translucide, brassards de bois cerclés d'argent |
| **Forgeron de Brasegrise** | Nains | plastron de cuivre à arête et bandes gravées, épaulières à bordure d'acier, col de fourrure, grosse ceinture à boucle d'or, tablier de forge, marteau à la ceinture, gantelets, bottes à revers de fourrure et coques d'acier |
| **Veilleur des Marches d'Ombre** | Enfants de l'Ombre | long manteau charbon ouvert sur gilet prune, col haut, capuche rabattue, liserés et fermoirs d'argent avec chaînette, ceinture violette, quatre pans fendus à liseré d'argent ; **visage toujours découvert** |

Les trois tenues historiques (Voyageur de minuit, Chevalier de fer noir, Parjure) restent dans la
liste : leurs identifiants sont dans des sauvegardes. Elles sont signalées comme dépendant du
catalogue Roblox.

### Nouvelle étape « Ornement » (après Chevelure)

| Ornement | Détail |
|---|---|
| Aucun | défaut ; c'est aussi la valeur des personnages existants |
| Barbe tressée brune, rousse ou grise | sous le menton (la bouche reste visible), tresse à anneaux de bronze ; **facultative pour tous, nains compris** |
| Diadème d'Ellendor | bandeau d'argent sur le front, feuille d'or pâle |
| Sablier de l'anomalie | pendentif d'argent, lueur violette (accessoire temporel) |

### Deux PNJ rhabillés

Nom, dialogue, position et rôle sont inchangés.

| PNJ | Avant | Maintenant |
|---|---|---|
| **Le Forgeron** | tenue de chevalier du catalogue + tablier en bloc | chemise noircie aux manches retroussées (avant-bras nus), grand tablier à bavette, sangles croisées, gants et manchettes de forge, ceinture à outils, marteau, pinces |
| **Corvin l'Archiviste** | tenue de voyageur + robe en bloc | longue robe bleu de nuit à quatre pans, étole d'or qui descend jusqu'à l'ourlet, col de lin, cordelière, larges manches à revers d'or, livre à la ceinture, étui à parchemins dans le dos |

## 3. Ressources et identifiants

- **Aucun nouvel asset externe, aucun identifiant ajouté.** Les tenues, ornements et costumes
  fabriqués n'utilisent que des pièces Roblox de base (Part, WedgePart, SpecialMesh « Sphere »,
  cylindre) et des matières intégrées (Fabric, Leather, Metal, Wood, Neon).
- Les coiffures, visages, marques et tenues historiques restent des **placeholders du catalogue**,
  déjà présents avant cette livraison et non vérifiés par moi. Pour les vérifier dans Studio :
  `require(game.ReplicatedStorage.Shared.Avatar.AvatarAudit).run()`. Le rapport donne pour
  chaque asset son nom, son créateur et son type chez Roblox.

## 4. Préparé seulement (pour la livraison B, après ton accord)

- les sept autres styles de tenue (vagabond, chevalier, mage, érudit, guérisseur, garde, noble),
  avec la même technique ;
- les coiffures : la qualité passe par des accessoires de cheveux du catalogue (les pièces
  fabriquées font de mauvaises chevelures). `AvatarAudit` servira à vérifier ceux que tu choisis ;
- davantage d'accessoires (épaulières, sacoches, bijoux, accessoires d'érudit et d'artisan) ;
- les autres PNJ ;
- des boutons Face / Profil / Dos dans le créateur (aujourd'hui, on fait tourner la vue au glisser).

## 5. Sauvegarde et compatibilité

- **Profil v4** : migration v3 → v4 non destructive, qui ajoute `avatar.ornament = "none"` sans
  rien changer d'autre.
- Les anciens personnages gardent leur tenue historique et n'ont pas d'ornement.
- Un client qui n'envoie pas encore l'ornement est accepté (« Aucun »).
- La tenue et l'ornement sont sauvegardés par identifiant, puis restaurés à la reconnexion et au
  respawn (tests).
- Combat, magies, musiques, guildes, quêtes, carte : aucun fichier touché.

## 6. Fichiers

- Nouveaux :
  - `src/shared/Avatar/GarmentLibrary.luau` (tenues, costumes, ornements) ;
  - `src/server/Avatar/CostumeBuilder.luau` (pose sur les personnages et les PNJ) ;
  - `src/shared/Avatar/AvatarAudit.luau` (vérification des assets du catalogue dans Studio) ;
  - `tools/sim/costume_test.luau`, `tools/sim/costume_dump.luau`, `tools/sim/costume_render.py`
    (rendus de contrôle) ;
  - ce document et `docs/renders/costume*.png`.
- Modifiés :
  - `src/shared/Avatar/AvatarConfig.luau` (quatre tenues fabriquées, ornements) ;
  - `src/server/Avatar/AvatarAppearance.luau` (pose de la tenue), `AvatarSerializer.luau`
    (ornement) ;
  - `src/server/Data/ProfileSchema.luau`, `ProfileStore.luau` (v4) ;
  - `src/client/AvatarCreator/AvatarCreatorCatalog.luau` (étape Ornement, fiches de tenue),
    `AvatarCreatorView.luau` (vignettes aux couleurs de la tenue) ;
  - `src/shared/NPC/NpcConfig.luau`, `src/server/NPC/NpcSpawner.luau` (deux PNJ) ;
  - `tools/sim/helpers.luau`, `tools/sim/boot_test.luau`, `tools/sim/run_all.sh`.

## 7. Limites connues, à regarder en priorité dans Studio

- **Corps arrondis** : sur les bundles Homme et Femme, les plaques plates (pourpoint, plastron)
  peuvent laisser voir un peu du corps aux angles, ou le dépasser. Dis-moi lesquelles.
- **Pointe des coins** (broche elfique, sablier) : leur orientation suit celle des pièces en coin
  de Roblox, que je n'ai pas pu voir.
- **Cheveux** : selon la coiffure, le diadème peut être en partie caché par la frange, et une
  coiffure très volumineuse peut traverser la capuche rabattue.
- **Capes et pans** : rigides (pas de tissu simulé). Lors d'un double saut ou d'une attaque
  plongeante, une jambe peut passer brièvement à travers un pan.

## 8. Test dans Studio

1. **Import** : remplace `ReplicatedStorage > Shared` par `Shared.rbxmx`,
   `ServerScriptService > Server` par `Server.rbxmx`, et
   `StarterPlayer > StarterPlayerScripts > Client` par `Client.rbxmx`.
2. **Rouvrir le créateur avec un personnage existant** : dans
   `Shared > Avatar > AvatarConfig`, passe `DEBUG_ALWAYS_OPEN_CREATOR` à `true`. Rien n'est
   effacé ; repasse-le à `false` après le test.
3. **Play**, puis dans le créateur :
   - étape *Tenue* : parcours les quatre premières. Fais tourner la vue au glisser (face, profil,
     dos) et regarde l'ajustement : épaules, ceinture, capes, pans, bottes ;
   - change de **peuple** avec chaque tenue (Nain, Elfe) et joue sur les **proportions** (taille,
     carrure) ;
   - étape *Ornement* : barbes, diadème, sablier, avec plusieurs coiffures ;
   - étape *Marques* : le visage doit rester entièrement visible.
4. **Valide**, puis en jeu : sprint, double saut, les cinq coups d'épée, les deux sorts et
   l'ultime. Les pièces suivent le corps et rien ne te gêne.
5. **Respawn** (Réinitialiser le personnage) : la tenue revient.
6. **Explorer** : `Workspace > <ton personnage> > Costume` contient les pièces (CanCollide
   décoché, Massless coché).
7. **Village** : va voir **Le Forgeron** et **Corvin l'Archiviste**, et parle-leur (dialogues
   inchangés).
8. **Deux joueurs** (Test > Clients et serveurs > 2 joueurs) : chacun voit la tenue de l'autre.
9. **Facultatif** : `require(game.ReplicatedStorage.Shared.Avatar.AvatarAudit).run()` pour
   vérifier les assets du catalogue existants.

Envoie-moi ton avis tenue par tenue (ajustement, cohérence avec le monde, couleurs), et une
capture si quelque chose dépasse ou flotte. J'ajusterai avant d'étendre le catalogue.
