-- metrics_battle: auto-battler balance probe. loads a doorstep state,
-- enters the fight, and PLAYS it with a swappable input policy while
-- recording what the balance work needs (docs/design/balance-metrics.md):
-- actions per side, damage split broken/unbroken, bp regen/spends by
-- level, shield chips, breaks, break uptime. no asserts -- the run
-- "passes" whenever the battle resolves or the budget ends; the product
-- is the report at the bottom of the log, one stat per line, greppable:
--   [ot6] [metrics] key=value
--
-- MULTI-ACTOR (2026-07-18). The v1 instrument assumed a SOLO party: the
-- policies asked "what does the character whose menu is open do" but had
-- one answer for everyone, and every stat above was a single scalar. The
-- Figaro->Kolts stretch is Terra + Locke + Edgar (+ Sabin at Vargas), so
-- both halves are now per-actor:
--  * POLICIES are asked per (slot, character): the policy sets the BOOST
--    discipline, the character's KIT (below) picks the action. Terra
--    casts Fire at a revealed fire-weakness, Locke Fights (and Steals to
--    probe), Edgar's Tools carry pierce/poison, Sabin Blitzes.
--  * every stat fans out per party slot: char_actions / char_dmg /
--    char_chips / char_breaks / char_boosts / char_bp_* / char_dmg_taken.
--    The aggregate keys keep their old meaning and old name, so logs and
--    bal_aggregate.py stay compatible; the fan-out is additive.
--
-- knobs are the locals right below: POLICY picks the player, STATE the
-- formation, ROUNDS caps recorded player actions (0 = play to the end),
-- SETTLE_EXTRA jitters the rng phase so one state x policy pair can
-- yield a distribution instead of a single deterministic point.
--
-- address notes (confirmed in-repo, not guessed):
--  * battle code runs with db=$7e (battle_main.asm BattleMain), so its
--    absolute stores surface at $7Exxxx for write callbacks; dp writes
--    surface at $0000xx (none watched here).
--  * entity tables are 2 bytes/entity, chars at +0..+6, monsters at
--    +8..+$12: cur hp $3bf4 (battle_main.asm:2934) puts monster slot i
--    at $3bfc+i*2 (the guards: $3c00/$3c02); ot6.asm's shield tables
--    $3e38/timer $3e88 put monster slots at $3e40/$3e90.
--  * a battle slot's CHARACTER index is $3ed9+slot*2 (battle_main.asm:
--    6218 "character index", :11902 "character number"); the character's
--    own data block is $1600+37c, name at +2, level at +8, the four
--    battle commands at +$16 (gen_arvis.lua's roster dump).
--  * executed actions: the battle loop dequeues entity offsets from
--    three queues (battle_main.asm @0092/@00a6/@0049): advance-wait
--    $3720 (start ptr $3a64), action $3820 ($3a66), counter $3920
--    ($3a68). ptrs are 8-bit (the loop runs shortai). sampling each
--    START ptr per frame and reading the bytes it walked past counts
--    what actually ran; $ff bytes are removed/cancelled entries (actor
--    died with actions queued) and don't count. offset < 8 = player,
--    and offset/2 is the party slot -- which is what makes the per-
--    character fan-out possible at all.
--
-- ATTRIBUTION, and what it can and cannot see:
--  * the battle loop executes exactly ONE dequeued entity's action at a
--    time (battle_main.asm BattleLoop @0049/@0092/@00a6 each dispatch and
--    return), so the most recently dequeued entity offset IS the actor
--    whose action is running. That shadow (`curActor`) is what credits
--    damage, chips and breaks to a character. This REPLACES v1's
--    victim-only attribution and, as a side effect, makes monster-on-
--    monster damage (muddle) visible instead of silently landing in
--    player_dmg: it is reported separately as monster_self_dmg.
--  * the shadow is FRAME-GRANULAR: the sampler walks the queue pointers
--    once per frame, so an event landing in the same frame as the
--    dequeue that began its action can be credited to the previous
--    actor. Actions run tens of frames, so the exposure is one frame per
--    action boundary; char_actions is cross-checked two independent ways
--    (dequeue pairs vs Ot6ActionEnd's per-actor bp write) and the
--    disagreement is reported as bp_action_skew, not hidden.
--
-- TODO (real gaps, deliberately not guessed around):
--  * exact per-hit attribution is still unavailable: ApplyDmg reads the
--    attacker off the STACK (`lda $02,s` -- battle_main.asm:2960), and
--    the only per-target attacker byte ($32e0,y, _c2362f "save previous
--    attacker" :8662) is a retaliation blacklist written on death, not
--    on every hit. $3406 ("currently acting character/monster" :133) is
--    NOT it either: ExecAction's `sec / ror $3406` (:194) marks it
--    invalid on entry and only @01d5 (:290) restores it for actions that
--    span loop iterations, so it reads negative across the damage
--    frames. Hence the dequeue shadow above.
--  * "immediate" actions ($340a, battle_main.asm @0033) bypass all
--    three queues (battle-start scripts, final attacks). rare in wob
--    trash; uncounted, and they also leave the shadow stale.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

-- ------------------------------------------------------------- knobs --
local POLICY = "boost3"            -- see POLICIES below
local STATES = {
  doorstep  = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua",
  doorstep2 = "/Users/mtklein/ot6/build/states/battle2_doorstep.mss.lua",
}
local STATE = STATES.doorstep2
local ROUNDS = 0                   -- player actions to record; 0 = to the end
local SETTLE_EXTRA = 0             -- extra pre-arm frames (rng phase jitter)
local METRICS_FRAMES = 20000       -- metrics-window frame budget
-- BUFF turns the demo doorstep (40-hp guards, no party-hittable
-- weakness -> break/boost never engage) into a MEASURABLE fixture:
-- inject a fire weakness and enough hp that the fight lasts long
-- enough for banking to pay off. this is a stand-in until real
-- post-magitek states exist; the delta between baseline and boost3
-- here is the first "how much juice" number.
local BUFF_HP   = 0                -- >0 = set every monster's hp to this
local BUFF_FIRE = false            -- true = make monsters fire-weak

-- --------------------------------------------------------- addresses --
local MENU  = 0x7bca               -- battle menu open flag
local ACTOR = 0x62ca               -- whose menu it is (char slot)
local PHP   = 0x3bf4               -- party cur hp, +slot*2
local PMP   = 0x3c08               -- party cur mp, +slot*2
local MHP   = 0x3bfc               -- monster cur hp, +slot*2
local BP    = 0x3e9c               -- char bp, +slot*2
local PEND  = 0x3e9d               -- char pending boost, +slot*2
local SHLD  = 0x3e40               -- monster cur shields, +slot*2 (odd = max)
local TIMER = 0x3e90               -- monster broken timer, +slot*2 (odd = revealed)
local RVEAL = 0x3e91               -- monster revealed elements, +slot*2
local WEAK  = 0x3be8               -- monster weak elements, +slot*2
local ALIVE = 0x3aa8               -- monster presence bit0, +slot*2
local MSTAT = 0x3eec               -- monster status-1, +slot*2 ($c2 = gone)
local CHARIX = 0x3ed9              -- battle slot -> character index, +slot*2
local CHARBLK = 0x1600             -- character data blocks, 37 bytes each
-- dequeue-side action counting (see header). `shadow` marks the queues
-- whose dequeue actually NAMES the running actor: $3820 dispatches
-- ExecAction and $3920 dispatches ExecRetal, both of which run an
-- attack. $3720 does NOT -- it dispatches _c22188 (`_gaugefull`,
-- battle_main.asm:5734), the atb-gauge-full handler that only calls
-- QueueAction and sets up a jump, never damage. Letting it move the
-- shadow was measurably wrong: on battle2_doorstep a Wedge gauge-fill
-- landed between Terra's action dequeue and Terra's beam, and Terra's
-- shield chip was credited to Wedge, who had taken no action at all.
local QUEUES = {
  { base = 0x3720, ptr = 0x3a64, counter = false, shadow = false },
  { base = 0x3820, ptr = 0x3a66, counter = false, shadow = true },
  { base = 0x3920, ptr = 0x3a68, counter = true,  shadow = true },
}                                  -- counters land in the per-side totals
                                   -- TOO; the counter_actions line is a
                                   -- subset, not a third bucket

local function bp(slot) return H.readByte(BP + slot*2) end
local function pend(slot) return H.readByte(PEND + slot*2) end
local function broken(slot) return H.readByte(TIMER + slot*2) > 0 end
local function monsterAlive(slot)
  -- the hud builder's own liveness criterion (visual_f2 idiom)
  return (H.readByte(ALIVE + slot*2) & 0x01) == 1
     and (H.readByte(MSTAT + slot*2) & 0xc2) == 0
end
-- canonical roster, by character index. The RAM name is the player's (or
-- the intro's: pre-Arvis Terra's name bytes are placeholder glyphs that
-- decode to nothing), so reports key on the index and only fall back to
-- RAM when the index is off-roster.
local ROSTER = {
  [0x00]="TERRA", [0x01]="LOCKE", [0x02]="CYAN",  [0x03]="SHADOW",
  [0x04]="EDGAR", [0x05]="SABIN", [0x06]="CELES", [0x07]="STRAGO",
  [0x08]="RELM",  [0x09]="SETZER",[0x0a]="MOG",   [0x0b]="GAU",
  [0x0c]="GOGO",  [0x0d]="UMARO", [0x0e]="WEDGE", [0x0f]="VICKS",
}
local function charName(cix)
  if ROSTER[cix] then return ROSTER[cix] end
  local s = ""
  for i = 0, 5 do
    local b = H.readByte(CHARBLK + 37*cix + 2 + i)
    if     b >= 0x80 and b <= 0x99 then s = s .. string.char(b - 0x80 + 65)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(b - 0x9a + 97)
    else break end
  end
  return s == "" and string.format("c%02X", cix) or s
end
-- The IN-BATTLE command list: $202E + slot*12 + i*3, four [cmd,cmd,
-- targeting] triples. It is indexed by BATTLE SLOT, not by character
-- index -- probed live on battle2_doorstep, where slot 1 (Wedge, char
-- $0E) reads Magitek/--/--/Item by slot and garbage by char index. It is
-- also the only correct source: a magitek-armor body's battle commands
-- are NOT its character block's (Terra's block says Fight/Morph/Magic/
-- Item, her armor says Magitek/--/Magic/Item), so the character block
-- would mis-describe every magitek-era fixture.
local CMDTBL = 0x202e
local function battleCmd(slot, i) return H.readByte(CMDTBL + slot*12 + i*3) end
local function hasCmd(rec, want)
  for i = 0, 3 do if rec.cmds[i] == want then return true end end
  return false
end

-- ------------------------------------------------------ menu driving --
-- The battle menu is driven by STATE, not by counting button presses.
-- $7BC2 is the battle menu state (btlgfx_main.asm:12536 UpdateMenuState
-- dispatches on it; ot6.asm:1279 and :2728 already read it), so the turn
-- machine below always knows which window is open and presses only in
-- the stable "select" states -- which is also what keeps input out of a
-- just-opening window, the wedge bal_mines.lua:123-127 works around with
-- timers.
local MSTATE = 0x7bc2
local ST = { root = 0x05, spell = 0x0e, tools = 0x30, magitek = 0x2a,
             item = 0x0a, blitz = 0x3d, target = 0x38 }

-- HOW A COMMAND IS SELECTED. The command window is a 1-column x 4-row
-- list whose cursor lives at $890F+slot (btlgfx_main.asm:18707/18897,
-- UP=dec DOWN=inc, auto-skipping disabled rows) -- so a cursor walk would
-- have to model which of the four rows are enabled for this actor. It is
-- both simpler and more robust to use battle_class.lua:603-607's proven
-- idiom: write the wanted command into ALL FOUR of the actor's command
-- cells, and whatever row the cursor rests on opens the right window
-- with one 'a'. The poke is per turn into battle scratch that battle
-- init rebuilds (InitCmdList, battle_main.asm:13719), so nothing leaks
-- between battles; the ORIGINAL list is read once at arm time and gates
-- what a kit may ask for, so this can never hand a character a command
-- they do not own. What it does mean: the instrument measures "this
-- character used this command", not "a human navigated to it" -- menu
-- travel is not a balance number.
--
-- Command ids: Fight $00, Item $01, Magic $02, Steal $05, Tools $09,
-- Blitz $0A, Magitek $1D (gen_arvis.lua's CMDNAME table).
local CMD = { fight = 0x00, item = 0x01, magic = 0x02, steal = 0x05,
              tools = 0x09, blitz = 0x0a, magitek = 0x1d }

local function pokeCmd(slot, cmd)
  for i = 0, 3 do H.writeByte(CMDTBL + slot*12 + i*3, cmd) end
end
local function restoreCmds(rec)
  for i = 0, 3 do H.writeByte(CMDTBL + rec.slot*12 + i*3, rec.cmds[i]) end
end

-- SUB-LIST CURSORS. Every battle list shares one movement routine
-- (GetCursorInput, btlgfx_main.asm:19534) over a per-slot (scroll, col,
-- row) triple, so a wanted entry is reached by WRITING that triple
-- rather than by pressing the d-pad toward it -- no wrap rules, no
-- blank-cell walking, no dependence on where the previous turn left the
-- cursor.
--   spell list  scroll $8913+slot, col $8917+slot, row $891B+slot;
--               2 columns x 4 visible rows of 27; entries live at
--               $2092 + SPELLBASE[slot] + i*4 with the spell id at +0 and
--               $FF for "not known" -- the array is fixed-slot and never
--               compacted (ValidateSpellList, battle_main.asm:14228), so
--               the wanted spell is found by scanning, not by arithmetic.
--   tools list  scroll $895F (always 0), col $8963+slot, row $8967+slot;
--               2 columns x 4 rows, entries PACKED at $4005 + i*3.
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

-- ------------------------------------------------------------- kits --
-- What a character DOES with a turn, independent of the boost discipline
-- the policy sets. An entry is { tag, cmd, pick = <cursor setter>, combo
-- = <buttons to feed a combo reader>, mp = <mp floor>, want = <gate> };
-- the first entry whose command the actor actually owns and whose gate
-- passes is taken, so a kit reads as a preference ladder and an actor
-- without the command falls through to the next line.
--
-- KITS[character index] = that ladder. Written for the whole
-- Figaro->Kolts party; a fixture only exercises the members it carries,
-- and the report's char_plan line says which lines actually fired.
local SPELL = { fire = 0x00, cure = 0x2d }
local TOOL  = { autocrossbow = 0xaa, bioblaster = 0xa4 }  -- item_name_en.json
local KITS = {
  -- TERRA: Fire is the party's elemental probe and its weakness nuke.
  [0x00] = { name = "TERRA",
    { tag = "fire", cmd = CMD.magic, mp = 4, want = "weak_fire",
      pick = function(slot) return magicCursor(slot, SPELL.fire) end },
    { tag = "probe_fire", cmd = CMD.magic, mp = 4, want = "probe_elem",
      pick = function(slot) return magicCursor(slot, SPELL.fire) end },
    { tag = "fight", cmd = CMD.fight },
    -- in magitek armor she has no Fight at all; the beam is the swing
    { tag = "tek", cmd = CMD.magitek },
  },
  -- LOCKE: a pierce Fight is his chip; Steal is his opening probe turn.
  [0x01] = { name = "LOCKE",
    { tag = "steal", cmd = CMD.steal, want = "probe_turn" },
    { tag = "fight", cmd = CMD.fight },
  },
  -- EDGAR: BioBlaster carries poison, AutoCrossbow is pierce AND
  -- multi-hit, so it chips per hit (weapon-classes.md "Multi-hit actions
  -- chip per hit"). UNEXERCISED: no fixture carries Edgar yet, so the
  -- tools-cursor path is written from the window shape the disassembly
  -- gives (btlgfx_main.asm:20607) and has never been driven.
  [0x04] = { name = "EDGAR",
    { tag = "bio", cmd = CMD.tools, want = "weak_poison",
      pick = function(slot) return toolsCursor(slot, TOOL.bioblaster) end },
    { tag = "xbow", cmd = CMD.tools,
      pick = function(slot) return toolsCursor(slot, TOOL.autocrossbow) end },
    { tag = "fight", cmd = CMD.fight },
  },
  -- SABIN: Blitz has no list and no cursor -- state $3d is a button-COMBO
  -- reader (btlgfx_main.asm:17219), so the entry feeds the combo instead
  -- of pointing at a cell. Pummel is left,right. UNEXERCISED for the same
  -- reason as Edgar; flagged, not assumed.
  [0x05] = { name = "SABIN",
    { tag = "blitz", cmd = CMD.blitz, combo = { "left", "right" } },
    { tag = "fight", cmd = CMD.fight },
  },
  -- Magitek-era bodies: MagiTek's list opens on Fire Beam, which is the
  -- action we want, so no cursor write is needed.
  [0x0e] = { name = "WEDGE", { tag = "tek", cmd = CMD.magitek },
                             { tag = "fight", cmd = CMD.fight } },
  [0x0f] = { name = "VICKS", { tag = "tek", cmd = CMD.magitek },
                             { tag = "fight", cmd = CMD.fight } },
}
local FALLBACK_KIT = { name = "?", { tag = "fight", cmd = CMD.fight } }

local function anyRevealed(mask)
  for slot = 0, 5 do
    if monsterAlive(slot) and (H.readByte(RVEAL + slot*2) & mask) ~= 0 then
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------- policies --
-- a policy is a function(slot) -> boost target for THIS actor's turn, or
-- nil for "no boost". The kit picks the action; the policy picks how much
-- bp rides on it. Both are consulted per actor as their menu opens, so a
-- party plays three different characters under one named policy.
local S                            -- accumulators (reset in resetRun)
local C = {}                       -- per-slot character records
local bySlot = {}                  -- slot -> C entry

local POLICIES = {}
-- baseline: confirm through every menu unboosted. vanilla-speed play;
-- the denominator for every boost comparison.
POLICIES.baseline = { boost = function() return 0 end, probe = false }
-- boost3: bank bp on plain turns, and the moment 3 are spendable,
-- commit all 3 (fold to tier 3 / x8) and fire into the best-known
-- weakness. the always-boost-3 numerator: maximum per-action throughput.
POLICIES.boost3 = { boost = function(slot)
  return bp(slot) >= 3 and 3 or 0
end, probe = true }
-- greedy: spend whatever is there, every turn (in practice a stream of
-- 1-boosts after the opener). the "player who never banks" datapoint.
POLICIES.greedy = { boost = function(slot)
  return bp(slot) >= 1 and math.min(bp(slot), 3) or 0
end, probe = true }
-- badboost (Measurement #5's negative control): bank to 3, then dump the
-- boost into a plain Fight -- i.e. deliberately into a shielded, unweak
-- target, the misplay the resistance constant is tuned to punish. Never
-- probes, never casts: `probe = false` forces the kit's Fight fallback.
POLICIES.badboost = { boost = function(slot)
  return bp(slot) >= 3 and 3 or 0
end, probe = false, force = "fight" }

-- ------------------------------------------------------ accumulators --
local mons = {}                    -- tracked monster slots, discovered at arm
local qShadow = {}                 -- per-queue start-ptr shadows
local refs = {}                    -- memory-callback handles
local shSeen, tmSeen = {}, {}      -- write-callback shadows by monster slot
local curActor = -1                -- entity offset of the running action
local curSlot = nil                -- party slot if curActor is a character
local pendChips, pendBreaks = {}, {}  -- write events awaiting attribution

local function resetRun()
  S = {
    t0 = 0,                          -- H.frame at arm; frame stats relative
    frames = 0,
    playerActions = 0, enemyActions = 0, counterActions = 0,
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
  mons, C, bySlot, qShadow = {}, {}, {}, {}
  curActor, curSlot = -1, nil
  pendChips, pendBreaks = {}, {}
end

-- one per-slot record; every per-character stat lives here so the report
-- is a single walk and the identity checks are one loop.
local function newChar(slot)
  local cix = H.readByte(CHARIX + slot*2)
  local kit = KITS[cix] or FALLBACK_KIT
  -- the UNPOKED battle command list: read once, before any turn rewrites
  -- it, and never re-read. It is both the gate on what the kit may ask
  -- for and the value restored at teardown.
  local cmds = {}
  for i = 0, 3 do cmds[i] = battleCmd(slot, i) end
  return {
    slot = slot, cix = cix, name = charName(cix), kit = kit, cmds = cmds,
    hp = H.readWord(PHP + slot*2), hp0 = H.readWord(PHP + slot*2),
    mp = H.readWord(PMP + slot*2), mp0 = H.readWord(PMP + slot*2),
    bp = bp(slot), bp0 = bp(slot),
    dequeues = 0, actions = 0, bpWrites = 0,
    dmg = 0, dmgBroken = 0, taken = 0, healed = 0,
    chips = 0, breaks = 0,
    boosts = { 0, 0, 0 }, bpSpent = 0, regens = 0,
    plans = {},                    -- tag -> count, what the kit actually did
  }
end

-- ------------------------------------------------- turn state machine --
-- One "episode" per open menu. The driver decides (boost target, kit
-- entry) once when the menu opens, then reacts to $7BC2: raise pending
-- with R at the root, open the poked command with A, place the sub-list
-- cursor by writing it, confirm, confirm the target. Every press is
-- gated on a stable select state, so an input can never land in a
-- window that is still opening -- the wedge bal_mines.lua:123-127 has to
-- dodge with timers. `nudge` is the only fallback left: if a state
-- persists far longer than a menu ever should, back out with B and
-- replan.
local ep = { slot = nil, entry = nil, want = 0, placed = false,
             comboIx = 1, pulses = 0 }

local function resetEpisode()
  ep.slot, ep.entry, ep.want, ep.placed = nil, nil, 0, false
  ep.comboIx, ep.pulses = 1, 0
end

-- is this kit entry playable for this actor, under this policy, now?
local function entryOk(rec, entry, pol)
  -- a policy that forces one tag (badboost) may only take that tag or
  -- the Fight fallback -- it must never wander into a weakness
  if pol.force and entry.tag ~= pol.force and entry.tag ~= "fight" then
    return false
  end
  if not hasCmd(rec, entry.cmd) then return false end
  if entry.mp and H.readWord(PMP + rec.slot*2) < entry.mp then return false end
  if entry.want == "weak_fire" then return pol.probe and anyRevealed(0x01) end
  if entry.want == "weak_poison" then return pol.probe and anyRevealed(0x20) end
  if entry.want == "probe_elem" then
    -- the OTHER half of a weakness rung, and the half a first draft
    -- forgot: an elemental weakness is only REVEALED by hitting it, so a
    -- kit that casts Fire "once fire is revealed" never casts Fire at
    -- all. Measured: 6/6 world-pool fights with a fire-weak monster and
    -- Terra never cast. So spend an early turn on the element while the
    -- board is still unread -- bal_mines.lua's probe1 rotation, per
    -- character.
    return pol.probe and not anyRevealed(0xff) and rec.actions == 0
  end
  if entry.want == "probe_turn" then
    -- a probe turn is a cheap information turn: take it only while
    -- nothing is revealed yet, and only on the opening turn (bp and the
    -- turns after it are for damage)
    return pol.probe and not anyRevealed(0xff) and rec.actions == 0
  end
  return true
end

-- pick the kit entry this actor uses this turn and poke its command into
-- every cell of the actor's command window
local function chooseAction(rec, pol)
  local pick
  for _, entry in ipairs(rec.kit) do
    if entryOk(rec, entry, pol) then pick = entry break end
  end
  if pick == nil then
    -- an actor whose kit ladder is entirely unavailable (a magitek body
    -- has no Fight at all): take whatever sits in its first real cell
    pick = { tag = "default", cmd = rec.cmds[0] }
  end
  pokeCmd(rec.slot, pick.cmd)
  return pick
end

-- the per-pulse driver: a button list for this ~30-frame pulse, or nil
-- to idle. R raises pending while a battle menu is open (ot6.asm:2575).
local function pulse()
  if H.readByte(MENU) == 0 then
    if ep.slot ~= nil then resetEpisode() end
    return nil
  end
  local slot = H.readByte(ACTOR)
  local rec = bySlot[slot]
  if rec == nil then return { "a" } end          -- unknown actor: don't wedge
  if ep.slot ~= slot then
    resetEpisode()
    ep.slot = slot
  end
  ep.pulses = ep.pulses + 1
  if ep.entry == nil then
    ep.want = POLICIES[POLICY].boost(slot)
    ep.entry = chooseAction(rec, POLICIES[POLICY])
    rec.plans[ep.entry.tag] = (rec.plans[ep.entry.tag] or 0) + 1
  end
  -- watchdog: a turn that will not commit gets backed out and replanned
  if ep.pulses > 40 then
    ep.pulses, ep.placed, ep.entry = 0, false, nil
    S.nudges = S.nudges + 1
    return { "b" }
  end
  local st = H.readByte(MSTATE)
  if st == ST.root then
    if pend(slot) < ep.want and pend(slot) < bp(slot) then return { "r" } end
    return { "a" }                     -- open the poked command
  end
  if st == ST.spell or st == ST.tools then
    -- place the cursor once, idle a pulse so the list redraws under it,
    -- then confirm. An entry with no `pick` takes whatever cell the
    -- cursor already holds (magitek's Fire Beam default).
    if not ep.placed then
      ep.placed = true
      if ep.entry.pick then ep.entry.pick(slot) end
      return nil
    end
    return { "a" }
  end
  if st == ST.magitek or st == ST.item then return { "a" } end
  if st == ST.blitz then
    local combo = ep.entry.combo or {}
    local b = combo[ep.comboIx]
    ep.comboIx = ep.comboIx + 1
    return b and { b } or { "a" }
  end
  if st == ST.target then return { "a" } end
  return nil                            -- transient open/close: hands off
end

-- -------------------------------------------------- event watchers --
-- chips and breaks are WRITE events, not per-frame states: a boosted
-- multi-hit can chip more than once between frames, and a break's
-- 0 -> OT6_BREAK_TICKS store is the only unambiguous "break happened"
-- signal (per-frame timer>0 also sees mid-window decrements).
--
-- The callbacks do NOT attribute; they only QUEUE. A write callback
-- fires the instant the store executes, mid-frame, whereas the sampler
-- reads the dequeue pointers at the next frame boundary -- so a chip
-- landing in the same frame as the dequeue that began its action would
-- see a stale shadow. Measured, not theorised: on battle2_doorstep that
-- lost Terra's opening chip to "unattributed" every run while her damage
-- attributed correctly one frame later. Queuing the event and draining it
-- in the sampler AFTER the queue walk puts both on the same shadow. The
-- callback body stays a table insert -- no emu API, no logging, so the
-- lib's callback-logging crash suspicion is not provoked.
local function arm()
  S.t0 = H.frame
  for i = 0, 5 do
    shSeen[i] = H.readByte(SHLD + i*2)
    tmSeen[i] = H.readByte(TIMER + i*2)
  end
  -- ot6.asm Ot6Chip: `dec a / sta $3e38,y` -- one absolute store per
  -- chip, value = new count; recovery restores UP (never a chip).
  refs[1] = emu.addMemoryCallback(function(addr, value)
    local off = addr - (0x7e0000 + SHLD)
    if off % 2 ~= 0 then return end          -- odd byte = max shields
    local slot = off // 2
    local prev = shSeen[slot]
    shSeen[slot] = value
    if value < prev then
      S.chips = S.chips + (prev - value)
      pendChips[#pendChips + 1] = prev - value
    end
  end, emu.callbackType.write, 0x7e0000 + SHLD, 0x7e0000 + SHLD + 11)
  -- ot6.asm Ot6Chip: `sta $3e88,y` with OT6_BREAK_TICKS on the 0-shield
  -- hit; a 0 -> nonzero write is a break, everything else is the tick.
  refs[2] = emu.addMemoryCallback(function(addr, value)
    local off = addr - (0x7e0000 + TIMER)
    if off % 2 ~= 0 then return end          -- odd byte = revealed mask
    local slot = off // 2
    local prev = tmSeen[slot]
    tmSeen[slot] = value
    if prev == 0 and value > 0 then
      -- pure accumulation only: printing from inside a memory callback
      -- is unproven here (the lib flags callback logging as a crash
      -- suspect); break_frames in the report carries the same info
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
-- runs as the metrics drive's predicate, so it fires EVERY frame while
-- the policy plays. hp and bp move at most once per entity per frame
-- (one store per action-end / damage-apply), so frame deltas lose
-- nothing there; the sampler also walks the dequeue pointers and calls
-- the stop conditions.
--
-- ORDER MATTERS: the queue walk runs FIRST so an action dequeued last
-- frame owns the damage that landed after it, and only then are the hp
-- deltas read. That is what makes curActor the right actor for the
-- deltas being attributed in the same pass.
local function sample()
  S.frames = H.frame - S.t0
  for qi, q in ipairs(QUEUES) do
    local cur = H.readByte(q.ptr)
    while qShadow[qi] ~= cur do
      local v = H.readByte(q.base + qShadow[qi])
      if (v & 0x80) == 0 then
        -- the executing entity: one action runs at a time, so the last
        -- ACTION-dispatching dequeue names the actor until the next one
        -- (header note; the advance-wait queue is deliberately not one)
        if q.shadow then
          curActor = v
          curSlot = (v < 8) and (v // 2) or nil
        end
        -- each real action passes through TWO queues (advance-wait +
        -- action), so raw dequeues run exactly 2x real actions.
        -- player_actions/enemy_actions emit REAL actions: every second
        -- dequeue of a side credits one. counter_actions stays a raw
        -- counter-queue dequeue tally (subset diagnostics).
        if q.counter then S.counterActions = S.counterActions + 1 end
        if v < 8 then
          S.playerDequeues = S.playerDequeues + 1
          if S.playerDequeues % 2 == 0 then
            S.playerActions = S.playerActions + 1
          end
          -- the same every-2nd rule PER SLOT: each actor contributes its
          -- own advance-wait + action pair, so the per-slot counters sum
          -- to player_actions (asserted as actions_sum in the report)
          local rec = bySlot[v // 2]
          if rec then
            rec.dequeues = rec.dequeues + 1
            if rec.dequeues % 2 == 0 then rec.actions = rec.actions + 1 end
          end
        else
          S.enemyDequeues = S.enemyDequeues + 1
          if S.enemyDequeues % 2 == 0 then
            S.enemyActions = S.enemyActions + 1
          end
        end
      end
      qShadow[qi] = (qShadow[qi] + 1) & 0xff
    end
  end
  -- drain last frame's chip/break events onto the now-current shadow
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
  local anyBroken = false
  for _, m in ipairs(mons) do
    if broken(m.slot) then anyBroken = true end
    local hp = H.readWord(MHP + m.slot*2)
    if hp < m.hp then
      local d = m.hp - hp                    -- effective damage: hp clamps
      S.playerDmg = S.playerDmg + d          -- at 0, which is what ttk feels
      m.dmg = m.dmg + d
      if broken(m.slot) then                 -- the game's own x2 criterion
        S.playerDmgBroken = S.playerDmgBroken + d
      end
      -- fan-out by the acting entity, and keep the leftovers honest
      local rec = curSlot and bySlot[curSlot]
      if rec then
        rec.dmg = rec.dmg + d
        if broken(m.slot) then rec.dmgBroken = rec.dmgBroken + d end
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
    -- damage TAKEN needs no shadow: the victim is the slot being read
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
      S.regens = S.regens + (b - c.bp)       -- unboosted action-end: +1
      c.regens = c.regens + (b - c.bp)
      c.bpWrites = c.bpWrites + 1
    elseif b < c.bp then
      local lvl = c.bp - b                   -- Ot6ActionEnd consume: -pending
      if lvl >= 1 and lvl <= 3 then
        S.boosts[lvl] = S.boosts[lvl] + 1
        c.boosts[lvl] = c.boosts[lvl] + 1
      end
      c.bpSpent = c.bpSpent + lvl
      c.bpWrites = c.bpWrites + 1
    end
    c.bp = b
  end
  -- stop conditions, checked after the frame's bookkeeping
  if not H.battleLoadStarted() then S.result = "torn_down" return true end
  local aliveM = 0
  for _, m in ipairs(mons) do
    if monsterAlive(m.slot) then aliveM = aliveM + 1 end
  end
  if aliveM == 0 then S.result = "won" return true end
  local aliveC = 0
  for _, c in ipairs(C) do if c.hp > 0 then aliveC = aliveC + 1 end end
  if aliveC == 0 then S.result = "wiped" return true end
  if ROUNDS > 0 and S.playerActions >= ROUNDS then
    S.result = "rounds" return true
  end
  if S.frames >= METRICS_FRAMES then S.result = "budget" return true end
  return false
end

-- ------------------------------------------------------------ report --
local function mline(k, v) H.log("[metrics] " .. k .. "=" .. tostring(v)) end
local function slotCsv(list, field)
  local parts = {}
  for _, e in ipairs(list) do
    parts[#parts + 1] = string.format("s%d:%d", e.slot, e[field])
  end
  return table.concat(parts, ",")
end
-- per-character CSV: same `sN:` shape as the monster lines, so one
-- parser rule covers both (bal_aggregate.py `slotcsv`)
local function charCsv(fn)
  local parts = {}
  for _, c in ipairs(C) do
    parts[#parts + 1] = string.format("s%d:%s", c.slot, tostring(fn(c)))
  end
  return table.concat(parts, ",")
end
local function report()
  mline("policy", POLICY)
  mline("state", STATE:match("[^/]+$"))
  mline("rounds_cfg", ROUNDS)
  mline("jitter_cfg", SETTLE_EXTRA)
  mline("result", S.result)
  mline("frames", S.frames)
  mline("player_actions", S.playerActions)
  mline("enemy_actions", S.enemyActions)
  mline("counter_actions", S.counterActions)
  mline("player_dmg", S.playerDmg)
  mline("player_dmg_broken", S.playerDmgBroken)
  mline("player_dmg_unbroken", S.playerDmg - S.playerDmgBroken)
  mline("enemy_dmg", S.enemyDmg)
  mline("party_heal", S.partyHeal)
  mline("monster_heal", S.monsterHeal)
  mline("boosts_spent", string.format("l1:%d,l2:%d,l3:%d",
    S.boosts[1], S.boosts[2], S.boosts[3]))
  mline("bp_regen", S.regens)
  mline("shield_chips", S.chips)
  mline("breaks", S.breaks)
  mline("first_break_frame", S.firstBreak)
  mline("break_frames", table.concat(S.breakFrames, ","))
  mline("break_uptime_frames", S.brokenUptime)
  mline("menu_nudges", S.nudges)   -- watchdog backouts; >0 = a menu path stalled
  mline("monster_hp_start", slotCsv(mons, "hp0"))
  mline("monster_dmg", slotCsv(mons, "dmg"))
  -- re-read at report time: the winning hit may land the same frame the
  -- liveness flip stops the sampler
  for _, m in ipairs(mons) do m.hp = H.readWord(MHP + m.slot*2) end
  mline("monster_hp_remaining", slotCsv(mons, "hp"))

  -- ----------------------------------------------------- the fan-out --
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
  -- start/end bp explain bp_action_skew: Ot6ActionEnd's regen branch is
  -- `cmp #$05 / bcs done` (ot6.asm:1552), so an actor already at the cap
  -- ends its action with NO bp write and the cross-check under-counts
  mline("char_bp_start", charCsv(function(c) return c.bp0 end))
  mline("char_bp_end", charCsv(function(c) return c.bp end))
  mline("char_dmg_taken", charCsv(function(c) return c.taken end))
  mline("char_hp_end", charCsv(function(c) return c.hp end))
  mline("char_mp_spent", charCsv(function(c) return c.mp0 - c.mp end))
  mline("char_plan", charCsv(function(c)
    local parts = {}
    for tag, n in pairs(c.plans) do parts[#parts+1] = tag .. "*" .. n end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, "+") or "-"
  end))

  -- ------------------------------------------------ identity checks --
  -- the numbers must close, and the report says so rather than the
  -- reader having to add them up. `dmg_residual` is player_dmg minus
  -- everything attributed; `bp_action_skew` is the independent
  -- cross-check on char_actions (Ot6ActionEnd writes bp once per
  -- character action -- ot6.asm:1529 -- except when bp is already
  -- capped at 5, so a nonzero skew is expected late in long fights and
  -- a LARGE one means the dequeue pairing is wrong).
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
end

-- --------------------------------------------------------------- run --
assert(POLICIES[POLICY], "unknown POLICY: " .. tostring(POLICY))
resetRun()
H.run({ maxFrames = METRICS_FRAMES + 12000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  -- battle-load idiom, verbatim from battle_boost
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  -- input during the first window-open animation wedges the battle menu
  H.waitFrames(240),
  H.waitFrames(SETTLE_EXTRA),      -- 0 = no jitter, completes same frame
  H.call(function()
    -- discover who's actually in this formation, then start the clock
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
        -- optional fixture buff, applied BEFORE the hp snapshot so the
        -- dmg accounting starts from the buffed value ($3be0 = weak
        -- elements, low byte fire; $3bec/$3bee mirror for the 2-guard
        -- formation, per battle_break.lua)
        if BUFF_FIRE then
          H.writeByte(0x3be0 + slot*2, H.readByte(0x3be0 + slot*2) | 0x01)
        end
        if BUFF_HP > 0 then H.writeWord(MHP + slot*2, BUFF_HP) end
        local hp = H.readWord(MHP + slot*2)
        mons[#mons + 1] = { slot = slot, hp = hp, hp0 = hp, dmg = 0 }
        -- what the fixture actually was, so a report is readable without
        -- re-deriving the formation from the state
        H.log(string.format(
          "[metrics-ev] mon s%d sp%04X hp%d weak%02X shields%d/%d",
          slot, H.readWord(0x57c0 + slot*2), hp, H.readByte(WEAK + slot*2),
          H.readByte(SHLD + slot*2), H.readByte(SHLD + slot*2 + 1)))
      end
    end
    for qi, q in ipairs(QUEUES) do qShadow[qi] = H.readByte(q.ptr) end
    -- seed the actor shadow from the action queue's LAST dequeued entry.
    -- Arming happens 240 frames into the battle, so an action can already
    -- be in flight; without this its damage and chips land in the
    -- unattributed buckets (measured: 1 of battle2_doorstep's 2 chips).
    local last = (H.readByte(QUEUES[2].ptr) - 1) & 0xff
    local v = H.readByte(QUEUES[2].base + last)
    if (v & 0x80) == 0 then
      curActor = v
      curSlot = (v < 8) and (v // 2) or nil
    end
    resetEpisode()
    arm()
    for _, c in ipairs(C) do
      H.log(string.format("[metrics-ev] slot=%d char=%02X %s kit=%s cmds=%02X/%02X/%02X/%02X",
        c.slot, c.cix, c.name, c.kit.name,
        c.cmds[0], c.cmds[1], c.cmds[2], c.cmds[3]))
    end
    H.log(string.format("[metrics-ev] armed frame=%d chars=%d mons=%d policy=%s",
      H.frame, #C, #mons, POLICY))
  end),
  -- the metrics loop: sampler every frame, one policy pulse per ~30.
  -- sample() enforces its own budget (result=budget), so the driveUntil
  -- cap only exists to satisfy the harness and never wins.
  H.driveUntil(function() return sample() end, METRICS_FRAMES + 600, {
    H.call(function()
      local pad = pulse()
      if pad then H.setPad(pad) end
    end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "battle resolved"),
  H.call(function()
    disarm()
    for _, c in ipairs(C) do restoreCmds(c) end
    report()
    H.screenshot("metrics_end")
  end),
})
