-- gen_sabin_train.lua -- leg 8 of SABIN's scenario: the Phantom Train,
-- boarding to the Ghost Train's fall.  Mints:
--   train_done.mss   World of Balance (178,93), on foot, $003A/$003B set,
--                    SABIN+CYAN+SHADOW -- the Baren Falls leg builds here.
--
-- THE MAZE, as measured (probe_train, probe_train2, probe_train3 -- the
-- floods and the trap forensics live in their headers and commits):
--
--  * The train is TWO exterior side-view strips (142 rear, 141 front) and a
--    handful of interior maps REUSED per physical car -- 145 plays car A
--    ($017E=$0180=0), car B ($017E=1) and car C ($0180=1); $0506/$0507/
--    $0509 pick each car's ghost cast.  $017E/$0180 are car bookkeeping
--    written by every door handler, not a puzzle.  The door "gates"
--    $01B0-$01B4 are UpdateCtrlFlags' live facing/A bits
--    (field/event.asm:5416), so levers/valves fire on facing-up+A.
--  * The forward walk is plain floor: car A's west door lands 142 (66,8)
--    and the y=8 strip reaches (58,8) = car B's east door.  (The old
--    "isolated cluster" claim was measured only from the EAST pocket.)
--  * Car C is entered by its SIDE door, 142 (41,8) facing up (_cba67d:
--    $0180=1, $0509=1).  Walking in fires _cbb399, which RELOCATES the trap
--    ghost from (3,6) to the south door; talking to it at (26,9) facing
--    down runs _cbb265: $017C=1, battle 47, and a hard load to the mob
--    surround at 142 (41,9).  Roof at x=40, west to (34,5) = SABIN's jump
--    (lands (12,8)), mob catch at (11,8) ($0182), car 149 at (10,8).
--  * 149's east vestibule (x=27-31) holds the lever at (28,5).  Pull ONE:
--    $0183, the detach cinematic, hard landing 141 (117,8).  Pull TWO
--    (after re-entering) is the maze's last secret: _cbb7c7 sets $017F and
--    re-tiles the x=26 column -- the inner door between vestibule and car.
--  * From 141 (108,8) THE STRIP IS THE ROUTE: lanes y=8/y=9 weave under
--    the door pockets, the roof (y=5, ladders x=60/65/76/81) bridges the
--    two ground gaps, and no car interior is entered (wrapping tile props
--    poison the BFS).  Waypoints dodge the unguarded door triggers;
--    (55,8)'s ghost-leave event is a measured no-op for a ghostless party.
--  * Engineer door 141 (38,8) accepts entry only from (38,9) facing up.
--    Valves (7,7)/(9,7) toggle $0184/$0186; SHUT/OPEN/SHUT is the
--    smokestack's guard.  (32,7) facing-up+A -> _cbb9d4 -> battle 68.
--
-- ============ ISSUE #75 / #74 -- THE FIGHT IS PLAYED FOR REAL ============
-- Zero state writes in this generator.  The old file was the heaviest
-- cheat load in the repo: HP/MP pins every frame, stop-bits freezing
-- everyone but SABIN, the train clamped to 1 HP, menu-cursor pokes, and a
-- $1DD2 SHADOW pin.  All of it is gone.  What replaced it:
--
--  * RANDOM/UNGATED BATTLES ARE FLED (hold L+R; navTo honest="flee").  A
--    fled battle is not a WIN, and SHADOW's 1/16 post-battle walk-off
--    (battle_main.asm:11976-11991; $4B story-CLEAR through the train until
--    the jump-off scene re-sets it, :63061) rolls only at a win -- so the
--    corridors roll nothing.
--  * BATTLE 47 (the trap ghost; win-gated by _ca5ea9) is fought by the
--    house menu-episode machine: everyone banks boost to 2 and dumps it on
--    Fight.  Its WIN does roll SHADOW's 1/16, and a wipe is a GameOver
--    park, so the fight sits behind a three-attempt retry ladder on a
--    checkpoint taken before the talk: a loss OR a walked-off SHADOW
--    reloads with a 17-frame stagger (a different timeline, a different
--    roll) -- the TAS discipline #75 names for exactly this leg.
--  * BATTLE 68 (the Ghost Train) runs THE PACIFIST LINE, #74's only
--    winning strategy at shipped tuning: SABIN chips one shield per round
--    (AuraBolt, 10 MP, the holy chip -- falling back to Pummel, 4 MP, the
--    bludgeon chip, whenever AuraBolt would leave the REMAINING chips
--    unfundable), while CYAN and SHADOW deal ZERO damage and play medic
--    with items bought from the GHOST MERCHANT (car B, obj 29, shop 85:
--    Tonics and Potions -- his stock has no Tincture and no skeans, which
--    is #74's finding restated as inventory).  Fenix Down is never
--    selected: the mint's proof obligation is the BREAK LOOP, not the
--    cheese path.  Boost is deliberately withheld from SABIN pre-break --
--    a boosted chip's extra damage spends the very HP budget the 6-chip
--    break needs to fit inside (1900 HP vs ~155-195/chip).  Once shields
--    hit 0 with the train still alive -- the leg's proof obligation,
--    asserted -- everyone dumps banked boost on Fight and the Broken
--    window finishes it.  Every SABIN cast and every medic turn is logged
--    with HP/MP/shield numbers; if SABIN's pool cannot fund the remaining
--    chips even at Pummel prices, the mint FAILS LOUDLY with the exact
--    arithmetic -- a #74 data point, never a rig.  The fight sits behind
--    the same three-attempt ladder (wipe or SHADOW walk-off reloads the
--    pre-smokestack checkpoint with a stagger).
--
-- THE RIDE OUT: victory scene -> the souls' station (Cyan's family) ->
-- map 137 with a 1200-frame timer -> auto-exit to the world at (178,93),
-- SHADOW steps out for the graveside beat and rejoins before the exit
-- (_cbbedd/_cbbee5).
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/forest_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end

-- battle model (battle_vargas's map; every address is READ-only here)
local GHOSTTRAIN = 0x0106
local OT6_BLUDG, HOLY = 0x04, 0x20
local PUMMEL, AURABOLT = 0x5D, 0x5E
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS = 0x05, 0x30     -- command list; tools-shell blitz list
local ST_ITEM, ST_TGT = 0x0A, 0x38      -- item select; target select
local CMD_BLITZ, CMD_ITEM = 0x0A, 0x01
local CMDTBL, ITEMLIST = 0x202E, 0x4005 -- command cells; wItemList rows
local BATTINV = 0x2686                  -- battle inventory, 5 bytes/entry
local CMDROW = 0x890F                   -- +actor: command-list cursor row
local BLSCROLL, BLCOL, BLROW = 0x895F, 0x8963, 0x8967  -- +actor: 2-col grids
-- the item-list cursor is TWO cells per actor: scroll ($8947) + row-on-
-- screen ($894F); get_item_poi (_c189be) sums them (measured the hard
-- way -- probe_itemuse)
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E -- live target-cursor masks
local BP = 0x3E9C                       -- banked boost points, +slot*2
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
-- #33 pending-reveal cells, entity-offset stride (see battle_vargas)
local function RVPE(s) return 0xED45 + s * 2 end
local function RVPC(s) return 0xED51 + s * 2 end
local function MHP(s) return 0x3BFC + s * 2 end
local function monPresent(s) return H.readByte(0x3aa8 + s * 2) % 2 == 1 end
local function pHP(e) return H.readWord(0x3BF4 + e * 2) end
local function pMaxHP(e) return H.readWord(0x3C1C + e * 2) end
local function pMP(e) return H.readWord(0x3C08 + e * 2) end
local function gil()
  return H.readByte(0x1860) + (H.readByte(0x1861) << 8)
       + (H.readByte(0x1862) << 16)
end
local function invCount(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return H.readByte(0x1969 + i) end
  end
  return 0
end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d(%dmp)", pHP(e), pMaxHP(e), pMP(e))
  end
  return table.concat(p, " ")
end

local gSlot, sabinE, cyanE, shadowE = nil, nil, nil, nil

local function cmdRowOf(actor, cmdId)
  for i = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + i * 3) == cmdId then return i end
  end
  return nil
end
local function battInvIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id
       and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end

-- navTo, always fleeing (the corridor discipline -- see the header)
local function nav(x, y, o)
  o = o or {}
  o.honest = "flee"
  return H.navTo(x, y, o)
end

local function swDump(tag)
  H.log(string.format(
    "[train %s] map=%d (%d,%d) $0039=%d $017C=%d $017E=%d $017F=%d "..
    "$0180=%d $0182=%d $0183=%d $0184=%d $0185=%d $0186=%d $003A=%d $003B=%d "..
    "shdw=%s/$1dd2=%02X/av=%02X gil=%d",
    tag, mapIdx(), H.fieldX(), H.fieldY(), sw(0x39), sw(0x17C), sw(0x17E),
    sw(0x17F), sw(0x180), sw(0x182), sw(0x183), sw(0x184), sw(0x185),
    sw(0x186), sw(0x3A), sw(0x3B),
    tostring(inParty(3)), H.readByte(0x1dd2), H.readByte(0x1ede), gil()))
end

-- ------------------------------------------------ the b47 fighter (+topup) --
-- The closed-loop engine (the leg fighters' second-pass machine), with one
-- b47-specific doctrine: THE FIGHT IS ALSO THE INFIRMARY.  The party walks
-- into battle 68 with whatever HP it leaves the maze carrying, and the
-- first honest run measured that entry at ~25% -- the pacifist line then
-- lost the attrition war before the 6th chip (SABIN down at chip 3, both
-- wipes inside 4000 frames).  A player heals before a boss; the only
-- healing surface this leg owns is a battle menu, so battle 47 does it:
-- any member under 95% gets a Tonic/Potion INSTEAD of a Fight, and the
-- trap ghosts only die once everyone is topped.  Capped at 24 heal turns
-- so a bad interleaving cannot prolong the fight forever.
local fightTier = 1
local lost = nil
local wipeN = 0
local b47Heals = 0
local fPlan, fPlanActor, fBtn = nil, nil, nil
local fTick, fStreak = 0, 0
local fHb = -300
local function makeB47Plan(actor)
  local hp, mx = pHP(actor), pMaxHP(actor)
  local itemRow = nil
  for i = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + i * 3) == CMD_ITEM then itemRow = i end
  end
  -- top up the neediest LIVING member (self-target only heals the actor,
  -- so each actor tops itself; the rotation covers everyone)
  if mx > 0 and hp > 0 and hp * 20 < mx * 19 and itemRow
     and b47Heals < 24 then
    local miss = mx - hp
    local id = nil
    if miss >= 100 and battInvIdx(POTION) then id = POTION
    elseif battInvIdx(TONIC) then id = TONIC
    elseif battInvIdx(POTION) then id = POTION end
    if id then
      b47Heals = b47Heals + 1
      H.log(string.format("[b47] topup %d: e%d %s (hp %d/%d) [%s]",
        b47Heals, actor, id == TONIC and "TONIC" or "POTION", hp, mx,
        partyLine()))
      return { kind = "item", item = id, row = itemRow }
    end
  end
  local bp = H.readByte(BP + actor * 2)
  local boost = bp >= 1 and math.min(bp, 3) or 0
  H.log(string.format("[b47] cast f%d e%d boost=%d tier=%d [%s]",
    H.frame, actor, boost, fightTier, partyLine()))
  return { kind = "fight", boostLeft = boost }
end
local function b47Button()
  local st = H.readByte(MSTATE)
  local actor = H.readByte(ACTOR)
  if fPlan == nil or fPlanActor ~= actor then
    if st ~= ST_CMD then
      if st == ST_TOOLS or st == ST_ITEM or st == ST_TGT then
        return { "b" }
      end
      return nil
    end
    fPlan, fPlanActor = makeB47Plan(actor), actor
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
    local want = battInvIdx(plan.item)
    if want == nil then return { "b" } end
    local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
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
local function fightPulse(_)
  if H.readByte(MENU) == 0 then
    fPlan, fPlanActor, fStreak = nil, nil, 0
    fTick = fTick + 1
    H.setPad(fTick % 8 < 4 and { "a" } or {})
    return
  end
  fStreak = fStreak + 1
  if fStreak < 4 then H.setPad({}); return end
  fTick = fTick + 1
  if H.frame - fHb >= 300 then
    fHb = H.frame
    local a = H.readByte(ACTOR)
    H.log(string.format("[b47] fmenu f%d st=%02X actor=%d row=%d plan=%s [%s]",
      H.frame, H.readByte(MSTATE), a, H.readByte(CMDROW + a) & 3,
      fPlan and fPlan.kind or "-", partyLine()))
  end
  local ph = fTick % 30
  if ph == 0 then fBtn = b47Button() end
  H.setPad(ph < 6 and fBtn or {})
end
local function wipeWatch(tag)
  local wiped = true
  for e = 0, 3 do
    if pMaxHP(e) > 0 and pHP(e) > 0 then wiped = false end
  end
  wipeN = wiped and wipeN + 1 or 0
  if wipeN >= 90 and not lost then
    lost = string.format("%s: PARTY WIPED at f%d (tier %d) [%s]",
      tag, H.frame, fightTier, partyLine())
    H.log("[train] LOST -- " .. lost)
    H.screenshot("train_lost")
  end
end

-- holdDrive: hold `dir` toward pred; dialogs tap-A; battles either FLEE
-- (default -- corridor trash earns no win and no SHADOW roll) or FIGHT
-- ("fight": the boost machine + wipe watch, for the win-gated battle 47).
local function holdDrive(dir, pred, what, budget, fightMode)
  local phase, hb = 0, -600
  return H.driveUntil(pred, budget or 15000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("drive[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s b=%s",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle())))
      end
      if inBattle() or H.battleLoadStarted() then
        if fightMode == "fight" then
          wipeWatch(what)
          if lost then H.setPad({}); return end
          fightPulse(phase)
        else
          H.setPad({ l = true, r = true })   -- flee, honestly
        end
        return
      end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- facing-up+A until pred: the lever/valve/switch idiom ($01B0/$01B4 are
-- live facing/A bits, re-checked every aligned frame)
local function upA(pred, what, budget)
  local phase = 0
  return H.driveUntil(pred, budget or 3000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad(phase < 4 and { "up", "a" } or { "up" })
    end),
  }, what)
end

local function settle(toMap, what)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 4000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function() swDump(what) end),
  }, {})
end

-- --------------------------------------------------- the ghost merchant --
-- Car B (map 145, $017E=1) carries NPC_14 = object 29, visibility switch
-- $0567 (set by the departure scene): "Howdy, folks.  I have some great,
-- value-priced items!" -- _cbad44, dlg $02D0, choice 0 = shop_menu 85.
-- Stock (menu/shop_prop.dat record 85): TONIC, POTION, ANTIDOTE, GREEN
-- CHERRY, FENIX DOWN, SLEEPING BAG, $41.  NO TINCTURE -- SABIN's MP pool
-- is the whole break budget, which is #74's arithmetic made concrete.
--
-- HAZARD, decoded before driving: car B's OTHER ghosts at {6,8}/{23,6}
-- (objects 22/23, _cbaadd/_cbaae8) open "Bring it along?" where OPTION 0
-- JOINS THE GHOST to the party.  The choice handler therefore keys on the
-- live dialog index ($00D0 & $1FFF, field/event.asm:1762): $02D0 gets
-- option 0 (shop), anything else gets option 1 (refuse).  Wrong-ghost
-- talks are thus harmless re-pokes, never a party change.
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local FACE = { up = 0, right = 1, down = 2, left = 3 }
local function dlgId() return H.readWord(0x00d0) & 0x1FFF end
local CH_SEL, CH_MAX = 0x056E, 0x056F
local function mstateMenu() return H.readByte(0x0026) end

-- open the merchant's shop: chase obj 29, poke, steer the $02D0 choice to
-- 0 (and any other choice to 1), until the menu module reads shop-options
local function openShop()
  local phase = 0
  return H.driveUntil(function() return mstateMenu() == 0x25 end, 20000, {
    H.call(function()
      phase = (phase + 1) % 8
      if inBattle() or H.battleLoadStarted() then
        H.setPad({ l = true, r = true })
        return
      end
      -- a choice is open: pick by dialog id (see the hazard note)
      if H.dialogWaiting() and H.readByte(CH_MAX) >= 2 then
        local want = dlgId() == 0x02D0 and 0 or 1
        local sel = H.readByte(CH_SEL)
        if sel < want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local ox, oy = objX(29), objY(29)
      local dx, dy = ox - H.fieldX(), oy - H.fieldY()
      if math.abs(dx) + math.abs(dy) == 1 then
        local dir = dx == 1 and "right" or dx == -1 and "left"
                 or dy == 1 and "down" or "up"
        if facing() ~= FACE[dir] then H.setPad({ [dir] = true }); return end
        H.setPad(phase < 4 and { "a" } or {})
        return
      end
      -- step toward the wanderer: first step of the shortest path to any
      -- neighbouring tile (re-planned every pulse; he moves)
      local best, bd = nil, nil
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { -1, 0 }, { 1, 0 } }) do
        local p = H.bfsPath(ox + d[1], oy + d[2])
        if p and #p > 0 and (not bd or #p < bd) then best, bd = p, #p end
      end
      H.setPad(best and { [H.movePress(best[1])] = true } or {})
    end),
  }, "the ghost merchant's shop opens")
end

-- buy `qtyFn()` MORE of shop row `row`, fully CLOSED-LOOP: the list
-- cursor row is MoveCursor's own cell (DP $4E, menu_common.asm:1318) and
-- the quantity is zSelIndex (DP $28, menu_ram.inc) -- both read and
-- steered, never press-counted (menu direction holds auto-repeat: a
-- counted 4-frame hold measurably bought 25 Tonics instead of 14 and
-- parked the potion lap on the wrong row).  Widget deltas (shop.asm
-- MenuState_27): RIGHT +1, LEFT -1, UP +10, DOWN -10, gil-clamped by the
-- handler.  Purchases are verified AFTER the shop closes; mid-menu
-- inventory reads measurably lie.
local function buyItem(id, row, qtyFn, name)
  local phase = 0
  local seen27, bought = false, false
  local want = nil
  return H.driveUntil(function() return bought end, 20000, {
    H.call(function()
      phase = (phase + 1) % 8
      local st = mstateMenu()
      if want == nil then
        want = qtyFn()
        if want < 1 then want = 1 end
        H.log(string.format("[shop] %s: buying %d", name, want))
      end
      if st == 0x27 then
        seen27 = true
        local qty = H.readByte(0x0028)
        local btn = nil
        if qty < want then
          btn = (want - qty >= 10) and "up" or "right"
        elseif qty > want then
          btn = (qty - want >= 10) and "down" or "left"
        else
          btn = "a"
        end
        H.setPad(phase < 2 and { [btn] = true } or {})
      elseif seen27 then
        bought = true
        H.setPad({})
      elseif st == 0x25 then
        H.setPad(phase < 2 and { "a" } or {})
      elseif st == 0x26 then
        local cur = H.readByte(0x004E)
        local btn = cur < row and "down" or cur > row and "up" or "a"
        H.setPad(phase < 2 and { [btn] = true } or {})
      else
        H.setPad({})
      end
    end),
  }, "buy " .. name)
end

local function closeShop()
  local phase = 0
  return H.driveUntil(function()
    return H.hasControl() and mstateMenu() ~= 0x25 and mstateMenu() ~= 0x26
       and mstateMenu() ~= 0x27
  end, 6000, {
    H.call(function()
      phase = (phase + 1) % 8
      H.setPad(phase < 4 and { "b" } or {})
    end),
  }, "shop closed")
end

-- ------------------------------------------- battle 68: the pacifist line --
-- The per-turn engine.  One button per 30-frame pulse, every press decided
-- CLOSED-LOOP from the live menu state (command cursor $890F+actor, blitz
-- grid $895F/$8963/$8967+actor, item index $8947+actor, target masks
-- $7B7D/$7B7E) -- steering by d-pad, confirming with A, never poking a
-- cursor cell.  Plans are built fresh at each actor's settled command menu:
--   SABIN  shields>0: AuraBolt while the REMAINING chips stay fundable
--          (mp-10 >= 4*(chips-1)), else Pummel (4 MP, the bludgeon chip);
--          mp<4 with shields up = the measured-IMPOSSIBLE branch: log the
--          arithmetic and fail -- a #74 data point, never a rig.
--          shields==0 (BROKEN, train alive): dump banked boost on Fight.
--   MEDICS shields>0: Tonic/Potion on the neediest living member (Potion
--          when >=150 HP is missing and one is in the bag); Fenix Down is
--          NEVER picked; with the bag empty they Fight and say so loudly.
--          shields==0: dump boost on Fight -- the break is complete, the
--          proof obligation met, and the Broken window wants damage.
local b68 = {
  casts = 0, chips = {}, plan = nil, planActor = nil,
  brokeAt = nil, impossible = nil, itemsOut = false,
  lastSH, lastHP,
}
local function b68Log(msg) H.log("[b68] " .. msg) end
-- neediest by FRACTION (the first honest fight measured SHADOW at 56/197
-- dying unhealed while absolute-missing ranking pointed both medics at
-- bigger pools), with SABIN jumping the queue under 60% -- he is the win
-- condition and no Fenix Down exists on this line
local function neediest()
  local best, miss, worst = nil, 0, 21
  if sabinE and pHP(sabinE) > 0 and pMaxHP(sabinE) > 0
     and pHP(sabinE) * 10 < pMaxHP(sabinE) * 6 then
    return sabinE, pMaxHP(sabinE) - pHP(sabinE)
  end
  for _, e in ipairs({ sabinE, cyanE, shadowE }) do
    if e and pHP(e) > 0 and pMaxHP(e) > 0 then
      local frac20 = pHP(e) * 20 // pMaxHP(e)   -- 0..20
      if frac20 < worst and frac20 < 15 then    -- only under 75%
        best, worst, miss = e, frac20, pMaxHP(e) - pHP(e)
      end
    end
  end
  return best, miss
end
local function makePlan(actor)
  local shields = H.readByte(SH(gSlot))
  if actor == sabinE then
    if shields > 0 then
      local mp = pMP(sabinE)
      local skill
      if mp >= 10 and (mp - 10) >= 4 * (shields - 1) then
        skill = AURABOLT
      elseif mp >= 4 then
        skill = PUMMEL
      else
        b68.impossible = string.format(
          "SABIN out of MP with the break incomplete: mp=%d shields=%d " ..
          "casts=%d trainHP=%d -- AuraBolt costs 10, Pummel 4, the ghost " ..
          "merchant stocks no MP restorative, and Osmose is the game's " ..
          "only MP income (Sabin has no magic).  The 6-chip break cannot " ..
          "be funded from this pool at shipped tuning.",
          mp, shields, b68.casts, H.readWord(MHP(gSlot)))
        return { kind = "fight", boost = 0 }   -- placeholder; caller errors
      end
      b68Log(string.format(
        "plan cast %d: %s (mp %d, shields %d, trainHP %d) [%s]",
        b68.casts + 1, skill == AURABOLT and "AURABOLT" or "PUMMEL",
        pMP(sabinE), shields, H.readWord(MHP(gSlot)), partyLine()))
      return { kind = "blitz", skill = skill,
               row = cmdRowOf(actor, CMD_BLITZ) }
    end
    local bp = math.min(H.readByte(BP + actor * 2), 3)
    b68Log(string.format("BROKEN finish: SABIN Fight boost=%d trainHP=%d",
      bp, H.readWord(MHP(gSlot))))
    return { kind = "fight", boost = bp }
  end
  -- a medic
  if shields > 0 then
    local tgt, miss = neediest()
    if tgt == nil then
      -- nobody down 50 HP yet: an idle-safe turn is still a heal (a Tonic
      -- on the actor), never a Fight -- pre-break damage is the one thing
      -- a medic must not deal
      tgt, miss = actor, 0
    end
    local item = nil
    if tgt then
      if miss >= 100 and invCount(POTION) > 0 then item = POTION
      elseif invCount(TONIC) > 0 then item = TONIC
      elseif invCount(POTION) > 0 then item = POTION end
    end
    if item then
      b68Log(string.format(
        "medic e%d: %s -> e%d (missing %d) tonics=%d potions=%d [%s]",
        actor, item == TONIC and "TONIC" or "POTION", tgt, miss,
        invCount(TONIC), invCount(POTION), partyLine()))
      return { kind = "item", item = item, target = tgt,
               row = cmdRowOf(actor, CMD_ITEM) }
    end
    if not b68.itemsOut then
      b68.itemsOut = true
      b68Log("MEDIC BAG EMPTY before the break completed -- falling back " ..
        "to Fight; the remaining damage budget is now shared")
    end
    return { kind = "fight", boost = 0 }
  end
  local bp = math.min(H.readByte(BP + actor * 2), 3)
  b68Log(string.format("BROKEN finish: medic e%d Fight boost=%d", actor, bp))
  return { kind = "fight", boost = bp }
end

-- one pulse of the b68 engine; returns the button table to hold (or nil)
local function b68Button()
  local st = H.readByte(MSTATE)
  local actor = H.readByte(ACTOR)
  local plan = b68.plan
  if plan == nil or b68.planActor ~= actor then
    if st ~= ST_CMD then
      -- a menu parked in a LIST state with no plan (measured: SABIN's
      -- second command menu reopened straight into the blitz shell $30
      -- after his first cast, and the engine waited 145000 frames for an
      -- ST_CMD that never came) -- back out to the command list
      if st == ST_TOOLS or st == ST_ITEM or st == ST_TGT then
        return { "b" }
      end
      return nil
    end
    b68.plan = makePlan(actor)
    b68.planActor = actor
    b68.plan.boostLeft = b68.plan.boost or 0
    return nil
  end
  if st == ST_CMD then
    if plan.boostLeft and plan.boostLeft > 0 then
      plan.boostLeft = plan.boostLeft - 1
      return { "r" }
    end
    local wantRow = plan.kind == "fight" and 0 or plan.row
    if wantRow == nil then                    -- command missing: plain Fight
      wantRow = 0
    end
    local cur = H.readByte(CMDROW + actor) & 3
    if cur == wantRow then return { "a" } end
    -- closed-loop steering; the engine skips invalid rows itself.  Try the
    -- incremental read first, the absolute-jump buttons as fallback.
    if plan.rowStall and plan.rowStall > 2 then
      plan.rowStall = 0
      return { ({ [0] = "up", [1] = "left", [2] = "right", [3] = "down" })[wantRow] }
    end
    plan.rowStall = (plan.rowStall or 0) + 1
    return { cur < wantRow and "down" or "up" }
  end
  if st == ST_TOOLS and plan.kind == "blitz" then
    local row = nil
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == plan.skill then row = i end
    end
    if row == nil then return nil end
    local wc, wr = row % 2, row // 2
    local cc = H.readByte(BLCOL + actor)
    local cr = H.readByte(BLROW + actor)
    if cc ~= wc then return { wc > cc and "right" or "left" } end
    if cr ~= wr then return { wr > cr and "down" or "up" } end
    b68.casts = b68.casts + 1                 -- the cast is committing NOW
    b68.plan, b68.planActor = nil, nil        -- done: next menu replans fresh
    return { "a" }                            -- confirm; blitzes self-target
  end
  if st == ST_ITEM and plan.kind == "item" then
    local want = battInvIdx(plan.item)
    if want == nil then return { "b" } end    -- ran out mid-menu: back out
    local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
    if cur < want then return { "down" } end
    if cur > want then return { "up" } end
    return { "a" }
  end
  if st == ST_TGT then
    if plan.kind ~= "item" then
      b68.plan, b68.planActor = nil, nil      -- Fight commits on this confirm
      return { "a" }                          -- default target
    end
    local chars = H.readByte(TGTCHARS)
    local mons = H.readByte(TGTMONS)
    if mons ~= 0 then return { "right" } end  -- off the monster side
    local wantMask = 1 << plan.target
    if chars == wantMask then
      b68.plan, b68.planActor = nil, nil      -- item commits on this confirm
      return { "a" }
    end
    plan.tgtStall = (plan.tgtStall or 0) + 1
    if plan.tgtStall > 20 then
      b68Log(string.format("target steer stalled (chars=%02X want=%02X) " ..
        "-- accepting the current party target", chars, wantMask))
      b68.plan, b68.planActor = nil, nil
      return { "a" }                          -- any party target is harmless
    end
    -- move within the party column: compare lowest set bits
    local cur = 0
    for b = 0, 3 do if chars & (1 << b) ~= 0 then cur = b; break end end
    return { cur < plan.target and "down" or "up" }
  end
  return nil                                  -- transitions: hands off
end

-- observers: shield chips, the break, the kill -- all logged with numbers
local function b68Observe()
  local shields = H.readByte(SH(gSlot))
  local hp = H.readWord(MHP(gSlot))
  if b68.lastSH and shields < b68.lastSH then
    local row = string.format(
      "chip %d->%d at f%d: lastSkill=$%02X trainHP=%d sabinMP=%d [%s]",
      b68.lastSH, shields, H.frame, H.readByte(0x3410), hp,
      sabinE and pMP(sabinE) or -1, partyLine())
    b68.chips[#b68.chips + 1] = row
    b68Log(row)
    b68.plan = nil                            -- re-plan on fresh numbers
  end
  if shields == 0 and b68.brokeAt == nil and (b68.lastSH or 6) > 0 then
    b68.brokeAt = H.frame
    b68Log(string.format(
      "*** BREAK COMPLETE at f%d with the train ALIVE at %d HP -- the " ..
      "proof obligation holds (casts=%d)", H.frame, hp, b68.casts))
    H.screenshot("train_b68_broken")
  end
  if hp == 0 and b68.killedAt == nil and b68.lastHP and b68.lastHP > 0 then
    b68.killedAt = H.frame
    b68Log(string.format("train at 0 HP at f%d (brokeAt=%s)", H.frame,
      tostring(b68.brokeAt)))
  end
  b68.lastSH, b68.lastHP = shields, hp
end

-- ----------------------------------------------- the save-point rest stop --
-- The engineer's room (map 146) carries a SAVE POINT at {20,10}
-- (NPCProp::_146), and the ghost merchant sells SLEEPING BAGS -- the
-- game's own answer to walking into a boss at 3/231, which is exactly
-- where the strip's fled encounters delivered SABIN (measured: b68 entry
-- [3/231, 150/197, 56/254] across every ladder attempt, because the
-- checkpoint bakes the entry HP).  So the party does what a player does:
-- stand on the save point, open the real field menu (X), and use one bag
-- per member -- full HP AND MP, by the game's own rules (UseItem gates
-- the bag on w0201 bit7, item.asm:@84e2).  All closed-loop: main-menu
-- cursor and character select steer MoveCursor's row cell (DP $4E), the
-- item list steers UseItem's own selection index (DP $4B), and every use
-- is verified against the character blocks before the next.
local function charHP(c)
  return H.readWord(0x1609 + 37 * c), H.readWord(0x160b + 37 * c) & 0x3fff
end
local SLEEPING_BAG = 0xF6
local function menuHeal()
  local phase = 0
  local partyChars = { 5, 2, 3 }          -- SABIN, CYAN, SHADOW
  local function allFull()
    for _, c in ipairs(partyChars) do
      local hp, mx = charHP(c)
      if hp < mx then return false end
    end
    return true
  end
  local usedRow = 0                       -- next character row to bag
  local seen70 = false
  return H.driveUntil(function()
    return allFull() and H.hasControl()
  end, 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      local st = mstateMenu()
      if H.hasControl() then
        if allFull() then H.setPad({}); return end
        if invCount(SLEEPING_BAG) == 0 then
          local h5, m5 = charHP(5)
          local h2, m2 = charHP(2)
          local h3, m3 = charHP(3)
          error(string.format("rest stop: out of Sleeping Bags with the " ..
            "party not full -- HP %d/%d %d/%d %d/%d", h5, m5, h2, m2,
            h3, m3), 0)
        end
        H.setPad(phase < 4 and { "x" } or {})   -- open the field menu
        return
      end
      if st == 0x05 then                        -- main menu: Item is row 0
        local cur = H.readByte(0x004E)
        local btn = cur > 0 and "up" or "a"
        H.setPad(phase < 2 and { [btn] = true } or {})
      elseif st == 0x08 then                    -- item list: steer $4B
        local want = nil
        for i = 0, 255 do
          if H.readByte(0x1869 + i) == SLEEPING_BAG
             and H.readByte(0x1969 + i) > 0 then want = i; break end
        end
        if want == nil then
          H.setPad(phase < 2 and { "b" } or {})  -- gone: close and error above
          return
        end
        local cur = H.readByte(0x004B)
        local btn = cur < want and "down" or cur > want and "up" or "a"
        H.setPad(phase < 2 and { [btn] = true } or {})
      elseif st == 0x70 then                    -- character select
        seen70 = true
        -- rows follow party order; heal the first member still hurt
        local wantRow = nil
        for r, c in ipairs(partyChars) do
          local hp, mx = charHP(c)
          if hp < mx then wantRow = r - 1; break end
        end
        if wantRow == nil then
          H.setPad(phase < 2 and { "b" } or {})
          return
        end
        local cur = H.readByte(0x004E)
        local btn = cur < wantRow and "down" or cur > wantRow and "up" or "a"
        H.setPad(phase < 2 and { [btn] = true } or {})
      elseif st == 0x04 or st == 0x07 or st == 0x6F then
        H.setPad({})                            -- inits: hands off
      else
        -- sleep animation / transitions: hands off; when the menu parks
        -- anywhere unexpected, B walks it back out
        H.setPad(phase == 0 and { "b" } or {})
      end
    end),
  }, "save-point rest: Sleeping Bags until the party is full")
end

-- ------------------------------------------------- the battle-47 ladder --
-- Checkpoint before the trap-ghost talk; an attempt is talk -> fight ->
-- mob scene -> settled back on 142.  A wipe (GameOver park) or a
-- walked-off SHADOW (the 1/16 win roll -- $4B is story-clear here)
-- reloads with a 17-frame stagger: a shifted timeline, a fresh roll.
local b47Blob, b47won = nil, false
local function b47Won() return b47won end
local function b47Checkpoint()
  local ckReq
  return H.cond(function() return true end, {
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "b47 checkpoint")
      b47Blob = ckReq.blob
      H.log(string.format("[train] b47 checkpoint captured (%d bytes) f%d",
        #b47Blob, H.frame))
    end),
  }, {})
end
local function b47Attempt(n)
  local ldReq
  return H.cond(function() return not b47won end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[train] b47 ATTEMPT %d -- reloading (%s)",
          n, tostring(lost))
      end),
      H.call(function() ldReq = H.requestLoadState(b47Blob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "b47 attempt " .. n) end),
      H.waitFrames(60 + (n - 1) * 17),
    }, {}),
    H.call(function()
      lost, fightTier, wipeN = nil, n, 0
      b47Heals, fPlan, fPlanActor = 0, nil, nil
    end),
    nav(26, 9, { maxFrames = 3000 }),
    (function()
      local phase = 0
      return H.driveUntil(function() return sw(0x17C) == 1 end, 3000, {
        H.call(function()
          phase = (phase + 1) % 8
          H.setPad(phase < 4 and { "down", "a" } or { "down" })
        end),
      }, "talk to the trap ghost")
    end)(),
    (function()
      local frames = 0
      return holdDrive("down", function()
        frames = frames + 1
        if frames > 29000 and lost == nil then
          lost = string.format("b47 attempt %d deadline (29000 frames) -- " ..
            "assumed wiped or wedged [%s]", n, partyLine())
          H.log("[train] LOST -- " .. lost)
        end
        return lost ~= nil
            or (mapIdx() == 142 and H.hasControl() and H.tileAligned()
                and not inBattle() and bright() >= 15)
      end, "battle 47 + mob scene (attempt " .. n .. ")", 30000, "fight")
    end)(),
    H.waitFrames(30),
    H.call(function()
      if lost == nil and not inParty(3) then
        lost = string.format("SHADOW walked off after battle 47's win (the " ..
          "1/16 roll) at f%d -- a shifted retry re-rolls it", H.frame)
        H.log("[train] " .. lost)
      end
      if lost == nil then
        b47won = true
        H.log(string.format("[train] battle 47 attempt %d clean: won, " ..
          "SHADOW aboard", n))
      end
    end),
  }, {})
end

-- ------------------------------------------------- the battle-68 ladder --
local b68Blob, b68won = nil, false
local function b68Won() return b68won end
local function b68Checkpoint()
  local ckReq
  return H.cond(function() return true end, {
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "b68 checkpoint")
      b68Blob = ckReq.blob
      H.log(string.format("[train] b68 checkpoint captured (%d bytes) f%d",
        #b68Blob, H.frame))
    end),
  }, {})
end
local function b68Attempt(n)
  local ldReq
  return H.cond(function()
    return not b68won and b68.impossible == nil
  end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[train] b68 ATTEMPT %d -- reloading (%s)",
          n, tostring(lost))
      end),
      H.call(function() ldReq = H.requestLoadState(b68Blob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "b68 attempt " .. n) end),
      H.waitFrames(60 + (n - 1) * 23),
    }, {}),
    H.call(function()
      lost, wipeN = nil, 0
      b68.casts, b68.chips = 0, {}
      b68.plan, b68.planActor = nil, nil
      b68.brokeAt, b68.killedAt = nil, nil
      b68.itemsOut = false
      b68.lastSH, b68.lastHP = nil, nil
      b68.tornDown, b68.mstreak, b68.sabinDeadN = 0, 0, 0
      gSlot, sabinE, cyanE, shadowE = nil, nil, nil, nil
    end),
    nav(32, 7, { maxFrames = 8000 }),
    upA(function() return sw(0x3A) == 1 end, "smokestack switch", 4000),
    (function()
      local phase = 0
      return H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
        H.call(function()
          phase = (phase + 1) % 8
          H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
        end),
      }, "battle 68 up")
    end)(),
    H.waitUntil(function()
      for s = 0, 5 do
        if H.readWord(0x57C0 + s * 2) == GHOSTTRAIN then return true end
      end
      return false
    end, 1200, "GHOSTTRAIN in the formation", 5),
    H.waitFrames(120),
    H.call(function()
      for s = 0, 5 do
        if H.readWord(0x57C0 + s * 2) == GHOSTTRAIN then gSlot = s end
      end
      for e = 0, 3 do
        local id = H.readByte(0x3ED8 + e * 2)
        if id == 0x05 then sabinE = e end
        if id == 0x02 then cyanE = e end
        if id == 0x03 then shadowE = e end
      end
      H.assertEq(gSlot ~= nil, true, "GHOSTTRAIN found in a monster slot")
      H.assertEq(sabinE ~= nil, true, "SABIN found in a party entity")
      H.assertEq(cyanE ~= nil, true, "CYAN found in a party entity")
      H.assertEq(shadowE ~= nil, true, "SHADOW found in a party entity")
      local lv = H.readByte(0x3B18 + sabinE * 2)
      H.log(string.format(
        "[b68] attempt %d: slot %d, SABIN e%d lv%d mp %d/%d, CYAN e%d, " ..
        "SHADOW e%d | tonics=%d potions=%d gil=%d",
        n, gSlot, sabinE, lv, pMP(sabinE), H.readWord(0x3C30 + sabinE * 2),
        cyanE, shadowE, invCount(TONIC), invCount(POTION), gil()))
      H.assertEq(lv >= 6, true, "SABIN level 6+ -- AuraBolt learned")
      -- the authored row, live: the runtime proof of GhostTrain's 6-shield
      -- OT6_BLUDG entry in Ot6ShieldTbl
      H.assertEq(H.readByte(SH(gSlot)), 6, "GHOSTTRAIN seeds 6 shields")
      H.assertEq(H.readByte(SMX(gSlot)), 6, "GHOSTTRAIN max shields 6")
      H.assertEq(H.readByte(WKC(gSlot)), OT6_BLUDG,
        "GHOSTTRAIN's class row is OT6_BLUDG")
      H.assertEq(H.readByte(WKE(gSlot)) & HOLY, HOLY,
        "holy in the weak byte (vanilla fire|bolt|holy)")
      H.assertEq(H.readByte(RVE(gSlot)), 0, "nothing revealed yet (elements)")
      H.assertEq(H.readByte(RVC(gSlot)), 0, "nothing revealed yet (classes)")
      H.screenshot("train_b68_up")
    end),
    -- the fight itself: the closed-loop pacifist engine
    (function()
      local tick = 0
      local frames = 0
      return H.driveUntil(function()
        frames = frames + 1
        if frames > 145000 and lost == nil then
          lost = string.format("b68 attempt %d deadline (145000 frames) " ..
            "[%s]", n, partyLine())
          H.log("[b68] LOST -- " .. lost)
        end
        return lost ~= nil or b68.impossible ~= nil or b68.tornDown >= 3
      end, 150000, {
        H.call(function()
          if not inBattle() then
            b68.tornDown = b68.tornDown + 1
            H.setPad({})
            return
          end
          b68.tornDown = 0
          b68Observe()
          wipeWatch("b68")
          -- SABIN down pre-break: the chip engine is gone; no Fenix Down
          -- on the pacifist line, so this attempt is over
          if pHP(sabinE) == 0 and H.readByte(SH(gSlot)) > 0 then
            b68.sabinDeadN = b68.sabinDeadN + 1
            if b68.sabinDeadN >= 90 and not lost then
              lost = string.format("SABIN down pre-break at f%d " ..
                "(shields=%d casts=%d) [%s]", H.frame,
                H.readByte(SH(gSlot)), b68.casts, partyLine())
              H.log("[b68] LOST -- " .. lost)
              H.screenshot("train_b68_lost")
            end
          else
            b68.sabinDeadN = 0
          end
          if lost then H.setPad({}); return end
          tick = tick + 1
          local ph = tick % 30
          if H.readByte(MENU) == 0 then
            b68.plan, b68.planActor = nil, nil
            b68.mstreak = 0
            H.setPad(ph < 4 and { "a" } or {})   -- page battle text
            return
          end
          b68.mstreak = b68.mstreak + 1
          if b68.mstreak < 4 then H.setPad({}); return end
          if H.frame - (b68.hb or -300) >= 300 then
            b68.hb = H.frame
            local a = H.readByte(ACTOR)
            b68Log(string.format(
              "fmenu f%d st=%02X actor=%d row=%d sh=%d hp=%d [%s]",
              H.frame, H.readByte(MSTATE), a, H.readByte(CMDROW + a) & 3,
              H.readByte(SH(gSlot)), H.readWord(MHP(gSlot)), partyLine()))
          end
          if ph == 0 then b68.btn = b68Button() end
          H.setPad(ph < 6 and b68.btn or {})
        end),
      }, "battle 68, the pacifist line (attempt " .. n .. ")")
    end)(),
    H.waitFrames(60),
    H.call(function()
      if b68.impossible then return end        -- reported at ladder exit
      if lost == nil and b68.killedAt == nil then
        lost = string.format("battle 68 ended without the train at 0 HP " ..
          "(a wipe-teardown) at f%d [%s]", H.frame, partyLine())
        H.log("[b68] " .. lost)
      end
      if lost == nil and b68.brokeAt == nil then
        -- the train died with shields standing: the pacifist policy failed
        -- to hold the damage under the break -- report, never rig
        lost = string.format("train died at f%d with the break INCOMPLETE " ..
          "(shields=%s, casts=%d) -- the proof obligation failed this " ..
          "attempt", tostring(b68.killedAt), tostring(b68.lastSH), b68.casts)
        H.log("[b68] " .. lost)
      end
      if lost == nil and not inParty(3) then
        lost = string.format("SHADOW walked off after battle 68's win " ..
          "(the 1/16 roll) at f%d -- a shifted retry re-rolls it", H.frame)
        H.log("[train] " .. lost)
      end
      if lost == nil then
        b68won = true
        H.assertEq(b68.brokeAt < b68.killedAt, true,
          "the 6-shield break landed BEFORE the kill (the leg's proof " ..
          "obligation)")
        H.log(string.format("[b68] attempt %d WON: brokeAt=f%d " ..
          "killedAt=f%d casts=%d", n, b68.brokeAt, b68.killedAt, b68.casts))
      else
        for _, row in ipairs(b68.chips) do
          H.log("[b68 attempt " .. n .. "] " .. row)
        end
      end
    end),
  }, {})
end

H.run({ maxFrames = 400000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 145, "boot aboard the train, map 145")
    H.assertEq(sw(0x38), 1, "$0038 set -- train discovered")
    H.assertEq(sw(0x39), 0, "$0039 clear -- not yet departed")
    swDump("start")
    -- NO SHADOW PIN (issue #75).  Corridor trash is fled (no win, no 1/16
    -- roll); the two win-gated fights sit behind retry ladders that treat
    -- a walked-off SHADOW as a loss and reload with a stagger.
  end),

  -- ---- rear half ----
  holdDrive("down", function() return sw(0x39) == 1 end, "departure", 6000),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 4000, "post-departure", 5),
  nav(2, 7, { maxFrames = 12000 }),
  holdDrive("left", function() return mapIdx() == 142 end, "A west exit", 4000),
  settle(142, "west pocket (66,8)"),
  holdDrive("left", function() return mapIdx() == 145 end, "-> car B", 4000),
  settle(145, "car B"),
  H.call(function() H.assertEq(sw(0x17E), 1, "$017E -- this 145 is car B") end),

  -- ---- the ghost merchant (car B only -- see the section comment) ----
  H.call(function()
    H.log(string.format("[shop] merchant obj 29 at (%d,%d); gil=%d " ..
      "tonics=%d potions=%d", objX(29), objY(29), gil(),
      invCount(TONIC), invCount(POTION)))
  end),
  openShop(),
  H.call(function()
    H.log(string.format("[shop] open; gil=%d", gil()))
    H.screenshot("train_shop")
  end),
  -- Tonics fund the round-by-round chip damage, Potions the Wheel spikes.
  -- 15/6 covers ~10 medic turns each with margin; the gil floors keep a
  -- short purse from zeroing out (log tells the story either way).
  buyItem(TONIC, 0, function() return 20 - invCount(TONIC) end, "TONIC to 20"),
  buyItem(POTION, 1, function() return 15 - invCount(POTION) end,
    "POTION to 15"),
  buyItem(SLEEPING_BAG, 5, function() return 4 - invCount(SLEEPING_BAG) end,
    "SLEEPING BAG to 4"),
  closeShop(),
  H.call(function()
    H.log(string.format("[shop] done: gil=%d tonics=%d potions=%d",
      gil(), invCount(TONIC), invCount(POTION)))
    H.assertEq(invCount(TONIC) >= 12, true,
      "at least 12 Tonics for the medic line (bought honestly)")
    H.assertEq(invCount(POTION) >= 8, true,
      "at least 8 Potions for the medic line (bought honestly)")
  end),

  -- Car B's aisle first gets a plain HELD walk, and only then bfs: on the
  -- 2026-07-20 lineage the ghosts' wander phase parked a pair mid-aisle
  -- long enough that the object map showed a full cut (both rows claimed
  -- at one column) for longer than navTo's whole no-path patience -- while
  -- the ENGINE walked straight through the same stretch, the moving party
  -- shouldering past as gaps opened (measured: hold-left crossed the
  -- "cut" and reached (4,7) in 419 frames while bfs still saw no path).
  -- The model is honestly conservative here -- it reads the object map at
  -- one instant; a held walk renegotiates every frame.  Same idiom as the
  -- exits' holdDrive; navTo then lands the final tiles precisely.
  (function()
    local n = 0
    return H.driveUntil(function()
      n = n + 1
      return H.fieldX() <= 4 or n > 900
    end, 1000, {
      H.call(function() H.setPad({ left = true }) end),
    }, "car B's aisle, held through the ghost wander")
  end)(),
  nav(2, 7, { maxFrames = 12000 }),
  holdDrive("left", function() return mapIdx() == 142 end, "B west exit", 4000),
  settle(142, "pocket (50,8)"),
  nav(41, 8, { maxFrames = 8000, arrive = function()
    return mapIdx() == 145 or (H.fieldX() == 41 and H.fieldY() == 8
       and H.hasControl() and H.tileAligned()) end }),
  holdDrive("up", function() return mapIdx() == 145 and sw(0x180) == 1 end,
    "-> car C", 4000),
  settle(145, "car C"),
  H.call(function() H.assertEq(sw(0x509), 1, "$0509 -- car C's ghost cast") end),
  holdDrive("up", function()
    return sw(0x3D) == 1 and H.hasControl() and H.tileAligned()
  end, "bait the follower ghost", 4000),

  -- ---- battle 47, honestly, behind the ladder ----
  b47Checkpoint(),
  b47Attempt(1),
  b47Attempt(2),
  b47Attempt(3),
  H.call(function()
    if not b47Won() then
      error(string.format("train: battle 47 did not complete cleanly on " ..
        "any of 3 honest attempts -- last: %s -- do not rig this leg",
        tostring(lost)), 0)
    end
  end),

  nav(40, 8, { maxFrames = 4000 }),
  holdDrive("up", function()
    return H.fieldY() <= 6 and H.hasControl() and H.tileAligned()
  end, "roof climb", 15000),
  holdDrive("up", function()
    return H.fieldY() == 5 and H.hasControl() and H.tileAligned()
  end, "roof top", 4000),
  holdDrive("left", function()
    return H.fieldX() <= 13 and H.hasControl() and H.tileAligned()
  end, "SABIN's jump", 30000),
  holdDrive("down", function()
    return H.fieldY() >= 8 and H.hasControl() and H.tileAligned()
  end, "down to the strip", 6000),
  holdDrive("left", function() return mapIdx() == 149 end,
    "mob catch + car 149", 30000),
  settle(149, "car 149 vestibule"),
  nav(28, 5, { maxFrames = 6000 }),
  upA(function() return sw(0x183) == 1 end, "detach lever", 3000),
  holdDrive("down", function()
    return mapIdx() == 141 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, "detach cinematic", 30000),
  H.call(function()
    swDump("detached")
    H.assertEq(sw(0x183), 1, "$0183 -- rear cars detached")
  end),

  -- ---- front half: the second pull, then the strip ----
  holdDrive("left", function() return mapIdx() == 149 end, "re-enter 149", 4000),
  settle(149, "vestibule again"),
  nav(28, 5, { maxFrames = 6000 }),
  upA(function() return sw(0x17F) == 1 end, "second pull -- inner door", 3000),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    2000, "post second pull", 5),
  nav(2, 7, { maxFrames = 10000 }),
  holdDrive("left", function() return mapIdx() == 141 end, "149 west exit", 4000),
  settle(141, "pocket (108,8)"),
  nav(101, 9, { maxFrames = 4000 }),
  nav(90, 9, { maxFrames = 4000 }),
  nav(84, 8, { maxFrames = 3000 }),
  nav(83, 9, { maxFrames = 2000 }),
  nav(81, 9, { maxFrames = 2000 }),
  nav(81, 6, { maxFrames = 2000 }),
  nav(76, 5, { maxFrames = 3000 }),
  nav(76, 7, { maxFrames = 2000 }),
  nav(76, 9, { maxFrames = 2000 }),
  nav(74, 9, { maxFrames = 2000 }),
  nav(74, 8, { maxFrames = 2000 }),
  nav(67, 8, { maxFrames = 3000 }),
  nav(67, 9, { maxFrames = 2000 }),
  nav(65, 9, { maxFrames = 2000 }),
  nav(65, 6, { maxFrames = 2000 }),
  nav(60, 5, { maxFrames = 3000 }),
  nav(60, 8, { maxFrames = 2000 }),
  nav(60, 9, { maxFrames = 2000 }),
  nav(58, 9, { maxFrames = 2000 }),
  nav(52, 8, { maxFrames = 4000 }),
  nav(51, 9, { maxFrames = 2000 }),
  nav(45, 9, { maxFrames = 3000 }),
  nav(45, 8, { maxFrames = 2000 }),
  nav(38, 9, { maxFrames = 3000 }),
  holdDrive("up", function() return mapIdx() == 146 end,
    "engineer entrance", 3000),
  settle(146, "engineer's room"),
  nav(7, 7, { maxFrames = 5000 }),
  upA(function() return sw(0x184) == 1 end, "valve 1 SHUT", 3000),
  nav(9, 7, { maxFrames = 3000 }),
  upA(function() return sw(0x186) == 1 end, "valve 3 SHUT", 3000),
  H.call(function()
    swDump("valves")
    H.assertEq(sw(0x184), 1, "$0184 -- valve 1 shut")
    H.assertEq(sw(0x185), 0, "$0185 -- valve 2 open")
    H.assertEq(sw(0x186), 1, "$0186 -- valve 3 shut")
  end),
  -- the rest stop (see the section comment): save point {20,10}, one
  -- Sleeping Bag per member, full HP+MP walking into the smokestack.
  -- The save point is drawn by an NPC object, so the BFS's object map
  -- reads its tile as SOLID (measured: no path (9,7)->(20,10)), and the
  -- straight (20,11) approach measured unreachable too -- so pick the
  -- approach empirically: BFS-reach each of the four neighbours, walk to
  -- the first reachable one, and hold the last step on (the engine takes
  -- it fine).  A full flood dump ships with the failure if none reach.
  (function()
    local approach, dir = nil, nil
    return H.cond(function() return true end, {
      H.call(function()
        local cands = {
          { 20, 11, "up" }, { 19, 10, "right" },
          { 21, 10, "left" }, { 20, 9, "down" },
        }
        for _, c in ipairs(cands) do
          local pth = H.bfsPath(c[1], c[2])
          if pth then approach, dir = { c[1], c[2] }, c[3]; break end
        end
        if not approach then
          local MOVES = { "up", "down", "left", "right" }
          local DELTA = { up = {0,-1}, down = {0,1},
                          left = {-1,0}, right = {1,0} }
          local sx, sy = H.fieldX(), H.fieldY()
          local seen = { [sy * 256 + sx] = true }
          local q, qi = { { sx, sy } }, 1
          while qi <= #q and qi <= 2000 do
            local x, y = q[qi][1], q[qi][2]
            qi = qi + 1
            for _, d in ipairs(MOVES) do
              if H.canStep(x, y, d) then
                local k = (y + DELTA[d][2]) * 256 + (x + DELTA[d][1])
                if not seen[k] then
                  seen[k] = true
                  q[#q + 1] = { x + DELTA[d][1], y + DELTA[d][2] }
                end
              end
            end
          end
          local rows = {}
          for k in pairs(seen) do
            local y, x = k >> 8, k & 0xFF
            rows[y] = rows[y] or {}
            rows[y][#rows[y] + 1] = x
          end
          for y, xs in pairs(rows) do
            table.sort(xs)
            H.log(string.format("  146 y=%d x=%s", y, table.concat(xs, ",")))
          end
          error("rest stop: no neighbour of the save point (20,10) is " ..
            "BFS-reachable; the flood above is the room model", 0)
        end
        H.log(string.format("[rest] approach (%d,%d) then hold %s",
          approach[1], approach[2], dir))
      end),
      nav(function() return approach[1] end, function() return approach[2] end,
        { maxFrames = 6000 }),
      (function()
        local phase = 0
        return H.driveUntil(function()
          return H.fieldX() == 20 and H.fieldY() == 10 and H.tileAligned()
        end, 1800, {
          H.call(function()
            phase = (phase + 1) % 8
            if not H.hasControl() then H.setPad({}); return end
            H.setPad({ [dir] = true })
          end),
        }, "step onto the save point")
      end)(),
    }, {})
  end)(),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "standing on the save point (w0201 bit7 -- the bag's own gate)")
    H.log(string.format("[rest] on the save point; bags=%d [%s]",
      invCount(SLEEPING_BAG), partyLine()))
  end),
  menuHeal(),
  H.call(function()
    H.log(string.format("[rest] party full: bags left=%d", 
      invCount(SLEEPING_BAG)))
    H.screenshot("train_rested")
  end),
  nav(8, 13, { maxFrames = 5000, arrive = function()
    return mapIdx() == 141 end }),
  settle(141, "outside again"),

  -- ---- BATTLE 68: the Ghost Train, the pacifist line, the ladder ----
  b68Checkpoint(),
  b68Attempt(1),
  b68Attempt(2),
  b68Attempt(3),
  H.call(function()
    if b68.impossible then
      error("train: the pacifist break line is IMPOSSIBLE as shipped -- " ..
        b68.impossible .. " -- this is the #74 data point; do not rig", 0)
    end
    if not b68Won() then
      error(string.format("train: battle 68 did not complete cleanly on " ..
        "any of 3 honest attempts -- last: %s", tostring(lost)), 0)
    end
  end),

  -- ---- the ride out: victory scene, the station, the timer, the world ----
  (function()
    local phase, hb = 0, -900
    return H.driveUntil(function()
      return H.worldMode() and H.worldHasControl()
    end, 60000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.frame - hb >= 900 then
          hb = H.frame
          H.log(string.format("ride f%d map=%d world=%s dlg=%s $003B=%d shdw=%s",
            H.frame, mapIdx(), tostring(H.worldMode()),
            tostring(H.dialogWaiting()), sw(0x3B), tostring(inParty(3))))
        end
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "ride the ending to the world map")
  end)(),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() end,
    3000, "world control", 5),
  H.waitUntil(function() return bright() >= 15 end, 1200, "world fade", 10),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the World of Balance")
    H.assertEq(H.worldX(), 178, "world x=178")
    H.assertEq(H.worldY(), 93, "world y=93")
    H.assertEq(sw(0x3A), 1, "$003A set -- the Ghost Train fought")
    H.assertEq(sw(0x3B), 1, "$003B set -- the train ride is over")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(2), true, "CYAN in the party")
    H.assertEq(inParty(3), true, "SHADOW in the party (rejoined, $018D dance)")
    H.log(string.format("[train_done] f%d world (%d,%d)",
      H.frame, H.worldX(), H.worldY()))
    for _, row in ipairs(b68.chips) do H.log("[b68 record] " .. row) end
    H.log(string.format("[b68 record] brokeAt=%s killedAt=%s casts=%d",
      tostring(b68.brokeAt), tostring(b68.killedAt), b68.casts))
    H.screenshot("train_done")
  end),
  H.saveState("train_done.mss"),
  H.logStep(function()
    return string.format("train_done minted at frame %d world (%d,%d) -- " ..
      "battle 68 won on the pacifist line, break before kill",
      H.frame, H.worldX(), H.worldY())
  end),
})
