-- gen_sabin_falls.lua -- step 9 of SABIN's scenario: Baren Falls.  Generates:
--   falls_done.mss   map 159 (the Veldt shore), SABIN+CYAN, $003C/$003F set
--                    SHADOW left at the overlook, GAU named but not
--                    joined (he takes nothing and runs; recruitment is the
--                    next step's Veldt work).

local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/train_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local CH_SEL, CH_MAX, NAME_MENU = 0x056E, 0x056F, 0x0200
local RIZOPAS = 0x0155
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local rizo = { seen = false, species = 0, shields = 0, smax = 0, wkc = 0,
               mask0 = nil }

local MENU, ACTOR = 0x7BCA, 0x62CA
local BP = 0x3E9C
local fightTier = 1
local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
local lost = nil
local wipeN = 0
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
  local rizoUp = rizo.seen and monPresent(5)
  local thresh = rizoUp and 6 or 8
  if mx > 0 and hp > 0 and hp * 10 < mx * thresh and itemRow then
    local id = nil
    if mx - hp >= 60 and battItemIdx(POTION) then id = POTION
    elseif battItemIdx(TONIC) then id = TONIC
    elseif battItemIdx(POTION) then id = POTION end
    if id then
      H.log(string.format("[falls] heal f%d e%d %s (hp %d/%d) [%s]",
        H.frame, actor, id == TONIC and "TONIC" or "POTION", hp, mx,
        partyLine()))
      return { kind = "item", item = id, row = itemRow }
    end
  end
  local bp = H.readByte(BP + actor * 2)
  local boost = bp >= 1 and math.min(bp, 3) or 0
  H.log(string.format("[falls] cast f%d e%d boost=%d tier=%d [%s]",
    H.frame, actor, boost, fightTier, partyLine()))
  return { kind = "fight", boostLeft = boost }
end
local function fightButton()
  local st = H.readByte(MSTATE)
  local actor = H.readByte(ACTOR)
  if fPlan == nil or fPlanActor ~= actor then
    if st ~= ST_CMD then
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
    H.log(string.format("[falls] fmenu f%d st=%02X actor=%d row=%d itm=%d " ..
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
        H.log(string.format("[falls] plan stalled 40 pulses (st=%02X) -- " ..
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
local function wipeWatch(tag)
  local wiped = true
  for e = 0, 3 do
    if H.readWord(0x3c1c + e * 2) > 0 and H.readWord(0x3bf4 + e * 2) > 0 then
      wiped = false
    end
  end
  wipeN = wiped and wipeN + 1 or 0
  if wipeN >= 90 and not lost then
    lost = string.format("%s: PARTY WIPED at f%d (tier %d) [%s]",
      tag, H.frame, fightTier, partyLine())
    H.log("[falls] LOST -- " .. lost)
    H.screenshot("falls_lost")
  end
end

-- ride/walk driver: choices steered by CH_SEL, name menu by menu state,
-- battles per fightMode ("real": the boost-and-Fight episode machine plus
-- the wipe watch -- the win bit is EARNED; default: flee, hold L+R),
-- dialogs tap-A, else hold `dir` (or hands-off when dir is nil).
local function ride(dir, pred, what, budget, fightMode, choiceWant)
  local phase, hb, quiet = 0, -900, 0
  return H.driveUntil(pred, budget or 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format(
          "ride[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s b=%s ch=%d/%d",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle()), H.readByte(CH_SEL), H.readByte(CH_MAX)))
      end

      if inBattle() or H.battleLoadStarted() then
        if fightMode == "real" then
          -- the rizopas watch: record the seed row THE FRAME IT SURFACES
          if not rizo.mask0 and H.battleLoadStarted() then
            local m = 0
            for s = 0, 5 do if monPresent(s) then m = m | (1 << s) end end
            rizo.mask0 = m
            H.log(string.format("[falls] battle-up present mask=$%02X", m))
          end
          if not rizo.seen and monPresent(5) then
            rizo.seen = true
            rizo.species = H.readWord(0x57C0 + 10)
            rizo.shields = H.readByte(0x3E38 + 8 + 10)
            rizo.smax    = H.readByte(0x3E39 + 8 + 10)
            rizo.wkc     = H.readByte(0x3E9C + 8 + 10)
            H.log(string.format(
              "[falls] slot 5 SURFACED: species=$%04X shields=%d/%d wkc=$%02X",
              rizo.species, rizo.shields, rizo.smax, rizo.wkc))
          end
          wipeWatch(what)
          if lost then H.setPad({}); return end
          fightPulse(phase)
        else
          H.setPad({ l = true, r = true })   -- flee, with real input
        end
        return
      end

      -- choice prompts: steer to choiceWant then confirm
      if H.readByte(CH_MAX) >= 2 and H.dialogWaiting() then
        local sel, want = H.readByte(CH_SEL), choiceWant or 0
        if sel < want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      end

      -- the name menu, on the menu module's own state (gen_sabin_camp)
      if H.readByte(NAME_MENU) == 1 and H.readByte(0x0059) ~= 0
         and (H.readByte(0x0026) == 0x5F or H.readByte(0x0027) == 0x5F) then
        quiet = quiet + 1
        if quiet >= 30 then
          if quiet == 30 then
            H.log(string.format("[falls] NAME MENU at f%d -- START", H.frame))
          end
          H.setPad(phase < 4 and { "start" } or {})
          return
        end
        H.setPad({})
        return
      end
      quiet = 0

      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad(dir and { [dir] = true } or {})
    end),
  }, what)
end

local function settle(toMap, what)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 5000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[falls] %s: map=%d (%d,%d)", what, mapIdx(),
        H.fieldX(), H.fieldY()))
    end),
  }, {})
end

-- world walk: the lib's verified-step walker (write-clears trash inline and
-- stalls out the post-battle world reload); the entrance firing mid-plan
-- is the arrival
local function worldToMap(tx, ty, what, budget)
  return H.worldNavTo(tx, ty, { maxFrames = budget or 30000,
    playBattles = "flee",
    arrive = function() return not H.worldMode() end })
end

local function seq(steps) return H.cond(function() return true end, steps) end

local function walkToFalls()
  return seq({
    worldToMap(185, 93, "falls cave (185,93)", 20000),
    settle(166, "cave 166"),
    H.navTo(7, 5, { maxFrames = 6000, playBattles = "flee" }),
    ride("up", function() return mapIdx() == 155 end, "-> 155", 3000),
    settle(155, "overlook 155"),
    H.navTo(10, 5, { maxFrames = 6000, playBattles = "flee" }),
    ride("up", function() return mapIdx() == 156 end, "-> 156", 3000),
    settle(156, "falls top 156"),
    ride("up", function()
      return sw(0x3C) == 1 and H.hasControl() and H.tileAligned()
    end, "arrival scene ($003C)", 15000),
    H.call(function()
      H.assertEq(sw(0x3C), 1, "$003C -- Baren Falls named")
      H.assertEq(inParty(3), false, "SHADOW left at the overlook")
      H.log(string.format("[falls] post-arrival at (%d,%d)", H.fieldX(),
        H.fieldY()))
    end),
  })
end

-- One jump attempt: (attempt 2+) reload the pre-jump checkpoint with a
-- stagger and the fighter escalated, walk onto the jump row, and ride the
-- fall + battle 18 + the shore cinematic to map 159.  `lost`
-- short-circuits the ride so the next attempt starts promptly.
local jumpWon = false

local function jumpAttempt(n)
  return H.cond(function() return not jumpWon end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[falls] ATTEMPT %d -- reloading the boot " ..
          "fixture and re-walking to the falls after a loss (%s)", n,
          tostring(lost))
      end),
      H.loadState(DOOR),
      H.waitFrames(30 + (n - 1) * 17),
      walkToFalls(),
    }, {}),
    H.call(function()
      lost, fightTier, wipeN = nil, n, 0
      rizo.seen, rizo.mask0 = false, nil
    end),
    H.navTo(13, 11, { maxFrames = 5000, playBattles = "flee" }),
    (function()
      local frames = 0
      return ride("up", function()
        frames = frames + 1
        if frames > 39000 and lost == nil then
          lost = string.format("attempt %d deadline (39000 frames) -- " ..
            "assumed wiped or wedged [%s]", n, partyLine())
          H.log("[falls] LOST -- " .. lost)
        end
        return lost ~= nil
            or (mapIdx() == 159 and sw(0x3F) == 1 and H.hasControl()
                and H.tileAligned() and bright() >= 15)
      end, "jump + battle 18 + the shore (attempt " .. n .. ")", 40000,
        "real", 0)
    end)(),
    H.release(),
    H.waitFrames(30),
    H.call(function()
      if lost == nil then
        jumpWon = true
        H.log(string.format("[falls] attempt %d WON battle 18", n))
      end
    end),
  }, {})
end

H.run({ maxFrames = 250000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the World of Balance")
    H.assertEq(sw(0x3B), 1, "$003B set -- the train is behind us")
    H.log(string.format("[falls] start world (%d,%d)", H.worldX(), H.worldY()))
  end),

  walkToFalls(),

  jumpAttempt(1),
  jumpAttempt(2),
  jumpAttempt(3),
  H.call(function()
    if not jumpWon then
      error(string.format("falls: battle 18 was lost on all 3 " ..
        "attempts -- last loss: %s -- the per-attempt numbers above are " ..
        "the balance finding (#74-style); do not rig this segment",
        tostring(lost)), 0)
    end
  end),

  H.call(function()
    H.assertEq(mapIdx(), 159, "washed ashore on map 159")
    H.assertEq(sw(0x3F), 1, "$003F -- GAU met and named")
    H.assertEq(rizo.seen, true, "RIZOPAS surfaced in slot 5 (the piranhas' "..
      "death script ran)")
    H.assertEq(rizo.species, RIZOPAS, "slot 5 was RIZOPAS ($0155)")
    H.assertEq(rizo.shields, 4,
      "RIZOPAS seeds 4 shields (Ot6ShieldTbl; #139 took the fifth pip -- "
      .. "the 1W/8L real-attempt ledger at the routed curve)")
    H.assertEq(rizo.wkc, 0x05, "RIZOPAS class row SLASH|BLUDG ($05)")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(2), true, "CYAN in the party")
    H.assertEq(inParty(3), false, "SHADOW gone")
    H.assertEq(inParty(11), false, "GAU did NOT join here")
    H.log(string.format("[falls_done] f%d map=%d (%d,%d) mask0=$%02X",
      H.frame, mapIdx(), H.fieldX(), H.fieldY(), rizo.mask0 or -1))
    H.screenshot("falls_done")
  end),
  H.saveState("falls_done.mss"),
  H.logStep(function()
    return string.format("falls_done generated at frame %d map 159 (%d,%d)",
      H.frame, H.fieldX(), H.fieldY())
  end),
})
