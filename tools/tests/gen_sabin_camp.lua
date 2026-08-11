-- gen_sabin_camp.lua -- step 2 of SABIN's scenario: the Imperial Camp's
-- opening, which is not about SABIN at all.  Generates one state:
--   camp_intro.mss  map 117 at (36,2), SABIN + SHADOW, controllable, with
--                   $02E2 set so the gate cutscene cannot re-fire
--
-- WALKING ONE TILE SOUTH HANDS THE GAME TO CYAN, ON ANOTHER MAP, FOR ~9,000
-- FRAMES.  This is the whole content of this step and it is not what the
-- route map suggests.  Stepping from the camp gate onto (36,3) fires
-- _cb0c2f (event_trigger.asm:33, event_main.asm:39785), which walks the
-- party UP 1 / RIGHT 2 to (38,2) and calls the commander scene _cb0c87
-- (:39826).  That scene's LAST act is not "give control back":
--
--     fade_out / wait_fade / switch $01CC=1 / switch $04EE=1
--     wait_1s / call _cb9aae                        (:40019-40027)
--
-- and _cb9aae (:60795) is the Doma interlude:
--     char_party CYAN, 1 / char_party SABIN, 0
--     load_map 120, {33,42}, UP                     (:60802-60806)
-- CYAN, alone, on DOMA CASTLE's interior map.  From there it runs a long
-- automatic stretch, detours through `load_map 123, {10,44}` (:61120), hits
-- `name_menu CYAN` (:61204), comes back with `load_map 120, {33,49}`
-- (:61245), parks SLOT_1 on (33,44) and the commander (NPC_1, obj 16) on
-- (33,54) (:61246-61269), and only then reaches `player_ctrl_on` (:61482).
--
-- WHAT THIS COST, AND WHY THE FILE IS SHAPED THIS WAY.  Run 1 of this step
-- pointed navTo at the LEO scene's tile and let it walk.  navTo dropped its
-- plan on the first frame ("control lost at (36,2)") and then sat for
-- 20,000 frames while the heartbeat printed the party object drifting
-- (38,2) -> (33,42) -> (10,44) -> (10,39): those are _cb9aae's map-120
-- spawn, map 123's spawn, and CYAN mid-cutscene, all read through the same
-- $0803 offset and all completely invisible as MAP CHANGES because navTo's
-- heartbeat does not print the map.  It froze for good at (10,39) --
-- `name_menu CYAN`, which navTo has no branch for and never will.  So:
-- nothing on this step is walked with navTo except the two short stretches
-- where the party genuinely has control, and everything else is ridden.
--
-- ONLY THE COMMANDER MATTERS.  Map 120 stands up twelve soldiers (NPCProp
-- ::_120, npc_prop.asm), eleven of which are `battle 43` grinding
-- (_cb9ffb.._cba073, :61739-61802) that hides one NPC each and changes no
-- switch.  The twelfth, obj 16 at (33,54), is the commander: _cb9eb5
-- (:61517) fights `battle 46` and its tail is the scene that ends the
-- interlude and calls _cb0bc4 (:61737) -- the CAMP's own startup event,
-- which re-creates SABIN and SHADOW and reloads map 117 at (36,2).  So the
-- interlude is exactly one fight long and the eleven others are skipped.
--
-- ISSUE #75 -- BATTLE 46 IS FOUGHT, NOT WRITE-CLEARED.  Zero state writes in
-- this generator.  The fight is CYAN alone (battle slot ONE -- see the
-- inBattle note) against event battle group 46 = formation 409 = one $14E,
-- and its loss is unrecoverable in-timeline: `battle 46` is followed by
-- `call _ca5ea9` (:61522-61523), the GameOver gate, so a lost fight parks
-- the event PC at $CB9EBB forever.  The fighter is the house menu-episode
-- machine (gen_scenario's cadence: presses start only once the battle-menu
-- flag has held 4 straight pulses, then ONE button per 30-frame pulse):
-- CYAN banks boost to 2 and dumps it on Fight -- R raises pending boost,
-- A A confirms the boosted Fight on the default target -- the same
-- bank-and-dump doctrine the river fighters proved.  A loss (CYAN at 0 HP
-- for 90 straight frames) does not error: it sets `lost` and the RETRY
-- LADDER reloads the cyan_defence-moment checkpoint -- the generator
-- script's spelling of a player reloading their save -- and pokes the
-- commander again with the fighter escalated (attempt 2+ dumps at 1 BP,
-- which changes every input from the first turn and reshuffles the whole
-- interleaving).  Three attempts, then fail with every attempt's numbers on
-- the record.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/sabin_camp.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function seq(steps) return H.cond(function() return true end, steps) end

local CH_SEL, CH_MAX = 0x056E, 0x056F
local NAME_MENU = 0x0200
local function monSpecies(i) return H.readWord(0x57c0 + i * 2) end
local function monHp(i) return H.readWord(0x3bfc + i * 2) end
local function monShields(i) return H.readByte(0x3e40 + i * 2) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function monCount()
  local n = 0
  for i = 0, 5 do if monPresent(i) then n = n + 1 end end
  return n
end

-- BATTLE DETECTION, SLOT-AGNOSTIC -- and this is the whole reason run 2 of
-- this file died.  lib/ot6.lua's battleLoadStarted() reads ONE word, party
-- battle-HP slot 0 at $3BF4, and calls it "a battle has begun loading".
-- That holds for every fixture the harness had before this arc, because
-- every one of them fought with a party whose slot 0 was occupied.  CYAN's
-- solo defence of Doma does not: measured across the whole fight,
--     $3BF4=0000  $3BF6=00FE  $3BF8=0000  $3BFA=0000
-- CYAN is in battle slot ONE.  So battleLoadStarted() stayed false for the
-- entire battle, every driver in the run treated it as "no battle", nobody
-- pressed anything, and CYAN stood there while his HP ticked
-- FE -> D4 -> 94 -> 5A and the fight was lost.  The loss is then silent by
-- design: `battle 46` is followed by `call _ca5ea9` (:61522-61523), and
-- _ca5ea9 is `if_b_switch $40, _ca5eb2 / call GameOver` -- so a lost battle
-- leaves the event PC parked at $CB9EBB forever with the field still drawn.
--
-- So scan all four slots -- but VALIDATE THE WHOLE TABLE, not just "some
-- slot looks like HP".  A first attempt that returned true on any single
-- plausible word fired on map 123 while the CYAN name menu was open:
--     $3BF4=FF00 $3BF6=0020 $3BF8=FF00 $3BFA=0020
-- ($3BF6 = 32 reads perfectly like a hit point).  That is OpenMenu_ext
-- scribbling on the same RAM while the field module is suspended, and
-- taking it for a battle made the driver write-clear and mash A at the name
-- menu instead of pressing START -- a new stall in place of the old one.
-- A LOADED battle party table only ever holds a real HP, or 0 / $FFFF for
-- a slot nobody is in; $FF00 is neither, and one impossible word condemns
-- the table.
local function inBattle()
  local any = false
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then                 -- empty slot: no opinion
    elseif hp < 10000 then any = true               -- a real party member
    else return false end                           -- impossible: not a table
  end
  return any
end

local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}

local function talkToObj(obj, what, maxF)
  local engaged = false
  local function objAt() return objX(obj), objY(obj) end
  local function adjacent()
    local ox, oy = objAt()
    return math.abs(ox - H.fieldX()) + math.abs(oy - H.fieldY()) == 1
  end
  local apFrame, apPick = -1000, nil
  local function approach()
    if H.frame - apFrame >= 30 then
      apFrame = H.frame
      local ox, oy = objAt()
      apPick = { ox, oy + 1 }
      for _, c in ipairs(NEIGHBOURS) do
        local cx, cy = ox + c[1], oy + c[2]
        if H.bfsPath(cx, cy) then apPick = { cx, cy }; break end
      end
    end
    return apPick
  end
  local function walkStep()
    return H.navTo(function() return approach()[1] end,
                   function() return approach()[2] end, {
      maxFrames = maxF or 20000,
      arrive = function()
        return engaged or (adjacent() and H.hasControl() and H.tileAligned())
      end,
    })
  end
  local function pokeStep(round, budget, hard)
    local started, waited, aPh = 0, 0, 0
    return H.driveUntil(function()
      started = (H.eventRunning() or H.dialogWaiting()) and started + 1 or 0
      if started >= 6 then engaged = true; return true end
      waited = waited + 1
      return not hard and waited > budget
    end, budget + 120, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if not (H.hasControl() and H.tileAligned() and adjacent()) then
          H.setPad({}); return
        end
        local ox, oy = objAt()
        local dx, dy = ox - H.fieldX(), oy - H.fieldY()
        local dir = dx == 1 and "right" or dx == -1 and "left"
                 or dy == 1 and "down" or "up"
        if facing() ~= FACE[dir] then H.setPad({ [dir] = true }); return end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, string.format("%s: activation round %d", what, round))
  end
  return seq({
    H.call(function() engaged, apFrame, apPick = false, -1000, nil end),
    walkStep(), pokeStep(1, 600, false),
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, true) }, {}),
    H.release(),
  })
end

-- No `choice` exists anywhere on this step -- map 117's only prompt is the
-- sealed-chest gag _cb0dbe (:40058) on obj 29 at {45,5}, which the route
-- never touches, and map 120 has none at all.  CHOICES stays empty so an
-- unexpected prompt is a hard failure rather than a blind A-press.
local CHOICES = {}
local ci, inChoice = 0, false
local nameMenus, battles = 0, {}

-- ---------------------------------------------------------- the fighter --
-- The input-driven battle driver (issue #75; gen_scenario's menu-episode
-- machine, reduced to the one policy this step needs): from a settled
-- battle menu
-- (flag $7BCA held 4 straight pulses), one button per 30-frame pulse --
-- boost prefix (R per banked point, dumped at the tier's threshold), then
-- A A = Fight on the default target.  Outside a settled menu, edge-tap A
-- (battle dialogs, victory text).  `tier` >= 2 dumps at 1 BP instead of 2.
local MENU, ACTOR = 0x7BCA, 0x62CA
local BP = 0x3E9C                       -- banked boost points, +slot*2
local fightTier = 1
local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
local lost = nil                        -- set by the loss watch
local bt = nil                          -- live-fight bookkeeping
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(0x3bf4 + e * 2),
      H.readWord(0x3c1c + e * 2))
  end
  return table.concat(p, " ")
end
-- CLOSED-LOOP (2nd pass): the seq machine assumed full-HP parties, and
-- the first input-driven generation of the chain proved fights now carry
-- damage forward between steps (SABIN entered the courtyard at 46/231).  So
-- the fighter reads the engine's own cursor state ($890F/$8947 + actor, the
-- $7BC2 menu state) and steers by pad: boost-and-Fight as before, plus a
-- SELF-HEAL branch under 50% HP funded from the real bag (Potion when >=150
-- HP is missing, else Tonic; battle inventory $2686 stride 5, count at +3
-- -- a zero-count row is never picked).  Item targets default to self, so
-- no target steering is needed here.
local MSTATE = 0x7BC2
local ST_CMD, ST_ITEM, ST_TGT, ST_TOOLS = 0x05, 0x0A, 0x38, 0x30
local CMD_ITEM = 0x01
local CMDTBL, CMDROW = 0x202E, 0x890F
-- the item-list cursor is TWO cells per actor -- scroll ($8947) plus
-- row-on-screen ($894F) -- and the engine's own get_item_poi
-- (btlgfx_main.asm:_c189be) sums them before the *5; reading the scroll
-- alone selected inventory index 4 while the display said 1 (measured,
-- probe_itemuse: the select/deselect toggle that wedged the first
-- input-driven courtyard generation)
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local function itemIdxOf(a)
  return H.readByte(ITEMSCR + a) + H.readByte(ITEMROW + a)
end
local BATTINV = 0x2686
local TONIC, POTION = 0xE8, 0xE9
local function pHPf(e) return H.readWord(0x3BF4 + e * 2) end
local function pMaxHPf(e) return H.readWord(0x3C1C + e * 2) end
local function battItemIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id
       and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end
local function cmdRowOf(actor, cmdId)
  for i = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + i * 3) == cmdId then return i end
  end
  return nil
end
local fPlan, fPlanActor, fBtn = nil, nil, nil
local fTick, fStreak = 0, 0
local function makeFightPlan(actor)
  local hp, mx = pHPf(actor), pMaxHPf(actor)
  local itemRow = cmdRowOf(actor, CMD_ITEM)
  -- heal under 60%, and reach for the Potion once 100+ HP is missing: the
  -- pursuit measured 4 attackers out-damaging a 50-HP Tonic line
  if mx > 0 and hp > 0 and hp * 10 < mx * 6 and itemRow then
    local id = nil
    if mx - hp >= 100 and battItemIdx(POTION) then id = POTION
    elseif battItemIdx(TONIC) then id = TONIC
    elseif battItemIdx(POTION) then id = POTION end
    if id then
      H.log(string.format("camp: heal f%d e%d %s (hp %d/%d) [%s]",
        H.frame, actor, id == TONIC and "TONIC" or "POTION", hp, mx,
        partyLine()))
      return { kind = "item", item = id, row = itemRow }
    end
  end
  local bp = H.readByte(BP + actor * 2)
  -- dump banked boost EVERY turn: these are 1-2 member steps where a dead
  -- enemy is the only mitigation, and the pursuit measured bank-to-2
  -- losing the tempo war against four attackers
  local boost = bp >= 1 and math.min(bp, 3) or 0
  H.log(string.format("camp: cast f%d e%d boost=%d tier=%d [%s]",
    H.frame, actor, boost, fightTier, partyLine()))
  return { kind = "fight", boostLeft = boost }
end
local function fightButton()
  local st = H.readByte(MSTATE)
  local actor = H.readByte(ACTOR)
  if fPlan == nil or fPlanActor ~= actor then
    if st ~= ST_CMD then
      -- planless in a parked LIST state: back out to the command list
      -- (the b68 engine measured a menu reopening straight into a list)
      if st == ST_TOOLS or st == ST_ITEM or st == ST_TGT then
        return { "b" }
      end
      return nil
    end
    fPlan, fPlanActor = makeFightPlan(actor), actor
    return nil
  end
  local plan = fPlan
  if st == ST_CMD then
    if plan.kind == "fight" then
      if plan.boostLeft > 0 then
        plan.boostLeft = plan.boostLeft - 1
        return { "r" }
      end
      local cur = H.readByte(CMDROW + actor) & 3
      if cur ~= 0 then return { "up" } end
      return { "a" }
    end
    local cur = H.readByte(CMDROW + actor) & 3
    if cur == plan.row then return { "a" } end
    if plan.rowStall and plan.rowStall > 2 then
      plan.rowStall = 0
      return { ({ [0]="up", [1]="left", [2]="right", [3]="down" })[plan.row] }
    end
    plan.rowStall = (plan.rowStall or 0) + 1
    return { cur < plan.row and "down" or "up" }
  end
  if st == ST_ITEM and plan.kind == "item" then
    local want = battItemIdx(plan.item)
    if want == nil then return { "b" } end
    local cur = itemIdxOf(actor)
    if cur < want then return { "down" } end
    if cur > want then return { "up" } end
    return { "a" }
  end
  if st == ST_TGT then
    fPlan, fPlanActor = nil, nil
    return { "a" }          -- item: default self; Fight: default enemy
  end
  if st == ST_TOOLS then return { "b" } end
  return nil
end
local fHeld, fHb = 0, -300
local function fightPulse(_)
  if H.readByte(MENU) == 0 then
    fPlan, fPlanActor, fStreak, fHeld = nil, nil, 0, 0
    fTick = fTick + 1
    H.setPad(fTick % 8 < 4 and { "a" } or {})
    return
  end
  fStreak = fStreak + 1
  if fStreak < 4 then H.setPad({}); return end
  fTick = fTick + 1
  -- the fighter's own heartbeat: menu state, cursor cells, plan -- the
  -- numbers a wedge diagnosis needs (300-frame cadence)
  if H.frame - fHb >= 300 then
    fHb = H.frame
    local a = H.readByte(ACTOR)
    H.log(string.format("camp: fmenu f%d st=%02X actor=%d row=%d itm=%d " ..
      "plan=%s held=%d [%s]", H.frame, H.readByte(MSTATE), a,
      H.readByte(CMDROW + a) & 3, itemIdxOf(a),
      fPlan and fPlan.kind or "-", fHeld, partyLine()))
  end
  -- stall recovery: a plan that cannot finish in 40 pulses is backed out
  -- (B) and rebuilt from whatever the cursor shows -- progress over
  -- elegance, the house idiom
  local ph = fTick % 30
  if ph == 0 then
    if fPlan ~= nil then
      fHeld = fHeld + 1
      if fHeld > 40 then
        H.log(string.format("camp: plan stalled 40 pulses (st=%02X) -- " ..
          "backing out", H.frame and H.readByte(MSTATE) or 0))
        fPlan, fPlanActor, fHeld = nil, nil, 0
        fBtn = { "b" }
        H.setPad(fBtn)
        return
      end
    else
      fHeld = 0
    end
    fBtn = fightButton()
  end
  H.setPad(ph < 6 and fBtn or {})
end
-- the loss watch: every party slot with a real max HP sitting at 0 -- for
-- CYAN's solo defence that is just him -- held 90 straight frames (past any
-- mid-round revive).  Sets `lost` for the ladder; never raises mid-fight.
local function lossWatch(tag)
  local wiped = true
  for e = 0, 3 do
    if H.readWord(0x3c1c + e * 2) > 0 and H.readWord(0x3bf4 + e * 2) > 0 then
      wiped = false
    end
  end
  bt.dead = wiped and bt.dead + 1 or 0
  if bt.dead >= 90 and not lost then
    lost = string.format("%s: party down at f%d (fight up f%d, tier %d) [%s]",
      tag, H.frame, bt.f0, fightTier, partyLine())
    H.log("camp: LOST -- " .. lost)
    H.screenshot("camp_lost")
  end
end

local function rideUntil(pred, what, budget)
  local phase, battN, dlgN, quiet, hb = 0, 0, 0, 0, -900
  return H.driveUntil(pred, budget or 40000, {
    H.call(function()
      phase = (phase + 1) % 8
      -- THE MAP IS IN THE HEARTBEAT.  Run 1's log had everything except
      -- the one field that would have explained it.
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format("camp f%d map=%d (%d,%d) face=%d ctl=%s dlg=%s " ..
          "batt=%s ev=%s br=%d menu=%d/%d $02E2=%d | evpc=%02X%02X%02X " ..
          "$0084=%02X $087C=%02X $00BA=%02X $00D3=%02X $0026=%02X " ..
          "$0027=%02X hp0=%04X mon=%d",
          H.frame, map(), H.fieldX(), H.fieldY(), facing(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle()), tostring(H.eventRunning()),
          bright(), H.readByte(NAME_MENU), H.readByte(0x0059), sw(0x02E2),
          H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
          H.readByte(0x0084), H.readByte(0x087c + H.readWord(0x0803)),
          H.readByte(0x00ba), H.readByte(0x00d3), H.readByte(0x0026),
          H.readByte(0x0027), H.readWord(0x3bf6), monCount()))
      end

      battN = inBattle() and battN + 1 or 0
      dlgN  = H.dialogWaiting() and dlgN + 1 or 0

      local chMax = (battN == 0) and H.readByte(CH_MAX) or 0
      if chMax >= 2 then
        quiet = 0
        if not H.dialogWaiting() then H.setPad({}); return end
        if not inChoice then
          inChoice = true
          ci = ci + 1
          if not CHOICES[ci] then
            error(string.format("camp: unexpected choice prompt (%d options) " ..
              "on map %d at (%d,%d) -- this segment expects none",
              chMax, map(), H.fieldX(), H.fieldY()), 0)
          end
        end
        local c, sel = CHOICES[ci], H.readByte(CH_SEL)
        if sel < c.want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > c.want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      elseif inChoice then
        inChoice = false
      end

      if battN >= 3 then
        quiet = 0
        if battN == 3 then
          local w = H.formationWords()
          battles[#battles + 1] = string.format("map%d:%04X/%d",
            map(), w[1], monCount())
          bt = { f0 = H.frame, dead = 0 }
          H.log(string.format("camp: battle up f%d map=%d present=%d " ..
            "(%04X %04X %04X %04X %04X %04X) php=%04X %04X %04X %04X",
            H.frame, map(), monCount(), w[1], w[2], w[3], w[4], w[5], w[6],
            H.readWord(0x3bf4), H.readWord(0x3bf6), H.readWord(0x3bf8),
            H.readWord(0x3bfa)))
          for i = 0, 5 do
            if monPresent(i) then
              H.log(string.format("   slot %d species $%04X hp=%d shields=%d",
                i, monSpecies(i), monHp(i), monShields(i)))
            end
          end
        end
        -- A SCRIPT BATTLE (zero monsters present) has nothing to fight
        -- and ends on its character-AI script's own schedule.  Hands off
        -- for 300 frames, then edge-tap A to advance its text.
        if monCount() == 0 then
          H.setPad(battN > 300 and phase < 4 and { "a" } or {})
          return
        end
        -- a REAL fight: play it (boosted Fights) and watch for the loss
        if bt then
          if battN % 300 == 0 then
            H.log(string.format("camp: fight f%d party [%s] vs $%04X hp=%d",
              H.frame, partyLine(), monSpecies(0), monHp(0)))
          end
          lossWatch(what)
          if lost then H.setPad({}); return end
        end
        fightPulse(phase)
        return
      end
      if bt then bt = nil end

      if dlgN >= 3 then quiet = 0; H.setPad(phase < 4 and { "a" } or {}); return end

      -- THE NAME MENU, detected on the MENU MODULE'S OWN STATE.  $0200 == 1
      -- is event command $98's marker (field/event.asm:3607) but goes stale
      -- the moment the menu closes, and $0059 ~= 0 is true of a good deal
      -- more than menus -- it read 82 mid-cutscene on map 120 in run 2 of
      -- this file.  The precise term is zMenuState/zNextMenuState == $5F
      -- (menu_ram.inc:112-113 at direct-page $26/$27; $5F is what
      -- MenuState_5d parks in, name_change.asm:60-61).  Either byte serves:
      -- during the menu's fade-in the state is still FADE_IN and only
      -- zNextMenuState reads $5F.
      if H.readByte(NAME_MENU) == 1 and H.readByte(0x0059) ~= 0
         and (H.readByte(0x0026) == 0x5F or H.readByte(0x0027) == 0x5F) then
        quiet = quiet + 1
        if quiet >= 30 then
          if quiet == 30 then
            nameMenus = nameMenus + 1
            H.log(string.format("camp: NAME MENU #%d at f%d (map %d) -- START",
              nameMenus, H.frame, map()))
          end
          H.setPad(phase < 4 and { "start" } or {})
          return
        end
        H.setPad({})
        return
      end
      quiet = 0

      H.setPad({})
    end),
  }, what)
end

local function landedField(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not inBattle()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d): map=%d ctl=%s algn=%s br=%d batt=%s",
        m, map(), tostring(H.hasControl()), tostring(H.tileAligned()),
        bright(), tostring(inBattle())))
    end
    return cnt >= n
  end
end

-- ------------------------------------------------------ the retry ladder --
-- One commander attempt: (attempt 2+) reload the checkpoint with a small
-- stagger, reset the fighter to the escalated tier, poke the commander, and
-- ride the fight + interlude tail back to the camp.  `lost` short-circuits
-- the ride so the next attempt starts promptly instead of timing out at the
-- parked event PC.
local cmdBlob, cmdWon = nil, false
local function cmdAttempt(n)
  local ldReq
  return H.cond(function() return not cmdWon end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("camp: ATTEMPT %d -- reloading the commander " ..
          "checkpoint after a loss (%s)", n, tostring(lost))
      end),
      H.call(function() ldReq = H.requestLoadState(cmdBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "attempt " .. n .. ": reload") end),
      H.waitFrames(60 + (n - 1) * 17),  -- the stagger shifts every later roll
    }, {}),
    H.call(function() lost, fightTier = nil, n end),
    talkToObj(16, "the Imperial commander (_cb9eb5, battle 46)", 20000),
    (function()
      local landedPred = function()
        return map() == 117 and sw(0x02E2) == 1 and H.hasControl()
           and H.tileAligned() and bright() >= 15
      end
      local frames = 0
      return rideUntil(function()
        frames = frames + 1
        if frames > 29000 and lost == nil then
          lost = string.format("attempt %d deadline (29000 frames) -- " ..
            "assumed wiped or wedged [%s]", n, partyLine())
          H.log("camp: LOST -- " .. lost)
        end
        return lost ~= nil or landedPred()
      end, "back in the camp as SABIN (attempt " .. n .. ")", 30000)
    end)(),
    H.release(),
    H.waitFrames(30),
    H.call(function()
      if lost == nil then
        cmdWon = true
        H.log(string.format("camp: attempt %d WON battle 46", n))
      end
    end),
  }, {})
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 117, "booted on map 117, the Imperial Camp")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(3), true, "SHADOW in the party")
    H.assertEq(sw(0x02E2), 0, "$02E2 clear -- the gate scene has not played")
    H.log(string.format("[camp] f%d at (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
  end),

  -- ==================================================================== --
  -- 1. ONE STEP SOUTH, AND THE GAME IS CYAN'S.  navTo's job here is only
  -- to reach (36,3); the arrive check is the MAP CHANGING, because the
  -- trigger takes control on the same frame the party lands and navTo's own
  -- terminator (on the tile, with control) can never be satisfied.
  -- ==================================================================== --
  H.navTo(36, 3, {
    maxFrames = 3000,
    arrive = function() return map() ~= 117 end,
  }),
  rideUntil(landedField(120, 10), "CYAN at DOMA (map 120)", 30000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 120, "map 120 -- DOMA CASTLE interior, CYAN's defence")
    H.assertEq(inParty(2), true, "CYAN is the party")
    H.assertEq(inParty(5), false, "SABIN is out")
    H.assertEq(nameMenus, 1, "one name menu so far (CYAN, :61204)")
    H.log(string.format("[doma] f%d CYAN at (%d,%d); commander obj 16 " ..
      "at (%d,%d)", H.frame, H.fieldX(), H.fieldY(), objX(16), objY(16)))
    H.screenshot("cyan_defence")
  end),
  H.saveState("cyan_defence.mss"),

  -- ==================================================================== --
  -- 2. THE COMMANDER.  obj 16, parked on (33,54) by :61266-61269.  Its
  -- `battle 46` is event battle GROUP 46 = formation 409 = one $14e
  -- (event_battle_group.dat, 4 bytes/group).  Fought for REAL (see the
  -- header), behind a three-attempt retry ladder on the cyan_defence-
  -- moment checkpoint: a loss reloads and re-pokes with the fighter
  -- escalated (tier 2+ dumps boost at 1 BP) plus a small reload stagger,
  -- which reshuffles every subsequent interleaving and roll.
  -- ==================================================================== --
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "commander checkpoint")
        cmdBlob = ckReq.blob
        H.log(string.format("camp: commander checkpoint captured (%d bytes) " ..
          "at f%d", #cmdBlob, H.frame))
      end),
    })
  end)(),
  cmdAttempt(1),
  cmdAttempt(2),
  cmdAttempt(3),
  H.call(function()
    if not cmdWon then
      error(string.format("camp: CYAN lost battle 46 on all 3 " ..
        "attempts -- last loss: %s -- the per-attempt numbers above are " ..
        "the balance finding (#74-style); do not rig this segment",
        tostring(lost)), 0)
    end
  end),
  -- STEP OFF THE TRIGGER BEFORE GENERATING.  _cb0bc4 puts the party back on
  -- (36,2) and walks it DOWN 1, so it comes to rest on (36,3) -- which is
  -- _cb0c2f's own trigger tile.  CheckEventTriggers (field/event.asm:5740)
  -- has no once-per-tile latch: it re-fires every frame the party stands
  -- there, and although $02E2 now makes the script an immediate
  -- EventReturn, each firing still flips $087C to 4 for a frame or two.
  -- hasControl() therefore FLAPS -- measured, run 5: the 900-frame
  -- heartbeat read ctl=true while landedField's every-frame sample read
  -- ctl=false, and "10 consecutive settled frames" never once happened in
  -- 6,000.  (36,5) is two tiles south, off every trigger on the map and on
  -- the road the next step takes anyway.
  H.navTo(36, 5, { maxFrames = 4000 }),
  rideUntil(landedField(117, 10), "camp control settled off the trigger", 6000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 117, "map 117 -- back in the Imperial Camp")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(inBattle(), false, "no battle")
    H.assertEq(inParty(5), true, "SABIN is the party again")
    H.assertEq(inParty(3), true, "SHADOW too")
    H.assertEq(inParty(2), false, "CYAN is out again")
    -- $02E2 is the gate scene's own latch: _cb0c2f/_cb0c47/_cb0c5e all open
    -- `if_switch $02E2=1, EventReturn` (:39786, :39797, :39807), so with it
    -- set the three gate tiles are inert and the next step can walk south
    -- across them without replaying the interlude.
    H.assertEq(sw(0x02E2), 1, "$02E2 set -- the gate tiles are inert now")
    H.assertEq(sw(0x002B), 0, "$002B clear -- the LEO scene is still ahead")
    H.assertEq(sw(0x0044), 0, "$0044 clear -- the scenario is not done")
    H.log("[camp] battles seen: " .. table.concat(battles, " "))
    for c = 0, 15 do
      if inParty(c) then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base + 8), H.readWord(base + 9),
          H.readWord(base + 11), H.readWord(base + 13),
          H.readWord(base + 15)))
      end
    end
    H.log(string.format("[camp_intro] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("camp_intro")
  end),
  H.saveState("camp_intro.mss"),
  H.logStep(function()
    return string.format("camp_intro generated at frame %d", H.frame)
  end),
})
