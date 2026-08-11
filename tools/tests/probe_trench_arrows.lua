-- probe_trench_arrows.lua -- READ-ONLY instrument for the Serpent Trench
-- ride (issue #75 follow-on; the sabin_done blocker).  Zero state writes:
-- buttons and eyes only.
--
-- WHY.  Five gen_sabin_trench driver permutations failed the ride five
-- ways (the record is in that file's ride() comment and commit dc07c44),
-- all reasoning about the show_arrows fork windows.  READING THE SOURCE
-- then showed the windows cannot be what freezes the ride:
--
--   * show_arrows (VehicleCmd_da, world/event.asm:589) just sets $E8
--     bits 1|2 and clears the flash counter; lock_arrows clears bit 2,
--     hide_arrows clears bit 1.  NON-BLOCKING -- the script pattern is
--     `show_arrows / wait 26 / lock_arrows / hide_arrows / if_switch
--     $01B7`, a TIMED input sample (event_main.asm:21212).
--   * The sample itself (world/move.asm:403-425) is LEVEL-triggered on
--     the HELD pad cell $05 every frame the arrows are shown: RIGHT
--     pressed -> $1EB6 &= $7F, LEFT pressed -> $1EB6 |= $80.  No edge,
--     no confirm, and it is skipped while $E7 bit0 or $1E bit0 says
--     player input is disabled.
--
--   So holding LEFT is the correct fork input, and the measured freeze
--   (ride parked at $ed=0200 from f9143 to a 60000-frame budget, b=false
--   by the gen's inBattle()) is some OTHER waiter -- one that a blanket
--   A-tap resolved, twice, while sending the ride down the $01B7=0
--   detour.  This probe's job is to NAME that waiter.
--
-- WHAT IT DOES.  Boots gau_joined, walks the gen's own route to the dive
-- (helmet scene -> jump), then rides with the ORIGINAL policy -- hold
-- LEFT, flee battles, tap-A stubborn ones -- while logging a transition
-- trace of every cell the mechanism touches:
--
--   $E8 (arrow show/lock bits + danger bits), $1EB6 (bit7 = the $01B7
--   fork switch), $05 (held-pad sample the arrows read), $E7/$1E (input
--   disable bits the sampler honors), $00ED (the ride's progress
--   signal), $1F64 (map), $0026 (field ZMENUSTATE), $7BCA/$7BC2 (battle
--   menu-open/menu-state), $3BF4 raw first words (what inBattle() sees),
--   and CH_SEL/CH_MAX ($056E/$056F).
--
-- When $00ED freezes >600 frames, it holds everything for 1200 more
-- frames of clean observation, then presses ONE A and logs which cells
-- transition in the next 120 frames -- the waiter is whatever answered.
-- It repeats that (freeze -> observe -> one A) up to 8 times, then ends.
-- PASS means "the trace was captured", not that Nikeah was reached; the
-- exit assertion is only that the ride left the helmet room and produced
-- at least one trace line.
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

-- --------------------------------- route to the dive (the gen's steps) --
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
