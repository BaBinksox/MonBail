# Musiques pour le jeu publié : statut réel et étapes d'approbation

## 1. La situation, sans détour

- Les musiques que tu entends dans Studio (créateur, village, boss) viennent de **l'essai
  automatique**. Il ne fonctionne que dans Studio (`AudioConfig.CANDIDATE_TRIAL.studioOnly = true`).
- **Aucune piste n'est encore inscrite dans `AudioConfig`.** Sur le jeu publié, ces contextes sont
  donc **silencieux** pour l'instant.
- Je n'ai pas accès à ton Studio ni à ta sortie. Je ne sais donc pas **quelles** pistes tu as
  entendues : l'essai prend le premier candidat qui se charge, et cela dépend de ce que Roblox
  autorise pour ton expérience.
- Une piste ne devient définitive que lorsque **toi** tu l'as écoutée et acceptée. Je recopie
  alors son ID dans `AudioConfig` (ou tu le fais toi-même, §4). Dès lors, elle joue aussi en jeu
  publié. C'est testé : « jeu publié : la piste approuvée (AudioConfig) est jouée ».

## 2. Ce dont j'ai besoin de toi (10 minutes)

1. **Studio, mode édition**, barre de commande :
   ```lua
   local A = require(game.ReplicatedStorage.Shared.Audio.AudioAudit) A.run()
   ```
   Attends `==== Fin.`, puis **copie tout le bloc** entre `==== AudioAudit` et `==== Fin.`. Il dit
   pour chaque piste si elle se charge, sa durée réelle, son nom et son créateur chez Roblox.
2. **Play**, puis promène-toi : créateur, belvédère, village (jour et nuit si possible), forêt,
   crypte, lac, un combat, le boss, une anomalie (rembobinage). Dans la fenêtre Sortie, filtre
   sur `[Musique]` et **copie les lignes**. Celles en `LECTURE CONFIRMÉE` prouvent qu'une piste a
   vraiment joué.
3. **Écoute** ce qui te plaît ou t'intrigue : `A.listen("forest", 2)`, puis `A.stop()`.
4. **Envoie-moi** ces deux blocs et, pour chaque contexte, ton verdict. Par exemple :
   « créateur : n°1 oui ; village : aucune ; boss : n°1 oui ; forêt : n°2 oui ».

Avec ça, j'inscris les pistes approuvées dans `AudioConfig` et je te renvoie les exports.

## 3. Tableau des musiques proposées

Statut commun à toutes les lignes, faute d'accès à ton Studio :
- **trouvé** : oui (recherche web, source dans `docs/MUSIQUE.md`) ;
- **chargé en Studio** : à confirmer (`A.run()`) ;
- **lu en jeu** : à confirmer (ligne `LECTURE CONFIRMÉE`) ;
- **approuvé** : à décider par toi.

« Essayé auto » : l'ordre dans lequel l'essai automatique les tente. « — » = jamais essayé
automatiquement (téléversement de particulier, droits inconnus), mais écoutable avec `A.listen`.

| Contexte | Ligne d'`AudioConfig` | Candidats (n°, titre, ID, licence annoncée) | Essayé auto |
|---|---|---|---|
| Créateur | 48 `creator` | 1 Sad Story (Piano & Harp) 1838577168 *store* · 2 Tears Of Sorrow 1843286166 *APM* · 3 Sad End (Solo Piano) 1838635121 *APM* | 1, 2, 3 |
| Belvédère | 49 `overlook` | 1 Abyssal Plain (Cello Lead) 9042861406 *APM* · 2 Paradise Falls 1837879082 *plage Roblox* | 1, 2 |
| Village (jour) | 50 `village` | 1 Hope And Glory 1842715333 · 2 Bright Middle Ages Music 1836089893 · 3 Medieval Magic 1846853445 · 4 Medieval (b) 9045862826 — tous *plage Roblox* | 1 à 4 |
| Village (nuit) | 51 `village_night` | 1 Nocturne Op. 9 n° 2 9045765634 · 2 Claire De Lune 1838457617 · 3 Calm Piano Music for Studying 108595570567760 *particulier* | 1, 2 |
| Forêt | 52 `forest` | 1 The Mysterious Book 1838592519 · 2 Fantasy In Blue 1847052146 · 3 Relaxed Scene 1848354536 *APM* | 1 à 3 |
| Forêt (nuit) | 53 `forest_night` | 1 Night Forest Ambience 7274920568 *particulier* · 2 Claire De Lune 1838457617 | 2 |
| Crypte | 54 `crypt` | 1 Suspense 1838865835 *APM* · 2 Forgotten Crypt 139743346356072 *particulier* · 3 Scary Ambience 1835337424 | 1, 3 |
| Lac | 55 `lake` | 1 Claire De Lune 1838457617 · 2 Celestial Calm 84386740040301 *particulier* · 3 Abyssal Plain 9042861406 *APM* | 1, 3 |
| Présence ennemie | 62 `hostile` | 1 Suspense 1838865835 *APM* · 2 Chase Me 9042675817 *APM* | 1, 2 |
| Combat | 63 `combat` | 1 Epic Middle Ages Music 1836089842 · 2 Ancient Myths 1837779548 *APM* · 3 Dragon Castle 5838262840 *particulier* | 1, 2 |
| Boss | 64 `boss` | 1 Ancient Myths 1837779548 *APM* · 2 Epic Boss Music 87773547872492 *particulier* · 3 Boss Fight! 78744747224727 *particulier* | 1 |
| Anomalie | 65 `anomaly` | 1 Midnight Litany of Drones 140704980462451 *particulier* · 2 Suspense 1838865835 *APM* | 2 |
| Victoire | 66 `victory` | 1 Victory 1837507072 · 2 victory.wav 12222253 *store, effet Roblox* · 3 Victory 1837507091 | 1 à 3 |
| Chœur du rembobinage | 88 `REWIND_CHOIR.id` | 1 Angelic Choir 1840524246 *plage Roblox* | 1 |

Décisions artistiques à prendre en priorité :
- **Suspense** sert de repli à trois contextes (crypte, présence ennemie, anomalie). Il faudra en
  choisir une autre pour au moins deux d'entre eux.
- **Chase Me** et **Scary Ambience** sont annoncées comme horrifiques : à refuser si elles cassent
  l'ambiance.
- **Ancient Myths** couvre à la fois le combat (repli) et le boss : mieux vaut deux pistes
  différentes.
- **Abyssal Plain** et **Claire De Lune** reviennent dans plusieurs contextes : à répartir.

## 4. Inscrire une piste approuvée (si tu veux le faire toi-même)

Dans `src/shared/Audio/AudioConfig.luau`, à la ligne du contexte, remplace le premier `""` par
l'ID. Par exemple, ligne 48 :

```lua
	creator = track("rbxassetid://1843286166", 0.45, "Thème principal : …", 4, 3),
```

Pour le chœur, ligne 88 : `id = "rbxassetid://1840524246",`.

`A.snippet()`, après `A.run()`, imprime ces lignes toutes prêtes pour le premier candidat chargé
de chaque contexte. Ne recopie que celles que tu as acceptées à l'écoute. Ensuite, réimporte
`Shared` (ou resynchronise avec Rojo).

## 5. Autorisations des assets (ce qui fera ou non jouer une piste en publié)

| Type | En jeu publié | À vérifier |
|---|---|---|
| Musique **sous licence Roblox** (APM Music, créateur affiché « Roblox » ou APM) | joue dans toute expérience | le créateur dans le rapport d'`A.run()` ; Roblox limite le nombre de pistes APM par jeu |
| Asset **public du Creator Store** | joue si son auteur l'a laissé public | qu'il se charge en Studio (`A.run()`) |
| **Téléversement d'un particulier** | souvent **bloqué** depuis 2022 (audio privé par défaut) | il faut l'accord de l'auteur, qui doit autoriser ton expérience dans les permissions de l'asset |
| **Ton propre téléversement** (Creator Hub > Création > Audio) | joue dans tes expériences | si l'expérience appartient à un groupe, l'audio doit appartenir au même groupe ou y être autorisé |

Un ID qui se charge dans Studio **pour ton expérience** se chargera aussi en publié, pour la même
expérience. En revanche, une piste qui se charge n'est pas pour autant approuvée : c'est ton
écoute qui décide.

## 6. Contextes couverts une fois les pistes inscrites

Créateur (`creator`), village (`village`, `village_night`), forêt (`forest`, `forest_night`),
crypte et creux (`crypt`), lac et cathédrale (`lake`), belvédère (`overlook`), présence ennemie
(`hostile`), combats (`combat`), boss (`boss`), anomalies (`anomaly`), victoire (`victory`),
rembobinage (`REWIND_CHOIR`).

Tous passent par MusicDirector :
- une seule piste à la fois, avec fondus ;
- priorités : créateur > anomalie > boss > combat > victoire > présence ennemie > région ;
- curseur « Musique » du joueur (le chœur suit le curseur « Effets »).

## 7. Sons à importer pour aller plus loin

Les sons des magies utilisent pour l'instant des fichiers **livrés avec Roblox** (`swoosh`,
`glassbreak`, `snap`, `splat`, `collide`, `Rocket whoosh 01`, `Rocket shot`), différenciés par la
hauteur. `A.run()` vérifie qu'ils existent (lignes `[builtin:…]`). Un fichier absent reste muet,
sans erreur.

Pour des sons vraiment propres à chaque magie, télécharge des sons sous licence libre (par
exemple le pack *Magic Sound Effects – Elemental Pack* ou *Freeze Spell*, voir `docs/MUSIQUE.md`
§4). Téléverse-les ensuite sur ton compte (Creator Hub > Création > Audio), puis envoie-moi les
ID ou colle-les à la place des chemins `rbxasset://` :

| Emplacement (`AudioConfig.SFX`) | Ce qu'il faut chercher |
|---|---|
| `cast_pyromancy` / `impact_pyromancy` | souffle de flamme / explosion de feu courte |
| `cast_ice` / `impact_ice` | cristallisation / glace qui se brise |
| `cast_lightning` / `impact_lightning` | crépitement / claquement de foudre court |
| `cast_shadow` / `impact_shadow` | souffle grave / impact étouffé |
| `cast_antimatter` / `impact_antimatter` | son inversé qui se contracte / implosion sourde |
| `cast_gravity` / `impact_gravity` | grondement / écrasement lourd |
| `manaFull`, `concentrate`, `ultimateReady`, `swordBlocked`, `postureBreak` | note cristalline, nappe montante, accord bref, métal contre métal, craquement |
