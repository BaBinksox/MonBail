# Rapport : sauvetage des animations et intégration musicale (livraisons A à F)

**Limite à garder en tête.** Je n'ai accès ni à Roblox Studio ni au réseau Roblox. Ce qui est
vérifié : le typage strict (`tools/typecheck.sh`), les 14 suites de simulation (`tools/sim/run_all.sh`),
la structure des séquences d'animation relue par Rojo, et la logique (quelle piste est jouée, à quel
moment, avec quel effet). **Rien n'a été vu ni entendu en jeu.** Les procédures du §8 servent à
cette vérification.

## 1. Livraisons et commits (branche `main`)

| Livraison | Commit | Contenu |
|---|---|---|
| A | `2dac2ce` | épée jouée par de vraies pistes d'animation (plus jamais de dégâts sans mouvement visible) ; son d'épée corrigé |
| B | `fa18ed7` | cinq mouvements d'épée distincts ; séquences éditables et publiables dans Studio |
| C | `d23b1ef` | Glace et Antimatière : gestuelles, sorts et ultimes refaits (chorégraphies dédiées) |
| D | `15ec17f` | Pyromancie, Foudre, Ombre, Gravité : gestuelles, effets de sorts et ultimes dédiés |
| E | `afd83f0` | recherche musicale, candidats, essai automatique dans Studio, outil de vérification |
| F | (ce commit) | fiches de magie complètes dans le créateur + aperçu visuel non destructif |

Point de restauration d'avant l'intervention : étiquette `avant-combat-2` sur le dépôt distant.

## 2. Fichiers modifiés ou créés

**Animation** : `src/shared/Animation/PoseLibrary.luau` (déplacé du client, 5 coups d'épée, gestes
recalés sur les temps d'incantation, 6 poses d'ultime), `KeyframeBuilder.luau` (nouveau),
`AnimationConfig.luau` (clips de repli, table `PUBLISHED`, actions d'ultime),
`src/client/Animation/CharacterAnimator.luau` (réécrit), `GeneratedAnimations.luau` (nouveau),
`AnimationDirector.client.luau`.

**Combat et magie** : `src/client/Combat/CombatController.client.luau`, `CombatEffects.luau`,
`src/client/Magic/MagicFx.luau` (nouveau), `SpellEffects.luau`, `UltimateChoreographies.luau`
(nouveau), `MagicPreview.luau` (nouveau), `src/shared/Magic/MagicConfig.luau` (`ultimateWindup`),
`MagicShowcase.luau` (nouveau), `src/server/Combat/CombatService.luau` (attente de la préparation de
l'ultime avant l'effet ; les dégâts eux-mêmes sont inchangés).

**Audio** : `src/shared/Audio/AudioConfig.luau`, `AudioCandidates.luau` (nouveau),
`AudioAudit.luau` (nouveau), `src/client/Audio/CandidateResolver.luau` (nouveau),
`MusicDirector.luau`, `MusicController.client.luau`, `SfxPlayer.luau`,
`src/client/TimeLoop/TimeLoopAudio.luau`.

**Créateur** : `src/client/AvatarCreator/AvatarCreatorView.luau`, `AvatarCreatorController.client.luau`.

**Outils et docs** : `tools/anim/export.sh`, `tools/anim/export_sequences.luau`, simulateur
(`tools/sim/mock.luau`, `runtime.luau`, `client.luau`), tests (`movement_test`, `combat_test`,
`spells_test`, `audio_test`, `creator_test`), `docs/ANIMATIONS.md`, `docs/MUSIQUE.md`,
`docs/ARCHITECTURE.md`, ce rapport.

Non touchés : quêtes, guildes, sauvegarde (aucun nouveau DataStore), sprint, double saut, Mana,
Tension, statuts, réactions élémentaires, rencontres multijoueur, rembobinage. Les coûts en Mana, les
deux sorts par magie, les altérations et les ultimes sont conservés. Aucune arme, race ou région ajoutée.

## 3. Animations utilisables

Pour chaque action, le jeu prend la première source disponible (détail dans `docs/ANIMATIONS.md`) :

1. clip **publié** sur votre compte (table `PUBLISHED`, vide pour l'instant) ;
2. **séquence générée** depuis `PoseLibrary`, dans Studio seulement ;
3. **anciens clips d'épée** Roblox (`522635514` Slash, `522638767` Lunge, ceux d'avant Combat 2.0),
   avec un accent du buste ;
4. **pose procédurale** seule. Une action n'est jamais invisible.

La sortie de Studio indique une fois la source de chaque action : `[Animation] sword_1 : …`.
37 séquences éditables : `build/AnimationSequences.rbxmx`, ou bien
`require(game.ReplicatedStorage.Shared.Animation.KeyframeBuilder).install()` dans la barre de commande.

## 4. Musique et sons

- **Recherche** : environ 40 candidats pour les 13 contextes et les effets. Chacun a sa source, sa
  durée annoncée et sa licence (`docs/MUSIQUE.md`, `AudioCandidates.luau`). Tous sont
  « trouvé, non vérifié ». Le catalogue Roblox n'était pas joignable d'ici.
- **ID intégrés comme définitifs dans `AudioConfig` : aucun.** Je n'ai pu ni charger ni écouter une
  seule piste. Les seuls sons actifs sont ceux livrés avec Roblox (`rbxasset://sounds/…` : épée,
  dégainer, saut).
- **Essai automatique dans Studio** : les emplacements vides prennent le premier candidat qui se
  charge vraiment. Il est annoncé `ESSAI`, puis `LECTURE CONFIRMÉE` après une lecture réelle.
- **Architecture conservée** : MusicDirector, une piste à la fois, fondus, priorités, volumes.

## 5. Ce qui attend une action de votre part

| Quoi | Pourquoi | Comment |
|---|---|---|
| Publier les 37 séquences d'animation | sur le jeu publié, les séquences générées n'existent pas : l'épée retombe sur les anciens clips, les sorts sur la pose procédurale | `docs/ANIMATIONS.md` §3, puis coller les ID dans `AnimationConfig.PUBLISHED` |
| Vérifier et accepter les musiques | aucune n'a été entendue | `docs/MUSIQUE.md` §5 (`AudioAudit.run()`, `listen`, `snippet`) |
| Sons des six magies, de la Mana, de la garde | aucun candidat fiable côté Roblox | téléverser des sons libres (`docs/MUSIQUE.md` §4) sur votre compte |
| Téléversements de particuliers | droits inconnus | n'utiliser qu'avec l'accord de l'auteur |

## 6. Fiches de magie (livraison F)

Chaque fiche de la page Destin affiche désormais :
- le nom et l'identité de la magie ;
- la difficulté (Accessible, Intermédiaire, Exigeante) ;
- le sort de base et le sort secondaire, avec leur coût en Mana et leur description (tirés de
  `SpellConfig`, donc toujours exacts) ;
- l'ultime et sa description, l'avantage principal, l'inconvénient principal ;
- le style tactique : une phrase et quatre jauges (dégâts, contrôle, mobilité, soutien).

Le bouton **Aperçu** fait enchaîner au personnage le geste du sort de base, celui du sort secondaire,
puis la pose d'ultime, avec les mêmes effets qu'en jeu. C'est purement local : aucune demande au
serveur, aucun dégât, ni Mana, ni Tension, ni recharge. Il ne change pas la magie choisie et ne
contourne pas la Roulette du Destin. Les profils (identité, jauges, difficulté) sont dans
`src/shared/Magic/MagicShowcase.luau`.

## 7. Tests

`bash tools/typecheck.sh` : aucune erreur. `bash tools/sim/run_all.sh` : 14 suites OK. Ce qui est
couvert en simulation :
- choix de la source d'animation et écriture sur `Motor6D.Transform` ;
- structure des séquences, sans saut de plus de 180° ;
- impact des coups dans la fenêtre de frappe du serveur ;
- gestes calés sur les temps d'incantation (±0,06 s) et ultimes calés sur la préparation (±0,03 s) ;
- chorégraphies des six ultimes et effets des douze sorts ;
- candidats audio : bien formés, aucun recopié dans `AudioConfig`, repli si un ID échoue, durée non
  conforme écartée, téléversements de particuliers jamais essayés, rien hors Studio, lecture
  confirmée ;
- fiches complètes, et un aperçu qui n'envoie rien au serveur.

La simulation ne remplace pas Studio : elle ne montre ni l'image, ni le son, ni la physique, ni le
réseau réel.

## 8. Vérification dans Studio (pas à pas)

1. **Import** : glissez `build/Shared.rbxmx` dans ReplicatedStorage (remplace `Shared`),
   `build/Server.rbxmx` dans ServerScriptService (remplace `Server`) et `build/Client.rbxmx` dans
   StarterPlayer > StarterPlayerScripts (remplace `Client`). Ou utilisez `rojo serve`.
2. **Créateur** : Play. À la page Destin, chaque fiche montre les deux sorts avec leur Mana, l'ultime,
   l'avantage, l'inconvénient, les quatre jauges et la difficulté. Cliquez **Aperçu** sur Glace :
   éclat de givre, prison de cristal, puis Hiver Éternel autour du personnage. Le bouton se réactive
   à la fin. La magie sélectionnée ne change pas.
3. **Musique** : dès le créateur, la sortie affiche `[Musique] creator : ESSAI de « … »` puis
   `LECTURE CONFIRMÉE`. Si rien ne se charge : `aucun candidat utilisable` (silence, sans erreur).
4. **Épée** : enchaînez les cinq coups. La sortie indique la source de chaque coup. Vérifiez que
   chaque coup se voit (entaille, revers, verticale, tourbillon, final), que le souffle est léger et
   varié, et que le « shing » métallique n'arrive qu'à l'impact.
5. **Sorts et ultimes** : pour chaque magie, touches 1, 2, puis E (Tension pleine). Le geste précède
   l'effet et l'impact tombe à la fin de la préparation.
6. **Vérification audio complète** : barre de commande,
   `local A = require(game.ReplicatedStorage.Shared.Audio.AudioAudit) A.run()`, puis `A.listen(...)`
   et `A.snippet()` (`docs/MUSIQUE.md` §5).
7. **Publication des animations** : `docs/ANIMATIONS.md` §2 et §3.
