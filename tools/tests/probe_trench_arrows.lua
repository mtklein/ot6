-- probe_trench_arrows.lua -- read-only instrument for the Serpent Trench
-- ride.  Zero state writes: buttons and observation only.
--
-- show_arrows sets $E8 bits 1|2; the fork sample (world/move.asm) is
-- level-triggered on held pad cell $05 while the arrows are shown: right
-- pressed clears $1EB6 bit 7, left pressed sets it.  No edge, no confirm.
--
-- Boots gau_joined, walks to the dive (helmet scene -> jump), then rides
-- holding left, fleeing battles, tap-A otherwise, logging a transition
-- trace of every watched cell ($E8, $1EB6, $05, $E7/$1E, $00ED, $1F64,
-- $0026, $7BCA/$7BC2, $3BF4, CH_SEL/CH_MAX).  When $00ED freezes >600
-- frames, it holds 1200 more frames, presses one A, and logs which cell
-- responds; repeats up to 8 times.  PASS means the trace was captured, not
-- that Nikeah was reached.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/gau_joined.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local CH_SEL, CH_MAX = 0x056E, 0x056F
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end

-- one flat snapshot of every watched cell
local function snap()
  return {
    e8   = H.readByte(0xe8),
    b6   = H.readByte(0x1eb6),
    p05  = H.readByte(0x05),
    e7   = H.readByte(0xe7),
    i1e  = H.readByte(0x1e),
    ed   = H.readWord(0xed),
    map  = mapIdx(),
    zm   = H.readByte(0x0026),
    menu = H.readByte(0x7bca),
    mst  = H.readByte(0x7bc2),
    hp0  = H.readWord(0x3bf4),
    hp1  = H.readWord(0x3bf6),
    hp2  = H.readWord(0x3bf8),
    chs  = H.readByte(CH_SEL),
    chm  = H.readByte(CH_MAX),
  }
end
local function fmt(s)
  return string.format(
    "e8=%02X b6=%02X p05=%02X e7=%02X 1e=%02X ed=%04X map=%d zm=%02X " ..
    "menu=%02X mst=%02X hp=%04X/%04X/%04X ch=%d/%d",
    s.e8, s.b6, s.p05, s.e7, s.i1e, s.ed, s.map, s.zm, s.menu, s.mst,
    s.hp0, s.hp1, s.hp2, s.chs, s.chm)
end
-- cells worth a transition line (ed/p05/hp churn too fast; they ride
-- along in the printed snapshot instead)
local KEYS = { "e8", "b6", "e7", "i1e", "map", "zm", "menu", "mst",
               "chm" }

local last = nil
local traces = 0
local function trace(why, s)
  traces = traces + 1
  H.log(string.format("[arrows] f%d %s: %s", H.frame, why, fmt(s)))
end

-- --------------------------------- route to the dive -----------------
local function ride(dir, pred, what, budget)
  -- plain pre-dive driver: dialogs tap A, otherwise hold dir
  local phase = 0
  return H.driveUntil(pred, budget or 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      H.setPad(dir and { [dir] = true } or {})
    end),
  }, what)
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the world at Crescent's door")
  end),
  ride("up", function() return mapIdx() == 167 end, "into Crescent", 6000),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 4000, "Crescent live", 5),
  H.navTo(12, 23, { maxFrames = 8000, playBattles = "flee" }),
  (function()
    local sceneSeen = false
    return ride("up", function()
      if not H.hasControl() then sceneSeen = true end
      return sceneSeen and H.hasControl() and H.tileAligned()
         and mapIdx() == 167
    end, "the (12,22) beat", 15000)
  end)(),
  H.navTo(25, 18, { maxFrames = 12000, playBattles = "flee", arrive = function()
    return sw(0x41) == 1 or (H.fieldX() == 25 and H.fieldY() == 18
       and H.hasControl() and H.tileAligned()) end }),
  ride("up", function()
    return sw(0x41) == 1 and H.hasControl() and H.tileAligned()
  end, "helmet scene", 25000),

  -- ------------------------- the instrumented ride, original policy --
  (function()
    local phase, battN = 0, 0
    local edLast, edStill = nil, 0
    local frozenAt, aFired, aAt = nil, 0, nil
    local hb = -900
    return H.driveUntil(function()
      return mapIdx() == 187 or aFired >= 8
    end, 70000, {
      H.call(function()
        phase = (phase + 1) % 8
        local s = snap()
        -- transition trace on the slow-moving cells
        if last then
          for _, k in ipairs(KEYS) do
            if s[k] ~= last[k] then
              trace(string.format("%s %02X->%02X", k,
                last[k] or 255, s[k] or 255), s)
              break
            end
          end
        else
          trace("start", s)
        end
        last = s
        -- $00ED freeze bookkeeping
        if s.ed ~= edLast then
          if edStill > 600 then
            trace(string.format("ed UNFROZE after %d frames", edStill), s)
          end
          edLast, edStill, frozenAt = s.ed, 0, nil
        else
          edStill = edStill + 1
          if edStill == 601 then
            frozenAt = H.frame
            trace("ed FROZEN 600 frames", s)
          end
        end
        -- the A experiment: after 1200 clean frozen frames, one press
        if aAt and H.frame - aAt <= 120 then
          -- inside the observation window after an A: full snapshot
          -- every 12 frames so the answering transition is on record
          if (H.frame - aAt) % 12 == 0 then
            trace(string.format("post-A +%d", H.frame - aAt), s)
          end
        end
        if frozenAt and H.frame - frozenAt >= 1200
           and (aAt == nil or H.frame - aAt > 600) and aFired < 8 then
          aFired = aFired + 1
          aAt = H.frame
          trace(string.format("pressing ONE A (experiment %d)", aFired), s)
          H.setPad({ a = true })
          return
        end
        if aAt and H.frame - aAt < 8 then
          H.setPad({ a = true })          -- hold the press 8 frames
          return
        end
        -- original ride policy
        if H.frame - hb >= 900 then
          hb = H.frame
          trace("heartbeat", s)
        end
        if inBattle() or H.battleLoadStarted() then
          battN = battN + 1
          if battN < 900 and H.monstersPresent() > 0 then
            H.setPad({ l = true, r = true })
          else
            H.setPad(phase < 4 and { "a" } or {})
          end
          return
        end
        battN = 0
        H.setPad({ left = true })
      end),
    }, "instrumented trench ride")
  end)(),
  H.call(function()
    H.assertEq(traces >= 2, true, "the ride produced a transition trace")
    H.log(string.format("[arrows] DONE f%d map=%d traces=%d",
      H.frame, mapIdx(), traces))
  end),
})
