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
local ITEMIDX = 0x8947                  -- +actor: item-list absolute index
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

-- ------------------------------------------------ the boost-Fight fighter --
-- gen_sabin_camp's menu-episode machine, for battle 47 (and any surprise
-- that cannot be fled): bank boost to 2, dump on Fight; one button per
-- 30-frame pulse from a settled menu; edge-tap A everywhere else.
local fightTier = 1
local lost = nil
local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
local wipeN = 0
local function fightPulse(phase)
  if H.readByte(MENU) == 0 then
    mStreak, mSeq = 0, nil
    H.setPad(phase < 4 and { "a" } or {})
    return
  end
  mStreak = mStreak + 1
  if mStreak < 4 then H.setPad({}); return end
  if mSeq == nil then
    local slot = H.readByte(ACTOR) & 3
    local bp = H.readByte(BP + slot * 2)
    local boostMin = fightTier >= 2 and 1 or 2
    local boost = bp >= boostMin and math.min(bp, 3) or 0
    mSeq, mIdx, mTick, mStall = {}, 1, 0, 0
    for _ = 1, boost do mSeq[#mSeq + 1] = "r" end
    mSeq[#mSeq + 1] = "a"; mSeq[#mSeq + 1] = "a"
    H.log(string.format("[b47] cast f%d slot=%d bp=%d tier=%d seq=%s | [%s]",
      H.frame, slot, bp, fightTier, table.concat(mSeq, ","), partyLine()))
  end
  mTick = mTick + 1
  local ph = mTick % 30
  local btn
  if mIdx <= #mSeq then
    btn = mSeq[mIdx]
  elseif mStall < 2 then
    btn = "a"
  elseif mStall < 4 then
    btn = "b"
  else
    mSeq = nil
    H.setPad({})
    return
  end
  if ph < 6 then H.setPad({ [btn] = true }) else H.setPad({}) end
  if ph == 29 then
    if mIdx <= #mSeq then mIdx = mIdx + 1 else mStall = mStall + 1 end
  end
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

-- buy `want` of item `id` sitting on shop row `row` (0-based), one unit
-- per confirm loop, verified against the FIELD inventory count each lap.
-- Stops early (loudly) if gil runs under `floor`.
local function buyItem(id, row, want, floor, name)
  local phase, downs = 0, 0
  return H.driveUntil(function()
    return invCount(id) >= want or gil() < floor
  end, 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      local st = mstateMenu()
      if st == 0x25 then                      -- options: A opens the buy list
        downs = 0
        H.setPad(phase < 4 and { "a" } or {})
      elseif st == 0x26 then                  -- buy list: steer to the row
        if downs < row then
          if phase == 0 then downs = downs + 1 end
          H.setPad(phase < 4 and { "down" } or {})
        else
          H.setPad(phase < 4 and { "a" } or {})
        end
      elseif st == 0x27 then                  -- quantity: confirm one unit
        H.setPad(phase < 4 and { "a" } or {})
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
local function cmdRowOf(actor, cmdId)
  for i = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + i * 3) == cmdId then return i end
  end
  return nil
end
local function battInvIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id then return i end
  end
  return nil
end
local function neediest()
  local best, miss = nil, 49
  for _, e in ipairs({ sabinE, cyanE, shadowE }) do
    if e and pHP(e) > 0 then
      local m = pMaxHP(e) - pHP(e)
      if m > miss then best, miss = e, m end
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
      if miss >= 150 and invCount(POTION) > 0 then item = POTION
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
    if st ~= ST_CMD then return nil end       -- wait for a settled cmd list
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
    local cur = H.readByte(ITEMIDX + actor)
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
    H.call(function() lost, fightTier, wipeN = nil, n, 0 end),
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
    holdDrive("down", function()
      return lost ~= nil
          or (mapIdx() == 142 and H.hasControl() and H.tileAligned()
              and not inBattle() and bright() >= 15)
    end, "battle 47 + mob scene (attempt " .. n .. ")", 30000, "fight"),
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
      return H.driveUntil(function()
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
  buyItem(TONIC, 0, 15, 60, "TONIC x15"),
  buyItem(POTION, 1, 6, 400, "POTION x6"),
  closeShop(),
  H.call(function()
    H.log(string.format("[shop] done: gil=%d tonics=%d potions=%d",
      gil(), invCount(TONIC), invCount(POTION)))
    H.assertEq(invCount(TONIC) >= 8, true,
      "at least 8 Tonics for the medic line (bought honestly)")
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
