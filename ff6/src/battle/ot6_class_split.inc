; ----------------------------------------------------------------------------
; what a four-class (v0.50 and older) save's revealed class bits mean: four
; bytes a species id (0..383), byte k the six-class bits the species' weakness
; of four-class bit k (slash $01, pierce $02, bludgeon $04, special $08) became;
; $00 where it had none.  Written by tools/proto_six/split.py when the six
; classes replaced the four (#566); it describes the saves of the releases
; before that, so it does not change when a row does.
; ----------------------------------------------------------------------------

Ot6ClassSplitTbl:
        .byte   $00, $08, $00, $00 ;   0 Guard
        .byte   $10, $04, $00, $00 ;   1 Soldier
        .byte   $00, $02, $00, $00 ;   2 Templar
        .byte   $01, $02, $00, $00 ;   3 Ninja
        .byte   $10, $01, $00, $00 ;   4 Samurai
        .byte   $01, $00, $04, $08 ;   5 Orog
        .byte   $00, $00, $08, $00 ;   6 Mag Roader
        .byte   $10, $00, $04, $00 ;   7 Retainer
        .byte   $10, $00, $00, $04 ;   8 Hazer
        .byte   $01, $00, $00, $04 ;   9 Dahling
        .byte   $00, $00, $04, $08 ;  10 Rain Man
        .byte   $01, $00, $00, $00 ;  11 Brawler
        .byte   $01, $02, $00, $04 ;  12 Apokryphos
        .byte   $00, $00, $04, $08 ;  13 Dark Force
        .byte   $10, $00, $00, $04 ;  14 Whisper
        .byte   $10, $00, $00, $08 ;  15 Over-Mind
        .byte   $00, $00, $04, $08 ;  16 Osteosaur
        .byte   $01, $02, $00, $00 ;  17 Commander
        .byte   $01, $02, $00, $00 ;  18 Rhodox
        .byte   $01, $02, $00, $00 ;  19 Were-Rat
        .byte   $01, $00, $04, $00 ;  20 Ursus
        .byte   $00, $08, $04, $00 ;  21 Rhinotaur
        .byte   $00, $20, $08, $00 ;  22 Steroidite
        .byte   $01, $00, $02, $00 ;  23 Leafer
        .byte   $04, $02, $00, $00 ;  24 Stray Cat
        .byte   $00, $22, $00, $00 ;  25 Lobo
        .byte   $00, $02, $00, $00 ;  26 Doberman
        .byte   $01, $00, $04, $00 ;  27 Vomammoth
        .byte   $11, $02, $00, $00 ;  28 Fidor
        .byte   $01, $02, $00, $00 ;  29 Baskervor
        .byte   $10, $00, $04, $00 ;  30 Suriander
        .byte   $01, $02, $00, $00 ;  31 Chimera
        .byte   $01, $20, $00, $00 ;  32 Behemoth
        .byte   $01, $20, $00, $00 ;  33 Mesosaur
        .byte   $01, $08, $00, $00 ;  34 Pterodon
        .byte   $00, $20, $04, $00 ;  35 FossilFang
        .byte   $00, $00, $00, $08 ;  36 White Drgn
        .byte   $00, $02, $00, $04 ;  37 Doom Drgn
        .byte   $00, $02, $04, $00 ;  38 Brachosaur
        .byte   $00, $02, $08, $00 ;  39 Tyranosaur
        .byte   $00, $0a, $00, $00 ;  40 Dark Wind
        .byte   $10, $08, $00, $00 ;  41 Beakor
        .byte   $00, $0a, $00, $00 ;  42 Vulture
        .byte   $00, $20, $00, $04 ;  43 Harpy
        .byte   $01, $00, $08, $00 ;  44 HermitCrab
        .byte   $00, $00, $08, $00 ;  45 Trapper
        .byte   $00, $0a, $00, $00 ;  46 Hornet
        .byte   $00, $02, $04, $00 ;  47 CrassHoppr
        .byte   $00, $20, $04, $00 ;  48 Delta Bug
        .byte   $01, $00, $04, $00 ;  49 Gilomantis
        .byte   $01, $02, $00, $00 ;  50 Trilium
        .byte   $10, $00, $00, $00 ;  51 Nightshade
        .byte   $10, $00, $08, $00 ;  52 TumbleWeed
        .byte   $01, $00, $00, $00 ;  53 Bloompire
        .byte   $00, $02, $04, $00 ;  54 Trilobiter
        .byte   $10, $20, $00, $00 ;  55 Siegfried
        .byte   $00, $08, $04, $00 ;  56 Nautiloid
        .byte   $01, $00, $04, $00 ;  57 Exocite
        .byte   $10, $00, $00, $00 ;  58 Anguiform
        .byte   $00, $00, $08, $00 ;  59 Reach Frog
        .byte   $01, $20, $00, $00 ;  60 Lizard
        .byte   $01, $00, $04, $00 ;  61 ChickenLip
        .byte   $10, $00, $08, $00 ;  62 Hoover
        .byte   $10, $02, $00, $00 ;  63 Rider
        .byte   $00, $00, $00, $00 ;  64 Chupon
        .byte   $00, $02, $00, $00 ;  65 Pipsqueak
        .byte   $00, $02, $08, $00 ;  66 M-TekArmor
        .byte   $01, $20, $00, $00 ;  67 Sky Armor
        .byte   $00, $00, $04, $00 ;  68 Telstar
        .byte   $10, $00, $08, $00 ;  69 Lethal Wpn
        .byte   $00, $02, $04, $00 ;  70 Vaporite
        .byte   $00, $00, $08, $00 ;  71 Flan
        .byte   $00, $02, $04, $00 ;  72 Ing
        .byte   $00, $00, $04, $00 ;  73 Humpty
        .byte   $01, $02, $00, $04 ;  74 Brainpan
        .byte   $00, $00, $04, $00 ;  75 Cruller
        .byte   $00, $08, $00, $00 ;  76 Cactrot
        .byte   $01, $02, $00, $00 ;  77 Repo Man
        .byte   $01, $20, $00, $00 ;  78 Harvester
        .byte   $10, $00, $08, $00 ;  79 Bomb
        .byte   $10, $00, $00, $08 ;  80 Still Life
        .byte   $10, $00, $08, $00 ;  81 Boxed Set
        .byte   $11, $00, $00, $00 ;  82 SlamDancer
        .byte   $00, $00, $0c, $00 ;  83 HadesGigas
        .byte   $10, $00, $00, $04 ;  84 Pug
        .byte   $00, $00, $00, $00 ;  85 Magic Urn
        .byte   $10, $00, $04, $00 ;  86 Mover
        .byte   $10, $00, $08, $00 ;  87 Figaliz
        .byte   $00, $00, $04, $00 ;  88 Buffalax
        .byte   $00, $00, $02, $00 ;  89 Aspik
        .byte   $10, $00, $00, $04 ;  90 Ghost
        .byte   $00, $02, $08, $00 ;  91 Crawler
        .byte   $00, $02, $00, $00 ;  92 Sand Ray
        .byte   $02, $00, $00, $00 ;  93 Areneid
        .byte   $00, $00, $04, $00 ;  94 Actaneon
        .byte   $01, $20, $00, $00 ;  95 Sand Horse
        .byte   $01, $00, $00, $08 ;  96 Dark Side
        .byte   $01, $00, $00, $00 ;  97 Mad Oscar
        .byte   $01, $00, $04, $00 ;  98 Crawly
        .byte   $00, $02, $00, $00 ;  99 Bleary
        .byte   $00, $22, $00, $00 ; 100 Marshal
        .byte   $11, $02, $00, $00 ; 101 Trooper
        .byte   $00, $20, $08, $00 ; 102 General
        .byte   $00, $20, $08, $00 ; 103 Covert
        .byte   $01, $02, $00, $00 ; 104 Ogor
        .byte   $00, $00, $08, $04 ; 105 Warlock
        .byte   $10, $00, $00, $08 ; 106 Madam
        .byte   $01, $00, $00, $04 ; 107 Joker
        .byte   $00, $08, $04, $00 ; 108 Iron Fist
        .byte   $10, $20, $00, $00 ; 109 Goblin
        .byte   $01, $02, $00, $00 ; 110 Apparite
        .byte   $01, $08, $00, $04 ; 111 PowerDemon
        .byte   $00, $00, $08, $04 ; 112 Displayer
        .byte   $01, $02, $00, $00 ; 113 Vector Pup
        .byte   $01, $00, $00, $00 ; 114 Peepers
        .byte   $00, $20, $04, $00 ; 115 Sewer Rat
        .byte   $00, $20, $04, $00 ; 116 Slatter
        .byte   $00, $00, $08, $00 ; 117 Rhinox
        .byte   $10, $00, $04, $00 ; 118 Rhobite
        .byte   $10, $02, $00, $00 ; 119 Wild Cat
        .byte   $10, $20, $00, $00 ; 120 Red Fang
        .byte   $11, $02, $00, $00 ; 121 Bounty Man
        .byte   $00, $00, $00, $00 ; 122 Tusker
        .byte   $01, $02, $00, $00 ; 123 Ralph
        .byte   $00, $00, $04, $00 ; 124 Chitonid
        .byte   $00, $20, $08, $00 ; 125 Wart Puck
        .byte   $00, $00, $02, $00 ; 126 Rhyos
        .byte   $00, $20, $08, $00 ; 127 SrBehemoth
        .byte   $10, $20, $00, $00 ; 128 Vectaur
        .byte   $01, $02, $00, $00 ; 129 Wyvern
        .byte   $01, $00, $08, $00 ; 130 Zombone
        .byte   $10, $20, $00, $00 ; 131 Dragon
        .byte   $00, $20, $04, $00 ; 132 Brontaur
        .byte   $00, $20, $08, $00 ; 133 Allosaurus
        .byte   $00, $0a, $00, $00 ; 134 Cirpius
        .byte   $01, $20, $00, $00 ; 135 Sprinter
        .byte   $01, $02, $00, $00 ; 136 Gobbler
        .byte   $01, $20, $00, $00 ; 137 Harpiai
        .byte   $00, $20, $04, $00 ; 138 GloomShell
        .byte   $00, $02, $08, $00 ; 139 Drop
        .byte   $01, $00, $00, $08 ; 140 Mind Candy
        .byte   $01, $00, $04, $00 ; 141 WeedFeeder
        .byte   $01, $02, $00, $00 ; 142 Luridan
        .byte   $00, $02, $04, $00 ; 143 Toe Cutter
        .byte   $10, $00, $04, $00 ; 144 Over Grunk
        .byte   $01, $08, $00, $00 ; 145 Exoray
        .byte   $00, $20, $04, $00 ; 146 Crusher
        .byte   $00, $00, $04, $00 ; 147 Uroburos
        .byte   $01, $00, $04, $00 ; 148 Primordite
        .byte   $00, $20, $00, $08 ; 149 Sky Cap
        .byte   $01, $02, $00, $00 ; 150 Cephaler
        .byte   $01, $00, $04, $00 ; 151 Maliga
        .byte   $01, $20, $00, $00 ; 152 Gigan Toad
        .byte   $10, $20, $00, $00 ; 153 Geckorex
        .byte   $10, $00, $04, $00 ; 154 Cluck
        .byte   $10, $02, $00, $00 ; 155 Land Worm
        .byte   $00, $20, $00, $00 ; 156 Test Rider
        .byte   $00, $08, $00, $00 ; 157 PlutoArmor
        .byte   $00, $20, $00, $08 ; 158 Tomb Thumb
        .byte   $00, $02, $00, $00 ; 159 HeavyArmor
        .byte   $00, $02, $04, $00 ; 160 Chaser
        .byte   $00, $20, $04, $00 ; 161 Scullion
        .byte   $10, $02, $00, $00 ; 162 Poplium
        .byte   $11, $2a, $0c, $0c ; 163 Intangir
        .byte   $01, $02, $00, $04 ; 164 Misfit
        .byte   $00, $20, $04, $00 ; 165 Eland
        .byte   $10, $00, $08, $00 ; 166 Enuo
        .byte   $00, $08, $00, $04 ; 167 Deep Eye
        .byte   $00, $02, $04, $00 ; 168 GreaseMonk
        .byte   $01, $02, $00, $04 ; 169 NeckHunter
        .byte   $00, $08, $04, $00 ; 170 Grenade
        .byte   $10, $00, $08, $00 ; 171 Critic
        .byte   $00, $00, $04, $08 ; 172 Pan Dora
        .byte   $10, $00, $00, $08 ; 173 SoulDancer
        .byte   $01, $00, $04, $00 ; 174 Gigantos
        .byte   $00, $00, $08, $00 ; 175 Mag Roader
        .byte   $10, $20, $04, $00 ; 176 Spek Tor
        .byte   $10, $00, $00, $00 ; 177 Parasite
        .byte   $01, $00, $00, $00 ; 178 EarthGuard
        .byte   $10, $00, $00, $00 ; 179 Coelecite
        .byte   $10, $00, $00, $00 ; 180 Anemone
        .byte   $00, $02, $04, $00 ; 181 Hipocampus
        .byte   $00, $00, $04, $08 ; 182 Spectre
        .byte   $10, $00, $00, $04 ; 183 Evil Oscar
        .byte   $00, $00, $08, $04 ; 184 Slurm
        .byte   $01, $20, $00, $00 ; 185 Latimeria
        .byte   $10, $00, $04, $00 ; 186 StillGoing
        .byte   $10, $00, $02, $00 ; 187 Allo Ver
        .byte   $00, $00, $00, $08 ; 188 Phase
        .byte   $10, $02, $00, $00 ; 189 Outsider
        .byte   $01, $00, $00, $10 ; 190 Barb-e
        .byte   $10, $20, $00, $00 ; 191 Parasoul
        .byte   $01, $00, $00, $08 ; 192 Pm Stalker
        .byte   $10, $00, $00, $08 ; 193 Hemophyte
        .byte   $01, $02, $00, $00 ; 194 Sp Forces
        .byte   $01, $00, $00, $00 ; 195 Nohrabbit
        .byte   $10, $02, $00, $08 ; 196 Wizard
        .byte   $01, $00, $04, $00 ; 197 Scrapper
        .byte   $00, $20, $08, $00 ; 198 Ceritops
        .byte   $00, $02, $00, $00 ; 199 Commando
        .byte   $10, $00, $04, $00 ; 200 Opinicus
        .byte   $10, $20, $00, $00 ; 201 Poppers
        .byte   $01, $20, $00, $00 ; 202 Lunaris
        .byte   $00, $02, $08, $00 ; 203 Garm
        .byte   $10, $02, $00, $00 ; 204 Vindr
        .byte   $10, $20, $00, $00 ; 205 Kiwok
        .byte   $10, $00, $04, $00 ; 206 Nastidon
        .byte   $00, $08, $00, $04 ; 207 Rinn
        .byte   $00, $02, $04, $00 ; 208 Insecare
        .byte   $00, $20, $04, $00 ; 209 Vermin
        .byte   $10, $00, $08, $04 ; 210 Mantodea
        .byte   $01, $00, $00, $08 ; 211 Bogy
        .byte   $10, $00, $08, $00 ; 212 Prussian
        .byte   $01, $00, $00, $00 ; 213 Black Drgn
        .byte   $00, $02, $04, $00 ; 214 Adamanchyt
        .byte   $01, $00, $04, $08 ; 215 Dante
        .byte   $01, $02, $00, $00 ; 216 Wirey Drgn
        .byte   $00, $20, $08, $00 ; 217 Dueller
        .byte   $00, $02, $00, $08 ; 218 Psychot
        .byte   $01, $00, $04, $00 ; 219 Muus
        .byte   $10, $00, $04, $00 ; 220 Karkass
        .byte   $01, $02, $00, $00 ; 221 Punisher
        .byte   $00, $00, $00, $00 ; 222 Balloon
        .byte   $00, $0a, $00, $00 ; 223 Gabbldegak
        .byte   $00, $02, $04, $00 ; 224 GtBehemoth
        .byte   $01, $20, $00, $00 ; 225 Scorpion
        .byte   $00, $20, $04, $00 ; 226 Chaos Drgn
        .byte   $01, $20, $00, $00 ; 227 Spit Fire
        .byte   $00, $00, $04, $08 ; 228 Vectagoyle
        .byte   $10, $00, $04, $08 ; 229 Lich
        .byte   $01, $20, $00, $00 ; 230 Osprey
        .byte   $00, $20, $08, $00 ; 231 Mag Roader
        .byte   $01, $02, $00, $00 ; 232 Bug
        .byte   $10, $00, $00, $00 ; 233 Sea Flower
        .byte   $00, $20, $08, $00 ; 234 Fortis
        .byte   $01, $02, $00, $00 ; 235 Abolisher
        .byte   $10, $20, $00, $00 ; 236 Aquila
        .byte   $00, $02, $08, $00 ; 237 Junk
        .byte   $01, $00, $04, $00 ; 238 Mandrake
        .byte   $00, $08, $04, $00 ; 239 1st Class
        .byte   $01, $00, $04, $00 ; 240 Tap Dancer
        .byte   $01, $00, $00, $04 ; 241 Necromancr
        .byte   $01, $00, $04, $00 ; 242 Borras
        .byte   $00, $20, $08, $00 ; 243 Mag Roader
        .byte   $01, $02, $00, $00 ; 244 Wild Rat
        .byte   $01, $00, $04, $00 ; 245 Gold Bear
        .byte   $00, $02, $08, $00 ; 246 Innoc
        .byte   $00, $20, $00, $08 ; 247 Trixter
        .byte   $10, $02, $00, $00 ; 248 Red Wolf
        .byte   $00, $00, $04, $08 ; 249 Didalos
        .byte   $10, $00, $00, $00 ; 250 Woolly
        .byte   $01, $02, $00, $00 ; 251 Veteran
        .byte   $00, $20, $08, $00 ; 252 Sky Base
        .byte   $00, $20, $04, $00 ; 253 IronHitman
        .byte   $00, $02, $08, $00 ; 254 Io
        .byte   $10, $00, $00, $08 ; 255 Pugs
        .byte   $00, $00, $00, $00 ; 256 Whelk
        .byte   $00, $00, $00, $00 ; 257 Presenter
        .byte   $00, $02, $04, $00 ; 258 Mega Armor
        .byte   $00, $00, $04, $00 ; 259 Vargas
        .byte   $00, $02, $00, $00 ; 260 TunnelArmr
        .byte   $00, $20, $08, $00 ; 261 Prometheus
        .byte   $00, $00, $04, $00 ; 262 GhostTrain
        .byte   $00, $02, $04, $00 ; 263 Dadaluma
        .byte   $01, $00, $00, $00 ; 264 Shiva
        .byte   $00, $02, $00, $00 ; 265 Ifrit
        .byte   $01, $02, $00, $00 ; 266 Number 024
        .byte   $00, $02, $00, $00 ; 267 Number 128
        .byte   $00, $20, $08, $00 ; 268 Inferno
        .byte   $00, $02, $00, $00 ; 269 Crane
        .byte   $00, $02, $00, $00 ; 270 Crane
        .byte   $00, $00, $00, $00 ; 271 Umaro
        .byte   $10, $20, $00, $00 ; 272 Umaro
        .byte   $00, $00, $00, $00 ; 273 Guardian
        .byte   $00, $20, $08, $00 ; 274 Guardian
        .byte   $00, $08, $00, $00 ; 275 Air Force
        .byte   $00, $00, $00, $00 ; 276 Tritoch
        .byte   $00, $00, $00, $00 ; 277 Tritoch
        .byte   $00, $02, $00, $00 ; 278 FlameEater
        .byte   $01, $02, $00, $00 ; 279 AtmaWeapon
        .byte   $01, $02, $00, $00 ; 280 Nerapa
        .byte   $00, $02, $04, $00 ; 281 SrBehemoth
        .byte   $00, $00, $00, $00 ; 282 Kefka
        .byte   $01, $20, $00, $00 ; 283 Tentacle
        .byte   $00, $02, $04, $08 ; 284 Dullahan
        .byte   $00, $20, $00, $08 ; 285 Doom Gaze
        .byte   $00, $00, $00, $00 ; 286 Chadarnook
        .byte   $10, $00, $00, $04 ; 287 Curley
        .byte   $00, $20, $04, $00 ; 288 Larry
        .byte   $10, $00, $08, $00 ; 289 Moe
        .byte   $10, $00, $00, $04 ; 290 Wrexsoul
        .byte   $00, $20, $04, $00 ; 291 Hidon
        .byte   $10, $20, $00, $00 ; 292 KatanaSoul
        .byte   $00, $00, $00, $08 ; 293 L.30 Magic
        .byte   $10, $00, $04, $00 ; 294 Hidonite
        .byte   $10, $00, $00, $08 ; 295 Doom
        .byte   $00, $20, $00, $08 ; 296 Goddess
        .byte   $00, $00, $04, $08 ; 297 Poltrgeist
        .byte   $11, $2a, $0c, $0c ; 298 Kefka
        .byte   $00, $00, $00, $08 ; 299 L.40 Magic
        .byte   $01, $08, $00, $00 ; 300 Ultros
        .byte   $01, $08, $00, $00 ; 301 Ultros
        .byte   $01, $08, $00, $00 ; 302 Ultros
        .byte   $00, $00, $08, $00 ; 303 Chupon
        .byte   $00, $00, $00, $04 ; 304 L.20 Magic
        .byte   $10, $02, $04, $00 ; 305 Siegfried
        .byte   $00, $00, $00, $08 ; 306 L.10 Magic
        .byte   $00, $00, $00, $04 ; 307 L.50 Magic
        .byte   $00, $08, $00, $00 ; 308 Head
        .byte   $00, $08, $00, $00 ; 309 Whelk Head
        .byte   $00, $00, $00, $00 ; 310 Colossus
        .byte   $00, $00, $00, $00 ; 311 CzarDragon
        .byte   $10, $00, $00, $04 ; 312 Master Pug
        .byte   $00, $00, $00, $04 ; 313 L.60 Magic
        .byte   $00, $02, $00, $00 ; 314 Merchant
        .byte   $00, $00, $00, $00 ; 315 B.Day Suit
        .byte   $01, $00, $04, $00 ; 316 Tentacle
        .byte   $00, $20, $04, $00 ; 317 Tentacle
        .byte   $01, $04, $00, $00 ; 318 Tentacle
        .byte   $01, $00, $00, $00 ; 319 RightBlade
        .byte   $01, $00, $00, $00 ; 320 Left Blade
        .byte   $10, $00, $08, $00 ; 321 Rough
        .byte   $10, $02, $00, $00 ; 322 Striker
        .byte   $00, $00, $00, $08 ; 323 L.70 Magic
        .byte   $10, $20, $00, $00 ; 324 Tritoch
        .byte   $00, $08, $00, $00 ; 325 Laser Gun
        .byte   $11, $2a, $0c, $0c ; 326 Speck
        .byte   $00, $08, $00, $00 ; 327 MissileBay
        .byte   $10, $20, $00, $00 ; 328 Chadarnook
        .byte   $00, $20, $04, $00 ; 329 Ice Dragon
        .byte   $01, $02, $00, $00 ; 330 Kefka
        .byte   $10, $01, $00, $00 ; 331 Storm Drgn
        .byte   $00, $02, $04, $00 ; 332 Dirt Drgn
        .byte   $01, $00, $00, $00 ; 333 Ipooh
        .byte   $10, $00, $00, $00 ; 334 Leader
        .byte   $10, $00, $04, $00 ; 335 Grunt
        .byte   $10, $02, $00, $00 ; 336 Gold Drgn
        .byte   $00, $00, $04, $08 ; 337 Skull Drgn
        .byte   $10, $02, $00, $00 ; 338 Blue Drgn
        .byte   $00, $20, $00, $00 ; 339 Red Dragon
        .byte   $10, $00, $04, $00 ; 340 Piranha
        .byte   $10, $00, $04, $00 ; 341 Rizopas
        .byte   $10, $00, $00, $04 ; 342 Specter
        .byte   $00, $02, $08, $00 ; 343 Short Arm
        .byte   $10, $02, $00, $00 ; 344 Long Arm
        .byte   $00, $00, $04, $08 ; 345 Face
        .byte   $10, $20, $00, $00 ; 346 Tiger
        .byte   $00, $02, $08, $00 ; 347 Tools
        .byte   $10, $00, $00, $08 ; 348 Magic
        .byte   $10, $00, $08, $00 ; 349 Hit
        .byte   $10, $20, $00, $00 ; 350 Girl
        .byte   $00, $00, $04, $08 ; 351 Sleep
        .byte   $10, $00, $04, $00 ; 352 Hidonite
        .byte   $00, $02, $04, $00 ; 353 Hidonite
        .byte   $00, $00, $04, $00 ; 354 Hidonite
        .byte   $00, $00, $00, $08 ; 355 L.80 Magic
        .byte   $00, $00, $00, $00 ; 356 L.90 Magic
        .byte   $00, $00, $08, $00 ; 357 ProtoArmor
        .byte   $00, $00, $00, $08 ; 358 MagiMaster
        .byte   $00, $00, $00, $04 ; 359 SoulSaver
        .byte   $01, $08, $00, $00 ; 360 Ultros
        .byte   $01, $02, $00, $08 ; 361 Naughty
        .byte   $00, $00, $00, $00 ; 362 Phunbaba
        .byte   $00, $00, $04, $08 ; 363 Phunbaba
        .byte   $00, $00, $04, $08 ; 364 Phunbaba
        .byte   $01, $00, $04, $08 ; 365 Phunbaba
        .byte   $00, $00, $00, $00 ; 366 (unused)
        .byte   $10, $00, $00, $00 ; 367 (unused)
        .byte   $00, $00, $00, $00 ; 368 (unused)
        .byte   $00, $00, $00, $00 ; 369 Zone Eater
        .byte   $00, $00, $00, $00 ; 370 (unused)
        .byte   $01, $00, $00, $00 ; 371 (unused)
        .byte   $10, $00, $00, $00 ; 372 (unused)
        .byte   $00, $02, $00, $00 ; 373 Officer
        .byte   $10, $00, $04, $00 ; 374 Cadet
        .byte   $00, $00, $00, $00 ; 375 (unused)
        .byte   $00, $00, $00, $00 ; 376 (unused)
        .byte   $00, $00, $00, $00 ; 377 Soldier
        .byte   $00, $00, $00, $00 ; 378 (unused)
        .byte   $00, $00, $00, $00 ; 379 (unused)
        .byte   $10, $00, $00, $00 ; 380 (unused)
        .byte   $10, $20, $00, $00 ; 381 Atma
        .byte   $10, $00, $00, $00 ; 382 (unused)
        .byte   $00, $00, $00, $00 ; 383 (unused)
