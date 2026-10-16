# Les Échos du Néant — Correctifs après les tests dans Roblox Studio

Les huit fonctionnalités validées dans Studio n'ont pas été touchées : placement et apparition,
roulette, Grimoire, collisions, carte (aucune reconstruction), nuit, sauvegarde (pas de changement
de schéma). Les tests ci-dessous ont été faits dans le **simulateur du dépôt**, pas dans Studio.

## 1. Teints clairs surexposés

**Cause** — trois facteurs qui ne touchent que les peaux très claires :
1. **Palette** : Porcelaine `(246, 222, 206)` et Clair `(234, 196, 168)` étaient presque blancs
   (luminance 0,89 et 0,80), Rosé `(226, 180, 158)` à 0,74.
2. **Éclairage additif du créateur** : la lumière clé du studio (0,85) et le débouchage s'ajoutent au
   soleil de jour (Brightness 2,6, exposition +0,1). Sur une couleur déjà presque blanche, le rendu
   sature.
3. **Bloom du monde actif dans le créateur** (intensité 0,6 à 1,0, seuil 1,2 à 1,6 selon l'heure) :
   seules ces peaux saturées dépassaient le seuil et se mettaient à « briller ». Les teints moyens et
   foncés restent sous le seuil, d'où un défaut limité aux premiers teints.

Vérifié aussi : la tête classique est en `Plastic`, sans réflectance (pas en cause). Le teint est
appliqué aux six parties du corps et à la tête, sans double application.

**Correction**
- `src/shared/Avatar/AvatarConfig.luau` : Porcelaine `(224, 198, 180)`, Clair `(220, 184, 158)`,
  Rosé `(216, 172, 150)`. Ils restent clairs (luminance 0,79 / 0,74 / 0,70) et gardent le même ordre.
- `src/client/AvatarCreator/AvatarCreatorCamera.luau` : lumière clé et débouchage adaptés à la
  luminance de la tête (`skinLightFactor`) : 100 % jusqu'à 0,65, puis jusqu'à 55 % pour les peaux
  les plus claires. Teints moyens, foncés et surnaturels : **exactement le même éclairage**.
- `src/client/World/WorldAtmosphere.client.luau` : pendant le créateur uniquement, bloom à 25 % et
  seuil relevé à 2,2. La lumière de la scène n'est pas assombrie.

## 2. La caméra de la cinématique d'arrivée traverse le décor

**Cause** (`src/client/World/ArrivalController.client.luau`, ancienne version) : le plan partait de
l'ancre `camera_overlook` (11 studs au-dessus de la terrasse). Le travelling avançait de 18 studs vers
la place **en descendant de 7,5 studs** : il finissait à y = 45,9 pour une terrasse à 46,0 — la
caméra terminait **dans le sol**. Elle rejoignait ensuite le joueur par un `Lerp` en ligne droite.
**Aucun raycast** ne vérifiait la trajectoire. Ce défaut est reproduit par le test (« ancienne fin de
travelling : −0,1 stud au-dessus du sol »).
Le placement du personnage (SpawnService, CharacterPlacement) n'était pas en cause et n'a pas changé.

**Correction** — nouvelle cinématique de découverte :
1. Écran noir (fin du créateur).
2. **Panorama** (10 s) : fondu d'ouverture sur le village vu de très haut, derrière le belvédère. Lente
   descente en arc vers l'est du village ; le regard glisse des toits et de la place vers la chapelle
   sur sa butte, puis le lac de la cathédrale. Le titre de la région apparaît pendant ce plan.
3. **Court fondu au noir** (0,7 s) : la caméra ne traverse jamais la colline entre village et joueur.
4. **Approche** (3,6 s) : depuis l'ancre au-dessus du joueur, qui contemple le village, descente douce
   jusqu'à la caméra de jeu derrière lui. Les bandes cinéma se retirent.
5. Caméra normale et contrôles rendus.

- Nouveau `src/client/World/ArrivalPath.luau` : points de passage en spline de Catmull-Rom. Chaque
  plan est **vérifié avant d'être joué**, tous les 2,5 studs :
  - rayon entre échantillons voisins (murs, piliers, troncs) ;
  - rayon tombé du ciel (jamais sous le terrain, une montagne, un toit, avec marge).
  
  Un panorama obstrué est relevé (jusqu'à 4 × 12 studs), sinon remplacé par un fondu. Une approche
  obstruée devient une coupe directe sur la caméra de jeu. La caméra de jeu se rapproche si un obstacle
  est entre elle et le personnage. Tout est calculé à partir de la **tête réelle** du personnage
  (Elfe, Nain, Humain).
- Sûreté : réapparition ou mort pendant la cinématique → caméra et contrôles rendus aussitôt. Filet de
  30 s maximum. Le personnage n'est jamais déplacé par la cinématique.

## 3. Fichiers modifiés

```
src/client/World/ArrivalPath.luau               (nouveau)
src/client/World/ArrivalController.client.luau
src/client/AvatarCreator/AvatarCreatorCamera.luau
src/client/World/WorldAtmosphere.client.luau
src/shared/Avatar/AvatarConfig.luau
tools/sim/arrival_test.luau                     (nouveau)
tools/sim/creator_test.luau
tools/sim/run_all.sh
docs/CORRECTIFS_STUDIO.md                       (nouveau)
```

## 4. Tests (simulateur, pas Studio)

Typecheck : 0 erreur. `run_all.sh` : **11 suites, 351 vérifications, 0 échec**. Audit géométrique : OK.

**Nouveau `arrival_test` (49 vérifications)**
- ancien défaut reproduit ;
- pour Humain, Elfe et Nain, sur la carte générée réelle :
  - panorama et approche jouables ;
  - panorama toujours ≥ 47 studs au-dessus du relief ; approche ≥ 9 studs ;
  - aucune entrée dans une pièce du décor (oracle indépendant des raycasts du jeu) ;
  - arrivée à 12,5 studs derrière la tête ;
  - personnage non déplacé ;
- replis (plan bloqué abandonné, plan trop bas relevé) ;
- teints clairs ≤ 0,80 de luminance et lumière adoucie ;
- 8 teints moyens, foncés et surnaturels : couleur et éclairage strictement inchangés.

**`creator_test` (+9 vérifications)**
- déroulé complet : caméra scénarisée pendant la cinématique, puis caméra Custom et écran rouvert ;
- réapparition en plein vol : caméra rendue aussitôt, pas de reprise ensuite.

**Non couvert** : le rendu réel de l'éclairage et du bloom ne peut être jugé que dans Studio.

## 5. Carte

**Pas de reconstruction** : le générateur n'a pas changé (`BUILD_VERSION` reste 3).

## 6. Vérifier dans Studio

Importer `Shared.rbxmx` (ReplicatedStorage), `Server.rbxmx` (ServerScriptService) et `Client.rbxmx`
(StarterPlayerScripts) en remplaçant les dossiers existants, ou synchroniser avec Rojo.
Pour revoir le créateur avec un personnage existant : `AvatarConfig.DEBUG_ALWAYS_OPEN_CREATOR = true`
(à remettre à `false` ensuite).

**Teints**
1. Play. Dans le créateur, étape **Teint** : passer Teint de votre avatar → Porcelaine → Clair →
   Rosé. La peau doit rester claire mais plus blanche ni « lumineuse ». Yeux, bouche, cicatrices et
   tatouages restent visibles (étape **Marques** avec Porcelaine).
2. Comparer avec Olivâtre, Ébène, Cendre : rendu identique à avant.
3. Si possible, tester de jour et au crépuscule (bloom plus fort) : les teints clairs ne brillent pas.

**Cinématique**
1. Terminer la création et confirmer.
2. Après le noir : vue panoramique du village depuis les hauteurs, descente lente sans **jamais** passer
   dans le terrain, une colline, un toit ou un arbre. Le titre s'affiche.
3. Court fondu, puis plan au-dessus du personnage debout sur la terrasse, face au village. La caméra
   descend derrière lui ; vous reprenez le contrôle.
4. Refaire avec un **Elfe** et un **Nain** (dernier plan bien cadré sur la tête).
5. Interruption : pendant la cinématique, barre de commande (côté serveur)
   `game.Players:GetPlayers()[1].Character.Humanoid.Health = 0`. La caméra doit être rendue aussitôt,
   sans écran noir bloqué.
6. Sortie (F9) : aucun message « [Arrival] … obstrué ». S'il en apparaît un, la cinématique a choisi
   un repli (fondu) : signalez-le avec le message.
