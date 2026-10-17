--!strict
--[[
	AudioCandidates
	Pistes et sons TROUVÉS par recherche web (octobre 2026) pour les emplacements encore vides
	d'AudioConfig. AUCUN n'est vérifié : le catalogue Roblox (create.roblox.com) n'était pas
	joignable depuis l'environnement où cette liste a été faite. Les identifiants viennent tels quels
	des pages citées dans `source` ; aucun n'a été deviné ou complété.

	Statut de chaque entrée : « trouvé, non vérifié ». Il ne change PAS ici : ce sont les outils de
	Studio qui disent ce qui se charge et ce qui joue (docs/MUSIQUE.md) :
		AudioAudit.run()       chargement réel + nom et créateur enregistrés chez Roblox
		AudioAudit.listen(...)  écoute dans Studio
		sortie du jeu          « [Musique] LECTURE CONFIRMÉE » quand une piste a vraiment joué
	Une piste acceptée après écoute se recopie dans AudioConfig (son `id`) : elle devient alors
	définitive, y compris sur le jeu publié, et cette liste n'est plus consultée pour elle.

	license :
		"roblox"  la source la présente comme musique sous licence Roblox (APM Music) : utilisable
		          dans toute expérience si l'ID est bien celui de la piste ;
		"store"   la source est la page Creator Store de l'asset (publié pour être réutilisé) ;
		"range"   ID dans la plage du catalogue sous licence Roblox, mais la source ne nomme pas le
		          fournisseur : vérifier le créateur avec AudioAudit.run() ;
		"user"    téléversement d'un particulier, vu seulement sur des listes de fans : droits et
		          disponibilité inconnus (souvent privé depuis 2022). Jamais essayé automatiquement
		          sauf si AudioConfig.CANDIDATE_TRIAL.licenses.user = true.
	duration : durée annoncée par la source (s), ou nil. Une durée réelle trop différente signale
	           un ID qui ne correspond pas à la piste annoncée : l'essai automatique l'écarte.
]]

export type License = "roblox" | "store" | "range" | "user"

export type Candidate = {
	id: string, -- identifiant numérique tel que publié par la source
	name: string, -- titre annoncé
	provider: string, -- compositeur, éditeur ou compte annoncé ("?" si la source ne le dit pas)
	source: string, -- page où l'ID a été trouvé
	duration: number?, -- secondes, d'après la source
	license: License,
	note: string?,
}

export type External = {
	name: string,
	provider: string,
	url: string,
	license: string,
	use: string,
}

local STATUS = "trouvé, non vérifié"

local HONE = "https://hone.gg/blog/roblox-song-ids-music-codes/"
local BLOXODES = "https://bloxodes.com/catalog/roblox-music-ids/artists/"
local ROBLOXSONG = "https://robloxsong.com/song/"
local STORE = "https://create.roblox.com/store/asset/"
-- Liste d'agrégateurs trouvée par la recherche « roblox music id calm piano melancholic fantasy ».
local PIANO_SEARCH = "agrégateurs (recherche « calm piano melancholic fantasy ») : https://robloxcalc.com/roblox-id-songs/, https://www.g2a.com/news/features/games-codes/roblox-music-codes/"

local function c(id: string, name: string, provider: string, source: string, license: License, duration: number?, note: string?): Candidate
	return { id = id, name = name, provider = provider, source = source, license = license, duration = duration, note = note }
end

-- Pistes réutilisées dans plusieurs contextes.
local SAD_STORY = c("1838577168", "Sad Story (Piano & Harp)", "Xavier Berthelot (album Sorrows of Life)", STORE .. "1838577168", "store", 124, "Piano et harpe, film score.")
local TEARS = c("1843286166", "Tears Of Sorrow", "APM Music", HONE, "roblox", 123, "Film score, scènes tristes.")
local SAD_END = c("1838635121", "Sad End (Solo Piano)", "APM Music (compte APMOfficial)", "https://robloxsong.com/artist/3379-orchestra", "roblox", 153, "Piano solo.")
local ABYSSAL = c("9042861406", "Abyssal Plain (Cello Lead Version)", "APM Music", HONE, "roblox", 187, "Orchestral, violoncelle.")
local CLAIRE = c("1838457617", "Claire De Lune", "? (œuvre de Debussy, domaine public ; enregistrement non précisé)", PIANO_SEARCH, "range", nil, "Piano doux.")
local SUSPENSE = c("1838865835", "Suspense", "APM Music", STORE .. "1838865835", "store", nil, "Description de la page très courte : écouter avant tout.")
local ANCIENT_MYTHS = c("1837779548", "Ancient Myths", "APM Music", "wiki de fans (recherche « epic orchestral battle music APM ») : https://roblox-slap-battles.fandom.com/wiki/Soundtracks ou https://roblox-field-of-battle-official-community.fandom.com/wiki/Music", "roblox", nil, "Présentée comme musique de boss d'un autre jeu.")

local MUSIC: { [string]: { Candidate } } = {
	creator = { SAD_STORY, TEARS, SAD_END },
	overlook = {
		ABYSSAL,
		c("1837879082", "Paradise Falls", "?", PIANO_SEARCH, "range", nil, "Exploration, fantasy."),
	},
	village = {
		c("1842715333", "Hope And Glory", "Daniel Richard Price (album Celtic Folk)", BLOXODES .. "daniel-richard-price", "range", 142, "Folk celtique."),
		c("1836089893", "Bright Middle Ages Music", "?", ROBLOXSONG .. "1836089842-epic-middle-ages-music", "range", nil, "Médiéval enjoué."),
		c("1846853445", "Medieval Magic", "Robert James Bruce", BLOXODES .. "robert-james-bruce", "range", 134),
		c("9045862826", "Medieval (b)", "?", ROBLOXSONG .. "9045862826-medieval-b", "range"),
	},
	village_night = {
		c("9045765634", "Nocturne in E-Flat Major, Op. 9, No. 2", "? (œuvre de Chopin, domaine public ; enregistrement non précisé)", PIANO_SEARCH, "range", nil, "Piano calme."),
		CLAIRE,
		c("108595570567760", "Calm Piano Music for Studying", "? (téléversement)", ROBLOXSONG .. "108595570567760-calm-piano-music-for-studying", "user"),
	},
	forest = {
		c("1838592519", "The Mysterious Book", "Xavier Berthelot (album The Magic Land)", BLOXODES .. "xavier-berthelot", "range", nil, "Mystère, féerique."),
		c("1847052146", "Fantasy In Blue", "Robert James Bruce", BLOXODES .. "robert-james-bruce", "range", 212),
		c("1848354536", "Relaxed Scene", "APM Music", STORE .. "1848354536/Relaxed-Scene", "store", nil, "Classée Pop : peut-être trop légère."),
	},
	forest_night = {
		c("7274920568", "Night Forest Ambience Sound", "? (téléversement)", "tableau d'un site de codes (recherche « mysterious forest ambient ») : https://rocodes.gg/music/tags/ambient, https://musiccoder.com", "user", nil, "Ambiance, pas une musique."),
		CLAIRE,
	},
	crypt = {
		SUSPENSE,
		c("139743346356072", "Forgotten Crypt", "? (téléversement)", "https://www.theclick.gg/roblox-scary-sound-ids/", "user", nil, "Présentée comme horreur : sans doute trop sombre."),
		c("1835337424", "Scary Ambience", "?", "https://www.theclick.gg/roblox-scary-sound-ids/", "range", nil, "Horreur : à n'accepter que si l'écoute reste mesurée."),
	},
	lake = {
		CLAIRE,
		c("84386740040301", "Celestial Calm", "? (téléversement)", "https://gameboost.com/blog/roblox-music-codes", "user"),
		ABYSSAL,
	},
	hostile = {
		SUSPENSE,
		c("9042675817", "Chase Me", "APM Music", STORE .. "9042675817/Chase-Me", "store", nil, "Orgue, cloches, cordes : plus horrifique que la direction voulue."),
	},
	combat = {
		c("1836089842", "Epic Middle Ages Music", "?", ROBLOXSONG .. "1836089842-epic-middle-ages-music", "range"),
		ANCIENT_MYTHS,
		c("5838262840", "Dragon Castle / Epic Orchestral Battle Music", "? (téléversement)", "https://roblox-field-of-battle-official-community.fandom.com/wiki/Music", "user"),
	},
	boss = {
		ANCIENT_MYTHS,
		c("87773547872492", "Epic Boss Music", "? (téléversement, 2024)", ROBLOXSONG .. "87773547872492-epic-boss-music", "user"),
		c("78744747224727", "Boss Fight!", "? (téléversement, 2024)", ROBLOXSONG .. "78744747224727-boss-fight", "user"),
	},
	anomaly = {
		c("140704980462451", "Midnight Litany of Drones", "? (téléversement)", "https://www.theclick.gg/roblox-scary-sound-ids/", "user", nil, "Nappe grave : courte durée seulement (pas de drone permanent)."),
		SUSPENSE,
	},
	victory = {
		c("1837507072", "Victory", "?", ROBLOXSONG .. "1837507072-victory", "range"),
		c("12222253", "victory.wav", "Roblox (effet sonore)", STORE .. "12222253/victorywav", "store", nil, "Effet court, pas une phrase orchestrale."),
		c("1837507091", "Victory", "?", "agrégateurs de codes (recherche « victory fanfare ») : https://musiccoder.com/codes/detail/3249-victory", "range"),
	},
}

-- Chœur du rembobinage (court, féminin). La piste ci-dessous est sans doute longue : le jeu n'en
-- garde que REWIND_CHOIR.maxDuration secondes, avec fondus.
local REWIND_CHOIR: { Candidate } = {
	c("1840524246", "Angelic Choir", "?", ROBLOXSONG .. "1840524246-angelic-choir", "range", nil, "Page sans description des voix."),
}

-- Effets sonores : seulement pour les emplacements VIDES d'AudioConfig.SFX (essai automatique).
local SFX: { [string]: { Candidate } } = {
	swordBlocked = {
		c("7058511334", "Sword Parry", "? (téléversement)", "https://robloxsong.com/artist/76557-the-sword?page=4", "user"),
		c("7058511971", "Sword Parry 5", "? (téléversement)", "https://robloxsong.com/artist/76557-the-sword?page=4", "user"),
	},
	plungeImpact = {
		c("5540424854", "impact", "? (utilisé par Slap Battles)", "https://roblox-slap-battles.fandom.com/wiki/Sound_Effects", "user"),
	},
}

-- Alternatives à ÉCOUTER (AudioAudit.listen("alt:<nom>", n)) pour des emplacements déjà remplis
-- par un son livré avec Roblox. Jamais utilisées automatiquement.
local SFX_ALTERNATIVES: { [string]: { Candidate } } = {
	dodge = {
		c("135315310485417", "sword-swing-whoosh-sound-effect-1-full-pack", "? (Creator Store)", STORE .. "135315310485417/swordswingwhooshsoundeffect1fullpack", "store", nil, "« Pack complet » : peut contenir plusieurs souffles à la suite."),
	},
	impact_lightning = {
		c("224339201", "lightning bolt", "? (utilisé par Slap Battles)", "https://roblox-slap-battles.fandom.com/wiki/Sound_Effects", "user"),
		c("7138705968", "lightning strike", "? (téléversement)", "https://devforum.roblox.com/t/best-way-to-create-a-lightning-effect/1367669", "user"),
	},
	impact_pyromancy = {
		c("9114362266", "explosion", "? (utilisé par Slap Battles)", "https://roblox-slap-battles.fandom.com/wiki/Sound_Effects", "user"),
	},
}

-- Sources libres hors Roblox : à télécharger, vérifier, puis téléverser sur VOTRE compte (Creator
-- Hub > Audio). L'ID obtenu vous appartient et se colle dans AudioConfig.
local EXTERNAL: { External } = {
	{ name = "Sword (sons d'épée)", provider = "Mixkit", url = "https://mixkit.co/free-sound-effects/sword/", license = "Mixkit Sound Effects Free License (à relire)", use = "souffle de lame, impact, garde" },
	{ name = "Freeze Spell", provider = "OpenGameArt", url = "https://opengameart.org/content/freeze-spell-0", license = "CC0", use = "cast_ice / impact_ice" },
	{ name = "Ice & Electricity Magic", provider = "OpenGameArt (Lips of Suna)", url = "https://opengameart.org/content/ice-electricity-magic", license = "CC-BY 3.0 (crédit obligatoire)", use = "glace, foudre" },
	{ name = "Game Victory", provider = "FiftySounds", url = "https://www.fiftysounds.com/royalty-free-music/game-victory.html", license = "gratuite, usage commercial, sans attribution selon le site (à relire)", use = "victoire" },
	{ name = "Bibliothèque Kevin MacLeod", provider = "incompetech", url = "https://incompetech.com", license = "CC BY 4.0 (crédit obligatoire), à vérifier par piste", use = "piano, cordes, ambiances" },
	{ name = "Fantasy Music Collection", provider = "Donat Baracsi (itch.io)", url = "https://donat-baracsi.itch.io/fantasy-music-collection/purchase", license = "licence du pack à lire avant achat/usage", use = "thèmes de région" },
	{ name = "Magic Sound Effects – Elemental Pack", provider = "High Impact Media (itch.io)", url = "https://high-impact-media.itch.io/magic-sound-effects-elemental-pack", license = "licence du pack à lire", use = "sons des six magies" },
}

return table.freeze({
	STATUS = STATUS,
	MUSIC = MUSIC,
	REWIND_CHOIR = REWIND_CHOIR,
	SFX = SFX,
	SFX_ALTERNATIVES = SFX_ALTERNATIVES,
	EXTERNAL = EXTERNAL,
})
