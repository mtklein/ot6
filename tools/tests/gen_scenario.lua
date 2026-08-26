-- gen_scenario.lua -- from lete_river.mss (map 113, one tile off the raft)
-- down the Lete River, through Ultros, to the three-way scenario split.
-- Generates one state:
--   scenario_hub.mss  map 9, party = SCENARIO_MOG alone, first controllable
--                     frame after Mog's "Choose a scenario…kupo!".  This is the
--                     entry point of the whole v0.3 arc, and the fixture the
--                     three scenario chains branch from.

-- The river loops.
-- The second steering prompt's option 0 is an infinite loop, and it is
-- vanilla behavior.  This is the most important fact in this file.

--   _cb07f2:  dlg $016E  "Hey, which way?  0: (Up)   1: (Left)"
--             choice _cb07fc, _cb0840          (event_main.asm:39152-39158)

-- Option 0 (_cb07fc, :39159) rides a loop of the river and ends
-- `if_switch $0176=0, _cb07f2` (:39197), which returns to the same prompt.
-- Option 1 (_cb0840, :39199) is the only way downstream.  This is the famous
-- unattended-grind spot of vanilla FF6 (memory cursor on, Banon healing,
-- return to an overlevelled party).  It is intentional, CONTRIBUTING.md's
-- "vanilla's bugs stay" covers it, and it is not to be fixed.

-- But it is a trap for a fixture, and a nasty one: advanceStory's blanket
-- A-press always takes option 0, so a naive drive down this river never
-- terminates.  It burns its whole frame budget and dies with a timeout that
-- reads like a navigation failure rather than a wrong menu pick.  So this
-- script never A-mashes a prompt.  Every `choice` on the route is answered
-- explicitly, by steering the multiple-choice cursor to a named option and
-- only then confirming, and each is logged so a future failure says which
-- fork it was at.  The three, in the order they arrive:

--   1. _cb059f  dlg $0167 "Hop aboard the raft?  0: Yes  1: No"      -> 0
--                 choice _cb05f0, EventReturn            (:38836-38841)
--   2. _cb0657  dlg $016A "Which way? 0:(Straight) 1:(Left) 2:(Right)" -> 0
--                 choice _cb0686, _cb06f7, _cb075c       (:38915-38921)
--      (all three converge, each ending `load_map 114, {13,36}`, so this
--      fork is safe either way; 0 is taken because it is shortest, and
--      "safe" was worth verifying rather than assuming)
--   3. _cb07f2  dlg $016E "Hey, which way?  0:(Up)  1:(Left)"        -> 1
--                 choice _cb07fc, _cb0840                (:39152-39158)
--      ^^^ the loop.  Option 0 here is the reason this file steers.

-- How the cursor works (src/field/text.asm:368-425, transcribed):
--   $056F  number of options; >= 2 means a multiple choice is live, and the
--          engine zeroes it the moment A confirms (:425)
--   $056E  current selection, 0-based
--   $056D  "selection is changing" latch, set when a direction moves the
--          cursor, cleared only on a frame with NO direction held (:380)
-- That latch is why the steering presses are edge presses (4 on / 4 off)
-- like every other input in this suite: a held DOWN moves the cursor one
-- row and no further.  DOWN/RIGHT increment (and stop at $056F), UP/LEFT
-- decrement (and stop at 0).

-- Two ways to read $056F wrong, both of which cost a run here:
--   * It is meaningless during a battle.  It is field dialog RAM and the
--     battle module scribbles it; a first cut tested it unconditionally and
--     announced a phantom "choice #2" in the middle of the ride's second
--     forced fight.  The handler only looks while no battle is up.
--   * It is built up as the text types out.  text.asm:684 calls it "max
--     choice found so far"; it counts special letter $15 indicators as
--     they are drawn.  Sampling it the instant it first reads >= 2 caught
--     fork 1 mid-render and reported 2 options for a 3-option prompt (the
--     screenshot showed a half-drawn box: "Which way? / (Straight)" and
--     nothing else yet).  So nothing is read or asserted until
--     H.dialogWaiting() ($BA=1 and $D3=1, the engine waiting for a
--     keypress), which is the only moment $056F is final.

-- The ride itself.
-- It is not a vehicle mode.  The brief that scoped this work expected a
-- third engine mode beside field and world (`set_script_mode` / `vehicle`
-- / `move_vehicle`).  It is not that.  The raft is an ordinary field map
-- (113, then 114) with the party under event control for most of it:
-- _cb05f0 does `player_ctrl_off` (:38843) and every inch of the river is
-- `obj_script SLOT_1, ASYNC { move ... }` followed by `wait_obj SLOT_1`.
-- The only `vehicle` opcodes involved are cosmetic: _cb050f (:38774) sets
-- each SLOT's sprite to {RAFT, SHOW_RIDER} and _cb04aa clears it.  And
-- `set_script_mode WORLD` appears only where the river spills onto the
-- overworld, a branch this route does not take.  So the harness needed no
-- new engine model: the ride is "answer the prompts, survive the battles,
-- and walk the two handoffs below".

-- $01B0-$01B7 are not story switches.  Switch id N lives at bit N&7 of
-- $1E80+(N>>3), so $01B0..$01B7 alias the byte $1EB6, and $1EB6 is the
-- field engine's own control-flags byte.  UpdateCtrlFlags (field/event.asm
-- :5415-5432) writes it every frame:
--     lda $087f,y / tax / lda $1eb6 / and #$f0 / ora f:BitOrTbl,x
-- i.e. bits 0-3 are the party's facing direction, one-hot, in the engine's
-- own 0=up 1=right 2=down 3=left encoding (BitOrTbl, :5523); bit4 is "A is
-- held"; bit5 is the once-per-tile event latch player.asm:529 clears on
-- every step.  So, read properly:
--     $01B0 = facing UP      $01B2 = facing DOWN     $01B4 = A held
--     $01B1 = facing RIGHT   $01B3 = facing LEFT     $01B5 = tile-event latch
-- `if_switch $01B2=0, EventReturn` means "unless the party is facing DOWN".
-- Hence the handoffs below are a plain held DOWN, which both walks the
-- party onto the trigger and leaves it facing the right way, rather than a
-- navTo, whose last step BFS is free to make sideways.

-- The same reading retro-explains three things elsewhere in the story that
-- had looked arbitrary: _caf79c picks Banon's approach animation off
-- $01B0/$01B1/$01B2 (which way you walked up to him), _caf68a/_caf6f0/
-- _caf717 pick escort variants the same way, and the Returner Hideout's
-- scrap-of-paper trigger _cb002b needs $01B4 and $01B2, so it is an examine
-- (press A facing down), not a step, which is why gen_banon never tripped it.
-- And _cb059f's own `if_switch $01B5=1, EventReturn` / `switch $01B5=1` is
-- just the standard once-per-tile latch, not a story flag.

-- Ultros: `battle 103, RIVER` at _cb08db (:39301), won with real input, the
-- first real Ultros in this chain's history.  He has an authored shield
-- row: Ot6ShieldTbl carries $012c (MONSTER::ULTROS_RIVER) at 5 shields,
-- OT6_SLASH|OT6_PIERCE, "ultros 1: the row he keeps all game"
-- (ff6/src/battle/ot6.asm:3008-3009) -- and the design brief for the fight
-- (bosses-wob.md #4) names the loss condition this generator now actually
-- risks:  Tentacle slams Banon.  The winning line here is the same tap-A
-- policy as
-- the earlier fights: three attackers on him, Banon healing through Tentacle,
-- with his HP, shields and the party's HP logged every 300 in-battle frames
-- so the whole trajectory is on the record.  A deeper breaking run (probe
-- fire, bank BP, break on the fuse) belongs in a battle test built ON this
-- state; the generator's job is a real, survivable win.

-- After him the script needs no more input: Sabin is swept overboard,
-- `switch $001A=1`, and `call _caad4c` (:39355 -> :26626) tears the party
-- down to SCENARIO_MOG and loads map 9 at {8,6}.  With none of $0021/$001E/
-- $0044 set this is the first visit, so it plays dlg $016F (the "what about
-- SABIN…" recap) and falls into _caadb4 (:26677): wait_30f, then
-- dlg $0B8C "Choose a scenario…kupo!", then `return`.

-- Where the generate lands, and why not mid-dialog.  The state is taken on
-- the first controllable frame after that last dialog is dismissed, i.e.
-- the
-- moment the player could walk to one of the three scenario NPCs.
-- rather than on the frame the prompt is on screen.  A fixture frozen inside
-- a dlg is awkward to build on (every consumer would have to dismiss it
-- first, and the $BA/$D3 dialog state rides in the savestate), and the
-- controllable frame is the same story beat by any useful definition.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/lete_river.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end

-- multiple-choice state (src/field/text.asm)
local CH_SEL, CH_MAX = 0x056E, 0x056F
-- battle readouts: species $57c0+2i, hp $3bfc+2i, shields $3e40+2i
-- (even = current, odd = max -- metrics_battle.lua:110)
local function monSpecies(i) return H.readWord(0x57c0 + i * 2) end
local function monHp(i) return H.readWord(0x3bfc + i * 2) end
local function monShields(i) return H.readByte(0x3e40 + i * 2) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end

-- Answered in order; each entry's `max` is asserted against $056F once the
-- prompt is input-ready, so arriving at a fork the route does not know about
-- fails loudly instead of picking blind.
local CHOICES = {
  { want = 0, max = 2, what = "board the raft (dlg $0167): 0 = Yes" },
  { want = 0, max = 3, what = "fork 1 (dlg $016A): 0 = Straight" },
  { want = 1, max = 2,
    what = "fork 2 (dlg $016E): 1 = LEFT -- option 0 is the vanilla loop" },
  -- A fourth prompt that was not planned for.  _cb04e6 parks the party
  -- on (6,13) after the second landing, and EventTrigger::_114 puts a
  -- SavePoint on exactly that tile (event_trigger.asm:465).  SavePoint
  -- (event_main.asm:100749) is gated on $0133 ("has the save-point
  -- tutorial been shown"), and this is the first save point this route has
  -- ever stepped on, so it fires its one-time
  --     dlg $000A "…Want info about Save Points?  0: Yes  1: No"
  --     choice show_save_info, EventReturn        (:100764-100770)
  -- Only one of its two answers returns control to the party.  This is not
  -- scenery after all.  Look at the two branches:
  --     show_save_info:  dlg $06D4 … / player_ctrl_on / return   (:100775)
  --     EventReturn:     return                                  (:14177)
  -- Option 1 ("No") jumps to a bare return.  Option 0's page of text
  -- text ends in `player_ctrl_on`; option 1 ends in nothing.  Taking "No"
  -- here left the party stuck on (6,13): control never came back, the
  -- ride's next trigger could never be walked onto, and the run timed out
  -- 30,000 frames later with map/alignment/brightness/battle all reading
  -- perfectly fine and only hasControl() false.  So option 0 is taken, and
  -- it is taken deliberately: the four pages of text cost a few hundred
  -- frames and are the only branch that ends with the party able to move.
  { want = 0, max = 2,
    what = "save-point tutorial (dlg $000A): 0 = Yes -- the ONLY branch " ..
           "that ends in player_ctrl_on" },
}
local ci, inChoice = 0, false

-- The fighter.  This river outpaces a blind A-masher: run 1 of the
-- input-driven test conversion lost BANON in fight #3 (the 3-monster roll)
-- with the party never healed once, because tap-A confirms each actor's
-- first command and Banon's first command is Fight; his Health is
-- row 1 of his list (char_prop.asm:321: set_char_prop_cmds FIGHT, HEALTH,
-- NONE, ITEM), so the "free party heal" never fired.  Battles therefore run
-- a menu-episode machine (gen_arvis's cadence: presses start only once the
-- battle-menu flag has held 4 straight frames, then one button per 30-frame
-- pulse, 6 held and 24 released, because battle menus ignore input during their open
-- animation every turn):
--     BANON (char 14)      down A A    Health, the designed sustain
--     EDGAR (4), tier 2+   down A A A  Tools -> AutoCrossbow, his kit's
--                                      whole-side opener (kits.md) --
--                                      escalation after a lost attempt
--     everyone else        A A         Fight, default target
-- A sequence that leaves the menu open (a target prompt the route did not
-- know about, an MP refusal) taps A two more pulses, backs out with B and
-- rebuilds from wherever the cursor is -- progress over elegance -- and
-- every episode is logged with its actor and buttons.

-- Battle bookkeeping (all READS): on each fight's rising edge the
-- formation is named and BANON's battle slot found ($3ED8+2s == 14 --
-- char 14, the WEDGE/BANON symbol collision gen_banon documents); while
-- the fight runs his current HP ($3BF4+2s) is watched every frame, and
-- party + monster HP are logged every 300 frames so a loss ships with its
-- whole trajectory.  Banon at 0 HP for 90 straight frames -- past any
-- mid-round revive the policy could produce -- is the game over the river
-- exists to threaten; a full party wipe is the same fact the long way.
-- Neither errors out of the run any more: they set `lost`, the attempt's
-- pred fires, and the RETRY LADDER below reloads the pre-board checkpoint
-- -- the generator script's spelling of a player reloading their save -- and
-- rides again with the escalated tier.
local BCHID, BCHP, BCMAXHP = 0x3ed8, 0x3bf4, 0x3c1c
local MENU, ACTOR = 0x7bca, 0x62ca -- battle menu open flag / whose menu
local BP = 0x3e9c                  -- banked boost points, +slot*2
local nBattles = 0
local lost = nil                   -- set by the in-battle loss guards
-- The per-turn action, built LIVE (the boost prefix depends on the actor's
-- banked BP this instant).  BOOST IS THE SYSTEM'S OWN LEVER (battle_boost:
-- R raises pending, cap 3, never past bp; a boosted action spends the
-- points and skips that turn's regen) and run 1 of the v2 fighter proved
-- the fights are lost without it -- so everyone banks to 2 and dumps:
-- boosted Fights chip and hit harder, boosted Health heals bigger, which
-- is exactly bosses-wob.md's "sit at 2-3 BP" line for this river.
-- Tiers only escalate what a turn is SPENT on:
--   tier 1  everyone Fight (BANON Health)
--   tier 2  + EDGAR Tools->AutoCrossbow, the whole-side opener
--   tier 3  + SABIN Blitz->AuraBolt (OT6 blitzes are MENU-picked -- the
--            tools-shell list, battle_vargas.lua:263 -- AuraBolt is cell 1
--            of the 2-column grid: right of Pummel)
local function seqFor(id, tier, slot)
  local bp = H.readByte(BP + slot * 2)
  local boost = bp >= 2 and math.min(bp, 3) or 0
  local seq = {}
  for _ = 1, boost do seq[#seq + 1] = "r" end
  local function push(...)
    for _, b in ipairs({ ... }) do seq[#seq + 1] = b end
    return seq
  end
  if id == 14 then return push("down", "a", "a") end          -- Health
  if id == 4 and tier >= 2 then
    return push("down", "a", "a", "a")                        -- AutoCrossbow
  end
  if id == 5 and tier >= 3 then
    return push("down", "a", "right", "a", "a")               -- AuraBolt
  end
  return push("a", "a")                                       -- Fight
end
local function rideUntil(pred, what, budget, idle, tier)
  tier = tier or 1
  local phase, battN, dlgN, lastBatt, hb = 0, 0, 0, -1, -900
  local bt = nil                 -- live fight: { n, f0, banon, dead }
  local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
  local function partyLine()
    local p = {}
    for e = 0, 3 do
      p[#p + 1] = string.format("%d/%d", H.readWord(BCHP + e * 2),
        H.readWord(BCMAXHP + e * 2))
    end
    return table.concat(p, " ")
  end
  local function monsterLine()
    local m = {}
    for i = 0, 5 do
      if monPresent(i) then
        m[#m + 1] = string.format("$%04X hp=%d sh=%d", monSpecies(i),
          monHp(i), monShields(i))
      end
    end
    return table.concat(m, " | ")
  end
  return H.driveUntil(pred, budget or 80000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format("river f%d map=%d (%d,%d) ctl=%s batt=%s dlg=%s " ..
          "ev=%s chMax=%d $0019=%d $001A=%d $04FC=%d $04FD=%d",
          H.frame, map(), H.fieldX(), H.fieldY(), tostring(H.hasControl()),
          tostring(H.battleLoadStarted()), tostring(H.dialogWaiting()),
          tostring(H.eventRunning()), H.readByte(CH_MAX), sw(0x0019),
          sw(0x001A), sw(0x04FC), sw(0x04FD)))
      end

      battN = H.battleLoadStarted() and battN + 1 or 0
      dlgN  = H.dialogWaiting() and dlgN + 1 or 0

      -- 1. a multiple choice: steer, then confirm.  Nothing is read or
      --    asserted until the dialog is input-ready ($056F is only final
      --    then), and nothing is read at all during a battle.
      local chMax = (battN == 0) and H.readByte(CH_MAX) or 0
      if chMax >= 2 then
        if not H.dialogWaiting() then H.setPad({}); return end
        if not inChoice then
          inChoice = true
          ci = ci + 1
          local c = CHOICES[ci]
          if not c then
            error(string.format("river: unexpected choice prompt #%d (%d " ..
              "options) on map %d -- the route knows of only %d",
              ci, chMax, map(), #CHOICES), 0)
          end
          H.assertEq(chMax, c.max,
            string.format("choice #%d option count (%s)", ci, c.what))
          H.log(string.format("river: CHOICE #%d up (%d options) -- taking " ..
            "option %d :: %s", ci, chMax, c.want, c.what))
          H.screenshot(string.format("scenario_choice%d", ci))
        end
        local c, sel = CHOICES[ci], H.readByte(CH_SEL)
        if sel < c.want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > c.want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      elseif inChoice then
        inChoice = false
        H.log(string.format("river: choice #%d resolved at f%d (%s)",
          ci, H.frame, CHOICES[ci].what))
      end

      -- 2. battle: name it on the rising edge, then FIGHT it -- the same
      --    edge-tapped A drives menus, targets and victory text (see the
      --    header: TERRA/EDGAR/SABIN Fight, BANON Health).  No writes.
      if battN >= 3 then
        if battN == 3 and lastBatt ~= H.frame then
          lastBatt = H.frame
          nBattles = nBattles + 1
          bt = { n = nBattles, f0 = H.frame, banon = nil, dead = 0 }
          local w = H.formationWords()
          H.log(string.format("river: battle #%d up f%d (%04X %04X %04X " ..
            "%04X %04X %04X)", bt.n, H.frame, w[1], w[2], w[3], w[4], w[5],
            w[6]))
          for i = 0, 5 do
            if monPresent(i) then
              H.log(string.format("   slot %d species $%04X hp=%d shields=%d",
                i, monSpecies(i), monHp(i), monShields(i)))
              if monSpecies(i) == 0x012C then
                bt.ultros = true
                H.log(string.format("river: *** ULTROS ($012C) slot %d -- " ..
                  "hp %d, shields %d (Ot6ShieldTbl authors 5, " ..
                  "OT6_SLASH|OT6_PIERCE) -- fighting him for real", i,
                  monHp(i), monShields(i)))
                H.screenshot("scenario_ultros")
              end
            end
          end
        end
        if bt then
          bt.gone = 0
          bt.lastParty = partyLine()
          -- Banon's slot is read once the load has settled (the char-id
          -- table is battle scratch; at battN==30 the battle module
          -- demonstrably owns it -- the HP signal has held 30 frames)
          if battN == 30 and bt.banon == nil then
            for s = 0, 3 do
              if H.readByte(BCHID + s * 2) == 14 then bt.banon = s end
            end
            H.log(string.format("river: #%d banon slot=%s party [%s]",
              bt.n, tostring(bt.banon), partyLine()))
          end
          if battN % 300 == 0 then
            H.log(string.format("river: #%d f%d party [%s] vs %s",
              bt.n, H.frame, partyLine(), monsterLine()))
          end
          if bt.banon then
            bt.dead = H.readWord(BCHP + bt.banon * 2) == 0 and bt.dead + 1
                      or 0
            local wiped = true
            for e = 0, 3 do
              if H.readWord(BCMAXHP + e * 2) > 0
                 and H.readWord(BCHP + e * 2) > 0 then wiped = false end
            end
            if bt.dead >= 90 or wiped then
              lost = string.format("%s in battle #%d at f%d (started f%d, " ..
                "%d frames in, tier %d) -- party [%s] vs %s",
                wiped and "PARTY WIPED" or "BANON DOWN", bt.n, H.frame,
                bt.f0, H.frame - bt.f0, tier, partyLine(), monsterLine())
              H.log("river: " .. lost)
              H.screenshot(string.format("scenario_lost%d", bt.n))
              return              -- the attempt's pred sees `lost` and ends
            end
          end
        end
        -- act: outside a settled menu, edge-tap A (opening dialogs, the
        -- shell text, victory pages); inside one, run the episode machine
        if bt == nil or bt.banon == nil or H.readByte(MENU) == 0 then
          mStreak, mSeq = 0, nil
          H.setPad(phase < 4 and { "a" } or {})
          return
        end
        mStreak = mStreak + 1
        if mStreak < 4 then H.setPad({}); return end
        if mSeq == nil then
          local slot = H.readByte(ACTOR) & 3
          local id = H.readByte(BCHID + slot * 2)
          mSeq, mIdx, mTick, mStall = seqFor(id, tier, slot), 1, 0, 0
          H.log(string.format("river: #%d cast f%d slot=%d char=%d bp=%d " ..
            "seq=%s | party [%s] vs %s", bt.n, H.frame, slot, id,
            H.readByte(BP + slot * 2), table.concat(mSeq, ","), partyLine(),
            monsterLine()))
        end
        mTick = mTick + 1
        local ph = mTick % 30
        local btn
        if mIdx <= #mSeq then
          btn = mSeq[mIdx]
        elseif mStall < 2 then
          btn = "a"               -- a prompt the sequence did not know
        elseif mStall < 4 then
          btn = "b"               -- back out (an MP refusal, a dead end)
        else
          mSeq = nil              -- rebuild from wherever the cursor is
          H.setPad({})
          return
        end
        if ph < 6 then H.setPad({ [btn] = true }) else H.setPad({}) end
        if ph == 29 then
          if mIdx <= #mSeq then mIdx = mIdx + 1 else mStall = mStall + 1 end
        end
        return
      end
      -- the falling edge, debounced the same 3 frames the rising edge is
      -- (the signal bytes are shared RAM; a 1-frame flicker mid-fight must
      -- not close the books on a battle that is still running)
      if bt then
        bt.gone = (bt.gone or 0) + 1
        if bt.gone >= 3 then
          H.log(string.format("river: battle #%d done at f%d (%d frames)%s " ..
            "-- party [%s]", bt.n, H.frame, H.frame - bt.f0,
            bt.ultros and " -- ULTROS BEATEN" or "",
            bt.lastParty or "?"))
          if bt.ultros then H.screenshot("scenario_ultros_won") end
          bt = nil
        end
      end

      -- 3. plain dialog: edge-tap through it
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}); return end

      -- 4. anything else (the raft moving, fades, map loads): hands off,
      --    unless the caller has something to do with the idle frames --
      --    which is how the two map-114 handoffs are driven.  Doing it HERE
      --    rather than as a separate step is deliberate: the save-point
      --    prompt fires AFTER the landing script sets its completion switch,
      --    so a standalone "hold DOWN" phase would have been holding a
      --    direction into an open multiple choice and steering its cursor.
      --    Inside the driver the choice branch above always wins first.
      if idle then idle() else H.setPad({}) end
    end),
  }, what)
end

-- n consecutive frames of real, settled player control on `m`
-- It says WHY it is not satisfied, every 600 frames.  A settle predicate
-- that just returns false is the worst thing to debug in this harness: the
-- run reports "timeout driving toward X" and every term you can see in the
-- heartbeat looks fine.
local function landed(m, n, doneSw)
  local cnt, hb = 0, -600
  return function()
    local okMap = map() == m
    -- THE LANDINGS ARE GATED ON THE LANDING SCRIPT'S OWN SWITCH, NOT ON
    -- hasControl().  _cb04b7 ends `switch $04FC=1` and _cb04e6 ends
    -- `switch $04FD=1` (:38708, :38737), which is the script saying "I am
    -- finished" in its own words.  hasControl() is the wrong question here
    -- and asking it cost two runs: at the SECOND landing the party sits on
    -- (6,13) with $1EB9/$0084/$0059 all clear and the screen up, but
    -- $087C reads 4 (event-controlled) and the event PC is parked at
    -- $CC9AEB -- which is SavePoint's own entry point (the disassembly
    -- labels it `; cc/9aeb`, event_main.asm:100748).  The party is standing
    -- ON the save point, so the harness's control predicate stays false
    -- even though the ride is over and the party can be walked.  The
    -- completion switch is unambiguous where hasControl() is not.
    local okCtl = doneSw and sw(doneSw) == 1 or H.hasControl()
    local okAlign, okBright = H.tileAligned(), bright() >= 15
    local okBatt = not H.battleLoadStarted()
    local okCh = H.readByte(CH_MAX) == 0 and not H.dialogWaiting()
    local ok = okMap and okCtl and okAlign and okBright and okBatt and okCh
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      local po = H.readWord(0x0803)
      H.log(string.format("landed(%d) f%d blocked: map=%s(%d) ctl=%s " ..
        "align=%s bright=%s(%d) batt=%s choice=%s | at (%d,%d) " ..
        "$1EB9=%02X $0084=%02X $0059=%02X $087C=%02X($0803=%04X) " ..
        "ev=%s evPC=%02X:%02X%02X", m, H.frame,
        tostring(okMap), map(), tostring(okCtl), tostring(okAlign),
        tostring(okBright), bright(), tostring(okBatt), tostring(okCh),
        H.fieldX(), H.fieldY(),
        H.readByte(0x1eb9), H.readByte(0x0084), H.readByte(0x0059),
        H.readByte(0x087c + po), po, tostring(H.eventRunning()),
        H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5)))
    end
    return cnt >= (n or 20)
  end
end

-- THE HANDOFF, as an idle action rather than a phase.  Map 114 is where the
-- raft puts in, twice, and each time the way onward is an event trigger the
-- party must WALK ONTO FACING DOWN (_cb051c/_cb055c both open `if_switch
-- $01B2=0, EventReturn`, and $01B2 is the engine's "facing down" bit -- see
-- the header).  A plain hold does both jobs at once; a navTo would not, since
-- BFS is free to make its last step sideways.
local announced = {}
local function walkOffLandings()
  if map() ~= 114 then H.setPad({}); return end
  local k = (sw(0x04FD) == 1) and 2 or 1
  if not announced[k] then
    announced[k] = true
    H.log(string.format("river: LANDING %d on map 114 at (%d,%d) -- holding " ..
      "DOWN onto %s, which only fires for a party facing DOWN", k,
      H.fieldX(), H.fieldY(),
      k == 1 and "_cb051c (20,24)" or "_cb055c (6,15)"))
    H.screenshot("scenario_landing" .. k)
  end
  H.setPad({ down = true })
end

-- ------------------------------------------------------ the retry ladder --
-- A lost river run is ACCEPTED, not rigged around: the checkpoint captured
-- at the entry point (before the boarding trigger) is reloaded -- the
-- generator's spelling of a player reloading their save -- and the ride is
-- taken again.  The reload replays byte-identically until the INPUT
-- differs, so each attempt escalates the fighter's tier (attempt 2+ spends
-- Edgar's turns on AutoCrossbow, the whole-side opener), which reshuffles
-- every subsequent ATB interleaving and roll as a side effect.  Three
-- attempts; a third loss fails the generation with every attempt's numbers
-- already on the record -- a real partial beats a fudged whole.
local rideBlob, rideWon = nil, false
local function rideAttempt(n)
  local ldReq
  return H.cond(function() return not rideWon end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("river: ATTEMPT %d -- reloading the pre-board " ..
          "checkpoint after a loss (%s)", n, tostring(lost))
      end),
      H.call(function() ldReq = H.requestLoadState(rideBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "attempt " .. n .. ": reload") end),
      H.waitFrames(60),
    }, {}),
    H.call(function()               -- fresh per-attempt driver state
      ci, inChoice, lost, nBattles = 0, false, nil, 0
      announced = {}
    end),
    H.navTo(31, 51, { maxFrames = 12000, playBattles = true,
      arrive = function() return sw(0x01B5) == 1 end }),
    H.release(),
    -- ONE driver for the whole river: it steers the four prompts, fights
    -- every battle, taps every dialog, and holds DOWN off both landings.
    (function()
      local landedPred = landed(9, 20)
      return rideUntil(function() return lost ~= nil or landedPred() end,
        string.format("the Lete River, attempt %d: board, both forks, the " ..
          "two landings, ULTROS, and the scenario hub", n),
        200000, walkOffLandings, n)
    end)(),
    H.release(),
    H.waitFrames(30),
    H.call(function()
      if lost == nil then
        rideWon = true
        H.log(string.format("river: attempt %d WON the ride -- %d battles " ..
          "fought", n, nBattles))
      end
    end),
  }, {})
end

H.run({ maxFrames = 700000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 113, "booted on map 113, the Lete River")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0018), 1, "$0018 set -- _cb059f will board")
    H.assertEq(sw(0x001A), 0, "$001A clear -- the river has not been run")
    H.assertEq(sw(0x0176), 0,
      "$0176 clear -- the ride's continuations are armed (every segment of the " ..
      "river ends `if_switch $0176=0, <next>`)")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true, "BANON in the party")
    H.log(string.format("[booted] map=%d (%d,%d)", map(), H.fieldX(), H.fieldY()))
  end),

  -- ===================================================================== --
  -- THE CHECKPOINT, then BOARD.  The pre-board capture is the ladder's
  -- reload point: it holds the entry point BEFORE (31,51) fires _cb059f
  -- (event_trigger.asm:462), so a reloaded attempt replays the boarding
  -- exactly.  NB $01B5 is NOT set the moment the trigger fires: _cb059f
  -- runs clr_status/max_hp for the party (the raft leaves FULLY HEALED,
  -- every attempt) and then `dlg $0166` ("Here we go!", :38826) -- a
  -- dialog that WAITS FOR A KEYPRESS -- and only reaches `switch $01B5=1`
  -- at _cb05e4 (:38834) once that is dismissed.  A first cut asserted
  -- $01B5 straight after the walk and failed on exactly that.  So the
  -- walk only gets the party onto the tile; the driver taps $0166 and on.
  -- ===================================================================== --
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "pre-board checkpoint")
        rideBlob = ckReq.blob
        H.log(string.format("river: pre-board checkpoint captured " ..
          "(%d bytes) at (%d,%d) f%d", #rideBlob, H.fieldX(), H.fieldY(),
          H.frame))
      end),
    })
  end)(),

  rideAttempt(1),
  rideAttempt(2),
  rideAttempt(3),
  H.call(function()
    if not rideWon then
      error(string.format("river: BANON did not survive any of 3 " ..
        "attempts -- last loss: %s -- the per-attempt numbers above are " ..
        "the balance finding (#74-style); do not rig this segment",
        tostring(lost)), 0)
    end
  end),
  H.call(function()
    H.assertEq(ci, 4,
      "all four prompts answered: board, fork 1, fork 2, save-point tutorial")
    H.assertEq(sw(0x0019), 1, "$0019 set -- the ride ran (_cb0657)")
    H.assertEq(sw(0x04FC), 1, "$04FC set -- _cb04b7 ran (the first landing)")
    H.assertEq(sw(0x04FD), 1, "$04FD set -- _cb04e6 ran (the second landing)")
    H.assertEq(sw(0x0133), 1, "$0133 set -- the save-point tutorial fired")
  end),

  H.call(function()
    H.assertEq(map(), 9, "on map 9, the SCENARIO HUB")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(H.readByte(CH_MAX), 0, "no choice prompt left open")
    H.assertEq(sw(0x001A), 1, "$001A set -- the river was run (_cb08db)")
    -- the hub tore the party down to SCENARIO_MOG alone
    H.assertEq((H.readByte(0x1850) & 0x07) ~= 0, false, "TERRA out of the party")
    H.assertEq((H.readByte(0x1854) & 0x07) ~= 0, false, "EDGAR out")
    H.assertEq((H.readByte(0x1855) & 0x07) ~= 0, false, "SABIN out")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, false, "BANON out")
    -- and none of the three scenarios has been completed yet
    H.assertEq(sw(0x001E), 0, "$001E clear -- LOCKE's scenario not done")
    H.assertEq(sw(0x0044), 0, "$0044 clear -- SABIN's scenario not done")
    H.assertEq(sw(0x0021), 0, "$0021 clear -- TERRA/BANON's scenario not done")
    -- the three scenario NPCs are on the map, waiting to be talked to
    H.assertEq(sw(0x0329), 1, "$0329 set -- LOCKE's scenario NPC {5,8}")
    H.assertEq(sw(0x032A), 1, "$032A set -- SABIN's scenario NPC {11,8}")
    H.assertEq(sw(0x032B), 1, "$032B set -- BANON's scenario NPC {8,10}")
    H.assertEq(sw(0x032C), 1, "$032C set -- TERRA's scenario NPC {7,11}")
    H.assertEq(sw(0x032D), 1, "$032D set -- EDGAR's scenario NPC {9,11}")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.log(string.format("[scenario_hub] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("scenario_hub")
  end),
  H.saveState("scenario_hub.mss"),
  H.logStep(function()
    return string.format("scenario_hub generated at frame %d", H.frame)
  end),
})
