# Musique et sons : recherche, candidats, vérification dans Studio

## 1. Ce que j'ai pu faire, et pourquoi pas plus

**Je n'ai pas pu ouvrir le catalogue Roblox.** Le réseau de mon environnement refuse les connexions
vers `create.roblox.com`, `apis.roblox.com`, `economy.roblox.com`, `assetdelivery.roblox.com` et
`devforum.roblox.com` (refus du proxy, code 403). Il refuse aussi les sites de listes de codes
(`robloxden.com`, `bloxodes.com`, `robloxsong.com`). Seul le moteur de recherche web répondait. Je n'ai
donc pu ni écouter une piste, ni voir sa page, ni confirmer son créateur ou sa durée.

Ce qui a été fait :

1. **Recherche web** des pistes et des sons pour chaque contexte. Les identifiants viennent tels quels
   des pages citées. Aucun n'a été deviné ou complété.
2. **Rangement** de ces résultats dans `src/shared/Audio/AudioCandidates.luau`, avec leur source, leur
   durée annoncée et leur catégorie de licence. Chacun porte le statut **« trouvé, non vérifié »**.
3. **Aucun de ces ID n'est écrit dans `AudioConfig`.** Un test le vérifie (`audio_test` : « aucun
   candidat non vérifié recopié dans AudioConfig »).
4. **Essai automatique dans Studio** (`CandidateResolver`). Pour chaque emplacement encore vide, le jeu
   essaie les candidats dans l'ordre. Il garde le premier qui se **charge vraiment** et dont la durée
   réelle correspond à celle annoncée par la source. Il l'annonce dans la sortie comme un ESSAI. Vous
   entendez donc de la musique dès le Play dans Studio, sans que rien soit déclaré vérifié.
5. **Outil de vérification** (`AudioAudit`). Il charge chaque candidat dans Studio et affiche le nom
   et le créateur enregistrés chez Roblox, la durée réelle, et les lignes à recopier.

### Échelle des statuts (colonne « Statut » des tableaux)

| Étape | Qui l'établit | Où le voir |
|---|---|---|
| trouvé | recherche web (moi) | ce document, `AudioCandidates` |
| autorisé | la licence annoncée par la source ; **confirmée** quand `AudioAudit.run()` montre le bon créateur (APM / Roblox, ou vous) | rapport d'AudioAudit |
| importé | candidat ajouté au projet (essai Studio) ; **définitif** quand l'ID est recopié dans `AudioConfig` | `AudioCandidates` / `AudioConfig` |
| chargé en Studio | `AudioAudit.run()` ou l'essai automatique | sortie : `CHARGÉ m:ss` ou `[Musique] … ESSAI …, chargé` |
| testé en lecture | le jeu, après quelques secondes de lecture réelle | sortie : `[Musique] LECTURE CONFIRMÉE : <contexte> ← …` |

Aujourd'hui, **toutes** les entrées sont au mieux « trouvé + importé comme candidat ». Aucune n'est
« chargé en Studio » ni « testé en lecture ». Ces deux statuts ne peuvent venir que de votre Studio.

### Catégories de licence

| Code | Signification | Essayé automatiquement ? |
|---|---|---|
| `roblox` | la source la présente comme musique **sous licence Roblox** (APM Music) | oui |
| `store` | la source est la **page Creator Store** de l'asset (publié pour être réutilisé) | oui |
| `range` | ID dans la plage du catalogue sous licence Roblox, **fournisseur non confirmé** par la source | oui (vérifier le créateur) |
| `user` | téléversement d'un particulier, vu seulement sur des listes de fans : **droits inconnus** | **non** (`CANDIDATE_TRIAL.licenses.user`) |

Les musiques sous licence Roblox (APM) sont utilisables dans toute expérience. Roblox limite leur
nombre par jeu (une limite de 250 est évoquée sur le forum des développeurs). Le jeu en utilise au plus
une douzaine.

## 2. Musiques : tableau des candidats

Direction : fantasy mystérieuse et mélancolique, piano, cordes, harpe, voix éthérées. Pas d'horreur
permanente, pas de drone continu, aucune musique d'anime ni imitation. Ordre = ordre d'essai.
Durée = celle **annoncée par la source** (« ? » = non annoncée). Statut de toutes les lignes :
**trouvé, importé comme candidat, non chargé, non testé**.

| Contexte (clé) | Piste | Créateur / fournisseur annoncé | Source | ID Roblox | Durée | Licence |
|---|---|---|---|---|---|---|
| Intro / créateur (`creator`) | Sad Story (Piano & Harp) | Xavier Berthelot, album *Sorrows of Life* | [Creator Store](https://create.roblox.com/store/asset/1838577168) | 1838577168 | 2:04 | store |
| | Tears Of Sorrow | APM Music | [hone.gg](https://hone.gg/blog/roblox-song-ids-music-codes/) | 1843286166 | 2:03 | roblox |
| | Sad End (Solo Piano) | APM Music (APMOfficial) | [robloxsong (orchestra)](https://robloxsong.com/artist/3379-orchestra) | 1838635121 | 2:33 | roblox |
| Belvédère (`overlook`) | Abyssal Plain (Cello Lead Version) | APM Music | [hone.gg](https://hone.gg/blog/roblox-song-ids-music-codes/) | 9042861406 | 3:07 | roblox |
| | Paradise Falls | ? | agrégateurs ([robloxcalc](https://robloxcalc.com/roblox-id-songs/), [g2a](https://www.g2a.com/news/features/games-codes/roblox-music-codes/)) | 1837879082 | ? | range |
| Village des Cendres, jour (`village`) | Hope And Glory | Daniel Richard Price, *Celtic Folk* | [bloxodes](https://bloxodes.com/catalog/roblox-music-ids/artists/daniel-richard-price) | 1842715333 | 2:22 | range |
| | Bright Middle Ages Music | ? | [robloxsong](https://robloxsong.com/song/1836089842-epic-middle-ages-music) | 1836089893 | ? | range |
| | Medieval Magic | Robert James Bruce | [bloxodes](https://bloxodes.com/catalog/roblox-music-ids/artists/robert-james-bruce) | 1846853445 | 2:14 | range |
| | Medieval (b) | ? | [robloxsong](https://robloxsong.com/song/9045862826-medieval-b) | 9045862826 | ? | range |
| Village, nuit (`village_night`) | Nocturne in E-Flat Major, Op. 9 No. 2 | ? (Chopin, œuvre du domaine public) | agrégateurs (voir Paradise Falls) | 9045765634 | ? | range |
| | Claire De Lune | ? (Debussy, œuvre du domaine public) | agrégateurs (voir Paradise Falls) | 1838457617 | ? | range |
| | Calm Piano Music for Studying | téléversement | [robloxsong](https://robloxsong.com/song/108595570567760-calm-piano-music-for-studying) | 108595570567760 | ? | user |
| Forêt des Murmures (`forest`) | The Mysterious Book | Xavier Berthelot, *The Magic Land* | [bloxodes](https://bloxodes.com/catalog/roblox-music-ids/artists/xavier-berthelot) | 1838592519 | ? | range |
| | Fantasy In Blue | Robert James Bruce | [bloxodes](https://bloxodes.com/catalog/roblox-music-ids/artists/robert-james-bruce) | 1847052146 | 3:32 | range |
| | Relaxed Scene | APM Music | [Creator Store](https://create.roblox.com/store/asset/1848354536/Relaxed-Scene) | 1848354536 | ? | store |
| Forêt, nuit (`forest_night`) | Night Forest Ambience Sound | téléversement | [rocodes](https://rocodes.gg/music/tags/ambient) / [musiccoder](https://musiccoder.com) | 7274920568 | ? | user |
| | Claire De Lune | (voir plus haut) | | 1838457617 | ? | range |
| Crypte (`crypt`) | Suspense | APM Music | [Creator Store](https://create.roblox.com/store/asset/1838865835) | 1838865835 | ? | store |
| | Forgotten Crypt | téléversement | [theclick.gg](https://www.theclick.gg/roblox-scary-sound-ids/) | 139743346356072 | ? | user |
| | Scary Ambience | ? | [theclick.gg](https://www.theclick.gg/roblox-scary-sound-ids/) | 1835337424 | ? | range |
| Lac (`lake`) | Claire De Lune | (voir plus haut) | | 1838457617 | ? | range |
| | Celestial Calm | téléversement | [gameboost](https://gameboost.com/blog/roblox-music-codes) | 84386740040301 | ? | user |
| | Abyssal Plain (Cello Lead Version) | APM Music | (voir belvédère) | 9042861406 | 3:07 | roblox |
| Présence ennemie (`hostile`) | Suspense | APM Music | (voir crypte) | 1838865835 | ? | store |
| | Chase Me | APM Music | [Creator Store](https://create.roblox.com/store/asset/9042675817/Chase-Me) | 9042675817 | ? | store |
| Combat normal (`combat`) | Epic Middle Ages Music | ? | [robloxsong](https://robloxsong.com/song/1836089842-epic-middle-ages-music) | 1836089842 | ? | range |
| | Ancient Myths | APM Music | wikis de fans ([Slap Battles](https://roblox-slap-battles.fandom.com/wiki/Soundtracks), [Field of Battle](https://roblox-field-of-battle-official-community.fandom.com/wiki/Music)) | 1837779548 | ? | roblox |
| | Dragon Castle / Epic Orchestral Battle Music | téléversement | [Field of Battle wiki](https://roblox-field-of-battle-official-community.fandom.com/wiki/Music) | 5838262840 | ? | user |
| Boss (`boss`) | Ancient Myths | APM Music | (voir combat) | 1837779548 | ? | roblox |
| | Epic Boss Music | téléversement (2024) | [robloxsong](https://robloxsong.com/song/87773547872492-epic-boss-music) | 87773547872492 | ? | user |
| | Boss Fight! | téléversement (2024) | [robloxsong](https://robloxsong.com/song/78744747224727-boss-fight) | 78744747224727 | ? | user |
| Anomalie temporelle (`anomaly`) | Midnight Litany of Drones | téléversement | [theclick.gg](https://www.theclick.gg/roblox-scary-sound-ids/) | 140704980462451 | ? | user |
| | Suspense | APM Music | (voir crypte) | 1838865835 | ? | store |
| Victoire (`victory`) | Victory | ? | [robloxsong](https://robloxsong.com/song/1837507072-victory) | 1837507072 | ? | range |
| | victory.wav | Roblox (effet sonore) | [Creator Store](https://create.roblox.com/store/asset/12222253/victorywav) | 12222253 | ? | store |
| | Victory | ? | [musiccoder](https://musiccoder.com/codes/detail/3249-victory) | 1837507091 | ? | range |
| Chœur féminin du rembobinage | Angelic Choir | ? | [robloxsong](https://robloxsong.com/song/1840524246-angelic-choir) | 1840524246 | ? | range |

Remarques d'écoute à faire en priorité :
- **Chase Me** et **Scary Ambience** sont décrites comme horrifiques (orgue, cloches). Elles ne sont là
  qu'en repli. Refusez-les si elles cassent l'ambiance.
- **Suspense** sert à trois contextes (crypte, présence ennemie, anomalie). C'est acceptable pour un
  essai, pas pour la version finale.
- **Angelic Choir** est sans doute une piste longue. Le jeu n'en garde que 3 s, avec fondus
  (`REWIND_CHOIR.maxDuration`).
- `elf_village` et `dwarf_halls` (régions futures) n'ont pas de candidat.

## 3. Effets sonores

| Besoin | État actuel dans le jeu | Candidat trouvé (statut : trouvé, non vérifié) | Licence |
|---|---|---|---|
| Balayage léger de l'épée | `rbxasset://sounds/swordlunge.wav` (son livré avec Roblox), aigu, varié, 0,12 s mini (Livraison A) | Sword Swing 6603295777, Sword Swing 1 969679894 ([robloxsong](https://robloxsong.com/artist/76557-the-sword?page=4)) : pas branchés, l'emplacement est déjà rempli | user |
| Impact sur la cible | `swordslash.wav` (livré avec Roblox), seulement si le coup porte | Sword Hit 1306077413 (même liste) : non branché | user |
| Impact sur une garde | vide | Sword Parry 7058511334, Sword Parry 5 7058511971 ([robloxsong](https://robloxsong.com/artist/76557-the-sword?page=4)) | user |
| Parade parfaite | `unsheath.wav` aigu (livré avec Roblox) | aucun | |
| Attaque lourde | `swordlunge.wav` grave | aucun | |
| Esquive / dash | vide | sword-swing-whoosh-sound-effect-1-full-pack 135315310485417 ([Creator Store](https://create.roblox.com/store/asset/135315310485417/swordswingwhooshsoundeffect1fullpack)) | store |
| Foudre (impact) | vide | lightning bolt 224339201 ([wiki Slap Battles](https://roblox-slap-battles.fandom.com/wiki/Sound_Effects)), lightning strike 7138705968 ([forum](https://devforum.roblox.com/t/best-way-to-create-a-lightning-effect/1367669)) | user |
| Pyromancie (impact) | vide | explosion 9114362266 ([wiki Slap Battles](https://roblox-slap-battles.fandom.com/wiki/Sound_Effects)) | user |
| Impact au sol (plongeante) | vide | impact 5540424854 ([wiki Slap Battles](https://roblox-slap-battles.fandom.com/wiki/Sound_Effects)) | user |
| Glace, Ombre, Antimatière, Gravité | vides | rien de fiable côté Roblox. Voir sources libres §4 | |
| Montée de Mana | vide | aucun | |
| Double saut | `action_jump.mp3` aigu (livré avec Roblox) | aucun | |
| Chœur du rembobinage | vide | Angelic Choir 1840524246 (voir §2) | range |

Les candidats `user` ne sont **pas** essayés automatiquement. Pour les écouter :
`AudioAudit.listen("sfx:swordBlocked")`. Pour autoriser leur essai :
`AudioConfig.CANDIDATE_TRIAL.licenses.user = true`. Pour un usage définitif, il vous faut l'accord de
leur auteur.

## 4. Sources libres à téléverser sur votre compte

Pour les six magies et la montée de Mana, la voie la plus sûre est de télécharger des sons sous licence
libre, de les téléverser (Creator Hub > Création > Audio) puis de coller l'ID obtenu. Il vous
appartient et se charge partout. Licences **à relire** avant usage :

| Pack | Fournisseur | Licence annoncée | Usage |
|---|---|---|---|
| [Sword](https://mixkit.co/free-sound-effects/sword/) | Mixkit | Mixkit Sound Effects Free License | souffles, impacts, garde |
| [Freeze Spell](https://opengameart.org/content/freeze-spell-0) | OpenGameArt | CC0 | glace |
| [Ice & Electricity Magic](https://opengameart.org/content/ice-electricity-magic) | OpenGameArt | CC-BY 3.0 (crédit) | glace, foudre |
| [Game Victory](https://www.fiftysounds.com/royalty-free-music/game-victory.html) | FiftySounds | gratuite, sans attribution selon le site | victoire |
| [Bibliothèque Kevin MacLeod](https://incompetech.com) | incompetech | CC BY 4.0 (crédit) | piano, cordes |
| [Fantasy Music Collection](https://donat-baracsi.itch.io/fantasy-music-collection/purchase) | Donat Baracsi | licence du pack | thèmes de région |
| [Magic SFX – Elemental Pack](https://high-impact-media.itch.io/magic-sound-effects-elemental-pack) | High Impact Media | licence du pack | six magies |

## 5. Procédure dans Studio (10 minutes)

1. Importez `build/Shared.rbxmx` et `build/Client.rbxmx` (ou synchronisez avec Rojo).
2. **Vérification du catalogue** : en mode édition, dans la barre de commande :
   ```lua
   local A = require(game.ReplicatedStorage.Shared.Audio.AudioAudit) A.run()
   ```
   Attendez la ligne `==== Fin.` dans la sortie. Pour chaque candidat, une ligne `CHARGÉ m:ss` ou
   `ÉCHEC`, avec `Roblox : « nom » par créateur`. Vérifiez :
   - que le **nom enregistré** correspond au titre annoncé ;
   - que le **créateur** est le compte Roblox ou APM pour les lignes `roblox` / `range` ;
   - qu'il n'y a pas d'avertissement `SOURCE : … → autre piste ?`.
3. **Écoute** : `A.listen("creator", 1)`, `A.listen("creator", 2)`, … puis `A.stop()`. Contextes :
   `creator`, `overlook`, `village`, `village_night`, `forest`, `forest_night`, `crypt`, `lake`,
   `hostile`, `combat`, `boss`, `anomaly`, `victory`, `choir`, `sfx:<nom>`.
4. **En jeu** (Play) : la sortie affiche `[Musique] creator : ESSAI de « … »` puis, environ 4 s plus
   tard, `[Musique] LECTURE CONFIRMÉE : creator ← « … »`. Seule cette seconde ligne vaut « testé en
   lecture ». Marchez jusqu'au village, à la forêt et à la crypte, engagez un combat, déclenchez un
   rembobinage : chaque contexte doit produire ses deux lignes.
5. **Rendre définitif** : `A.snippet()` affiche une ligne par contexte, par exemple
   `TRACKS.creator = "rbxassetid://1843286166" -- « Tears Of Sorrow »…`. Pour chaque piste **écoutée
   et acceptée**, remplacez le `""` correspondant dans `src/shared/Audio/AudioConfig.luau`. Elle sera
   alors jouée aussi sur le jeu publié. L'essai automatique, lui, ne fonctionne que dans Studio
   (`CANDIDATE_TRIAL.studioOnly`).
6. Si aucun candidat d'un contexte ne se charge, la sortie l'indique :
   `[Musique] boss : aucun candidat utilisable (…) : silence`. Le contexte reste alors silencieux, sans
   erreur. Cherchez dans Toolbox > Audio avec les critères de `criteria` (dans `AudioConfig`), ou
   téléversez un fichier libre (§4).

Rien dans la logique de musique n'a changé : une seule piste à la fois, mêmes fondus, mêmes priorités
(créateur > anomalie > boss > combat > victoire > présence hostile > région), mêmes volumes du joueur.
