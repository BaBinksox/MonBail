# Animations : vraies pistes, séquences éditables, publication

Ce que j'ai pu vérifier, et ce qui reste à faire de votre côté. Je n'ai pas accès à Roblox Studio ni au
réseau Roblox depuis mon environnement, donc rien ci-dessous n'a été *vu* en jeu. Ce qui est vérifié :
la structure des séquences (relues par Rojo sans erreur), leur hiérarchie R15, leurs poids, et la
logique qui choisit et lance les pistes (simulation).

## 1. Comment le jeu joue une action

Pour chaque action d'`AnimationConfig.ACTIONS`, la première solution disponible gagne :

| Ordre | Solution | Où ça marche |
|---|---|---|
| 1 | `animationId` : clip **publié** sur votre compte | partout (Studio, jeu publié), répliqué aux autres joueurs |
| 2 | **séquence générée** depuis `PoseLibrary`, enregistrée par `KeyframeSequenceProvider` | **Studio seulement** (identifiant temporaire) |
| 3 | `fallbackId` : clips d'épée d'avant Combat 2.0 (`522635514`, `522638767`) + accent du buste | partout si Roblox les sert (à confirmer) |
| 4 | pose procédurale seule, appliquée sur `Motor6D.Transform` après l'Animator | partout |

La sortie de Studio affiche une fois par action la solution utilisée, par exemple
`[Animation] sword_1 : séquence générée (Studio)`. Pour revenir aux anciens clips d'épée dans Studio :
`AnimationConfig.USE_GENERATED_IN_STUDIO = false`.

**Conséquence importante** : sur le jeu **publié**, tant que les séquences ne sont pas publiées
(§3), l'épée utilise les anciens clips (3) et les sorts la pose procédurale (4). Publier les séquences
est donc l'étape qui rend les animations définitives pour tous les joueurs.

## 2. Obtenir les séquences éditables

Deux méthodes, au choix.

**A. Script d'installation (recommandé)** : Studio, mode édition, après import des dossiers. Dans la
barre de commande :

```lua
require(game.ReplicatedStorage.Shared.Animation.KeyframeBuilder).install()
```

Cela crée un mannequin R15 `EchosAnimRig` (avec une épée fixée comme en jeu, articulation `SwordGrip`
vers la pièce `Handle`) et place les 37 séquences dans `EchosAnimRig > AnimSaves` et dans
`ServerStorage > RBX_ANIMSAVES > EchosAnimRig` (emplacement de l'Animation Editor actuel).

**B. Fichier** : `build/AnimationSequences.rbxmx` (régénéré par `tools/anim/export.sh`). Glissez-le dans
un rig R15 (Avatar > Rig Builder) : il devient son dossier `AnimSaves`.

## 3. Publier une séquence et l'utiliser en jeu

1. **Publication directe** : dans l'Explorer, clic droit sur une `KeyframeSequence` (par exemple
   `sword_1`) > *Save to Roblox…*, puis créez l'animation. Copiez l'identifiant obtenu.
2. **Ou avec retouche** : sélectionnez `EchosAnimRig`, Avatar > Animation Editor, « … » > *Load*,
   choisissez la séquence, ajustez, puis « … » > *Publish to Roblox*.
3. Collez l'identifiant dans la table `PUBLISHED` de `src/shared/Animation/AnimationConfig.luau`
   (une ligne par action) : `sword_1 = "rbxassetid://VOTRE_ID",`.
4. Gardez la **durée** de la séquence : le serveur valide les coups sur les fenêtres de
   `CombatConfig.COMBO` (impact du coup 1 à 0,15 s, coup 3 à 0,25 s…). Si vous allongez un mouvement,
   ajustez `duration`, `hitStart`, `hitEnd` du coup correspondant.

Une animation doit appartenir au propriétaire de l'expérience (vous, ou le groupe) pour se charger dans
le jeu publié.

## 4. Les mouvements

| Action | Durée | Impact | Mouvement |
|---|---|---|---|
| `sword_1` Entaille | 0,36 s | 0,15 s | bassin et buste armés à droite, balayage vif vers la gauche, bras gauche en balancier |
| `sword_2` Revers | 0,34 s | 0,15 s | lame haute à gauche, diagonale vers le bas à droite, appui sur la jambe gauche |
| `sword_3` Verticale | 0,50 s | 0,25 s | petit appel, armé à deux mains au-dessus de la tête, frappe écrasante, genoux fléchis |
| `sword_4` Tourbillon | 0,55 s | 0,28 s | armé à droite, tour complet du bassin lame tendue (4 segments < 180°) |
| `sword_5` Final | 0,70 s | 0,39 s | accroupi lame armée derrière, bond en avant et grande taille plongeante |
| `sword_charge` / `sword_charged` | boucle / 0,55 s | 0,17 s | lame ramenée haut derrière l'épaule ; frappe chargée |
| `sword_counter`, `sword_plunge_fall`, `sword_plunge` | | | riposte, chute lame levée, impact au sol |
| `cast_*` (12), `cast_ultimate` et `cast_ultimate_<magie>` (6), `concentrate` | | | gestuelle propre à chaque magie |

Chaque coup comporte une anticipation, une image clé de frappe en interpolation linéaire (vive), un
impact placé dans la fenêtre de frappe du serveur, puis une récupération. Les articulations non
utilisées par une séquence (souvent les jambes des sorts) restent aux animations de marche de Roblox.
