# Magies 3.0 : Glace et Antimatière (livraisons A et B)

**Ce qui est vérifié, et ce qui ne l'est pas.** Je n'ai pas accès à Roblox Studio. La simulation
vérifie les points suivants :
- les bons objets apparaissent aux bons moments, calés sur les événements du serveur ;
- aucun objet d'effet n'est solide ;
- tout disparaît ensuite ;
- le budget de pièces tient avec dix sorts simultanés ;
- les deux sorts d'une magie ne se ressemblent pas.

**Elle ne montre pas l'image.** Rendu du verre, lisibilité des formes, couleurs, réfraction : tout
cela reste à juger dans Studio, avec la procédure du §4.

Point de restauration d'avant ce chantier : branche `sauvegarde-avant-magies-3` (le dépôt distant
refuse les étiquettes).

## 1. Pourquoi les sorts se ressemblaient

Tous les effets étaient construits avec les quatre mêmes briques :

1. des **disques plats** (cylindres couchés) : c'était l'élément principal de chaque zone et de
   chaque annonce ; en plus, toute zone de rayon ≥ 3 recevait un anneau commun à l'impact ;
2. des **boules néon ou ForceField** ;
3. des **blocs carrés tournés** pour figurer les « cristaux » ;
4. **une seule texture de particules** (`sparkles`), recolorée.

À distance de combat, tout se lisait donc comme « disque coloré + étincelles ». Il n'y avait pas
non plus de préparation dans la main : seul le geste du personnage annonçait le sort.

## 2. Nouvelle base technique

| Élément | Rôle |
|---|---|
| `src/client/Magic/VfxKit.luau` | vraies formes : pointe de cristal (colonne de verre + pyramide), cristal léger, éclats projetés qui retombent, givre qui s'étend, sphères à couches, liens d'énergie ; textures livrées avec Roblox (feu, fumée, vortex, onde de choc) ; niveau de détail selon la distance ; budget global ; nettoyage garanti |
| `src/client/Magic/Vfx/Ice.luau`, `Vfx/Antimatter.luau` | un module par magie : préparation, vol, annonce, impact et ultime |
| `src/shared/Magic/SpellTags.luau` | nature de chaque sort (forme · effet), déduite des données du serveur, affichée dans le HUD et sur les fiches du créateur |
| `AudioMixer.duck` | atténuation brève de la musique et de l'ambiance (instant de silence d'un ultime) |

Les dégâts, coûts en Mana, recharges, altérations et durées ne changent pas. Les effets ne
calculent rien : ils suivent `SpellCast`, `SpellImpact`, `UltimateFired` et les attributs
d'altération publiés par le serveur.

Garde-fous :
- aucune pièce n'a de collision, de requête ni de contact ;
- tout se détruit seul ; aucune modification du terrain ;
- la caméra ne secoue brièvement que chez les joueurs proches, moins fort en effets réduits ;
- détail réduit au-delà de 90 studs, puis au-delà de 200 studs ;
- détail divisé par deux en « effets réduits » ;
- détail réduit quand trop de pièces d'effet sont déjà présentes (compteur exact, avec réservation
  pour les pointes qui apparaissent en différé).

## 3. Ce qui change à l'écran

### Glace

| | Éclat de Givre (touche 1) | Prison Cristalline (touche 2) |
|---|---|---|
| Nature (HUD) | **Projectile · Ralentit** | **Zone ciblée · Immobilise** |
| Préparation | un cristal se forme dans la main, le givre converge | le sol se couvre de plaques de givre, brume froide, petits cristaux qui poussent un à un sur le pourtour |
| Manifestation | fragment de glace irrégulier en 3D : corps en losange, pointes, deux éclats secondaires, cœur lumineux, traînée froide | cinq pointes par cible jaillissent l'une après l'autre et se referment sur elle |
| Impact | le cristal éclate en fragments qui retombent, bouffée de givre, plaques de glace aux pieds | poudre de glace, éclat bleu, pointes dans la zone même sans cible |
| Conséquence | cible bleutée, givre qui tombe (froid réel) | la cage **tient tant que dure le gel** publié par le serveur, puis éclate ; un **boss** (simple froid) la brise aussitôt |

Gel : la grande boîte de verre autour du corps est remplacée par un givre blanc sur la silhouette et
des éclats de glace pris sur le corps.

**Hiver Éternel (ultime)** :
- voile froid à l'écran, cristaux en suspension qui tournent et montent autour du lanceur, givre qui
  gagne le sol jusqu'au rayon de l'ultime ;
- à l'impact (moment exact des dégâts) : couronne de grandes formations, trois pointes autour de
  chaque cible, éclat lumineux bref ;
- puis tout se fend et éclate. L'ultime **ralentit fortement** (« Hiver Éternel ») sans geler :
  les pointes encadrent les cibles sans les emprisonner.

### Antimatière

| | Fragment du Vide (touche 1) | Singularité Mineure (touche 2) |
|---|---|---|
| Nature (HUD) | **Projectile · Explose** | **Zone ciblée · Aspire** |
| Préparation | une sphère noire se condense dans la main | un point noir naît au-dessus du sol, l'espace se bombe (lentille de verre), la poussière converge |
| Manifestation | sphère à couches (cœur noir, lentille de verre, coque ondulante), traînée de fragments sombres | cœur sombre, coque qui ondule, anneaux de fragments en orbite, matière aspirée |
| Impact | la sphère enfle, se contracte, puis l'onde de rupture part (coque, lentille, onde de choc, éclats noirs) | liens tendus vers chaque ennemi **réellement aspiré**, traînée de matière arrachée ; un boss (immunisé) rompt son lien |
| Fin | | contraction, puis implosion finale |

**Rupture du Néant (ultime, ancien nom affiché « Éruption d'Antimatière »)** :
- la matière obscure de toute la zone est tirée en spirale vers un cœur au-dessus du lanceur ;
  l'espace se comprime et des liens partent vers les cibles ;
- 0,3 s avant la libération, musique et ambiance s'effacent un instant (joueurs proches) ;
- le cœur s'effondre, puis une onde géante part, des fissures sombres rayonnent au sol, des éclats
  sont projetés ;
- les survivants laissent une traînée vers le lanceur (aspiration réelle du serveur).

L'identifiant sauvegardé reste `antimatter` : seul le nom affiché change.

La déformation de l'espace est une illusion. Le verre brouille ce qui est derrière lui seulement à
une qualité graphique suffisante. À qualité basse, on voit surtout les sphères et les particules.

## 4. Test dans Studio (10 minutes)

1. **Import** : remplacez `ReplicatedStorage > Shared` par `Shared.rbxmx`,
   `ServerScriptService > Server` par `Server.rbxmx`, et
   `StarterPlayer > StarterPlayerScripts > Client` par `Client.rbxmx`.
2. **Créateur** : sur la fiche Glace puis la fiche Antimatière, cliquez **Aperçu**. On doit voir,
   dans l'ordre, le sort 1, le sort 2 et l'ultime. Sous chaque sort, la nature s'affiche en italique
   (par exemple *Projectile · Ralentit*).
3. **En jeu, avec la Glace** (Graphismes en qualité élevée pour juger le verre) :
   - touche 1 sur un ennemi : un cristal dans la main, un fragment de glace en vol, l'éclatement ;
   - touche 2 : le givre et les petits cristaux pendant la préparation, puis la cage de pointes
     autour de l'ennemi. Elle doit tenir environ 2,5 s puis éclater ;
   - sur le boss, la cage doit se briser aussitôt.
4. **Ultime Glace** (Tension pleine, E) : cristaux en suspension, givre, grandes formations, puis
   éclatement. Rien ne doit bloquer vos déplacements.
5. **Antimatière** : touche 1 (sphère sombre, contraction puis onde), touche 2 (singularité,
   fragments en orbite, liens vers les ennemis aspirés, implosion), puis E : spirale de matière,
   **un instant de silence**, libération et fissures.
6. **Effets réduits** (Grimoire > Options) : refaites un sort de chaque. Il doit y avoir moins de
   cristaux et de particules, sans secousse forte.
7. **Après chaque sort**, l'Explorer ne doit garder aucun objet dans `Workspace > UltimateEffects`
   ni dans `Workspace > SpellEffects` au bout de quelques secondes.

À me signaler en priorité :
- les **pointes de cristal paraissent creuses ou inversées**. Leur forme repose sur l'orientation
  des pièces en coin de Roblox, que je ne peux pas voir. La correction tient en une ligne :
  `VfxKit.WEDGE_SLOPE_FRONT = false` dans `src/client/Magic/VfxKit.luau` ;
- les effets sont trop discrets ou trop chargés ;
- une couleur ne correspond pas à l'identité de la magie.

## 5. Limites connues

- Les sons propres à la glace et à l'antimatière sont encore vides dans `AudioConfig` (livraison D).
- Les quatre autres magies gardent leurs effets actuels jusqu'à la livraison C.
- Le simulateur ne rend ni le verre, ni les particules, ni la lumière. Le budget de pièces est
  mesuré, mais pas le coût réel au rendu sur téléphone.
