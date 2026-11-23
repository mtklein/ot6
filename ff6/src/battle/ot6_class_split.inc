; ----------------------------------------------------------------------------
; what a four-class (v0.50 and older) save's revealed class bits mean, per
; species id (0..383): bit k set = the weakness of four-class bit k (slash $01,
; pierce $02, bludgeon $04, special $08) became its SECOND child (katana,
; spear, arcane, dagger); clear = its first (sword, dagger, fist, arcane).
; Written once, when the six classes replaced the four (#566); it describes
; the saves of the releases before that, so it does not change when a row does.
; ----------------------------------------------------------------------------

Ot6ClassSplitTbl:
        .byte   $02             ;   0 Guard
        .byte   $01             ;   1 Soldier
        .byte   $00             ;   2 Templar
        .byte   $02             ;   3 Ninja
        .byte   $00             ;   4 Samurai
        .byte   $01             ;   5 Orog
        .byte   $00             ;   6 Mag Roader
        .byte   $05             ;   7 Retainer
        .byte   $01             ;   8 Hazer
        .byte   $00             ;   9 Dahling
        .byte   $00             ;  10 Rain Man
        .byte   $00             ;  11 Brawler
        .byte   $02             ;  12 Apokryphos
        .byte   $08             ;  13 Dark Force
        .byte   $09             ;  14 Whisper
        .byte   $08             ;  15 Over-Mind
        .byte   $00             ;  16 Osteosaur
        .byte   $00             ;  17 Commander
        .byte   $03             ;  18 Rhodox
        .byte   $03             ;  19 Were-Rat
        .byte   $00             ;  20 Ursus
        .byte   $02             ;  21 Rhinotaur
        .byte   $02             ;  22 Steroidite
        .byte   $04             ;  23 Leafer
        .byte   $01             ;  24 Stray Cat
        .byte   $02             ;  25 Lobo
        .byte   $00             ;  26 Doberman
        .byte   $01             ;  27 Vomammoth
        .byte   $00             ;  28 Fidor
        .byte   $02             ;  29 Baskervor
        .byte   $05             ;  30 Suriander
        .byte   $02             ;  31 Chimera
        .byte   $01             ;  32 Behemoth
        .byte   $02             ;  33 Mesosaur
        .byte   $02             ;  34 Pterodon
        .byte   $00             ;  35 FossilFang
        .byte   $00             ;  36 White Drgn
        .byte   $00             ;  37 Doom Drgn
        .byte   $02             ;  38 Brachosaur
        .byte   $00             ;  39 Tyranosaur
        .byte   $02             ;  40 Dark Wind
        .byte   $01             ;  41 Beakor
        .byte   $02             ;  42 Vulture
        .byte   $00             ;  43 Harpy
        .byte   $00             ;  44 HermitCrab
        .byte   $00             ;  45 Trapper
        .byte   $03             ;  46 Hornet
        .byte   $04             ;  47 CrassHoppr
        .byte   $02             ;  48 Delta Bug
        .byte   $04             ;  49 Gilomantis
        .byte   $01             ;  50 Trilium
        .byte   $01             ;  51 Nightshade
        .byte   $05             ;  52 TumbleWeed
        .byte   $00             ;  53 Bloompire
        .byte   $00             ;  54 Trilobiter
        .byte   $03             ;  55 Siegfried
        .byte   $06             ;  56 Nautiloid
        .byte   $04             ;  57 Exocite
        .byte   $01             ;  58 Anguiform
        .byte   $04             ;  59 Reach Frog
        .byte   $00             ;  60 Lizard
        .byte   $01             ;  61 ChickenLip
        .byte   $01             ;  62 Hoover
        .byte   $00             ;  63 Rider
        .byte   $00             ;  64 Chupon
        .byte   $02             ;  65 Pipsqueak
        .byte   $02             ;  66 M-TekArmor
        .byte   $01             ;  67 Sky Armor
        .byte   $00             ;  68 Telstar
        .byte   $05             ;  69 Lethal Wpn
        .byte   $04             ;  70 Vaporite
        .byte   $00             ;  71 Flan
        .byte   $02             ;  72 Ing
        .byte   $00             ;  73 Humpty
        .byte   $02             ;  74 Brainpan
        .byte   $00             ;  75 Cruller
        .byte   $00             ;  76 Cactrot
        .byte   $02             ;  77 Repo Man
        .byte   $03             ;  78 Harvester
        .byte   $05             ;  79 Bomb
        .byte   $00             ;  80 Still Life
        .byte   $05             ;  81 Boxed Set
        .byte   $00             ;  82 SlamDancer
        .byte   $00             ;  83 HadesGigas
        .byte   $00             ;  84 Pug
        .byte   $00             ;  85 Magic Urn
        .byte   $01             ;  86 Mover
        .byte   $05             ;  87 Figaliz
        .byte   $00             ;  88 Buffalax
        .byte   $00             ;  89 Aspik
        .byte   $08             ;  90 Ghost
        .byte   $04             ;  91 Crawler
        .byte   $02             ;  92 Sand Ray
        .byte   $04             ;  93 Areneid
        .byte   $00             ;  94 Actaneon
        .byte   $03             ;  95 Sand Horse
        .byte   $08             ;  96 Dark Side
        .byte   $00             ;  97 Mad Oscar
        .byte   $04             ;  98 Crawly
        .byte   $02             ;  99 Bleary
        .byte   $02             ; 100 Marshal
        .byte   $00             ; 101 Trooper
        .byte   $00             ; 102 General
        .byte   $06             ; 103 Covert
        .byte   $00             ; 104 Ogor
        .byte   $00             ; 105 Warlock
        .byte   $01             ; 106 Madam
        .byte   $00             ; 107 Joker
        .byte   $02             ; 108 Iron Fist
        .byte   $01             ; 109 Goblin
        .byte   $03             ; 110 Apparite
        .byte   $0b             ; 111 PowerDemon
        .byte   $00             ; 112 Displayer
        .byte   $00             ; 113 Vector Pup
        .byte   $00             ; 114 Peepers
        .byte   $02             ; 115 Sewer Rat
        .byte   $04             ; 116 Slatter
        .byte   $00             ; 117 Rhinox
        .byte   $01             ; 118 Rhobite
        .byte   $03             ; 119 Wild Cat
        .byte   $01             ; 120 Red Fang
        .byte   $01             ; 121 Bounty Man
        .byte   $00             ; 122 Tusker
        .byte   $02             ; 123 Ralph
        .byte   $00             ; 124 Chitonid
        .byte   $06             ; 125 Wart Puck
        .byte   $00             ; 126 Rhyos
        .byte   $04             ; 127 SrBehemoth
        .byte   $03             ; 128 Vectaur
        .byte   $01             ; 129 Wyvern
        .byte   $04             ; 130 Zombone
        .byte   $03             ; 131 Dragon
        .byte   $04             ; 132 Brontaur
        .byte   $06             ; 133 Allosaurus
        .byte   $00             ; 134 Cirpius
        .byte   $02             ; 135 Sprinter
        .byte   $01             ; 136 Gobbler
        .byte   $02             ; 137 Harpiai
        .byte   $04             ; 138 GloomShell
        .byte   $02             ; 139 Drop
        .byte   $00             ; 140 Mind Candy
        .byte   $01             ; 141 WeedFeeder
        .byte   $03             ; 142 Luridan
        .byte   $00             ; 143 Toe Cutter
        .byte   $00             ; 144 Over Grunk
        .byte   $03             ; 145 Exoray
        .byte   $00             ; 146 Crusher
        .byte   $04             ; 147 Uroburos
        .byte   $00             ; 148 Primordite
        .byte   $00             ; 149 Sky Cap
        .byte   $03             ; 150 Cephaler
        .byte   $00             ; 151 Maliga
        .byte   $00             ; 152 Gigan Toad
        .byte   $02             ; 153 Geckorex
        .byte   $05             ; 154 Cluck
        .byte   $01             ; 155 Land Worm
        .byte   $02             ; 156 Test Rider
        .byte   $02             ; 157 PlutoArmor
        .byte   $02             ; 158 Tomb Thumb
        .byte   $01             ; 159 HeavyArmor
        .byte   $00             ; 160 Chaser
        .byte   $04             ; 161 Scullion
        .byte   $03             ; 162 Poplium
        .byte   $00             ; 163 Intangir
        .byte   $02             ; 164 Misfit
        .byte   $04             ; 165 Eland
        .byte   $01             ; 166 Enuo
        .byte   $02             ; 167 Deep Eye
        .byte   $00             ; 168 GreaseMonk
        .byte   $02             ; 169 NeckHunter
        .byte   $00             ; 170 Grenade
        .byte   $00             ; 171 Critic
        .byte   $00             ; 172 Pan Dora
        .byte   $01             ; 173 SoulDancer
        .byte   $01             ; 174 Gigantos
        .byte   $00             ; 175 Mag Roader
        .byte   $02             ; 176 Spek Tor
        .byte   $00             ; 177 Parasite
        .byte   $00             ; 178 EarthGuard
        .byte   $01             ; 179 Coelecite
        .byte   $01             ; 180 Anemone
        .byte   $04             ; 181 Hipocampus
        .byte   $00             ; 182 Spectre
        .byte   $01             ; 183 Evil Oscar
        .byte   $00             ; 184 Slurm
        .byte   $02             ; 185 Latimeria
        .byte   $01             ; 186 StillGoing
        .byte   $01             ; 187 Allo Ver
        .byte   $00             ; 188 Phase
        .byte   $00             ; 189 Outsider
        .byte   $01             ; 190 Barb-e
        .byte   $02             ; 191 Parasoul
        .byte   $08             ; 192 Pm Stalker
        .byte   $09             ; 193 Hemophyte
        .byte   $02             ; 194 Sp Forces
        .byte   $00             ; 195 Nohrabbit
        .byte   $0b             ; 196 Wizard
        .byte   $01             ; 197 Scrapper
        .byte   $02             ; 198 Ceritops
        .byte   $00             ; 199 Commando
        .byte   $04             ; 200 Opinicus
        .byte   $03             ; 201 Poppers
        .byte   $00             ; 202 Lunaris
        .byte   $02             ; 203 Garm
        .byte   $01             ; 204 Vindr
        .byte   $03             ; 205 Kiwok
        .byte   $00             ; 206 Nastidon
        .byte   $02             ; 207 Rinn
        .byte   $04             ; 208 Insecare
        .byte   $00             ; 209 Vermin
        .byte   $01             ; 210 Mantodea
        .byte   $00             ; 211 Bogy
        .byte   $00             ; 212 Prussian
        .byte   $00             ; 213 Black Drgn
        .byte   $06             ; 214 Adamanchyt
        .byte   $09             ; 215 Dante
        .byte   $03             ; 216 Wirey Drgn
        .byte   $00             ; 217 Dueller
        .byte   $02             ; 218 Psychot
        .byte   $00             ; 219 Muus
        .byte   $05             ; 220 Karkass
        .byte   $03             ; 221 Punisher
        .byte   $00             ; 222 Balloon
        .byte   $02             ; 223 Gabbldegak
        .byte   $04             ; 224 GtBehemoth
        .byte   $00             ; 225 Scorpion
        .byte   $00             ; 226 Chaos Drgn
        .byte   $03             ; 227 Spit Fire
        .byte   $00             ; 228 Vectagoyle
        .byte   $00             ; 229 Lich
        .byte   $00             ; 230 Osprey
        .byte   $02             ; 231 Mag Roader
        .byte   $01             ; 232 Bug
        .byte   $00             ; 233 Sea Flower
        .byte   $04             ; 234 Fortis
        .byte   $02             ; 235 Abolisher
        .byte   $03             ; 236 Aquila
        .byte   $00             ; 237 Junk
        .byte   $05             ; 238 Mandrake
        .byte   $02             ; 239 1st Class
        .byte   $05             ; 240 Tap Dancer
        .byte   $00             ; 241 Necromancr
        .byte   $01             ; 242 Borras
        .byte   $02             ; 243 Mag Roader
        .byte   $00             ; 244 Wild Rat
        .byte   $04             ; 245 Gold Bear
        .byte   $04             ; 246 Innoc
        .byte   $02             ; 247 Trixter
        .byte   $01             ; 248 Red Wolf
        .byte   $08             ; 249 Didalos
        .byte   $00             ; 250 Woolly
        .byte   $03             ; 251 Veteran
        .byte   $02             ; 252 Sky Base
        .byte   $04             ; 253 IronHitman
        .byte   $06             ; 254 Io
        .byte   $09             ; 255 Pugs
        .byte   $00             ; 256 Whelk
        .byte   $00             ; 257 Presenter
        .byte   $02             ; 258 Mega Armor
        .byte   $00             ; 259 Vargas
        .byte   $00             ; 260 TunnelArmr
        .byte   $02             ; 261 Prometheus
        .byte   $00             ; 262 GhostTrain
        .byte   $04             ; 263 Dadaluma
        .byte   $00             ; 264 Shiva
        .byte   $02             ; 265 Ifrit
        .byte   $00             ; 266 Number 024
        .byte   $02             ; 267 Number 128
        .byte   $04             ; 268 Inferno
        .byte   $02             ; 269 Crane
        .byte   $00             ; 270 Crane
        .byte   $00             ; 271 Umaro
        .byte   $03             ; 272 Umaro
        .byte   $00             ; 273 Guardian
        .byte   $00             ; 274 Guardian
        .byte   $02             ; 275 Air Force
        .byte   $00             ; 276 Tritoch
        .byte   $00             ; 277 Tritoch
        .byte   $00             ; 278 FlameEater
        .byte   $02             ; 279 AtmaWeapon
        .byte   $00             ; 280 Nerapa
        .byte   $02             ; 281 SrBehemoth
        .byte   $00             ; 282 Kefka
        .byte   $03             ; 283 Tentacle
        .byte   $00             ; 284 Dullahan
        .byte   $00             ; 285 Doom Gaze
        .byte   $00             ; 286 Chadarnook
        .byte   $01             ; 287 Curley
        .byte   $06             ; 288 Larry
        .byte   $00             ; 289 Moe
        .byte   $01             ; 290 Wrexsoul
        .byte   $04             ; 291 Hidon
        .byte   $03             ; 292 KatanaSoul
        .byte   $00             ; 293 L.30 Magic
        .byte   $04             ; 294 Hidonite
        .byte   $01             ; 295 Doom
        .byte   $00             ; 296 Goddess
        .byte   $00             ; 297 Poltrgeist
        .byte   $0a             ; 298 Kefka
        .byte   $00             ; 299 L.40 Magic
        .byte   $02             ; 300 Ultros
        .byte   $02             ; 301 Ultros
        .byte   $02             ; 302 Ultros
        .byte   $00             ; 303 Chupon
        .byte   $00             ; 304 L.20 Magic
        .byte   $01             ; 305 Siegfried
        .byte   $00             ; 306 L.10 Magic
        .byte   $00             ; 307 L.50 Magic
        .byte   $02             ; 308 Head
        .byte   $00             ; 309 Whelk Head
        .byte   $00             ; 310 Colossus
        .byte   $00             ; 311 CzarDragon
        .byte   $09             ; 312 Master Pug
        .byte   $00             ; 313 L.60 Magic
        .byte   $00             ; 314 Merchant
        .byte   $00             ; 315 B.Day Suit
        .byte   $01             ; 316 Tentacle
        .byte   $02             ; 317 Tentacle
        .byte   $00             ; 318 Tentacle
        .byte   $01             ; 319 RightBlade
        .byte   $00             ; 320 Left Blade
        .byte   $01             ; 321 Rough
        .byte   $02             ; 322 Striker
        .byte   $00             ; 323 L.70 Magic
        .byte   $03             ; 324 Tritoch
        .byte   $00             ; 325 Laser Gun
        .byte   $0b             ; 326 Speck
        .byte   $00             ; 327 MissileBay
        .byte   $02             ; 328 Chadarnook
        .byte   $02             ; 329 Ice Dragon
        .byte   $00             ; 330 Kefka
        .byte   $03             ; 331 Storm Drgn
        .byte   $04             ; 332 Dirt Drgn
        .byte   $00             ; 333 Ipooh
        .byte   $01             ; 334 Leader
        .byte   $01             ; 335 Grunt
        .byte   $02             ; 336 Gold Drgn
        .byte   $00             ; 337 Skull Drgn
        .byte   $01             ; 338 Blue Drgn
        .byte   $02             ; 339 Red Dragon
        .byte   $01             ; 340 Piranha
        .byte   $01             ; 341 Rizopas
        .byte   $01             ; 342 Specter
        .byte   $04             ; 343 Short Arm
        .byte   $02             ; 344 Long Arm
        .byte   $00             ; 345 Face
        .byte   $00             ; 346 Tiger
        .byte   $06             ; 347 Tools
        .byte   $00             ; 348 Magic
        .byte   $00             ; 349 Hit
        .byte   $00             ; 350 Girl
        .byte   $00             ; 351 Sleep
        .byte   $05             ; 352 Hidonite
        .byte   $06             ; 353 Hidonite
        .byte   $04             ; 354 Hidonite
        .byte   $00             ; 355 L.80 Magic
        .byte   $00             ; 356 L.90 Magic
        .byte   $00             ; 357 ProtoArmor
        .byte   $00             ; 358 MagiMaster
        .byte   $00             ; 359 SoulSaver
        .byte   $02             ; 360 Ultros
        .byte   $0b             ; 361 Naughty
        .byte   $00             ; 362 Phunbaba
        .byte   $08             ; 363 Phunbaba
        .byte   $08             ; 364 Phunbaba
        .byte   $08             ; 365 Phunbaba
        .byte   $00             ; 366 (unused)
        .byte   $00             ; 367 (unused)
        .byte   $00             ; 368 (unused)
        .byte   $00             ; 369 Zone Eater
        .byte   $00             ; 370 (unused)
        .byte   $00             ; 371 (unused)
        .byte   $01             ; 372 (unused)
        .byte   $00             ; 373 Officer
        .byte   $01             ; 374 Cadet
        .byte   $00             ; 375 (unused)
        .byte   $00             ; 376 (unused)
        .byte   $00             ; 377 Soldier
        .byte   $00             ; 378 (unused)
        .byte   $00             ; 379 (unused)
        .byte   $00             ; 380 (unused)
        .byte   $03             ; 381 Atma
        .byte   $00             ; 382 (unused)
        .byte   $00             ; 383 (unused)
