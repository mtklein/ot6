-- bal_party.lua -- the multi-character balance measurement. bal_mines.lua's
-- protocol (seeded draws, loadState-independent battles, paired samples
-- across policies) run against a PARTY instead of solo Terra, with every
-- stat attributed per party member.
--
-- THE FIXTURE. worldmap_narshe.mss puts LOCKE (battle slot 0, L6,
-- Fight/Steal/Item) and TERRA (slot 1, L4, Fight/Magic/Item, knowing Fire
-- and Cure) on the World of Balance at (84,34), the state gen_figaro.lua
-- walks south to Figaro. It is the closest existing fixture to the stretch
-- balance-metrics.md wants measured next -- Figaro -> Mt.Kolts is Terra +
-- Locke + Edgar -- and unlike the Figaro interiors it sits on a map with
-- LIVE random encounters, so the fights are the real pool rather than a
-- scripted set piece. What it is missing is EDGAR (and Sabin): the states
-- that carry them are still being minted. So the party numbers below are
-- two thirds of the stretch party, and the Edgar/Sabin kit rungs in
-- metrics_battle.lua's KITS table remain written-but-undriven. Point this
-- driver at a Kolts fixture when one exists; nothing else has to change.
--
-- Protocol (deliberately boring, and the same as bal_mines):
--  * every battle starts from an identical loadState -- battles are fully
--    independent (HP/MP/BP/RNG all reset).
--  * the danger counter $1F6E is zeroed per sample (mines_pace.lua's
--    Measurement #4 finding: the fixture's warm counter otherwise masks
--    the pacing entirely), and $1FA1 is seeded per battle index, so
--    battle k is the SAME battle in every policy arm -- paired samples.
--  * pacing is a dumb left/right two-tile walk at the spawn
--    (84,34)<->(83,34); leaving the world map or running out of budget
--    VOIDS the sample (logged; the next loadState wipes it away).
--  * the battle is then played to the end by POLICY x KIT, and metrics
--    are sampled every frame (the multi-actor core from
--    metrics_battle.lua, which documents every address and every
--    attribution rule -- read that header first).
--  * in-battle rng phase jitter: battle k arms after 240 + 7(k-1) settle
--    frames, so same-formation battles decorrelate.
--
-- Per battle the log carries greppable lines, bal_mines' shape:
--   [ot6] [metrics] b=<k> <key>=<value>
-- with the per-character fan-out riding the same `sN:` CSV convention the
-- monster lines already use. bal_aggregate.py tabulates both.
--
-- Policies (POLICY knob) set the BOOST discipline; the per-character KIT
-- picks the action, so one named policy plays two different characters:
--   baseline  never boosts, never probes -- the denominator
--   boost3    bank BP to 3, then spend all 3, and use the weakness once
--             one is revealed
--   greedy    spend every BP the turn it appears
--   badboost  bank to 3 then dump it into a plain Fight -- Measurement
--             #5's negative control, the "boost feels wasted" misplay
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

-- ------------------------------------------------------------- knobs --
-- env overrides (2026-07-21 v0.4 Zozo pass): running a policy x fixture x
-- shield-count matrix by hand is a lot of edits, so the four knobs a sweep
-- touches read an env var first and fall back to the literal default below.
-- pcall-guarded: if Mesen's lua sandbox hides os.getenv the read simply
-- yields the default, so the file still runs edited-by-hand exactly as before.
local function envcfg(name)
  local ok, v = pcall(function() return os.getenv(name) end)
  if ok and v and v ~= "" then return v end
  return nil
end
local POLICY = envcfg("BAL_POLICY") or "baseline"
-- FIXTURE names a row of FIXTURES below. The header's "point this driver at
-- a Kolts fixture; nothing else has to change" was WRONG by one thing --
-- the pacer. worldmap_narshe is on the WORLD map (worldX/worldMode); every
-- stretch fixture past it is a FIELD map (fieldX/mapId), which is
-- bal_mines' pacer, not this one's. So the pacing lane is per-fixture and
-- the two pacers both live here; everything downstream of "a battle
-- started" is shared and untouched.
local FIXTURE = envcfg("BAL_FIXTURE") or "worldmap_narshe"
local FIXTURES = {
  -- Measurement #6's fixture, kept byte-identical (state, seeds, spawn) so
  -- its numbers stay the continuity baseline for every later sweep.
  worldmap_narshe = {
    state = "/Users/mtklein/ot6/build/states/worldmap_narshe.mss.lua",
    mode = "world", spawn = 84,
    seeds = { {fa1=0x37}, {fa1=0x6e}, {fa1=0xa5},
              {fa1=0xdc}, {fa1=0x13}, {fa1=0x4a} },
  },
  -- The rung-2 stretch the playtester is actually in. $1FA2 is seeded too:
  -- unlike the Narshe world spawn (one formation in every sample) a
  -- mountain pool has several slots, and the formation draw has to be
  -- pinned or the arms are not paired.
  --
  -- `lane` names the direction to step OFF the spawn tile. Without it the
  -- pacer takes the first direction the passability model allows, and on
  -- shelf F that is LEFT -- onto (7,13), which is the entrance back to map
  -- 95 (gen_kolts' mountain flood: "F ... exits (7,13)->95"). The party
  -- would leave the map on its first step, every sample. Passability cannot
  -- see entrance records, so the safe direction is named, not derived.
  kolts_pool = {
    state = "/Users/mtklein/ot6/build/states/kolts_pool.mss.lua",
    mode = "field", map = 100, lane = "right",
    seeds = { {fa1=0x37,fa2=0x00}, {fa1=0x6e,fa2=0x01}, {fa1=0xa5,fa2=0x02},
              {fa1=0xdc,fa2=0x03}, {fa1=0x13,fa2=0x04}, {fa1=0x4a,fa2=0x05} },
  },
  -- The OTHER Mt. Kolts pool, and the one the mountain is mostly made of.
  -- kolts_pool stands on map 100, group 63 (Brawler-pair / Tusker-pair);
  -- maps 96/97 carry group 61, which is CIRPIUS x3 at 93.75% of draws.
  -- Cirpius is the species the v0.3 trash pass exists for -- no vanilla
  -- weakness of any kind, three at a time, the mountain's most common
  -- fight -- and it is the one place a GROUP tool answers a GROUP enemy,
  -- so it needs its own fixture. Minted by gen_kolts_cave.lua, which is
  -- gen_kolts' K2 crossing plus gen_kolts_pool's "prove an encounter
  -- fires" tail. Arrival is (16,22); the lane is RIGHT (the mint's own
  -- probe picked it and paced 96 without leaving it).
  kolts_cave = {
    state = "/Users/mtklein/ot6/build/states/kolts_cave.mss.lua",
    mode = "field", map = 96, lane = "right",
    seeds = { {fa1=0x37,fa2=0x00}, {fa1=0x6e,fa2=0x01}, {fa1=0xa5,fa2=0x02},
              {fa1=0xdc,fa2=0x03}, {fa1=0x13,fa2=0x04}, {fa1=0x4a,fa2=0x05} },
  },
  -- Map 95, Mt. Kolts' ENTRANCE map: a run here paced 437 tiles across six
  -- samples and drew nothing, voiding every sample as a timeout. The
  -- diagnosis written here was "carries no encounter group" and it was
  -- WRONG -- map 95 carries group 61, the same Cirpius/Tusker pool as maps
  -- 96/97 (`sub_battle_group.dat[95]` = 61). What it does not carry is the
  -- ENABLE BIT: map properties are 33 bytes at `map_prop.dat[map*33]` and
  -- byte 5 bit 7 is the flag `CheckBattleSub` tests (`lda $0525 / bpl Done`,
  -- field/battle.asm:332). Map 95 reads $00; so does map 74, which likewise
  -- has a group (59) it can never draw. The observation stands, the
  -- mechanism did not. Kept as the doorstep gen_kolts_pool.lua crosses
  -- from; measure the mountain on kolts_pool and kolts_cave.
  kolts_doorstep = {
    state = "/Users/mtklein/ot6/build/states/kolts_doorstep.mss.lua",
    mode = "field", map = 95,
    seeds = { {fa1=0x37,fa2=0x00}, {fa1=0x6e,fa2=0x01}, {fa1=0xa5,fa2=0x02},
              {fa1=0xdc,fa2=0x03}, {fa1=0x13,fa2=0x04}, {fa1=0x4a,fa2=0x05} },
  },
  south_figaro = {
    state = "/Users/mtklein/ot6/build/states/south_figaro.mss.lua",
    mode = "field", map = 75,
    seeds = { {fa1=0x37,fa2=0x00}, {fa1=0x6e,fa2=0x01}, {fa1=0xa5,fa2=0x02},
              {fa1=0xdc,fa2=0x03}, {fa1=0x13,fa2=0x04}, {fa1=0x4a,fa2=0x05} },
  },
  -- v0.4 Zozo stretch. Party is LOCKE + CELES + EDGAR + SABIN (TERRA is
  -- GONE -- she is the search target). zozo_arrival lands on the Zozo
  -- street, map 221 group 78: Gabbldegak $0DF / Harvester $04E /
  -- HadesGigas $053, all poison-weak in vanilla (Edgar's Bio Blaster is
  -- the town's break key). No lane named: the street's first walkable
  -- neighbour is fine to oscillate on; the pacer scans for it.
  zozo_arrival = {
    state = "/Users/mtklein/ot6/build/states/zozo_arrival.mss.lua",
    mode = "field", map = 221,
    seeds = { {fa1=0x37,fa2=0x00}, {fa1=0x6e,fa2=0x01}, {fa1=0xa5,fa2=0x02},
              {fa1=0xdc,fa2=0x03}, {fa1=0x13,fa2=0x04}, {fa1=0x4a,fa2=0x05} },
  },
  -- The Dadaluma boss ($0107, +2x $006C sidekicks it revives). Not a
  -- random encounter: the party stands at (30,13) one tile north of the
  -- gentleman NPC (30,14); facing DOWN and pressing A opens the dialog
  -- that fires battle 69 (gen_zozo4_dadaluma's own trigger). `trigger =
  -- "talk"` swaps the random-encounter pacer for that face-and-A drive.
  -- Seeds are inert here (fixed formation), so the six samples differ only
  -- by settle jitter -- a distribution of the SAME boss fight, whelkbal's
  -- shape. BOSS_FRAMES is longer: 3270 HP + revives + self-heal is a slog.
  dadaluma_doorstep = {
    state = "/Users/mtklein/ot6/build/states/dadaluma_doorstep.mss.lua",
    mode = "field", map = 221, trigger = "talk", face = "down",
    nbattles = 4, battleFrames = 24000, runFrames = 240000,
    seeds = { {}, {}, {}, {} },
  },
}
local FX = assert(FIXTURES[FIXTURE], "unknown FIXTURE: " .. tostring(FIXTURE))
local STATE = FX.state
-- a boss is one fixed fight sampled for its jitter distribution, not a pool
-- to cover, so it wants fewer, longer samples (FX.nbattles).
local NBATTLES = FX.nbattles or 6
-- BUFF_HP: 0 = measure the pool as it ships. >0 = set every monster's HP
-- to this before the clock starts, which is metrics_battle.lua's own
-- fixture-buff knob and the only way to make this pool express the loop
-- at all: the shipped species dies to one weakness hit, so BP can never
-- reach 3 and two chips can never land on a live target. A buffed arm
-- measures the INSTRUMENT and the loop's shape; the unbuffed arm is the
-- honest stretch number. Never mix them in one table.
local BUFF_HP = 0
-- BUFF_SHIELDS: 0 = the shields Ot6SeedShields really seeded (authored row,
-- or the level formula 2 + level/8 capped at 6). >0 = overwrite every
-- monster's CURRENT and MAX shield cell with this before the clock starts.
-- This is the shield-count lever measured WITHOUT a ROM edit: the formula
-- is inline code, so a source change would have to be rebuilt per cell,
-- while the seeded cells are plain WRAM and the whole break system reads
-- them and nothing else. Like BUFF_HP it is a synthetic arm -- label it,
-- never average it with the shipped one.
local BUFF_SHIELDS = tonumber(envcfg("BAL_BUFF_SHIELDS") or "") or 0
-- BUFF_CLASS: 0 = the class-weakness mask Ot6SeedShields really seeded,
-- which for every FORMULA species is $00 -- no class weakness at all (the
-- @formula path explicitly clears $3e9c). >0 = OR this mask into every
-- monster's class-weak cell, i.e. simulate an authored Ot6ShieldTbl row
-- WITHOUT authoring one. OT6_SLASH $01, OT6_PIERCE $02, OT6_BLUDG $04.
--
-- This is the "what would authoring buy" arm, and it is the only way to
-- ask that question before the authoring exists. It matters because the
-- two chip channels are NOT interchangeable: an element-weak hit collects
-- vanilla's x2 and a class-weak hit collects nothing ("the damage bonus
-- for classes is the break window itself", Ot6ClassChip), so the breaking
-- hit is 4x base through the element channel and 2x base through the class
-- channel. Which channel does the chipping decides whether a broken target
-- can survive its own break.
local BUFF_CLASS = 0
local PACE_FRAMES = 7000            -- pacing budget per battle
-- policy-driven battle budget. A boss ($0107 Dadaluma: 3270 HP, revives two
-- sidekicks, self-heals) runs far longer than trash, so a fixture may raise
-- it; 9000 is the trash default.
local BATTLE_FRAMES = FX.battleFrames or 9000
local SEEDS = FX.seeds              -- $1FA1 (step roll) / $1FA2 (formation)

-- Difficulty-knob poke, bal_mines.lua's mechanism verbatim (Measurement #4
-- proved poking the loaded ROM image equals a rebuild: the scale routines
-- read these very bytes). POKE_SHIELD -> Ot6ShieldedMulW in 16ths ($10 =
-- 1x/off, $08 = 0.5x, $06 = 0.375x, $04 = 0.25x, $02 = 0.125x); POKE_HP ->
-- Ot6HpMulTbl band0. nil = leave the shipped byte.
local POKE_SHIELD = nil
local POKE_HP = nil
-- POKE_AUTHORING: nil = the v0.3 trash weakness rows as they ship.
-- "off" = neutralise them in the loaded ROM image, which is the BEFORE arm
-- of the authoring measurement. Doing it by poke rather than by two builds
-- is not a shortcut, it is the better experiment: both arms then run
-- against the SAME savestate mint, the same party HP/MP/gil and the same
-- seeds, so the only difference between them is the ten bytes below. (Two
-- builds cannot give that -- the fixture is minted by PLAYING the game, and
-- a ROM where the trash has weaknesses is a ROM where the mint's own fights
-- go differently.) Measurement #4 established the equivalence of poking the
-- loaded image to rebuilding: the scanners read these very bytes.
--   * Ot6ElemAddTbl -- the six v0.3 rows are the LAST six, so writing the
--     $FFFF terminator over the first of them hides exactly those and
--     leaves the eight boss/armor rows above untouched.
--   * Ot6ShieldTbl -- Brawler's row is in the MIDDLE, and only $FFFF ends
--     that scan, so it is disabled by rewriting its species id to $0FFF:
--     4095 is past the 384-species table (monster_prop.dat is 12288 bytes
--     / 32), so it can never match and the rows after it stay live.
local POKE_AUTHORING = envcfg("BAL_AUTHORING")   -- "off" = neutralise rows
-- Bank-$F0 offsets are BUILD-SPECIFIC and drifted repeatedly (bal_mines'
-- header tells that story: eighteen bytes early, poking live code while
-- reporting a grid; and these Kolts rows slid +$14 twice in the v0.4 Zozo
-- pass alone). The TABLE BASES now derive from ff6/rom/ff6-en.dbg at compose
-- time via H.sym, so they can no longer go stale by hand; `& 0x3FFFFF` maps
-- each CPU address to its snesPrgRom file offset (bank $F0 -> $30xxxx).
local ROM_HPMUL  = H.sym("Ot6HpMulTbl") & 0x3FFFFF       -- band0 byte
local ROM_SHIELD = H.sym("Ot6ShieldedMulW") & 0x3FFFFF   -- word, low byte
-- The v0.3 authoring rows, as (derived base) + (row index * 4-byte stride):
-- Ot6ElemAddTbl row 8 = the first v0.3 trash row ($0086 cirpius); the three
-- Ot6ShieldTbl rows are brawler ($000B, row 5), cirpius ($0086, row 6),
-- tusker ($007A, row 7). Only the ROW INDEX is written out now -- the base is
-- derived, and AUTHORING_OK below still verifies the species at each row
-- before the destructive poke, since a row can move WITHIN its table.
local ROM_ELEMADD_V3    = (H.sym("Ot6ElemAddTbl") & 0x3FFFFF) + 8 * 4
local SHIELDTBL         = H.sym("Ot6ShieldTbl") & 0x3FFFFF
local ROM_SHIELDROWS_V3 = { SHIELDTBL + 5 * 4, SHIELDTBL + 6 * 4, SHIELDTBL + 7 * 4 }
-- brawler's row = ROM_SHIELDROWS_V3[1]; the knob_authoring report line reads
-- it as the ShieldTbl witness.
local ROM_BRAWLER_ROW = ROM_SHIELDROWS_V3[1]
-- what those words MUST read before the authoring poke touches them; a
-- mismatch now means a row moved WITHIN its table (the base can't be stale --
-- it's derived), so the row indices above need bumping.
local AUTHORING_OK = { [ROM_ELEMADD_V3]       = 0x0086,
                       [ROM_SHIELDROWS_V3[1]] = 0x000b,
                       [ROM_SHIELDROWS_V3[2]] = 0x0086,
                       [ROM_SHIELDROWS_V3[3]] = 0x007a }

-- --------------------------------------------------------- addresses --
-- (all cited in metrics_battle.lua's header; kept in the same order)
local MENU  = 0x7bca               -- battle menu open flag
local ACTOR = 0x62ca               -- whose menu it is (battle slot)
local MSTATE = 0x7bc2              -- battle menu state (btlgfx_main.asm:12536)
local PHP   = 0x3bf4               -- party cur hp, +slot*2
local PMP   = 0x3c08               -- party cur mp, +slot*2
local MHP   = 0x3bfc               -- monster cur hp, +slot*2
local BP    = 0x3e9c               -- char bp, +slot*2
local PEND  = 0x3e9d               -- char pending boost, +slot*2
local SHLD  = 0x3e40               -- monster cur shields, +slot*2
local TIMER = 0x3e90               -- monster broken timer, +slot*2
local RVEAL = 0x3e91               -- monster revealed elements, +slot*2
local WEAK  = 0x3be8               -- monster weak elements, +slot*2
local WKC   = 0x3ea4               -- monster class-weak mask, +slot*2
                                   --   ($3e9c's monster half: chars +0..+6)
local RVEALC = 0x3ea5              -- monster revealed CLASSES, +slot*2
                                   --   ($3e9d's monster half; Ot6ClassChip
                                   --   ORs the matched bit in as it chips,
                                   --   ot6.asm:736-738 -- the class twin of
                                   --   RVEAL, and the gate a kit needs to
                                   --   know a class weakness was found)
local ALIVE = 0x3aa8               -- monster presence bit0, +slot*2
local MSTAT = 0x3eec               -- monster status-1, +slot*2 ($c2 = gone)
local CHARIX = 0x3ed9              -- battle slot -> character index, +slot*2
local CMDTBL = 0x202e              -- battle commands, +slot*12 +i*3 (BY SLOT)
local DANGER = 0x1f6e              -- random battle counter (word)
local QUEUES = {                   -- `shadow`: dispatches an attack?
  { base = 0x3720, ptr = 0x3a64, counter = false, shadow = false }, -- gauge-full
  { base = 0x3820, ptr = 0x3a66, counter = false, shadow = true  }, -- ExecAction
  { base = 0x3920, ptr = 0x3a68, counter = true,  shadow = true  }, -- ExecRetal
}
-- blitz is now a menu that reuses the tools window (state $30 = ST.tools).
local ST = { root = 0x05, spell = 0x0e, tools = 0x30, magitek = 0x2a,
             item = 0x0a, target = 0x38 }

local function bp(slot) return H.readByte(BP + slot*2) end
local function pend(slot) return H.readByte(PEND + slot*2) end
local function broken(slot) return H.readByte(TIMER + slot*2) > 0 end
local function monsterAlive(slot)
  return (H.readByte(ALIVE + slot*2) & 0x01) == 1
     and (H.readByte(MSTAT + slot*2) & 0xc2) == 0
end
local function battleCmd(slot, i) return H.readByte(CMDTBL + slot*12 + i*3) end
local function hasCmd(rec, want)
  for i = 0, 3 do if rec.cmds[i] == want then return true end end
  return false
end
local function pokeCmd(slot, cmd)
  for i = 0, 3 do H.writeByte(CMDTBL + slot*12 + i*3, cmd) end
end
-- What the player KNOWS, not what is currently on screen. These read the
-- battle-scoped accumulators the sampler ORs the living monsters' reveal
-- cells into every frame, and that stickiness is a correctness fix, not a
-- convenience (2026-07-19). $3E91/$3EA5 are PER-MONSTER cells: chip the
-- first of a pair, learn its weakness, kill it -- and the bit dies with it,
-- so a poll over living monsters said the board was unread again. Measured
-- consequence, on a Brawler pair: Edgar's probe swing chipped and revealed
-- SLASH, the Brawler died, and his `slash` exploit rung then failed its
-- gate and dropped him to AutoCrossbow for the rest of the fight --
-- `char_plan=s0:probe_bio*1+probe_swing*1+xbow*1`, 1 chip out of 4
-- available, 0 breaks. No player forgets a weakness because the monster
-- that taught it fell over; the codex (OT6_CODEX_CLASS) does not either.
-- Their own upvalues, not fields of S: S is declared BELOW these helpers, so
-- naming it here compiles to a global read and dies with "attempt to index a
-- nil value (global 'S')" on the first menu of the first battle.
local seenElem, seenClass = 0, 0
local function seenReset() seenElem, seenClass = 0, 0 end
local function seenAdd(e, c) seenElem = seenElem | e seenClass = seenClass | c end
local function anyRevealed(mask) return (seenElem & mask) ~= 0 end
local function anyRevealedClass(mask) return (seenClass & mask) ~= 0 end

local ROSTER = {
  [0x00]="TERRA", [0x01]="LOCKE", [0x02]="CYAN",  [0x03]="SHADOW",
  [0x04]="EDGAR", [0x05]="SABIN", [0x06]="CELES", [0x07]="STRAGO",
  [0x08]="RELM",  [0x09]="SETZER",[0x0a]="MOG",   [0x0b]="GAU",
  [0x0c]="GOGO",  [0x0d]="UMARO", [0x0e]="WEDGE", [0x0f]="VICKS",
}

-- ------------------------------------------------------------- kits --
-- Same shape and same rationale as metrics_battle.lua's KITS: a per
-- character preference ladder, gated on the commands the actor really
-- owns, with sub-list entries reached by writing the cursor triple
-- rather than pressing toward them.
local CMD = { fight = 0x00, item = 0x01, magic = 0x02, steal = 0x05,
              tools = 0x09, blitz = 0x0a, magitek = 0x1d }
local SPELL = { fire = 0x00, ice = 0x01, ice2 = 0x06, ice3 = 0x0a, cure = 0x2d }
local TOOL  = { autocrossbow = 0xaa, bioblaster = 0xa4 }
local BLITZ = { pummel = 0x5d, aurabolt = 0x5e }          -- resolved attack ids
local SPELLBASE = { [0] = 0x0000, [1] = 0x013c, [2] = 0x0278, [3] = 0x03b4 }
local function magicCursor(slot, spellId)
  local base = 0x2092 + SPELLBASE[slot]
  for i = 0, 53 do
    if H.readByte(base + i*4) == spellId then
      local r, c = i // 2, i % 2
      local scroll = (r <= 3) and 0 or math.min(r - 3, 0x17)
      H.writeByte(0x8913 + slot, scroll)
      H.writeByte(0x8917 + slot, c)
      H.writeByte(0x891b + slot, r - scroll)
      return true
    end
  end
  return false
end
local function toolsCursor(slot, itemId)
  for i = 0, 7 do
    if H.readByte(0x4005 + i*3) == itemId then
      H.writeByte(0x895f + slot, 0)
      H.writeByte(0x8963 + slot, i % 2)
      H.writeByte(0x8967 + slot, i // 2)
      return true
    end
  end
  return false
end

local KITS = {
  [0x00] = { name = "TERRA",
    { tag = "fire", cmd = CMD.magic, mp = 4, want = "weak_fire",
      pick = function(slot) return magicCursor(slot, SPELL.fire) end },
    { tag = "probe_fire", cmd = CMD.magic, mp = 4, want = "probe_turn",
      pick = function(slot) return magicCursor(slot, SPELL.fire) end },
    { tag = "fight", cmd = CMD.fight },
    { tag = "tek", cmd = CMD.magitek },
  },
  [0x01] = { name = "LOCKE",
    { tag = "steal", cmd = CMD.steal, want = "probe_turn" },
    { tag = "fight", cmd = CMD.fight },
  },
  -- EDGAR carries the stretch's two DELIBERATE keys and this ladder is
  -- what drives them. It grew two probe rungs and one exploit rung for
  -- the v0.3 trash-weakness pass, because as written the poison rung
  -- could never fire: `want = "weak_poison"` waits for poison to be
  -- REVEALED, and the only thing in the party that casts poison is the
  -- BioBlaster itself. Circular -- so Edgar has to be willing to SPEND a
  -- turn finding out, exactly as Terra spends one on probe_fire and Locke
  -- one on Steal. Two turns, in the order a player would try them:
  --   probe_swing the SWORD first. It is the cheapest probe there is -- no
  --               menu, no item, the thing the A button already does -- and
  --               Edgar's Mithril Blade is the party's only slashing weapon
  --               (ot6_class.asm:59), so this rung is the sole way any
  --               driver can discover a slash row. Brawler's, for one.
  --   probe_bio   then the tool, if the blade taught nothing. Free (0 MP)
  --               and it targets the whole enemy side (magic_prop_en.dat
  --               $7d: tgt $6a), so one turn probes every monster in the
  --               formation at once.
  -- and `bio`/`slash` exploit whichever answered. THE ORDER WAS MEASURED,
  -- not assumed. Tool-first was tried and it is strictly worse, for a
  -- reason worth keeping: Brawler ABSORBS poison (monster_prop.dat +$0177
  -- = $08), so a tool-first Edgar opens every Brawler fight by HEALING both
  -- of them -- 75 to 86 HP of it per fight, which the driver reports as
  -- `monster_heal` -- and only reaches the blade on his second turn, by
  -- which time Locke and Terra have spent the monster's HP and the break
  -- lands on a corpse. It made the MASH arm chip Brawlers better than the
  -- loop arm (3.5 chips / 1.5 breaks vs 1.0 / 0.0), which is backwards.
  -- The trap is real and stays in the game; leading with the free probe is
  -- simply what a player does, and it is what the loop needs here.
  [0x04] = { name = "EDGAR",
    { tag = "bio", cmd = CMD.tools, want = "weak_poison",
      pick = function(slot) return toolsCursor(slot, TOOL.bioblaster) end },
    { tag = "slash", cmd = CMD.fight, want = "weak_slash" },
    { tag = "probe_swing", cmd = CMD.fight, want = "probe1" },
    { tag = "probe_bio", cmd = CMD.tools, want = "probe2",
      pick = function(slot) return toolsCursor(slot, TOOL.bioblaster) end },
    { tag = "xbow", cmd = CMD.tools,
      pick = function(slot) return toolsCursor(slot, TOOL.autocrossbow) end },
    { tag = "fight", cmd = CMD.fight },
  },
  [0x05] = { name = "SABIN",
    { tag = "blitz", cmd = CMD.blitz,
      pick = function(slot) return toolsCursor(slot, BLITZ.pummel) end },
    { tag = "fight", cmd = CMD.fight },
  },
  -- CELES is the v0.4 Zozo party's ICE carrier -- the deliberate key the A
  -- button does not swing, the twin of Terra's Fire one stretch earlier
  -- (Terra is GONE this stretch, so there is no native fire at all). Her
  -- natural list is Ice 1 / Cure 4 / Antdot 8 / Scan 18 / Ice2 26 / Ice3 42
  -- (field/event.asm NaturalMagic, celes block), so ICE is her whole
  -- offensive ring here; the pick takes the strongest ice she owns. Ice
  -- answers the corridor's fire-absorbing Bombs/Grenades (ice|water weak),
  -- FossilFang (ice among its weaks, and it ABSORBS the poison answer), and
  -- the Zozo outlier Crawler ($05b, ice-only). In the poison town her ice
  -- reveals nothing, so she probes once and falls to her SLASH Fight --
  -- Edgar's Bio Blaster carries that pool, not her.
  [0x06] = { name = "CELES",
    { tag = "ice", cmd = CMD.magic, mp = 5, want = "weak_ice",
      pick = function(slot) return magicCursor(slot, SPELL.ice2)
                                 or magicCursor(slot, SPELL.ice) end },
    { tag = "probe_ice", cmd = CMD.magic, mp = 5, want = "probe_turn",
      pick = function(slot) return magicCursor(slot, SPELL.ice2)
                                 or magicCursor(slot, SPELL.ice) end },
    { tag = "fight", cmd = CMD.fight },
  },
}
local FALLBACK_KIT = { name = "?", { tag = "fight", cmd = CMD.fight } }

-- ---------------------------------------------------------- policies --
local POLICIES = {}
POLICIES.baseline = { boost = function() return 0 end, probe = false }
POLICIES.boost3   = { boost = function(slot)
  return bp(slot) >= 3 and 3 or 0 end, probe = true }
POLICIES.greedy   = { boost = function(slot)
  return bp(slot) >= 1 and math.min(bp(slot), 3) or 0 end, probe = true }
POLICIES.badboost = { boost = function(slot)
  return bp(slot) >= 3 and 3 or 0 end, probe = false, force = "fight" }
-- mash: LITERALLY holding A. Every character Fights with what is equipped,
-- nobody boosts, nobody opens a menu. Added 2026-07-19 for the trash
-- weakness pass, which has to answer "does the mash arm chip by accident?"
-- and could not: `baseline` has no probe discipline but still lets Edgar
-- fall through to AutoCrossbow, because that rung carries no `want` gate.
-- That is a fine denominator (and stays one -- every published measurement
-- uses it) but it is not a masher: it swings PIERCE from Edgar where a
-- masher swings his Mithril Blade's SLASH. The two arms differ by exactly
-- that, so run both and read `chips` in each.
POLICIES.mash     = { boost = function() return 0 end,
                      probe = false, force = "fight" }

-- ------------------------------------------------------ accumulators --
local S, C, bySlot, mons, qShadow
local refs, shSeen, tmSeen = {}, {}, {}
local curActor, curSlot
local pendChips, pendBreaks
local voidReason, paceSteps
local actTrace

local function resetBattleState()
  seenReset()           -- battles are loadState-independent: so is knowledge
  S = {
    t0 = 0, frames = 0,
    playerActions = 0, enemyActions = 0, counterActions = 0,
    -- "breaks per fight" is a misleading number on its own: Measurement #6
    -- broke 6/6 fights and every break landed on the killing blow, so the
    -- reward the whole system is built around was never once collected.
    -- These two say whether a WINDOW existed, not whether a break fired:
    -- actions the party got to take against a broken target, and enemy
    -- turns skipped while it was broken.
    playerActionsBroken = 0, enemyActionsBroken = 0,
    playerDequeues = 0, enemyDequeues = 0,
    playerDmg = 0, playerDmgBroken = 0, monsterHeal = 0,
    monsterSelfDmg = 0, unattributedDmg = 0,
    enemyDmg = 0, partyHeal = 0,
    regens = 0, boosts = { 0, 0, 0 },
    chips = 0, breaks = 0, breakFrames = {}, firstBreak = -1,
    unattributedChips = 0, unattributedBreaks = 0,
    brokenUptime = 0, nudges = 0,
    result = "budget",
  }
  C, bySlot, mons, qShadow = {}, {}, {}, {}
  curActor, curSlot = -1, nil
  pendChips, pendBreaks = {}, {}
  voidReason, paceSteps = nil, 0
  actTrace = {}
end

local function newChar(slot)
  local cix = H.readByte(CHARIX + slot*2)
  local cmds = {}
  for i = 0, 3 do cmds[i] = battleCmd(slot, i) end
  return {
    slot = slot, cix = cix, name = ROSTER[cix] or string.format("c%02X", cix),
    kit = KITS[cix] or FALLBACK_KIT, cmds = cmds,
    hp = H.readWord(PHP + slot*2), hp0 = H.readWord(PHP + slot*2),
    mp = H.readWord(PMP + slot*2), mp0 = H.readWord(PMP + slot*2),
    bp = bp(slot), bp0 = bp(slot),
    dequeues = 0, actions = 0, bpWrites = 0,
    dmg = 0, dmgBroken = 0, taken = 0, healed = 0,
    chips = 0, breaks = 0,
    boosts = { 0, 0, 0 }, bpSpent = 0, regens = 0,
    plans = {},
  }
end

-- ------------------------------------------------- turn state machine --
local ep = { slot = nil, entry = nil, want = 0, placed = false, pulses = 0 }
local function resetEpisode()
  ep.slot, ep.entry, ep.want, ep.placed = nil, nil, 0, false
  ep.pulses = 0
end

local function entryOk(rec, entry, pol)
  if pol.force and entry.tag ~= pol.force and entry.tag ~= "fight" then
    return false
  end
  if not hasCmd(rec, entry.cmd) then return false end
  if entry.mp and H.readWord(PMP + rec.slot*2) < entry.mp then return false end
  if entry.want == "weak_fire" then return pol.probe and anyRevealed(0x01) end
  -- ice is element bit $02 (fire $01, ice $02, bolt $04, poison $08 ...);
  -- Celes's exploit rung, the twin of Terra's weak_fire.
  if entry.want == "weak_ice" then return pol.probe and anyRevealed(0x02) end
  -- poison is element bit $08. This read $20 (PEARL) until 2026-07-19 --
  -- the bit order is fire $01, ice $02, bolt $04, poison $08, wind $10,
  -- pearl $20, earth $40, water $80 (Ot6Chip walks it from bit 0 at
  -- ot6.asm:627-633, and Ot6ElemAddTbl's own rows read $08 for the poison
  -- armor line). The rung had never been driven, so the wrong bit had
  -- never cost a measurement; it would have cost this one.
  if entry.want == "weak_poison" then return pol.probe and anyRevealed(0x08) end
  if entry.want == "weak_slash" then
    return pol.probe and anyRevealedClass(0x01)     -- OT6_SLASH
  end
  -- probe1/probe2: Edgar's FIRST and SECOND information turns. The gate is
  -- "nothing *Edgar* can exploit is known yet", not Terra's "nothing at all
  -- is known" -- and that distinction is load-bearing, not pedantry. Edgar's
  -- ladder can act on poison and on a class; it can do nothing whatever with
  -- a revealed FIRE, which is Terra's key. Under the board-wide gate, Terra
  -- probing first and finding fire (Tusker is fire-weak) stopped Edgar
  -- probing before he ever opened Tools, so the poison rung stayed dead for
  -- exactly the species it was authored for. Reading only REVEALED bits
  -- keeps this honest: the gate sees what the player sees, never the
  -- monster's hidden weak byte.
  if entry.want == "probe1" or entry.want == "probe2" then
    local unread = not anyRevealed(0x08) and not anyRevealedClass(0xff)
    local n = (entry.want == "probe1") and 0 or 1
    return pol.probe and unread and rec.actions == n
  end
  if entry.want == "probe_turn" then
    -- this actor's opening information turn, taken only while the board
    -- is unread. Covers Locke's Steal and Terra's Fire alike -- an
    -- element is only REVEALED by hitting it, so an exploit rung alone
    -- can never fire. One probe per actor, then stop. (Full rationale in
    -- metrics_battle.lua.)
    return pol.probe and not anyRevealed(0xff) and rec.actions == 0
  end
  return true
end

local function chooseAction(rec, pol)
  local pick
  for _, entry in ipairs(rec.kit) do
    if entryOk(rec, entry, pol) then pick = entry break end
  end
  if pick == nil then pick = { tag = "default", cmd = rec.cmds[0] } end
  pokeCmd(rec.slot, pick.cmd)
  return pick
end

local function pulse()
  if H.readByte(MENU) == 0 then
    if ep.slot ~= nil then resetEpisode() end
    return nil
  end
  local slot = H.readByte(ACTOR)
  local rec = bySlot[slot]
  if rec == nil then return { "a" } end
  if ep.slot ~= slot then resetEpisode() ep.slot = slot end
  ep.pulses = ep.pulses + 1
  if ep.entry == nil then
    ep.want = POLICIES[POLICY].boost(slot)
    ep.entry = chooseAction(rec, POLICIES[POLICY])
    rec.plans[ep.entry.tag] = (rec.plans[ep.entry.tag] or 0) + 1
  end
  if ep.pulses > 40 then
    ep.pulses, ep.placed, ep.entry = 0, false, nil
    S.nudges = S.nudges + 1
    return { "b" }
  end
  local st = H.readByte(MSTATE)
  if st == ST.root then
    if pend(slot) < ep.want and pend(slot) < bp(slot) then return { "r" } end
    return { "a" }
  end
  if st == ST.spell or st == ST.tools then
    if not ep.placed then
      ep.placed = true
      if ep.entry.pick then ep.entry.pick(slot) end
      return nil
    end
    return { "a" }
  end
  if st == ST.magitek or st == ST.item then return { "a" } end
  if st == ST.target then return { "a" } end
  return nil
end

-- -------------------------------------------------- event watchers --
local function arm()
  S.t0 = H.frame
  for i = 0, 5 do
    shSeen[i] = H.readByte(SHLD + i*2)
    tmSeen[i] = H.readByte(TIMER + i*2)
  end
  refs[1] = emu.addMemoryCallback(function(addr, value)
    local off = addr - (0x7e0000 + SHLD)
    if off % 2 ~= 0 then return end
    local slot = off // 2
    local prev = shSeen[slot]
    shSeen[slot] = value
    if value < prev then
      S.chips = S.chips + (prev - value)
      pendChips[#pendChips + 1] = prev - value
    end
  end, emu.callbackType.write, 0x7e0000 + SHLD, 0x7e0000 + SHLD + 11)
  refs[2] = emu.addMemoryCallback(function(addr, value)
    local off = addr - (0x7e0000 + TIMER)
    if off % 2 ~= 0 then return end
    local slot = off // 2
    local prev = tmSeen[slot]
    tmSeen[slot] = value
    if prev == 0 and value > 0 then
      S.breaks = S.breaks + 1
      local at = H.frame - S.t0
      S.breakFrames[#S.breakFrames + 1] = at
      if S.firstBreak < 0 then S.firstBreak = at end
      pendBreaks[#pendBreaks + 1] = 1
    end
  end, emu.callbackType.write, 0x7e0000 + TIMER, 0x7e0000 + TIMER + 11)
end
local function disarm()
  emu.removeMemoryCallback(refs[1], emu.callbackType.write,
    0x7e0000 + SHLD, 0x7e0000 + SHLD + 11)
  emu.removeMemoryCallback(refs[2], emu.callbackType.write,
    0x7e0000 + TIMER, 0x7e0000 + TIMER + 11)
end

-- ------------------------------------------------- per-frame sampler --
local function sample()
  S.frames = H.frame - S.t0
  -- read the broken state BEFORE walking the queues, so an action dequeued
  -- this frame is credited against the board it is actually acting on
  local brokenNow = false
  for _, m in ipairs(mons) do
    if monsterAlive(m.slot) and broken(m.slot) then brokenNow = true end
  end
  for qi, q in ipairs(QUEUES) do
    local cur = H.readByte(q.ptr)
    while qShadow[qi] ~= cur do
      local v = H.readByte(q.base + qShadow[qi])
      if (v & 0x80) == 0 then
        if q.shadow then
          curActor = v
          curSlot = (v < 8) and (v // 2) or nil
        end
        if q.counter then S.counterActions = S.counterActions + 1 end
        if v < 8 then
          S.playerDequeues = S.playerDequeues + 1
          if S.playerDequeues % 2 == 0 then
            S.playerActions = S.playerActions + 1
            if brokenNow then
              S.playerActionsBroken = S.playerActionsBroken + 1
            end
          end
          local rec = bySlot[v // 2]
          if rec then
            rec.dequeues = rec.dequeues + 1
            if rec.dequeues % 2 == 0 then
              rec.actions = rec.actions + 1
              actTrace[#actTrace + 1] = string.format("%d:s%d:%d",
                S.playerActions, rec.slot, S.playerDmg)
            end
          end
        else
          S.enemyDequeues = S.enemyDequeues + 1
          if S.enemyDequeues % 2 == 0 then
            S.enemyActions = S.enemyActions + 1
            if brokenNow then
              S.enemyActionsBroken = S.enemyActionsBroken + 1
            end
          end
        end
      end
      qShadow[qi] = (qShadow[qi] + 1) & 0xff
    end
  end
  local actorRec = curSlot and bySlot[curSlot]
  for i = 1, #pendChips do
    if actorRec then actorRec.chips = actorRec.chips + pendChips[i]
    else S.unattributedChips = S.unattributedChips + pendChips[i] end
    pendChips[i] = nil
  end
  for i = 1, #pendBreaks do
    if actorRec then actorRec.breaks = actorRec.breaks + 1
    else S.unattributedBreaks = S.unattributedBreaks + 1 end
    pendBreaks[i] = nil
  end
  -- `monsterAlive and broken`, not bare `broken` -- the same predicate
  -- brokenNow above uses, and it was NOT the same before 2026-07-19. The
  -- broken timer is $10 ticks decremented on the monster's own turn
  -- (ot6.asm:20, :1140), so a monster that breaks and DIES to the breaking
  -- hit never ticks it down: the corpse stays "broken" for the rest of the
  -- fight and every frame of it was counted as break uptime. That is the
  -- worst possible failure mode for this metric, because break-and-die is
  -- precisely the pathology the uptime number exists to detect -- it
  -- reported 58% uptime on a Brawler pair where `player_actions_broken`
  -- was 0, i.e. where the window never existed at all.
  -- accumulate what the player has been told, before anyone dies of it
  for slot = 0, 5 do
    if monsterAlive(slot) then
      seenAdd(H.readByte(RVEAL + slot*2), H.readByte(RVEALC + slot*2))
    end
  end
  local anyBroken = false
  for _, m in ipairs(mons) do
    if monsterAlive(m.slot) and broken(m.slot) then anyBroken = true end
    local hp = H.readWord(MHP + m.slot*2)
    if hp < m.hp then
      local d = m.hp - hp
      S.playerDmg = S.playerDmg + d
      m.dmg = m.dmg + d
      if broken(m.slot) then S.playerDmgBroken = S.playerDmgBroken + d end
      if actorRec then
        actorRec.dmg = actorRec.dmg + d
        if broken(m.slot) then actorRec.dmgBroken = actorRec.dmgBroken + d end
      elseif curActor >= 8 then
        S.monsterSelfDmg = S.monsterSelfDmg + d
      else
        S.unattributedDmg = S.unattributedDmg + d
      end
    elseif hp > m.hp then
      S.monsterHeal = S.monsterHeal + (hp - m.hp)
    end
    m.hp = hp
  end
  if anyBroken then S.brokenUptime = S.brokenUptime + 1 end
  for _, c in ipairs(C) do
    local hp = H.readWord(PHP + c.slot*2)
    if hp < c.hp then
      S.enemyDmg = S.enemyDmg + (c.hp - hp)
      c.taken = c.taken + (c.hp - hp)
    elseif hp > c.hp then
      S.partyHeal = S.partyHeal + (hp - c.hp)
      c.healed = c.healed + (hp - c.hp)
    end
    c.hp = hp
    c.mp = H.readWord(PMP + c.slot*2)
    local b = bp(c.slot)
    if b > c.bp then
      S.regens = S.regens + (b - c.bp)
      c.regens = c.regens + (b - c.bp)
      c.bpWrites = c.bpWrites + 1
    elseif b < c.bp then
      local lvl = c.bp - b
      if lvl >= 1 and lvl <= 3 then
        S.boosts[lvl] = S.boosts[lvl] + 1
        c.boosts[lvl] = c.boosts[lvl] + 1
      end
      c.bpSpent = c.bpSpent + lvl
      c.bpWrites = c.bpWrites + 1
    end
    c.bp = b
  end
  -- party death first: a wipe's game-over teardown must read "wiped",
  -- not "torn_down" (bal_mines' fire-policy postmortem)
  local aliveC = 0
  for _, c in ipairs(C) do if c.hp > 0 then aliveC = aliveC + 1 end end
  if aliveC == 0 then S.result = "wiped" return true end
  -- The teardown probe scans the WHOLE party, not slot 0. lib/ot6.lua's
  -- H.battleLoadStarted() reads one word -- M.BATTLE_HP = $3BF4, which is
  -- battle slot 0's current HP (lib/ot6.lua:301,:336) -- and calls a zero
  -- there "no battle". That held for every fixture before this one because
  -- no slot-0 character ever died in them. On kolts_pool slot 0 is EDGAR
  -- and a Tusker pair kills him in four enemy actions, so the driver
  -- declared `torn_down` and abandoned battles that were still being
  -- fought: 9 of 48 samples in the first authoring sweep, each one cut at
  -- the exact frame Edgar fell, with TTK, damage taken and the win/loss
  -- ledger all truncated with it. Scanning all four slots asks the question
  -- the probe meant to ask ("is anyone still standing in a battle?"); the
  -- all-dead case is the `wiped` branch immediately above, so the two
  -- together cover it. Left local rather than pushed into lib/ot6.lua: 24
  -- gate tests call H.battleLoadStarted() and none of them has a slot-0
  -- death, so widening the shared helper buys nothing and risks all of them.
  local anyC = false
  for i = 0, 3 do
    local hp = H.readWord(PHP + i*2)
    if hp ~= 0xffff and hp ~= 0 and hp < 10000 then anyC = true end
  end
  if not anyC then S.result = "torn_down" return true end
  local aliveM = 0
  for _, m in ipairs(mons) do
    if monsterAlive(m.slot) then aliveM = aliveM + 1 end
  end
  if aliveM == 0 then S.result = "won" return true end
  if S.frames >= BATTLE_FRAMES then S.result = "budget" return true end
  return false
end

-- ------------------------------------------------------------ report --
local B = 0
local function mline(k, v)
  H.log(string.format("[metrics] b=%d %s=%s", B, k, tostring(v)))
end
local function slotCsv(list, field)
  local parts = {}
  for _, e in ipairs(list) do
    parts[#parts + 1] = string.format("s%d:%d", e.slot, e[field])
  end
  return table.concat(parts, ",")
end
local function charCsv(fn)
  local parts = {}
  for _, c in ipairs(C) do
    parts[#parts + 1] = string.format("s%d:%s", c.slot, tostring(fn(c)))
  end
  return table.concat(parts, ",")
end

local function report()
  mline("policy", POLICY)
  mline("steps_paced", paceSteps)
  if voidReason then
    mline("void", voidReason)
    return
  end
  local sp = {}
  for _, m in ipairs(mons) do
    sp[#sp + 1] = string.format("%04X", H.readWord(0x57c0 + m.slot*2))
  end
  mline("formation", table.concat(sp, ","))
  mline("buff_hp", BUFF_HP)
  mline("buff_shields", BUFF_SHIELDS)
  mline("buff_class", BUFF_CLASS)
  mline("result", S.result)
  mline("frames", S.frames)
  mline("player_actions", S.playerActions)
  mline("enemy_actions", S.enemyActions)
  -- the window, not the event (see resetBattleState)
  mline("player_actions_broken", S.playerActionsBroken)
  mline("enemy_actions_broken", S.enemyActionsBroken)
  mline("counter_actions", S.counterActions)
  mline("player_dmg", S.playerDmg)
  mline("player_dmg_broken", S.playerDmgBroken)
  mline("enemy_dmg", S.enemyDmg)
  mline("party_heal", S.partyHeal)
  mline("monster_heal", S.monsterHeal)
  mline("boosts_spent", string.format("l1:%d,l2:%d,l3:%d",
    S.boosts[1], S.boosts[2], S.boosts[3]))
  mline("bp_regen", S.regens)
  mline("shield_chips", S.chips)
  mline("breaks", S.breaks)
  mline("first_break_frame", S.firstBreak)
  mline("break_uptime_frames", S.brokenUptime)
  mline("menu_nudges", S.nudges)
  mline("monster_hp_start", slotCsv(mons, "hp0"))
  mline("monster_dmg", slotCsv(mons, "dmg"))
  for _, m in ipairs(mons) do m.hp = H.readWord(MHP + m.slot*2) end
  mline("monster_hp_remaining", slotCsv(mons, "hp"))

  -- the fan-out
  mline("party_size", #C)
  mline("party", charCsv(function(c)
    return string.format("%02X:%s", c.cix, c.name) end))
  mline("char_actions", charCsv(function(c) return c.actions end))
  mline("char_dmg", charCsv(function(c) return c.dmg end))
  mline("char_dmg_broken", charCsv(function(c) return c.dmgBroken end))
  mline("char_chips", charCsv(function(c) return c.chips end))
  mline("char_breaks", charCsv(function(c) return c.breaks end))
  mline("char_boosts", charCsv(function(c)
    return string.format("%d/%d/%d", c.boosts[1], c.boosts[2], c.boosts[3]) end))
  mline("char_bp_spent", charCsv(function(c) return c.bpSpent end))
  mline("char_bp_regen", charCsv(function(c) return c.regens end))
  mline("char_bp_start", charCsv(function(c) return c.bp0 end))
  mline("char_bp_end", charCsv(function(c) return c.bp end))
  mline("char_dmg_taken", charCsv(function(c) return c.taken end))
  mline("char_hp_end", charCsv(function(c) return c.hp end))
  mline("char_hp_start", charCsv(function(c) return c.hp0 end))
  mline("char_mp_spent", charCsv(function(c) return c.mp0 - c.mp end))
  mline("char_plan", charCsv(function(c)
    local parts = {}
    for tag, n in pairs(c.plans) do parts[#parts + 1] = tag .. "*" .. n end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, "+") or "-"
  end))

  -- identity checks (see metrics_battle.lua for what each one proves)
  local aSum, dSum, cSum, bSum, tSum, wSum = 0, 0, 0, 0, 0, 0
  for _, c in ipairs(C) do
    aSum = aSum + c.actions
    dSum = dSum + c.dmg
    cSum = cSum + c.chips
    bSum = bSum + c.breaks
    tSum = tSum + c.taken
    wSum = wSum + c.bpWrites
  end
  -- bp_action_skew reads a steady -1 on a won fight and that is
  -- EXPECTED, not slack: the sampler's stop condition fires the frame the
  -- last monster dies, which is before the killing action reaches
  -- Ot6ActionEnd, so its bp write is never observed. Measured constant at
  -- -1 across 6/6 world-pool battles regardless of action count (1 or 2)
  -- and on battle2_doorstep. A skew that GROWS with actions would mean
  -- the dequeue pairing is wrong; a steady -1 means it is right.
  mline("actions_sum", aSum)
  mline("actions_residual", S.playerActions - aSum)
  mline("bp_action_skew", wSum - aSum)
  mline("dmg_sum", dSum)
  mline("monster_self_dmg", S.monsterSelfDmg)
  mline("unattributed_dmg", S.unattributedDmg)
  mline("dmg_residual",
    S.playerDmg - dSum - S.monsterSelfDmg - S.unattributedDmg)
  mline("chips_sum", cSum)
  mline("chips_residual", S.chips - cSum - S.unattributedChips)
  mline("breaks_sum", bSum)
  mline("breaks_residual", S.breaks - bSum - S.unattributedBreaks)
  mline("dmg_taken_residual", S.enemyDmg - tSum)
  mline("action_trace", table.concat(actTrace, ","))
end

-- ----------------------------------------------------- battle blocks --
assert(POLICIES[POLICY], "unknown POLICY: " .. tostring(POLICY))

-- seqStepList: plain sequential composition (H.seqStep is local to the
-- lib, so rebuild the trivial version here -- same as bal_mines.lua)
local function seqStepList(steps)
  return {
    i = 1,
    tick = function(self)
      while self.i <= #steps do
        local r = steps[self.i]:tick()
        if r == "frame" then return "frame" end
        self.i = self.i + 1
      end
      return "done"
    end,
  }
end

-- "the party is standing still, in control, on the map we expect" -- the
-- world and field halves ask different modules, so the settle predicate is
-- per-fixture the same way the pacer is.
local function calmField(n)
  local cnt = 0
  return function()
    local ok = (FX.mode == "world")
      and (H.worldHasControl() and H.worldAligned())
      or  (H.hasControl() and H.tileAligned()
           and (H.mapId() & 0x1ff) == FX.map)
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function paceWorld(k)
  -- Pace two world tiles until a battle starts loading. Never raises from
  -- the predicate: void reasons flow into the report instead.
  local battN, waited, lastX = 0, 0, nil
  return H.driveUntil(function()
    waited = waited + 1
    battN = H.battleLoadStarted() and battN + 1 or 0
    if battN >= 3 then H.setPad({}) return true end
    if not H.worldMode() then voidReason = "left_world" H.setPad({}) return true end
    if waited >= PACE_FRAMES then voidReason = "pace_timeout" H.setPad({}) return true end
    return false
  end, PACE_FRAMES + 600, {
    H.call(function()
      if not (H.worldHasControl() and H.worldAligned()) then H.setPad({}) return end
      local x = H.worldX()
      if lastX ~= nil and x ~= lastX then paceSteps = paceSteps + 1 end
      lastX = x
      H.setPad({ [(x >= FX.spawn) and "left" or "right"] = true })
    end),
    H.waitFrames(1),
  }, "encounter fires (b=" .. k .. ")")
end

-- The four presses and how to undo each, for the field lane picker.
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local LANE_ORDER = { "left", "right", "up", "down" }

local function paceField(k)
  -- bal_mines' field pacer, with the lane chosen LIVE instead of hardcoded.
  -- bal_mines could name (78,58)<->(77,58) because it owns one fixture;
  -- this driver is pointed at whatever stretch is being measured, and a
  -- fixture whose spawn tile has a wall to its left would otherwise pace
  -- zero steps and void every sample as a timeout while looking like an
  -- encounter-free map. H.canStep models the live z-level and the object
  -- map, so the first direction it allows is a lane the party can really
  -- walk; the party oscillates spawn <-> that neighbour.
  --
  -- A random encounter fires THROUGH an event script (EventScript_RandBattle,
  -- field/battle.asm), so eventRunning alone is normal here: pacing goes
  -- hands-off during any event and only voids if no battle follows within
  -- 600 frames.
  local battN, evHold, waited = 0, 0, 0
  local lane, lastXY = nil, nil
  return H.driveUntil(function()
    waited = waited + 1
    battN = H.battleLoadStarted() and battN + 1 or 0
    if battN >= 3 then H.setPad({}) return true end
    if H.eventRunning() or H.dialogWaiting() then
      evHold = evHold + 1
    elseif H.hasControl() then
      evHold = 0
    end
    if evHold >= 600 then voidReason = "event_no_battle" H.setPad({}) return true end
    if (H.mapId() & 0x1ff) ~= FX.map then
      voidReason = "left_map" H.setPad({}) return true
    end
    if waited >= PACE_FRAMES then voidReason = "pace_timeout" H.setPad({}) return true end
    return false
  end, PACE_FRAMES + 600, {
    H.call(function()
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      local x, y = H.fieldX(), H.fieldY()
      if lane == nil then
        -- FX.lane first when the fixture names one (an exit tile the
        -- passability model cannot see); otherwise scan.
        for _, m in ipairs(FX.lane and { FX.lane } or LANE_ORDER) do
          if H.canStep(x, y, m) then
            lane = { ax = x, ay = y, out = m, back = BACK[m] }
            break
          end
        end
        if lane == nil then
          voidReason = "walled_in" H.setPad({}) return
        end
        H.log(string.format("[metrics-ev] b=%d lane (%d,%d) %s/%s",
          k, x, y, lane.out, lane.back))
      end
      local xy = x * 1000 + y
      if lastXY ~= nil and xy ~= lastXY then paceSteps = paceSteps + 1 end
      lastXY = xy
      H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    end),
    H.waitFrames(1),
  }, "encounter fires (b=" .. k .. ")")
end

-- A talk-triggered boss ($0107 Dadaluma) is not a random encounter: the
-- party stands one tile north of the gentleman NPC and pressing A opens the
-- dialog that fires battle 69. This is gen_zozo4_dadaluma's own trigger,
-- reshaped into the pacer's driveUntil/voidReason contract: face FX.face,
-- press A, and A through whatever dialog pages until a battle loads. No
-- pacing, so a boss fixture on a random-encounter map never risks drawing a
-- stray trash fight first.
local function paceTalk(k)
  local battN, waited, ph = 0, 0, 0
  return H.driveUntil(function()
    waited = waited + 1
    battN = H.battleLoadStarted() and battN + 1 or 0
    if battN >= 3 then H.setPad({}) return true end
    if (H.mapId() & 0x1ff) ~= FX.map then
      voidReason = "left_map" H.setPad({}) return true
    end
    if waited >= PACE_FRAMES then voidReason = "talk_timeout" H.setPad({}) return true end
    return false
  end, PACE_FRAMES + 600, {
    H.call(function()
      ph = (ph + 1) % 24
      if H.battleLoadStarted() then H.setPad({}) return end
      if H.dialogWaiting() then H.setPad(ph % 4 < 2 and { "a" } or {}) return end
      if not H.hasControl() then H.setPad({}) return end
      if ph < 6 then H.setPad({ [FX.face or "down"] = true })
      elseif ph < 12 then H.setPad({ "a" })
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, "talk fires (b=" .. k .. ")")
end

local function paceStep(k)
  if FX.trigger == "talk" then return paceTalk(k) end
  return (FX.mode == "world") and paceWorld(k) or paceField(k)
end

local function battleBlock(k)
  return seqStepList({
    H.call(function() B = k resetBattleState() end),
    H.loadState(STATE),
    H.waitFrames(10),
    H.waitUntil(calmField(20), 1800, "field control (b=" .. k .. ")"),
    H.call(function()
      -- ROM_HPMUL/ROM_SHIELD are H.sym-derived table bases now, so the old
      -- "does this still read a knob byte" drift guard is redundant and gone.
      -- (The authoring arm below keeps its own guard: it pokes base+ROW_INDEX
      -- offsets, and a row can still move within a table.)
      -- the poke survives loadState: ROM is not savestate-backed
      if POKE_HP ~= nil then
        emu.write(ROM_HPMUL, POKE_HP, emu.memType.snesPrgRom)
        H.assertEq(H.readRomByte(ROM_HPMUL), POKE_HP, "hp band0 poked")
      end
      if POKE_SHIELD ~= nil then
        emu.write(ROM_SHIELD, POKE_SHIELD, emu.memType.snesPrgRom)
        H.assertEq(H.readRomByte(ROM_SHIELD), POKE_SHIELD, "resistance poked")
      end
      -- the authoring arm keeps a row-species guard before its destructive
      -- poke: the table BASE is H.sym-derived (can't be stale), but these
      -- addresses are base + a hardcoded ROW INDEX, and a row can move within
      -- its table. Guard on the SHIPPED value, so a re-run after the poke (the
      -- ROM image is not savestate-backed, so battle 2 sees battle 1's poke)
      -- is a no-op rather than a false alarm.
      if POKE_AUTHORING == "off" then
        for addr, want in pairs(AUTHORING_OK) do
          local seen = H.readRomWord(addr)
          if seen ~= want and seen ~= 0xffff and seen ~= 0x0fff then
            error(string.format(
              "authoring row drift: $%06X reads $%04X, want $%04X -- the "
              .. "ShieldTbl/ElemAddTbl base auto-derives, so a row moved "
              .. "within the table; bump its row index", addr, seen, want), 0)
          end
        end
        -- byte pair, not writeWord: emu.write is the call the two knobs
        -- above already use against snesPrgRom, and there is no
        -- H.writeRomWord in lib/ot6.lua to borrow.
        local function pokeRomWord(addr, v)
          emu.write(addr, v & 0xff, emu.memType.snesPrgRom)
          emu.write(addr + 1, (v >> 8) & 0xff, emu.memType.snesPrgRom)
          H.assertEq(H.readRomWord(addr), v,
            string.format("authoring poke landed at $%06X", addr))
        end
        pokeRomWord(ROM_ELEMADD_V3, 0xffff)   -- hide the six element rows
        for _, a in ipairs(ROM_SHIELDROWS_V3) do
          pokeRomWord(a, 0x0fff)              -- make each shield row inert
        end
      end
      mline("knob_hp", string.format("%02x", H.readRomByte(ROM_HPMUL)))
      mline("knob_shield", string.format("%02x", H.readRomByte(ROM_SHIELD)))
      mline("knob_authoring", string.format("%04x/%04x",
        H.readRomWord(ROM_ELEMADD_V3), H.readRomWord(ROM_BRAWLER_ROW)))
      mline("fixture", FIXTURE)
      -- cold danger counter + seeded rolls: battle k is the same battle in
      -- every policy arm (mines_pace.lua Measurement #4)
      H.writeWord(DANGER, 0)
      local sd = SEEDS[k] or {}
      if sd.fa1 then H.writeByte(0x1fa1, sd.fa1) end
      if sd.fa2 then H.writeByte(0x1fa2, sd.fa2) end
      mline("seed_1fa1", string.format("%02x", H.readByte(0x1fa1)))
      mline("seed_1fa2", string.format("%02x", H.readByte(0x1fa2)))
    end),
    paceStep(k),
    H.cond(function() return voidReason ~= nil end, {
      H.call(function() report() end),
    }, {
      H.waitUntilSoft(function() return H.battleActive() end, 900,
        "battle_active_b" .. k, 30),
      H.waitFrames(240 + 7 * (k - 1)),   -- settle + rng phase jitter
      H.call(function()
        for slot = 0, 3 do
          local hp = H.readWord(PHP + slot*2)
          if hp > 0 and hp ~= 0xffff then
            local rec = newChar(slot)
            C[#C + 1] = rec
            bySlot[slot] = rec
          end
        end
        for slot = 0, 5 do
          if monsterAlive(slot) then
            if BUFF_HP > 0 then H.writeWord(MHP + slot*2, BUFF_HP) end
            if BUFF_SHIELDS > 0 then
              H.writeByte(SHLD + slot*2, BUFF_SHIELDS)      -- current
              H.writeByte(SHLD + slot*2 + 1, BUFF_SHIELDS)  -- max (refill)
            end
            if BUFF_CLASS > 0 then
              -- monster half of $3e9c (chars at +0..+6, monsters at +8)
              H.writeByte(WKC + slot*2,
                H.readByte(WKC + slot*2) | BUFF_CLASS)
            end
            local hp = H.readWord(MHP + slot*2)
            mons[#mons + 1] = { slot = slot, hp = hp, hp0 = hp, dmg = 0 }
            mline("mon_detail", string.format(
              "s%d:sp%04X:hp%d:weak%02x:sh%d/%d", slot,
              H.readWord(0x57c0 + slot*2), hp,
              H.readByte(WEAK + slot*2),
              H.readByte(SHLD + slot*2), H.readByte(SHLD + slot*2 + 1)))
          end
        end
        for qi, q in ipairs(QUEUES) do qShadow[qi] = H.readByte(q.ptr) end
        -- seed the actor shadow from the action queue's last dequeue: an
        -- action can already be in flight 240 frames into the battle
        local last = (H.readByte(QUEUES[2].ptr) - 1) & 0xff
        local v = H.readByte(QUEUES[2].base + last)
        if (v & 0x80) == 0 then
          curActor = v
          curSlot = (v < 8) and (v // 2) or nil
        end
        resetEpisode()
        arm()
        for _, c in ipairs(C) do
          mline("member", string.format("s%d:%02X:%s:cmds%02X/%02X/%02X/%02X",
            c.slot, c.cix, c.name, c.cmds[0], c.cmds[1], c.cmds[2], c.cmds[3]))
        end
        H.log(string.format("[metrics-ev] b=%d armed frame=%d chars=%d mons=%d policy=%s",
          k, H.frame, #C, #mons, POLICY))
      end),
      H.driveUntil(function() return sample() end, BATTLE_FRAMES + 600, {
        H.call(function()
          local pad = pulse()
          if pad then H.setPad(pad) end
        end),
        H.waitFrames(6),
        H.call(function() H.setPad({}) end),
        H.waitFrames(24),
      }, "battle resolved (b=" .. k .. ")"),
      H.call(function()
        disarm()
        report()
      end),
    }),
  })
end

local blocks = {}
for k = 1, NBATTLES do blocks[#blocks + 1] = battleBlock(k) end
blocks[#blocks + 1] = H.call(function()
  H.log(string.format("[metrics] run_done policy=%s battles=%d buff_hp=%d",
    POLICY, NBATTLES, BUFF_HP))
end)

H.run({ maxFrames = FX.runFrames or 200000 }, blocks)
