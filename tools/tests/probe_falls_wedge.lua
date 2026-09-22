-- @manual
-- probe_falls_wedge.lua -- #159: measure the Baren Falls "stall".  In the
-- v0.16 qualification gen_sabin_falls' attempt 1 sat on map 156 (13,9)
-- with ctl=false dlg=false b=false from f18833 to its 39000-frame deadline
-- and was declared "assumed wiped or stalled".  This probe boots the
-- generator's own fixture (train_done), walks to the falls the way the
-- generator does, snapshots the post-arrival tile ONCE (in memory, and
-- emitted as build/states/falls_prejump.mss by shard 0), then branches
-- that snapshot into attempts: each varies the entry legitimately (idle
-- frames before the walk to the jump row, idle frames before the last
-- step, hold-vs-tap pacing, a delay before answering "Jump?") -- the
-- battle RNG seed is the game-time frame counter ($021E asl2 -> $BE,
-- battle_main.asm InitBattle), so idle frames are real seed variation --
-- and rides the jump with a VERBATIM copy of the generator's ride and
-- fighter (as fixed for #159: the wipe watch outside the battle gate; the
-- pre-fix copy is in this file's first revision), plus per-pulse dumps of every hasControl component at map 156
-- (probe_forest_stall.lua's dumpControl, extended with the battle-side
-- words), whether battle 18 starts, and the frames to control.
--
-- Per attempt the outcome is one of WON (map 159, $003F, control), WIPED
-- (M.partyWipedInBattle held 90 frames -- the generator's own inBattle()
-- and wipe watch are blind to an all-zero HP table, so this is measured
-- separately), or STALL (the 20000-frame deadline with neither).  The
-- first WIPED and the first STALL each get a snapshot and a screenshot.
-- After a wipe the probe keeps observing hands-off, then (labelled) thaws
-- the canary's pad freeze and taps A ONCE to see where the engine goes.
--
-- Read-only under docs/TESTING.md: pad presses and memory reads; complete
-- snapshots only.  allowGameOver: the canary must not end the run, since
-- observing what follows a wipe is the point; every attempt restores the
-- snapshot, which thaws the pad and restarts the experiment.
--
-- Parallel use: tools/tests/probe_falls_wedge.sh substitutes the SHARD
-- line into scratch copies and runs them concurrently.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/train_done.mss.lua"
local SHARD = 0
local PER_SHARD = 4
local ATTEMPT_DEADLINE = 20000   -- a clean pass is ~10500 frames (qual: f53959->f64471)

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local CH_SEL, CH_MAX, NAME_MENU = 0x056E, 0x056F, 0x0200
local RIZOPAS = 0x0155

-- ===================== verbatim from gen_sabin_falls.lua =====================
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
  if H.frame - fHb >= 300 then
    fHb = H.frame
    local a = H.readByte(ACTOR)
    H.log(string.format("[falls] fmenu f%d st=%02X actor=%d row=%d itm=%d " ..
      "plan=%s held=%d [%s]", H.frame, H.readByte(MSTATE), a,
      H.readByte(CMDROW + a) & 3, itemIdxOf(a),
      fPlan and fPlan.kind or "-", fHeld, partyLine()))
  end
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
local function wipeWatch(tag)   -- #159 fix: every frame, lib predicate, canary counts
  local wiped = H.partyWipedInBattle()
  wipeN = wiped and wipeN + 1 or 0
  if (H.gameOverFired or 0) > 0 and not lost then
    lost = string.format("%s: GAME OVER counted by the canary at f%d (tier %d) [%s]",
      tag, H.frame, fightTier, partyLine())
    H.log("[falls] LOST -- " .. lost)
  end
  if wipeN >= 90 and not lost then
    lost = string.format("%s: PARTY WIPED at f%d (tier %d) [%s]",
      tag, H.frame, fightTier, partyLine())
    H.log("[falls] LOST -- " .. lost)
    H.screenshot("falls_lost")
  end
end

-- `watch` is the probe's per-frame hook (nil for the walk-in); `dirMode`
-- "hold" is the generator's held direction, "tap" presses it 4 of 8 frames.
local function ride(dir, pred, what, budget, fightMode, choiceWant, watch, dirMode)
  local phase, hb, quiet = 0, -900, 0
  return H.driveUntil(pred, budget or 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      if watch then watch() end
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format(
          "ride[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s b=%s ch=%d/%d",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle()), H.readByte(CH_SEL), H.readByte(CH_MAX)))
      end

      if fightMode == "real" then
        wipeWatch(what)
        if lost then H.setPad({}); return end
      end

      if inBattle() or H.battleLoadStarted() then
        if fightMode == "real" then
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
          fightPulse(phase)
        else
          H.setPad({ l = true, r = true })
        end
        return
      end

      if H.readByte(CH_MAX) >= 2 and H.dialogWaiting() then
        if watch and watch("choice") then return end   -- probe: prompt delay
        local sel, want = H.readByte(CH_SEL), choiceWant or 0
        if sel < want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      end

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
      if dirMode == "tap" then
        H.setPad((dir and phase < 4) and { [dir] = true } or {})
      else
        H.setPad(dir and { [dir] = true } or {})
      end
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

local function worldToMap(tx, ty, what, budget)
  return H.worldNavTo(tx, ty, { maxFrames = budget or 30000,
    playBattles = "tactical",
    arrive = function() return not H.worldMode() end })
end

local function seq(steps) return H.cond(function() return true end, steps) end

local function walkToFalls()
  return seq({
    worldToMap(185, 93, "falls cave (185,93)", 20000),
    settle(166, "cave 166"),
    H.navTo(7, 5, { maxFrames = 6000, playBattles = "tactical" }),
    ride("up", function() return mapIdx() == 155 end, "-> 155", 3000),
    settle(155, "overlook 155"),
    H.navTo(10, 5, { maxFrames = 6000, playBattles = "tactical" }),
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
-- =================== end of the verbatim generator copy ====================

-- ------------------------------------------------------------ the probe --
local function evtPC()
  return H.readByte(0xE7) * 65536 + H.readByte(0xE6) * 256 + H.readByte(0xE5)
end
local function presentMask()
  local m = 0
  for s = 0, 5 do if monPresent(s) then m = m | (1 << s) end end
  return m
end
local function dumpControl(tag)
  H.log(string.format(
    "[%s] f%d map=%d (%d,%d) ctl=%s aligned=%s evt=%s dlg=%s | $087C=%02X " ..
    "$1EB9=%02X evtPC=%06X $0084=%02X $0059=%02X $BA=%02X $D3=%02X " ..
    "batt=%s bright=%d | hp=[%s] present=$%02X $3A76=%02X $3A77=%02X " ..
    "$3EBC=%02X $3A6E=%02X wipedInBattle=%s gameOverFired=%d $021E=%02X " ..
    "$BE=%02X $1F6D=%02X sw3C=%d sw3F=%d",
    tag, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
    tostring(H.hasControl()), tostring(H.tileAligned()),
    tostring(H.eventRunning()), tostring(H.dialogWaiting()),
    H.readByte(0x087C), H.readByte(0x1EB9), evtPC(),
    H.readByte(0x0084), H.readByte(0x0059), H.readByte(0xBA),
    H.readByte(0xD3), tostring(H.battleLoadStarted()), bright(),
    partyLine(), presentMask(), H.readByte(0x3A76), H.readByte(0x3A77),
    H.readByte(0x3EBC), H.readByte(0x3A6E), tostring(H.partyWipedInBattle()),
    H.gameOverFired or 0, H.readByte(0x021E), H.readByte(0xBE),
    H.readByte(0x1F6D), sw(0x3C), sw(0x3F)))
end
-- the event script bytes under the parked PC, for reading against
-- event_main.asm (bank $CA-$CC is ROM offset (bank-$C0)<<16 | addr)
local function dumpScript(tag)
  local pc = evtPC()
  local off = pc & 0x3FFFFF
  local b = {}
  for i = 0, 15 do b[#b + 1] = string.format("%02X", H.readRomByte(off + i)) end
  H.log(string.format("[%s] script bytes at %06X: %s", tag, pc,
    table.concat(b, " ")))
end

local pre = nil                      -- the post-arrival snapshot request
local results = {}
local firstWipeSaved, firstStallSaved = false, false

local function attempt(k)
  local i = SHARD * PER_SHARD + (k - 1)          -- global attempt index
  local preIdle = 20 + (i * 37) % 200            -- idle at (15,10) after load
  local lastIdle = (i * 23) % 120                -- idle at (13,11) before the last step
  local promptDelay = (i * 17) % 90              -- frames before answering "Jump?"
  local pace = (i % 2 == 0) and "hold" or "tap"
  local R = { i = i, preIdle = preIdle, lastIdle = lastIdle,
              promptDelay = promptDelay, pace = pace, outcome = "?",
              t0 = 0, battleUp = nil, seed = nil, battleDown = nil,
              wipeAt = nil, ctlAt = nil, rizo = false }
  results[#results + 1] = R
  local lreq
  local frames, hb, promptSeen, wipeHeld = 0, -300, nil, 0
  local lastSig = nil
  local function watch(kind)
    if kind == "choice" then
      if promptSeen == nil then
        promptSeen = frames
        dumpControl("prompt")
      end
      if frames - promptSeen < promptDelay then H.setPad({}); return true end
      return false
    end
    -- transitions of the control tuple, debounced to one line per 20 frames
    local sig = string.format("%s%s%s%s", tostring(H.hasControl()),
      tostring(H.battleLoadStarted()), tostring(H.dialogWaiting()),
      tostring(H.eventRunning()))
    if sig ~= lastSig and frames - hb >= 20 then
      lastSig = sig; hb = frames
      dumpControl("edge")
    elseif frames - hb >= 300 then
      hb = frames
      dumpControl("pulse")
    end
    if R.battleUp == nil and H.battleLoadStarted() then
      R.battleUp = frames
      R.seed = H.readByte(0xBE)
      local w = H.formationWords and H.formationWords() or {}
      local ws = {}
      for _, v in ipairs(w) do ws[#ws + 1] = string.format("%04X", v) end
      H.log(string.format("[attempt %d] battle up at +%d ($BE=%02X $021E=%02X) " ..
        "formation=[%s] $11E0=%04X", i, frames, R.seed, H.readByte(0x021E),
        table.concat(ws, ","), H.readWord(0x11E0)))
    end
    if R.battleUp and R.battleDown == nil and not H.battleLoadStarted()
       and not H.partyWipedInBattle() then
      R.battleDown = frames
      dumpControl("battle-down")
    end
    if H.partyWipedInBattle() then
      wipeHeld = wipeHeld + 1
      if wipeHeld == 90 and R.wipeAt == nil then
        R.wipeAt = frames
        H.log(string.format("[attempt %d] WIPED: every battle-HP word 0 for " ..
          "90 frames at +%d [%s]", i, frames, partyLine()))
        dumpControl("wipe")
        dumpScript("wipe")
      end
    else
      wipeHeld = 0
    end
  end
  return seq({
    H.logStep(function()
      return string.format("[attempt %d] shard %d #%d: preIdle=%d lastIdle=%d " ..
        "promptDelay=%d pace=%s", i, SHARD, k, preIdle, lastIdle, promptDelay, pace)
    end),
    H.call(function() lreq = H.requestLoadState(pre.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(lreq, "prejump restore")
      H.rearmInputInjection()
      H.gameOverFired = 0
      lost, fightTier, wipeN = nil, 1, 0
      rizo.seen, rizo.mask0 = false, nil
      fPlan, fPlanActor, fBtn, fTick, fStreak, fHeld = nil, nil, nil, 0, 0, 0
    end),
    H.waitFrames(preIdle),
    H.call(function()
      R.t0 = H.frame
      dumpControl("start")
    end),
    H.navTo(13, 11, { maxFrames = 5000, playBattles = "tactical" }),
    H.waitFrames(lastIdle),
    H.call(function()
      H.log(string.format("[attempt %d] at (%d,%d) f%d after %d idle; last step",
        i, H.fieldX(), H.fieldY(), H.frame, lastIdle))
    end),
    ride("up", function()
      frames = frames + 1
      -- the generator's own watch is checked first: with the #159 fix it
      -- must catch the wipe itself (GEN-LOST); the probe's separate
      -- detector (WIPED) is the pre-fix measurement
      if lost ~= nil then R.genLost = frames; return true end
      if R.wipeAt ~= nil then return true end
      if mapIdx() == 159 and sw(0x3F) == 1 and H.hasControl()
         and H.tileAligned() and bright() >= 15 then
        R.ctlAt = frames
        return true
      end
      if frames > ATTEMPT_DEADLINE then return true end
      return false
    end, "jump (attempt " .. i .. ")", ATTEMPT_DEADLINE + 100, "real", 0,
      watch, pace),
    H.release(),
    H.call(function()
      R.rizo = rizo.seen
      if R.ctlAt then
        R.outcome = "WON"
        H.log(string.format("[attempt %d] WON: control on map 159 at +%d frames " ..
          "(battle up +%s, down +%s) [%s]", i, R.ctlAt, tostring(R.battleUp),
          tostring(R.battleDown), partyLine()))
      elseif R.genLost then
        R.outcome = "GEN-LOST"
        H.log(string.format("[attempt %d] the generator's wipe watch fired at +%d: %s",
          i, R.genLost, tostring(lost)))
      elseif R.wipeAt then
        R.outcome = "WIPED"
        if not firstWipeSaved then
          firstWipeSaved = true
          H.screenshot(string.format("falls_wipe_s%d", SHARD))
        end
      else
        R.outcome = "STALL"
        H.log(string.format("[attempt %d] STALL: deadline %d with no control, " ..
          "no win, no wipe", i, ATTEMPT_DEADLINE))
        dumpControl("stall")
        dumpScript("stall")
        if not firstStallSaved then
          firstStallSaved = true
          H.screenshot(string.format("falls_wedge_s%d", SHARD))
        end
      end
    end),
    H.cond(function() return R.outcome == "WIPED" and firstWipeSaved
                          and not R.wipeSnap and SHARD == 0 end, {
      H.call(function() R.wipeSnap = true end),
      H.saveState("falls_wipe.mss"),
    }, {}),
    H.cond(function() return R.outcome == "STALL" and not R.stallSnap end, {
      H.call(function() R.stallSnap = true end),
      H.saveState(string.format("falls_wedge_s%d.mss", SHARD)),
    }, {}),
    -- after a wipe: what does the engine do with the pad neutral, and
    -- then with one A press (a person would press something)?
    H.cond(function() return R.outcome == "WIPED" end, {
      H.call(function() frames = 0; hb = -1000 end),
      H.driveUntil(function() frames = frames + 1; return frames > 600 end, 700, {
        H.call(function()
          if frames - hb >= 150 then hb = frames; dumpControl("post-wipe idle") end
          H.setPad({})
        end),
      }, "post-wipe idle watch"),
      H.call(function()
        H.log(string.format("[attempt %d] LABELLED EXPERIMENT: thawing the " ..
          "canary's pad freeze and tapping A once on the annihilated screen " ..
          "(gameOverFired=%d before)", i, H.gameOverFired or 0))
        H.thawPad()
        frames = 0; hb = -1000
      end),
      H.driveUntil(function() frames = frames + 1; return frames > 900 end, 1000, {
        H.call(function()
          if frames <= 4 then H.setPad({ "a" }) else H.setPad({}) end
          if frames - hb >= 150 then hb = frames; dumpControl("post-wipe A") end
        end),
      }, "post-wipe press watch"),
      H.call(function()
        H.log(string.format("[attempt %d] after the A press: gameOverFired=%d " ..
          "map=%d ctl=%s", i, H.gameOverFired or 0, mapIdx(),
          tostring(H.hasControl())))
        dumpControl("post-wipe end")
      end),
    }, {}),
  })
end

local steps = {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the World of Balance")
    H.assertEq(sw(0x3B), 1, "$003B set -- the train is behind us")
    H.log(string.format("[falls] start world (%d,%d)", H.worldX(), H.worldY()))
  end),
  walkToFalls(),
  H.waitFrames(10),
  H.call(function()
    dumpControl("prejump")
    pre = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(pre, "prejump capture")
    H.log(string.format("[probe] prejump snapshot captured at f%d map=%d (%d,%d) " ..
      "(%d bytes)", H.frame, mapIdx(), H.fieldX(), H.fieldY(), #pre.blob))
    if SHARD == 0 then H.emitBlob("falls_prejump.mss", pre.blob) end
  end),
}
for k = 1, PER_SHARD do steps[#steps + 1] = attempt(k) end
steps[#steps + 1] = H.call(function()
  for _, R in ipairs(results) do
    H.log(string.format("[rate] attempt=%d preIdle=%d lastIdle=%d promptDelay=%d " ..
      "pace=%s seed=%s battleUp=%s rizo=%s outcome=%s wipeAt=%s ctlAt=%s",
      R.i, R.preIdle, R.lastIdle, R.promptDelay, R.pace,
      R.seed and string.format("%02X", R.seed) or "-", tostring(R.battleUp),
      tostring(R.rizo), R.outcome, tostring(R.wipeAt), tostring(R.ctlAt)))
  end
end)

H.run({ maxFrames = 40000 + PER_SHARD * (ATTEMPT_DEADLINE + 8000),
        allowGameOver = true }, steps)
