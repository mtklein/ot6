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
-- The save point (#218): map 146 is two rooms. The engineer's room the
-- front door opens on is one pocket; the other, reached from map 152
-- (8,7) -> 146 (23,12), holds the train's SavePoint at (20,10). Map 152
-- hangs off the rear strip at 142 (83,8)/(85,8)/(86,8), which is the
-- pocket car A's EAST door (145 (30,7)/(30,8) -> 142 (75,8)) lands in.
-- The save is taken there, right after the departure.
--
-- No emulator state writes: random/ungated battles are fought by the
-- library fighter (H.newWalkFighter, #183); battle 47
-- (the trap ghost) and battle 68 (the Ghost Train) are played with real
-- input; battle 47 sits behind a checkpoint retry sweep, battle 68 is
-- fought once and a wipe there is the segment runner's to retry. SABIN's
-- first two turns against the Ghost Train are AuraBolt (chips a shield,
-- reveals HOLY) and Pummel (chips another, reveals OT6_BLUDG); after that
-- all three attack with banked-boost Fights, healing under 50% from the
-- ghost merchant's bag, reviving the fallen with Fenix Down and curing an
-- Imp with the bag's cure. The train killed before its last shield comes
-- off is a win (docs/guidelines.md, #311), logged as a [tuning] line.
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
-- frames between a reveal and the chip its hit landed: the reveal banks
-- (OT6_RVPEND_*) and the shield comes off in the same damage calc, and the
-- observer sees both on one frame (build/attempts/wt/train-win/review:
-- "HOLY: AuraBolt ($5E) cast f1347, its first chip f1409, revealed f1409",
-- "OT6_BLUDG: Pummel ($5D) cast f2427, its first chip f2893, revealed
-- f2893").  Two frames of slack for a hit that straddles a frame edge.
local REVEAL_SLACK = 2
local SHURIKEN = 0x41                   -- the ghost merchant's row 6
local FIRE_SKEAN = 0xAB                 -- his row 7, OT6's (const.inc:271)
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS = 0x05, 0x30     -- command list; tools-shell blitz list
local ST_ITEM, ST_TGT = 0x0A, 0x38      -- item select; target select
local ST_THROW = 0x2D                   -- throw select (UpdateMenuState_2d)
local ST_ROW, ST_DEF = 0x24, 0x27       -- Row / Def. side windows (lib's ST_ROW)
local CMD_BLITZ, CMD_ITEM, CMD_THROW = 0x0A, 0x01, 0x08
local CMDTBL, ITEMLIST = 0x202E, 0x4005 -- command cells; wItemList rows
local BATTINV = 0x2686                  -- battle inventory, 5 bytes/entry
local CMDROW = 0x890F                   -- +actor: command-list cursor row
local BLSCROLL, BLCOL, BLROW = 0x895F, 0x8963, 0x8967  -- +actor: 2-col grids
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E -- live target-cursor masks
local BP = 0x3E9C                       -- banked boost points, +slot*2
local TONIC, POTION, ANTIDOTE, FENIX_DOWN = 0xE8, 0xE9, 0xF2, 0xF0
local REMEDY = 0xF5
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
-- The lib fight driver's battle-open, [death] and Fenix Down landing lines
-- (newFightDriver, lib/ot6.lua) for a fight this file drives itself, so
-- tools/audit_boost.py sees the pips a member held when they fell and
-- tools/audit_fenix.py the fight a Fenix Down answered (#220).  Ticks count
-- from the first frame the battle table is live with monsters present; no
-- monster action is attributed.
local function newDeathWatch(tag)
  local W = {}
  function W.reset()
    W.tick, W.opened, W.hp, W.said, W.raise = 0, false, {}, {}, {}
  end
  W.reset()
  function W.frame()
    if not H.battleLoadStarted() then W.reset(); return end
    if not W.opened and H.monstersPresent() == 0 then return end
    W.tick = W.tick + 1
    local pbp = {}
    for p = 0, 3 do pbp[#pbp + 1] = tostring(H.readByte(0x3E9C + p * 2)) end
    local party_bp = table.concat(pbp, ",")
    if not W.opened then
      W.opened = true
      local hp = {}
      for e = 0, 3 do hp[#hp + 1] = tostring(H.readWord(0x3BF4 + e * 2)) end
      H.log(string.format("[%s] battle f+%d partyhp=%s party_bp=%s monsters=%d",
        tag, W.tick, table.concat(hp, ","), party_bp, H.monstersPresent()))
    end
    for e = 0, 3 do
      local hp, maxhp = H.readWord(0x3BF4 + e * 2), H.readWord(0x3C1C + e * 2)
      local last = W.hp[e]
      if last ~= nil and last ~= 0xFFFF and last > 0 and hp == 0 and maxhp > 0
         and not W.said[e] then
        W.said[e] = true
        local bp = H.readByte(0x3E9C + e * 2)
        H.log(string.format("[%s] [death] f+%d entity %d char %d from %d/%d by "
          .. "nobody (no monster action attributed) bp=%d party_bp=%s%s", tag,
          W.tick, e, H.readByte(0x3ED8 + e * 2), last, maxhp, bp, party_bp,
          bp >= 3 and string.format(" -- died holding %d BP", bp) or ""))
      elseif hp > 0 and hp ~= 0xFFFF then
        W.said[e] = nil
      end
      W.hp[e] = hp
      local r = W.raise[e]
      if r ~= nil then
        if hp > 0 and hp ~= 0xFFFF then
          H.log(string.format("[%s] actor %d's Fenix Down landed: entity %d is at "
            .. "%d/%d at tick %d", tag, r.by, e, hp, maxhp, W.tick))
          W.raise[e] = nil
        elseif W.tick - r.tick > 840 then
          H.log(string.format("[%s] actor %d's Fenix Down on entity %d never landed "
            .. "(%d ticks) -- forgetting it", tag, r.by, e, W.tick - r.tick))
          W.raise[e] = nil
        end
      end
    end
  end
  function W.fenix(actor, e) W.raise[e] = { by = actor, tick = W.tick } end
  return W
end
local b47Watch, b68Watch = newDeathWatch("b47"), newDeathWatch("b68")
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
-- the battle inventory's count of an item (what an in-battle decision
-- reads; the field inventory at $1969 is not kept in step during a battle)
local function battCount(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id then
      return H.readByte(BATTINV + i * 5 + 3)
    end
  end
  return 0
end
local function battInvIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id
       and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end

-- maxFrames is a walking budget: navTo charges only the frames spent
-- walking, not those in a battle or a care stop (lib/ot6_field.lua), so a
-- leg that meets encounters needs no allowance on top of it.
local function nav(x, y, o)
  o = o or {}
  o.playBattles = "tactical"
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
         or st == ST_THROW or st == ST_ROW or st == ST_DEF then
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
    -- UP and DOWN only: LEFT/RIGHT here open Row/Def. (#366, b68Button);
    -- a row never reached fails by name (12 steering pulses on one plan)
    plan.rowStall = (plan.rowStall or 0) + 1
    if plan.rowStall > 12 then
      error(string.format("battle 47: the command steer is stuck -- actor %d's " ..
        "cursor on row %d after %d steering pulses wanting row %d", actor, cur, plan.rowStall,
        plan.row), 0)
    end
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
      if plan.item == FENIX_DOWN then b47Watch.fenix(actor, plan.target) end
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
  if st == ST_TOOLS or st == ST_ROW or st == ST_DEF then return { "b" } end
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
-- #163: runs EVERY frame of a fight-mode drive and of the battle-68 loop,
-- not behind the inBattle() gate.  A wipe zeroes every battle-HP word,
-- which inBattle() and battleLoadStarted() both read as "no battle", so
-- the old gate hid the one state the watch existed for and a lost battle
-- 47 idled to its 29000-frame deadline (gen_sabin_falls, #159, had the
-- same shape).  The lib's canary now counts the same wipe as a game over
-- at 300 frames and freezes the pad; allowGameOver on the run keeps it
-- alive for the reload, and the counter is a loss here too.
local function wipeWatch(tag)
  local wiped = H.partyWipedInBattle()
  wipeN = wiped and wipeN + 1 or 0
  if (H.gameOverFired or 0) > 0 and not lost then
    lost = string.format("%s: GAME OVER counted by the canary at f%d (tier %d) [%s]",
      tag, H.frame, fightTier, partyLine())
    H.log("[train] LOST -- " .. lost)
  end
  if wipeN >= 90 and not lost then
    lost = string.format("%s: PARTY WIPED at f%d (tier %d) [%s]",
      tag, H.frame, fightTier, partyLine())
    H.log("[train] LOST -- " .. lost)
    H.screenshot("train_lost")
  end
end

-- holdDrive: hold `dir` toward pred; dialogs tap-A; battles are fought --
-- corridor encounters by the library fighter (#183: they used to be fled,
-- which earned no XP), the win-gated battle 47 by the custom boost
-- machine plus wipe watch ("fight").
-- A walk that meets random encounters charges its budget with WALKING
-- frames only, navTo's rule (lib/ot6_field.lua's walk budget): the frames
-- the walk fighter spends in a battle or its care stop do not count, and
-- the driveUntil cap (budget + 80000) is the hard backstop.  The budget
-- is for the steps: a random 60 frames into a 4000-frame "-> car B" took
-- the rest of a whole-frame budget on a varied draw
-- (build/attempts/wt/train-mp/: K=3 encounters used up, shift 41, old and
-- new library alike).  The "fight" mode (battle 47) keeps its own budget:
-- that walk IS the battle.
local function holdDrive(dir, pred, what, budget, fightMode)
  local phase, hb = 0, -600
  local W = fightMode ~= "fight" and H.newWalkFighter("holdDrive " .. what) or nil
  budget = budget or 15000
  local walked, started = 0, 0
  return H.cond(function() return true end, {
    H.call(function() walked, started = 0, H.frame end),
    H.driveUntil(pred, W and budget + 80000 or budget, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("drive[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s b=%s",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle())))
      end
      if fightMode == "fight" then
        wipeWatch(what)                    -- every frame, outside the gate
        b47Watch.frame()
        if lost then H.setPad({}); return end
      end
      if W then
        if W.frame() then return end
        walked = walked + 1
        if walked > budget then
          error(string.format("holdDrive %s: timeout after %d walk frames " ..
            "(battle and care frames excluded; %d frames in all, %d fought)",
            what, budget, H.frame - started, W.fought()), 0)
        end
      elseif inBattle() or H.battleLoadStarted() then
        fightPulse(phase)
        return
      end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, what),
    H.call(function()
      if W then
        H.log(string.format("[walk] %s: %d walk frames of %d, %d frames in all, " ..
          "%d random(s) fought", what, walked, budget, H.frame - started, W.fought()))
      end
    end),
  }, {})
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
local function mstateMenu() return H.readByte(0x0026) end

-- open the merchant's shop: chase obj 29, poke, steer the $02D0 choice to
-- 0 (and any other choice to 1), until the menu module reads shop-options
local function openShop()
  local phase, W = 0, H.newWalkFighter("openShop")
  -- a choice window: H.newChoice (lib/ot6_field.lua) picks by dialog id,
  -- owns the pad only while the dialog waits, and asserts the landed row
  local C = H.newChoice(function(dlg) return dlg == 0x02D0 and 0 or 1 end,
    { ready = "pass", tag = "openShop" })
  return H.driveUntil(function() return mstateMenu() == 0x25 end, 20000, {
    H.call(function()
      phase = (phase + 1) % 8
      if W.frame() then return end
      -- a choice is open: pick by dialog id (see the hazard note)
      if C.frame(phase) then return end
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
  casts = 0, chips = {}, plan = nil, planActor = nil, impCure = {}, reviveFor = {}, chipAt = {}, castAt = {},
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
-- #366: the bank is spent on the damage turns, not carried to the grave.
-- The v0.24 wipe and this branch's lab both died "holding 5 BP": SABIN's
-- chips and SHADOW's throws were never boosted, so every pip they banked
-- past the fifth was lost and a member a round from death took his pips
-- with him.  A boosted Blitz is the x2/x4/x8 multiplier at an escalating
-- price (Ot6BoostPriceFor; H.boostPlan is where a fighter reads it), so a
-- chip boosts only with the MP the rest of the break does not need: the
-- reserve is the unboosted Pummels (two shields each) that take the
-- shields this cast leaves.  After the break (Suplex) nothing is
-- reserved.  A Throw is multiplied and costs no MP (Ot6BoostDmg gates it
-- in; probe_throw_boost), so a throw spends the bank whole, as Fight does.
local function blitzBoost(skill, shields)
  local want = math.min(H.readByte(BP + sabinE * 2), 3)
  if want == 0 then return 0 end
  local left = math.max(0, shields - (skill == PUMMEL and 2 or 1))
  local reserve = ((left + 1) // 2) * (H.abilityCost(PUMMEL) or 4)
  local boost, ok = H.boostPlan({ slot = sabinE, id = skill, want = want,
    reserve = reserve, tag = "b68" })
  return ok and boost or 0
end
local function makePlan(actor)
  local shields = H.readByte(SH(gSlot))
  local itemRow = cmdRowOf(actor, CMD_ITEM)
  -- Survival first, for everyone including SABIN (he died mid-chip at
  -- 80/231 three attempts in a row): revive the fallen (Fenix Down's
  -- target select initializes on the dead ally, and the steer never
  -- confirms on the monster side, so the undead throw cannot happen),
  -- cure own poison, heal under 50%.
  -- One revive per fallen member in flight (#341), the imp cure's rule
  -- below: a Fenix Down an ally has planned on a member stands until that
  -- ally's next command menu (its queued action has run by then), its
  -- death, or the member standing again.  Two allies spent two Fenix
  -- Downs on one corpse in the Ghost Train's losses (sweep4
  -- tw_k0_s0_pre68_w29: `revive: e2 is down` twice, both landing).
  for e, rec in pairs(b68.reviveFor) do
    if rec.by == actor or pHP(rec.by) == 0 or pHP(e) > 0 then b68.reviveFor[e] = nil end
  end
  for e = 0, 3 do
    if pMaxHP(e) > 0 and pHP(e) == 0 and itemRow
       and battInvIdx(FENIX_DOWN) then
      if b68.reviveFor[e] then
        b68Log(string.format("no revive on e%d: e%d's Fenix Down on it is in flight [%s]",
          e, b68.reviveFor[e].by, partyLine()))
      else
        b68Log(string.format("revive: e%d is down -- FENIX DOWN [%s]",
          e, partyLine()))
        b68.reviveFor[e] = { by = actor }
        return { kind = "item", item = FENIX_DOWN, target = e,
                 row = itemRow }
      end
    end
  end
  -- #403: a Muddled or Berserk SABIN gets no cure here.  No item in this
  -- ROM removes either (item_prop: no record carries STATUS2 $20 or $10
  -- with the remove flag).  The one other cure, an ally's plain Fight on a
  -- Muddled SABIN, was tried and measured worse: a Fight's target select
  -- opens on the monster side and RIGHT never crossed to the party there
  -- (the menu sat at $38 while the train played on), both runs that tried
  -- wiped where the same keys won without it, and the train's own hits
  -- clear Muddle within a round anyway (be14: s00/20 at f1245, clear by
  -- f2093; build/attempts/wt/v026-route2/e403/).  Berserk fights the train
  -- on his own, which is what the plan wanted of him.
  local st1 = H.readByte(0x3EE4 + actor * 2)
  if (st1 & 0x04) ~= 0 and itemRow and battInvIdx(ANTIDOTE) then
    b68Log(string.format("cure e%d: ANTIDOTE (status=%02X) [%s]",
      actor, st1, partyLine()))
    return { kind = "item", item = ANTIDOTE, target = actor,
             row = itemRow }
  end
  -- Imp: an imp's Fight lands for 0 and its Blitz and Throw are greyed
  -- (lib/ot6.lua's ST1_IMP note), so a person cures it -- the actor's own
  -- first, then SABIN's (his Blitz is the chip engine), then anyone's --
  -- with the bag's cure, read from the ROM's item records (Green Cherry,
  -- then Remedy).  With no cure in the bag the imp fights on below.
  -- One cure per imp: a cure an ally has already planned on it is not
  -- doubled while it is in flight -- until that ally's next command menu
  -- (its queued action has run by then) or its death.
  for e, rec in pairs(b68.impCure) do
    if rec.by == actor or pHP(rec.by) == 0 then b68.impCure[e] = nil end
  end
  local impOrder = { actor, sabinE, cyanE, shadowE }
  for _, e in ipairs(impOrder) do
    if e and itemRow and pHP(e) > 0 and not b68.impCure[e]
       and (H.readByte(0x3EE4 + e * 2) & H.ST1_IMP) ~= 0 then
      local cure = H.statusCure({ byte = 1, bit = H.ST1_IMP,
        has = function(item) return battInvIdx(item) ~= nil end })
      if cure then
        b68Log(string.format("cure e%d: e%d is an IMP -- item $%02X [%s]",
          actor, e, cure, partyLine()))
        b68.impCure[e] = { by = actor }
        return { kind = "item", item = cure, target = e, row = itemRow }
      end
      if not b68.impSaid then
        b68.impSaid = true
        b68Log(string.format("e%d is an IMP and the battle inventory holds " ..
          "no cure (Green Cherry %d, Remedy %d) -- fighting on [%s]", e,
          battCount(H.GREEN_CHERRY), battCount(REMEDY), partyLine()))
      end
    end
  end
  local imp = (H.readByte(0x3EE4 + actor * 2) & H.ST1_IMP) ~= 0
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
  -- #410: a player who knows the joke suplexes the train, and in OT6 that
  -- wins (Ot6SuplexTrain): SABIN's first free turn is a Suplex whenever he
  -- can pay for it.
  if actor == sabinE and not imp and pMP(sabinE) >= (H.abilityCost(SUPLEX) or 13)
     and H.readWord(MHP(gSlot)) > 0 then
    b68Log(string.format("cast: SABIN Suplexes the train (the joke, #410; mp %d) trainHP=%d [%s]",
      pMP(sabinE), H.readWord(MHP(gSlot)), partyLine()))
    return { kind = "blitz", skill = SUPLEX, boost = 0, row = cmdRowOf(actor, CMD_BLITZ) }
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
  if actor == sabinE and shields > 0 and not imp then
    if not b68.holyRevealed and pMP(sabinE) >= 10 then
      local boost = blitzBoost(AURABOLT, shields)
      b68Log(string.format("plan chip 1: AURABOLT boost=%d (mp %d, sh %d, " ..
        "trainHP %d) [%s]", boost, pMP(sabinE), shields,
        H.readWord(MHP(gSlot)), partyLine()))
      return { kind = "blitz", skill = AURABOLT, boost = boost,
               row = cmdRowOf(actor, CMD_BLITZ) }
    end
    if pMP(sabinE) >= 4 then
      local boost = blitzBoost(PUMMEL, shields)
      b68Log(string.format("plan chip: PUMMEL x2 boost=%d (mp %d, sh %d, " ..
        "trainHP %d) [%s]", boost, pMP(sabinE), shields,
        H.readWord(MHP(gSlot)), partyLine()))
      return { kind = "blitz", skill = PUMMEL, boost = boost,
               row = cmdRowOf(actor, CMD_BLITZ) }
    end
    b68Log(string.format("SABIN is out of chip MP at %d shields (mp %d): " ..
      "Pummel costs 4 and AuraBolt 10, so the rest of this break is not " ..
      "fundable and he falls back to Fight", shields, pMP(sabinE)))
  end
  if actor == shadowE and shields > 0 and b68.holyRevealed and not imp
     and battInvIdx(FIRE_SKEAN) then
    local boost = math.min(H.readByte(BP + actor * 2), 3)
    b68Log(string.format("throw: SHADOW FIRE SKEAN boost=%d (%d left, sh %d) " ..
      "trainHP=%d [%s]", boost, invCount(FIRE_SKEAN), shields,
      H.readWord(MHP(gSlot)), partyLine()))
    return { kind = "throw", item = FIRE_SKEAN, boost = boost,
             row = cmdRowOf(actor, CMD_THROW) }
  end
  if actor == shadowE and not imp and battInvIdx(SHURIKEN) then
    local boost = math.min(H.readByte(BP + actor * 2), 3)
    b68Log(string.format("throw: SHADOW Shuriken boost=%d (%d left) trainHP=%d [%s]",
      boost, invCount(SHURIKEN), H.readWord(MHP(gSlot)), partyLine()))
    return { kind = "throw", item = SHURIKEN, boost = boost,
             row = cmdRowOf(actor, CMD_THROW) }
  end
  if actor == sabinE and not imp and pMP(sabinE) >= 13 then
    local boost = blitzBoost(SUPLEX, 0)
    b68Log(string.format("cast: SABIN Suplex boost=%d (mp %d) trainHP=%d [%s]",
      boost, pMP(sabinE), H.readWord(MHP(gSlot)), partyLine()))
    return { kind = "blitz", skill = SUPLEX, boost = boost,
             row = cmdRowOf(actor, CMD_BLITZ) }
  end
  -- an imp's Fight lands for 0: the pips stay banked for after the cure
  local bp = imp and 0 or math.min(H.readByte(BP + actor * 2), 3)
  b68Log(string.format("cast e%d: Fight boost=%d%s trainHP=%d sh=%d [%s]",
    actor, bp, imp and " (an IMP)" or "", H.readWord(MHP(gSlot)), shields,
    partyLine()))
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
         or st == ST_THROW or st == ST_ROW or st == ST_DEF then
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
    -- closed-loop steering, UP and DOWN only; the engine skips invalid
    -- rows itself.  (#366: this used to fall back to LEFT/RIGHT as
    -- "absolute jumps" after two stalled pulses, but LEFT and RIGHT on the
    -- command window open the Row and Def. side windows ($24/$27,
    -- UpdateMenuState_24) -- the "unhandled menu state $24 ... plan=blitz"
    -- of the v0.24 wipe was SABIN's steer toward Blitz, row 1, pressing
    -- LEFT.)  A row the cursor never reaches fails by name rather than
    -- running to the frame cap: four rows take at most three presses, so
    -- 12 steering pulses on one plan is a stuck steer.
    plan.rowStall = (plan.rowStall or 0) + 1
    if plan.rowStall > 12 then
      error(string.format("battle 68: the command steer is stuck -- actor %d's " ..
        "cursor on row %d after %d steering pulses wanting row %d (plan %s)", actor, cur,
        plan.rowStall, wantRow, plan.kind), 0)
    end
    return { cur < wantRow and "down" or "up" }
  end
  -- Row / Def. (lib/ot6.lua's ST_ROW/ST_DEF): open only if a direction
  -- reached the command window, which this fighter no longer presses
  -- there.  A in $24 would change the row and spend the turn; B closes
  -- it ($24 -> $05) with the turn and the plan intact.
  if st == ST_ROW or st == ST_DEF then
    b68.sideN = (b68.sideN or 0) + 1
    b68Log(string.format("side window $%02X open (actor=%d plan=%s, #%d this battle) -- B out",
      st, actor, plan.kind, b68.sideN))
    -- The bound, derived: this fighter presses no LEFT/RIGHT at the command
    -- window.  A side window can open only from a direction held into the
    -- battle (once) or a target steer's RIGHT that landed after its window
    -- closed under it (at most once per RIGHT sent), so more openings than
    -- RIGHTs + 1 means something else is pressing.
    if b68.sideN > (b68.rightN or 0) + 1 then
      error(string.format("battle 68: the Row/Def. side window ($%02X) opened %d times " ..
        "against %d target-steer RIGHT(s) + 1 -- something presses LEFT/RIGHT on the " ..
        "command window (actor %d, plan %s)", st, b68.sideN, b68.rightN or 0, actor,
        plan.kind), 0)
    end
    return { "b" }
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
    if actor == sabinE then b68.sabinCmdAt = H.frame end
    b68.castAt[plan.skill] = b68.castAt[plan.skill] or H.frame
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
      if actor == sabinE then b68.sabinCmdAt = H.frame end
      b68.plan, b68.planActor = nil, nil      -- Fight commits on this confirm
      return { "a" }                          -- default target
    end
    local chars = H.readByte(TGTCHARS)
    local mons = H.readByte(TGTMONS)
    if mons ~= 0 then                         -- off the monster side
      b68.rightN = (b68.rightN or 0) + 1      -- a RIGHT that could land on $05
      plan.sideStall = (plan.sideStall or 0) + 1
      if plan.sideStall > 8 then
        b68Log(string.format("target steer never left the monster side in %d RIGHTs " ..
          "(plan %s) -- backing out", plan.sideStall, plan.kind))
        b68.plan, b68.planActor = nil, nil
        return { "b" }
      end
      return { "right" }
    end
    local wantMask = 1 << plan.target
    if chars == wantMask then
      if plan.item == FENIX_DOWN then b68Watch.fenix(actor, plan.target) end
      if actor == sabinE then b68.sabinCmdAt = H.frame end
      b68.plan, b68.planActor = nil, nil      -- item commits on this confirm
      return { "a" }
    end
    plan.tgtStall = (plan.tgtStall or 0) + 1
    if plan.tgtStall > 20 then
      b68Log(string.format("target steer stalled (chars=%02X want=%02X) " ..
        "-- accepting the current party target", chars, wantMask))
      if plan.item == FENIX_DOWN then b68Watch.fenix(actor, plan.target) end
      if actor == sabinE then b68.sabinCmdAt = H.frame end
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
  -- the last frame SABIN was Muddled or Berserk: an action the engine
  -- picked for him, not this fighter (a hit can cure Muddle before the
  -- picked action lands, so the chip itself may see him clear)
  if sabinE and (H.readByte(0x3EE5 + sabinE * 2) & (H.ST2_MUDDLE | H.ST2_BERSERK)) ~= 0 then
    b68.wildAt = H.frame
  end
  local shields = H.readByte(SH(gSlot))
  local hp = H.readWord(MHP(gSlot))
  if (H.readByte(RVE(gSlot)) & HOLY) == HOLY
     or (H.readByte(RVPE(gSlot)) & HOLY) == HOLY then
    if not b68.holyRevealed then
      b68.holyAt, b68.holyBy = H.frame, H.readByte(0x3410)
      b68Log(string.format("HOLY revealed at f%d (lastSkill=$%02X)", H.frame,
        H.readByte(0x3410)))
    end
    b68.holyRevealed = true
  end
  if (H.readByte(RVC(gSlot)) & OT6_BLUDG) == OT6_BLUDG
     or (H.readByte(RVPC(gSlot)) & OT6_BLUDG) == OT6_BLUDG then
    if not b68.bludgRevealed then
      b68.bludgAt, b68.bludgBy = H.frame, H.readByte(0x3410)
      b68Log(string.format("OT6_BLUDG revealed at f%d (lastSkill=$%02X)",
        H.frame, H.readByte(0x3410)))
    end
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
    local sk = H.readByte(0x3410)
    if b68.chipAt[sk] == nil then                 -- first chip by each skill
      b68.chipAt[sk] = H.frame
      b68.chipWild[sk] = b68.wildAt and b68.wildAt > (b68.sabinCmdAt or -1)
        and b68.wildAt or nil
    end
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
      "*** BREAK COMPLETE at f%d: all %d shields off with the train at %d of " ..
      "%d HP (casts=%d)", H.frame, b68.maxSH or -1, hp, b68.maxHP or -1, b68.casts))
    H.screenshot("train_b68_broken")
  end
  if hp == 0 and b68.killedAt == nil and b68.lastHP and b68.lastHP > 0 then
    b68.killedAt = H.frame
    b68.killSkill = H.readByte(0x3410)
    b68.killFrom = b68.lastHP
    b68.killParty = partyLine()
    b68Log(string.format("train at 0 HP at f%d (brokeAt=%s)", H.frame,
      tostring(b68.brokeAt)))
  end
  b68.lastSH, b68.lastHP = shields, hp
end


-- Battle 47, played once (#311).  This used to be a three-rung reload
-- ladder (an in-run snapshot and H.newSeedSweep's spread seeds, the same
-- plan each rung, its losses invisible to the retry audit).  A loss now
-- raises the wipe it is (class=wipe), and the segment runner's bounded
-- retry is the only reload.
local function b47Fight()
  return H.cond(function() return true end, {
    H.call(function()
      lost, fightTier, wipeN = nil, 1, 0
      b47Heals, fPlan, fPlanActor = 0, nil, nil
      b47Watch.reset()
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
          error(string.format("timeout after 29000 frames: battle 47 with " ..
            "no win and no wipe seen -- a genuine stall, see #159/#163 [%s]",
            partyLine()), 0)
        end
        return lost ~= nil
            or (mapIdx() == 142 and H.hasControl() and H.tileAligned()
                and not inBattle() and bright() >= 15)
      end, "battle 47 + mob scene", 30000, "fight")
    end)(),
    H.waitFrames(30),
    H.call(function()
      -- the 1/16 leave roll is a no-op by design (Ot6ShadowLeaves): a
      -- missing SHADOW after a win is a ROM regression, not a re-roll
      if lost ~= nil then
        error("train: battle 47: THE PARTY IS WIPED -- " .. lost, 0)
      end
      H.assertEq(inParty(3), true, "SHADOW aboard after battle 47's win (the leave roll is a no-op by design)")
      H.log("[train] battle 47 clean: won, SHADOW aboard")
    end),
  })
end

-- (A wander-for-an-encounter top-up was tried here and does not work: the
-- post-b47 strip has no random pool at all, and b=true never showed outside
-- battle 47 across every run.  The entry-HP loss is the field poison the
-- trap ghosts inflict, draining per step for the whole strip walk, which is
-- what "SABIN at 3/231, the drain floor" described.  The counter is bought
-- two cars back: Antidotes, used inside battle 47 before the ghosts are
-- killed.)

-- ------------------------------------------------------- battle 68 --
-- One fight, played out.  A win is a win however many shields came off
-- (the owner's ruling on #311, docs/guidelines.md "A win is a win and a
-- loss is a loss"): a train killed before its break is logged as a
-- [tuning] line and the segment moves on; every win asserts each reveal
-- tied to the chip its skill landed.  Only a loss
-- is a loss -- the party wiped -- and it is the canary's: allowGameOver
-- ends with battle 47's ladder, so the wipe is counted and filed as class
-- wipe, which the segment runner retries from the boot point, bounded and
-- counted.  (This used to be a five-rung reload ladder that
-- also re-rolled a WON fight with fewer than six shields off, and gave up
-- on a live fight when SABIN was Imp'd or down before the break.)
--
-- The fight's draw is logged at InitBattle's seed store as a key -- the
-- battle seed $be and the battle group ($11E0), the lib's first-battle key
-- shape -- so a set of runs can count distinct fights rather than runs.
local b68won = false
local b68Req = nil                        -- the train_b68_entry capture
local b68Arm = false
local function b68Won() return b68won end
local function b68KeyWatch()
  return H.call(function()
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      if not b68Arm then return end
      b68Arm = false
      -- exec callbacks fire before the instruction: A is the seed
      local seed = emu.getState()["cpu.a"] & 0xff
      H.log(string.format("[b68] battle key be%02X-g%04X ($021e=%d f%d)",
        seed, H.readWord(0x11e0), H.seedPhase(), H.frame))
    end, emu.callbackType.exec, addr, addr)
  end)
end
local function b68Fight()
  return H.cond(function() return true end, {
    H.call(function()
      lost, wipeN = nil, 0
      b68.casts, b68.chips = 0, {}
      b68.plan, b68.planActor = nil, nil
      b68.brokeAt, b68.killedAt, b68.brokeHP = nil, nil, nil
      b68.killParty, b68.wiped = nil, false
      b68.holyAt, b68.bludgAt, b68.chipAt, b68.castAt = nil, nil, {}, {}
      b68.chipWild, b68.sideN, b68.wildAt, b68.sabinCmdAt = {}, 0, nil, nil
      b68.rightN = 0
      b68.holyBy, b68.bludgBy = nil, nil
      b68.shieldsOff = 0
      b68.holyRevealed, b68.bludgRevealed = false, false
      b68.itemsOut = false
      b68.lastSH, b68.lastHP = nil, nil
      b68.tornDown, b68.mstreak = 0, 0
      b68.oddState, b68.oddN, b68.impSaid = nil, 0, false
      b68.impCure, b68.reviveFor = {}, {}
      gSlot, sabinE, cyanE, shadowE = nil, nil, nil, nil
      b68Watch.reset()
    end),
    H.cond(function() return lost ~= nil end, { H.waitFrames(1) }, {
    nav(32, 7, { maxFrames = 8000 }),
    H.call(function() b68Arm = true end),   -- the next battle seeded is 68
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
        "[b68] entry: slot %d, SABIN e%d lv%d mp %d/%d, CYAN e%d, " ..
        "SHADOW e%d | tonics=%d potions=%d gil=%d",
        gSlot, sabinE, lv, pMP(sabinE), H.readWord(0x3C30 + sabinE * 2),
        cyanE, shadowE, invCount(TONIC), invCount(POTION), gil()))
      H.assertEq(lv >= 6, true, "SABIN level 6+ -- AuraBolt learned")
      -- the authored row and the record, read from the ROM (#400 retunes
      -- them): Ot6ShieldTbl's (species word, shields, classes) record and
      -- MonsterProp's max HP word (+$08)
      local t = H.sym("Ot6ShieldTbl") & 0x3FFFFF
      b68.maxSH = nil
      for i = 0, 1023 do
        local id = H.readRomWord(t + i * 4)
        if id == 0xFFFF then break end
        if id == GHOSTTRAIN then b68.maxSH = H.readRomByte(t + i * 4 + 2); break end
      end
      b68.maxHP = H.readRomWord((H.sym("MonsterProp") & 0x3FFFFF) + GHOSTTRAIN * 32 + 8)
      H.log(string.format("[b68] the train's record: %s shields (Ot6ShieldTbl), %d HP " ..
        "(MonsterProp), %d HP live", tostring(b68.maxSH), b68.maxHP, H.readWord(MHP(gSlot))))
      H.assertEq(b68.maxSH ~= nil, true, "GHOSTTRAIN has an authored Ot6ShieldTbl row")
      H.assertEq(H.readByte(SH(gSlot)), b68.maxSH, "GHOSTTRAIN seeds its authored shields")
      H.assertEq(H.readByte(SMX(gSlot)), b68.maxSH, "GHOSTTRAIN's max shields are its authored count")
      H.assertEq(H.readWord(MHP(gSlot)), b68.maxHP, "GHOSTTRAIN opens at its record's max HP")
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
          lost = string.format("b68 deadline (145000 frames) with no win " ..
            "and no wipe seen [%s]", partyLine())
          H.log("[b68] STALLED -- " .. lost)
        end
        return lost ~= nil or b68.tornDown >= 3
      end, 150000, {
        H.call(function()
          -- #163: the wipe watch runs before the inBattle() gate, which
          -- reads a wiped party's all-zero table as "torn down"
          wipeWatch("b68")
          b68Watch.frame()
          if lost then H.setPad({}); return end
          if not inBattle() then
            b68.tornDown = b68.tornDown + 1
            H.setPad({})
            return
          end
          b68.tornDown = 0
          b68Observe()
          -- SABIN down or Imp'd before the break is not a lost fight: the
          -- plan revives him (Fenix Down) or cures him (the bag's Imp
          -- cure), and CYAN and SHADOW fight on.  Only a wipe ends it.
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
      }, "battle 68, the pacifist line")
    end)(),
    H.waitFrames(60),
    H.call(function()
      for _, row in ipairs(b68.chips) do H.log("[b68 chip] " .. row) end
      if lost and lost:find("deadline", 1, true) then
        error("battle 68: timeout after 145000 frames -- " .. lost, 0)
      end
      -- the canary's own wipe test (every present seat at 0 HP, or
      -- LoseBattle's bit 0 -- a Petrify/Zombie wipe); a won battle's
      -- torn-down table ($FFFF) reads false
      local wipedNow = H.partyWipedInBattle()
      if lost ~= nil or (b68.killedAt == nil and wipedNow) then
        b68.wiped = true
        b68Log(string.format("the party is down at f%d (%s) [%s] -- a wipe, " ..
          "the canary's to count and file", H.frame, tostring(lost or
          "the canary's wipe test, the train not seen at 0 HP"), partyLine()))
        H.screenshot("train_b68_lost")
      end
    end),
    -- A wipe is the canary's (allowGameOver is off since battle 47's
    -- ladder): the pad stays neutral at the Annihilated screen, the canary
    -- counts the wiped battle table (300 frames), freezes the pad and ends
    -- the attempt as class wipe with its context line.  Reaching the call
    -- below means it never did, which is a harness finding, not a loss.
    H.cond(function() return b68.wiped == true end, {
      H.call(function() H.setPad({}) end),
      H.waitFrames(900),
      H.call(function()
        error(string.format("battle 68: the party was down but the canary " ..
          "counted no wipe in 900 frames (gameOverFired=%d) [%s]",
          H.gameOverFired or 0, partyLine()), 0)
      end),
    }, {}),
    H.call(function()
      if b68.killedAt == nil then
        error(string.format("battle 68 ended at f%d with a member standing " ..
          "and the train never seen at 0 HP (last train HP %s, %d of %d " ..
          "shields off) -- neither a win nor a wipe this driver can read [%s]",
          H.frame, tostring(b68.lastHP), b68.shieldsOff or 0, b68.maxSH or -1, partyLine()), 0)
      end
      H.assertEq(inParty(3), true, "SHADOW aboard after battle 68's win (the leave roll is a no-op by design)")
      b68won = true
      local off = b68.shieldsOff or 0
      local mx = b68.maxSH or 6
      -- #410: a Suplex SABIN cast before the kill is the kill, in one hit
      -- (Ot6SuplexTrain deals the train's whole current HP).
      local sup = b68.castAt[SUPLEX]
      if sup and b68.killedAt and sup <= b68.killedAt then
        H.log(string.format("[b68] the joke: Suplex cast f%d, the train %s -> 0 at f%d by attack $%02X",
          sup, tostring(b68.killFrom), b68.killedAt, b68.killSkill or -1))
        H.assertEq(b68.killSkill, SUPLEX, string.format("the train's last HP went to the " ..
          "Suplex cast at f%d (the killing hit read attack $%02X, the train from %s HP)", sup,
          b68.killSkill or -1, tostring(b68.killFrom)))
      end
      H.log(string.format("[b68] WON: %d of %d shields off, killedAt=f%s " ..
        "brokeAt=%s casts=%d chips=%d holy=%s bludg=%s", off, mx,
        tostring(b68.killedAt), tostring(b68.brokeAt), b68.casts, #b68.chips,
        tostring(b68.holyRevealed), tostring(b68.bludgRevealed)))
      -- Each reveal is tied to the chip its skill landed, on any win: the
      -- tie is a property of the chip, not of the break.  HOLY is
      -- AuraBolt's ($5E, the holy weakness), OT6_BLUDG is Pummel's ($5D,
      -- the train's class row); the reveal banks at damage calc
      -- (OT6_RVPEND_*) and the shield comes off on the same hit, so the two
      -- are seen on one frame.  A skill that never chipped proves nothing
      -- either way (SABIN short on MP, the train dead first): logged, with
      -- "cast but never chipped" told apart from "never cast".
      -- A Muddled or Berserk SABIN acts on his own (the engine picks the
      -- Blitz, never this fighter's plan): the lab's be14 run (#366) had a
      -- Muddled SABIN's Suplex ($5F, bludgeon too) chip the first shield
      -- and reveal OT6_BLUDG before any Pummel.  So the reveal is tied to
      -- the skill that made it (the attack index at the reveal frame) when
      -- that skill chipped there, and a skill the plan never cast is the
      -- engine's: its chip and reveal still have to share the frame.
      -- A substitute revealer must carry the key it revealed, read from the
      -- ROM: OT6_BLUDG from Ot6SkillClassTbl (Pummel, Suplex), HOLY from the
      -- attack's own element byte (MagicProp +1: AuraBolt).
      local SKILLNAME = { [PUMMEL] = "Pummel ($5D)", [AURABOLT] = "AuraBolt ($5E)",
                          [SUPLEX] = "Suplex ($5F)" }
      local function skillClass(id)
        local base = H.sym("Ot6SkillClassTbl") & 0x3FFFFF
        for i = 0, 63 do
          local k = H.readRomByte(base + i * 2)
          if k == 0xFF then return 0 end
          if k == id then return H.readRomByte(base + i * 2 + 1) end
        end
        return 0
      end
      local function carries(key, id)
        if key == "HOLY" then return (H.spellElement(id) & HOLY) ~= 0 end
        return (skillClass(id) & OT6_BLUDG) ~= 0
      end
      local function tied(what, at, skill, name, by)
        if by and by ~= skill and SKILLNAME[by] and carries(what, by) and b68.chipAt[by]
           and at and math.abs(at - b68.chipAt[by]) <= REVEAL_SLACK then
          skill, name = by, SKILLNAME[by]
        end
        if by and SKILLNAME[by] then
          H.assertEq(carries(what, by), true, string.format("%s revealed on a frame whose " ..
            "attack is %s, which does not carry %s", what, SKILLNAME[by], what))
        end
        H.assertEq(carries(what, skill), true, string.format("%s's revealer %s carries %s " ..
          "(Ot6SkillClassTbl / its element byte)", what, name, what))
        local cast, chip = b68.castAt[skill], b68.chipAt[skill]
        if chip ~= nil and cast == nil then
          local wild = b68.chipWild[skill]
          H.log(string.format("[b68] %s: %s chipped f%d but the plan never " ..
            "cast it -- the engine's (SABIN last Muddled/Berserk at f%s, after his last " ..
            "command)", what, name, chip, tostring(wild)))
          H.assertEq(wild ~= nil, true, string.format(
            "%s: a %s the plan never cast came from a SABIN Muddled or Berserk since his " ..
            "last command (chip f%d)", what, name, chip))
          H.assertEq(at ~= nil and math.abs(at - chip) <= REVEAL_SLACK, true,
            string.format("%d of %d shields off: %s revealed by the %s that " ..
            "chipped (engine-chosen; chip f%d, reveal f%s, slack %d)", off, mx,
            what, name, chip, tostring(at), REVEAL_SLACK))
          return
        end
        if chip == nil then
          H.log(string.format("[b68] %s: %s %s -- the tie is not asserted " ..
            "(%s revealed f%s)", what, name, cast and string.format(
            "cast f%d but never chipped", cast) or "never cast", what,
            tostring(at)))
          return
        end
        local ok = at ~= nil and cast ~= nil
          and at >= cast and math.abs(at - chip) <= REVEAL_SLACK
        H.log(string.format("[b68] %s: %s cast f%s, its first chip f%s, " ..
          "revealed f%s", what, name, tostring(cast), tostring(chip),
          tostring(at)))
        H.assertEq(ok, true, string.format("%d of %d shields off: %s revealed " ..
          "by the %s that chipped (cast f%s, chip f%s, reveal f%s, slack %d)",
          off, mx, what, name, tostring(cast), tostring(chip), tostring(at),
          REVEAL_SLACK))
      end
      tied("HOLY", b68.holyAt, AURABOLT, "AuraBolt ($5E)", b68.holyBy)
      tied("OT6_BLUDG", b68.bludgAt, PUMMEL, "Pummel ($5D)", b68.bludgBy)
      if off < mx then
        H.log(string.format("[tuning] battle 68 won with %d of %d shields off " ..
          "-- the train died before its break (killedAt=f%s casts=%d " ..
          "chips=%d holy=%s bludg=%s) [party at the kill: %s]", off, mx,
          tostring(b68.killedAt), b68.casts, #b68.chips,
          tostring(b68.holyRevealed), tostring(b68.bludgRevealed),
          tostring(b68.killParty)))
        return
      end
      H.log(string.format(
        "[b68] break margin: train at %s of %d HP when the last shield " ..
        "came off, dead %s frames later (brokeAt=%s killedAt=%s)",
        tostring(b68.brokeHP), b68.maxHP or -1, b68.brokeAt and b68.killedAt
          and tostring(b68.killedAt - b68.brokeAt) or "?",
        tostring(b68.brokeAt), tostring(b68.killedAt)))
      H.assertEq(#b68.chips >= 2, true,
        "a full break: at least two shield chips landed")
    end),
    }),
  }, {})
end

-- allowGameOver: through battle 47 a lost fight is read by wipeWatch
-- (#163), which b47Fight raises as the wipe it is, with the party's last
-- reading; it ends there (H.setAllowGameOver below).
H.run({ maxFrames = 400000, allowGameOver = true }, {
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

  -- ---- the train's save point, back through the rear cars -------------
  -- A player who has just been told the train is leaving looks both ways
  -- out of the car he boarded into, and the way back finds the vanilla
  -- save point one car along.
  --
  -- #218: the save used to be attempted at the far end of the run, from
  -- the engineer's room, and bfsPath answered "not reachable" every time,
  -- so the save was skipped and the train-engineer-v1 battery kept
  -- whatever slot 3 already held (the Kolts summit save, map 103 (57,8)).
  -- The TILE was right -- map 146 (20,10) is a SavePoint
  -- (event_trigger.asm EventTrigger::_146) -- but map 146 is two rooms,
  -- and the engineer's room the front door opens on is a 31-tile pocket,
  -- bbox (5,7)-(9,13) (build/lab/218-train-diag.log), holding neither
  -- (20,10) nor (23,13), the door to map 152.  The save point's half is
  -- entered from 152 (8,7), and map 152 hangs off the REAR strip at 142
  -- (83,8)/(85,8)/(86,8) -- the pocket car A's EAST door lands in, at
  -- (75,8).  The route used to step out of car A's WEST door and turn
  -- away from all of it.  Measured end to end, with $01BF set on the tile
  -- and both crossings walked back: build/lab/218-train-savepoint2.log,
  -- shots trainsave_strip142/m152/m146east/on_savepoint.png.
  nav(29, 7, { maxFrames = 12000 }),
  holdDrive("right", function() return mapIdx() == 142 end,
    "car A's east door -> rear strip (75,8)", 4000),
  settle(142, "rear strip (75,8)"),
  nav(83, 8, { maxFrames = 20000,
               arrive = function() return mapIdx() ~= 142 end }),
  settle(152, "the rear car, map 152"),
  nav(8, 7, { maxFrames = 20000,
              arrive = function() return mapIdx() ~= 152 end }),
  settle(146, "the save car, map 146's east half"),
  nav(20, 10, { maxFrames = 12000 }),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 146, "on the save car, map 146")
    H.assertEq(H.fieldX(), 20, "standing on the save tile x=20")
    H.assertEq(H.fieldY(), 10, "standing on the save tile y=10")
    H.assertEq((H.readByte(0x1EB7) & 0x80) ~= 0, true,
      "$01BF SET -- the Phantom Train save point, map 146 (20,10)")
    H.screenshot("train_savepoint")
  end),
  H.saveGame({ tag = "train save (map 146 (20,10))" }),
  H.call(function()
    -- What went into the battery, read back out of the battery: the save
    -- slot's own map/tile words, so a save that lands somewhere else can
    -- never be lifted as this checkpoint (#218).
    H.assertSavedSlot(146, 20, 10, "train-engineer: the slot-3 save")
  end),
  -- and back the way we came, into car A
  nav(23, 13, { maxFrames = 12000,
                arrive = function() return mapIdx() ~= 146 end }),
  settle(152, "the rear car again"),
  nav(1, 8, { maxFrames = 12000,
              arrive = function() return mapIdx() ~= 152 end }),
  settle(142, "rear strip again (82,8)"),
  nav(74, 8, { maxFrames = 12000,
               arrive = function() return mapIdx() ~= 142 end }),
  settle(145, "back in car A"),

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
  -- Owner's route-wide restock rule: essentials and revives FIRST, then the
  -- Tonic soak LAST, so a short purse shorts Tonics (topped again at Mobliz
  -- and downstream) rather than the throwing kit or the revives.  Tonic -> 99
  -- ("a rite of passage to get 99 in the bag") and Fenix -> 15 are the
  -- ceilings; H.buyItem purse-clamps each to what the merchant's gil allows.
  buyItem(ANTIDOTE, 2, function() return 3 - invCount(ANTIDOTE) end,
    "ANTIDOTE to 3"),
  buyItem(SHURIKEN, 6, function() return 10 - invCount(SHURIKEN) end,
    "SHURIKEN to 10"),
  buyItem(FIRE_SKEAN, 7, function() return 2 - invCount(FIRE_SKEAN) end,
    "FIRE SKEAN to 2"),
  -- Potions are the IN-COMBAT heal (a Tonic's +50 is under the measured
  -- round cost here; the field care between fights is what Tonics are
  -- for), and this merchant is the route's FIRST Potion shop and the last
  -- one before Baren Falls (shop_prop.dat: Figaro's shop 4 and South
  -- Figaro's shop 8 sell none; nothing between here and Mobliz).  The
  -- supply curve (docs/design/level-curve.md) carries ~level x1.5 of them:
  -- L14 here -> 21.  The old target of 10 left 8 at the falls jump (#167),
  -- and a target of 21 left 12: the GhostTrain fight between this counter
  -- and the falls spent 9 on its own (train_done.log, nine `[b68] heal ...
  -- POTION` lines, potion=21 -> 12 at the post-train care).  The last shop
  -- before a shopless boss stretch buys the band PLUS that stretch's
  -- measured spend, so the falls jump still holds the band: 21 + 9 = 30.
  buyItem(POTION, 1, function() return 30 - invCount(POTION) end,
    "POTION to 30"),
  -- Fenix Downs are for reviving allies (battle 47's prolonged tail killed
  -- SHADOW, measurably, and he entered the boss fight dead); the item target
  -- steer never confirms on the monster side, so the undead-instant-kill
  -- throw is not reachable
  buyItem(FENIX_DOWN, 4, function() return 15 - invCount(FENIX_DOWN) end,
    "FENIX DOWN to 15"),
  buyItem(TONIC, 0, function() return 99 - invCount(TONIC) end, "TONIC to 99"),
  closeShop(),
  -- #197: the combat items back on top of the bag after every purchase
  -- (the fight driver found the Potion at row 43 downstream of a stop
  -- that did not re-arrange)
  H.bagArrange({ POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY }, { tag = "bag: combat items on top (train merchant)" }),
  H.call(function()
    H.log(string.format("[shop] done: gil=%d tonics=%d potions=%d skeans=%d",
      gil(), invCount(TONIC), invCount(POTION), invCount(FIRE_SKEAN)))
    H.assertEq(invCount(TONIC) >= 12, true,
      "at least 12 Tonics for the medic line (bought)")
    H.assertEq(invCount(POTION) >= 10, true,
      "at least 10 Potions for the medic line (bought; the Potion band's floor)")
    H.assertEq(invCount(FIRE_SKEAN) >= 2, true,
      "two Fire Skeans for SHADOW's chip (bought, #74)")
  end),

  -- The aisle hold fights what it meets (#203): the bare 900-frame
  -- setPad(left) this used to be had no battle check, so a ghost that
  -- opened a battle mid-hold met a LEFT still down at its command window,
  -- which opens the Row side window ($24) -- the v0.17 train_done
  -- attempt-1 no-effect trip, and 3/3 seeds once forest_done moved or the
  -- merchant stop grew by the bag arrange (#197).  holdDrive's walk
  -- fighter plays the battle and the hold resumes; the 900-frame give-up
  -- counts only frames with control outside a battle, so a long ghost
  -- fight (~2150 frames measured) never ends the hold mid-fight.
  (function()
    local n = 0
    return holdDrive("left", function()
      if H.hasControl() and not inBattle() then n = n + 1 end
      return H.fieldX() <= 4 or n > 900
    end, "car B's aisle, held through the ghost wander", 6000)
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

  -- ---- battle 47, with real input ----
  b47Fight(),
  -- From battle 47 on a wipe (a corridor random, battle 68) is the canary's: it
  -- counts it, freezes the pad and files the attempt as class wipe, with
  -- its context line, for the segment runner's bounded retry.
  H.setAllowGameOver(false, "battle 47 is done; battle 68 and the " ..
    "rest of the train lose the way every other fight does"),

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
  -- (The train's save point, map 146 (20,10), was taken back in the rear
  -- cars -- see the note at the save step.  This half of map 146, the
  -- engineer's room the front door opens on, is a 31-tile pocket,
  -- bbox (5,7)-(9,13), that holds neither (20,10) nor (23,13).)
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
  -- says which walk lost him.
  H.call(function()
    H.assertEq(inParty(3), true,
      "SHADOW still aboard after the strip walk (a fought-out corridor " ..
      "encounter rolls his 1/16 leave; a fled one does not)")
    H.log(string.format("[train] pre-smokestack bag: tonics=%d potions=%d " ..
      "skeans=%d shurikens=%d fenix=%d gil=%d", invCount(TONIC),
      invCount(POTION), invCount(FIRE_SKEAN), invCount(SHURIKEN),
      invCount(FENIX_DOWN), gil()))
  end),

  -- train_b68_entry: the corridor before the smokestack switch, one walk
  -- from battle 68 (battle_suplextrain boots it, #410).  Captured with no
  -- frames spent, emitted after train_done.
  H.call(function() b68Req = H.requestSaveState() end),
  b68KeyWatch(),
  b68Fight(),
  H.call(function()
    H.assertEq(b68Won(), true, "battle 68 won (a wipe ended the attempt above)")
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
  H.call(function()
    H.checkReq(b68Req, "train_b68_entry capture")
    H.emitBlob("train_b68_entry.mss", b68Req.blob)
  end),
  H.logStep(function()
    return string.format("train_done generated at frame %d world (%d,%d) -- " ..
      "battle 68 won with %d of %d shields off (the [b68] WON line; a " ..
      "[tuning] line when the train died before its break)",
      H.frame, H.worldX(), H.worldY(), b68.shieldsOff or 0, b68.maxSH or -1)
  end),
})
