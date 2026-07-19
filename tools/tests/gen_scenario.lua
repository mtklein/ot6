-- gen_scenario.lua -- from lete_river.mss (map 113, one tile off the raft)
-- down the LETE RIVER, through ULTROS, to the THREE-WAY SCENARIO SPLIT.
-- Mints one state:
--   scenario_hub.mss  map 9, party = SCENARIO_MOG alone, first controllable
--                     frame after Mog's "Choose a scenario…kupo!" -- the
--                     entry point of the whole v0.3 arc, and the fixture the
--                     three scenario chains branch from.
--
-- ============================ THE RIVER LOOPS ============================
-- THE SECOND STEERING PROMPT'S OPTION 0 IS AN INFINITE LOOP, AND IT IS
-- VANILLA.  This is the single most important fact in this file.
--
--   _cb07f2:  dlg $016E  "Hey, which way?  0: (Up)   1: (Left)"
--             choice _cb07fc, _cb0840          (event_main.asm:39152-39158)
--
-- Option 0 (_cb07fc, :39159) rides a loop of the river and ends
-- `if_switch $0176=0, _cb07f2` (:39197) -- straight back to the same prompt.
-- Option 1 (_cb0840, :39199) is the only way downstream.  This is the famous
-- unattended-grind spot of vanilla FF6 -- memory cursor on, Banon healing,
-- come back to an overlevelled party -- it is intentional, CONTRIBUTING.md's
-- "vanilla's bugs stay" covers it, and it is NOT something to fix.
--
-- But it is a trap for a fixture, and a nasty one: advanceStory's blanket
-- A-press ALWAYS takes option 0, so a naive drive down this river never
-- terminates.  It burns its whole frame budget and dies with a timeout that
-- reads like a navigation failure rather than a wrong menu pick.  So this
-- script never A-mashes a prompt.  Every `choice` on the route is answered
-- EXPLICITLY, by steering the multiple-choice cursor to a named option and
-- only then confirming, and each is logged so a future failure says which
-- fork it was at.  The three, in the order they arrive:
--
--   1. _cb059f  dlg $0167 "Hop aboard the raft?  0: Yes  1: No"      -> 0
--                 choice _cb05f0, EventReturn            (:38836-38841)
--   2. _cb0657  dlg $016A "Which way? 0:(Straight) 1:(Left) 2:(Right)" -> 0
--                 choice _cb0686, _cb06f7, _cb075c       (:38915-38921)
--      (all three converge -- each ends `load_map 114, {13,36}` -- so this
--      fork is safe either way; 0 is taken because it is shortest, and
--      "safe" was worth verifying rather than assuming)
--   3. _cb07f2  dlg $016E "Hey, which way?  0:(Up)  1:(Left)"        -> 1
--                 choice _cb07fc, _cb0840                (:39152-39158)
--      ^^^ THE LOOP.  Option 0 here is the whole reason this file steers.
--
-- HOW THE CURSOR WORKS (src/field/text.asm:368-425, transcribed):
--   $056F  number of options; >= 2 means a multiple choice is live, and the
--          engine zeroes it the moment A confirms (:425)
--   $056E  current selection, 0-based
--   $056D  "selection is changing" latch -- set when a direction moves the
--          cursor, cleared only on a frame with NO direction held (:380)
-- That latch is why the steering presses are EDGE presses (4 on / 4 off)
-- like every other input in this suite: a held DOWN moves the cursor exactly
-- one row, ever.  DOWN/RIGHT increment (and stop at $056F), UP/LEFT
-- decrement (and stop at 0).
--
-- TWO WAYS TO READ $056F WRONG, both of which cost a run here:
--   * IT IS MEANINGLESS DURING A BATTLE.  It is field dialog RAM and the
--     battle module scribbles it; a first cut tested it unconditionally and
--     announced a phantom "choice #2" in the middle of the ride's second
--     forced fight.  The handler only looks while no battle is up.
--   * IT IS BUILT UP AS THE TEXT TYPES OUT.  text.asm:684 calls it "max
--     choice found so far" -- it counts special letter $15 indicators AS
--     THEY ARE DRAWN.  Sampling it the instant it first reads >= 2 caught
--     fork 1 mid-render and reported 2 options for a 3-option prompt (the
--     screenshot showed a half-drawn box: "Which way? / (Straight)" and
--     nothing else yet).  So nothing is read or asserted until
--     H.dialogWaiting() -- $BA=1 and $D3=1, the engine waiting for a
--     keypress -- which is the only moment $056F is final.
--
-- ============================ THE RIDE ITSELF ============================
-- IT IS NOT A VEHICLE MODE.  The brief that scoped this work expected a
-- third engine mode beside field and world -- `set_script_mode` / `vehicle`
-- / `move_vehicle`.  It is not that.  The raft is an ORDINARY FIELD MAP
-- (113, then 114) with the party under event control for most of it:
-- _cb05f0 does `player_ctrl_off` (:38843) and every inch of the river is
-- `obj_script SLOT_1, ASYNC { move ... }` followed by `wait_obj SLOT_1`.
-- The only `vehicle` opcodes involved are cosmetic -- _cb050f (:38774) sets
-- each SLOT's sprite to {RAFT, SHOW_RIDER} and _cb04aa clears it -- and
-- `set_script_mode WORLD` appears only where the river spills onto the
-- overworld, a branch this route does not take.  So the harness needed no
-- new engine model: the ride is "answer the prompts, survive the battles,
-- and walk the two handoffs below".
--
-- THE RIDE IS NOT CONTINUOUS -- IT HANDS CONTROL BACK TWICE, AND THE WAY
-- ONWARD IS A TRIGGER YOU MUST WALK ONTO **FACING DOWN**.  This is the fact
-- that actually cost the most here.  Map 114 is where the raft puts in, and
-- EventTrigger::_114 (event_trigger.asm:464-468) is
--     {20,21} SavePoint   {6,13} SavePoint
--     {20,24} _cb051c     {6,15} _cb055c
-- Both continuations open with `if_switch $01B2=0, EventReturn` (:38746,
-- :38777).  A first pass read $01B2 as an inert engine flag, measured it 0,
-- and shrugged -- and the ride duly stopped dead with the party standing
-- controllable at map 114 (20,22) for 130,000 frames, which is exactly what
-- "the river hangs" looks like from the outside.
--
-- $01B0-$01B7 ARE NOT STORY SWITCHES.  Switch id N lives at bit N&7 of
-- $1E80+(N>>3), so $01B0..$01B7 alias the byte $1EB6 -- and $1EB6 is the
-- field engine's own control-flags byte.  UpdateCtrlFlags (field/event.asm
-- :5415-5432) writes it every frame:
--     lda $087f,y / tax / lda $1eb6 / and #$f0 / ora f:BitOrTbl,x
-- i.e. BITS 0-3 ARE THE PARTY'S FACING DIRECTION, one-hot, in the engine's
-- own 0=up 1=right 2=down 3=left encoding (BitOrTbl, :5523); bit4 is "A is
-- held"; bit5 is the once-per-tile event latch player.asm:529 clears on
-- every step.  So, read properly:
--     $01B0 = facing UP      $01B2 = facing DOWN     $01B4 = A held
--     $01B1 = facing RIGHT   $01B3 = facing LEFT     $01B5 = tile-event latch
-- `if_switch $01B2=0, EventReturn` means "unless the party is facing DOWN".
-- Hence the handoffs below are a plain HOLD DOWN -- which both walks the
-- party onto the trigger and leaves it facing the right way -- and not a
-- navTo, whose last step BFS is free to make sideways.
--
-- The same reading retro-explains three things elsewhere in the story that
-- had looked arbitrary: _caf79c picks Banon's approach animation off
-- $01B0/$01B1/$01B2 (which way you walked up to him), _caf68a/_caf6f0/
-- _caf717 pick escort variants the same way, and the Returner Hideout's
-- scrap-of-paper trigger _cb002b needs $01B4 AND $01B2 -- it is an EXAMINE
-- (press A facing down), not a step, which is why gen_banon never tripped it.
-- And _cb059f's own `if_switch $01B5=1, EventReturn` / `switch $01B5=1` is
-- just the standard once-per-tile latch, not a story flag.
--
-- THE BATTLES ARE FORCED, NOT RANDOM ENCOUNTERS.  The ride calls _cb0498
-- (`battle 7, RIVER`) and _cb04a1 (`battle 8, RIVER`) outright, and
-- _cb0486/_cb048f are `if_rand` coin-flips into them (:38660-38678).  A
-- dozen or so fire on the way down.  They are cleared with the harness's
-- kill-bit idiom, like every other trash fight in the frontier chain.
--
-- ULTROS: `battle 103, RIVER` at _cb08db (:39301).  He HAS an authored
-- shield row -- Ot6ShieldTbl carries $012c (MONSTER::ULTROS_RIVER) at
-- 5 shields, OT6_SLASH|OT6_PIERCE, commented "ultros 1: the row he keeps all
-- game" (ff6/src/battle/ot6.asm:3008-3009).  The fight is logged in detail
-- below (species, hp, shields per slot) so the numbers are on the record,
-- but it is CLEARED, not fought properly: unlike Vargas -- whose reaction
-- script answers Pummel specifically, so his fixture had to fight him the
-- way the story means -- nothing downstream of Ultros depends on how he went
-- down.  A real breaking run against him belongs in a battle test built on
-- this state, not in the state's own mint.
--
-- AFTER HIM the script needs no more input: Sabin is swept overboard,
-- `switch $001A=1`, and `call _caad4c` (:39355 -> :26626) tears the party
-- down to SCENARIO_MOG and loads map 9 at {8,6}.  With none of $0021/$001E/
-- $0044 set this is the first visit, so it plays dlg $016F (the "what about
-- SABIN…" recap) and falls into _caadb4 (:26677) -- wait_30f, then
-- dlg $0B8C "Choose a scenario…kupo!", then `return`.
--
-- WHERE THE MINT LANDS, and why not mid-dialog.  The state is taken on the
-- first CONTROLLABLE frame after that last dialog is dismissed -- i.e. the
-- moment the player could actually walk to one of the three scenario NPCs --
-- rather than on the frame the prompt is on screen.  A fixture frozen inside
-- a dlg is awkward to build on (every consumer would have to dismiss it
-- first, and the $BA/$D3 dialog state rides in the savestate), and the
-- controllable frame is the same story beat by any useful definition.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/lete_river.mss.lua"

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
  -- A FOURTH PROMPT NOBODY PUT THERE ON PURPOSE.  _cb04e6 parks the party
  -- on (6,13) after the second landing, and EventTrigger::_114 puts a
  -- SavePoint on exactly that tile (event_trigger.asm:465).  SavePoint
  -- (event_main.asm:100749) is gated on $0133 -- "has the save-point
  -- tutorial been shown" -- and this is the first save point this route has
  -- ever stepped on, so it fires its one-time
  --     dlg $000A "…Want info about Save Points?  0: Yes  1: No"
  --     choice show_save_info, EventReturn        (:100764-100770)
  -- AND ONLY ONE OF ITS TWO ANSWERS GIVES THE PARTY BACK.  This is not
  -- scenery after all.  Look at the two branches:
  --     show_save_info:  dlg $06D4 … / player_ctrl_on / return   (:100775)
  --     EventReturn:     return                                  (:14177)
  -- Option 1 ("No") jumps to a BARE RETURN.  Option 0's page of flavour
  -- text ends in `player_ctrl_on`; option 1 ends in nothing.  Taking "No"
  -- here left the party frozen on (6,13) -- control never came back, the
  -- ride's next trigger could never be walked onto, and the run timed out
  -- 30,000 frames later with map/alignment/brightness/battle all reading
  -- perfectly fine and only hasControl() false.  So option 0 is taken, and
  -- it is taken ON PURPOSE: the four pages of text cost a few hundred
  -- frames and are the only branch that ends with the party able to move.
  { want = 0, max = 2,
    what = "save-point tutorial (dlg $000A): 0 = Yes -- the ONLY branch " ..
           "that ends in player_ctrl_on" },
}
local ci, inChoice = 0, false

-- The ride driver: steer choices, kill-bit battles, tap dialogs, touch
-- nothing else.  Reused for each stretch between the manual handoffs.
local function rideUntil(pred, what, budget, idle)
  local phase, battN, dlgN, lastBatt, hb = 0, 0, 0, -1, -900
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

      -- 2. battle: name it once on the rising edge, then kill-bit it
      if battN >= 3 then
        if battN == 3 and lastBatt ~= H.frame then
          lastBatt = H.frame
          local w = H.formationWords()
          H.log(string.format("river: battle up f%d (%04X %04X %04X %04X " ..
            "%04X %04X)", H.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
          for i = 0, 5 do
            if monPresent(i) then
              H.log(string.format("   slot %d species $%04X hp=%d shields=%d",
                i, monSpecies(i), monHp(i), monShields(i)))
              if monSpecies(i) == 0x012C then
                H.log(string.format("river: *** ULTROS ($012C) slot %d -- " ..
                  "hp %d, shields %d (Ot6ShieldTbl authors 5, " ..
                  "OT6_SLASH|OT6_PIERCE)", i, monHp(i), monShields(i)))
                H.screenshot("scenario_ultros")
              end
            end
          end
        end
        if H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if monPresent(slot) then
              H.writeByte(0x3eec + slot * 2,
                H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        H.setPad(phase < 4 and { "a" } or {})
        return
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

H.run({ maxFrames = 200000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 113, "booted on map 113, the Lete River")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0018), 1, "$0018 set -- _cb059f will board")
    H.assertEq(sw(0x001A), 0, "$001A clear -- the river has not been run")
    H.assertEq(sw(0x0176), 0,
      "$0176 clear -- the ride's continuations are armed (every leg of the " ..
      "river ends `if_switch $0176=0, <next>`)")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true, "BANON in the party")
    H.log(string.format("[booted] map=%d (%d,%d)", map(), H.fieldX(), H.fieldY()))
  end),

  -- ===================================================================== --
  -- BOARD.  Step onto (31,51) -> _cb059f (event_trigger.asm:462).
  -- NB $01B5 is NOT set the moment the trigger fires: _cb059f runs
  -- clr_status/max_hp for the party and then `dlg $0166` ("Here we go!",
  -- :38826) -- a dialog that WAITS FOR A KEYPRESS -- and only reaches
  -- `switch $01B5=1` at _cb05e4 (:38834) once that is dismissed.  A first
  -- cut asserted $01B5 straight after the walk and failed on exactly that,
  -- with the dialog on screen and nobody pressing anything.  So the walk
  -- only gets the party onto the tile; the driver taps $0166 and on.
  -- ===================================================================== --
  H.navTo(31, 51, { maxFrames = 12000,
    arrive = function() return sw(0x01B5) == 1 end }),
  H.release(),

  -- ONE driver for the whole river: it steers the four prompts, kill-bits a
  -- dozen forced fights, taps every dialog, and holds DOWN off both landings.
  rideUntil(landed(9, 20), "the Lete River: board, both forks, the two " ..
    "landings, ULTROS, and the scenario hub", 160000, walkOffLandings),
  H.release(),
  H.waitFrames(30),
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
    return string.format("scenario_hub minted at frame %d", H.frame)
  end),
})
