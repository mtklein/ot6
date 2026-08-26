-- gen_sabin_train.lua -- boards the Phantom Train through the Ghost
-- Train's fall. Generates train_done.mss: World of Balance (178,93), on
-- foot, $003A/$003B set, SABIN+CYAN+SHADOW.
--
-- The train: exterior side-view strips 142 (rear) and 141 (front), plus
-- interior maps reused per car -- 145 plays car A ($017E=$0180=0), car B
-- ($017E=1), car C ($0180=1); $0506/$0507/$0509 pick each car's ghost
-- cast. $017E/$0180 are car bookkeeping written by every door handler.
-- The door "gates" $01B0-$01B4 are UpdateCtrlFlags' facing/A bits, firing
-- on facing-up+A. Car A's west door (142 (66,8)) reaches car B's east door
-- (58,8) along y=8. Car C's side door (142 (41,8), facing up) sets
-- $0180=1/$0509=1; walking in relocates the trap ghost to the south door,
-- and talking to it triggers battle 47 and a hard load to 142 (41,9). The
-- roof (x=40) leads to SABIN's jump to (12,8), mob catch at (11,8)
-- ($0182), car 149 at (10,8). 149's east vestibule lever at (28,5): pull
-- once sets $0183 (detach, hard landing 141 (117,8)); pull twice (after
-- re-entering) sets $017F and re-tiles the vestibule's inner door. Strip
-- 141 from (108,8) weaves lanes y=8/y=9 under door pockets, with a roof
-- bridge (y=5, ladders x=60/65/76/81) over two ground gaps; no car
-- interior is entered. Engineer door 141 (38,8) accepts entry only from
-- (38,9) facing up; valves (7,7)/(9,7) toggle $0184/$0186 (SHUT/OPEN/SHUT
-- is the smokestack's guard); (32,7) facing-up+A triggers battle 68.
--
-- No emulator state writes: random/ungated battles are fled; battle 47
-- (the trap ghost) and battle 68 (the Ghost Train) are played with real
-- input, each behind a checkpoint retry ladder. SABIN's first two turns
-- against the Ghost Train are AuraBolt (chips a shield, reveals HOLY) and
-- Pummel (chips another, reveals OT6_BLUDG); after that all three attack
-- with banked-boost Fights, healing under 50% from the ghost merchant's
-- bag. Fenix Down is never selected, so the generated state records a
-- real fight.
--
-- Win tail: victory scene -> the souls' station (Cyan's family) -> map 137
-- (1200-frame timer) -> auto-exit to the world at (178,93). SHADOW steps
-- out for the graveside scene and rejoins before the exit.
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

-- battle model (battle_vargas's map; every address is read-only here)
local GHOSTTRAIN = 0x0106
local OT6_BLUDG, HOLY = 0x04, 0x20
local PUMMEL, AURABOLT, SUPLEX = 0x5D, 0x5E, 0x5F
local SHURIKEN = 0x41                   -- the ghost merchant's row 6
local FIRE_SKEAN = 0xAB                 -- his row 7, OT6's (const.inc:271)
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS = 0x05, 0x30     -- command list; tools-shell blitz list
local ST_ITEM, ST_TGT = 0x0A, 0x38      -- item select; target select
local ST_THROW = 0x2D                   -- throw select (UpdateMenuState_2d)
local CMD_BLITZ, CMD_ITEM, CMD_THROW = 0x0A, 0x01, 0x08
local CMDTBL, ITEMLIST = 0x202E, 0x4005 -- command cells; wItemList rows
local BATTINV = 0x2686                  -- battle inventory, 5 bytes/entry
local CMDROW = 0x890F                   -- +actor: command-list cursor row
local BLSCROLL, BLCOL, BLROW = 0x895F, 0x8963, 0x8967  -- +actor: 2-col grids
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E -- live target-cursor masks
local BP = 0x3E9C                       -- banked boost points, +slot*2
local TONIC, POTION, ANTIDOTE, FENIX_DOWN = 0xE8, 0xE9, 0xF2, 0xF0
local BUCKLER, HEAVY_SHLD = 0x5A, 0x5B
local PLUMED_HAT, STAR_PENDANT, JEWEL_RING = 0x6B, 0xB1, 0xB5
local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
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
-- All four battle status bytes, not just the first.  The fight log used to
-- print status 1 alone ($3EE4, stride 2), which carries wound/poison/dark and
-- nothing else; every status that costs a character their turn lives in the
-- other three -- Berserk $10 and Muddled $20 and Sleep $80 in status 2
-- ($3EE5), Stop $10 in status 3 ($3EF8) (ff6/notes/battle-lists.txt:632-647,
-- addresses at ff6/notes/battle-ram.txt:1098-1101).  That gap cost a
-- diagnosis: a run where SABIN took one turn in fourteen and chipped once
-- read as "SABIN was not served a menu" because the byte that would have
-- said why was not being printed.  Statuses 2-4 are appended only when one
-- of them is set, so the common line stays the width it was.
local function statusStr(e)
  local s1 = H.readByte(0x3EE4 + e * 2)
  local s2 = H.readByte(0x3EE5 + e * 2)
  local s3 = H.readByte(0x3EF8 + e * 2)
  local s4 = H.readByte(0x3EF9 + e * 2)
  if s2 == 0 and s3 == 0 and s4 == 0 then
    return string.format("s%02X", s1)
  end
  return string.format("s%02X/%02X/%02X/%02X", s1, s2, s3, s4)
end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d(%dmp,%s)", pHP(e), pMaxHP(e),
      pMP(e), statusStr(e))
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

local ENCOUNTER_ALLOWANCE = 12000
local function nav(x, y, o)
  o = o or {}
  o.playBattles = "flee"
  o.maxFrames = (o.maxFrames or 20000) + ENCOUNTER_ALLOWANCE
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
  for e = 0, 3 do
    if pMaxHP(e) > 0 and pHP(e) == 0 and itemRow
       and battInvIdx(FENIX_DOWN) then
      H.log(string.format("[b47] revive: e%d is down -- FENIX DOWN [%s]",
        e, partyLine()))
      return { kind = "item", item = FENIX_DOWN, row = itemRow, target = e }
    end
  end
  -- Poison is where the strip's HP goes (see the section note): cure it
  -- before anything else, because the status persists out of the battle and
  -- drains per field step all the way to the smokestack
  local st1 = H.readByte(0x3EE4 + actor * 2)
  if (st1 & 0x04) ~= 0 and itemRow and battInvIdx(ANTIDOTE) then
    H.log(string.format("[b47] cure e%d: ANTIDOTE (status=%02X) [%s]",
      actor, st1, partyLine()))
    return { kind = "item", item = ANTIDOTE, row = itemRow }
  end
  -- top up the neediest living member (self-target only heals the actor,
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
      if st == ST_TOOLS or st == ST_ITEM or st == ST_TGT
         or st == ST_THROW then
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
    -- No named target: take the default, which is the acting character for
    -- an item and the enemy for Fight.  That is what the topups want.
    if plan.target == nil then
      fPlan, fPlanActor = nil, nil
      return { "a" }
    end
    -- A named target (the revive) is steered, the same way the b68 fighter
    -- steers its heals: off the monster side first, then down or up the
    -- party column until the live character mask is the one slot we mean.
    local chars = H.readByte(TGTCHARS)
    local mons = H.readByte(TGTMONS)
    if mons ~= 0 then return { "right" } end
    local wantMask = 1 << plan.target
    if chars == wantMask then
      fPlan, fPlanActor = nil, nil
      return { "a" }
    end
    plan.tgtStall = (plan.tgtStall or 0) + 1
    if plan.tgtStall > 20 then
      -- Unlike b68's heals, a revive on the wrong ally is a wasted Fenix
      -- Down out of a bag of four, so this gives up on the turn instead of
      -- confirming somewhere harmless.  Backing out re-plans next menu.
      H.log(string.format("[b47] revive steer stalled (chars=%02X want=%02X)" ..
        " -- backing out rather than spending the Fenix Down on the wrong " ..
        "ally", chars, wantMask))
      fPlan, fPlanActor = nil, nil
      return { "b" }
    end
    local cur = 0
    for b = 0, 3 do if chars & (1 << b) ~= 0 then cur = b; break end end
    return { cur < plan.target and "down" or "up" }
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

-- holdDrive: hold `dir` toward pred; dialogs tap-A; battles are either fled
-- (the default, because corridor encounters earn no win and no SHADOW roll)
-- or fought ("fight": the boost machine plus wipe watch, for the win-gated
-- battle 47).
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
          H.setPad({ l = true, r = true })   -- flee, with real input
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
      -- step toward him: first step of the shortest path to any
      -- neighbouring tile (re-planned every pulse, because he moves)
      local best, bd = nil, nil
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { -1, 0 }, { 1, 0 } }) do
        local p = H.bfsPath(ox + d[1], oy + d[2])
        if p and #p > 0 and (not bd or #p < bd) then best, bd = p, #p end
      end
      H.setPad(best and { [H.movePress(best[1])] = true } or {})
    end),
  }, "the ghost merchant's shop opens")
end

-- shop buys use the library's closed-loop, purse-clamp-accepting drive
-- (M.buyItem, promoted from this file's local copy; the cursor cells, the
-- widget deltas, and the clamp acceptance are documented at the definition)
local buyItem = H.buyItem

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

local b68 = {
  casts = 0, chips = {}, plan = nil, planActor = nil,
  brokeAt = nil, impossible = nil, itemsOut = false,
  lastSH, lastHP,
}
local function b68Log(msg) H.log("[b68] " .. msg) end
local function neediest(limit20)
  limit20 = limit20 or 15                       -- default: under 75%
  local best, miss, worst = nil, 0, 21
  if sabinE and pHP(sabinE) > 0 and pMaxHP(sabinE) > 0
     and pHP(sabinE) * 20 < pMaxHP(sabinE) * math.min(12, limit20) then
    return sabinE, pMaxHP(sabinE) - pHP(sabinE)
  end
  for _, e in ipairs({ sabinE, cyanE, shadowE }) do
    if e and pHP(e) > 0 and pMaxHP(e) > 0 then
      local frac20 = pHP(e) * 20 // pMaxHP(e)   -- 0..20
      if frac20 < worst and frac20 < limit20 then
        best, worst, miss = e, frac20, pMaxHP(e) - pHP(e)
      end
    end
  end
  return best, miss
end
local function makePlan(actor)
  local shields = H.readByte(SH(gSlot))
  local itemRow = cmdRowOf(actor, CMD_ITEM)
  -- Survival first, for everyone including SABIN (he died mid-chip at
  -- 80/231 three attempts in a row): revive the fallen (Fenix Down's
  -- target select initializes on the dead ally, and the steer never
  -- confirms on the monster side, so the undead throw cannot happen),
  -- cure own poison, heal under 50%.
  for e = 0, 3 do
    if pMaxHP(e) > 0 and pHP(e) == 0 and itemRow
       and battInvIdx(FENIX_DOWN) then
      b68Log(string.format("revive: e%d is down -- FENIX DOWN [%s]",
        e, partyLine()))
      return { kind = "item", item = FENIX_DOWN, target = e,
               row = itemRow }
    end
  end
  local st1 = H.readByte(0x3EE4 + actor * 2)
  if (st1 & 0x04) ~= 0 and itemRow and battInvIdx(ANTIDOTE) then
    b68Log(string.format("cure e%d: ANTIDOTE (status=%02X) [%s]",
      actor, st1, partyLine()))
    return { kind = "item", item = ANTIDOTE, target = actor,
             row = itemRow }
  end
  local hp, mx = pHP(actor), pMaxHP(actor)
  local broken = shields == 0
  local cyanLimit, sabinLimit, shadowLimit = 15, 13, 9
  if broken then cyanLimit, sabinLimit, shadowLimit = 8, 8, 8 end
  local function healPlan(tgt, miss)
    local item = nil
    if miss >= 100 and battInvIdx(POTION) then item = POTION
    elseif battInvIdx(TONIC) then item = TONIC
    elseif battInvIdx(POTION) then item = POTION end
    if item == nil then return nil end
    b68Log(string.format(
      "heal e%d: %s -> e%d (missing %d) [%s]",
      actor, item == TONIC and "TONIC" or "POTION", tgt, miss, partyLine()))
    return { kind = "item", item = item, target = tgt,
             row = cmdRowOf(actor, CMD_ITEM) }
  end
  if actor == sabinE and mx > 0 and hp > 0 and hp * 20 < mx * sabinLimit then
    local p = healPlan(actor, mx - hp)
    if p then return p end
  end
  if actor == cyanE then
    local tgt, miss = neediest(cyanLimit)
    if tgt then
      local p = healPlan(tgt, miss)
      if p then return p end
    end
  end
  if actor == shadowE then
    local tgt, miss = neediest(shadowLimit)
    if tgt then
      local p = healPlan(tgt, miss)
      if p then return p end
    end
  end
  if mx > 0 and hp > 0 and hp * 20 < mx * (broken and 8 or 10) then
    local tgt, miss = neediest(cyanLimit)       -- fallback: stay alive
    if tgt == nil then tgt, miss = actor, mx - hp end
    local p = healPlan(tgt, miss)
    if p then return p end
  end
  if actor == sabinE and shields > 0 then
    if not b68.holyRevealed and pMP(sabinE) >= 10 then
      b68Log(string.format("plan chip 1: AURABOLT (mp %d, sh %d, trainHP %d) " ..
        "[%s]", pMP(sabinE), shields, H.readWord(MHP(gSlot)), partyLine()))
      return { kind = "blitz", skill = AURABOLT,
               row = cmdRowOf(actor, CMD_BLITZ) }
    end
    if pMP(sabinE) >= 4 then
      b68Log(string.format("plan chip: PUMMEL x2 (mp %d, sh %d, trainHP %d) [%s]",
        pMP(sabinE), shields, H.readWord(MHP(gSlot)), partyLine()))
      return { kind = "blitz", skill = PUMMEL,
               row = cmdRowOf(actor, CMD_BLITZ) }
    end
    b68Log(string.format("SABIN is out of chip MP at %d shields (mp %d): " ..
      "Pummel costs 4 and AuraBolt 10, so the rest of this break is not " ..
      "fundable and he falls back to Fight", shields, pMP(sabinE)))
  end
  if actor == shadowE and shields > 0 and b68.holyRevealed
     and battInvIdx(FIRE_SKEAN) then
    b68Log(string.format("throw: SHADOW FIRE SKEAN (%d left, sh %d) " ..
      "trainHP=%d [%s]", invCount(FIRE_SKEAN), shields,
      H.readWord(MHP(gSlot)), partyLine()))
    return { kind = "throw", item = FIRE_SKEAN,
             row = cmdRowOf(actor, CMD_THROW) }
  end
  if actor == shadowE and battInvIdx(SHURIKEN) then
    b68Log(string.format("throw: SHADOW Shuriken (%d left) trainHP=%d [%s]",
      invCount(SHURIKEN), H.readWord(MHP(gSlot)), partyLine()))
    return { kind = "throw", item = SHURIKEN,
             row = cmdRowOf(actor, CMD_THROW) }
  end
  if actor == sabinE and pMP(sabinE) >= 13 then
    b68Log(string.format("cast: SABIN Suplex (mp %d) trainHP=%d [%s]",
      pMP(sabinE), H.readWord(MHP(gSlot)), partyLine()))
    return { kind = "blitz", skill = SUPLEX,
             row = cmdRowOf(actor, CMD_BLITZ) }
  end
  local bp = math.min(H.readByte(BP + actor * 2), 3)
  b68Log(string.format("cast e%d: Fight boost=%d trainHP=%d sh=%d [%s]",
    actor, bp, H.readWord(MHP(gSlot)), shields, partyLine()))
  return { kind = "fight", boost = bp }
end

-- one pulse of the b68 engine; returns the button table to hold (or nil)
local function b68Button()
  local st = H.readByte(MSTATE)
  local actor = H.readByte(ACTOR)
  local plan = b68.plan
  if plan == nil or b68.planActor ~= actor then
    if st ~= ST_CMD then
      if st == ST_TOOLS or st == ST_ITEM or st == ST_TGT
         or st == ST_THROW then
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
  if st == ST_THROW and plan.kind == "throw" then
    -- the throw list is a wItemList shell (UpdateMenuState_2d confirms
    -- through wItemList::Index); cursor = scroll $8953 + row $895B
    local want = nil
    for i = 0, 15 do
      if H.readByte(ITEMLIST + i * 3) == plan.item then want = i end
    end
    if want == nil then return { "b" } end
    local cur = H.readByte(0x8953 + actor) + H.readByte(0x895B + actor)
    if cur < want then return { "down" } end
    if cur > want then return { "up" } end
    return { "a" }                            -- -> target select (enemy)
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
  if st ~= 0x00 and st ~= 0x01 then
    b68.oddN = (b68.oddState == st) and (b68.oddN or 0) + 1 or 1
    b68.oddState = st
    if b68.oddN >= 4 then
      b68Log(string.format("unhandled menu state $%02X for %d pulses " ..
        "(actor=%d plan=%s) -- backing out", st, b68.oddN, actor,
        plan and plan.kind or "-"))
      b68.oddN = 0
      b68.plan, b68.planActor = nil, nil
      return { "b" }
    end
  else
    b68.oddN = 0
  end
  return nil                                  -- transitions: hands off
end

-- observers: shield chips, the break, and the kill, each logged with numbers
local function b68Observe()
  local shields = H.readByte(SH(gSlot))
  local hp = H.readWord(MHP(gSlot))
  if (H.readByte(RVE(gSlot)) & HOLY) == HOLY
     or (H.readByte(RVPE(gSlot)) & HOLY) == HOLY then
    b68.holyRevealed = true
  end
  if (H.readByte(RVC(gSlot)) & OT6_BLUDG) == OT6_BLUDG
     or (H.readByte(RVPC(gSlot)) & OT6_BLUDG) == OT6_BLUDG then
    b68.bludgRevealed = true
  end
  -- Every hit the train takes, attributed.  Without this the log only shows
  -- the turns the driver planned, and a fight can lose most of the train's
  -- HP to damage nobody in the log dealt -- a berserked party member, a
  -- counter, a status tick.  $3410 is the attack index the engine last
  -- resolved (the chip rows below already read it).
  if b68.lastHP and hp < b68.lastHP then
    b68Log(string.format("train -%d -> %d at f%d: lastSkill=$%02X sh=%d [%s]",
      b68.lastHP - hp, hp, H.frame, H.readByte(0x3410), shields, partyLine()))
  end
  if b68.lastSH and shields < b68.lastSH then
    local row = string.format(
      "chip %d->%d at f%d: lastSkill=$%02X trainHP=%d sabinMP=%d [%s]",
      b68.lastSH, shields, H.frame, H.readByte(0x3410), hp,
      sabinE and pMP(sabinE) or -1, partyLine())
    b68.chips[#b68.chips + 1] = row
    -- Shields off, not chip rows.  A double-hitting Pummel takes two shields
    -- in one transition (6->5->4->2 is three rows and four shields), so the
    -- row count undercounts the break and cannot be the thing asserted on.
    b68.shieldsOff = (b68.shieldsOff or 0) + (b68.lastSH - shields)
    b68Log(row)
    b68.plan = nil                            -- re-plan on fresh numbers
  end
  if shields == 0 and b68.brokeAt == nil and (b68.lastSH or 6) > 0 then
    b68.brokeAt = H.frame
    b68.brokeHP = hp
    b68Log(string.format(
      "*** BREAK COMPLETE at f%d: six shields off with the train at %d of " ..
      "1900 HP (casts=%d)", H.frame, hp, b68.casts))
    H.screenshot("train_b68_broken")
  end
  if hp == 0 and b68.killedAt == nil and b68.lastHP and b68.lastHP > 0 then
    b68.killedAt = H.frame
    b68Log(string.format("train at 0 HP at f%d (brokeAt=%s)", H.frame,
      tostring(b68.brokeAt)))
  end
  b68.lastSH, b68.lastHP = shields, hp
end


local L47 = H.newSeedLadder("battle 47")
local L68 = H.newSeedLadder("battle 68", { attempts = 5 })
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
      H.waitFrames(60),                 -- settle the reload before driving
    }, {}),
    L47.spread(n),                      -- spread the battle RNG phase (#83)
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

-- (A wander-for-an-encounter top-up was tried here and does not work: the
-- post-b47 strip has no random pool at all, and b=true never showed outside
-- battle 47 across every run.  The entry-HP loss is the field poison the
-- trap ghosts inflict, draining per step for the whole strip walk, which is
-- what "SABIN at 3/231, the drain floor" described.  The counter is bought
-- two cars back: Antidotes, used inside battle 47 before the ghosts are
-- killed.)

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
  return H.cond(function() return not b68won end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[train] b68 ATTEMPT %d -- reloading (%s)",
          n, tostring(lost))
      end),
      H.call(function() ldReq = H.requestLoadState(b68Blob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "b68 attempt " .. n) end),
      H.waitFrames(60),                 -- settle the reload before driving
    }, {}),
    L68.spread(n),                      -- spread the battle RNG phase (#83)
    H.call(function()
      lost, wipeN = nil, 0
      b68.casts, b68.chips = 0, {}
      b68.plan, b68.planActor = nil, nil
      b68.brokeAt, b68.killedAt, b68.brokeHP = nil, nil, nil
      b68.shieldsOff = 0
      b68.holyRevealed, b68.bludgRevealed = false, false
      b68.itemsOut = false
      b68.lastSH, b68.lastHP = nil, nil
      b68.tornDown, b68.mstreak, b68.sabinDeadN = 0, 0, 0
      b68.oddState, b68.oddN, b68.sabinImpN = nil, 0, 0
      gSlot, sabinE, cyanE, shadowE = nil, nil, nil, nil
    end),
    H.cond(function() return lost ~= nil end, { H.waitFrames(1) }, {
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
        return lost ~= nil or b68.tornDown >= 3
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
          -- SABIN down pre-break: the chip engine is gone, and there is no
          -- Fenix Down on the pacifist line, so this attempt is over
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
          if (H.readByte(0x3EE4 + sabinE * 2) & 0x20) ~= 0
             and H.readByte(SH(gSlot)) > 0 then
            b68.sabinImpN = (b68.sabinImpN or 0) + 1
            if b68.sabinImpN >= 90 and not lost then
              lost = string.format("SABIN is Imp'd pre-break at f%d, so no " ..
                "Blitz and no more chips (shields=%d casts=%d) [%s]",
                H.frame, H.readByte(SH(gSlot)), b68.casts, partyLine())
              H.log("[b68] LOST -- " .. lost)
            end
          else
            b68.sabinImpN = 0
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
      if lost == nil and b68.killedAt == nil then
        lost = string.format("battle 68 ended without the train at 0 HP " ..
          "(a wipe-teardown) at f%d [%s]", H.frame, partyLine())
        H.log("[b68] " .. lost)
      end
      if lost == nil and not inParty(3) then
        lost = string.format("SHADOW walked off after battle 68's win " ..
          "(the 1/16 roll) at f%d -- a shifted retry re-rolls it", H.frame)
        H.log("[train] " .. lost)
      end
      if lost == nil and (b68.shieldsOff or 0) < 6 then
        lost = string.format("battle 68 won at f%d but only %d of 6 shields " ..
          "came off -- the break did not complete, so this attempt does not " ..
          "meet the step's obligation (casts=%d) [%s]", H.frame,
          b68.shieldsOff or 0, b68.casts, partyLine())
        H.log("[b68] LOST -- " .. lost)
        for _, row in ipairs(b68.chips) do
          H.log("[b68 attempt " .. n .. "] " .. row)
        end
      end
      if lost == nil then
        H.assertEq((b68.shieldsOff or 0) >= 6, true,
          "six chips landed -- all six shields came off (#74's break)")
        H.log(string.format(
          "[b68] break margin: train at %s of 1900 HP when the sixth shield " ..
          "came off, dead %s frames later (brokeAt=%s killedAt=%s)",
          tostring(b68.brokeHP), b68.brokeAt and b68.killedAt
            and tostring(b68.killedAt - b68.brokeAt) or "?",
          tostring(b68.brokeAt), tostring(b68.killedAt)))
        H.assertEq(#b68.chips >= 2, true,
          "at least two shield chips landed (the mechanism proofs)")
        H.assertEq(b68.holyRevealed, true,
          "AuraBolt's HOLY reveal went live (banked or committed)")
        H.assertEq(b68.bludgRevealed, true,
          "Pummel's OT6_BLUDG class reveal went live (banked or committed)")
        b68won = true
        H.log(string.format("[b68] attempt %d WON: killedAt=f%s " ..
          "brokeAt=%s casts=%d chips=%d", n, tostring(b68.killedAt),
          tostring(b68.brokeAt), b68.casts, #b68.chips))
      else
        for _, row in ipairs(b68.chips) do
          H.log("[b68 attempt " .. n .. "] " .. row)
        end
      end
    end),
    }),
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
  end),

  H.equipLoadout(2, {
    { 1, HEAVY_SHLD },
  }, { tag = "CYAN Phantom Train kit" }),
  H.equipLoadout(5, {
    { 1, BUCKLER }, { 4, STAR_PENDANT }, { 5, JEWEL_RING },
  }, { tag = "SABIN Phantom Train kit" }),
  H.equipLoadout(3, {
    { 2, PLUMED_HAT },
  }, { tag = "SHADOW Phantom Train kit" }),




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
  buyItem(TONIC, 0, function() return 30 - invCount(TONIC) end, "TONIC to 30"),
  buyItem(ANTIDOTE, 2, function() return 3 - invCount(ANTIDOTE) end,
    "ANTIDOTE to 3"),
  -- Fenix Downs are for reviving allies (battle 47's prolonged tail killed
  -- SHADOW, measurably, and he entered the boss fight dead); the item target
  -- steer never confirms on the monster side, so the undead-instant-kill
  -- throw is not reachable
  buyItem(FENIX_DOWN, 4, function() return 4 - invCount(FENIX_DOWN) end,
    "FENIX DOWN to 4"),
  buyItem(SHURIKEN, 6, function() return 10 - invCount(SHURIKEN) end,
    "SHURIKEN to 10"),
  buyItem(FIRE_SKEAN, 7, function() return 2 - invCount(FIRE_SKEAN) end,
    "FIRE SKEAN to 2"),
  -- Potions drop from 15 to 11 to pay for them: 4 Potions is 1200 GP against
  -- the skeans' 1000, so the purse that leaves this shop is 1634 rather than
  -- the 1434 the Potion-heavy list left, and the scenario's later stops are
  -- funded a little better than before rather than worse.  11 is still above
  -- the medic line's floor asserted below.
  buyItem(POTION, 1, function() return 10 - invCount(POTION) end,
    "POTION to 10"),
  closeShop(),
  H.call(function()
    H.log(string.format("[shop] done: gil=%d tonics=%d potions=%d skeans=%d",
      gil(), invCount(TONIC), invCount(POTION), invCount(FIRE_SKEAN)))
    H.assertEq(invCount(TONIC) >= 12, true,
      "at least 12 Tonics for the medic line (bought)")
    H.assertEq(invCount(POTION) >= 8, true,
      "at least 8 Potions for the medic line (bought)")
    H.assertEq(invCount(FIRE_SKEAN) >= 2, true,
      "two Fire Skeans for SHADOW's chip (bought, #74)")
  end),

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

  -- ---- battle 47, with real input, behind the ladder ----
  b47Checkpoint(),
  L47.watch(),
  b47Attempt(1),
  b47Attempt(2),
  b47Attempt(3),
  L47.report(),
  H.call(function()
    if not b47Won() then
      error(string.format("train: battle 47 did not complete cleanly on " ..
        "any of 3 attempts -- last: %s -- do not rig this segment",
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

  H.fieldCare({ tag = "pre-smokestack care", threshold = 0.95 }),

  -- The strip is where SHADOW can still be lost, and it is worth saying so
  -- here rather than three steps later.  Fleeing rolls nothing, but a
  -- formation that refuses the run gets fought out, and a win rolls his 1/16
  -- walk-off (battle_main.asm:11976-11991).  He is checked at the end of the
  -- run too, but by then the failure reads as a missing party entity inside
  -- battle 68's setup; naming it at the last point he was definitely aboard
  -- says which walk lost him.  This is also the checkpoint's entry contract:
  -- every b68 attempt reloads a blob taken below, so a SHADOW who is gone now
  -- is gone from all three attempts.
  H.call(function()
    H.assertEq(inParty(3), true,
      "SHADOW still aboard after the strip walk (a fought-out corridor " ..
      "encounter rolls his 1/16 leave; a fled one does not)")
    H.log(string.format("[train] pre-smokestack bag: tonics=%d potions=%d " ..
      "skeans=%d shurikens=%d fenix=%d gil=%d", invCount(TONIC),
      invCount(POTION), invCount(FIRE_SKEAN), invCount(SHURIKEN),
      invCount(FENIX_DOWN), gil()))
  end),

  b68Checkpoint(),
  L68.watch(),
  b68Attempt(1),
  b68Attempt(2),
  b68Attempt(3),
  b68Attempt(4),
  b68Attempt(5),
  L68.report(),
  H.call(function()
    if not b68Won() then
      error(string.format("train: battle 68 did not complete cleanly on " ..
        "any of 5 attempts -- last: %s", tostring(lost)), 0)
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
    H.log(string.format("[b68 record] shieldsOff=%d brokeAt=%s killedAt=%s " ..
      "brokeHP=%s casts=%d", b68.shieldsOff or 0, tostring(b68.brokeAt),
      tostring(b68.killedAt), tostring(b68.brokeHP), b68.casts))
  end),

  -- A full break costs more HP than the old line that stopped at five
  -- shields, and the ride out does not heal: the first run to complete the
  -- break saved SHADOW at 38/197, which clears the party-hp audit's near-fatal
  -- floor (max/8 = 24) by fourteen points and is no state to hand the Baren
  -- Falls step.  The bag that funded the fight still has Tonics in it and the
  -- world map is a healing surface, so spend them here rather than shipping
  -- the fixture thin.  0.9 rather than full, because a Tonic is 50 HP and the
  -- last few points cost a whole item each.
  H.fieldCare({ tag = "post-train care", threshold = 0.9 }),
  H.call(function()
    -- The same three conditions as tools/audit_party_hp.py, and the two are
    -- changed together: the audit is the net after a full `make savestates`,
    -- this is the trip-wire at the moment the state was about to be saved.
    H.assertPartyStanding("train_done")
    H.screenshot("train_done")
  end),
  H.saveState("train_done.mss"),
  H.logStep(function()
    return string.format("train_done generated at frame %d world (%d,%d) -- " ..
      "battle 68 won with all six shields chipped off (the margin to the " ..
      "kill is in the [b68] break margin line, not asserted)",
      H.frame, H.worldX(), H.worldY())
  end),
})
